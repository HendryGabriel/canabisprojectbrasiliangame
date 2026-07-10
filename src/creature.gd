extends CharacterBody3D
class_name Creature

signal state_changed(state: String)
signal died(creature)

var creature_id: String = "creature"
var max_health: float = 1.0
var health: float = 1.0
var controller: Node = null
var collision_radius: float = 0.35
var collision_height: float = 1.0
var current_state: String = "idle"
var visual_root: Node3D = null
var dead: bool = false

func _ready() -> void:
	add_to_group("creature")
	collision_layer = 2
	collision_mask = 1
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = collision_radius
	capsule.height = maxf(collision_height, collision_radius * 2.0)
	collision.shape = capsule
	collision.position.y = collision_height * 0.5
	add_child(collision)
	visual_root = Node3D.new()
	visual_root.name = "VisualRoot"
	add_child(visual_root)
	_build_visual()
	set_state("idle")

func configure(p_controller: Node, id: String, p_health: float) -> void:
	controller = p_controller
	creature_id = id
	max_health = p_health
	health = p_health

func take_damage(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	set_state("hurt")
	if health <= 0.0:
		_die()

func set_state(next_state: String) -> void:
	if current_state == next_state:
		return
	current_state = next_state
	state_changed.emit(current_state)

func _die() -> void:
	dead = true
	velocity = Vector3.ZERO
	set_physics_process(false)
	set_state("death")
	died.emit(self)
	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(self):
		queue_free()

func _build_visual() -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = collision_radius
	mesh.height = collision_height
	mesh_instance.mesh = mesh
	mesh_instance.position.y = collision_height * 0.5
	visual_root.add_child(mesh_instance)
