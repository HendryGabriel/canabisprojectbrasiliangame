class_name StructureRegistry
extends RefCounted


const FORMAT: String = "trumancraft_structure_registry"
const VERSION: int = 1


var entries: Dictionary = {} # template id -> normalized rule
var source_path: String = ""


static func empty_registry():
	return (load("res://src/structure_registry.gd") as Script).new()


static func load_from_file(path: String):
	if not FileAccess.file_exists(path):
		return empty_registry()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = parsed as Dictionary
	if str(data.get("format", "")) != FORMAT or int(data.get("version", 0)) != VERSION:
		return null
	var registry = (load("res://src/structure_registry.gd") as Script).new()
	registry.source_path = path
	var raw_entries: Variant = data.get("entries", [])
	if typeof(raw_entries) == TYPE_ARRAY:
		for raw_entry in raw_entries as Array:
			if typeof(raw_entry) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = _normalized_rule(raw_entry as Dictionary)
			var template_id: String = str(entry.get("id", ""))
			if template_id != "":
				registry.entries[template_id] = entry
	return registry


func get_rule(template_id: String) -> Dictionary:
	return (entries.get(template_id, {}) as Dictionary).duplicate(true)


func get_rules() -> Array:
	return entries.values()


func validate() -> Array[String]:
	var errors: Array[String] = []
	for template_id in entries.keys():
		var rule: Dictionary = entries[template_id] as Dictionary
		if str(rule.get("path", "")) == "":
			errors.append("Template %s sem path." % template_id)
		if str(rule.get("mode", "")) not in ["surface_adaptive", "cave_floor", "underground"]:
			errors.append("Template %s com modo invalido." % template_id)
	return errors


func content_hash() -> String:
	var rows: Array = []
	var ids: Array = entries.keys()
	ids.sort()
	for template_id in ids:
		rows.append(entries[template_id])
	return JSON.stringify({"format": FORMAT, "version": VERSION, "entries": rows}).sha256_text()


static func _normalized_rule(raw: Dictionary) -> Dictionary:
	var rotations: Array = raw.get("rotations", [0, 1, 2, 3]) as Array
	var normalized_rotations: Array[int] = []
	for value in rotations:
		var rotation: int = posmod(int(value), 4)
		if not normalized_rotations.has(rotation):
			normalized_rotations.append(rotation)
	return {
		"id": str(raw.get("id", "")),
		"path": str(raw.get("path", "")),
		"mode": str(raw.get("mode", "surface_adaptive")),
		"zone_mask": int(raw.get("zone_mask", 1)),
		"weight": clampf(float(raw.get("weight", 0.0)), 0.0, 1.0),
		"spacing": maxi(4, int(raw.get("spacing", 24))),
		"rotations": normalized_rotations,
		"allow_mirror_x": bool(raw.get("allow_mirror_x", false)),
		"allow_mirror_z": bool(raw.get("allow_mirror_z", false)),
		"max_slope": maxi(0, int(raw.get("max_slope", 8))),
		"max_support_depth": maxi(0, int(raw.get("max_support_depth", 24))),
		"min_depth": maxi(4, int(raw.get("min_depth", 12))),
		"max_depth": maxi(5, int(raw.get("max_depth", 42))),
		"minimum_cover": maxi(1, int(raw.get("minimum_cover", 4))),
	}
