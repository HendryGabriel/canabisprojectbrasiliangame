## Fixed-size, palette-backed voxel storage for TRUMANCRAFT.
##
## The world is deliberately finite.  Runtime lookups use a compact byte grid
## instead of a Dictionary<Vector3i, String>, while names remain available at
## the gameplay boundary through the stable palette below.
class_name VoxelWorld
extends RefCounted


const VoxelHitScript = preload("res://src/voxel_hit.gd")

const WORLD_WIDTH: int = 200
const WORLD_DEPTH: int = 200
const WORLD_MIN_Y: int = -65
const WORLD_MAX_Y: int = 126
const WORLD_HEIGHT: int = WORLD_MAX_Y - WORLD_MIN_Y + 1
const WORLD_VOLUME: int = WORLD_WIDTH * WORLD_DEPTH * WORLD_HEIGHT

const BIOME_SIZE: int = 100
const SECTION_SIZE: int = 16
const PADDED_SECTION_SIZE: int = SECTION_SIZE + 2
const SECTION_COUNT_X: int = 13 # ceil(200 / 16)
const SECTION_COUNT_Y: int = 12 # 192 / 16
const SECTION_COUNT_Z: int = 13 # ceil(200 / 16)

const SAVE_FORMAT: String = "finite_voxel_v3"
const SAVE_VERSION: int = 3
## Bump only when the stable byte palette layout changes incompatibly.
const PALETTE_VERSION: int = 1
## Never reorder existing values. New catalog entries are appended after this
## list, so save palette IDs remain stable across content updates.
const STABLE_BLOCK_ORDER: Array = [
	"grass", "dirt", "stone", "cobblestone", "bedrock", "wood", "leaves",
	"planks", "copper_ore", "iron_ore", "coal_ore", "manita_ore",
	"crafting_table", "chest", "short_grass", "wild_grass", "poppy",
	"dandelion", "cornflower", "oxeye_daisy",
]


var _voxels: PackedByteArray = PackedByteArray()
var _surface_heights: PackedInt32Array = PackedInt32Array()
var _name_to_id: Dictionary = {}
var _id_to_name: PackedStringArray = PackedStringArray([""])
var _block_defs: Dictionary = {}
var _render_palette: Dictionary = {}
var _section_revisions: Dictionary = {}
var _section_nonempty_counts: Dictionary = {}
var _changed_voxels: Dictionary = {} # linear index -> palette id (0 is removal)
## Sparse state for chests and future stateful blocks, keyed by linear voxel
## index. It is intentionally separate from the dense palette byte grid.
var _metadata: Dictionary = {}
var _tracking_changes: bool = false
var _seed: int = 0


func _init(block_definitions: Dictionary = {}) -> void:

	_voxels.resize(WORLD_VOLUME)
	_voxels.fill(0)
	_surface_heights.resize(WORLD_WIDTH * WORLD_DEPTH)
	_surface_heights.fill(0)
	if not block_definitions.is_empty():
		configure_palette(block_definitions)


## Builds a stable palette from deterministic catalog key order.  Never use a
## Dictionary iteration order as saved data; palette IDs are derived from the
## sorted names and the save records its format version.
func configure_palette(block_definitions: Dictionary) -> void:
	_block_defs = block_definitions
	_name_to_id.clear()
	_id_to_name = PackedStringArray([""])
	_render_palette.clear()
	var names: Array = []
	for block_name in STABLE_BLOCK_ORDER:
		if block_definitions.has(block_name):
			names.append(block_name)
	var remaining: Array = block_definitions.keys()
	remaining.sort()
	for block_name in remaining:
		if not names.has(block_name):
			names.append(block_name)
	for raw_name in names:
		var block_name: String = str(raw_name)
		if _id_to_name.size() >= 256:
			push_error("Voxel palette exceeded 255 block IDs.")
			break
		var palette_id: int = _id_to_name.size()
		_name_to_id[block_name] = palette_id
		_id_to_name.append(block_name)
		var definition: Dictionary = block_definitions.get(block_name, {})
		_render_palette[palette_id] = _make_render_descriptor(block_name, definition)


func reset(seed: int = 0) -> void:
	_seed = seed
	_voxels.fill(0)
	_surface_heights.fill(0)
	_section_revisions.clear()
	_section_nonempty_counts.clear()
	_changed_voxels.clear()
	_metadata.clear()
	_tracking_changes = false


func get_seed() -> int:
	return _seed


func get_voxel_hash() -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(_voxels)
	return context.finish().hex_encode()


func set_tracking_changes(enabled: bool) -> void:
	_tracking_changes = enabled


func is_tracking_changes() -> bool:
	return _tracking_changes


func is_inside_world(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < WORLD_WIDTH and pos.z >= 0 and pos.z < WORLD_DEPTH and pos.y >= WORLD_MIN_Y and pos.y <= WORLD_MAX_Y


## Only Biome 1 is currently generated and playable.  The rest of the fixed
## 200x200 grid remains reserved for future content.  Superflat/creative worlds
## can grow the unlocked area at runtime up to the full 200x200 grid.
var unlocked_size: int = BIOME_SIZE


func set_unlocked_size(value: int) -> void:
	unlocked_size = clampi(value, BIOME_SIZE, WORLD_WIDTH)


func is_inside_unlocked_biome(pos: Vector3i) -> bool:
	return is_inside_world(pos) and pos.x >= 0 and pos.x < unlocked_size and pos.z >= 0 and pos.z < unlocked_size


func is_buildable(pos: Vector3i) -> bool:
	# Reserve the top layer for the future sky boundary.
	return is_inside_unlocked_biome(pos) and pos.y < WORLD_MAX_Y


func get_linear_index(pos: Vector3i) -> int:
	if not is_inside_world(pos):
		return -1
	var local_y: int = pos.y - WORLD_MIN_Y
	return (local_y * WORLD_DEPTH + pos.z) * WORLD_WIDTH + pos.x


func get_position_from_index(index: int) -> Vector3i:
	if index < 0 or index >= WORLD_VOLUME:
		return Vector3i.ZERO
	var x: int = index % WORLD_WIDTH
	var yz: int = index / WORLD_WIDTH
	var z: int = yz % WORLD_DEPTH
	var local_y: int = yz / WORLD_DEPTH
	return Vector3i(x, local_y + WORLD_MIN_Y, z)


func get_block_palette_id(pos: Vector3i) -> int:
	var index: int = get_linear_index(pos)
	return int(_voxels[index]) if index >= 0 else 0


func get_palette_id_for_name(block_id: String) -> int:
	return int(_name_to_id.get(block_id, 0))


func get_palette_name(palette_id: int) -> String:
	return str(_id_to_name[palette_id]) if palette_id > 0 and palette_id < _id_to_name.size() else ""


func get_block_id(pos: Vector3i) -> String:
	var palette_id: int = get_block_palette_id(pos)
	return str(_id_to_name[palette_id]) if palette_id > 0 and palette_id < _id_to_name.size() else ""


func has_block(pos: Vector3i) -> bool:
	return get_block_palette_id(pos) != 0


func get_definition(block_id: String) -> Dictionary:
	return _block_defs.get(block_id, {})


func get_render_palette() -> Dictionary:
	return _render_palette


func configure_texture_layers(layer_by_path: Dictionary) -> void:
	for raw_palette_id in _render_palette.keys():
		var descriptor: Dictionary = _render_palette[raw_palette_id] as Dictionary
		var layers: Dictionary = {}
		var textures: Dictionary = descriptor.get("textures", {}) as Dictionary
		for face_name in textures.keys():
			layers[face_name] = int(layer_by_path.get(str(textures[face_name]), 0))
		descriptor["texture_layers"] = layers


func set_base_block(pos: Vector3i, block_id: String) -> bool:
	return _set_block_internal(pos, block_id, false)


func clear_base_block(pos: Vector3i) -> bool:
	if not is_inside_world(pos):
		return false
	var index: int = get_linear_index(pos)
	if int(_voxels[index]) == 0:
		return false
	_set_palette_id(pos, 0, false)
	_metadata.erase(index)
	return true


func set_block(pos: Vector3i, block_id: String) -> bool:
	if not is_buildable(pos):
		return false
	return _set_block_internal(pos, block_id, true)


func remove_block(pos: Vector3i) -> bool:
	if not is_buildable(pos):
		return false
	var index: int = get_linear_index(pos)
	if int(_voxels[index]) == 0:
		return false
	_set_palette_id(pos, 0, true)
	_metadata.erase(index)
	return true


func set_metadata(pos: Vector3i, key: String, value: Variant) -> bool:
	if not is_inside_world(pos) or key == "":
		return false
	var index: int = get_linear_index(pos)
	var entry: Dictionary = _metadata.get(index, {}) as Dictionary
	entry[key] = value
	_metadata[index] = entry
	return true


func has_metadata(pos: Vector3i, key: String) -> bool:
	var index: int = get_linear_index(pos)
	if index < 0:
		return false
	var entry: Dictionary = _metadata.get(index, {}) as Dictionary
	return entry.has(key)


func get_metadata(pos: Vector3i, key: String, fallback: Variant = null) -> Variant:
	var index: int = get_linear_index(pos)
	if index < 0:
		return fallback
	var entry: Dictionary = _metadata.get(index, {}) as Dictionary
	return entry.get(key, fallback)


func erase_metadata(pos: Vector3i, key: String = "") -> void:
	var index: int = get_linear_index(pos)
	if index < 0:
		return
	if key == "":
		_metadata.erase(index)
		return
	var entry: Dictionary = _metadata.get(index, {}) as Dictionary
	entry.erase(key)
	if entry.is_empty():
		_metadata.erase(index)
	else:
		_metadata[index] = entry


func clear_metadata(key: String = "") -> void:
	if key == "":
		_metadata.clear()
		return
	for raw_index in _metadata.keys():
		var index: int = int(raw_index)
		var entry: Dictionary = _metadata[index] as Dictionary
		entry.erase(key)
		if entry.is_empty():
			_metadata.erase(index)
		else:
			_metadata[index] = entry


func get_metadata_positions(key: String) -> Array:
	var result: Array = []
	for raw_index in _metadata.keys():
		var index: int = int(raw_index)
		var entry: Dictionary = _metadata[index] as Dictionary
		if entry.has(key):
			result.append(get_position_from_index(index))
	return result


func clear_changes() -> void:
	_changed_voxels.clear()


func export_changes() -> Array:
	var result: Array = []
	var indices: Array = _changed_voxels.keys()
	indices.sort()
	for raw_index in indices:
		result.append([int(raw_index), int(_changed_voxels[raw_index])])
	return result


func import_changes(raw_changes: Variant) -> bool:
	if typeof(raw_changes) != TYPE_ARRAY:
		return false
	_tracking_changes = false
	for raw_entry in raw_changes:
		if typeof(raw_entry) != TYPE_ARRAY:
			continue
		var entry: Array = raw_entry as Array
		if entry.size() != 2:
			continue
		var index: int = int(entry[0])
		var palette_id: int = int(entry[1])
		if index < 0 or index >= WORLD_VOLUME or palette_id < 0 or palette_id >= _id_to_name.size():
			continue
		var pos: Vector3i = get_position_from_index(index)
		if not is_buildable(pos):
			continue
		_set_palette_id(pos, palette_id, false)
		_changed_voxels[index] = palette_id
	return true


func export_metadata() -> Array:
	var result: Array = []
	var indices: Array = _metadata.keys()
	indices.sort()
	for raw_index in indices:
		var index: int = int(raw_index)
		result.append([index, _metadata[index]])
	return result


func import_metadata(raw_metadata: Variant) -> bool:
	if typeof(raw_metadata) != TYPE_ARRAY:
		return false
	for raw_entry in raw_metadata:
		if typeof(raw_entry) != TYPE_ARRAY:
			continue
		var entry: Array = raw_entry as Array
		if entry.size() != 2:
			continue
		var index: int = int(entry[0])
		if index < 0 or index >= WORLD_VOLUME or typeof(entry[1]) != TYPE_DICTIONARY:
			continue
		var pos: Vector3i = get_position_from_index(index)
		if not is_buildable(pos) or get_block_palette_id(pos) == 0:
			continue
		_metadata[index] = (entry[1] as Dictionary).duplicate(true)
	return true


func build_save_data() -> Dictionary:
	return {
		"format": SAVE_FORMAT,
		"version": SAVE_VERSION,
		"palette_version": PALETTE_VERSION,
		"seed": _seed,
		"width": WORLD_WIDTH,
		"depth": WORLD_DEPTH,
		"min_y": WORLD_MIN_Y,
		"max_y": WORLD_MAX_Y,
		"changes": export_changes(),
		"metadata": export_metadata(),
	}


func load_save_data(data: Dictionary) -> bool:
	if str(data.get("format", "")) != SAVE_FORMAT or int(data.get("version", 0)) != SAVE_VERSION:
		return false
	if int(data.get("palette_version", 0)) != PALETTE_VERSION:
		return false
	if int(data.get("width", -1)) != WORLD_WIDTH or int(data.get("depth", -1)) != WORLD_DEPTH:
		return false
	if int(data.get("min_y", 0)) != WORLD_MIN_Y or int(data.get("max_y", 0)) != WORLD_MAX_Y:
		return false
	_seed = int(data.get("seed", _seed))
	_changed_voxels.clear()
	_metadata.clear()
	if not import_changes(data.get("changes", [])):
		return false
	return import_metadata(data.get("metadata", []))


func set_surface_height(x: int, z: int, height: int) -> void:
	if x < 0 or x >= WORLD_WIDTH or z < 0 or z >= WORLD_DEPTH:
		return
	_surface_heights[z * WORLD_WIDTH + x] = height


func get_surface_height(x: int, z: int, fallback: int = 0) -> int:
	if x < 0 or x >= WORLD_WIDTH or z < 0 or z >= WORLD_DEPTH:
		return fallback
	return int(_surface_heights[z * WORLD_WIDTH + x])


func get_section_coord(pos: Vector3i) -> Vector3i:
	return Vector3i(
		floori(float(pos.x) / float(SECTION_SIZE)),
		floori(float(pos.y - WORLD_MIN_Y) / float(SECTION_SIZE)),
		floori(float(pos.z) / float(SECTION_SIZE))
	)


func is_valid_section(section: Vector3i) -> bool:
	return section.x >= 0 and section.x < SECTION_COUNT_X and section.y >= 0 and section.y < SECTION_COUNT_Y and section.z >= 0 and section.z < SECTION_COUNT_Z


func get_section_origin(section: Vector3i) -> Vector3i:
	return Vector3i(section.x * SECTION_SIZE, WORLD_MIN_Y + section.y * SECTION_SIZE, section.z * SECTION_SIZE)


func get_section_revision(section: Vector3i) -> int:
	return int(_section_revisions.get(section, 0))


func get_nonempty_sections() -> Array:
	var sections: Array = []
	for raw_section in _section_nonempty_counts.keys():
		if int(_section_nonempty_counts[raw_section]) > 0:
			sections.append(raw_section)
	return sections


## A snapshot owns its byte buffer and never references the live voxel grid.
## It is safe to hand to a worker as long as the worker only reads it.
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
	return {
		"section": section,
		"origin": origin,
		"size": SECTION_SIZE,
		"padded_size": PADDED_SECTION_SIZE,
		"voxels": padded,
		"revision": get_section_revision(section),
	}


## Returns all sections whose mesh or AO can change after one voxel mutation.
## The surrounding 3x3x3 set only expands at a section boundary; most edits
## invalidate one section.
func get_affected_sections(pos: Vector3i) -> Array:
	var center: Vector3i = get_section_coord(pos)
	var local: Vector3i = pos - get_section_origin(center)
	var x_offsets: Array[int] = [0]
	var y_offsets: Array[int] = [0]
	var z_offsets: Array[int] = [0]
	if local.x == 0:
		x_offsets.append(-1)
	elif local.x == SECTION_SIZE - 1:
		x_offsets.append(1)
	if local.y == 0:
		y_offsets.append(-1)
	elif local.y == SECTION_SIZE - 1:
		y_offsets.append(1)
	if local.z == 0:
		z_offsets.append(-1)
	elif local.z == SECTION_SIZE - 1:
		z_offsets.append(1)
	var result: Array = []
	for x_offset in x_offsets:
		for y_offset in y_offsets:
			for z_offset in z_offsets:
				var section: Vector3i = center + Vector3i(x_offset, y_offset, z_offset)
				if is_valid_section(section):
					result.append(section)
	return result


## Data-driven block picking.  Blocks are centered on integer coordinates, so
## ray traversal is performed in a grid shifted by +0.5.
func raycast_hit(ray_origin: Vector3, ray_direction: Vector3, max_distance: float):
	if max_distance <= 0.0 or ray_direction.length_squared() <= 0.000001:
		return null
	var direction: Vector3 = ray_direction.normalized()
	var shifted_origin: Vector3 = ray_origin + Vector3(0.5, 0.5, 0.5)
	var cell: Vector3i = Vector3i(floori(shifted_origin.x), floori(shifted_origin.y), floori(shifted_origin.z))
	var step: Vector3i = Vector3i(_sign_i(direction.x), _sign_i(direction.y), _sign_i(direction.z))
	var t_delta: Vector3 = Vector3(_axis_delta(direction.x), _axis_delta(direction.y), _axis_delta(direction.z))
	var t_max: Vector3 = Vector3(
		_axis_max(shifted_origin.x, direction.x, cell.x, step.x),
		_axis_max(shifted_origin.y, direction.y, cell.y, step.y),
		_axis_max(shifted_origin.z, direction.z, cell.z, step.z)
	)
	var distance_travelled: float = 0.0
	var normal: Vector3i = Vector3i.ZERO
	var max_steps: int = max(8, ceili(max_distance * 4.0) + 8)
	for _step_index in range(max_steps):
		if is_inside_world(cell):
			var block_id: String = get_block_id(cell)
			if block_id != "":
				return VoxelHitScript.new(cell, normal, block_id, distance_travelled)
		elif distance_travelled > 0.0:
			return null
		if t_max.x <= t_max.y and t_max.x <= t_max.z:
			distance_travelled = t_max.x
			t_max.x += t_delta.x
			cell.x += step.x
			normal = Vector3i(-step.x, 0, 0)
		elif t_max.y <= t_max.z:
			distance_travelled = t_max.y
			t_max.y += t_delta.y
			cell.y += step.y
			normal = Vector3i(0, -step.y, 0)
		else:
			distance_travelled = t_max.z
			t_max.z += t_delta.z
			cell.z += step.z
			normal = Vector3i(0, 0, -step.z)
		if distance_travelled > max_distance:
			break
	return null


## Compatibility helper for lightweight callers and regression assertions.
func raycast_voxels(ray_origin: Vector3, ray_direction: Vector3, max_distance: float) -> Dictionary:
	var hit = raycast_hit(ray_origin, ray_direction, max_distance)
	return hit.to_dictionary() if hit != null else {}


func _set_block_internal(pos: Vector3i, block_id: String, record_change: bool) -> bool:
	if not is_inside_world(pos) or not _name_to_id.has(block_id):
		return false
	var palette_id: int = int(_name_to_id[block_id])
	var index: int = get_linear_index(pos)
	if int(_voxels[index]) == palette_id:
		return false
	_set_palette_id(pos, palette_id, record_change)
	return true


func _set_palette_id(pos: Vector3i, palette_id: int, record_change: bool) -> void:
	var index: int = get_linear_index(pos)
	if index < 0:
		return
	var previous_id: int = int(_voxels[index])
	if previous_id == palette_id:
		return
	var section: Vector3i = get_section_coord(pos)
	if previous_id == 0 and palette_id != 0:
		_section_nonempty_counts[section] = int(_section_nonempty_counts.get(section, 0)) + 1
	elif previous_id != 0 and palette_id == 0:
		var new_count: int = max(0, int(_section_nonempty_counts.get(section, 1)) - 1)
		if new_count == 0:
			_section_nonempty_counts.erase(section)
		else:
			_section_nonempty_counts[section] = new_count
	_voxels[index] = palette_id
	if record_change and _tracking_changes:
		_changed_voxels[index] = palette_id
	for affected_section in get_affected_sections(pos):
		_section_revisions[affected_section] = get_section_revision(affected_section) + 1


func _make_render_descriptor(block_name: String, definition: Dictionary) -> Dictionary:
	var texture_paths: Dictionary = {}
	for face_name in ["north", "south", "east", "west", "top", "bottom"]:
		texture_paths[face_name] = _texture_for_face(definition, face_name)
	return {
		"block_id": block_name,
		"solid": bool(definition.get("solid", true)),
		"transparent": bool(definition.get("transparent", false)) or float(definition.get("alpha", 1.0)) < 0.99,
		"foliage": bool(definition.get("foliage", false)),
		"plant": bool(definition.get("plant", false)),
		"alpha": float(definition.get("alpha", 1.0)),
		"color": definition.get("color", Color.WHITE),
		"random_top_rotation": bool(definition.get("random_top_rotation", false)),
		"textures": texture_paths,
	}


func _texture_for_face(definition: Dictionary, face_name: String) -> String:
	var textures: Dictionary = definition.get("textures", {})
	if textures.has(face_name):
		return str(textures[face_name])
	if face_name in ["north", "south", "east", "west"]:
		if face_name == "north" and textures.has("front"):
			return str(textures["front"])
		if textures.has("side"):
			return str(textures["side"])
	return str(definition.get("texture", ""))


static func _sign_i(value: float) -> int:
	return 1 if value > 0.0 else (-1 if value < 0.0 else 0)


static func _axis_delta(value: float) -> float:
	return abs(1.0 / value) if abs(value) > 0.000001 else INF


static func _axis_max(origin: float, direction: float, cell: int, step: int) -> float:
	if step == 0 or abs(direction) <= 0.000001:
		return INF
	var next_boundary: float = float(cell + 1) if step > 0 else float(cell)
	return (next_boundary - origin) / direction
