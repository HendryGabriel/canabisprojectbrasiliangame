class_name VoxelDebrisSystem
extends MultiMeshInstance3D


const STORAGE_CAPACITY: int = 256
const GRAVITY: float = 12.0

var block_definitions: Dictionary = {}
var capacity_limit: int = STORAGE_CAPACITY
var _positions: PackedVector3Array = PackedVector3Array()
var _velocities: PackedVector3Array = PackedVector3Array()
var _rotations: PackedVector3Array = PackedVector3Array()
var _ages: PackedFloat32Array = PackedFloat32Array()
var _lifetimes: PackedFloat32Array = PackedFloat32Array()
var _active: PackedByteArray = PackedByteArray()
var _colors: PackedColorArray = PackedColorArray()
var _palette_cache: Dictionary = {}
var _mining_accumulator: float = 0.0


func _init() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_positions.resize(STORAGE_CAPACITY)
	_velocities.resize(STORAGE_CAPACITY)
	_rotations.resize(STORAGE_CAPACITY)
	_ages.resize(STORAGE_CAPACITY)
	_lifetimes.resize(STORAGE_CAPACITY)
	_active.resize(STORAGE_CAPACITY)
	_colors.resize(STORAGE_CAPACITY)

	var cube: BoxMesh = BoxMesh.new()
	cube.size = Vector3.ONE * 0.105
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	cube.material = material

	var data: MultiMesh = MultiMesh.new()
	data.transform_format = MultiMesh.TRANSFORM_3D
	data.use_colors = true
	data.mesh = cube
	data.instance_count = STORAGE_CAPACITY
	multimesh = data
	for index in range(STORAGE_CAPACITY):
		_hide_instance(index)


func configure(definitions: Dictionary, max_particles: int = STORAGE_CAPACITY) -> void:
	block_definitions = definitions
	set_capacity_limit(max_particles)


func set_capacity_limit(value: int) -> void:
	capacity_limit = clampi(value, 0, STORAGE_CAPACITY)
	for index in range(capacity_limit, STORAGE_CAPACITY):
		_active[index] = 0
		_hide_instance(index)


func emit_mining(block_pos: Vector3i, normal: Vector3i, block_id: String, delta: float) -> void:
	_mining_accumulator += delta * 10.0
	while _mining_accumulator >= 1.0:
		_mining_accumulator -= 1.0
		_emit_one(Vector3(block_pos) + Vector3(normal) * 0.53, Vector3(normal), block_id, _face_from_normal(normal), 0.28, 0.46)


func emit_burst(block_pos: Vector3i, normal: Vector3i, block_id: String, count: int = 18) -> void:
	var origin: Vector3 = Vector3(block_pos) + Vector3(normal) * 0.28
	for _index in range(count):
		_emit_one(origin, Vector3(normal), block_id, _face_from_normal(normal), 1.2, 0.75)


func stop_mining() -> void:
	_mining_accumulator = 0.0


func update_particles(delta: float, world = null) -> void:
	if multimesh == null:
		return
	for index in range(capacity_limit):
		if _active[index] == 0:
			continue
		_ages[index] += delta
		if _ages[index] >= _lifetimes[index]:
			_active[index] = 0
			_hide_instance(index)
			continue
		var velocity: Vector3 = _velocities[index]
		velocity.y -= GRAVITY * delta
		var previous: Vector3 = _positions[index]
		var next: Vector3 = previous + velocity * delta
		if world != null and world.get_block_id(_world_to_voxel(next)) != "":
			next = previous
			velocity.y = absf(velocity.y) * 0.32
			velocity.x *= 0.62
			velocity.z *= 0.62
		_positions[index] = next
		_velocities[index] = velocity
		_rotations[index] += Vector3(2.9, 4.1, 3.3) * delta
		var basis: Basis = Basis.from_euler(_rotations[index])
		multimesh.set_instance_transform(index, Transform3D(basis, next))
		multimesh.set_instance_color(index, _colors[index])


func active_count() -> int:
	var count: int = 0
	for index in range(capacity_limit):
		count += int(_active[index])
	return count


func _emit_one(origin: Vector3, normal: Vector3, block_id: String, face_name: String, speed: float, lifetime: float) -> void:
	var slot: int = _free_slot()
	if slot < 0:
		return
	var lateral: Vector3 = Vector3(randf_range(-1.0, 1.0), randf_range(-0.2, 1.0), randf_range(-1.0, 1.0))
	var direction: Vector3 = (normal * 0.55 + lateral).normalized()
	_active[slot] = 1
	_positions[slot] = origin + lateral * 0.12
	_velocities[slot] = direction * randf_range(speed * 0.55, speed) + Vector3.UP * speed * 0.45
	_rotations[slot] = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	_ages[slot] = 0.0
	_lifetimes[slot] = randf_range(lifetime * 0.72, lifetime)
	_colors[slot] = _sample_color(block_id, face_name)


func _free_slot() -> int:
	for index in range(capacity_limit):
		if _active[index] == 0:
			return index
	return -1


func _hide_instance(index: int) -> void:
	if multimesh != null:
		multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))


func _sample_color(block_id: String, face_name: String) -> Color:
	var key: String = "%s|%s" % [block_id, face_name]
	if not _palette_cache.has(key):
		_palette_cache[key] = _load_palette(block_id, face_name)
	var palette: PackedColorArray = _palette_cache[key]
	return palette[randi() % palette.size()] if not palette.is_empty() else Color(0.55, 0.55, 0.55)


func _load_palette(block_id: String, face_name: String) -> PackedColorArray:
	var result: PackedColorArray = PackedColorArray()
	if not block_definitions.has(block_id):
		return result
	var definition: Dictionary = block_definitions[block_id] as Dictionary
	var texture_path: String = _texture_for_face(definition, face_name)
	var texture: Texture2D = load(texture_path) as Texture2D if texture_path != "" else null
	var image: Image = texture.get_image() if texture != null else null
	if image == null:
		return result
	image = image.duplicate()
	image.convert(Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color: Color = image.get_pixel(x, y)
			if color.a >= 0.5:
				result.append(Color(color.r, color.g, color.b, 1.0))
	return result


static func _texture_for_face(definition: Dictionary, face_name: String) -> String:
	var textures: Dictionary = definition.get("textures", {}) as Dictionary
	if textures.has(face_name): return str(textures[face_name])
	if face_name == "north" and textures.has("front"): return str(textures["front"])
	if face_name in ["south", "east", "west"] and textures.has("side"): return str(textures["side"])
	if textures.has("side"): return str(textures["side"])
	if textures.has("all"): return str(textures["all"])
	return str(definition.get("texture", ""))


static func _face_from_normal(normal: Vector3i) -> String:
	if normal.y > 0: return "top"
	if normal.y < 0: return "bottom"
	if normal.x > 0: return "east"
	if normal.x < 0: return "west"
	if normal.z > 0: return "south"
	return "north"


static func _world_to_voxel(position: Vector3) -> Vector3i:
	return Vector3i(floori(position.x + 0.5), floori(position.y + 0.5), floori(position.z + 0.5))
