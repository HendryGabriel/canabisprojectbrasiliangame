extends Node3D
class_name PlayerBodyRig

var skin_texture: Texture2D
var head: Node3D
var body: Node3D
var right_arm: Node3D
var left_arm: Node3D
var right_leg: Node3D
var left_leg: Node3D
var walk_time: float = 0.0
var swing_time: float = 0.0
var current_item_visual: Node3D = null

func _ready() -> void:
	_create_body()
	apply_skin(skin_texture if skin_texture != null else SkinLoader.default_skin_texture())

func _process(delta: float) -> void:
	var parent_body: CharacterBody3D = get_parent() as CharacterBody3D
	var speed: float = 0.0
	if parent_body != null:
		speed = Vector2(parent_body.velocity.x, parent_body.velocity.z).length()
	if speed > 0.08:
		walk_time += delta * speed * 2.8
	var stride: float = sin(walk_time) * clamp(speed / 4.5, 0.0, 1.0)
	var arm_swing: float = 0.0
	if swing_time > 0.0:
		swing_time = max(0.0, swing_time - delta)
		var swing_phase = 1.0 - (swing_time / 0.22)
		arm_swing = sin(swing_phase * PI) * 0.6

	if right_arm != null:
		right_arm.rotation.x = deg_to_rad(8.0 + stride * 24.0) + arm_swing
	if left_arm != null:
		left_arm.rotation.x = deg_to_rad(8.0 - stride * 24.0)
	if right_leg != null:
		right_leg.rotation.x = deg_to_rad(-stride * 28.0)
	if left_leg != null:
		left_leg.rotation.x = deg_to_rad(stride * 28.0)
		
	if parent_body != null and "pitch" in parent_body:
		if head != null:
			head.rotation.x = parent_body.pitch

func play_swing() -> void:
	if swing_time <= 0.0:
		swing_time = 0.22

func set_selected_item(p_item_id: String, p_icon: Texture2D, p_block_mesh: Mesh, p_cube_faces: Dictionary = {}) -> void:
	if current_item_visual != null:
		current_item_visual.queue_free()
		current_item_visual = null
	
	if p_item_id == "" or right_arm == null:
		return
		
	if p_block_mesh != null or p_cube_faces.size() > 0:
		var block = MeshInstance3D.new()
		if p_block_mesh != null:
			block.mesh = p_block_mesh
		block.scale = Vector3(0.2, 0.2, 0.2)
		block.position = Vector3(0.0, -0.75, -0.15)
		block.rotation_degrees = Vector3(0, 45, 0)
		right_arm.add_child(block)
		current_item_visual = block
	else:
		var pivot = Node3D.new()
		pivot.name = "ItemPivot"
		pivot.position = Vector3(0.0, -0.75, 0.0)
		
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.mesh = _build_extruded_icon_mesh(p_icon)
		# Offset the mesh so the handle (bottom-left) is at the pivot center
		mesh_instance.position = Vector3(0.35, 0.35, 0.0)
		pivot.add_child(mesh_instance)
		
		pivot.scale = Vector3(0.7, 0.7, 0.7)
		pivot.rotation_degrees = Vector3(0, -90, 115)
		
		right_arm.add_child(pivot)
		current_item_visual = pivot

func apply_skin(texture: Texture2D) -> void:
	skin_texture = texture if texture != null else SkinLoader.default_skin_texture()
	_apply_part_material(head, SkinLoader.head_uvs(), Vector3(0.50, 0.50, 0.50))
	_apply_part_material(body, SkinLoader.body_uvs(), Vector3(0.50, 0.75, 0.25))
	_apply_part_material(right_arm, SkinLoader.right_arm_uvs(), Vector3(0.25, 0.75, 0.25))
	_apply_part_material(left_arm, SkinLoader.left_arm_uvs(), Vector3(0.25, 0.75, 0.25))
	_apply_part_material(right_leg, SkinLoader.right_leg_uvs(), Vector3(0.25, 0.75, 0.25))
	_apply_part_material(left_leg, SkinLoader.left_leg_uvs(), Vector3(0.25, 0.75, 0.25))
	
	if head != null:
		var hat: MeshInstance3D = head.get_node_or_null("Hat")
		if hat != null:
			hat.mesh = SkinLoader.make_skin_box_mesh(Vector3(0.50, 0.50, 0.50), SkinLoader.hat_uvs())
			var hat_mat: StandardMaterial3D = SkinLoader.skin_material(skin_texture, SkinLoader.hat_uvs())
			hat_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			hat.material_override = hat_mat

func set_first_person_hidden(hidden: bool) -> void:
	visible = not hidden

func _create_body() -> void:
	head = _add_part("Head", Vector3(0.50, 0.50, 0.50), Vector3(0.0, 1.50, 0.0), Vector3(0.0, 0.25, 0.0))
	
	var hat_mesh: MeshInstance3D = MeshInstance3D.new()
	hat_mesh.name = "Hat"
	hat_mesh.position = Vector3(0.0, 0.25, 0.0)
	hat_mesh.scale = Vector3(1.125, 1.125, 1.125)
	head.add_child(hat_mesh)
	
	body = _add_part("Body", Vector3(0.50, 0.75, 0.25), Vector3(0.0, 1.125, 0.0), Vector3.ZERO)
	right_arm = _add_part("RightArm", Vector3(0.25, 0.75, 0.25), Vector3(-0.375, 1.50, 0.0), Vector3(0.0, -0.375, 0.0))
	left_arm = _add_part("LeftArm", Vector3(0.25, 0.75, 0.25), Vector3(0.375, 1.50, 0.0), Vector3(0.0, -0.375, 0.0))
	right_leg = _add_part("RightLeg", Vector3(0.25, 0.75, 0.25), Vector3(-0.125, 0.75, 0.0), Vector3(0.0, -0.375, 0.0))
	left_leg = _add_part("LeftLeg", Vector3(0.25, 0.75, 0.25), Vector3(0.125, 0.75, 0.0), Vector3(0.0, -0.375, 0.0))

func _add_part(part_name: String, _size: Vector3, part_position: Vector3, mesh_offset: Vector3) -> Node3D:
	var pivot: Node3D = Node3D.new()
	pivot.name = part_name
	pivot.position = part_position
	add_child(pivot)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.position = mesh_offset
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pivot.add_child(mesh_instance)
	return pivot

func _apply_part_material(part: Node3D, uvs: Dictionary, size: Vector3) -> void:
	if part == null:
		return
	var mesh_instance: MeshInstance3D = part.get_node_or_null("Mesh") as MeshInstance3D
	if mesh_instance == null:
		return
	mesh_instance.mesh = SkinLoader.make_skin_box_mesh(size, uvs)
	mesh_instance.material_override = SkinLoader.skin_material(skin_texture, uvs)

func _build_extruded_icon_mesh(texture: Texture2D) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	if texture == null:
		return mesh
	var image: Image = texture.get_image()
	if image == null:
		return mesh
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var width: int = image.get_width()
	var height: int = image.get_height()
	if width <= 0 or height <= 0:
		return mesh
	var unit: float = 1.0 / float(max(width, height))
	var depth: float = unit
	var half_w: float = float(width) * unit * 0.5
	var half_h: float = float(height) * unit * 0.5

	for y in range(height):
		for x in range(width):
			var color: Color = image.get_pixel(x, y)
			if color.a < 0.1:
				continue
			var left: float = float(x) * unit - half_w
			var right: float = left + unit
			var top: float = half_h - float(y) * unit
			var bottom: float = top - unit
			var front_z: float = -depth * 0.5
			var back_z: float = depth * 0.5

			_add_icon_quad(vertices, normals, colors, indices, [
				Vector3(left, bottom, front_z),
				Vector3(right, bottom, front_z),
				Vector3(right, top, front_z),
				Vector3(left, top, front_z)
			], Vector3(0, 0, 1), color)
			_add_icon_quad(vertices, normals, colors, indices, [
				Vector3(right, bottom, back_z),
				Vector3(left, bottom, back_z),
				Vector3(left, top, back_z),
				Vector3(right, top, back_z)
			], Vector3(0, 0, -1), color)

			if _is_icon_edge(image, x - 1, y):
				_add_icon_quad(vertices, normals, colors, indices, [
					Vector3(left, bottom, back_z),
					Vector3(left, bottom, front_z),
					Vector3(left, top, front_z),
					Vector3(left, top, back_z)
				], Vector3(-1, 0, 0), color)
			if _is_icon_edge(image, x + 1, y):
				_add_icon_quad(vertices, normals, colors, indices, [
					Vector3(right, bottom, front_z),
					Vector3(right, bottom, back_z),
					Vector3(right, top, back_z),
					Vector3(right, top, front_z)
				], Vector3(1, 0, 0), color)
			if _is_icon_edge(image, x, y - 1):
				_add_icon_quad(vertices, normals, colors, indices, [
					Vector3(left, top, front_z),
					Vector3(right, top, front_z),
					Vector3(right, top, back_z),
					Vector3(left, top, back_z)
				], Vector3(0, 1, 0), color)
			if _is_icon_edge(image, x, y + 1):
				_add_icon_quad(vertices, normals, colors, indices, [
					Vector3(left, bottom, back_z),
					Vector3(right, bottom, back_z),
					Vector3(right, bottom, front_z),
					Vector3(left, bottom, front_z)
				], Vector3(0, -1, 0), color)

	if vertices.size() <= 0:
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mesh.surface_set_material(0, material)
	return mesh

func _add_icon_quad(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	points: Array,
	normal: Vector3,
	color: Color
) -> void:
	var start: int = vertices.size()
	for point in points:
		var vertex: Vector3 = point
		vertices.append(vertex)
		normals.append(normal)
		colors.append(color)
	indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))

func _is_icon_edge(image: Image, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return true
	return image.get_pixel(x, y).a < 0.1
