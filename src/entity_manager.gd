extends Node3D
class_name EntityManager

const GhostScript = preload("res://src/ghost.gd")
const RabbitScript = preload("res://src/rabbit.gd")
const MIN_SPAWN_DISTANCE: float = 12.0
const MAX_SPAWN_DISTANCE: float = 32.0
const MAX_GHOSTS: int = 8
const MAX_RABBITS: int = 10
const WORLD_MIN_Y: int = -65

var controller: Node = null
var voxel_world = null
var light_registry = null
var special_spawn_points: Array[Vector3] = []
var ghosts: Array = []
var rabbits: Array = []
var spawn_timer: float = 1.0

func configure(p_controller: Node, world, lights, raw_special_spawns: Array = []) -> void:
	controller = p_controller
	voxel_world = world
	light_registry = lights
	special_spawn_points.clear()
	for raw_spawn in raw_special_spawns:
		if typeof(raw_spawn) == TYPE_DICTIONARY and str((raw_spawn as Dictionary).get("entity_id", "")) == "ghost":
			var position_value: Variant = (raw_spawn as Dictionary).get("position", Vector3.ZERO)
			if position_value is Vector3:
				special_spawn_points.append(position_value as Vector3)

func _process(delta: float) -> void:
	if controller == null or not controller.can_spawn_entities():
		return
	spawn_timer -= delta
	if spawn_timer > 0.0:
		return
	spawn_timer = 2.5
	_prune_entities()
	if ghosts.size() < MAX_GHOSTS:
		_try_spawn_ghost()
	if rabbits.size() < MAX_RABBITS:
		_try_spawn_rabbit()

func get_player_target() -> TrumanPlayer:
	return controller.player if controller != null else null

func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return result.is_empty() or result.get("collider") == get_player_target()

func find_floor_y(position: Vector3, max_depth: int = 10) -> int:
	return controller.find_floor_y(position, max_depth)

func is_rabbit_step_safe(from: Vector3, to: Vector3) -> bool:
	return controller.is_rabbit_step_safe(from, to)

func _try_spawn_ghost() -> void:
	if not special_spawn_points.is_empty() and randf() < 0.2:
		var special: Vector3 = special_spawn_points.pick_random()
		if _valid_common_spawn(special) and _is_air_column(Vector3i(floori(special.x), floori(special.y), floori(special.z))):
			_spawn_ghost(special)
			return
	for _attempt in range(18):
		var point: Vector2i = _random_horizontal_point()
		var position: Vector3
		if controller.is_night() and randf() < 0.55:
			var surface_y: int = voxel_world.get_surface_height(point.x, point.y, 0)
			position = Vector3(point.x, surface_y + 1.7, point.y)
		else:
			var surface_y: int = voxel_world.get_surface_height(point.x, point.y, 0)
			var cave_y: int = randi_range(WORLD_MIN_Y + 2, surface_y - 4)
			var floor_y: int = _find_cave_floor(point.x, point.y, cave_y)
			if floor_y <= WORLD_MIN_Y:
				continue
			position = Vector3(point.x, floor_y + 1.7, point.y)
		if _valid_common_spawn(position):
			_spawn_ghost(position)
			return

func _try_spawn_rabbit() -> void:
	if controller.is_night():
		return
	for _attempt in range(10):
		var point: Vector2i = _random_horizontal_point()
		var surface_y: int = voxel_world.get_surface_height(point.x, point.y, 0)
		var block_pos := Vector3i(point.x, surface_y, point.y)
		var position := Vector3(point.x, surface_y + 0.55, point.y)
		if voxel_world.get_block_id(block_pos) not in ["grass", "dirt"]:
			continue
		if not controller.has_sky_access(block_pos + Vector3i.UP) or not _valid_common_spawn(position, false):
			continue
		var rabbit = RabbitScript.new()
		rabbit.configure(self, "rabbit", 5.0)
		add_child(rabbit)
		rabbit.global_position = position
		rabbits.append(rabbit)
		return

func _spawn_ghost(position: Vector3) -> void:
	var ghost = GhostScript.new()
	ghost.configure(self, "ghost", 20.0)
	add_child(ghost)
	ghost.global_position = position
	ghosts.append(ghost)

func _random_horizontal_point() -> Vector2i:
	var player_position: Vector3 = get_player_target().global_position
	var angle: float = randf() * TAU
	var distance: float = randf_range(MIN_SPAWN_DISTANCE, MAX_SPAWN_DISTANCE)
	return Vector2i(
		clampi(floori(player_position.x + cos(angle) * distance), 1, 98),
		clampi(floori(player_position.z + sin(angle) * distance), 1, 98)
	)

func _valid_common_spawn(position: Vector3, require_dark: bool = true) -> bool:
	var player_target := get_player_target()
	if player_target == null or position.distance_to(player_target.global_position) < MIN_SPAWN_DISTANCE:
		return false
	if controller.is_spawn_position_visible(position):
		return false
	if require_dark and light_registry != null and light_registry.is_spawn_blocked(position):
		return false
	return _is_air_column(Vector3i(floori(position.x), floori(position.y), floori(position.z)))

func _is_air_column(pos: Vector3i) -> bool:
	return voxel_world.is_inside_unlocked_biome(pos) and not voxel_world.has_block(pos) and not voxel_world.has_block(pos + Vector3i.UP)

func _find_cave_floor(x: int, z: int, start_y: int) -> int:
	for y in range(start_y, WORLD_MIN_Y, -1):
		var floor_pos := Vector3i(x, y, z)
		if voxel_world.has_block(floor_pos) and _is_air_column(floor_pos + Vector3i.UP):
			return y
	return WORLD_MIN_Y

func _prune_entities() -> void:
	ghosts = ghosts.filter(func(value): return is_instance_valid(value) and not value.is_queued_for_deletion())
	rabbits = rabbits.filter(func(value): return is_instance_valid(value) and not value.is_queued_for_deletion())
