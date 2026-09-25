class_name SinCommand
extends RefCounted

var command_id: String
var expected_revision: int
var actor: String
var type: String
var payload: Dictionary

func _init(p_command_id: String = "", p_actor: String = "", p_type: String = "", p_payload: Dictionary = {}, p_expected_revision: int = -1) -> void:
	command_id = p_command_id
	actor = p_actor
	type = p_type
	payload = p_payload.duplicate(true)
	expected_revision = p_expected_revision

func fingerprint() -> String:
	return JSON.stringify({"actor": actor, "type": type, "payload": payload, "expected_revision": expected_revision}, "", false)

