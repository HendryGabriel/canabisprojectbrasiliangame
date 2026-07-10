## Shared rendering, free-camera, and UI helpers for in-game authoring modes.
class_name AuthoringSceneBase
extends Node3D


const BlockCatalogScript = preload("res://src/block_catalog.gd")
const VoxelSectionSystemScript = preload("res://src/voxel_section_system.gd")
const VoxelTextureArrayScript = preload("res://src/voxel_texture_array.gd")

var block_definitions: Dictionary = {}
var authoring_world
var section_system
var texture_array
var camera: Camera3D
var ui_layer: CanvasLayer
var status_label: Label
var yaw: float = 0.0
var pitch: float = -0.35
var fly_speed: float = 24.0
var mouse_sensitivity: float = 0.0025
var right_mouse_toggles_capture: bool = true
var free_camera_controls_enabled: bool = true


func setup_authoring_world(world, camera_position: Vector3) -> void:
	block_definitions = BlockCatalogScript.blocks()
	authoring_world = world
	texture_array = VoxelTextureArrayScript.new()
	if texture_array.build(block_definitions):
		authoring_world.configure_texture_layers(texture_array.layer_by_path)
	else:
		texture_array = null
	section_system = VoxelSectionSystemScript.new()
	section_system.name = "AuthoringSections"
	add_child(section_system)
	section_system.setup(authoring_world, Callable(self, "_material_for_surface"), true)
	section_system.queue_rebuild_all(true)
	_create_authoring_environment()
	camera = Camera3D.new()
	camera.name = "AuthoringCamera"
	camera.position = camera_position
	add_child(camera)
	_apply_camera_rotation()
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 20
	add_child(ui_layer)


func _process(delta: float) -> void:
	if section_system != null:
		section_system.process_updates(false)
	if free_camera_controls_enabled:
		_update_free_camera(delta)


func _unhandled_input(event: InputEvent) -> void:
	if right_mouse_toggles_capture and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()
	elif free_camera_controls_enabled and event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, -1.52, 1.52)
		_apply_camera_rotation()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _update_free_camera(delta: float) -> void:
	if camera == null or Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	var input: Vector3 = Vector3(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q)),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)
	if input.length_squared() <= 0.0:
		return
	var speed: float = fly_speed * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	camera.position += camera.basis * input.normalized() * speed * delta


func _apply_camera_rotation() -> void:
	if camera != null:
		camera.rotation = Vector3(pitch, yaw, 0.0)


func camera_ray_origin() -> Vector3:
	return camera.global_position


func camera_ray_direction() -> Vector3:
	return -camera.global_transform.basis.z.normalized()


func make_side_panel(title: String, width: float = 330.0) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 12
	panel.offset_top = 12
	panel.offset_right = 12 + width
	panel.offset_bottom = -12
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.035, 0.045, 0.94)
	style.border_color = Color(0.38, 0.42, 0.48, 1.0)
	style.set_border_width_all(2)
	style.set_content_margin_all(12.0)
	panel.add_theme_stylebox_override("panel", style)
	ui_layer.add_child(panel)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(scroll)
	var root: VBoxContainer = VBoxContainer.new()
	root.custom_minimum_size = Vector2(width - 28.0, 0)
	root.add_theme_constant_override("separation", 7)
	scroll.add_child(root)
	var heading: Label = Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 22)
	root.add_child(heading)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(width - 28.0, 48)
	root.add_child(status_label)
	return root


func make_button(text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 32)
	button.pressed.connect(callback)
	return button


func set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text


func return_to_main_menu() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _material_for_surface(surface: Dictionary) -> Material:
	if bool(surface.get("use_texture_array", false)) and texture_array != null:
		var material: Material = texture_array.material_for(str(surface.get("render_class", "opaque")))
		if material != null:
			return material
	var fallback: StandardMaterial3D = StandardMaterial3D.new()
	fallback.albedo_color = surface.get("fallback_color", Color.WHITE)
	fallback.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	fallback.vertex_color_use_as_albedo = true
	var path: String = str(surface.get("texture_path", ""))
	if path != "":
		fallback.albedo_texture = load(path) as Texture2D
		fallback.albedo_color = Color.WHITE
	return fallback


func _create_authoring_environment() -> void:
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.32, 0.48, 0.68)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.88, 0.94)
	environment.ambient_light_energy = 0.72
	environment_node.environment = environment
	add_child(environment_node)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)
