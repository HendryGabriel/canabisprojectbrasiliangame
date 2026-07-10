extends CharacterBody3D
class_name TrumanPlayer

signal health_changed(current: float, maximum: float)
signal died

const FIRST_PERSON_RIG_SCENE: PackedScene = preload("res://scenes/first_person_view_rig.tscn")
const PLAYER_BODY_RIG_SCENE: PackedScene = preload("res://scenes/player_body_rig.tscn")

@export var walk_speed: float = 4.5
@export var run_speed: float = 7.0
@export var jump_velocity: float = 6.8
@export var mouse_sensitivity: float = 0.0025
@export var block_reach: float = 4.0
@export var third_person_distance: float = 4.0
@export var creative_flight: bool = false
@export var creative_flight_speed: float = 12.0
@export var max_health: float = 20.0

var gravity: float = 18.0
var controls_enabled: bool = true
var yaw: float = 0.0
var pitch: float = 0.0
var camera_mode: int = 0
var camera: Camera3D
var ray: RayCast3D
var first_person_rig: Node
var body_rig: Node
var visuals_enabled: bool = false
var eye_height: float = 1.55
var pending_skin_texture: Texture2D
var pending_item_id: String = ""
var pending_item_icon: Texture2D
var pending_item_block_mesh: Mesh
var pending_item_cube_faces: Dictionary = {}

var was_on_floor: bool = true
var prev_vel_y: float = 0.0
var landing_bob: float = 0.0

var collision_shape_node: CollisionShape3D = null
var health: float = 20.0
var dead: bool = false

func _ready() -> void:
	health = clampf(health, 0.0, max_health)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	camera.position = Vector3(0, 1.55, 0)
	add_child(camera)

	first_person_rig = FIRST_PERSON_RIG_SCENE.instantiate()
	camera.add_child(first_person_rig)

	body_rig = PLAYER_BODY_RIG_SCENE.instantiate()
	add_child(body_rig)

	ray = RayCast3D.new()
	ray.name = "BlockRay"
	ray.target_position = Vector3(0, 0, -block_reach)
	ray.enabled = true
	ray.add_exception(self)
	camera.add_child(ray)

	var shape: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.35
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)
	collision_shape_node = shape
	_update_camera_transform(0.0, 1.55)
	if pending_skin_texture != null:
		_apply_skin_to_rigs(pending_skin_texture)
	_apply_held_item_to_rig()
	health_changed.emit(health, max_health)

func take_damage(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		dead = true
		controls_enabled = false
		died.emit()

func restore_health(value: float = -1.0) -> void:
	dead = false
	health = max_health if value < 0.0 else clampf(value, 0.0, max_health)
	health_changed.emit(health, max_health)

func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, deg_to_rad(-88), deg_to_rad(88))
		rotation.y = yaw
		_update_camera_transform(0.0)

func _physics_process(delta: float) -> void:
	if creative_flight:
		_physics_process_creative(delta)
		return
	var main_game = get_parent()
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Detect landing event to calculate impact bob
	var landed: bool = is_on_floor() and not was_on_floor
	if landed:
		var impact_speed: float = abs(prev_vel_y)
		if impact_speed > 2.0:
			landing_bob = clamp(impact_speed * 0.03, 0.0, 0.22)
	
	was_on_floor = is_on_floor()
	
	# Smoothly decay camera landing bob
	landing_bob = move_toward(landing_bob, 0.0, delta * 1.5)

	var input_dir: Vector2 = Vector2.ZERO
	var is_crouching: bool = false
	var is_sprinting: bool = false
	var speed: float = walk_speed
	
	if controls_enabled:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		
		# Shift key to crouch (Minecraft crouch has priority over sprint)
		if Input.is_key_pressed(KEY_SHIFT):
			is_crouching = true
			speed = walk_speed * 0.3
		
		if not is_crouching:
			# CTRL key for sprinting (only when moving forward)
			if Input.is_key_pressed(KEY_CTRL) and input_dir.y < -0.1:
				is_sprinting = true
				speed = run_speed

		if Input.is_action_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity
			if is_sprinting:
				# Forward boost for sprint jump
				var forward_dir = -global_transform.basis.z
				forward_dir.y = 0
				forward_dir = forward_dir.normalized()
				velocity.x += forward_dir.x * 1.5
				velocity.z += forward_dir.z * 1.5

	# Update collision capsule height based on crouch state
	if collision_shape_node != null and collision_shape_node.shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = collision_shape_node.shape
		if is_crouching:
			capsule.height = 1.5
			collision_shape_node.position.y = 0.75
		else:
			capsule.height = 1.8
			collision_shape_node.position.y = 0.9

	# Interpolate camera height smoothly
	var camera_target_y: float = 1.25 if is_crouching else 1.55
	if camera != null:
		_update_camera_transform(delta, camera_target_y - landing_bob)

	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if is_on_floor():
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		# Air drag (0.98 multiplier) + air steering drift acceleration
		velocity.x *= 0.98
		velocity.z *= 0.98
		if direction != Vector3.ZERO:
			velocity.x += direction.x * speed * delta * 2.2
			velocity.z += direction.z * speed * delta * 2.2
			# Cap maximum horizontal air speed
			var speed_2d = Vector2(velocity.x, velocity.z).length()
			var max_cap = max(speed, run_speed) # Sprint speed cap
			if speed_2d > max_cap:
				var capped = Vector2(velocity.x, velocity.z).normalized() * max_cap
				velocity.x = capped.x
				velocity.z = capped.y

	# Edge protection when crouching
	if is_crouching and is_on_floor():
		var next_pos: Vector3 = global_position + velocity * delta
		if main_game != null and main_game.has_method("_is_solid_block_at"):
			var y_check: int = int(floor(global_position.y - 0.1))
			
			var radius_check: float = 0.3
			var offsets = [
				Vector3.ZERO,
				Vector3(-radius_check, 0, -radius_check),
				Vector3(radius_check, 0, -radius_check),
				Vector3(-radius_check, 0, radius_check),
				Vector3(radius_check, 0, radius_check)
			]
			
			# Check X movement alone
			var has_x_support: bool = false
			var next_x_pos = Vector3(next_pos.x, global_position.y, global_position.z)
			for offset in offsets:
				var check_pt = next_x_pos + offset
				var bx = int(floor(check_pt.x))
				var bz = int(floor(check_pt.z))
				var block_pos = Vector3i(bx, y_check, bz)
				if main_game.has_method("_is_solid_block_at") and main_game._is_solid_block_at(block_pos):
					has_x_support = true
					break
			if not has_x_support:
				velocity.x = 0.0
				
			# Check Z movement alone
			var has_z_support: bool = false
			var next_z_pos = Vector3(global_position.x, global_position.y, next_pos.z)
			for offset in offsets:
				var check_pt = next_z_pos + offset
				var bx = int(floor(check_pt.x))
				var bz = int(floor(check_pt.z))
				var block_pos = Vector3i(bx, y_check, bz)
				if main_game.has_method("_is_solid_block_at") and main_game._is_solid_block_at(block_pos):
					has_z_support = true
					break
			if not has_z_support:
				velocity.z = 0.0

	prev_vel_y = velocity.y
	move_and_slide()


func _physics_process_creative(delta: float) -> void:
	if not controls_enabled:
		velocity = Vector3.ZERO
		_update_camera_transform(delta, eye_height)
		return
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var horizontal: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var vertical: float = float(Input.is_key_pressed(KEY_SPACE)) - float(Input.is_key_pressed(KEY_CTRL))
	var movement: Vector3 = horizontal + Vector3.UP * vertical
	if movement.length_squared() > 1.0:
		movement = movement.normalized()
	var speed: float = creative_flight_speed * (2.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	velocity = movement * speed
	move_and_slide()
	_update_camera_transform(delta, eye_height)

func get_block_raycast() -> RayCast3D:
	return ray

func get_interaction_ray_start() -> Vector3:
	return global_position + Vector3(0, eye_height, 0)

func get_interaction_ray_end() -> Vector3:
	return get_interaction_ray_start() + get_aim_direction() * block_reach

func get_aim_direction() -> Vector3:
	var yaw_basis: Basis = Basis(Vector3.UP, yaw)
	var forward: Vector3 = yaw_basis * Vector3(0, 0, -1)
	var right: Vector3 = yaw_basis * Vector3.RIGHT
	return forward.rotated(right, pitch).normalized()

func get_camera_pitch() -> float:
	return pitch

func get_camera_yaw() -> float:
	return yaw

func set_view_angles(yaw_value: float, pitch_value: float) -> void:
	yaw = yaw_value
	rotation.y = yaw
	set_camera_pitch(pitch_value)

func set_camera_pitch(value: float) -> void:
	pitch = clamp(value, deg_to_rad(-88), deg_to_rad(88))
	_update_camera_transform(0.0)

func set_controls_enabled(value: bool) -> void:
	controls_enabled = value
	if not value:
		velocity = Vector3.ZERO

func toggle_camera_mode() -> int:
	camera_mode = (camera_mode + 1) % 3
	_update_camera_transform(0.0)
	return camera_mode

func set_camera_mode(value: int) -> void:
	camera_mode = clamp(value, 0, 2)
	_update_camera_transform(0.0)

func get_camera_mode() -> int:
	return camera_mode

func apply_skin(texture: Texture2D) -> void:
	pending_skin_texture = texture
	_apply_skin_to_rigs(texture)

func _apply_skin_to_rigs(texture: Texture2D) -> void:
	if first_person_rig != null:
		first_person_rig.apply_skin(texture)
	if body_rig != null:
		body_rig.apply_skin(texture)

func set_held_item(item_id: String, icon: Texture2D, block_mesh: Mesh, cube_faces: Dictionary = {}) -> void:
	pending_item_id = item_id
	pending_item_icon = icon
	pending_item_block_mesh = block_mesh
	pending_item_cube_faces = cube_faces
	_apply_held_item_to_rig()

func _apply_held_item_to_rig() -> void:
	if first_person_rig != null:
		first_person_rig.set_selected_item(pending_item_id, pending_item_icon, pending_item_block_mesh, pending_item_cube_faces)
	if body_rig != null and body_rig.has_method("set_selected_item"):
		body_rig.set_selected_item(pending_item_id, pending_item_icon, pending_item_block_mesh, pending_item_cube_faces)

func play_mine_swing(progress: float) -> void:
	if first_person_rig != null:
		first_person_rig.play_mine_swing(progress)
	if body_rig != null and body_rig.has_method("play_swing"):
		body_rig.play_swing()

func play_place_swing() -> void:
	if first_person_rig != null:
		first_person_rig.play_place_swing()
	if body_rig != null and body_rig.has_method("play_swing"):
		body_rig.play_swing()

func play_attack_swing() -> void:
	play_place_swing()

func play_drop_swing() -> void:
	if first_person_rig != null:
		first_person_rig.play_drop_swing()
	if body_rig != null and body_rig.has_method("play_swing"):
		body_rig.play_swing()

func play_break_finish() -> void:
	if first_person_rig != null:
		first_person_rig.play_break_finish()
	if body_rig != null and body_rig.has_method("play_swing"):
		body_rig.play_swing()

func set_visuals_visible(value: bool) -> void:
	visuals_enabled = value
	if first_person_rig != null:
		first_person_rig.set_hud_visible(value and camera_mode == 0)
	if body_rig != null:
		body_rig.visible = value and camera_mode != 0

func _update_camera_transform(delta: float, target_height: float = -1.0) -> void:
	if camera == null:
		return
	var height: float = target_height
	if height < 0.0:
		height = eye_height
	eye_height = clamp(height, 1.15, 1.8)
	if camera_mode == 0:
		var target_pos: Vector3 = Vector3(0, height, 0)
		camera.position = target_pos if delta <= 0.0 else camera.position.lerp(target_pos, delta * 12.0)
		camera.rotation = Vector3(pitch, 0, 0)
	else:
		var look_target: Vector3 = global_position + Vector3(0, height + 0.06, 0)
		var aim_direction: Vector3 = get_aim_direction()
		var camera_direction: Vector3 = -aim_direction if camera_mode == 1 else aim_direction
		var distance: float = _safe_third_person_distance(look_target, camera_direction)
		var desired_global_pos: Vector3 = look_target + camera_direction * distance
		if delta <= 0.0:
			camera.global_position = desired_global_pos
		else:
			camera.global_position = camera.global_position.lerp(desired_global_pos, delta * 14.0)
		camera.look_at(look_target, Vector3.UP)
	if first_person_rig != null:
		first_person_rig.visible = visuals_enabled and camera_mode == 0
	if body_rig != null:
		body_rig.visible = visuals_enabled and camera_mode != 0

func _safe_third_person_distance(look_target: Vector3, camera_direction: Vector3) -> float:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = look_target
	var to: Vector3 = look_target + camera_direction.normalized() * third_person_distance
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return third_person_distance
	var hit_pos: Vector3 = result.get("position", to)
	return clamp(from.distance_to(hit_pos) - 0.25, 0.75, third_person_distance)
