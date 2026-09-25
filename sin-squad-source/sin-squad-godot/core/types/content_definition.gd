class_name ContentDefinition
extends RefCounted

var id := ""
var name := ""
var category := ""
var source := ""
var source_text := ""
var logic_handler := ""
var handler_status := "not_implemented"
var presentation_id := ""
var schema_version := 1
var fields: Dictionary = {}

static func from_dict(data: Dictionary) -> ContentDefinition:
	var definition := ContentDefinition.new()
	definition.id = str(data.get("id", ""))
	definition.name = str(data.get("name", ""))
	definition.category = str(data.get("category", ""))
	definition.source = str(data.get("source", ""))
	definition.source_text = str(data.get("source_text", ""))
	definition.logic_handler = str(data.get("logic_handler", ""))
	definition.handler_status = str(data.get("handler_status", "not_implemented"))
	definition.presentation_id = str(data.get("presentation_id", ""))
	definition.schema_version = int(data.get("schema_version", 1))
	definition.fields = data.get("fields", {}).duplicate(true)
	return definition

func to_dict() -> Dictionary:
	return {"id": id, "name": name, "category": category, "source": source, "source_text": source_text,
		"logic_handler": logic_handler, "handler_status": handler_status, "presentation_id": presentation_id,
		"schema_version": schema_version, "fields": fields.duplicate(true)}

