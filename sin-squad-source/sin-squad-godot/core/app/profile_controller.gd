class_name SinProfileController
extends RefCounted

const SessionScript = preload("res://core/session/session.gd")
const AppControllerScript = preload("res://core/app/app_controller.gd")
const SaveStoreScript = preload("res://core/save/save_store.gd")

var save_store: SinSaveStore
var app_controller: SinAppController
var profile: Dictionary = {}
var profile_slot := "default"
var integration_review := false
var profile_initialized := false


func _init(p_store: SinSaveStore = null, p_integration_review: bool = false) -> void:
	save_store = p_store if p_store != null else SaveStoreScript.new()
	integration_review = p_integration_review
	profile = _default_profile()


func create_new_profile(slot: String = "default") -> Dictionary:
	if not _valid_slot(slot): return _error("invalid_profile_slot")
	if profile_initialized: return _error("profile_already_initialized")
	var existing: Dictionary = save_store.load_profile(slot)
	if str(existing.get("error", "")).is_empty(): return _error("profile_already_exists")
	if not str(existing.get("error", "")).begins_with("save_not_found_or_unreadable:"): return existing
	profile_slot = slot
	profile = _default_profile()
	app_controller = null
	var saved := save_profile()
	if not str(saved.get("error", "")).is_empty():
		return saved
	profile_initialized = true
	return {"error":"","accepted":true,"profile":profile_snapshot()}


func load_profile(slot: String = "default") -> Dictionary:
	var loaded: Dictionary = save_store.load_profile(slot)
	if not str(loaded.get("error", "")).is_empty(): return loaded
	profile_slot = slot
	profile = loaded.profile.duplicate(true)
	profile_initialized = true
	app_controller = null
	if loaded.get("active_session", null) is SinSession:
		app_controller = AppControllerScript.new(loaded.active_session, null, integration_review)
	return {"error":"","accepted":true,"profile":profile_snapshot(),"recovered_from_backup":bool(loaded.get("recovered_from_backup", false))}


func profile_snapshot() -> Dictionary:
	var result := profile.duplicate(true)
	result["active_session_snapshot"] = app_controller.session.snapshot() if app_controller != null else null
	return result


func save_profile() -> Dictionary:
	if app_controller != null:
		profile["active_session_snapshot"] = app_controller.session.snapshot()
	return save_store.commit_profile(profile_snapshot(), profile_slot)


## Buy-in is debited once from the Profile. The new Session receives zero player-wallet
## chips and exactly the selected table stack, so recreating/continuing it cannot mint funds.
func enter_room(buy_in: Variant, room_options: Dictionary = {}) -> Dictionary:
	if not profile_initialized: return _error("profile_not_initialized")
	if app_controller != null: return _error("profile_already_in_room")
	if not buy_in is int and not buy_in is String: return _error("buy_in_choice_invalid")
	var all_in: bool = buy_in is String and buy_in == "all"
	var amount := int(profile.wallet) if all_in else int(buy_in)
	if not all_in and amount not in [100, 200, 500]: return _error("buy_in_choice_invalid")
	if amount < 10 or amount > int(profile.wallet): return _error("buy_in_unaffordable")
	var original := profile.duplicate(true)
	profile.wallet = int(profile.wallet) - amount
	var options := room_options.duplicate(true)
	for protected_key in ["player_wallet", "player_table", "opponent_table", "opponent_funds", "ante"]:
		options.erase(protected_key)
	options["player_wallet"] = 0
	options["player_table"] = amount
	options["opponent_table"] = amount
	options["opponent_funds"] = 0
	options["ante"] = int(room_options.get("ante", 5))
	options["team_draft"] = bool(room_options.get("team_draft", true))
	var session = SessionScript.new(options)
	app_controller = AppControllerScript.new(session, null, integration_review)
	profile["active_session_snapshot"] = session.snapshot()
	var saved := save_profile()
	if not str(saved.get("error", "")).is_empty():
		profile = original
		app_controller = null
		return saved
	var initial_side := "player" if session.state.phase == "TEAM_SELECTION" else str(session.state.acting_side)
	return {"error":"","accepted":true,"buy_in":amount,"profile_wallet":profile.wallet,
		"session":app_controller.observation("player"),"legal_actions":app_controller.legal_actions(initial_side)}


func legal_actions(side: String) -> Array[Dictionary]:
	return [] if app_controller == null else app_controller.legal_actions(side)


func observation(side: String) -> Dictionary:
	return {} if app_controller == null else app_controller.observation(side)


func submit(command: SinCommand) -> Dictionary:
	if app_controller == null: return _error("profile_not_in_room")
	# Leave is a Profile-level transfer: never let a generic LegalActions command
	# mark the Session departed while leaving its remaining wallet stranded here.
	if command != null and command.actor == "player" and command.type == "leave_table":
		return leave_room(command.command_id)
	var result: Dictionary = app_controller.submit(command)
	if bool(result.get("accepted", false)):
		profile["active_session_snapshot"] = app_controller.session.snapshot()
		var saved := save_profile()
		if not str(saved.get("error", "")).is_empty(): result["persistence_error"] = str(saved.error)
	return result


## Rebuild a battle replay after loading a BATTLE_READY save. Battle simulation is
## deterministic and read-only with respect to Session/RNG/economy; settlement remains
## gated behind finish_battle_replay, exactly as for a live replay.
func resume_pending_battle() -> Dictionary:
	if app_controller == null: return _error("profile_not_in_room")
	if app_controller.pending_battle_replay:
		return app_controller.pending_battle_replay_package()
	if app_controller.session == null or app_controller.session.state.phase != "BATTLE_READY":
		return _error("battle_not_ready")
	return app_controller.resolve_battle()


func finish_battle_replay(consumed_event_count: int) -> Dictionary:
	if app_controller == null: return _error("profile_not_in_room")
	var result: Dictionary = app_controller.finish_battle_replay(consumed_event_count)
	if bool(result.get("accepted", false)):
		profile["active_session_snapshot"] = app_controller.session.snapshot()
		var saved := save_profile()
		if not str(saved.get("error", "")).is_empty(): result["persistence_error"] = str(saved.error)
	return result


func leave_room(command_id: String) -> Dictionary:
	if app_controller == null: return _error("profile_not_in_room")
	var session: SinSession = app_controller.session
	var command := SinCommand.new(command_id, "player", "leave_table", {}, int(session.state.revision))
	var result: Dictionary = app_controller.submit(command)
	if not bool(result.get("accepted", false)): return result
	if int(session.ledger.balances.player_table) != 0 or int(session.ledger.balances.player_wallet) < 0:
		return _error("profile_return_invariant_failed")
	var returned := int(session.ledger.balances.player_wallet)
	profile.wallet = int(profile.wallet) + returned
	profile["active_session_snapshot"] = null
	app_controller = null
	var saved := save_profile()
	if not str(saved.get("error", "")).is_empty(): result["persistence_error"] = str(saved.error)
	result["wallet"] = profile.wallet
	result["returned_from_table"] = returned
	return result


func save_tutorial_progress(progress: Dictionary, completed: bool = false) -> Dictionary:
	if not profile_initialized: return _error("profile_not_initialized")
	var tutorial_saved: Dictionary = save_store.commit_tutorial_progress(progress, profile_slot)
	if not str(tutorial_saved.get("error", "")).is_empty(): return tutorial_saved
	profile.tutorial_progress = progress.duplicate(true)
	profile.tutorial_completed = completed
	var profile_saved := save_profile()
	if not str(profile_saved.get("error", "")).is_empty():
		return {"error":"profile_progress_save_failed:" + str(profile_saved.error),"tutorial_saved":true}
	return {"error":"","saved":true,"tutorial_completed":completed}


func _default_profile() -> Dictionary:
	return {"wallet":1000,"tutorial_completed":false,"settings":{},"tutorial_progress":{},"active_session_snapshot":null}


func _valid_slot(slot: String) -> bool:
	if slot.is_empty() or slot.length() > 32: return false
	var regex := RegEx.new()
	if regex.compile("^[A-Za-z0-9_-]+$") != OK: return false
	return regex.search(slot) != null


func _error(message: String) -> Dictionary:
	return {"error":message,"accepted":false}
