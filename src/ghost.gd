extends "res://src/creature.gd"
class_name Ghost

const SPEED: float = 2.8
const DETECTION_RANGE: float = 14.0
const ATTACK_RANGE: float = 1.55
const ATTACK_DAMAGE: float = 2.0
const ATTACK_INTERVAL: float = 1.0

var target: TrumanPlayer = null
var wander_direction: Vector3 = Vector3.FORWARD
var decision_timer: float = 0.0
var attack_timer: float = 0.0

func _ready() -> void:
	collision_radius = 0.42
	collision_height = 1.25
	super._ready()

func _physics_process(delta: float) -> void:
	if dead or controller == null:
		return
	attack_timer = maxf(0.0, attack_timer - delta)
	decision_timer -= delta
	if target == null or not is_instance_valid(target) or target.dead or global_position.distance_to(target.global_position) > DETECTION_RANGE * 1.5:
		target = null
	if target == null and controller.has_method("get_player_target"):
		var candidate = controller.get_player_target()
		if candidate != null and global_position.distance_to(candidate.global_position) <= DETECTION_RANGE and controller.has_line_of_sight(global_position + Vector3.UP * 0.7, candidate.global_position + Vector3.UP):
			target = candidate
	if target != null:
		_chase_target(delta)
	else:
		_wander(delta)
	move_and_slide()

func _chase_target(delta: float) -> void:
	var offset: Vector3 = target.global_position + Vector3.UP - global_position
	var distance: float = offset.length()
	if distance <= ATTACK_RANGE:
		velocity = velocity.move_toward(Vector3.ZERO, delta * 12.0)
		set_state("attack")
		if attack_timer <= 0.0:
			target.take_damage(ATTACK_DAMAGE)
			attack_timer = ATTACK_INTERVAL
		return
	set_state("move")
	var direction: Vector3 = offset.normalized()
	var floor_y: int = controller.find_floor_y(global_position, 10)
	var desired_y: float = float(floor_y) + 1.7 if floor_y > -999 else target.global_position.y + 1.0
	direction.y = clampf((desired_y - global_position.y) * 0.7, -0.6, 0.6)
	velocity = direction.normalized() * SPEED
	look_at(global_position + Vector3(direction.x, 0.0, direction.z), Vector3.UP)

func _wander(_delta: float) -> void:
	set_state("move")
	if decision_timer <= 0.0 or get_slide_collision_count() > 0:
		var angle: float = randf() * TAU
		wander_direction = Vector3(cos(angle), 0.0, sin(angle))
		decision_timer = randf_range(1.5, 4.0)
	var floor_y: int = controller.find_floor_y(global_position, 10)
	var desired_y: float = float(floor_y) + 1.7 if floor_y > -999 else global_position.y
	wander_direction.y = clampf((desired_y - global_position.y) * 0.6, -0.45, 0.45)
	velocity = wander_direction.normalized() * SPEED * 0.55

func _build_visual() -> void:
	var body := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.55
	mesh.height = 1.25
	body.mesh = mesh
	body.position.y = 0.65
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.85, 1.0, 0.72)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body.material_override = material
	visual_root.add_child(body)
