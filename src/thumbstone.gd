extends StaticBody3D
class_name Thumbstone

var thumbstone_id: String = ""
var contents: Array = []
var controller: Node = null
var collecting: bool = false

func configure(p_controller: Node, id: String, slots: Array, p_position: Vector3) -> void:
	controller = p_controller
	thumbstone_id = id
	contents = slots.duplicate(true)
	position = p_position

func _ready() -> void:
	add_to_group("thumbstone")
	collision_layer = 2
	collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.85, 1.25, 0.35)
	collision.shape = shape
	collision.position.y = 0.625
	add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	visual.mesh = mesh
	visual.position = collision.position
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.25, 0.28)
	visual.material_override = material
	add_child(visual)

func collect() -> void:
	if collecting or controller == null:
		return
	collecting = true
	controller.collect_thumbstone(self)
	collecting = false

func to_data() -> Dictionary:
	return {
		"id": thumbstone_id,
		"position": [global_position.x, global_position.y, global_position.z],
		"contents": contents.duplicate(true),
	}
