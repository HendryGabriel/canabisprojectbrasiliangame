## Compact 64-cubed voxel volume used only by the in-game Structure Studio.
class_name StructureWorkspace
extends RefCounted


const VoxelWorldScript = preload("res://src/voxel_world.gd")
const VoxelHitScript = preload("res://src/voxel_hit.gd")
const StructureTemplateScript = preload("res://src/structure_template_data.gd")
const MicroCellScript = preload("res://src/micro_cell_data.gd")

const SIZE: int = 64
const VOLUME: int = SIZE * SIZE * SIZE
const SECTION_SIZE: int = 16
const PADDED_SECTION_SIZE: int = 18
const SECTION_COUNT: int = 4


var _voxels: PackedByteArray = PackedByteArray()
var _palette_source
var _render_palette: Dictionary = {}
var _section_counts: Dictionary = {}
var _section_revisions: Dictionary = {}
var _metadata: Dictionary = {}
var _micro_cells: Dictionary = {} # linear index -> MicroCellData
var explicit_air: Dictionary = {}
var markers: Array = []
var components: Array = [] # world-space editor references
var pivot: Vector3i = Vector3i.ZERO


func _init(block_definitions: Dictionary = {}) -> void:
	_voxels.resize(VOLUME)
	_voxels.fill(0)
	_palette_source = VoxelWorldScript.new(block_definitions)
	_render_palette = _palette_source.get_render_palette()


func configure_texture_layers(layer_by_path: Dictionary) -> void:
	_palette_source.configure_texture_layers(layer_by_path)
	_render_palette = _palette_source.get_render_palette()


func reset() -> void:
	_voxels.fill(0)
	_section_counts.clear()
	_section_revisions.clear()
	_metadata.clear()
	_micro_cells.clear()
	explicit_air.clear()
	markers.clear()
	components.clear()
	pivot = Vector3i.ZERO


func is_inside_world(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < SIZE and pos.y >= 0 and pos.y < SIZE and pos.z >= 0 and pos.z < SIZE


func get_linear_index(pos: Vector3i) -> int:
	return (pos.y * SIZE + pos.z) * SIZE + pos.x if is_inside_world(pos) else -1


func get_block_palette_id(pos: Vector3i) -> int:
	var index: int = get_linear_index(pos)
	return int(_voxels[index]) if index >= 0 else 0


func get_block_id(pos: Vector3i) -> String:
	return _palette_source.get_palette_name(get_block_palette_id(pos))


func has_block(pos: Vector3i) -> bool:
	return get_block_palette_id(pos) != 0 or has_micro_cell(pos)


func set_block(pos: Vector3i, block_id: String) -> bool:
	var palette_id: int = _palette_source.get_palette_id_for_name(block_id)
	if not is_inside_world(pos) or palette_id == 0:
		return false
	var changed: bool = _set_palette_id(pos, palette_id)
	if _micro_cells.erase(get_linear_index(pos)):
		_touch_position(pos)
		changed = true
	return changed


func clear_block(pos: Vector3i) -> bool:
	if not is_inside_world(pos) or (get_block_palette_id(pos) == 0 and not has_micro_cell(pos)):
		return false
	if get_block_palette_id(pos) != 0:
		_set_palette_id(pos, 0)
	if _micro_cells.erase(get_linear_index(pos)):
		_touch_position(pos)
	_metadata.erase(get_linear_index(pos))
	return true


func has_micro_cell(pos: Vector3i) -> bool:
	var index: int = get_linear_index(pos)
	return index >= 0 and _micro_cells.has(index)


func get_micro_cell(pos: Vector3i):
	var index: int = get_linear_index(pos)
	return _micro_cells[index] if index >= 0 and _micro_cells.has(index) else null


func set_micro_cell(pos: Vector3i, cell) -> bool:
	if not is_inside_world(pos) or cell == null:
		return false
	if cell.is_empty():
		return clear_block(pos)
	var full_material: String = cell.normalizable_material()
	if full_material != "":
		return set_block(pos, full_material)
	var index: int = get_linear_index(pos)
	var changed: bool = true
	if _micro_cells.has(index):
		changed = _micro_cells[index].content_hash() != cell.content_hash()
	if not changed:
		return false
	if get_block_palette_id(pos) != 0:
		_set_palette_id(pos, 0)
	_micro_cells[index] = cell.duplicate_cell()
	_touch_position(pos)
	return true


func set_metadata(pos: Vector3i, value: Dictionary) -> void:
	var index: int = get_linear_index(pos)
	if index >= 0:
		_metadata[index] = value.duplicate(true)


func get_metadata(pos: Vector3i) -> Dictionary:
	var index: int = get_linear_index(pos)
	return (_metadata.get(index, {}) as Dictionary).duplicate(true) if index >= 0 else {}


func clear_metadata(pos: Vector3i) -> void:
	var index: int = get_linear_index(pos)
	if index >= 0:
		_metadata.erase(index)


func get_render_palette() -> Dictionary:
	return _render_palette


func get_section_coord(pos: Vector3i) -> Vector3i:
	return Vector3i(pos.x / SECTION_SIZE, pos.y / SECTION_SIZE, pos.z / SECTION_SIZE)


func get_section_origin(section: Vector3i) -> Vector3i:
	return section * SECTION_SIZE


func is_valid_section(section: Vector3i) -> bool:
	return section.x >= 0 and section.x < SECTION_COUNT and section.y >= 0 and section.y < SECTION_COUNT and section.z >= 0 and section.z < SECTION_COUNT


func get_section_revision(section: Vector3i) -> int:
	return int(_section_revisions.get(section, 0))


func get_nonempty_sections() -> Array:
	var result: Array = []
	for raw_section in _section_counts.keys():
		if int(_section_counts[raw_section]) > 0:
			result.append(raw_section)
	for raw_index in _micro_cells.keys():
		var section: Vector3i = get_section_coord(_position_from_index(int(raw_index)))
		if not result.has(section):
			result.append(section)
	return result


func get_affected_sections(pos: Vector3i) -> Array:
	var center: Vector3i = get_section_coord(pos)
	var local: Vector3i = pos - get_section_origin(center)
	var xs: Array[int] = [0]
	var ys: Array[int] = [0]
	var zs: Array[int] = [0]
	if local.x == 0: xs.append(-1)
	elif local.x == SECTION_SIZE - 1: xs.append(1)
	if local.y == 0: ys.append(-1)
	elif local.y == SECTION_SIZE - 1: ys.append(1)
	if local.z == 0: zs.append(-1)
	elif local.z == SECTION_SIZE - 1: zs.append(1)
	var result: Array = []
	for dx in xs:
		for dy in ys:
			for dz in zs:
				var section: Vector3i = center + Vector3i(dx, dy, dz)
				if is_valid_section(section):
					result.append(section)
	return result


func make_section_snapshot(section: Vector3i) -> Dictionary:
	var padded: PackedByteArray = PackedByteArray()
	padded.resize(PADDED_SECTION_SIZE * PADDED_SECTION_SIZE * PADDED_SECTION_SIZE)
	var origin: Vector3i = get_section_origin(section)
	var cursor: int = 0
	for local_y in range(-1, SECTION_SIZE + 1):
		for local_z in range(-1, SECTION_SIZE + 1):
			for local_x in range(-1, SECTION_SIZE + 1):
				padded[cursor] = get_block_palette_id(origin + Vector3i(local_x, local_y, local_z))
				cursor += 1
	var micro_rows: Array = []
	for raw_index in _micro_cells.keys():
		var world_pos: Vector3i = _position_from_index(int(raw_index))
		var local_pos: Vector3i = world_pos - origin
		if local_pos.x >= -1 and local_pos.x <= SECTION_SIZE and local_pos.y >= -1 and local_pos.y <= SECTION_SIZE and local_pos.z >= -1 and local_pos.z <= SECTION_SIZE:
			micro_rows.append([local_pos.x, local_pos.y, local_pos.z, _micro_cells[raw_index].to_dictionary()])
	return {"section": section, "origin": origin, "size": SECTION_SIZE, "padded_size": PADDED_SECTION_SIZE, "voxels": padded, "micro_cells": micro_rows, "revision": get_section_revision(section)}


func raycast_hit(ray_origin: Vector3, ray_direction: Vector3, max_distance: float):
	if max_distance <= 0.0 or ray_direction.length_squared() < 0.000001:
		return null
	var direction: Vector3 = ray_direction.normalized()
	var shifted: Vector3 = ray_origin + Vector3(0.5, 0.5, 0.5)
	var cell: Vector3i = Vector3i(floori(shifted.x), floori(shifted.y), floori(shifted.z))
	var step: Vector3i = Vector3i(_sign_i(direction.x), _sign_i(direction.y), _sign_i(direction.z))
	var delta: Vector3 = Vector3(_axis_delta(direction.x), _axis_delta(direction.y), _axis_delta(direction.z))
	var maximum: Vector3 = Vector3(_axis_max(shifted.x, direction.x, cell.x, step.x), _axis_max(shifted.y, direction.y, cell.y, step.y), _axis_max(shifted.z, direction.z, cell.z, step.z))
	var distance: float = 0.0
	var normal: Vector3i = Vector3i.ZERO
	for _index in range(512):
		if is_inside_world(cell) and has_block(cell):
			var block_id: String = get_block_id(cell)
			if block_id != "":
				return VoxelHitScript.new(cell, normal, block_id, distance)
			var micro_hit = _raycast_micro_interval(ray_origin, direction, cell, distance, minf(maximum.x, minf(maximum.y, maximum.z)))
			if micro_hit != null:
				return micro_hit
		if maximum.x <= maximum.y and maximum.x <= maximum.z:
			distance = maximum.x
			maximum.x += delta.x
			cell.x += step.x
			normal = Vector3i(-step.x, 0, 0)
		elif maximum.y <= maximum.z:
			distance = maximum.y
			maximum.y += delta.y
			cell.y += step.y
			normal = Vector3i(0, -step.y, 0)
		else:
			distance = maximum.z
			maximum.z += delta.z
			cell.z += step.z
			normal = Vector3i(0, 0, -step.z)
		if distance > max_distance:
			break
	return null


func _raycast_micro_interval(ray_origin: Vector3, direction: Vector3, base_pos: Vector3i, start_distance: float, end_distance: float):
	var scaled_origin: Vector3 = (ray_origin + Vector3(0.5, 0.5, 0.5)) * float(MicroCellScript.SIZE)
	var scaled_direction: Vector3 = direction * float(MicroCellScript.SIZE)
	var distance: float = maxf(0.0, start_distance) + 0.00001
	var point: Vector3 = scaled_origin + scaled_direction * distance
	var micro_global: Vector3i = Vector3i(floori(point.x), floori(point.y), floori(point.z))
	var step: Vector3i = Vector3i(_sign_i(scaled_direction.x), _sign_i(scaled_direction.y), _sign_i(scaled_direction.z))
	var delta: Vector3 = Vector3(_axis_delta(scaled_direction.x), _axis_delta(scaled_direction.y), _axis_delta(scaled_direction.z))
	var maximum: Vector3 = Vector3(distance + _axis_max(point.x, scaled_direction.x, micro_global.x, step.x), distance + _axis_max(point.y, scaled_direction.y, micro_global.y, step.y), distance + _axis_max(point.z, scaled_direction.z, micro_global.z, step.z))
	var normal: Vector3i = Vector3i.ZERO
	var cell_data = get_micro_cell(base_pos)
	for _index in range(64):
		var owner: Vector3i = Vector3i(floori(float(micro_global.x) / 8.0), floori(float(micro_global.y) / 8.0), floori(float(micro_global.z) / 8.0))
		if owner != base_pos or distance > end_distance + 0.00001:
			break
		var local: Vector3i = Vector3i(posmod(micro_global.x, 8), posmod(micro_global.y, 8), posmod(micro_global.z, 8))
		var material_id: String = cell_data.get_material(local)
		if material_id != "":
			return VoxelHitScript.new(base_pos, normal, material_id, distance, local, true)
		if maximum.x <= maximum.y and maximum.x <= maximum.z:
			distance = maximum.x; maximum.x += delta.x; micro_global.x += step.x; normal = Vector3i(-step.x, 0, 0)
		elif maximum.y <= maximum.z:
			distance = maximum.y; maximum.y += delta.y; micro_global.y += step.y; normal = Vector3i(0, -step.y, 0)
		else:
			distance = maximum.z; maximum.z += delta.z; micro_global.z += step.z; normal = Vector3i(0, 0, -step.z)
	return null


func to_template(selection_min: Vector3i, selection_max: Vector3i, template_id: String, name: String):
	var minimum: Vector3i = Vector3i(min(selection_min.x, selection_max.x), min(selection_min.y, selection_max.y), min(selection_min.z, selection_max.z))
	var maximum: Vector3i = Vector3i(max(selection_min.x, selection_max.x), max(selection_min.y, selection_max.y), max(selection_min.z, selection_max.z))
	var template = StructureTemplateScript.new()
	template.structure_id = template_id
	template.display_name = name
	template.size = maximum - minimum + Vector3i.ONE
	template.pivot = pivot - minimum
	var component_owned: Dictionary = {}
	for raw_component in components:
		for raw_owned in (raw_component as Dictionary).get("owned_positions", []) as Array:
			component_owned[StructureTemplateScript._vector3i_from_value(raw_owned)] = true
	for y in range(minimum.y, maximum.y + 1):
		for z in range(minimum.z, maximum.z + 1):
			for x in range(minimum.x, maximum.x + 1):
				var world_pos: Vector3i = Vector3i(x, y, z)
				if component_owned.has(world_pos): continue
				var local_pos: Vector3i = world_pos - minimum
				var block_id: String = get_block_id(world_pos)
				if block_id != "":
					template.blocks[local_pos] = block_id
				var micro_cell = get_micro_cell(world_pos)
				if micro_cell != null:
					template.micro_cells[local_pos] = micro_cell.duplicate_cell()
				if explicit_air.has(world_pos):
					template.explicit_air[local_pos] = true
				var meta: Dictionary = get_metadata(world_pos)
				if not meta.is_empty():
					template.metadata[local_pos] = meta
	for raw_marker in markers:
		var marker: Dictionary = (raw_marker as Dictionary).duplicate(true)
		var marker_pos: Vector3i = _marker_position(marker)
		if marker_pos.x >= minimum.x and marker_pos.x <= maximum.x and marker_pos.y >= minimum.y and marker_pos.y <= maximum.y and marker_pos.z >= minimum.z and marker_pos.z <= maximum.z:
			var local_marker: Vector3i = marker_pos - minimum
			marker["pos"] = [local_marker.x, local_marker.y, local_marker.z]
			template.markers.append(marker)
	for raw_component in components:
		var component: Dictionary = (raw_component as Dictionary).duplicate(true)
		var component_pos: Vector3i = _marker_position(component)
		if component_pos.x < minimum.x or component_pos.x > maximum.x or component_pos.y < minimum.y or component_pos.y > maximum.y or component_pos.z < minimum.z or component_pos.z > maximum.z: continue
		var local_component: Vector3i = component_pos - minimum
		component["pos"] = [local_component.x, local_component.y, local_component.z]
		component.erase("owned_positions")
		template.components.append(component)
	return template


func load_template(template, origin: Vector3i = Vector3i.ZERO) -> void:
	reset()
	for raw_pos in template.blocks.keys():
		set_block(origin + (raw_pos as Vector3i), str(template.blocks[raw_pos]))
	for raw_pos in template.micro_cells.keys():
		set_micro_cell(origin + (raw_pos as Vector3i), template.micro_cells[raw_pos])
	for raw_pos in template.explicit_air.keys():
		explicit_air[origin + (raw_pos as Vector3i)] = true
	for raw_pos in template.metadata.keys():
		set_metadata(origin + (raw_pos as Vector3i), template.metadata[raw_pos] as Dictionary)
	markers.clear()
	for raw_marker in template.markers:
		var marker: Dictionary = (raw_marker as Dictionary).duplicate(true)
		var marker_pos: Vector3i = _marker_position(marker) + origin
		marker["pos"] = [marker_pos.x, marker_pos.y, marker_pos.z]
		markers.append(marker)
	components.clear()
	for raw_component in template.components:
		var component: Dictionary = (raw_component as Dictionary).duplicate(true)
		var component_pos: Vector3i = _marker_position(component) + origin
		component["pos"] = [component_pos.x, component_pos.y, component_pos.z]
		components.append(component)
	pivot = origin + template.pivot


func _set_palette_id(pos: Vector3i, palette_id: int) -> bool:
	var index: int = get_linear_index(pos)
	var previous: int = int(_voxels[index])
	if previous == palette_id:
		return false
	var section: Vector3i = get_section_coord(pos)
	if previous == 0 and palette_id != 0:
		_section_counts[section] = int(_section_counts.get(section, 0)) + 1
	elif previous != 0 and palette_id == 0:
		var count: int = int(_section_counts.get(section, 1)) - 1
		if count <= 0: _section_counts.erase(section)
		else: _section_counts[section] = count
	_voxels[index] = palette_id
	for affected in get_affected_sections(pos):
		_section_revisions[affected] = get_section_revision(affected) + 1
	return true


func _touch_position(pos: Vector3i) -> void:
	for affected in get_affected_sections(pos):
		_section_revisions[affected] = get_section_revision(affected) + 1


func _position_from_index(index: int) -> Vector3i:
	var x: int = index % SIZE
	var yz: int = index / SIZE
	var z: int = yz % SIZE
	return Vector3i(x, yz / SIZE, z)


static func _marker_position(marker: Dictionary) -> Vector3i:
	var raw: Variant = marker.get("pos", [0, 0, 0])
	if raw is Vector3i:
		return raw
	if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 3:
		return Vector3i(int(raw[0]), int(raw[1]), int(raw[2]))
	return Vector3i.ZERO


static func _sign_i(value: float) -> int:
	return 1 if value > 0.0 else (-1 if value < 0.0 else 0)


static func _axis_delta(value: float) -> float:
	return abs(1.0 / value) if abs(value) > 0.000001 else INF


static func _axis_max(origin: float, direction: float, cell: int, step: int) -> float:
	if step == 0 or abs(direction) <= 0.000001:
		return INF
	var boundary: float = float(cell + 1) if step > 0 else float(cell)
	return (boundary - origin) / direction
