## Sparse, versioned structure asset shared by the studio and world generator.
class_name StructureTemplateData
extends RefCounted


const FORMAT: String = "trumancraft_structure"
const VERSION: int = 1
const MAX_SIZE: int = 64


var structure_id: String = "unnamed"
var display_name: String = "Estrutura sem nome"
var size: Vector3i = Vector3i.ONE
var pivot: Vector3i = Vector3i.ZERO
var blocks: Dictionary = {} # Vector3i -> stable block name
var explicit_air: Dictionary = {} # Vector3i -> true
var metadata: Dictionary = {} # Vector3i -> Dictionary
var markers: Array = []
var source_path: String = ""


func validate(block_definitions: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	if structure_id.strip_edges() == "":
		errors.append("structure_id obrigatorio.")
	if size.x <= 0 or size.y <= 0 or size.z <= 0 or size.x > MAX_SIZE or size.y > MAX_SIZE or size.z > MAX_SIZE:
		errors.append("Dimensoes devem estar entre 1 e 64.")
	if not is_inside(pivot):
		errors.append("Pivot deve estar dentro da estrutura.")
	for raw_pos in blocks.keys():
		if not (raw_pos is Vector3i) or not is_inside(raw_pos as Vector3i):
			errors.append("Bloco fora dos limites.")
			break
		var block_id: String = str(blocks[raw_pos])
		if block_id == "" or (not block_definitions.is_empty() and not block_definitions.has(block_id)):
			errors.append("Bloco desconhecido: %s" % block_id)
			break
	for raw_pos in explicit_air.keys():
		if not (raw_pos is Vector3i) or not is_inside(raw_pos as Vector3i):
			errors.append("Celula de ar explicito fora dos limites.")
			break
		if blocks.has(raw_pos):
			errors.append("Uma celula nao pode conter bloco e ar explicito.")
			break
	for raw_pos in metadata.keys():
		if not (raw_pos is Vector3i) or not is_inside(raw_pos as Vector3i) or typeof(metadata[raw_pos]) != TYPE_DICTIONARY:
			errors.append("Metadado stateful invalido ou fora dos limites.")
			break
		if not blocks.has(raw_pos):
			errors.append("Metadado stateful precisa pertencer a um bloco.")
			break
	for raw_marker in markers:
		if typeof(raw_marker) != TYPE_DICTIONARY:
			errors.append("Marcador invalido.")
			continue
		var marker: Dictionary = raw_marker as Dictionary
		var marker_pos: Vector3i = _vector3i_from_value(marker.get("pos", []))
		var marker_type: String = str(marker.get("type", ""))
		if not is_inside(marker_pos) or marker_type not in ["foundation", "connector", "anchor", "entity_spawn"]:
			errors.append("Marcador sem tipo ou fora dos limites.")
		elif marker_type == "entity_spawn" and str(marker.get("entity_id", "")) == "":
			errors.append("Marcador entity_spawn sem entity_id.")
	return errors


func is_inside(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < size.x and pos.y >= 0 and pos.y < size.y and pos.z >= 0 and pos.z < size.z


func to_dictionary() -> Dictionary:
	var block_rows: Array = []
	var positions: Array = blocks.keys()
	positions.sort_custom(_sort_vector3i)
	for raw_pos in positions:
		var pos: Vector3i = raw_pos
		block_rows.append([pos.x, pos.y, pos.z, str(blocks[pos])])
	var air_rows: Array = []
	positions = explicit_air.keys()
	positions.sort_custom(_sort_vector3i)
	for raw_pos in positions:
		var pos: Vector3i = raw_pos
		air_rows.append([pos.x, pos.y, pos.z])
	var metadata_rows: Array = []
	positions = metadata.keys()
	positions.sort_custom(_sort_vector3i)
	for raw_pos in positions:
		var pos: Vector3i = raw_pos
		metadata_rows.append([pos.x, pos.y, pos.z, metadata[pos]])
	return {
		"format": FORMAT,
		"version": VERSION,
		"id": structure_id,
		"name": display_name,
		"size": [size.x, size.y, size.z],
		"pivot": [pivot.x, pivot.y, pivot.z],
		"blocks": block_rows,
		"explicit_air": air_rows,
		"metadata": metadata_rows,
		"markers": markers,
	}


static func from_dictionary(data: Dictionary):
	if str(data.get("format", "")) != FORMAT or int(data.get("version", 0)) != VERSION:
		return null
	var template = (load("res://src/structure_template_data.gd") as Script).new()
	template.structure_id = str(data.get("id", "unnamed"))
	template.display_name = str(data.get("name", template.structure_id))
	template.size = _vector3i_from_value(data.get("size", [1, 1, 1]), Vector3i.ONE)
	template.pivot = _vector3i_from_value(data.get("pivot", [0, 0, 0]))
	var raw_blocks: Variant = data.get("blocks", [])
	if typeof(raw_blocks) == TYPE_ARRAY:
		for raw_row in raw_blocks as Array:
			if typeof(raw_row) != TYPE_ARRAY or (raw_row as Array).size() < 4:
				continue
			var row: Array = raw_row as Array
			template.blocks[Vector3i(int(row[0]), int(row[1]), int(row[2]))] = str(row[3])
	var raw_air: Variant = data.get("explicit_air", [])
	if typeof(raw_air) == TYPE_ARRAY:
		for raw_row in raw_air as Array:
			if typeof(raw_row) == TYPE_ARRAY and (raw_row as Array).size() >= 3:
				var row: Array = raw_row as Array
				template.explicit_air[Vector3i(int(row[0]), int(row[1]), int(row[2]))] = true
	var raw_metadata: Variant = data.get("metadata", [])
	if typeof(raw_metadata) == TYPE_ARRAY:
		for raw_row in raw_metadata as Array:
			if typeof(raw_row) == TYPE_ARRAY and (raw_row as Array).size() >= 4 and typeof(raw_row[3]) == TYPE_DICTIONARY:
				var row: Array = raw_row as Array
				template.metadata[Vector3i(int(row[0]), int(row[1]), int(row[2]))] = (row[3] as Dictionary).duplicate(true)
	template.markers = (data.get("markers", []) as Array).duplicate(true)
	return template


static func load_from_file(path: String):
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var template = from_dictionary(parsed as Dictionary)
	if template != null:
		template.source_path = path
	return template


func save_to_file(path: String, block_definitions: Dictionary = {}) -> Error:
	var errors: Array[String] = validate(block_definitions)
	if not errors.is_empty():
		push_error("StructureTemplate invalido: %s" % "; ".join(errors))
		return ERR_INVALID_DATA
	var temporary_path: String = "%s.tmp" % path
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dictionary(), "\t"))
	file.close()
	var absolute_target: String = ProjectSettings.globalize_path(path)
	var absolute_temporary: String = ProjectSettings.globalize_path(temporary_path)
	var backup_path: String = "%s.bak" % path
	var absolute_backup: String = ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	var had_target: bool = FileAccess.file_exists(path)
	if had_target:
		var backup_error: Error = DirAccess.rename_absolute(absolute_target, absolute_backup)
		if backup_error != OK:
			DirAccess.remove_absolute(absolute_temporary)
			return backup_error
	var rename_error: Error = DirAccess.rename_absolute(absolute_temporary, absolute_target)
	if rename_error != OK:
		if had_target:
			DirAccess.rename_absolute(absolute_backup, absolute_target)
		if FileAccess.file_exists(temporary_path):
			DirAccess.remove_absolute(absolute_temporary)
		return rename_error
	if had_target and FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	source_path = path
	return rename_error


func content_hash() -> String:
	return JSON.stringify(to_dictionary()).sha256_text()


func transformed_size(rotation_quarters: int) -> Vector3i:
	var rotation: int = posmod(rotation_quarters, 4)
	return Vector3i(size.z, size.y, size.x) if rotation == 1 or rotation == 3 else size


func transform_position(pos: Vector3i, rotation_quarters: int, mirror_x: bool = false, mirror_z: bool = false) -> Vector3i:
	var transformed: Vector3i = pos
	if mirror_x:
		transformed.x = size.x - 1 - transformed.x
	if mirror_z:
		transformed.z = size.z - 1 - transformed.z
	match posmod(rotation_quarters, 4):
		1:
			return Vector3i(size.z - 1 - transformed.z, transformed.y, transformed.x)
		2:
			return Vector3i(size.x - 1 - transformed.x, transformed.y, size.z - 1 - transformed.z)
		3:
			return Vector3i(transformed.z, transformed.y, size.x - 1 - transformed.x)
	return transformed


static func _vector3i_from_value(raw_value: Variant, fallback: Vector3i = Vector3i.ZERO) -> Vector3i:
	if raw_value is Vector3i:
		return raw_value as Vector3i
	if typeof(raw_value) != TYPE_ARRAY or (raw_value as Array).size() < 3:
		return fallback
	var values: Array = raw_value as Array
	return Vector3i(int(values[0]), int(values[1]), int(values[2]))


static func _sort_vector3i(a: Variant, b: Variant) -> bool:
	var left: Vector3i = a
	var right: Vector3i = b
	if left.y != right.y:
		return left.y < right.y
	if left.z != right.z:
		return left.z < right.z
	return left.x < right.x
