extends SceneTree

const AttachmentCatalogScript = preload("res://content/attachments/attachment_catalog.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/attachments/attachments.json"))
	var original: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/source-catalog/catalog.json"))
	if not document is Dictionary or not original is Dictionary:
		_fail("attachment or original catalog JSON cannot be read")
		return
	var source_path := ProjectSettings.globalize_path("res://../sin-squad-design/02-装备与槽位.md")
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK or hashing.update(source_bytes) != OK:
		_fail("cannot hash original attachment source")
		return
	var actual_hash := hashing.finish().hex_encode().to_upper()
	if actual_hash != str(document.source.sha256):
		_fail("attachment source hash differs from the original design file")
		return
	var original_by_id := {}
	for item: Dictionary in original.entries:
		original_by_id[str(item.id)] = item
	var seen := {}
	var checks := 1
	for card: Dictionary in document.get("attachments", []):
		var card_id := str(card.get("id", ""))
		if seen.has(card_id):
			_fail("duplicate ID: " + card_id)
			return
		seen[card_id] = true
		if not original_by_id.has(card_id):
			_fail("source catalog is missing " + card_id)
			return
		var source_text := str(original_by_id[card_id].text)
		if str(card.get("source_text", "")) != source_text:
			_fail("source text differs from locked catalog: " + card_id)
			return
		for key: String in ["effect", "adaptation", "tradeoff"]:
			var prefix: String = {"effect":"效果：", "adaptation":"适配：", "tradeoff":"取舍："}[key]
			var found := false
			for line: String in source_text.split("\n"):
				if line.begins_with(prefix) and str(card.get(key, "")) == line.trim_prefix(prefix):
					found = true
					break
			if not found:
				_fail("structured source field differs for %s/%s" % [card_id, key])
				return
		checks += 4
	if seen.size() != 100 or int(document.get("count", 0)) != 100:
		_fail("expected exactly 100 unique attachments")
		return
	var event_target_scope_ids: Array[String] = []
	for card: Dictionary in document.attachments:
		if str(card.get("trigger_scope", "root")) == "event_target": event_target_scope_ids.append(str(card.id))
	_check(event_target_scope_ids == ["FX43"], "only printed per-recipient FX43 opts into event-target root guarding")
	checks += 1
	for static_id: String in ["EQ01", "EQ02", "EQ03", "EQ04", "EQ10", "EQ12", "EQ13", "EQ24", "EQ26", "EQ39"]:
		var card: Dictionary = document.attachments.filter(func(item: Dictionary) -> bool: return item.id == static_id)[0]
		for modifier: Dictionary in card.get("initial_modifiers", []):
			if str(modifier.get("phase", "")) != "pre_battle_setup":
				_fail("initial panel change is deferred into combat for " + static_id)
				return
		checks += 1
	var base_unit := {"H":100,"A":10,"T_ticks":20,"R":2,"hp_tenths":1000,"reach":"melee"}
	var eq01: Dictionary = AttachmentCatalogScript.apply_setup_modifiers(base_unit, "EQ01")
	var eq02: Dictionary = AttachmentCatalogScript.apply_setup_modifiers(base_unit, "EQ02")
	var eq03: Dictionary = AttachmentCatalogScript.apply_setup_modifiers(base_unit, "EQ03")
	var eq04: Dictionary = AttachmentCatalogScript.apply_setup_modifiers(base_unit, "EQ04")
	var eq12: Dictionary = AttachmentCatalogScript.apply_setup_modifiers(base_unit, "EQ12")
	var eq13: Dictionary = AttachmentCatalogScript.apply_setup_modifiers(base_unit, "EQ13")
	var eq24: Dictionary = AttachmentCatalogScript.apply_setup_modifiers(base_unit, "EQ24")
	var eq26: Dictionary = AttachmentCatalogScript.apply_setup_modifiers(base_unit, "EQ26")
	var eq39: Dictionary = AttachmentCatalogScript.apply_setup_modifiers(base_unit, "EQ39")
	var eq10: Dictionary = AttachmentCatalogScript.apply_setup_modifiers(base_unit, "EQ10")
	_check(AttachmentCatalogScript.sin_for_definition_id("WR01") == "愤怒" and AttachmentCatalogScript.sin_for_definition_id("GR01") == "贪婪", "soft affinity reads existing character sin tags only")
	_check(eq01.accepted and eq01.unit.A == 10 and eq01.unit.setup_modifiers.any(func(item: Dictionary) -> bool: return item.stat == "A_flat" and item.amount == 3), "EQ01 setup remains an explicit engine modifier over the naked panel")
	_check(eq02.unit.H == 100 and eq02.unit.setup_modifiers.any(func(item: Dictionary) -> bool: return item.stat == "H_flat" and item.amount == 18), "EQ02 setup does not overwrite base H before engine setup")
	_check(eq03.unit.T_ticks == 20 and eq03.unit.setup_modifiers.any(func(item: Dictionary) -> bool: return item.stat == "T_ticks_flat" and item.amount == -2) and eq04.unit.setup_modifiers.any(func(item: Dictionary) -> bool: return item.stat == "R_flat" and item.amount == 3), "EQ03/EQ04 setup remains explicit for base-panel adjudication")
	_check(eq12.unit.H == 100 and eq12.unit.setup_modifiers.any(func(item: Dictionary) -> bool: return item.stat == "H_flat" and item.amount == -12 and item.minimum == 1 and item.current_hp_minimum == 1 and item.also_current_hp), "EQ12 setup carries both printed one-life floors and synchronized HP metadata")
	_check(eq12.unit.setup_modifiers.any(func(item: Dictionary) -> bool: return item.stat == "flying" and item.value), "EQ12 setup carries flight as a pre-battle tag without generating combat damage")
	_check(eq13.unit.reach == "melee" and eq13.unit.setup_modifiers.any(func(item: Dictionary) -> bool: return item.stat == "reach" and item.value == "ranged") and eq24.unit.T_ticks == 20 and eq10.unit.setup_modifiers.any(func(item: Dictionary) -> bool: return item.stat == "T_ticks_flat" and item.amount == 2), "EQ10/EQ13/EQ24 setup keeps source unit values untouched")
	_check(eq26.unit.T_ticks == 20 and eq26.unit.setup_modifiers.any(func(item: Dictionary) -> bool: return item.stat == "natural_damage_bp" and item.amount == 4500), "EQ26 setup records only a natural-attack modifier, not attached damage")
	_check(eq39.unit.A == 10 and eq39.unit.setup_modifiers.any(func(item: Dictionary) -> bool: return item.stat == "A_flat" and item.amount == -1), "EQ39 setup keeps the unmodified base attack for rules")
	checks += 9
	print("ATTACHMENT_DATA_TESTS_PASSED checks=%d cards=%d" % [checks, seen.size()])
	quit(0)

func _check(condition: bool, description: String) -> void:
	if not condition:
		_fail(description)
		return
	

func _fail(message: String) -> void:
	printerr("ATTACHMENT_DATA_TESTS_FAILED " + message)
	quit(1)
