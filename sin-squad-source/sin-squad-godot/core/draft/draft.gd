class_name SinDraft
extends RefCounted

var seed_value := 0
var counter := 0
var rng := RandomNumberGenerator.new()
var active_offer_id := ""
var offers: Dictionary = {}
var selected: Dictionary = {}
var archive: Array[Dictionary] = []
var character_offers: Dictionary = {}
var character_history: Dictionary = {}
var character_rerolls: Dictionary = {}
var character_selected: Dictionary = {}

func _init(p_seed: int = 1, p_counter: int = 0) -> void:
	seed_value = p_seed
	counter = p_counter
	rng.seed = seed_value
	for _i in range(counter):
		rng.randi()

func begin_batch(offer_id: String) -> void:
	active_offer_id = offer_id
	offers.clear()
	selected.clear()

func begin_character_batch(offer_id: String, pool: Array) -> Dictionary:
	active_offer_id = offer_id
	character_offers.clear()
	character_history.clear()
	character_rerolls.clear()
	character_selected.clear()
	var used: Dictionary = {}
	for side in ["player", "opponent"]:
		character_offers[side] = {}
		character_history[side] = {}
		character_rerolls[side] = {}
		character_selected[side] = {}
		for slot in [1, 2, 3]:
			var cards := _draw_character_cards(pool, used, 3)
			if cards.size() < 3: return {"accepted":false,"reason":"not_enough_character_candidates"}
			character_offers[side][str(slot)] = cards
			character_history[side][str(slot)] = [cards.duplicate(true)]
			character_rerolls[side][str(slot)] = false
	return {"accepted":true,"offer_id":active_offer_id,"offers":character_offers.duplicate(true)}

func reroll_character(side: String, slot: int, pool: Array) -> Dictionary:
	var key := str(slot)
	if not character_offers.has(side) or not character_offers[side].has(key): return {"accepted":false,"reason":"character_position_invalid"}
	if bool(character_rerolls[side].get(key, false)) or character_selected[side].has(key): return {"accepted":false,"reason":"character_reroll_already_used"}
	var used: Dictionary = {}
	for offer_side in character_offers:
		for offer_slot in character_offers[offer_side]:
			for card in character_offers[offer_side][offer_slot]: used[str(card)] = true
	for history_side in character_history:
		for history_slot in character_history[history_side]:
			for history_cards in character_history[history_side][history_slot]:
				for card in history_cards: used[str(card)] = true
	for selected_side in character_selected:
		for chosen in character_selected[selected_side].values(): used[str(chosen)] = true
	var cards := _draw_character_cards(pool, used, 3)
	if cards.size() < 3: return {"accepted":false,"reason":"not_enough_character_reroll_candidates"}
	character_rerolls[side][key] = true
	character_offers[side][key] = cards
	character_history[side][key].append(cards.duplicate(true))
	return {"accepted":true,"cards":cards.duplicate(true),"reroll_used":true}

func choose_character(side: String, slot: int, character_id: String) -> Dictionary:
	var key := str(slot)
	if not character_offers.has(side) or not character_offers[side].has(key): return {"accepted":false,"reason":"character_position_invalid"}
	if character_selected[side].has(key): return {"accepted":false,"reason":"character_position_already_selected"}
	if not character_offers[side][key].has(character_id): return {"accepted":false,"reason":"character_not_in_offer"}
	character_selected[side][key] = character_id
	return {"accepted":true,"slot":slot,"character_id":character_id}

func character_complete(side: String) -> bool:
	return character_selected.get(side, {}).size() == 3

func _draw_character_cards(pool: Array, used: Dictionary, count: int) -> Array:
	var available: Array = []
	for item in pool:
		var id := str(item.get("id", "")) if item is Dictionary else str(item)
		if not id.is_empty() and not used.has(id): available.append(id)
	for i in range(available.size() - 1, 0, -1):
		var j := _random_index(i + 1)
		var temp = available[i]; available[i] = available[j]; available[j] = temp
	var result := available.slice(0, count)
	for id in result: used[id] = true
	return result

func draw(side: String, pool: Array, size: int = 3) -> Dictionary:
	if offers.has(side):
		return {"accepted": true, "duplicate": true, "offer_id": active_offer_id, "cards": offers[side].duplicate(true)}
	if side not in ["player", "opponent"] or size < 1:
		return {"accepted": false, "reason": "invalid_pool_or_size", "cards": []}
	var available: Array = []
	var unique: Dictionary = {}
	for item: Variant in pool:
		var card_id := str(item.get("id", "")) if item is Dictionary else str(item)
		if not card_id.is_empty() and not unique.has(card_id):
			unique[card_id] = true
			available.append(item)
	if available.size() < size:
		return {"accepted": false, "reason": "not_enough_unique_cards", "cards": []}
	for index in range(available.size() - 1, 0, -1):
		var swap_index := _random_index(index + 1)
		var temp: Variant = available[index]
		available[index] = available[swap_index]
		available[swap_index] = temp
	var result: Array = available.slice(0, size)
	offers[side] = result.duplicate(true)
	return {"accepted": true, "duplicate": false, "offer_id": active_offer_id, "cards": result.duplicate(true)}

func choose(side: String, card_id: String, slot: int, slot_kind: String) -> Dictionary:
	if selected.has(side):
		return {"accepted": true, "duplicate": true, "selected": selected[side].duplicate(true)}
	if not offers.has(side) or slot < 1 or slot > 3:
		return {"accepted": false, "reason": "no_offer_or_bad_slot"}
	var found := false
	for card: Variant in offers[side]:
		if (str(card.get("id", "")) if card is Dictionary else str(card)) == card_id:
			found = true
			break
	if not found:
		return {"accepted": false, "reason": "card_not_in_private_offer"}
	if slot_kind not in ["equipment", "effect"]:
		return {"accepted": false, "reason": "invalid_slot_kind"}
	selected[side] = {"card_id": card_id, "slot": slot, "slot_kind": slot_kind, "offer_id": active_offer_id}
	return {"accepted": true, "duplicate": false, "selected": selected[side].duplicate(true)}

func snapshot() -> Dictionary:
	return {"seed": seed_value, "counter": counter, "rng_state": rng.state, "active_offer_id": active_offer_id,
		"offers": offers.duplicate(true), "selected": selected.duplicate(true), "archive": archive.duplicate(true),
		"character_offers": character_offers.duplicate(true), "character_history": character_history.duplicate(true),
		"character_rerolls": character_rerolls.duplicate(true), "character_selected": character_selected.duplicate(true)}

func restore(data: Dictionary) -> bool:
	if not data.has("seed") or not data.has("counter") or not data.has("rng_state") or not data.get("offers", null) is Dictionary or not data.get("selected", null) is Dictionary or not data.get("archive", null) is Array:
		return false
	var replacement := RandomNumberGenerator.new()
	replacement.seed = int(data.seed)
	replacement.state = int(data.rng_state)
	seed_value = int(data.seed)
	counter = int(data.counter)
	rng = replacement
	active_offer_id = str(data.get("active_offer_id", ""))
	offers = data.offers.duplicate(true)
	selected = data.selected.duplicate(true)
	archive.assign(data.archive)
	character_offers = data.get("character_offers", {}).duplicate(true)
	character_history = data.get("character_history", {}).duplicate(true)
	character_rerolls = data.get("character_rerolls", {}).duplicate(true)
	character_selected = data.get("character_selected", {}).duplicate(true)
	return true

func archive_batch() -> void:
	if not active_offer_id.is_empty():
		archive.append({"offer_id": active_offer_id, "offers": offers.duplicate(true), "selected": selected.duplicate(true)})
	active_offer_id = ""
	offers.clear()
	selected.clear()

func _random_index(limit: int) -> int:
	var result := rng.randi_range(0, limit - 1)
	counter += 1
	return result
