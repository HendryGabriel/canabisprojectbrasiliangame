extends "res://src/creature.gd"
class_name Rabbit

const SPEED: float = 1.7
const GRAVITY: float = 18.0

var move_direction: Vector3 = Vector3.FORWARD
var decision_timer: float = 0.0
var hop_timer: float = 0.0

func _ready() -> void:
	collision_radius = 0.28
	collision_height = 0.65
	super._ready()

func _physics_process(delta: float) -> void:
	if dead or controller == null:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	decision_timer -= delta
	hop_timer -= delta
	if decision_timer <= 0.0:
		_choose_direction()
	var next_position: Vector3 = global_position + move_direction * 0.75
	if not controller.is_rabbit_step_safe(global_position, next_position):
		_choose_direction(true)
	velocity.x = move_direction.x * SPEED
	velocity.z = move_direction.z * SPEED
	if is_on_floor() and hop_timer <= 0.0:
		velocity.y = 3.6
		hop_timer = randf_range(1.0, 2.2)
	set_state("move" if Vector2(velocity.x, velocity.z).length_squared() > 0.01 else "idle")
	move_and_slide()

func _choose_direction(reverse: bool = false) -> void:
	var angle: float = atan2(move_direction.z, move_direction.x) + (PI if reverse else randf_range(-1.8, 1.8))
	move_direction = Vector3(cos(angle), 0.0, sin(angle)).normalized()
	decision_timer = randf_range(1.5, 4.0)

func _build_visual() -> void:
	_add_box(Vector3(0.65, 0.45, 0.85), Vector3(0.0, 0.35, 0.0), Color(0.72, 0.56, 0.42))
	_add_box(Vector3(0.42, 0.38, 0.42), Vector3(0.0, 0.62, -0.42), Color(0.78, 0.62, 0.48))
	_add_box(Vector3(0.12, 0.45, 0.12), Vector3(-0.12, 0.98, -0.42), Color(0.78, 0.62, 0.48))
	_add_box(Vector3(0.12, 0.45, 0.12), Vector3(0.12, 0.98, -0.42), Color(0.78, 0.62, 0.48))

func _add_box(size: Vector3, position: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.material_override = material
	visual_root.add_child(node)
