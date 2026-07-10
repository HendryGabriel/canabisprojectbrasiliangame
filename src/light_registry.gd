extends Node3D
class_name LightRegistry

const METADATA_KEY: String = "torch_light"
const SPAWN_BLOCK_RADIUS: float = 8.0

var voxel_world = null
var lights: Dictionary = {}

func configure(world) -> void:
	voxel_world = world
	rebuild()

func rebuild() -> void:
	for light in lights.values():
		if is_instance_valid(light):
			light.queue_free()
	lights.clear()
	if voxel_world == null:
		return
	for raw_pos in voxel_world.get_metadata_positions(METADATA_KEY):
		var pos: Vector3i = raw_pos
		if voxel_world.get_block_id(pos) == "torch":
			register_torch(pos, false)
		else:
			voxel_world.erase_metadata(pos, METADATA_KEY)

func register_torch(pos: Vector3i, store_metadata: bool = true) -> void:
	if lights.has(pos):
		return
	if store_metadata and voxel_world != null:
		voxel_world.set_metadata(pos, METADATA_KEY, true)
	var light := OmniLight3D.new()
	light.name = "TorchLight_%d_%d_%d" % [pos.x, pos.y, pos.z]
	light.position = Vector3(pos) + Vector3(0.0, 0.7, 0.0)
	light.light_color = Color(1.0, 0.62, 0.22)
	light.light_energy = 1.7
	light.omni_range = 8.0
	light.shadow_enabled = false
	add_child(light)
	lights[pos] = light

func unregister_torch(pos: Vector3i) -> void:
	if voxel_world != null:
		voxel_world.erase_metadata(pos, METADATA_KEY)
	var light: Variant = lights.get(pos)
	if light != null and is_instance_valid(light):
		light.queue_free()
	lights.erase(pos)

func is_spawn_blocked(position: Vector3, radius: float = SPAWN_BLOCK_RADIUS) -> bool:
	var radius_squared: float = radius * radius
	for raw_pos in lights.keys():
		var torch_pos: Vector3 = Vector3(raw_pos as Vector3i) + Vector3(0.0, 0.5, 0.0)
		if torch_pos.distance_squared_to(position) <= radius_squared:
			return true
	return false
