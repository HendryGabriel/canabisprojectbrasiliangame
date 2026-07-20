extends Node3D
class_name FirstPersonViewRig

const BASE_POSITION: Vector3 = Vector3(0.58, -0.52, -0.86)
const HIDDEN_POSITION: Vector3 = Vector3(0.76, -0.92, -0.96)

var skin_texture: Texture2D
var item_id: String = ""
var item_icon: Texture2D
var item_block_mesh: Mesh
var item_cube_faces: Dictionary = {}

var arm_root: Node3D
var arm_mesh: MeshInstance3D
var item_root: Node3D
var current_item_visual: Node3D

var swing_time: float = 0.0
var swing_duration: float = 0.28
var swing_strength: float = 0.0
var mine_loop_time: float = 0.0
var swap_time: float = 0.0
var idle_time: float = 0.0

func _ready() -> void:
	_create_nodes()
	apply_skin(skin_texture if skin_texture != null else SkinLoader.default_skin_texture())
	set_selected_item(item_id, item_icon, item_block_mesh, item_cube_faces)

func _process(delta: float) -> void:
	idle_time += delta
	if swing_time > 0.0:
		swing_time = max(0.0, swing_time - delta)
	if swap_time > 0.0:
		swap_time = max(0.0, swap_time - delta)
	_update_pose(delta)

func apply_skin(texture: Texture2D) -> void:
	skin_texture = texture if texture != null else SkinLoader.default_skin_texture()
	if arm_mesh != null:
		arm_mesh.mesh = SkinLoader.make_skin_box_mesh(Vector3(0.22, 0.72, 0.22), SkinLoader.right_arm_uvs())
		var mat: StandardMaterial3D = SkinLoader.skin_material(skin_texture, SkinLoader.right_arm_uvs())
		_make_material_overlay(mat)
		arm_mesh.material_override = mat

func set_selected_item(p_item_id: String, p_icon: Texture2D, p_block_mesh: Mesh, p_cube_faces: Dictionary = {}) -> void:
	item_id = p_item_id
	item_icon = p_icon
	item_block_mesh = p_block_mesh
	item_cube_faces = p_cube_faces
	swap_time = 0.16
	if item_root != null:
		_rebuild_item_visual()

func play_mine_swing(progress: float) -> void:
	mine_loop_time += 0.12
	if swing_time <= 0.0:
		_start_swing(0.22, 0.72)
	swing_strength = max(swing_strength, clamp(progress, 0.15, 1.0))

func play_place_swing() -> void:
	_start_swing(0.20, 1.0)

func play_drop_swing() -> void:
	_start_swing(0.26, 1.15)

func play_break_finish() -> void:
	_start_swing(0.20, 0.85)

func set_hud_visible(value: bool) -> void:
	visible = value

func _create_nodes() -> void:
	arm_root = Node3D.new()
	arm_root.name = "ArmRoot"
	add_child(arm_root)

	arm_mesh = MeshInstance3D.new()
	arm_mesh.name = "RightArm"
	arm_mesh.position = Vector3(0.0, -0.12, 0.0)
	arm_mesh.rotation_degrees = Vector3(-16, 0, 8)
	arm_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arm_root.add_child(arm_mesh)

	item_root = Node3D.new()
	item_root.name = "HeldItemRoot"
	item_root.position = Vector3(-0.08, -0.18, -0.18)
	item_root.rotation_degrees = Vector3(-18, -32, 10)
	arm_root.add_child(item_root)

	position = BASE_POSITION
	rotation_degrees = Vector3(-4, -7, 0)

func _start_swing(duration: float, strength: float) -> void:
	swing_duration = duration
	swing_time = duration
	swing_strength = strength

func _update_pose(delta: float) -> void:
	var idle_bob: float = sin(idle_time * 1.8) * 0.018
	var swap_offset: float = 0.0
	if swap_time > 0.0:
		swap_offset = sin((swap_time / 0.16) * PI) * -0.24

	var swing_phase: float = 0.0
	if swing_duration > 0.0 and swing_time > 0.0:
		swing_phase = 1.0 - (swing_time / swing_duration)
	var swing: float = sin(swing_phase * PI)
	var swing_twist: float = sin(swing_phase * TAU)
	if item_id == "":
		var target_pos: Vector3 = BASE_POSITION + Vector3(
			-swing * 0.16 * swing_strength,
			idle_bob - swing * 0.18 * swing_strength + swap_offset,
			-swing * 0.08 * swing_strength
		)
		position = position.lerp(target_pos, delta * 18.0)

		rotation_degrees = Vector3(
			-4.0 - swing * 42.0 * swing_strength,
			-7.0 + swing_twist * 20.0 * swing_strength,
			swing * 18.0 * swing_strength
		)
	else:
		var target_pos: Vector3 = BASE_POSITION + Vector3(
			-swing * 0.40 * swing_strength,
			idle_bob + swing * 0.20 * swing_strength + swap_offset,
			-swing * 1.30 * swing_strength
		)
		position = target_pos

		rotation_degrees = Vector3(
			-4.0 - swing * 25.0 * swing_strength,
			-7.0 - swing * 15.0 * swing_strength,
			swing * 25.0 * swing_strength
		)
	if swing_time <= 0.0:
		swing_strength = move_toward(swing_strength, 0.0, delta * 5.0)

func _rebuild_item_visual() -> void:
	for child in item_root.get_children():
		item_root.remove_child(child)
		child.queue_free()
	current_item_visual = null
	if arm_mesh != null:
		arm_mesh.visible = item_id == ""
	if item_id == "":
		return
	if item_block_mesh != null and item_cube_faces.is_empty():
		var pattern: MeshInstance3D = MeshInstance3D.new()
		pattern.mesh = item_block_mesh
		pattern.scale = Vector3(0.32, 0.32, 0.32)
		pattern.rotation_degrees = Vector3(18, 36, 0)
		pattern.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		current_item_visual = pattern
		item_root.add_child(pattern)
		return
	if item_cube_faces.size() > 0:
		var block: MeshInstance3D = MeshInstance3D.new()
		block.mesh = _build_cube_mesh()
		block.scale = Vector3(0.32, 0.32, 0.32)
		block.rotation_degrees = Vector3(18, 36, 0)
		block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		current_item_visual = block
		item_root.add_child(block)
		return
	var icon_mesh: MeshInstance3D = MeshInstance3D.new()
	icon_mesh.mesh = _build_extruded_icon_mesh(item_icon)
	icon_mesh.rotation_degrees = Vector3(12, -42, 42)
	icon_mesh.scale = Vector3(1.5, 1.5, 1.5)
	icon_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	current_item_visual = icon_mesh
	item_root.add_child(icon_mesh)

func _build_cube_mesh() -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	_add_cube_face(mesh, "north", PackedVector3Array([
		Vector3(-0.5, -0.5, -0.5),
		Vector3(0.5, -0.5, -0.5),
		Vector3(0.5, 0.5, -0.5),
		Vector3(-0.5, 0.5, -0.5)
	]), Vector3(0, 0, -1))
	_add_cube_face(mesh, "south", PackedVector3Array([
		Vector3(0.5, -0.5, 0.5),
		Vector3(-0.5, -0.5, 0.5),
		Vector3(-0.5, 0.5, 0.5),
		Vector3(0.5, 0.5, 0.5)
	]), Vector3(0, 0, 1))
	_add_cube_face(mesh, "east", PackedVector3Array([
		Vector3(0.5, -0.5, -0.5),
		Vector3(0.5, -0.5, 0.5),
		Vector3(0.5, 0.5, 0.5),
		Vector3(0.5, 0.5, -0.5)
	]), Vector3(1, 0, 0))
	_add_cube_face(mesh, "west", PackedVector3Array([
		Vector3(-0.5, -0.5, 0.5),
		Vector3(-0.5, -0.5, -0.5),
		Vector3(-0.5, 0.5, -0.5),
		Vector3(-0.5, 0.5, 0.5)
	]), Vector3(-1, 0, 0))
	_add_cube_face(mesh, "top", PackedVector3Array([
		Vector3(-0.5, 0.5, -0.5),
		Vector3(0.5, 0.5, -0.5),
		Vector3(0.5, 0.5, 0.5),
		Vector3(-0.5, 0.5, 0.5)
	]), Vector3(0, 1, 0))
	_add_cube_face(mesh, "bottom", PackedVector3Array([
		Vector3(-0.5, -0.5, 0.5),
		Vector3(0.5, -0.5, 0.5),
		Vector3(0.5, -0.5, -0.5),
		Vector3(-0.5, -0.5, -0.5)
	]), Vector3(0, -1, 0))
	return mesh

func _add_cube_face(mesh: ArrayMesh, face_name: String, vertices: PackedVector3Array, normal: Vector3) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([normal, normal, normal, normal])
	if face_name in ["north", "south", "east", "west"]:
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
			Vector2(0, 1),
			Vector2(1, 1),
			Vector2(1, 0),
			Vector2(0, 0)
		])
	else:
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
			Vector2(0, 0),
			Vector2(1, 0),
			Vector2(1, 1),
			Vector2(0, 1)
		])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface_index: int = mesh.get_surface_count() - 1
	mesh.surface_set_material(surface_index, _material_for_face(face_name))

func _material_for_face(face_name: String) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.roughness = 1.0
	var texture: Texture2D = _texture_for_face(face_name)
	if texture != null:
		material.albedo_texture = texture
	else:
		material.albedo_color = Color(0.8, 0.8, 0.8)
	_make_material_overlay(material)
	return material

func _texture_for_face(face_name: String) -> Texture2D:
	var raw_texture: Variant = item_cube_faces.get(face_name, null)
	if raw_texture is Texture2D:
		return raw_texture as Texture2D
	if face_name == "east" or face_name == "west" or face_name == "south":
		raw_texture = item_cube_faces.get("side", null)
		if raw_texture is Texture2D:
			return raw_texture as Texture2D
	if face_name == "north":
		raw_texture = item_cube_faces.get("front", null)
		if raw_texture is Texture2D:
			return raw_texture as Texture2D
	raw_texture = item_cube_faces.get("top", null)
	if raw_texture is Texture2D:
		return raw_texture as Texture2D
	raw_texture = item_cube_faces.get("front", null)
	if raw_texture is Texture2D:
		return raw_texture as Texture2D
	return item_icon

func _make_material_overlay(mat: StandardMaterial3D) -> void:
	mat.no_depth_test = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.render_priority = 127

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
	_make_material_overlay(material)
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
