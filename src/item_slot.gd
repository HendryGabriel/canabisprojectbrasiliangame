extends Control
class_name ItemSlot

const UIStyleScript = preload("res://src/ui_style.gd")

var controller: Node
var slot_type: String = ""
var slot_index: int = -1
var item_id: String = ""
var item_count: int = 0
var count_text_override: String = ""
var item_label: String = ""
var item_description: String = ""
var item_icon: Texture2D
var cube_faces: Dictionary = {}
var item_mesh: Mesh
var selected: bool = false
var interactive: bool = true
var hovered: bool = false
var ghost: bool = false
var visual_kind: String = "stone"

var flat_icon: TextureRect
var count_label: Label
var viewport_container: SubViewportContainer
var block_viewport: SubViewport
var preview_root: Node3D
var preview_mesh_instance: MeshInstance3D
var preview_scene_signature: String = ""

## PackedStringArray constructors are runtime expressions in Godot 4.
const CUBE_FACE_NAMES: Array = [
	"north", "south", "east", "west", "top", "bottom"
]

func configure(
	p_controller: Node,
	p_slot_type: String,
	p_slot_index: int,
	p_item_id: String,
	p_item_count: int,
	p_item_label: String,
	p_item_description: String,
	p_item_icon: Texture2D,
	p_cube_faces: Dictionary,
	p_size: Vector2 = Vector2(72, 54),
	p_interactive: bool = true,
	p_item_mesh: Mesh = null
) -> void:
	var cube_preview_changed: bool = _preview_signature_for(p_cube_faces, p_item_icon, p_item_mesh) != preview_scene_signature
	controller = p_controller
	slot_type = p_slot_type
	slot_index = p_slot_index
	item_id = p_item_id
	item_count = p_item_count
	item_label = p_item_label
	item_description = p_item_description
	item_icon = p_item_icon
	cube_faces = p_cube_faces
	item_mesh = p_item_mesh
	interactive = p_interactive
	ghost = false
	modulate = Color.WHITE
	custom_minimum_size = p_size
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	tooltip_text = ""
	_ensure_children()
	_update_visual(cube_preview_changed)

func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()

func set_visual_kind(value: String) -> void:
	visual_kind = value
	queue_redraw()

func set_ghost(value: bool) -> void:
	ghost = value
	modulate = Color(1.0, 1.0, 1.0, 0.42) if value else Color.WHITE
	queue_redraw()

func set_count_text_override(value: String) -> void:
	count_text_override = value
	if count_label != null:
		count_label.text = value if value != "" else (str(item_count) if item_count > 1 else "")

func _gui_input(event: InputEvent) -> void:
	if not interactive or controller == null:
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT or mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			controller.call(
				"slot_mouse_button",
				slot_type,
				slot_index,
				mouse_event.button_index,
				mouse_event.pressed
			)
			accept_event()

func _ready() -> void:
	_update_visual()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER and interactive:
		hovered = true
		queue_redraw()
		if controller != null:
			controller.call("slot_mouse_entered", slot_type, slot_index)
	elif what == NOTIFICATION_MOUSE_EXIT and interactive:
		hovered = false
		queue_redraw()
		if controller != null:
			controller.call("slot_mouse_exited", slot_type, slot_index)
	elif what == NOTIFICATION_RESIZED:
		_position_children()

func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	if slot_type == "cursor":
		return
	var colors: Array[Color] = UIStyleScript.slot_colors(visual_kind)
	draw_rect(rect, colors[0], true)
	draw_rect(rect.grow(-1), colors[1], false, 2.0)
	if selected:
		draw_rect(rect.grow(-3), colors[2], false, 3.0)
	if hovered:
		draw_rect(rect.grow(-2), Color(colors[2], 0.20), true)

func _ensure_children() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if viewport_container == null:
		viewport_container = SubViewportContainer.new()
		viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		viewport_container.stretch = false
		viewport_container.clip_contents = true
		viewport_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(viewport_container)
	if block_viewport == null:
		block_viewport = SubViewport.new()
		block_viewport.own_world_3d = true
		block_viewport.transparent_bg = true
		block_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		block_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		block_viewport.msaa_3d = Viewport.MSAA_DISABLED
		block_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		viewport_container.add_child(block_viewport)
	if flat_icon == null:
		flat_icon = TextureRect.new()
		flat_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		flat_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flat_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(flat_icon)
	if count_label == null:
		count_label = Label.new()
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count_label.add_theme_font_size_override("font_size", 11)
		count_label.add_theme_color_override("font_color", Color.WHITE)
		count_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		count_label.add_theme_constant_override("shadow_offset_x", 1)
		count_label.add_theme_constant_override("shadow_offset_y", 1)
		add_child(count_label)

func _update_visual(force_cube_preview_refresh: bool = false) -> void:
	if not is_node_ready():
		return
	_ensure_children()
	if item_id == "" or item_count <= 0:
		flat_icon.visible = false
		viewport_container.visible = false
		count_label.text = ""
		queue_redraw()
		return

	if item_mesh != null or cube_faces.size() > 0:
		flat_icon.visible = false
		viewport_container.visible = true
		if _update_cube_preview_if_needed():
			force_cube_preview_refresh = true
	else:
		viewport_container.visible = false
		flat_icon.visible = true
		flat_icon.texture = item_icon

	count_label.text = count_text_override if count_text_override != "" else (str(item_count) if item_count > 1 else "")
	_position_children()
	if force_cube_preview_refresh:
		request_preview_update()
	queue_redraw()

func _position_children() -> void:
	var slot_size: Vector2 = size
	if slot_size.x <= 0 or slot_size.y <= 0:
		slot_size = custom_minimum_size
	var padding: float = 2.0
	var max_icon_edge: float = min(slot_size.x, slot_size.y) - padding * 2.0
	var icon_edge: float = clampf(max_icon_edge, 16.0, 40.0)
	var icon_size: Vector2 = Vector2(icon_edge, icon_edge)
	var icon_position: Vector2 = (slot_size - icon_size) * 0.5
	flat_icon.position = icon_position
	flat_icon.size = icon_size
	viewport_container.position = icon_position
	viewport_container.size = icon_size
	if block_viewport != null:
		var viewport_size: Vector2i = Vector2i(max(1, int(icon_size.x)), max(1, int(icon_size.y)))
		if block_viewport.size != viewport_size:
			block_viewport.size = viewport_size
			if viewport_container.visible:
				request_preview_update()
	count_label.position = Vector2(0, slot_size.y - 17.0)
	count_label.size = Vector2(slot_size.x - 4.0, 16.0)

func request_preview_update() -> void:
	if not is_node_ready() or block_viewport == null or viewport_container == null:
		return
	if not viewport_container.visible or (item_mesh == null and cube_faces.is_empty()):
		return
	block_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _update_cube_preview_if_needed() -> bool:
	var signature: String = _preview_signature_for(cube_faces, item_icon, item_mesh)
	_ensure_block_preview_scene()
	if signature == preview_scene_signature and preview_mesh_instance.mesh != null:
		return false
	preview_mesh_instance.mesh = item_mesh if item_mesh != null else _build_cube_mesh()
	preview_scene_signature = signature
	return true

func _ensure_block_preview_scene() -> void:
	if preview_root != null and is_instance_valid(preview_root):
		return

	preview_root = Node3D.new()
	block_viewport.add_child(preview_root)

	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.82, 0.9)
	environment.ambient_light_energy = 0.72
	environment_node.environment = environment
	block_viewport.add_child(environment_node)

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.light_energy = 1.35
	preview_root.add_child(light)

	preview_mesh_instance = MeshInstance3D.new()
	preview_root.add_child(preview_mesh_instance)

	var camera: Camera3D = Camera3D.new()
	block_viewport.add_child(camera)
	camera.position = Vector3(1.9, 1.45, 2.25)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.fov = 34.0
	camera.current = true

func _cube_preview_signature_for(p_cube_faces: Dictionary, p_item_icon: Texture2D) -> String:
	if p_cube_faces.is_empty():
		return ""
	var face_signatures: PackedStringArray = PackedStringArray()
	for face_name in CUBE_FACE_NAMES:
		var texture: Texture2D = _texture_for_face_data(face_name, p_cube_faces, p_item_icon)
		face_signatures.append(str(texture.get_instance_id()) if texture != null else "0")
	return "|".join(face_signatures)


func _preview_signature_for(p_cube_faces: Dictionary, p_item_icon: Texture2D, p_item_mesh: Mesh) -> String:
	return "mesh:%d" % p_item_mesh.get_instance_id() if p_item_mesh != null else _cube_preview_signature_for(p_cube_faces, p_item_icon)

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
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 1.0
	var texture: Texture2D = _texture_for_face(face_name)
	if texture != null:
		mat.albedo_texture = texture
	else:
		mat.albedo_color = Color(0.8, 0.8, 0.8)
	return mat

func _texture_for_face(face_name: String) -> Texture2D:
	return _texture_for_face_data(face_name, cube_faces, item_icon)

func _texture_for_face_data(face_name: String, p_cube_faces: Dictionary, p_item_icon: Texture2D) -> Texture2D:
	var raw_texture: Variant = p_cube_faces.get(face_name, null)
	if raw_texture is Texture2D:
		return raw_texture as Texture2D
	if face_name == "east" or face_name == "west" or face_name == "south":
		raw_texture = p_cube_faces.get("side", null)
		if raw_texture is Texture2D:
			return raw_texture as Texture2D
	if face_name == "north":
		raw_texture = p_cube_faces.get("front", null)
		if raw_texture is Texture2D:
			return raw_texture as Texture2D
	raw_texture = p_cube_faces.get("top", null)
	if raw_texture is Texture2D:
		return raw_texture as Texture2D
	raw_texture = p_cube_faces.get("front", null)
	if raw_texture is Texture2D:
		return raw_texture as Texture2D
	return p_item_icon
