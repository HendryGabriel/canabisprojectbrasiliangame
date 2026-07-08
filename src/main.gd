extends Node3D

const BIOME_SIZE: int = 100
const MAP_SIZE: int = 200
const WORLD_DEPTH: int = 64
const SURFACE_BASE_Y: int = 0
const SURFACE_MIN_Y: int = -2
const SURFACE_MAX_Y: int = 9
const BEDROCK_Y: int = -65
const WORLD_SEED: int = 1235571
const BIOME_MIN_X: int = 0
const BIOME_MAX_X: int = BIOME_SIZE - 1
const BIOME_MIN_Z: int = 0
const BIOME_MAX_Z: int = BIOME_SIZE - 1
const WORLD_WALL_HEIGHT: float = 180.0
const BLOCK_NEIGHBORS: Array[Vector3i] = [
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0),
	Vector3i(0, -1, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1)
]
const INVENTORY_SLOT_COUNT: int = 27
const CHEST_SLOT_COUNT: int = 18
const MANA_MAX: float = 100.0
const MANA_REGEN_PER_SECOND: float = 5.0
const MANITA_PICKAXE_MANA_COST: float = 5.0
const HOTBAR_SLOT_COUNT: int = 9
const SAVE_PATH: String = "user://savegame.json"
const SETTINGS_PATH: String = "user://settings.cfg"
const CHUNK_SIZE: int = 8
const COLLISION_RADIUS: int = 12
const SHADOW_OPACITY: float = 0.4
const LEAF_PARTICLE_MAX: int = 28
const LEAF_PARTICLE_SPAWN_INTERVAL: float = 0.34
const LEAF_PARTICLE_SEARCH_RADIUS: int = 10

var chunk_nodes: Dictionary = {} # Vector2i -> Node3D
var blocks_in_chunk: Dictionary = {} # Vector2i -> (Vector3i -> String)
var dirty_chunk_queue: Array = []
var dirty_chunk_keys: Dictionary = {}
var last_collision_update_pos: Vector3i = Vector3i(-999, -999, -999)
var breaking_pos: Vector3i = Vector3i(-999, -999, -999)
var breaking_progress: float = 0.0
var breaking_overlay: MeshInstance3D = null
var breaking_crack_textures: Array = []
var target_outline: MeshInstance3D = null
var target_outline_pos: Vector3i = Vector3i(-999, -999, -999)
var dropped_items: Array = []
var is_loading_world: bool = false
var chunks_to_mesh: Array = []
var total_chunks_to_mesh: int = 0
var meshed_chunks_count: int = 0
var tracking_on_load_finish: bool = false
var continue_on_load_finish: bool = false
var loaded_game_data: Dictionary = {}
var place_cooldown: float = 0.0
var leaf_particles: Array = []
var leaf_particle_spawn_timer: float = 0.0
var leaf_particle_texture: Texture2D = null
var leaf_particle_mesh: QuadMesh = null

var time_of_day: float = 8.0
var day_count: int = 1
var time_speed: float = 0.05
var sun_light: DirectionalLight3D = null
var moon_light: DirectionalLight3D = null
var world_env: WorldEnvironment = null
var sky_material: ProceduralSkyMaterial = null
var fog_env: Environment = null
var hud_time_label: Label = null

var loading_panel: PanelContainer = null
var loading_progress_bar: ProgressBar = null
var loading_label: Label = null
var block_defs: Dictionary = {}
var item_defs: Dictionary = {}
var recipes: Array = []
var materials: Dictionary = {}
var block_item_meshes: Dictionary = {}
var item_icons: Dictionary = {}
var item_icon_faces: Dictionary = {}
var blocks: Dictionary = {}
var block_nodes: Dictionary = {}
var surface_heights: Dictionary = {}
var chest_inventories: Dictionary = {}
var changed_blocks: Dictionary = {}
var removed_blocks: Dictionary = {}
var inventory_slots: Array = []
var craft_slots: Array = []
var craft_size: int = 2
var craft_context: String = "inventory"
var selected_hotbar_index: int = 0
var mana: float = MANA_MAX
var manita_pickaxe_xp: int = 0
var manita_pickaxe_level: int = 1
var current_chest_pos: Vector3i = Vector3i.ZERO
var has_current_chest: bool = false
var message_time: float = 0.0
var cursor_stack: Dictionary = {"item": "", "count": 0}
var left_drag_active: bool = false
var left_drag_targets: Array = []
var left_drag_keys: Dictionary = {}
var right_drag_active: bool = false
var right_drag_keys: Dictionary = {}
var tracking_world_changes: bool = false
var game_started: bool = false
var fullscreen_enabled: bool = false
var shadows_enabled: bool = true
var ssao_enabled: bool = true
var voxel_ao_enabled: bool = true
var options_origin: String = "main"
var player_skin_path: String = ""
var saved_camera_mode: int = 0

var player: TrumanPlayer
var world_root: Node3D
var ui_layer: CanvasLayer
var crosshair_label: Label
var status_label: Label
var message_label: Label
var cursor_stack_slot: ItemSlot
var cursor_stack_signature: String = ""
var hotbar_box: HBoxContainer
var inventory_panel: PanelContainer
var chest_panel: PanelContainer
var main_menu_panel: PanelContainer
var pause_menu_panel: PanelContainer
var options_panel: PanelContainer
var continue_button: Button
var fullscreen_toggle: CheckBox
var shadows_toggle: CheckBox
var ssao_toggle: CheckBox
var voxel_ao_toggle: CheckBox
var skin_file_dialog: FileDialog
var options_status_label: Label
var menu_status_label: Label
var pause_status_label: Label
var inventory_grid: GridContainer
var craft_grid: GridContainer
var craft_output_holder: CenterContainer
var craft_title_label: Label
var craft_result_label: Label
var chest_player_grid: GridContainer
var chest_grid: GridContainer
var tooltip_panel: PanelContainer
var tooltip_name_label: Label
var tooltip_description_label: Label
var hovered_slot_type: String = ""
var hovered_slot_index: int = -1
var held_item_signature: String = ""

func _ready() -> void:
	_setup_input_map()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	block_defs = BlockCatalog.blocks()
	item_defs = BlockCatalog.items()
	recipes = BlockCatalog.recipes()
	inventory_slots = _make_slots(INVENTORY_SLOT_COUNT)
	craft_slots = _make_slots(4)

	_load_settings()
	_apply_fullscreen(fullscreen_enabled)
	_setup_materials()
	_create_lighting()
	_create_world()
	_create_player()
	_create_ui()
	_give_start_items()
	player.set_controls_enabled(false)
	_show_main_menu()
	_message("Bioma 1 iniciado: 100x100. E abre craft 2x2; bancada abre craft 3x3.")

func _process(delta: float) -> void:
	if is_loading_world:
		var chunks_per_frame: int = 8
		for i in range(chunks_per_frame):
			if chunks_to_mesh.is_empty():
				_finish_world_loading()
				break
			var c_pos = chunks_to_mesh.pop_back()
			_update_chunk_mesh(c_pos.x, c_pos.y)
			meshed_chunks_count += 1
		if total_chunks_to_mesh > 0:
			var pct = float(meshed_chunks_count) / float(total_chunks_to_mesh) * 100.0
			loading_progress_bar.value = pct
			loading_label.text = "Construindo o Mundo: %d%%" % int(pct)
		return

	_process_dirty_chunk_meshes(1)

	mana = min(MANA_MAX, mana + MANA_REGEN_PER_SECOND * delta)
	if place_cooldown > 0.0:
		place_cooldown -= delta

	_update_day_night_cycle(delta)
	_update_leaf_particles(delta)
	
	if message_time > 0:
		message_time -= delta
		if message_time <= 0:
			message_label.text = ""
	if player != null and is_instance_valid(player) and player.is_inside_tree():
		var p_pos: Vector3 = player.global_position
		var p_block: Vector3i = Vector3i(int(round(p_pos.x)), int(round(p_pos.y)), int(round(p_pos.z)))
		if p_block != last_collision_update_pos:
			last_collision_update_pos = p_block
			_update_active_collisions(p_pos)
		
		# Handle held left-click block breaking & held right-click block placing
		if game_started and not _is_menu_open() and not inventory_panel.visible and not chest_panel.visible:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				_handle_block_breaking(delta)
			else:
				_cancel_block_breaking()
				
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				if place_cooldown <= 0.0:
					if _use_or_place_target():
						place_cooldown = 0.2
		else:
			_cancel_block_breaking()
		_update_target_outline()
	_update_cursor_stack_label()
	_update_hover_tooltip_position()
	_update_status()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if not mouse_event.pressed:
			if mouse_event.button_index == MOUSE_BUTTON_LEFT and left_drag_active:
				_finish_left_drag()
			elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
				right_drag_active = false
				right_drag_keys.clear()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if options_panel != null and options_panel.visible:
				_close_options_panel()
			elif main_menu_panel != null and main_menu_panel.visible:
				return
			elif pause_menu_panel != null and pause_menu_panel.visible:
				_resume_game()
			elif inventory_panel.visible or chest_panel.visible:
				_close_all_panels()
			else:
				_show_pause_menu()
			return
		if not game_started or _is_menu_open():
			return
		if event.keycode == KEY_E:
			if chest_panel.visible or inventory_panel.visible:
				_close_all_panels()
			else:
				_open_inventory_craft()
			return
		if event.keycode == KEY_Q:
			_drop_selected_item()
			return
		if event.keycode == KEY_F5:
			if player != null:
				saved_camera_mode = player.toggle_camera_mode()
				_save_settings()
				_update_player_visual_visibility()
			return
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			selected_hotbar_index = event.keycode - KEY_1
			_update_hotbar()
			return

	if not game_started or _is_menu_open() or inventory_panel.visible or chest_panel.visible:
		return

	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			player.set_controls_enabled(true)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			selected_hotbar_index = (selected_hotbar_index - 1 + HOTBAR_SLOT_COUNT) % HOTBAR_SLOT_COUNT
			_update_hotbar()
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			selected_hotbar_index = (selected_hotbar_index + 1) % HOTBAR_SLOT_COUNT
			_update_hotbar()
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if _use_or_place_target():
				place_cooldown = 0.2

func _setup_input_map() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)

func _add_key_action(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action_name, event)

func _setup_materials() -> void:
	materials.clear()
	block_item_meshes.clear()
	item_icons.clear()
	item_icon_faces.clear()
	for block_id in block_defs.keys():
		var block_data: Dictionary = block_defs[block_id]
		for face_name in ["top", "bottom", "north", "south", "east", "west"]:
			var texture_path: String = _block_texture_for_face(block_data, face_name)
			_material_for_texture(
				texture_path,
				block_data.get("color", Color.WHITE),
				float(block_data.get("alpha", 1.0)),
				bool(block_data.get("transparent", false)),
				bool(block_data.get("foliage", false))
			)
	for item_id in item_defs.keys():
		_item_icon(item_id)
		_item_icon_faces(item_id)

func _material_for_texture(texture_path: String, fallback_color: Color, alpha: float = 1.0, transparent: bool = false, foliage: bool = false) -> Material:
	var texture_key: String = texture_path if texture_path != "" else fallback_color.to_html()
	var key: String = "%s|%.3f|%s|%s" % [texture_key, alpha, str(transparent), str(foliage)]
	if materials.has(key):
		var cached: Material = materials[key]
		return cached

	if foliage:
		var leaf_mat: ShaderMaterial = _make_foliage_material(texture_path, fallback_color, alpha)
		materials[key] = leaf_mat
		return leaf_mat

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	var material_color: Color = fallback_color
	material_color.a = alpha
	mat.albedo_color = material_color
	mat.roughness = 0.95
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	if transparent or alpha < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	if texture_path != "":
		var texture: Texture2D = load(texture_path) as Texture2D
		if texture != null:
			mat.albedo_texture = texture
			mat.albedo_color = Color(1.0, 1.0, 1.0, alpha)
	materials[key] = mat
	return mat

func _make_foliage_material(texture_path: String, fallback_color: Color, alpha: float) -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_lambert;

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.88);
uniform float sway_strength = 0.032;
uniform float sway_speed = 1.05;

void vertex() {
	float world_x = MODEL_MATRIX[3].x + VERTEX.x;
	float world_z = MODEL_MATRIX[3].z + VERTEX.z;
	float phase = world_x * 0.83 + world_z * 0.61 + VERTEX.y * 0.37;
	float sway = sin(TIME * sway_speed + phase) * sway_strength;
	float flutter = sin(TIME * sway_speed * 1.73 + phase * 1.41) * sway_strength * 0.35;
	VERTEX.x += sway + flutter;
	VERTEX.z += cos(TIME * sway_speed * 0.82 + phase) * sway_strength * 0.35;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb * COLOR.rgb * tint.rgb;
	ALPHA = tex.a * COLOR.a * tint.a;
	ALPHA_SCISSOR_THRESHOLD = 0.08;
}
"""
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	var texture: Texture2D = load(texture_path) as Texture2D
	var tint: Color = fallback_color
	if texture != null:
		mat.set_shader_parameter("albedo_texture", texture)
		tint = Color(1.0, 1.0, 1.0)
	tint.a = alpha
	mat.set_shader_parameter("tint", tint)
	return mat

func _update_leaf_particles(delta: float) -> void:
	if not game_started or player == null or not is_instance_valid(player):
		return
	_update_active_leaf_particles(delta)
	leaf_particle_spawn_timer -= delta
	if leaf_particle_spawn_timer > 0.0:
		return
	leaf_particle_spawn_timer = LEAF_PARTICLE_SPAWN_INTERVAL + randf_range(0.0, 0.22)
	if leaf_particles.size() >= LEAF_PARTICLE_MAX:
		return
	var spawn: Dictionary = _find_leaf_particle_spawn()
	if spawn.is_empty():
		return
	_spawn_leaf_particle(spawn["position"])

func _update_active_leaf_particles(delta: float) -> void:
	if leaf_particles.is_empty():
		return
	for i in range(leaf_particles.size() - 1, -1, -1):
		var particle: Dictionary = leaf_particles[i]
		var node: MeshInstance3D = particle.get("node", null)
		if node == null or not is_instance_valid(node):
			leaf_particles.remove_at(i)
			continue
		var age: float = float(particle.get("age", 0.0)) + delta
		var life: float = float(particle.get("life", 1.0))
		if age >= life:
			_remove_leaf_particle(i)
			continue
		var velocity: Vector3 = particle.get("velocity", Vector3.ZERO)
		var phase: float = float(particle.get("phase", 0.0))
		var wind: Vector3 = Vector3(
			sin(age * 1.55 + phase) * 0.18 + 0.06,
			0.0,
			cos(age * 0.95 + phase * 0.7) * 0.08
		)
		node.position += (velocity + wind) * delta
		node.rotation.z += float(particle.get("spin", 0.0)) * delta
		node.rotation.x = sin(age * 2.2 + phase) * 0.35
		var block_pos: Vector3i = Vector3i(int(round(node.position.x)), 0, int(round(node.position.z)))
		if not _is_inside_current_biome(block_pos):
			_remove_leaf_particle(i)
			continue
		var ground_y: float = float(_surface_y_at(block_pos.x, block_pos.z)) + 0.15
		if node.position.y <= ground_y:
			_remove_leaf_particle(i)
			continue
		
		var dist_to_ground: float = node.position.y - ground_y
		var ground_fade: float = clamp(dist_to_ground / 0.8, 0.0, 1.0)
		var fade: float = min(age / 0.45, (life - age) / 0.7)
		var alpha: float = clamp(fade, 0.0, 1.0) * ground_fade * float(particle.get("base_alpha", 0.58))
		var mat: StandardMaterial3D = node.material_override as StandardMaterial3D
		if mat != null:
			var color: Color = mat.albedo_color
			color.a = alpha
			mat.albedo_color = color
		particle["age"] = age
		leaf_particles[i] = particle

func _find_leaf_particle_spawn() -> Dictionary:
	var player_pos: Vector3 = player.global_position
	var center_x: int = int(round(player_pos.x))
	var center_y: int = int(round(player_pos.y))
	var center_z: int = int(round(player_pos.z))
	for attempt in range(14):
		var x: int = center_x + randi_range(-LEAF_PARTICLE_SEARCH_RADIUS, LEAF_PARTICLE_SEARCH_RADIUS)
		var z: int = center_z + randi_range(-LEAF_PARTICLE_SEARCH_RADIUS, LEAF_PARTICLE_SEARCH_RADIUS)
		if not _is_inside_current_biome(Vector3i(x, 0, z)):
			continue
		var top_y: int = center_y + 9
		var bottom_y: int = center_y - 3
		for y in range(top_y, bottom_y - 1, -1):
			var pos: Vector3i = Vector3i(x, y, z)
			if _is_foliage_block_id(str(blocks.get(pos, ""))):
				return {
					"position": Vector3(
						float(x) + randf_range(-0.36, 0.36),
						float(y) - 0.35,
						float(z) + randf_range(-0.36, 0.36)
					)
				}
	return {}

func _spawn_leaf_particle(position: Vector3) -> void:
	if world_root == null or not is_instance_valid(world_root):
		return
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "FallingLeaf"
	node.mesh = _leaf_particle_quad_mesh()
	node.material_override = _make_leaf_particle_material()
	node.position = position
	node.rotation = Vector3(randf_range(-0.35, 0.35), randf_range(0.0, TAU), randf_range(0.0, TAU))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(node)
	leaf_particles.append({
		"node": node,
		"velocity": Vector3(randf_range(-0.05, 0.08), randf_range(-0.58, -0.42), randf_range(-0.05, 0.05)),
		"age": 0.0,
		"life": randf_range(4.2, 6.3),
		"phase": randf_range(0.0, TAU),
		"spin": randf_range(-1.6, 1.6),
		"base_alpha": randf_range(0.45, 0.68)
	})

func _leaf_particle_quad_mesh() -> QuadMesh:
	if leaf_particle_mesh != null:
		return leaf_particle_mesh
	leaf_particle_mesh = QuadMesh.new()
	leaf_particle_mesh.size = Vector2(0.18, 0.12)
	return leaf_particle_mesh

func _make_leaf_particle_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = _leaf_particle_card_texture()
	mat.albedo_color = Color(randf_range(0.36, 0.50), randf_range(0.62, 0.82), randf_range(0.18, 0.28), 0.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return mat

func _leaf_particle_card_texture() -> Texture2D:
	if leaf_particle_texture != null:
		return leaf_particle_texture
	var image: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for x in range(8):
		for y in range(8):
			var dx: float = (float(x) - 3.5) / 3.3
			var dy: float = (float(y) - 3.5) / 2.25
			if dx * dx + dy * dy <= 1.0:
				var vein: float = 0.0
				if abs(x - y) <= 1:
					vein = 0.12
				var shade: float = 0.9 + (float(y) / 8.0) * 0.12
				image.set_pixel(x, y, Color(0.34 * shade - vein, 0.68 * shade - vein, 0.18 * shade, 0.92))
	leaf_particle_texture = ImageTexture.create_from_image(image)
	return leaf_particle_texture

func _remove_leaf_particle(index: int) -> void:
	if index < 0 or index >= leaf_particles.size():
		return
	var particle: Dictionary = leaf_particles[index]
	var node: MeshInstance3D = particle.get("node", null)
	if node != null and is_instance_valid(node):
		node.queue_free()
	leaf_particles.remove_at(index)

func _clear_leaf_particles() -> void:
	for particle in leaf_particles:
		var node: MeshInstance3D = particle.get("node", null)
		if node != null and is_instance_valid(node):
			node.queue_free()
	leaf_particles.clear()
	leaf_particle_spawn_timer = 0.0

func _block_texture_for_face(block_data: Dictionary, face_name: String) -> String:
	var textures: Dictionary = block_data.get("textures", {})
	if textures.has(face_name):
		return textures[face_name]
	if face_name == "north" and textures.has("front"):
		return textures["front"]
	if face_name in ["south", "east", "west"] and textures.has("side"):
		return textures["side"]
	if textures.has("side"):
		return textures["side"]
	if textures.has("all"):
		return textures["all"]
	return block_data.get("texture", "")

func _item_icon(item_id: String) -> Texture2D:
	if item_id == "":
		return null
	if item_icons.has(item_id):
		var cached_icon: Texture2D = item_icons[item_id]
		return cached_icon

	var icon_path: String = ""
	var item_data: Dictionary = item_defs.get(item_id, {})
	icon_path = item_data.get("icon", "")
	if icon_path == "":
		var place_block: String = item_data.get("place_block", "")
		if block_defs.has(place_block):
			var block_data: Dictionary = block_defs[place_block]
			icon_path = block_data.get("icon", block_data.get("texture", ""))

	var texture: Texture2D = null
	if icon_path != "":
		texture = load(icon_path) as Texture2D
	item_icons[item_id] = texture
	return texture

func _item_icon_faces(item_id: String) -> Dictionary:
	if item_id == "":
		return {}
	if item_icon_faces.has(item_id):
		var cached_faces: Dictionary = item_icon_faces[item_id]
		return cached_faces

	var faces: Dictionary = {}
	var item_data: Dictionary = item_defs.get(item_id, {})
	var place_block: String = item_data.get("place_block", "")
	if block_defs.has(place_block):
		var block_data: Dictionary = block_defs[place_block]
		if bool(block_data.get("plant", false)):
			item_icon_faces[item_id] = {}
			return {}
		for face_name in ["north", "south", "east", "west", "top", "bottom"]:
			var texture_path: String = _block_texture_for_face(block_data, face_name)
			if texture_path != "":
				faces[face_name] = load(texture_path) as Texture2D
		faces["front"] = faces.get("north", null)
		faces["side"] = faces.get("west", faces.get("east", null))
	item_icon_faces[item_id] = faces
	return faces

func _create_lighting() -> void:
	# --- Sun ---
	sun_light = DirectionalLight3D.new()
	sun_light.name = "Sun"
	sun_light.rotation_degrees = Vector3(-45, 35, 0)
	sun_light.light_energy = 1.45
	sun_light.light_color = Color(1.0, 0.78, 0.42)
	sun_light.shadow_enabled = shadows_enabled
	sun_light.shadow_opacity = SHADOW_OPACITY
	sun_light.shadow_bias = 0.03
	sun_light.shadow_normal_bias = 2.0
	sun_light.directional_shadow_max_distance = 80.0
	add_child(sun_light)

	# --- Moon ---
	moon_light = DirectionalLight3D.new()
	moon_light.name = "Moon"
	moon_light.rotation_degrees = Vector3(45, 35, 0)
	moon_light.light_energy = 0.0
	moon_light.light_color = Color(0.9, 0.6, 0.32)
	moon_light.shadow_enabled = shadows_enabled
	moon_light.shadow_opacity = SHADOW_OPACITY
	moon_light.shadow_bias = 0.04
	moon_light.shadow_normal_bias = 2.5
	moon_light.directional_shadow_max_distance = 60.0
	add_child(moon_light)

	# --- Procedural Sky ---
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.9, 0.5, 0.18)
	sky_material.sky_horizon_color = Color(1.0, 0.72, 0.34)
	sky_material.ground_bottom_color = Color(0.2, 0.12, 0.05)
	sky_material.ground_horizon_color = Color(1.0, 0.72, 0.34)
	sky_material.sun_angle_max = 30.0
	sky_material.sun_curve = 0.15

	var sky: Sky = Sky.new()
	sky.sky_material = sky_material

	# --- Environment ---
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.62, 0.36)
	env.ambient_light_energy = 0.68

	# Tonemapping ACES
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.85

	# SSAO
	env.ssao_enabled = ssao_enabled
	env.ssao_radius = 0.45
	env.ssao_intensity = 0.65

	# Fog
	env.volumetric_fog_enabled = false
	env.fog_enabled = true
	env.fog_light_color = Color(0.86, 0.57, 0.24)
	env.fog_light_energy = 0.82
	env.fog_density = 0.004

	fog_env = env
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

func _update_day_night_cycle(delta: float) -> void:
	if not game_started:
		return

	# Advance time (time_speed = 0.05 means 1 real second = 0.05 game hours)
	# Full 24h cycle = 24 / 0.05 = 480 seconds = 8 minutes real time
	time_of_day += time_speed * delta
	if time_of_day >= 24.0:
		time_of_day -= 24.0
		day_count += 1

	# Sun angle: 0h = directly below (-90), 6h = horizon (0), 12h = zenith (90), 18h = horizon (0), 24h = below (-90)
	# Convert time_of_day to angle in degrees: sun_pitch = (time/24 * 360) - 90
	var sun_angle: float = (time_of_day / 24.0) * 360.0 - 90.0
	var moon_angle: float = sun_angle + 180.0

	# DirectionalLight3D shines along its local -Z axis, so invert the sky angle.
	if sun_light != null:
		sun_light.rotation_degrees = Vector3(-sun_angle, 35.0, 0.0)
	if moon_light != null:
		moon_light.rotation_degrees = Vector3(-moon_angle, 35.0, 0.0)

	# Calculate sun altitude factor (0.0 = horizon/below, 1.0 = zenith)
	# Sun is above horizon when time_of_day is roughly between 6 and 18
	var sun_altitude: float = sin(deg_to_rad(sun_angle))
	var sun_factor: float = clamp(sun_altitude, 0.0, 1.0)
	var is_night: bool = sun_altitude < -0.1

	# Sunrise/sunset detection (sun near horizon)
	var is_sunrise_sunset: bool = abs(sun_altitude) < 0.25 and not is_night

	# --- Sun intensity ---
	if sun_light != null:
		sun_light.light_energy = max(sun_factor * 1.45, 0.08) if sun_altitude > 0.0 else 0.0
		sun_light.shadow_enabled = shadows_enabled and sun_altitude > 0.08
		if is_sunrise_sunset:
			sun_light.light_color = Color(1.0, 0.5, 0.18).lerp(Color(1.0, 0.78, 0.42), sun_factor)
		else:
			sun_light.light_color = Color(1.0, 0.78, 0.42)

	# --- Moon intensity ---
	if moon_light != null:
		var moon_factor: float = clamp(-sun_altitude - 0.1, 0.0, 1.0)
		moon_light.light_color = Color(0.9, 0.6, 0.32)
		moon_light.light_energy = moon_factor * 1.25
		moon_light.shadow_enabled = shadows_enabled and moon_factor > 0.08

	# --- Sky colors ---
	if sky_material != null:
		var day_top: Color = Color(0.00, 0.70, 1.00)
		var day_horizon: Color = Color(0.94, 0.57, 0.08)
		var night_top: Color = Color(0.05, 0.01, 0.53)
		var night_horizon: Color = Color(0.55, 0.29, 0.67)
		var sunset_top: Color = Color(0.77, 0.55, 0.09)
		var sunset_horizon: Color = Color(0.61, 0.22, 0.66)

		if is_night:
			sky_material.sky_top_color = night_top
			sky_material.sky_horizon_color = night_horizon
			sky_material.ground_horizon_color = night_horizon
		elif is_sunrise_sunset:
			var t: float = clamp(sun_altitude / 0.25, 0.0, 1.0)
			sky_material.sky_top_color = sunset_top.lerp(day_top, t)
			sky_material.sky_horizon_color = sunset_horizon.lerp(day_horizon, t)
			sky_material.ground_horizon_color = sunset_horizon.lerp(day_horizon, t)
		else:
			sky_material.sky_top_color = day_top
			sky_material.sky_horizon_color = day_horizon
			sky_material.ground_horizon_color = day_horizon

	# --- Ambient light ---
	if fog_env != null:
		var ambient_energy: float = lerp(0.46, 0.68, sun_factor) if not is_night else 0.62
		fog_env.ambient_light_energy = ambient_energy

		if is_night:
			fog_env.ambient_light_color = Color(0.32, 0.10, 0.72)
		elif is_sunrise_sunset:
			var t: float = clamp(sun_altitude / 0.25, 0.0, 1.0)
			fog_env.ambient_light_color = Color(0.83, 0.41, 0.01).lerp(Color(0.87, 0.89, 0.13), t)
		else:
			fog_env.ambient_light_color = Color(0.87, 0.89, 0.13)

		# --- Fog color follows sky ---
		if is_night:
			fog_env.fog_light_color = Color(0.15, 0.08, 0.42)
		elif is_sunrise_sunset:
			var t: float = clamp(sun_altitude / 0.25, 0.0, 1.0)
			fog_env.fog_light_color = Color(0.72, 0.25, 0.97).lerp(Color(0.98, 1.00, 0.00), t)
		else:
			fog_env.fog_light_color = Color(0.98, 1.00, 0.00)

	# --- HUD time label ---
	if hud_time_label != null:
		var hours: int = int(time_of_day) % 24
		var minutes: int = int(fmod(time_of_day, 1.0) * 60.0)
		hud_time_label.text = "Dia %d - %02d:%02d" % [day_count, hours, minutes]

func _create_world() -> void:
	world_root = Node3D.new()
	world_root.name = "Biome1_Inicio_100x100"
	add_child(world_root)

	_generate_biome_one_data()
	_build_visible_world()
	_create_world_bounds()

	var spawn_surface_y: int = _surface_y_at(52, 52)
	var spawn_chest_pos: Vector3i = Vector3i(52, spawn_surface_y + 1, 52)
	var spawn_chest_slots: Array = _make_slots(CHEST_SLOT_COUNT)
	_set_block(spawn_chest_pos, "chest")
	_add_item_to_slots(spawn_chest_slots, "planks", 8)
	_add_item_to_slots(spawn_chest_slots, "coal", 4)
	chest_inventories[spawn_chest_pos] = spawn_chest_slots

func _create_loading_panel() -> void:
	loading_panel = _make_center_menu_panel(Vector2(400, 160))
	loading_panel.visible = false
	ui_layer.add_child(loading_panel)
	
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	loading_panel.add_child(root)
	
	loading_label = Label.new()
	loading_label.text = "Preparando o mundo..."
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.add_theme_font_size_override("font_size", 18)
	root.add_child(loading_label)
	
	loading_progress_bar = ProgressBar.new()
	loading_progress_bar.custom_minimum_size = Vector2(340, 24)
	loading_progress_bar.value = 0.0
	root.add_child(loading_progress_bar)

func _generate_biome_one_data() -> void:
	blocks.clear()
	block_nodes.clear()
	surface_heights.clear()
	chest_inventories.clear()

	var terrain_noise: FastNoiseLite = FastNoiseLite.new()
	terrain_noise.seed = WORLD_SEED
	terrain_noise.frequency = 0.045
	terrain_noise.fractal_octaves = 3

	var detail_noise: FastNoiseLite = FastNoiseLite.new()
	detail_noise.seed = WORLD_SEED + 17
	detail_noise.frequency = 0.12
	detail_noise.fractal_octaves = 2

	var cave_noise: FastNoiseLite = FastNoiseLite.new()
	cave_noise.seed = WORLD_SEED + 41
	cave_noise.frequency = 0.075
	cave_noise.fractal_octaves = 4

	var cave_detail_noise: FastNoiseLite = FastNoiseLite.new()
	cave_detail_noise.seed = WORLD_SEED + 77
	cave_detail_noise.frequency = 0.13
	cave_detail_noise.fractal_octaves = 3

	for x in range(BIOME_MIN_X, BIOME_MAX_X + 1):
		for z in range(BIOME_MIN_Z, BIOME_MAX_Z + 1):
			var surface_y: int = _procedural_surface_y(x, z, terrain_noise, detail_noise)
			surface_heights[Vector2i(x, z)] = surface_y
			var bedrock_y: int = _column_bedrock_y(surface_y)
			var cave_entrance: bool = _is_cave_entrance(x, z, surface_y, cave_noise)
			for y in range(bedrock_y, surface_y + 1):
				var depth: int = surface_y - y
				if y == bedrock_y:
					_set_block_data(Vector3i(x, y, z), "bedrock")
				elif _is_signature_cave_at(x, y, z, surface_y, bedrock_y):
					continue
				elif cave_entrance and depth <= 5:
					continue
				elif depth > 2 and _is_cave_at(x, y, z, surface_y, bedrock_y, cave_noise, cave_detail_noise):
					continue
				elif y == surface_y:
					_set_block_data(Vector3i(x, y, z), "grass")
				elif depth <= 3:
					_set_block_data(Vector3i(x, y, z), "dirt")
				else:
					_set_block_data(Vector3i(x, y, z), _stone_or_ore_for_depth(x, y, z, depth))

	_generate_procedural_trees()
	_generate_ground_decorations()

func _procedural_surface_y(x: int, z: int, terrain_noise: FastNoiseLite, detail_noise: FastNoiseLite) -> int:
	var broad: float = terrain_noise.get_noise_2d(float(x), float(z))
	var detail: float = detail_noise.get_noise_2d(float(x), float(z))
	var height: int = int(round(float(SURFACE_BASE_Y) + broad * 5.0 + detail * 2.0))
	return clamp(height, SURFACE_MIN_Y, SURFACE_MAX_Y)

func _column_bedrock_y(surface_y: int) -> int:
	return surface_y - WORLD_DEPTH + 1

func _is_signature_cave_at(x: int, y: int, z: int, surface_y: int, bedrock_y: int) -> bool:
	if y <= bedrock_y + 1:
		return false
	var depth: int = surface_y - y
	if depth < 0:
		return false
	var t: float = clamp(float(depth) / float(WORLD_DEPTH - 4), 0.0, 1.0)
	var center: Vector2 = _signature_cave_center(t)
	var radius: float = _signature_cave_radius(t)
	var horizontal_distance: float = Vector2(float(x), float(z)).distance_to(center)
	if horizontal_distance <= radius:
		return true

	var entrance_center: Vector2 = _signature_cave_center(0.0)
	var entrance_distance: float = Vector2(float(x), float(z)).distance_to(entrance_center)
	if depth <= 7 and entrance_distance <= 14.0:
		return true
	return false

func _signature_cave_center(t: float) -> Vector2:
	var curved_x: float = lerp(24.0, 78.0, t) + sin(t * TAU * 1.35) * 10.0
	var curved_z: float = lerp(14.0, 82.0, t) + sin(t * TAU * 0.9 + 0.8) * 8.0
	return Vector2(curved_x, curved_z)

func _signature_cave_radius(t: float) -> float:
	var belly: float = sin(t * PI)
	return 7.5 + belly * 5.0 + (1.0 - t) * 2.0

func _is_cave_entrance(x: int, z: int, surface_y: int, cave_noise: FastNoiseLite) -> bool:
	var spawn_distance: float = Vector2(float(x - 50), float(z - 50)).length()
	if spawn_distance < 10.0:
		return false
	var entrance_noise: float = cave_noise.get_noise_3d(float(x), float(surface_y - 4), float(z))
	return entrance_noise > 0.56 and _hash01(x, surface_y, z, 9001) > 0.82

func _is_cave_at(
	x: int,
	y: int,
	z: int,
	surface_y: int,
	bedrock_y: int,
	cave_noise: FastNoiseLite,
	cave_detail_noise: FastNoiseLite
) -> bool:
	var depth: int = surface_y - y
	if depth < 3 or y <= bedrock_y + 1:
		return false
	var spawn_distance: float = Vector3(float(x - 50), float(y - surface_y), float(z - 50)).length()
	if spawn_distance < 8.0 and depth < 16:
		return false
	var main_value: float = cave_noise.get_noise_3d(float(x), float(y), float(z))
	var detail_value: float = cave_detail_noise.get_noise_3d(float(x), float(y), float(z))
	if depth < 8:
		return main_value > 0.62 and detail_value > 0.18
	return main_value > 0.46 and detail_value > -0.08

func _stone_or_ore_for_depth(x: int, y: int, z: int, depth: int) -> String:
	var roll: float = _hash01(x, y, z, 123)
	if depth >= 44 and roll < 0.006:
		return "manita_ore"
	if depth >= 22 and roll < 0.024:
		return "iron_ore"
	if depth >= 8 and depth <= 44 and roll < 0.042:
		return "copper_ore"
	if depth >= 5 and roll < 0.068:
		return "coal_ore"
	return "stone"

func _hash01(x: int, y: int, z: int, salt: int) -> float:
	var value: float = sin(float(x) * 12.9898 + float(y) * 78.233 + float(z) * 37.719 + float(salt) * 19.19) * 43758.5453
	return value - floor(value)

func _create_world_bounds() -> void:
	_add_world_wall(
		"WorldWall_West",
		Vector3(BIOME_MIN_X - 1, BEDROCK_Y + WORLD_WALL_HEIGHT * 0.5, BIOME_SIZE * 0.5 - 0.5),
		Vector3(1, WORLD_WALL_HEIGHT, BIOME_SIZE + 2)
	)
	_add_world_wall(
		"WorldWall_East",
		Vector3(BIOME_MAX_X + 1, BEDROCK_Y + WORLD_WALL_HEIGHT * 0.5, BIOME_SIZE * 0.5 - 0.5),
		Vector3(1, WORLD_WALL_HEIGHT, BIOME_SIZE + 2)
	)
	_add_world_wall(
		"WorldWall_North",
		Vector3(BIOME_SIZE * 0.5 - 0.5, BEDROCK_Y + WORLD_WALL_HEIGHT * 0.5, BIOME_MIN_Z - 1),
		Vector3(BIOME_SIZE + 2, WORLD_WALL_HEIGHT, 1)
	)
	_add_world_wall(
		"WorldWall_South",
		Vector3(BIOME_SIZE * 0.5 - 0.5, BEDROCK_Y + WORLD_WALL_HEIGHT * 0.5, BIOME_MAX_Z + 1),
		Vector3(BIOME_SIZE + 2, WORLD_WALL_HEIGHT, 1)
	)

func _add_world_wall(wall_name: String, wall_position: Vector3, wall_size: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = wall_name
	body.position = wall_position
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = wall_size
	collision.shape = shape
	body.add_child(collision)
	world_root.add_child(body)

func _generate_procedural_trees() -> void:
	for x in range(6, BIOME_SIZE - 6, 4):
		for z in range(6, BIOME_SIZE - 6, 4):
			var roll: float = _hash01(x, 7, z, 404)
			if roll < 0.86:
				continue
			var jitter_x: int = int(floor(_hash01(x, 1, z, 405) * 3.0)) - 1
			var jitter_z: int = int(floor(_hash01(x, 2, z, 406) * 3.0)) - 1
			var tree_x: int = clamp(x + jitter_x, BIOME_MIN_X + 3, BIOME_MAX_X - 3)
			var tree_z: int = clamp(z + jitter_z, BIOME_MIN_Z + 3, BIOME_MAX_Z - 3)
			if Vector2(float(tree_x - 50), float(tree_z - 50)).length() < 9.0:
				continue
			var surface_y: int = _surface_y_at(tree_x, tree_z)
			var ground_pos: Vector3i = Vector3i(tree_x, surface_y, tree_z)
			if blocks.get(ground_pos, "") == "grass":
				_place_tree_data(Vector3i(tree_x, surface_y + 1, tree_z))

func _generate_ground_decorations() -> void:
	for x in range(BIOME_MIN_X, BIOME_MAX_X + 1):
		for z in range(BIOME_MIN_Z, BIOME_MAX_Z + 1):
			if Vector2(float(x - 50), float(z - 50)).length() < 9.0:
				continue
				
			var surface_y: int = _surface_y_at(x, z)
			var pos: Vector3i = Vector3i(x, surface_y, z)
			if blocks.get(pos, "") != "grass":
				continue
				
			var spawn_pos: Vector3i = Vector3i(x, surface_y + 1, z)
			if blocks.has(spawn_pos) and blocks[spawn_pos] != "" and blocks[spawn_pos] != "air":
				continue
				
			var roll: float = _hash01(x, surface_y, z, 707)
			if roll < 0.12:
				var roll_decor: float = _hash01(x, surface_y, z, 808)
				var decor_id: String = ""
				if roll_decor < 0.55:
					decor_id = "short_grass"
				elif roll_decor < 0.80:
					decor_id = "wild_grass"
				elif roll_decor < 0.88:
					decor_id = "dandelion"
				elif roll_decor < 0.96:
					decor_id = "poppy"
				elif roll_decor < 0.98:
					decor_id = "cornflower"
				else:
					decor_id = "oxeye_daisy"
				
				_set_block_data(spawn_pos, decor_id)

func _place_tree_data(base: Vector3i) -> void:
	var trunk_height: int = 4 + int(floor(_hash01(base.x, base.y, base.z, 505) * 3.0))
	for y in range(0, trunk_height):
		_set_block_data(base + Vector3i(0, y, 0), "wood")
	var leaf_center_y: int = trunk_height
	
	# Determine clump configurations deterministically based on tree position
	var center_r: float = 2.8 + _hash01(base.x, base.y, base.z, 100) * 0.8 # 2.8 to 3.6
	
	# Clump 1 (offset North-East-ish)
	var c1_offset_x: float = 1.0 + _hash01(base.x, base.y, base.z, 101) * 1.5
	var c1_offset_z: float = 1.0 + _hash01(base.x, base.y, base.z, 102) * 1.5
	var c1_offset_y: float = float(leaf_center_y) + _hash01(base.x, base.y, base.z, 103) * 1.5
	var c1_r: float = 1.8 + _hash01(base.x, base.y, base.z, 104) * 0.8
	
	# Clump 2 (offset South-West-ish)
	var c2_offset_x: float = -1.0 - _hash01(base.x, base.y, base.z, 105) * 1.5
	var c2_offset_z: float = -1.0 - _hash01(base.x, base.y, base.z, 106) * 1.5
	var c2_offset_y: float = float(leaf_center_y) - 0.5 + _hash01(base.x, base.y, base.z, 107) * 1.5
	var c2_r: float = 1.7 + _hash01(base.x, base.y, base.z, 108) * 0.8
	
	# Clump 3 (Top cap)
	var c3_offset_x: float = (_hash01(base.x, base.y, base.z, 109) - 0.5) * 1.0
	var c3_offset_z: float = (_hash01(base.x, base.y, base.z, 110) - 0.5) * 1.0
	var c3_offset_y: float = float(leaf_center_y) + 2.2 + _hash01(base.x, base.y, base.z, 111) * 1.0
	var c3_r: float = 1.5 + _hash01(base.x, base.y, base.z, 112) * 0.6

	# Bounding box search: x in [-4, 4], z in [-4, 4], y offsets from -3 to 5
	for y_offset in range(-3, 6):
		for x in range(-4, 5):
			for z in range(-4, 5):
				var pos: Vector3i = base + Vector3i(x, leaf_center_y + y_offset, z)
				if blocks.has(pos):
					continue
				
				var in_canopy: bool = false
				var edge_dist: float = 999.0
				
				# Central clump check
				var d_cent: float = Vector3(float(x), float(y_offset) - 0.5, float(z)).length()
				if d_cent <= center_r:
					in_canopy = true
					edge_dist = min(edge_dist, center_r - d_cent)
				
				# Clump 1 check
				var d_c1: float = Vector3(float(x) - c1_offset_x, float(y_offset) - (c1_offset_y - leaf_center_y), float(z) - c1_offset_z).length()
				if d_c1 <= c1_r:
					in_canopy = true
					edge_dist = min(edge_dist, c1_r - d_c1)
				
				# Clump 2 check
				var d_c2: float = Vector3(float(x) - c2_offset_x, float(y_offset) - (c2_offset_y - leaf_center_y), float(z) - c2_offset_z).length()
				if d_c2 <= c2_r:
					in_canopy = true
					edge_dist = min(edge_dist, c2_r - d_c2)
				
				# Clump 3 check
				var d_c3: float = Vector3(float(x) - c3_offset_x, float(y_offset) - (c3_offset_y - leaf_center_y), float(z) - c3_offset_z).length()
				if d_c3 <= c3_r:
					in_canopy = true
					edge_dist = min(edge_dist, c3_r - d_c3)
				
				if not in_canopy:
					continue
				
				# Calculate skip chance to make the canopy silhouette softer and irregular
				var skip_chance: float = 0.05
				if edge_dist < 0.8:
					skip_chance += (0.8 - edge_dist) * 0.45
				
				# Softer lower skirt (y_offset <= -2)
				if y_offset <= -2:
					skip_chance += 0.25 + (abs(y_offset) - 2) * 0.2
				# Uneven top cap (y_offset >= 3)
				elif y_offset >= 3:
					skip_chance += 0.20 + (y_offset - 3) * 0.15
				
				# Deterministic noise check
				var gap_roll: float = _hash01(pos.x, pos.y, pos.z, 612)
				if gap_roll < skip_chance:
					continue
				
				_set_block_data(pos, "leaves")

func _surface_y_at(x: int, z: int) -> int:
	var key: Vector2i = Vector2i(x, z)
	return int(surface_heights.get(key, SURFACE_BASE_Y))

func _create_player() -> void:
	player = TrumanPlayer.new()
	player.name = "Player"
	player.position = Vector3(50.5, float(_surface_y_at(50, 50)) + 2.4, 50.5)
	add_child(player)
	player.set_camera_mode(saved_camera_mode)
	_apply_current_skin()
	_sync_held_item(true)
	_update_player_visual_visibility()

func _create_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)

	crosshair_label = Label.new()
	crosshair_label.text = "+"
	crosshair_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair_label.set_anchors_preset(Control.PRESET_CENTER)
	crosshair_label.position = Vector2(-8, -12)
	crosshair_label.size = Vector2(24, 24)
	ui_layer.add_child(crosshair_label)

	status_label = Label.new()
	status_label.position = Vector2(16, 12)
	status_label.size = Vector2(720, 86)
	ui_layer.add_child(status_label)

	message_label = Label.new()
	message_label.position = Vector2(16, 104)
	message_label.size = Vector2(980, 44)
	ui_layer.add_child(message_label)

	hud_time_label = Label.new()
	hud_time_label.position = Vector2(16, 70)
	hud_time_label.size = Vector2(260, 30)
	hud_time_label.add_theme_font_size_override("font_size", 14)
	hud_time_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 0.85))
	ui_layer.add_child(hud_time_label)

	cursor_stack_slot = ItemSlot.new()
	cursor_stack_slot.visible = false
	cursor_stack_slot.z_index = 100
	cursor_stack_slot.configure(self, "cursor", -1, "", 0, "", "", null, {}, Vector2(58, 58), false)
	ui_layer.add_child(cursor_stack_slot)

	hotbar_box = HBoxContainer.new()
	hotbar_box.position = Vector2(220, 650)
	hotbar_box.size = Vector2(840, 54)
	ui_layer.add_child(hotbar_box)

	_create_inventory_panel()
	_create_chest_panel()
	_create_tooltip_panel()
	_create_menu_panels()
	_update_hotbar()
	_update_status()

func _make_square_box(bg_color: Color, border_color: Color, border_width: int, content_margin: float = 0.0) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	style.set_content_margin(SIDE_LEFT, content_margin)
	style.set_content_margin(SIDE_RIGHT, content_margin)
	style.set_content_margin(SIDE_TOP, content_margin)
	style.set_content_margin(SIDE_BOTTOM, content_margin)
	return style

func _apply_square_panel_style(panel: PanelContainer) -> void:
	panel.add_theme_stylebox_override("panel", _make_square_box(Color(0.07, 0.07, 0.07, 0.96), Color(0.34, 0.34, 0.34, 1.0), 2, 14.0))

func _apply_square_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _make_square_box(Color(0.18, 0.18, 0.18, 1.0), Color(0.42, 0.42, 0.42, 1.0), 1, 8.0))
	button.add_theme_stylebox_override("hover", _make_square_box(Color(0.26, 0.26, 0.26, 1.0), Color(0.58, 0.58, 0.58, 1.0), 1, 8.0))
	button.add_theme_stylebox_override("pressed", _make_square_box(Color(0.11, 0.11, 0.11, 1.0), Color(0.78, 0.78, 0.78, 1.0), 1, 8.0))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.custom_minimum_size = Vector2(0, 34)

func _make_menu_button(text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	_apply_square_button_style(button)
	button.pressed.connect(callback)
	return button

func _create_menu_panels() -> void:
	main_menu_panel = _make_center_menu_panel(Vector2(380, 340))
	ui_layer.add_child(main_menu_panel)

	var main_root: VBoxContainer = VBoxContainer.new()
	main_root.add_theme_constant_override("separation", 10)
	main_menu_panel.add_child(main_root)

	var title: Label = Label.new()
	title.text = "TRUMANCRAFT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	main_root.add_child(title)

	continue_button = _make_menu_button("Continuar", _continue_game)
	main_root.add_child(continue_button)
	main_root.add_child(_make_menu_button("Novo Jogo", _start_new_game))
	main_root.add_child(_make_menu_button("Opcoes", _open_options_from_main))
	main_root.add_child(_make_menu_button("Sair", _quit_game))

	menu_status_label = Label.new()
	menu_status_label.text = ""
	menu_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_root.add_child(menu_status_label)

	pause_menu_panel = _make_center_menu_panel(Vector2(380, 360))
	pause_menu_panel.visible = false
	ui_layer.add_child(pause_menu_panel)

	var pause_root: VBoxContainer = VBoxContainer.new()
	pause_root.add_theme_constant_override("separation", 10)
	pause_menu_panel.add_child(pause_root)

	var pause_title: Label = Label.new()
	pause_title.text = "Pausado"
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_title.add_theme_font_size_override("font_size", 24)
	pause_root.add_child(pause_title)
	pause_root.add_child(_make_menu_button("Voltar ao jogo", _resume_game))
	pause_root.add_child(_make_menu_button("Salvar", _save_from_pause_menu))
	pause_root.add_child(_make_menu_button("Opcoes", _open_options_from_pause))
	pause_root.add_child(_make_menu_button("Menu inicial", _return_to_main_menu))

	pause_status_label = Label.new()
	pause_status_label.text = ""
	pause_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pause_root.add_child(pause_status_label)

	options_panel = _make_center_menu_panel(Vector2(420, 390))
	options_panel.visible = false
	ui_layer.add_child(options_panel)

	var options_root: VBoxContainer = VBoxContainer.new()
	options_root.add_theme_constant_override("separation", 12)
	options_panel.add_child(options_root)

	var options_title: Label = Label.new()
	options_title.text = "Opcoes"
	options_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	options_title.add_theme_font_size_override("font_size", 24)
	options_root.add_child(options_title)

	fullscreen_toggle = CheckBox.new()
	fullscreen_toggle.text = "Tela cheia"
	fullscreen_toggle.button_pressed = fullscreen_enabled
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	options_root.add_child(fullscreen_toggle)

	shadows_toggle = CheckBox.new()
	shadows_toggle.text = "Sombras"
	shadows_toggle.button_pressed = shadows_enabled
	shadows_toggle.toggled.connect(_on_shadows_toggled)
	options_root.add_child(shadows_toggle)

	ssao_toggle = CheckBox.new()
	ssao_toggle.text = "SSAO"
	ssao_toggle.button_pressed = ssao_enabled
	ssao_toggle.toggled.connect(_on_ssao_toggled)
	options_root.add_child(ssao_toggle)

	voxel_ao_toggle = CheckBox.new()
	voxel_ao_toggle.text = "Voxel AO"
	voxel_ao_toggle.button_pressed = voxel_ao_enabled
	voxel_ao_toggle.toggled.connect(_on_voxel_ao_toggled)
	options_root.add_child(voxel_ao_toggle)

	options_root.add_child(_make_menu_button("Importar skin", _open_skin_file_dialog))

	options_status_label = Label.new()
	options_status_label.text = ""
	options_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	options_root.add_child(options_status_label)

	options_root.add_child(_make_menu_button("Voltar", _close_options_panel))
	_create_skin_file_dialog()
	_create_loading_panel()

func _make_center_menu_panel(panel_size: Vector2) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size = panel_size
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -panel_size * 0.5
	_apply_square_panel_style(panel)
	return panel

func _is_menu_open() -> bool:
	return (
		(main_menu_panel != null and main_menu_panel.visible)
		or (pause_menu_panel != null and pause_menu_panel.visible)
		or (options_panel != null and options_panel.visible)
	)

func _show_main_menu() -> void:
	game_started = false
	_return_cursor_stack_to_inventory()
	_return_craft_slots_to_inventory()
	_cancel_slot_drags()
	if inventory_panel != null:
		inventory_panel.visible = false
	if chest_panel != null:
		chest_panel.visible = false
	if pause_menu_panel != null:
		pause_menu_panel.visible = false
	if options_panel != null:
		options_panel.visible = false
	if main_menu_panel != null:
		main_menu_panel.visible = true
	if continue_button != null:
		continue_button.disabled = not FileAccess.file_exists(SAVE_PATH)
	if menu_status_label != null:
		menu_status_label.text = ""
	_set_game_hud_visible(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if player != null:
		player.set_controls_enabled(false)

func _start_new_game() -> void:
	_start_world_loading(true, false)

func _continue_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		if menu_status_label != null:
			menu_status_label.text = "Nenhum save encontrado."
		return
	_start_world_loading(false, true)

func _start_world_loading(enable_tracking: bool, is_continue: bool) -> void:
	tracking_on_load_finish = enable_tracking
	continue_on_load_finish = is_continue
	
	if main_menu_panel != null:
		main_menu_panel.visible = false
	if pause_menu_panel != null:
		pause_menu_panel.visible = false
	if options_panel != null:
		options_panel.visible = false
	if loading_panel != null:
		loading_panel.visible = true
		loading_progress_bar.value = 0.0
		loading_label.text = "Carregando mundo salvo..." if is_continue else "Gerando Bioma..."
		
	# Wait one frame for UI to update
	await get_tree().process_frame
	
	# Reset states
	tracking_world_changes = false
	changed_blocks.clear()
	removed_blocks.clear()
	blocks.clear()
	block_nodes.clear()
	chunk_nodes.clear()
	blocks_in_chunk.clear()
	dirty_chunk_queue.clear()
	dirty_chunk_keys.clear()
	last_collision_update_pos = Vector3i(-999, -999, -999)
	surface_heights.clear()
	chest_inventories.clear()
	inventory_slots = _make_slots(INVENTORY_SLOT_COUNT)
	craft_slots = _make_slots(4)
	craft_size = 2
	craft_context = "inventory"
	selected_hotbar_index = 0
	mana = MANA_MAX
	manita_pickaxe_xp = 0
	manita_pickaxe_level = 1
	time_of_day = 8.0
	day_count = 1
	current_chest_pos = Vector3i.ZERO
	has_current_chest = false
	cursor_stack = _empty_slot()
	left_drag_active = false
	left_drag_targets.clear()
	left_drag_keys.clear()
	right_drag_active = false
	right_drag_keys.clear()
	
	for item in dropped_items:
		if is_instance_valid(item):
			item.queue_free()
	dropped_items.clear()
	_clear_leaf_particles()
	breaking_pos = Vector3i(-999, -999, -999)
	breaking_progress = 0.0
	breaking_overlay = null
	_clear_target_outline()
	
	if world_root != null and is_instance_valid(world_root):
		remove_child(world_root)
		world_root.queue_free()
	if player != null and is_instance_valid(player):
		remove_child(player)
		player.queue_free()
		
	world_root = Node3D.new()
	world_root.name = "Biome1_Inicio_100x100"
	add_child(world_root)
	
	_generate_biome_one_data()
		
	if is_continue:
		if not _load_game_state():
			if menu_status_label != null:
				menu_status_label.text = "Nao foi possivel carregar o save."
			_show_main_menu()
			if loading_panel != null:
				loading_panel.visible = false
			return
			
	var active_chunks: Dictionary = {}
	for pos in blocks.keys():
		var c_pos = _get_chunk_coords(pos)
		active_chunks[c_pos] = true
		
	chunks_to_mesh = active_chunks.keys()
	total_chunks_to_mesh = chunks_to_mesh.size()
	meshed_chunks_count = 0
	dirty_chunk_queue.clear()
	dirty_chunk_keys.clear()
	is_loading_world = true

func _finish_world_loading() -> void:
	is_loading_world = false
	if loading_panel != null:
		loading_panel.visible = false
		
	_create_world_bounds()
	_create_player()
	
	if continue_on_load_finish:
		if not loaded_game_data.is_empty():
			player.position = _vector3_from_data(loaded_game_data.get("player_position", []), player.position)
			player.set_view_angles(
				float(loaded_game_data.get("player_rotation_y", player.get_camera_yaw())),
				float(loaded_game_data.get("camera_pitch", player.get_camera_pitch()))
			)
	else:
		_give_start_items()
		var spawn_surface_y: int = _surface_y_at(52, 52)
		var spawn_chest_pos: Vector3i = Vector3i(52, spawn_surface_y + 1, 52)
		var spawn_chest_slots: Array = _make_slots(CHEST_SLOT_COUNT)
		_set_block(spawn_chest_pos, "chest")
		_add_item_to_slots(spawn_chest_slots, "planks", 8)
		_add_item_to_slots(spawn_chest_slots, "coal", 4)
		chest_inventories[spawn_chest_pos] = spawn_chest_slots
		
	# Build active collisions around the player's position immediately
	_update_active_collisions(player.position)
	
	tracking_world_changes = tracking_on_load_finish
	_begin_gameplay()
	
	if continue_on_load_finish:
		_message("Save carregado.")
	else:
		_message("Novo jogo iniciado.")

func _begin_gameplay() -> void:
	game_started = true
	tracking_world_changes = true
	if main_menu_panel != null:
		main_menu_panel.visible = false
	if pause_menu_panel != null:
		pause_menu_panel.visible = false
	if options_panel != null:
		options_panel.visible = false
	_set_game_hud_visible(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	player.set_controls_enabled(true)
	_update_all_ui()

func _show_pause_menu() -> void:
	if not game_started:
		return
	_return_cursor_stack_to_inventory()
	_cancel_slot_drags()
	if inventory_panel != null:
		inventory_panel.visible = false
	if chest_panel != null:
		chest_panel.visible = false
	if pause_menu_panel != null:
		pause_menu_panel.visible = true
	if main_menu_panel != null:
		main_menu_panel.visible = false
	if options_panel != null:
		options_panel.visible = false
	if pause_status_label != null:
		pause_status_label.text = ""
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	player.set_controls_enabled(false)
	_update_player_visual_visibility()

func _resume_game() -> void:
	if not game_started:
		return
	if pause_menu_panel != null:
		pause_menu_panel.visible = false
	if options_panel != null:
		options_panel.visible = false
	_set_game_hud_visible(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	player.set_controls_enabled(true)
	_update_player_visual_visibility()

func _return_to_main_menu() -> void:
	_show_main_menu()

func _open_options_from_main() -> void:
	_open_options_panel("main")

func _open_options_from_pause() -> void:
	_open_options_panel("pause")

func _open_options_panel(origin: String) -> void:
	options_origin = origin
	if fullscreen_toggle != null:
		fullscreen_toggle.button_pressed = fullscreen_enabled
	if shadows_toggle != null:
		shadows_toggle.button_pressed = shadows_enabled
	if ssao_toggle != null:
		ssao_toggle.button_pressed = ssao_enabled
	if voxel_ao_toggle != null:
		voxel_ao_toggle.button_pressed = voxel_ao_enabled
	if main_menu_panel != null:
		main_menu_panel.visible = false
	if pause_menu_panel != null:
		pause_menu_panel.visible = false
	if options_panel != null:
		options_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if player != null:
		player.set_controls_enabled(false)
	_update_player_visual_visibility()

func _close_options_panel() -> void:
	if options_panel != null:
		options_panel.visible = false
	if options_origin == "pause" and game_started:
		if pause_menu_panel != null:
			pause_menu_panel.visible = true
	else:
		if main_menu_panel != null:
			main_menu_panel.visible = true
	_update_player_visual_visibility()

func _save_from_pause_menu() -> void:
	if _save_game_state():
		if pause_status_label != null:
			pause_status_label.text = "Jogo salvo."
		if continue_button != null:
			continue_button.disabled = false
	else:
		if pause_status_label != null:
			pause_status_label.text = "Nao foi possivel salvar."

func _quit_game() -> void:
	get_tree().quit()

func _on_fullscreen_toggled(enabled: bool) -> void:
	fullscreen_enabled = enabled
	_apply_fullscreen(fullscreen_enabled)
	_save_settings()

func _on_shadows_toggled(enabled: bool) -> void:
	shadows_enabled = enabled
	_apply_shadow_setting()
	_save_settings()

func _on_ssao_toggled(enabled: bool) -> void:
	ssao_enabled = enabled
	_apply_ssao_setting()
	_save_settings()

func _on_voxel_ao_toggled(enabled: bool) -> void:
	voxel_ao_enabled = enabled
	_refresh_all_chunk_meshes()
	_save_settings()

func _open_skin_file_dialog() -> void:
	if skin_file_dialog == null:
		return
	skin_file_dialog.popup_centered_ratio(0.65)

func _on_skin_file_selected(path: String) -> void:
	var result: Dictionary = SkinLoader.import_skin(path)
	if bool(result.get("ok", false)):
		player_skin_path = str(result.get("path", SkinLoader.PLAYER_SKIN_PATH))
		_apply_current_skin()
		_save_settings()
		if options_status_label != null:
			options_status_label.text = str(result.get("message", "Skin importada."))
	else:
		if options_status_label != null:
			options_status_label.text = str(result.get("message", "Skin invalida."))

func _apply_fullscreen(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _apply_shadow_setting() -> void:
	if not shadows_enabled:
		if sun_light != null:
			sun_light.shadow_enabled = false
		if moon_light != null:
			moon_light.shadow_enabled = false
		return
	_update_day_night_cycle(0.0)

func _apply_ssao_setting() -> void:
	if fog_env != null:
		fog_env.ssao_enabled = ssao_enabled

func _set_game_hud_visible(p_visible: bool) -> void:
	if crosshair_label != null:
		crosshair_label.visible = p_visible
	if status_label != null:
		status_label.visible = p_visible
	if message_label != null:
		message_label.visible = p_visible
	if hotbar_box != null:
		hotbar_box.visible = p_visible
	if cursor_stack_slot != null:
		cursor_stack_slot.visible = p_visible and _slot_item(cursor_stack) != ""
	if tooltip_panel != null and not p_visible:
		tooltip_panel.visible = false
	_update_player_visual_visibility()

func _create_skin_file_dialog() -> void:
	skin_file_dialog = FileDialog.new()
	skin_file_dialog.title = "Importar skin do Minecraft"
	skin_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	skin_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	skin_file_dialog.filters = PackedStringArray(["*.png ; Skin PNG"])
	skin_file_dialog.file_selected.connect(_on_skin_file_selected)
	ui_layer.add_child(skin_file_dialog)

func _create_inventory_panel() -> void:
	inventory_panel = PanelContainer.new()
	inventory_panel.visible = false
	inventory_panel.position = Vector2(215, 70)
	inventory_panel.size = Vector2(850, 560)
	_apply_square_panel_style(inventory_panel)
	ui_layer.add_child(inventory_panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	inventory_panel.add_child(root)

	craft_title_label = Label.new()
	craft_title_label.text = "Inventário & Fabricação"
	root.add_child(craft_title_label)

	var hint: Label = Label.new()
	hint.text = "Use Shift+Clique esquerdo para mover itens rapidamente."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)

	# TOP: Crafting Section
	var craft_section: HBoxContainer = HBoxContainer.new()
	craft_section.add_theme_constant_override("separation", 24)
	craft_section.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(craft_section)

	var craft_grid_container: VBoxContainer = VBoxContainer.new()
	craft_section.add_child(craft_grid_container)
	
	var craft_label: Label = Label.new()
	craft_label.text = "Fabricação"
	craft_grid_container.add_child(craft_label)

	craft_grid = GridContainer.new()
	craft_grid.columns = 2
	craft_grid_container.add_child(craft_grid)

	var arrow_label: Label = Label.new()
	arrow_label.text = "==>"
	arrow_label.add_theme_font_size_override("font_size", 20)
	arrow_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	craft_section.add_child(arrow_label)

	var output_container: VBoxContainer = VBoxContainer.new()
	craft_section.add_child(output_container)
	
	var output_label: Label = Label.new()
	output_label.text = "Resultado"
	output_container.add_child(output_label)

	craft_output_holder = CenterContainer.new()
	craft_output_holder.custom_minimum_size = Vector2(96, 70)
	output_container.add_child(craft_output_holder)

	craft_result_label = Label.new()
	craft_result_label.text = ""
	craft_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	output_container.add_child(craft_result_label)

	# Divider line
	var hs: HSeparator = HSeparator.new()
	root.add_child(hs)

	# BOTTOM: Inventory Section
	var inv_container: VBoxContainer = VBoxContainer.new()
	root.add_child(inv_container)
	
	var inv_label: Label = Label.new()
	inv_label.text = "Inventário do Jogador"
	inv_container.add_child(inv_label)

	inventory_grid = GridContainer.new()
	inventory_grid.columns = 9
	inventory_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inv_container.add_child(inventory_grid)

func _create_tooltip_panel() -> void:
	tooltip_panel = PanelContainer.new()
	tooltip_panel.visible = false
	tooltip_panel.z_index = 120
	tooltip_panel.custom_minimum_size = Vector2(220, 0)
	_apply_square_panel_style(tooltip_panel)
	ui_layer.add_child(tooltip_panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 3)
	tooltip_panel.add_child(root)

	tooltip_name_label = Label.new()
	tooltip_name_label.add_theme_font_size_override("font_size", 14)
	tooltip_name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	root.add_child(tooltip_name_label)

	tooltip_description_label = Label.new()
	tooltip_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_description_label.add_theme_font_size_override("font_size", 11)
	tooltip_description_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.9))
	root.add_child(tooltip_description_label)

func _create_chest_panel() -> void:
	chest_panel = PanelContainer.new()
	chest_panel.visible = false
	chest_panel.position = Vector2(215, 70)
	chest_panel.size = Vector2(850, 560)
	_apply_square_panel_style(chest_panel)
	ui_layer.add_child(chest_panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	chest_panel.add_child(root)

	var title: Label = Label.new()
	title.text = "Baú - use Shift+Clique para mover rápido"
	root.add_child(title)

	# TOP: Chest Section
	var chest_section: VBoxContainer = VBoxContainer.new()
	root.add_child(chest_section)
	
	var chest_title: Label = Label.new()
	chest_title.text = "Baú"
	chest_section.add_child(chest_title)
	
	chest_grid = GridContainer.new()
	chest_grid.columns = 9
	chest_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chest_section.add_child(chest_grid)

	# Divider line
	var hs: HSeparator = HSeparator.new()
	root.add_child(hs)

	# BOTTOM: Player Inventory Section
	var player_section: VBoxContainer = VBoxContainer.new()
	root.add_child(player_section)
	
	var player_title: Label = Label.new()
	player_title.text = "Inventário do Jogador"
	player_section.add_child(player_title)
	
	chest_player_grid = GridContainer.new()
	chest_player_grid.columns = 9
	chest_player_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	player_section.add_child(chest_player_grid)

	var close_button: Button = Button.new()
	close_button.text = "Fechar"
	_apply_square_button_style(close_button)
	close_button.pressed.connect(_close_all_panels)
	root.add_child(close_button)

func _give_start_items() -> void:
	_add_item("dirt", 12)
	_add_item("wood", 6)
	_add_item("planks", 8)
	_add_item("poppy", 5)
	_add_item("dandelion", 5)
	_add_item("short_grass", 5)
	_update_all_ui()

func _set_block(pos: Vector3i, block_id: String) -> void:
	if not block_defs.has(block_id):
		return
	blocks[pos] = block_id
	var c_pos: Vector2i = _get_chunk_coords(pos)
	if not blocks_in_chunk.has(c_pos):
		blocks_in_chunk[c_pos] = {}
	blocks_in_chunk[c_pos][pos] = block_id
	
	if tracking_world_changes:
		var key: String = _pos_key(pos)
		changed_blocks[key] = block_id
		removed_blocks.erase(key)
	_refresh_block_and_neighbors(pos)

func _set_block_data(pos: Vector3i, block_id: String) -> void:
	if not block_defs.has(block_id):
		return
	blocks[pos] = block_id
	var c_pos: Vector2i = _get_chunk_coords(pos)
	if not blocks_in_chunk.has(c_pos):
		blocks_in_chunk[c_pos] = {}
	blocks_in_chunk[c_pos][pos] = block_id

func _erase_block_data(pos: Vector3i) -> void:
	if blocks.has(pos):
		blocks.erase(pos)
	var c_pos: Vector2i = _get_chunk_coords(pos)
	if blocks_in_chunk.has(c_pos):
		blocks_in_chunk[c_pos].erase(pos)
		if blocks_in_chunk[c_pos].is_empty():
			blocks_in_chunk.erase(c_pos)

func _build_visible_world() -> void:
	chunk_nodes.clear()
	dirty_chunk_queue.clear()
	dirty_chunk_keys.clear()
	var active_chunks: Dictionary = {}
	for pos in blocks.keys():
		var c_pos: Vector2i = _get_chunk_coords(pos)
		active_chunks[c_pos] = true
	for c_pos in active_chunks.keys():
		_update_chunk_mesh(c_pos.x, c_pos.y)

func _refresh_all_chunk_meshes() -> void:
	for c_pos in blocks_in_chunk.keys():
		_queue_chunk_mesh_update(c_pos.x, c_pos.y)

func _get_chunk_coords(pos: Vector3i) -> Vector2i:
	return Vector2i(
		int(floor(float(pos.x) / CHUNK_SIZE)),
		int(floor(float(pos.z) / CHUNK_SIZE))
	)

func _get_chunk_node(cx: int, cz: int) -> Node3D:
	var key: Vector2i = Vector2i(cx, cz)
	if chunk_nodes.has(key):
		return chunk_nodes[key]
	var chunk: Node3D = Node3D.new()
	chunk.name = "Chunk_%s_%s" % [cx, cz]
	chunk.position = Vector3(cx * CHUNK_SIZE, 0, cz * CHUNK_SIZE)
	world_root.add_child(chunk)
	chunk_nodes[key] = chunk
	return chunk

func _update_chunk_mesh(cx: int, cz: int) -> void:
	var c_key: Vector2i = Vector2i(cx, cz)
	dirty_chunk_keys.erase(c_key)
	var chunk: Node3D = _get_chunk_node(cx, cz)
	
	for child in chunk.get_children():
		chunk.remove_child(child)
		child.queue_free()

	var chunk_blocks: Dictionary = blocks_in_chunk.get(c_key, {})
	var surface_builders: Dictionary = {}
	for pos in chunk_blocks.keys():
		var block_id: String = chunk_blocks[pos]
		if block_id == "" or block_id == "air" or not block_defs.has(block_id):
			continue
		var world_pos: Vector3i = pos
		var local_center: Vector3 = Vector3(
			world_pos.x - cx * CHUNK_SIZE,
			world_pos.y,
			world_pos.z - cz * CHUNK_SIZE
		)
		var block_data: Dictionary = block_defs[block_id]
		var fallback_color: Color = block_data.get("color", Color.WHITE)
		var alpha: float = float(block_data.get("alpha", 1.0))
		var transparent: bool = bool(block_data.get("transparent", false))
		var foliage: bool = bool(block_data.get("foliage", false))
		var is_plant: bool = bool(block_data.get("plant", false))
		if is_plant:
			var texture_path: String = block_data.get("texture", "")
			var material_key: String = "%s|%s|%.3f|%s|%s" % [texture_path, fallback_color.to_html(), alpha, str(transparent), str(foliage)]
			if not surface_builders.has(material_key):
				surface_builders[material_key] = {
					"texture_path": texture_path,
					"fallback_color": fallback_color,
					"alpha": alpha,
					"transparent": transparent,
					"foliage": foliage,
					"vertices": [],
					"normals": [],
					"uvs": [],
					"colors": [],
					"indices": []
				}
			_append_chunk_plant(surface_builders[material_key], local_center, world_pos, block_id)
		else:
			for face_name in ["north", "south", "east", "west", "top", "bottom"]:
				var face_offset: Vector3i = _face_offset(face_name)
				if not _is_block_face_visible(world_pos, face_offset, block_id):
					continue
				var texture_path: String = _block_texture_for_face(block_data, face_name)
				var material_key: String = "%s|%s|%.3f|%s|%s" % [texture_path, fallback_color.to_html(), alpha, str(transparent), str(foliage)]
				if not surface_builders.has(material_key):
					surface_builders[material_key] = {
						"texture_path": texture_path,
						"fallback_color": fallback_color,
						"alpha": alpha,
						"transparent": transparent,
						"foliage": foliage,
						"vertices": [],
						"normals": [],
						"uvs": [],
						"colors": [],
						"indices": []
					}
				_append_chunk_face(surface_builders[material_key], face_name, local_center, world_pos, block_id)

	if surface_builders.is_empty():
		return

	var mesh: ArrayMesh = ArrayMesh.new()
	for material_key in surface_builders.keys():
		var builder: Dictionary = surface_builders[material_key]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(builder["vertices"])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(builder["normals"])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(builder["uvs"])
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray(builder["colors"])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(builder["indices"])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var surface_index: int = mesh.get_surface_count() - 1
		mesh.surface_set_material(
			surface_index,
			_material_for_texture(
				str(builder["texture_path"]),
				builder["fallback_color"],
				float(builder.get("alpha", 1.0)),
				bool(builder.get("transparent", false)),
				bool(builder.get("foliage", false))
			)
		)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "ChunkMesh"
	mesh_instance.mesh = mesh
	chunk.add_child(mesh_instance)

func _append_chunk_face(builder: Dictionary, face_name: String, local_center: Vector3, world_pos: Vector3i, block_id: String) -> void:
	var vertices: PackedVector3Array = _face_vertices(face_name)
	var normal_offset: Vector3i = _face_offset(face_name)
	var normal: Vector3 = Vector3(normal_offset.x, normal_offset.y, normal_offset.z)
	var uvs: PackedVector2Array = _face_uvs_for_block(face_name, block_id, world_pos)
	var first_index: int = builder["vertices"].size()
	var ao_values: Array = []
	var alpha: float = float(builder.get("alpha", 1.0))
	for vertex in vertices:
		var ao: float = _vertex_ao_for_face(world_pos, face_name, vertex)
		ao_values.append(ao)
		builder["vertices"].append(local_center + vertex)
		builder["normals"].append(normal)
		builder["colors"].append(Color(ao, ao, ao, alpha))
	for uv in uvs:
		builder["uvs"].append(uv)
	if float(ao_values[0]) + float(ao_values[2]) > float(ao_values[1]) + float(ao_values[3]):
		builder["indices"].append_array([
			first_index,
			first_index + 1,
			first_index + 3,
			first_index + 1,
			first_index + 2,
			first_index + 3
		])
	else:
		builder["indices"].append_array([
			first_index,
			first_index + 1,
			first_index + 2,
			first_index,
			first_index + 2,
			first_index + 3
		])

func _append_chunk_plant(builder: Dictionary, local_center: Vector3, _world_pos: Vector3i, _block_id: String) -> void:
	var height: float = 0.8
	var p1_verts: PackedVector3Array = PackedVector3Array([
		Vector3(-0.5, -0.5, -0.5),
		Vector3(0.5, -0.5, 0.5),
		Vector3(0.5, -0.5 + height, 0.5),
		Vector3(-0.5, -0.5 + height, -0.5)
	])
	var p1_normal: Vector3 = Vector3(-0.7071, 0.0, 0.7071)
	
	var p2_verts: PackedVector3Array = PackedVector3Array([
		Vector3(-0.5, -0.5, 0.5),
		Vector3(0.5, -0.5, -0.5),
		Vector3(0.5, -0.5 + height, -0.5),
		Vector3(-0.5, -0.5 + height, 0.5)
	])
	var p2_normal: Vector3 = Vector3(0.7071, 0.0, 0.7071)

	var uvs: PackedVector2Array = PackedVector2Array([
		Vector2(0, 1),
		Vector2(1, 1),
		Vector2(1, 0),
		Vector2(0, 0)
	])
	
	var alpha: float = float(builder.get("alpha", 1.0))

	# Plane 1
	var first_index: int = builder["vertices"].size()
	for i in range(4):
		builder["vertices"].append(local_center + p1_verts[i])
		builder["normals"].append(p1_normal)
		builder["colors"].append(Color(1.0, 1.0, 1.0, alpha))
		builder["uvs"].append(uvs[i])
	builder["indices"].append_array([
		first_index,
		first_index + 1,
		first_index + 2,
		first_index,
		first_index + 2,
		first_index + 3
	])

	# Plane 2
	first_index = builder["vertices"].size()
	for i in range(4):
		builder["vertices"].append(local_center + p2_verts[i])
		builder["normals"].append(p2_normal)
		builder["colors"].append(Color(1.0, 1.0, 1.0, alpha))
		builder["uvs"].append(uvs[i])
	builder["indices"].append_array([
		first_index,
		first_index + 1,
		first_index + 2,
		first_index,
		first_index + 2,
		first_index + 3
	])

func _face_vertices(face_name: String) -> PackedVector3Array:
	match face_name:
		"north":
			return PackedVector3Array([
				Vector3(-0.5, -0.5, -0.5),
				Vector3(0.5, -0.5, -0.5),
				Vector3(0.5, 0.5, -0.5),
				Vector3(-0.5, 0.5, -0.5)
			])
		"south":
			return PackedVector3Array([
				Vector3(0.5, -0.5, 0.5),
				Vector3(-0.5, -0.5, 0.5),
				Vector3(-0.5, 0.5, 0.5),
				Vector3(0.5, 0.5, 0.5)
			])
		"east":
			return PackedVector3Array([
				Vector3(0.5, -0.5, -0.5),
				Vector3(0.5, -0.5, 0.5),
				Vector3(0.5, 0.5, 0.5),
				Vector3(0.5, 0.5, -0.5)
			])
		"west":
			return PackedVector3Array([
				Vector3(-0.5, -0.5, 0.5),
				Vector3(-0.5, -0.5, -0.5),
				Vector3(-0.5, 0.5, -0.5),
				Vector3(-0.5, 0.5, 0.5)
			])
		"top":
			return PackedVector3Array([
				Vector3(-0.5, 0.5, -0.5),
				Vector3(0.5, 0.5, -0.5),
				Vector3(0.5, 0.5, 0.5),
				Vector3(-0.5, 0.5, 0.5)
			])
	return PackedVector3Array([
		Vector3(-0.5, -0.5, 0.5),
		Vector3(0.5, -0.5, 0.5),
		Vector3(0.5, -0.5, -0.5),
		Vector3(-0.5, -0.5, -0.5)
	])

func _face_uvs_for_block(face_name: String, block_id: String, world_pos: Vector3i) -> PackedVector2Array:
	var base_uvs: PackedVector2Array = _face_uvs(face_name)
	if face_name == "top" and block_defs.has(block_id):
		var block_data: Dictionary = block_defs[block_id]
		if bool(block_data.get("random_top_rotation", false)):
			var roll: float = _hash01(world_pos.x, world_pos.y, world_pos.z, 909)
			var rotation: int = int(floor(roll * 4.0))
			rotation = clamp(rotation, 0, 3)
			if rotation > 0:
				var rotated: PackedVector2Array = PackedVector2Array()
				rotated.resize(4)
				for i in range(4):
					rotated[i] = base_uvs[(i + rotation) % 4]
				return rotated
	return base_uvs

func _face_uvs(face_name: String) -> PackedVector2Array:
	if face_name in ["north", "south", "east", "west"]:
		return PackedVector2Array([
			Vector2(0, 1),
			Vector2(1, 1),
			Vector2(1, 0),
			Vector2(0, 0)
		])
	return PackedVector2Array([
		Vector2(0, 0),
		Vector2(1, 0),
		Vector2(1, 1),
		Vector2(0, 1)
	])

func _face_offset(face_name: String) -> Vector3i:
	match face_name:
		"north":
			return Vector3i(0, 0, -1)
		"south":
			return Vector3i(0, 0, 1)
		"east":
			return Vector3i(1, 0, 0)
		"west":
			return Vector3i(-1, 0, 0)
		"top":
			return Vector3i(0, 1, 0)
	return Vector3i(0, -1, 0)

func _is_block_face_visible(pos: Vector3i, offset: Vector3i, block_id: String) -> bool:
	if offset == Vector3i(0, -1, 0) and block_id == "bedrock":
		return false
	var neighbor_id: String = str(blocks.get(pos + offset, ""))
	if _is_foliage_block_id(block_id) and _is_foliage_block_id(neighbor_id):
		return false
	if _is_transparent_block_id(neighbor_id):
		return true
	return not _is_solid_block_at(pos + offset)

func _is_solid_block_at(pos: Vector3i) -> bool:
	var block_id: String = str(blocks.get(pos, ""))
	return _is_solid_block_id(block_id)

func _is_solid_block_id(block_id: String) -> bool:
	if block_id == "" or block_id == "air" or not block_defs.has(block_id):
		return false
	var block_data: Dictionary = block_defs[block_id]
	return bool(block_data.get("solid", true))

func _is_plant_block_id(block_id: String) -> bool:
	if block_id == "" or block_id == "air" or not block_defs.has(block_id):
		return false
	var block_data: Dictionary = block_defs[block_id]
	return bool(block_data.get("plant", false))

func _is_transparent_block_id(block_id: String) -> bool:
	if block_id == "" or block_id == "air" or not block_defs.has(block_id):
		return false
	var block_data: Dictionary = block_defs[block_id]
	return bool(block_data.get("transparent", false)) or float(block_data.get("alpha", 1.0)) < 0.99

func _is_foliage_block_id(block_id: String) -> bool:
	if block_id == "" or block_id == "air" or not block_defs.has(block_id):
		return false
	var block_data: Dictionary = block_defs[block_id]
	return bool(block_data.get("foliage", false))

func _vertex_ao_for_face(pos: Vector3i, face_name: String, vertex: Vector3) -> float:
	if not voxel_ao_enabled:
		return 1.0
	var dirs: Array = _ao_dirs_for_vertex(face_name, vertex)
	var side_a_offset: Vector3i = dirs[0]
	var side_b_offset: Vector3i = dirs[1]
	var side_a: bool = _is_ao_occluder_at(pos + side_a_offset)
	var side_b: bool = _is_ao_occluder_at(pos + side_b_offset)
	var corner: bool = _is_ao_occluder_at(pos + side_a_offset + side_b_offset)
	var occluders: int = (1 if side_a else 0) + (1 if side_b else 0) + (1 if corner else 0)
	var level: int = 0 if side_a and side_b else 3 - occluders
	var brightness: Array = [0.72, 0.82, 0.92, 1.0]
	return float(brightness[level])

func _is_ao_occluder_at(pos: Vector3i) -> bool:
	var block_id: String = str(blocks.get(pos, ""))
	return _is_solid_block_id(block_id) and not _is_transparent_block_id(block_id)

func _ao_dirs_for_vertex(face_name: String, vertex: Vector3) -> Array:
	var sx: int = 1 if vertex.x > 0.0 else -1
	var sy: int = 1 if vertex.y > 0.0 else -1
	var sz: int = 1 if vertex.z > 0.0 else -1
	match face_name:
		"north", "south":
			return [Vector3i(sx, 0, 0), Vector3i(0, sy, 0)]
		"east", "west":
			return [Vector3i(0, 0, sz), Vector3i(0, sy, 0)]
		"top", "bottom":
			return [Vector3i(sx, 0, 0), Vector3i(0, 0, sz)]
	return [Vector3i.ZERO, Vector3i.ZERO]

func _block_mesh(block_id: String) -> Mesh:
	if block_item_meshes.has(block_id):
		var cached_mesh: ArrayMesh = block_item_meshes[block_id]
		return cached_mesh
	if not block_defs.has(block_id):
		return null
	var mesh: ArrayMesh = ArrayMesh.new()
	var block_data: Dictionary = block_defs[block_id]
	var fallback_color: Color = block_data.get("color", Color.WHITE)
	if bool(block_data.get("plant", false)):
		var height: float = 0.8
		var p1_verts: PackedVector3Array = PackedVector3Array([
			Vector3(-0.5, -0.5, -0.5),
			Vector3(0.5, -0.5, 0.5),
			Vector3(0.5, -0.5 + height, 0.5),
			Vector3(-0.5, -0.5 + height, -0.5)
		])
		var p1_normal: Vector3 = Vector3(-0.7071, 0.0, 0.7071)
		
		var p2_verts: PackedVector3Array = PackedVector3Array([
			Vector3(-0.5, -0.5, 0.5),
			Vector3(0.5, -0.5, -0.5),
			Vector3(0.5, -0.5 + height, -0.5),
			Vector3(-0.5, -0.5 + height, 0.5)
		])
		var p2_normal: Vector3 = Vector3(0.7071, 0.0, 0.7071)

		var uvs: PackedVector2Array = PackedVector2Array([
			Vector2(0, 1),
			Vector2(1, 1),
			Vector2(1, 0),
			Vector2(0, 0)
		])
		var alpha: float = float(block_data.get("alpha", 1.0))
		
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		
		var vertices: PackedVector3Array = PackedVector3Array()
		var normals: PackedVector3Array = PackedVector3Array()
		var colors: PackedColorArray = PackedColorArray()
		var final_uvs: PackedVector2Array = PackedVector2Array()
		var indices: PackedInt32Array = PackedInt32Array()
		
		# Plane 1
		for i in range(4):
			vertices.append(p1_verts[i])
			normals.append(p1_normal)
			colors.append(Color(1.0, 1.0, 1.0, alpha))
			final_uvs.append(uvs[i])
		indices.append_array([0, 1, 2, 0, 2, 3])
		
		# Plane 2
		for i in range(4):
			vertices.append(p2_verts[i])
			normals.append(p2_normal)
			colors.append(Color(1.0, 1.0, 1.0, alpha))
			final_uvs.append(uvs[i])
		indices.append_array([4, 5, 6, 4, 6, 7])
		
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = final_uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var surface_index: int = mesh.get_surface_count() - 1
		var texture_path: String = block_data.get("texture", "")
		mesh.surface_set_material(
			surface_index,
			_material_for_texture(
				texture_path,
				fallback_color,
				alpha,
				bool(block_data.get("transparent", false)),
				false
			)
		)
		block_item_meshes[block_id] = mesh
		return mesh

	for face_name in ["north", "south", "east", "west", "top", "bottom"]:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		var vertices: PackedVector3Array = _face_vertices(face_name)
		var normal_offset: Vector3i = _face_offset(face_name)
		var normal: Vector3 = Vector3(normal_offset.x, normal_offset.y, normal_offset.z)
		var alpha: float = float(block_data.get("alpha", 1.0))
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([normal, normal, normal, normal])
		arrays[Mesh.ARRAY_TEX_UV] = _face_uvs(face_name)
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray([
			Color(1.0, 1.0, 1.0, alpha),
			Color(1.0, 1.0, 1.0, alpha),
			Color(1.0, 1.0, 1.0, alpha),
			Color(1.0, 1.0, 1.0, alpha)
		])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var surface_index: int = mesh.get_surface_count() - 1
		var texture_path: String = _block_texture_for_face(block_data, face_name)
		mesh.surface_set_material(
			surface_index,
			_material_for_texture(
				texture_path,
				fallback_color,
				alpha,
				bool(block_data.get("transparent", false)),
				false
			)
		)
	block_item_meshes[block_id] = mesh
	return mesh

func _queue_chunk_mesh_update(cx: int, cz: int) -> void:
	var c_key: Vector2i = Vector2i(cx, cz)
	if dirty_chunk_keys.has(c_key):
		return
	dirty_chunk_keys[c_key] = true
	dirty_chunk_queue.append(c_key)

func _process_dirty_chunk_meshes(max_chunks: int) -> void:
	var processed: int = 0
	while processed < max_chunks and not dirty_chunk_queue.is_empty():
		var c_key = dirty_chunk_queue.pop_front()
		if not (c_key is Vector2i):
			continue
		if not dirty_chunk_keys.has(c_key):
			continue
		_update_chunk_mesh(c_key.x, c_key.y)
		processed += 1

func _refresh_chunk_for_block(pos: Vector3i) -> void:
	var c_pos: Vector2i = _get_chunk_coords(pos)
	_queue_chunk_mesh_update(c_pos.x, c_pos.y)

func _refresh_chunks_for_block_and_neighbors(pos: Vector3i) -> void:
	var chunks_to_update: Dictionary = {}
	var c_pos: Vector2i = _get_chunk_coords(pos)
	chunks_to_update[c_pos] = true

	var local_x: int = pos.x - c_pos.x * CHUNK_SIZE
	var local_z: int = pos.z - c_pos.y * CHUNK_SIZE
	if local_x <= 0:
		chunks_to_update[Vector2i(c_pos.x - 1, c_pos.y)] = true
	if local_x >= CHUNK_SIZE - 1:
		chunks_to_update[Vector2i(c_pos.x + 1, c_pos.y)] = true
	if local_z <= 0:
		chunks_to_update[Vector2i(c_pos.x, c_pos.y - 1)] = true
	if local_z >= CHUNK_SIZE - 1:
		chunks_to_update[Vector2i(c_pos.x, c_pos.y + 1)] = true

	for chunk_coord in chunks_to_update.keys():
		_queue_chunk_mesh_update(chunk_coord.x, chunk_coord.y)

func _create_collision_node(pos: Vector3i, block_id: String) -> void:
	if not block_defs.has(block_id):
		return
	if not _is_solid_block_id(block_id) and not _is_plant_block_id(block_id):
		_remove_block_node(pos)
		return
	if block_nodes.has(pos):
		_remove_block_node(pos)

	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Collision_%s_%s_%s" % [pos.x, pos.y, pos.z]
	body.position = Vector3(pos.x, pos.y, pos.z)
	body.set_meta("block_pos", pos)
	body.set_meta("block_id", block_id)
	
	if _is_plant_block_id(block_id):
		body.collision_layer = 2
		body.collision_mask = 0
	else:
		body.collision_layer = 1
		body.collision_mask = 1

	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3.ONE
	collision.shape = shape
	body.add_child(collision)

	world_root.add_child(body)
	block_nodes[pos] = body

func _update_active_collisions(player_pos: Vector3) -> void:
	if world_root == null or not is_instance_valid(world_root):
		return
	var p_block: Vector3i = Vector3i(
		int(round(player_pos.x)),
		int(round(player_pos.y)),
		int(round(player_pos.z))
	)
	var desired_collisions: Dictionary = {}
	
	for x in range(p_block.x - COLLISION_RADIUS, p_block.x + COLLISION_RADIUS + 1):
		for z in range(p_block.z - COLLISION_RADIUS, p_block.z + COLLISION_RADIUS + 1):
			for y in range(p_block.y - COLLISION_RADIUS, p_block.y + COLLISION_RADIUS + 1):
				var pos: Vector3i = Vector3i(x, y, z)
				if blocks.has(pos):
					var block_id: String = blocks[pos]
					if _is_solid_block_id(block_id) or _is_plant_block_id(block_id):
						desired_collisions[pos] = block_id
						
	for pos in desired_collisions.keys():
		if not block_nodes.has(pos):
			_create_collision_node(pos, desired_collisions[pos])
			
	var existing_positions: Array = block_nodes.keys()
	for pos in existing_positions:
		if not desired_collisions.has(pos):
			_remove_block_node(pos)

func _refresh_block_and_neighbors(pos: Vector3i) -> void:
	_refresh_chunks_for_block_and_neighbors(pos)
	_refresh_collision_for_block(pos)

func _refresh_collision_for_block(pos: Vector3i) -> void:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return
	var p_block: Vector3i = Vector3i(
		int(round(player.global_position.x)),
		int(round(player.global_position.y)),
		int(round(player.global_position.z))
	)
	if abs(pos.x - p_block.x) > COLLISION_RADIUS or abs(pos.y - p_block.y) > COLLISION_RADIUS or abs(pos.z - p_block.z) > COLLISION_RADIUS:
		_remove_block_node(pos)
		return
	var block_id: String = str(blocks.get(pos, ""))
	if not _is_solid_block_id(block_id) and not _is_plant_block_id(block_id):
		_remove_block_node(pos)
	elif not block_nodes.has(pos):
		_create_collision_node(pos, block_id)

func _remove_block_node(pos: Vector3i) -> void:
	if block_nodes.has(pos):
		var node: Node = block_nodes[pos]
		if is_instance_valid(node):
			node.queue_free()
		block_nodes.erase(pos)

func _remove_block(pos: Vector3i) -> void:
	if blocks.has(pos):
		blocks.erase(pos)
	var c_pos: Vector2i = _get_chunk_coords(pos)
	if blocks_in_chunk.has(c_pos):
		blocks_in_chunk[c_pos].erase(pos)
		if blocks_in_chunk[c_pos].is_empty():
			blocks_in_chunk.erase(c_pos)
			
	if tracking_world_changes:
		var key: String = _pos_key(pos)
		changed_blocks.erase(key)
		removed_blocks[key] = true
	_remove_block_node(pos)
	
	# Rebuild chunks exactly once
	_refresh_chunks_for_block_and_neighbors(pos)

func _handle_block_breaking(delta: float) -> void:
	var hit: Dictionary = _get_target_block()
	if hit.is_empty():
		_cancel_block_breaking()
		return
	var pos: Vector3i = hit["pos"]
	var block_id: String = blocks.get(pos, "")
	if block_id == "":
		_cancel_block_breaking()
		return
		
	var block_data: Dictionary = block_defs.get(block_id, {})
	if not bool(block_data.get("breakable", true)):
		_cancel_block_breaking()
		return

	if pos != breaking_pos:
		breaking_pos = pos
		breaking_progress = 0.0
		_create_breaking_visuals(pos)
		
	var selected_item: String = _get_selected_hotbar_item()
	var break_speed: float = _calculate_break_speed(block_id, selected_item)
	var base_break_time: float = _get_base_break_time(block_id)
	
	breaking_progress += (delta * break_speed) / base_break_time
	_update_breaking_visuals(breaking_progress)
	if player != null:
		player.play_mine_swing(breaking_progress)
	
	if breaking_progress >= 1.0:
		_complete_block_breaking(pos, block_id, block_data)

func _cancel_block_breaking() -> void:
	if breaking_pos != Vector3i(-999, -999, -999):
		_clear_breaking_visuals()
		breaking_pos = Vector3i(-999, -999, -999)
		breaking_progress = 0.0

func _complete_block_breaking(pos: Vector3i, block_id: String, block_data: Dictionary) -> void:
	_clear_breaking_visuals()
	breaking_pos = Vector3i(-999, -999, -999)
	breaking_progress = 0.0
	
	var selected_item: String = _get_selected_hotbar_item()
	if selected_item == "manita_pickaxe":
		if mana < MANITA_PICKAXE_MANA_COST:
			_message("Mana insuficiente para usar a Picareta de Manita.")
			return
		mana -= MANITA_PICKAXE_MANA_COST
		manita_pickaxe_xp += 1
		if manita_pickaxe_xp >= manita_pickaxe_level * 10:
			manita_pickaxe_xp = 0
			manita_pickaxe_level += 1
			_message("Picareta de Manita subiu para nivel %s." % manita_pickaxe_level)

	var drop_id: String = block_data.get("drop", "")
	_remove_block(pos)
	if block_id == "chest":
		chest_inventories.erase(pos)
	if drop_id != "":
		# Spawn floating dropped item entity
		var spawn_pos: Vector3 = Vector3(pos) + Vector3(0.0, 0.25, 0.0)
		var spawn_vel: Vector3 = Vector3(randf_range(-1.0, 1.0), 2.5, randf_range(-1.0, 1.0))
		_spawn_dropped_item(drop_id, 1, spawn_pos, spawn_vel)
	if player != null:
		player.play_break_finish()
	if drop_id != "" or block_id == "chest" or selected_item == "manita_pickaxe":
		_update_all_ui()

func _create_breaking_visuals(pos: Vector3i) -> void:
	_clear_breaking_visuals()
	
	breaking_overlay = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(1.01, 1.01, 1.01)
	breaking_overlay.mesh = box_mesh
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	mat.roughness = 1.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	breaking_overlay.material_override = mat
	world_root.add_child(breaking_overlay)
	breaking_overlay.position = Vector3(pos)

func _update_breaking_visuals(progress: float) -> void:
	if breaking_overlay != null and is_instance_valid(breaking_overlay):
		var mat = breaking_overlay.material_override as StandardMaterial3D
		if mat != null:
			var stage: int = clamp(int(floor(progress * 10.0)), 0, 9)
			mat.albedo_texture = _breaking_crack_texture(stage)
			mat.albedo_color = Color(1.0, 1.0, 1.0, clamp(progress * 1.2, 0.25, 0.9))

func _breaking_crack_texture(stage: int) -> Texture2D:
	while breaking_crack_textures.size() <= stage:
		breaking_crack_textures.append(null)
	var cached: Texture2D = breaking_crack_textures[stage]
	if cached != null:
		return cached
	var image: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var crack_count: int = 3 + stage * 2
	for i in range(crack_count):
		var x: int = int(fmod(float(i * 5 + stage * 3), 16.0))
		var y: int = int(fmod(float(i * 7 + stage * 2), 16.0))
		var length: int = 3 + int(fmod(float(i + stage), 5.0))
		var dx: int = 1 if i % 2 == 0 else -1
		var dy: int = 1 if i % 3 != 0 else 0
		for j in range(length):
			var px: int = clamp(x + dx * j, 0, 15)
			var py: int = clamp(y + dy * j, 0, 15)
			image.set_pixel(px, py, Color(0.02, 0.02, 0.02, 0.86))
			if stage > 5 and px + 1 < 16:
				image.set_pixel(px + 1, py, Color(0.02, 0.02, 0.02, 0.58))
	cached = ImageTexture.create_from_image(image)
	breaking_crack_textures[stage] = cached
	return cached

func _clear_breaking_visuals() -> void:
	if breaking_overlay != null and is_instance_valid(breaking_overlay):
		breaking_overlay.queue_free()
		breaking_overlay = null

func _update_target_outline() -> void:
	if not game_started or _is_menu_open() or inventory_panel.visible or chest_panel.visible:
		_clear_target_outline()
		return
	var hit: Dictionary = _get_target_block()
	if hit.is_empty():
		_clear_target_outline()
		return
	var pos: Vector3i = hit["pos"]
	if not blocks.has(pos):
		_clear_target_outline()
		return
	if target_outline != null and is_instance_valid(target_outline) and pos == target_outline_pos:
		return
	_create_target_outline(pos)

func _create_target_outline(pos: Vector3i) -> void:
	_clear_target_outline()
	target_outline = MeshInstance3D.new()
	target_outline.mesh = _make_target_outline_mesh()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.BLACK
	target_outline.material_override = mat
	world_root.add_child(target_outline)
	target_outline.position = Vector3(pos)
	target_outline_pos = pos

func _clear_target_outline() -> void:
	if target_outline != null and is_instance_valid(target_outline):
		target_outline.queue_free()
	target_outline = null
	target_outline_pos = Vector3i(-999, -999, -999)

func _make_target_outline_mesh() -> ArrayMesh:
	var s: float = 0.515
	var vertices: PackedVector3Array = PackedVector3Array([
		Vector3(-s, -s, -s), Vector3(s, -s, -s),
		Vector3(s, -s, -s), Vector3(s, -s, s),
		Vector3(s, -s, s), Vector3(-s, -s, s),
		Vector3(-s, -s, s), Vector3(-s, -s, -s),
		Vector3(-s, s, -s), Vector3(s, s, -s),
		Vector3(s, s, -s), Vector3(s, s, s),
		Vector3(s, s, s), Vector3(-s, s, s),
		Vector3(-s, s, s), Vector3(-s, s, -s),
		Vector3(-s, -s, -s), Vector3(-s, s, -s),
		Vector3(s, -s, -s), Vector3(s, s, -s),
		Vector3(s, -s, s), Vector3(s, s, s),
		Vector3(-s, -s, s), Vector3(-s, s, s)
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh

func _get_base_break_time(block_id: String) -> float:
	if block_id in ["stone", "cobblestone", "iron_ore", "copper_ore", "coal_ore", "manita_ore"]:
		return 4.0
	elif block_id in ["wood", "planks", "crafting_table", "chest"]:
		return 2.0
	elif block_id in ["dirt", "grass"]:
		return 1.0
	elif block_id == "leaves":
		return 0.3
	elif _is_plant_block_id(block_id):
		return 0.1
	return 1.0

func _calculate_break_speed(block_id: String, selected_item: String) -> float:
	var block_type: String = ""
	if block_id in ["stone", "cobblestone", "iron_ore", "copper_ore", "coal_ore", "manita_ore"]:
		block_type = "stone"
	elif block_id in ["wood", "planks", "crafting_table", "chest"]:
		block_type = "wood"
	elif block_id in ["dirt", "grass"]:
		block_type = "dirt"
	elif block_id == "leaves":
		block_type = "leaves"

	var tool_type: String = ""
	var tool_tier: int = 1
	if selected_item != "":
		var item_data: Dictionary = item_defs.get(selected_item, {})
		tool_type = item_data.get("tool", "")
		if "stone_" in selected_item:
			tool_tier = 2
		elif "iron_" in selected_item:
			tool_tier = 3
		elif "manita_" in selected_item:
			tool_tier = 4
		else:
			tool_tier = 1

	var multiplier: float = 1.0
	if block_type == "stone" and tool_type == "pickaxe":
		multiplier = _tool_multiplier(tool_tier, selected_item)
	elif block_type == "wood" and tool_type == "axe":
		multiplier = _tool_multiplier(tool_tier, selected_item)
	elif block_type == "dirt" and tool_type == "shovel":
		multiplier = _tool_multiplier(tool_tier, selected_item)
	elif block_type == "leaves" and tool_type == "hoe":
		multiplier = _tool_multiplier(tool_tier, selected_item)
	
	return multiplier

func _tool_multiplier(tier: int, item_id: String) -> float:
	var mult: float = 1.0
	match tier:
		1: mult = 3.0 # Wood
		2: mult = 5.0 # Stone
		3: mult = 8.0 # Iron
		4: mult = 12.0 # Manita
	if item_id == "manita_pickaxe":
		mult += float(manita_pickaxe_level) * 0.5
	return mult

func _spawn_dropped_item(item_id: String, count: int, pos: Vector3, vel: Vector3) -> void:
	var item_node: DroppedItem = DroppedItem.new()
	world_root.add_child(item_node)
	item_node.configure(self, item_id, count, pos, vel)
	dropped_items.append(item_node)

func _drop_selected_item() -> void:
	if not game_started or _is_menu_open() or inventory_panel.visible or chest_panel.visible:
		return
	var item_id: String = _get_selected_hotbar_item()
	if item_id == "":
		return
	
	# Calculate throw direction and spawn parameters
	var forward: Vector3 = player.get_aim_direction()
	var spawn_pos: Vector3 = player.global_position + Vector3(0, 1.4, 0) + forward * 0.5
	var spawn_vel: Vector3 = forward * 4.5 + Vector3(0, 1.5, 0)
	
	# Spawn dropped item entity
	_spawn_dropped_item(item_id, 1, spawn_pos, spawn_vel)
	if player != null:
		player.play_drop_swing()
	
	# Remove 1 from slot
	_remove_from_slot(inventory_slots, selected_hotbar_index, 1)
	_update_all_ui()

func _use_or_place_target() -> bool:
	var hit: Dictionary = _get_target_block()
	if hit.is_empty():
		return false

	var pos: Vector3i = hit["pos"]
	var block_id: String = blocks.get(pos, "")
	var block_data: Dictionary = block_defs.get(block_id, {})
	var interact: String = block_data.get("interact", "")
	if interact == "chest":
		_open_chest(pos)
		if player != null:
			player.play_place_swing()
		return true
	if interact == "craft":
		_open_table_craft()
		if player != null:
			player.play_place_swing()
		return true

	var selected_item: String = _get_selected_hotbar_item()
	if selected_item == "":
		return false
	var item_data: Dictionary = item_defs.get(selected_item, {})
	var place_block: String = item_data.get("place_block", "")

	var normal: Vector3 = hit["normal"]
	var offset: Vector3i = Vector3i(int(round(normal.x)), int(round(normal.y)), int(round(normal.z)))
	var target_pos: Vector3i = pos + offset
	if place_block == "":
		_message("Item selecionado nao pode ser colocado.")
		return false
	if blocks.has(target_pos):
		return false
	if not _is_inside_current_biome(target_pos):
		_message("Este MVP esta limitado ao Bioma 1 de 100x100.")
		return false
	if _would_block_player(target_pos):
		_message("Nao da para colocar bloco dentro do jogador.")
		return false
	if not _remove_from_slot(inventory_slots, selected_hotbar_index, 1):
		_message("Sem %s no slot selecionado." % _item_name(selected_item))
		return false

	_set_block(target_pos, place_block)
	if place_block == "chest":
		chest_inventories[target_pos] = _make_slots(CHEST_SLOT_COUNT)
	if player != null:
		player.play_place_swing()
	_update_all_ui()
	return true

func _get_target_block() -> Dictionary:
	if player == null:
		return {}
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		player.get_interaction_ray_start(),
		player.get_interaction_ray_end()
	)
	query.exclude = [player]
	query.collision_mask = 1 | 2
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return {}
	var collider: Object = result.get("collider", null)
	if collider == null or not collider.has_meta("block_pos"):
		return {}
	return {
		"pos": collider.get_meta("block_pos"),
		"normal": result.get("normal", Vector3.ZERO)
	}

func _is_inside_current_biome(pos: Vector3i) -> bool:
	return pos.x >= BIOME_MIN_X and pos.x <= BIOME_MAX_X and pos.z >= BIOME_MIN_Z and pos.z <= BIOME_MAX_Z

func _would_block_player(pos: Vector3i) -> bool:
	var block_top: float = float(pos.y) + 0.5
	var player_feet: float = player.global_position.y
	if block_top < player_feet - 0.08:
		return false

	var player_min_y: float = player.global_position.y
	var player_max_y: float = player.global_position.y + 1.8
	var block_min_y: float = float(pos.y) - 0.5
	var block_max_y: float = float(pos.y) + 0.5
	var vertical_overlap: bool = block_min_y < player_max_y and block_max_y > player_min_y
	if not vertical_overlap:
		return false

	var dx: float = abs(float(pos.x) - player.global_position.x)
	var dz: float = abs(float(pos.z) - player.global_position.z)
	return dx < 0.85 and dz < 0.85

func _open_inventory_craft() -> void:
	_open_craft_panel(2, "Craft pessoal 2x2")

func _open_table_craft() -> void:
	_open_craft_panel(3, "Bancada 3x3")

func _open_craft_panel(size: int, title: String) -> void:
	_return_craft_slots_to_inventory()
	craft_size = size
	craft_context = title
	craft_slots = _make_slots(size * size)
	inventory_panel.visible = true
	chest_panel.visible = false
	craft_title_label.text = "%s - arraste itens para a grade" % title
	craft_grid.columns = size
	craft_result_label.text = ""
	_update_inventory_panel()
	_set_ui_mode(true)

func _open_chest(pos: Vector3i) -> void:
	_return_craft_slots_to_inventory()
	current_chest_pos = pos
	has_current_chest = true
	if not chest_inventories.has(pos):
		chest_inventories[pos] = _make_slots(CHEST_SLOT_COUNT)
	chest_panel.visible = true
	inventory_panel.visible = false
	_update_chest_panel()
	_set_ui_mode(true)

func _close_all_panels() -> void:
	_return_craft_slots_to_inventory()
	inventory_panel.visible = false
	chest_panel.visible = false
	has_current_chest = false
	_set_ui_mode(false)
	_update_all_ui()

func _set_ui_mode(open: bool) -> void:
	if open:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		player.set_controls_enabled(false)
	else:
		_return_cursor_stack_to_inventory()
		_cancel_slot_drags()
		if game_started and not _is_menu_open():
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			player.set_controls_enabled(true)
	_update_player_visual_visibility()

func slot_mouse_button(slot_type: String, slot_index: int, button_index: int, pressed: bool) -> void:
	if pressed and button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SHIFT):
		_handle_shift_click(slot_type, slot_index)
		return
	if slot_type == "craft_output":
		if pressed and (button_index == MOUSE_BUTTON_LEFT or button_index == MOUSE_BUTTON_RIGHT):
			_take_craft_output()
		return
	if button_index == MOUSE_BUTTON_LEFT:
		if pressed:
			_handle_left_slot_press(slot_type, slot_index)
		elif left_drag_active:
			_finish_left_drag()
	elif button_index == MOUSE_BUTTON_RIGHT:
		if pressed:
			_handle_right_slot_press(slot_type, slot_index)
		else:
			right_drag_active = false
			right_drag_keys.clear()

func slot_mouse_entered(slot_type: String, slot_index: int) -> void:
	_show_slot_tooltip(slot_type, slot_index)
	if slot_type == "craft_output":
		return
	if left_drag_active and _slot_count(cursor_stack) > 0:
		_add_left_drag_target(slot_type, slot_index)
	elif right_drag_active and _slot_count(cursor_stack) > 0:
		_place_one_from_cursor(slot_type, slot_index)
		_update_all_ui()

func slot_mouse_exited(slot_type: String, slot_index: int) -> void:
	if hovered_slot_type == slot_type and hovered_slot_index == slot_index:
		_hide_slot_tooltip()

func _handle_left_slot_press(slot_type: String, slot_index: int) -> void:
	if not _is_valid_slot(slot_type, slot_index):
		return
	if _slot_item(cursor_stack) == "":
		var slot: Dictionary = _get_slot(slot_type, slot_index)
		if _slot_item(slot) == "":
			return
		cursor_stack = slot.duplicate()
		_set_slot(slot_type, slot_index, _empty_slot())
		_update_all_ui()
	else:
		left_drag_active = true
		left_drag_targets.clear()
		left_drag_keys.clear()
		_add_left_drag_target(slot_type, slot_index)
	_update_cursor_stack_label()

func _handle_right_slot_press(slot_type: String, slot_index: int) -> void:
	if not _is_valid_slot(slot_type, slot_index):
		return
	if _slot_item(cursor_stack) == "":
		var slot: Dictionary = _get_slot(slot_type, slot_index)
		if _slot_item(slot) == "":
			return
		var take_count: int = int(ceil(float(_slot_count(slot)) / 2.0))
		cursor_stack = {"item": _slot_item(slot), "count": take_count}
		slot["count"] = _slot_count(slot) - take_count
		if _slot_count(slot) <= 0:
			slot = _empty_slot()
		_set_slot(slot_type, slot_index, slot)
		_update_all_ui()
	else:
		right_drag_active = true
		right_drag_keys.clear()
		_place_one_from_cursor(slot_type, slot_index)
		_update_all_ui()
	_update_cursor_stack_label()

func _add_left_drag_target(slot_type: String, slot_index: int) -> void:
	if not _can_accept_cursor(slot_type, slot_index):
		return
	var key: String = _slot_key(slot_type, slot_index)
	if left_drag_keys.has(key):
		return
	left_drag_keys[key] = true
	left_drag_targets.append({"type": slot_type, "index": slot_index})

func _finish_left_drag() -> void:
	if not left_drag_active:
		return
	left_drag_active = false

	if _slot_count(cursor_stack) <= 0:
		_clear_left_drag()
		_update_all_ui()
		return

	if left_drag_targets.size() <= 1:
		if left_drag_targets.size() == 1:
			var target: Dictionary = left_drag_targets[0]
			_place_or_swap_cursor_stack(str(target["type"]), int(target["index"]))
	else:
		_spread_cursor_stack_evenly()

	_clear_left_drag()
	_update_all_ui()
	_update_cursor_stack_label()

func _clear_left_drag() -> void:
	left_drag_targets.clear()
	left_drag_keys.clear()

func _cancel_slot_drags() -> void:
	left_drag_active = false
	right_drag_active = false
	_clear_left_drag()
	right_drag_keys.clear()

func _place_or_swap_cursor_stack(slot_type: String, slot_index: int) -> void:
	if not _is_valid_slot(slot_type, slot_index) or _slot_item(cursor_stack) == "":
		return
	var slot: Dictionary = _get_slot(slot_type, slot_index)
	if _slot_item(slot) == "":
		_set_slot(slot_type, slot_index, cursor_stack.duplicate())
		cursor_stack = _empty_slot()
	elif _slot_item(slot) == _slot_item(cursor_stack):
		slot["count"] = _slot_count(slot) + _slot_count(cursor_stack)
		_set_slot(slot_type, slot_index, slot)
		cursor_stack = _empty_slot()
	else:
		var old_slot: Dictionary = slot.duplicate()
		_set_slot(slot_type, slot_index, cursor_stack.duplicate())
		cursor_stack = old_slot

func _place_one_from_cursor(slot_type: String, slot_index: int) -> void:
	if _slot_count(cursor_stack) <= 0 or not _can_accept_cursor(slot_type, slot_index):
		return
	var key: String = _slot_key(slot_type, slot_index)
	if right_drag_keys.has(key):
		return
	right_drag_keys[key] = true

	var slot: Dictionary = _get_slot(slot_type, slot_index)
	if _slot_item(slot) == "":
		slot = {"item": _slot_item(cursor_stack), "count": 1}
	else:
		slot["count"] = _slot_count(slot) + 1
	_set_slot(slot_type, slot_index, slot)
	cursor_stack["count"] = _slot_count(cursor_stack) - 1
	if _slot_count(cursor_stack) <= 0:
		cursor_stack = _empty_slot()
		right_drag_active = false
		right_drag_keys.clear()

func _spread_cursor_stack_evenly() -> void:
	var valid_targets: Array = []
	for target in left_drag_targets:
		var typed_target: Dictionary = target
		var slot_type: String = str(typed_target["type"])
		var slot_index: int = int(typed_target["index"])
		if _can_accept_cursor(slot_type, slot_index):
			valid_targets.append(typed_target)

	var target_count: int = valid_targets.size()
	if target_count <= 0:
		return

	var total: int = _slot_count(cursor_stack)
	var base_amount: int = max(1, int(floor(float(total) / float(target_count))))
	var remaining: int = total

	for i in range(valid_targets.size()):
		if remaining <= 0:
			break
		var target: Dictionary = valid_targets[i]
		var amount: int = min(base_amount, remaining)
		if i < total % target_count:
			amount = min(amount + 1, remaining)
		_add_amount_to_slot(str(target["type"]), int(target["index"]), _slot_item(cursor_stack), amount)
		remaining -= amount

	cursor_stack["count"] = remaining
	if remaining <= 0:
		cursor_stack = _empty_slot()

func _add_amount_to_slot(slot_type: String, slot_index: int, item_id: String, amount: int) -> void:
	if amount <= 0 or item_id == "" or not _is_valid_slot(slot_type, slot_index):
		return
	var slot: Dictionary = _get_slot(slot_type, slot_index)
	if _slot_item(slot) == "":
		slot = {"item": item_id, "count": amount}
	elif _slot_item(slot) == item_id:
		slot["count"] = _slot_count(slot) + amount
	else:
		return
	_set_slot(slot_type, slot_index, slot)

func _can_accept_cursor(slot_type: String, slot_index: int) -> bool:
	if slot_type == "craft_output":
		return false
	if _slot_item(cursor_stack) == "" or not _is_valid_slot(slot_type, slot_index):
		return false
	var slot: Dictionary = _get_slot(slot_type, slot_index)
	return _slot_item(slot) == "" or _slot_item(slot) == _slot_item(cursor_stack)

func _slot_key(slot_type: String, slot_index: int) -> String:
	return "%s:%s" % [slot_type, slot_index]

func _is_valid_slot(slot_type: String, slot_index: int) -> bool:
	if slot_type == "craft_output":
		return slot_index == 0 and _slot_item(_current_craft_output_slot()) != ""
	var slots: Array = _get_slots_for_type(slot_type)
	return slot_index >= 0 and slot_index < slots.size()

func _get_slot(slot_type: String, slot_index: int) -> Dictionary:
	if slot_type == "craft_output":
		return _current_craft_output_slot()
	var slots: Array = _get_slots_for_type(slot_type)
	if slot_index < 0 or slot_index >= slots.size():
		return _empty_slot()
	var slot: Dictionary = slots[slot_index]
	return slot

func _set_slot(slot_type: String, slot_index: int, slot: Dictionary) -> void:
	if slot_type == "craft_output":
		return
	var slots: Array = _get_slots_for_type(slot_type)
	if slot_index < 0 or slot_index >= slots.size():
		return
	slots[slot_index] = slot
	_store_slots_for_type(slot_type, slots)

func _get_slots_for_type(slot_type: String) -> Array:
	match slot_type:
		"inventory":
			return inventory_slots
		"craft":
			return craft_slots
		"chest":
			if has_current_chest and chest_inventories.has(current_chest_pos):
				var chest_slots: Array = chest_inventories[current_chest_pos]
				return chest_slots
			return []
		_:
			return []

func _store_slots_for_type(slot_type: String, slots: Array) -> void:
	match slot_type:
		"inventory":
			inventory_slots = slots
		"craft":
			craft_slots = slots
		"chest":
			if has_current_chest:
				chest_inventories[current_chest_pos] = slots

func _try_craft() -> void:
	_take_craft_output()

func _current_craft_output_slot() -> Dictionary:
	var recipe: Dictionary = _current_craft_recipe()
	if recipe.is_empty():
		return _empty_slot()
	var output_id: String = str(recipe.get("output", ""))
	var output_count: int = int(recipe.get("count", 1))
	if output_id == "" or output_count <= 0:
		return _empty_slot()
	return {"item": output_id, "count": output_count}

func _current_craft_recipe() -> Dictionary:
	var normalized: Array = _normalize_craft_grid(craft_slots, craft_size)
	if normalized.is_empty():
		return {}
	for recipe in recipes:
		var typed_recipe: Dictionary = recipe
		var shape: Array = typed_recipe.get("shape", [])
		if _shape_matches(normalized, shape):
			return typed_recipe
	return {}

func _take_craft_output() -> void:
	var output_slot: Dictionary = _current_craft_output_slot()
	var output_id: String = _slot_item(output_slot)
	var output_count: int = _slot_count(output_slot)
	if output_id == "" or output_count <= 0:
		return
	if _slot_item(cursor_stack) != "" and _slot_item(cursor_stack) != output_id:
		_message("O mouse ja esta carregando outro item.")
		return
	if _slot_item(cursor_stack) == "":
		cursor_stack = output_slot.duplicate()
	else:
		cursor_stack["count"] = _slot_count(cursor_stack) + output_count
	_consume_craft_ingredients()
	craft_result_label.text = "Criado: %s x%s" % [_item_name(output_id), output_count]
	_message(craft_result_label.text)
	_update_all_ui()
	_update_cursor_stack_label()

func _handle_shift_click(slot_type: String, slot_index: int) -> void:
	if slot_type == "craft_output":
		_take_craft_output_to_inventory()
		return
		
	if slot_type == "chest":
		_quick_transfer_item("chest", slot_index, "inventory")
	elif slot_type == "inventory":
		if chest_panel.visible:
			_quick_transfer_item("inventory", slot_index, "chest")
		else:
			if slot_index < 9:
				_quick_transfer_between_indices(slot_index, 9, 27)
			else:
				_quick_transfer_between_indices(slot_index, 0, 9)
	elif slot_type == "craft":
		_quick_transfer_item("craft", slot_index, "inventory")

func _quick_transfer_between_indices(source_index: int, target_start: int, target_end: int) -> void:
	var source_slot: Dictionary = inventory_slots[source_index]
	var item_id: String = _slot_item(source_slot)
	var count: int = _slot_count(source_slot)
	if item_id == "":
		return
		
	var remaining: int = count
	
	for i in range(target_start, target_end):
		var t_slot: Dictionary = inventory_slots[i]
		if _slot_item(t_slot) == item_id:
			var current_count: int = _slot_count(t_slot)
			if current_count < 64:
				var add_count: int = min(remaining, 64 - current_count)
				t_slot["count"] = current_count + add_count
				remaining -= add_count
				inventory_slots[i] = t_slot
				if remaining <= 0:
					break
					
	if remaining > 0:
		for i in range(target_start, target_end):
			var t_slot: Dictionary = inventory_slots[i]
			if _slot_item(t_slot) == "":
				var place_count: int = min(remaining, 64)
				t_slot["item"] = item_id
				t_slot["count"] = place_count
				remaining -= place_count
				inventory_slots[i] = t_slot
				if remaining <= 0:
					break
					
	if remaining <= 0:
		inventory_slots[source_index] = _empty_slot()
	else:
		source_slot["count"] = remaining
		inventory_slots[source_index] = source_slot
		
	_update_all_ui()

func _quick_transfer_item(source_type: String, source_index: int, target_type: String) -> void:
	var source_slot: Dictionary = _get_slot(source_type, source_index)
	var item_id: String = _slot_item(source_slot)
	var count: int = _slot_count(source_slot)
	if item_id == "":
		return
		
	var target_slots: Array = _get_slots_for_type(target_type)
	if target_slots.is_empty():
		return
		
	var remaining: int = count
	
	for i in range(target_slots.size()):
		var t_slot: Dictionary = target_slots[i]
		if _slot_item(t_slot) == item_id:
			var current_count: int = _slot_count(t_slot)
			if current_count < 64:
				var add_count: int = min(remaining, 64 - current_count)
				t_slot["count"] = current_count + add_count
				remaining -= add_count
				_set_slot(target_type, i, t_slot)
				if remaining <= 0:
					break
					
	if remaining > 0:
		for i in range(target_slots.size()):
			var t_slot: Dictionary = target_slots[i]
			if _slot_item(t_slot) == "":
				var place_count: int = min(remaining, 64)
				t_slot["item"] = item_id
				t_slot["count"] = place_count
				remaining -= place_count
				_set_slot(target_type, i, t_slot)
				if remaining <= 0:
					break
					
	if remaining <= 0:
		_set_slot(source_type, source_index, _empty_slot())
	else:
		source_slot["count"] = remaining
		_set_slot(source_type, source_index, source_slot)
		
	_update_all_ui()

func _take_craft_output_to_inventory() -> void:
	var output_slot: Dictionary = _current_craft_output_slot()
	var output_id: String = _slot_item(output_slot)
	var output_count: int = _slot_count(output_slot)
	if output_id == "" or output_count <= 0:
		return
		
	var target_slots: Array = inventory_slots
	var remaining: int = output_count
	
	for i in range(target_slots.size()):
		var t_slot: Dictionary = target_slots[i]
		if _slot_item(t_slot) == output_id:
			var current_count: int = _slot_count(t_slot)
			if current_count < 64:
				var add_count: int = min(remaining, 64 - current_count)
				t_slot["count"] = current_count + add_count
				remaining -= add_count
				inventory_slots[i] = t_slot
				if remaining <= 0:
					break
					
	if remaining > 0:
		for i in range(target_slots.size()):
			var t_slot: Dictionary = target_slots[i]
			if _slot_item(t_slot) == "":
				var place_count: int = min(remaining, 64)
				t_slot["item"] = output_id
				t_slot["count"] = place_count
				remaining -= place_count
				inventory_slots[i] = t_slot
				if remaining <= 0:
					break
					
	if remaining < output_count:
		_consume_craft_ingredients()
		craft_result_label.text = "Criado: %s x%s" % [_item_name(output_id), output_count - remaining]
		_message(craft_result_label.text)
		_update_all_ui()

func _consume_craft_ingredients() -> void:
	for i in range(craft_slots.size()):
		var slot: Dictionary = craft_slots[i]
		if _slot_item(slot) != "":
			_remove_from_slot(craft_slots, i, 1)

func _return_craft_slots_to_inventory() -> void:
	for i in range(craft_slots.size()):
		var slot: Dictionary = craft_slots[i]
		if _slot_item(slot) != "":
			_add_item(_slot_item(slot), _slot_count(slot))
	craft_slots = _make_slots(craft_size * craft_size)

func _return_cursor_stack_to_inventory() -> void:
	if _slot_item(cursor_stack) == "":
		return
	_add_item(_slot_item(cursor_stack), _slot_count(cursor_stack))
	cursor_stack = _empty_slot()
	_update_cursor_stack_label()

func _normalize_craft_grid(slots: Array, size: int) -> Array:
	var min_x: int = size
	var min_y: int = size
	var max_x: int = -1
	var max_y: int = -1
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		if _slot_item(slot) != "":
			var x: int = i % size
			var y: int = int(float(i) / size)
			min_x = min(min_x, x)
			min_y = min(min_y, y)
			max_x = max(max_x, x)
			max_y = max(max_y, y)
	if max_x == -1:
		return []

	var shape: Array = []
	for y in range(min_y, max_y + 1):
		var row: Array = []
		for x in range(min_x, max_x + 1):
			var slot: Dictionary = slots[y * size + x]
			row.append(_slot_item(slot))
		shape.append(row)
	return shape

func _shape_matches(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for y in range(a.size()):
		var row_a: Array = a[y]
		var row_b: Array = b[y]
		if row_a.size() != row_b.size():
			return false
		for x in range(row_a.size()):
			if row_a[x] != row_b[x]:
				return false
	return true

func _make_slots(count: int) -> Array:
	var result: Array = []
	for _i in range(count):
		result.append(_empty_slot())
	return result

func _empty_slot() -> Dictionary:
	return {"item": "", "count": 0}

func _add_item(item_id: String, count: int) -> bool:
	return _add_item_to_slots(inventory_slots, item_id, count)

func _add_item_to_slots(slots: Array, item_id: String, count: int) -> bool:
	if item_id == "" or count <= 0:
		return true
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		if _slot_item(slot) == item_id:
			slot["count"] = _slot_count(slot) + count
			slots[i] = slot
			return true
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		if _slot_item(slot) == "":
			slots[i] = {"item": item_id, "count": count}
			return true
	_message("Inventario cheio: %s ficou no chao por enquanto." % _item_name(item_id))
	return false

func _remove_from_slot(slots: Array, index: int, count: int) -> bool:
	if index < 0 or index >= slots.size():
		return false
	var slot: Dictionary = slots[index]
	if _slot_count(slot) < count:
		return false
	slot["count"] = _slot_count(slot) - count
	if _slot_count(slot) <= 0:
		slots[index] = _empty_slot()
	else:
		slots[index] = slot
	return true

func _slot_item(slot: Dictionary) -> String:
	return str(slot.get("item", ""))

func _slot_count(slot: Dictionary) -> int:
	return int(slot.get("count", 0))

func _item_total(item_id: String) -> int:
	var total: int = 0
	for slot in inventory_slots:
		var typed_slot: Dictionary = slot
		if _slot_item(typed_slot) == item_id:
			total += _slot_count(typed_slot)
	return total

func _item_name(item_id: String) -> String:
	if item_id == "":
		return ""
	var data: Dictionary = item_defs.get(item_id, {"name": item_id})
	return data.get("name", item_id)

func _item_description(item_id: String) -> String:
	if item_id == "":
		return ""
	var data: Dictionary = item_defs.get(item_id, {})
	if str(data.get("place_block", "")) != "":
		return "Bloco: pode ser colocado no mundo."
	if str(data.get("tool", "")) != "":
		return "Ferramenta: use para interagir com blocos ou recursos."
	return "Material: usado em receitas e progresso."

func _get_selected_hotbar_item() -> String:
	if selected_hotbar_index < 0 or selected_hotbar_index >= HOTBAR_SLOT_COUNT:
		return ""
	var slot: Dictionary = inventory_slots[selected_hotbar_index]
	return _slot_item(slot)

func _get_selected_hotbar_count() -> int:
	if selected_hotbar_index < 0 or selected_hotbar_index >= HOTBAR_SLOT_COUNT:
		return 0
	var slot: Dictionary = inventory_slots[selected_hotbar_index]
	return _slot_count(slot)

func _save_game_state() -> bool:
	if not game_started:
		return false
	_return_cursor_stack_to_inventory()
	_return_craft_slots_to_inventory()
	_cancel_slot_drags()

	var save_data: Dictionary = {
		"version": 1,
		"world_seed": WORLD_SEED,
		"player_position": _vector3_to_array(player.global_position),
		"player_rotation_y": player.get_camera_yaw(),
		"camera_pitch": player.get_camera_pitch(),
		"inventory_slots": inventory_slots,
		"selected_hotbar_index": selected_hotbar_index,
		"mana": mana,
		"manita_pickaxe_xp": manita_pickaxe_xp,
		"manita_pickaxe_level": manita_pickaxe_level,
		"changed_blocks": changed_blocks,
		"removed_blocks": _removed_block_keys(),
		"chest_inventories": _serialize_chest_inventories(),
		"time_of_day": time_of_day,
		"day_count": day_count
	}

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(save_data, "\t"))
	return true

func _load_game_state() -> bool:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var text: String = file.get_as_text()
	var json: JSON = JSON.new()
	var parse_error: int = json.parse(text)
	if parse_error != OK:
		return false

	var raw_data: Variant = json.data
	if typeof(raw_data) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = raw_data as Dictionary

	tracking_world_changes = false
	changed_blocks.clear()
	removed_blocks.clear()

	inventory_slots = _slots_from_data(data.get("inventory_slots", []), INVENTORY_SLOT_COUNT)
	craft_slots = _make_slots(4)
	cursor_stack = _empty_slot()
	selected_hotbar_index = clamp(int(data.get("selected_hotbar_index", 0)), 0, HOTBAR_SLOT_COUNT - 1)
	mana = clamp(float(data.get("mana", MANA_MAX)), 0.0, MANA_MAX)
	manita_pickaxe_xp = max(0, int(data.get("manita_pickaxe_xp", 0)))
	manita_pickaxe_level = max(1, int(data.get("manita_pickaxe_level", 1)))
	time_of_day = clamp(float(data.get("time_of_day", 8.0)), 0.0, 24.0)
	day_count = max(1, int(data.get("day_count", 1)))

	var raw_removed: Variant = data.get("removed_blocks", [])
	if typeof(raw_removed) == TYPE_ARRAY:
		var removed_list: Array = raw_removed as Array
		for raw_key in removed_list:
			var key: String = str(raw_key)
			removed_blocks[key] = true
			_remove_block(_pos_from_key(key))

	var raw_changed: Variant = data.get("changed_blocks", {})
	if typeof(raw_changed) == TYPE_DICTIONARY:
		var changed_data: Dictionary = raw_changed as Dictionary
		for raw_key in changed_data.keys():
			var key: String = str(raw_key)
			var block_id: String = str(changed_data[raw_key])
			if block_defs.has(block_id):
				changed_blocks[key] = block_id
				removed_blocks.erase(key)
				_set_block(_pos_from_key(key), block_id)

	chest_inventories.clear()
	var raw_chests: Variant = data.get("chest_inventories", {})
	if typeof(raw_chests) == TYPE_DICTIONARY:
		var chest_data: Dictionary = raw_chests as Dictionary
		for raw_key in chest_data.keys():
			var key: String = str(raw_key)
			var pos: Vector3i = _pos_from_key(key)
			if blocks.get(pos, "") == "chest":
				chest_inventories[pos] = _slots_from_data(chest_data[raw_key], CHEST_SLOT_COUNT)

	for raw_key in changed_blocks.keys():
		var changed_key: String = str(raw_key)
		if str(changed_blocks[raw_key]) == "chest":
			var chest_pos: Vector3i = _pos_from_key(changed_key)
			if not chest_inventories.has(chest_pos):
				chest_inventories[chest_pos] = _make_slots(CHEST_SLOT_COUNT)

	loaded_game_data = data

	tracking_world_changes = true
	_update_all_ui()
	return true

func _load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		fullscreen_enabled = bool(config.get_value("video", "fullscreen", false))
		shadows_enabled = bool(config.get_value("video", "shadows", true))
		ssao_enabled = bool(config.get_value("video", "ssao", true))
		voxel_ao_enabled = bool(config.get_value("video", "voxel_ao", true))
		player_skin_path = str(config.get_value("player", "skin_path", ""))
		saved_camera_mode = clamp(int(config.get_value("player", "camera_mode", 0)), 0, 2)
		if player_skin_path != "" and not SkinLoader.is_valid_skin_path(player_skin_path):
			player_skin_path = ""

func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("video", "fullscreen", fullscreen_enabled)
	config.set_value("video", "shadows", shadows_enabled)
	config.set_value("video", "ssao", ssao_enabled)
	config.set_value("video", "voxel_ao", voxel_ao_enabled)
	config.set_value("player", "skin_path", player_skin_path)
	config.set_value("player", "camera_mode", saved_camera_mode)
	config.save(SETTINGS_PATH)

func _serialize_chest_inventories() -> Dictionary:
	var result: Dictionary = {}
	for raw_pos in chest_inventories.keys():
		var pos: Vector3i = raw_pos
		if blocks.get(pos, "") == "chest":
			result[_pos_key(pos)] = chest_inventories[pos]
	return result

func _removed_block_keys() -> Array:
	var result: Array = []
	for raw_key in removed_blocks.keys():
		result.append(str(raw_key))
	return result

func _slots_from_data(raw_value: Variant, slot_count: int) -> Array:
	var slots: Array = _make_slots(slot_count)
	if typeof(raw_value) != TYPE_ARRAY:
		return slots
	var source: Array = raw_value as Array
	for i in range(min(slot_count, source.size())):
		var raw_slot: Variant = source[i]
		if typeof(raw_slot) != TYPE_DICTIONARY:
			continue
		var slot_data: Dictionary = raw_slot as Dictionary
		var item_id: String = str(slot_data.get("item", ""))
		var item_count: int = int(slot_data.get("count", 0))
		if item_defs.has(item_id) and item_count > 0:
			slots[i] = {"item": item_id, "count": item_count}
	return slots

func _pos_key(pos: Vector3i) -> String:
	return "%s,%s,%s" % [pos.x, pos.y, pos.z]

func _pos_from_key(key: String) -> Vector3i:
	var parts: PackedStringArray = key.split(",")
	if parts.size() != 3:
		return Vector3i.ZERO
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))

func _vector3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _vector3_from_data(raw_value: Variant, fallback: Vector3) -> Vector3:
	if typeof(raw_value) != TYPE_ARRAY:
		return fallback
	var values: Array = raw_value as Array
	if values.size() < 3:
		return fallback
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func _update_all_ui() -> void:
	_update_hotbar()
	_update_status()
	if inventory_panel.visible:
		_update_inventory_panel()
	if chest_panel.visible:
		_update_chest_panel()
	_update_player_visual_visibility()

func _sync_held_item(force: bool = false) -> void:
	if player == null:
		return
	var selected_item: String = _get_selected_hotbar_item()
	var signature: String = selected_item
	if not force and signature == held_item_signature:
		return
	var icon: Texture2D = _item_icon(selected_item)
	var block_mesh: Mesh = null
	var cube_faces: Dictionary = {}
	if selected_item != "":
		var item_data: Dictionary = item_defs.get(selected_item, {})
		var place_block: String = str(item_data.get("place_block", ""))
		if place_block != "" and block_defs.has(place_block):
			var block_data: Dictionary = block_defs[place_block]
			if not bool(block_data.get("plant", false)):
				block_mesh = _block_mesh(place_block)
				cube_faces = _item_icon_faces(selected_item)
	player.set_held_item(selected_item, icon, block_mesh, cube_faces)
	held_item_signature = signature

func _apply_current_skin() -> void:
	if player == null:
		return
	var skin_texture: Texture2D = SkinLoader.load_skin(player_skin_path)
	player.apply_skin(skin_texture)

func _update_player_visual_visibility() -> void:
	if player == null:
		return
	var visuals_visible: bool = game_started and not _is_menu_open()
	player.set_visuals_visible(visuals_visible)

func _update_status() -> void:
	var selected_item: String = _get_selected_hotbar_item()
	var selected_name: String = "Vazio" if selected_item == "" else _item_name(selected_item)
	status_label.text = "Bioma 1/4: Inicio 100x100 | Mapa final: 200x200\nMana: %s/%s | Picareta Manita Nv.%s XP %s/%s\nSelecionado: %s x%s | E: craft 2x2 | F5: camera" % [
		int(mana),
		int(MANA_MAX),
		manita_pickaxe_level,
		manita_pickaxe_xp,
		manita_pickaxe_level * 10,
		selected_name,
		_get_selected_hotbar_count()
	]

func _update_cursor_stack_label() -> void:
	if cursor_stack_slot == null:
		return
	if _slot_item(cursor_stack) == "":
		cursor_stack_slot.visible = false
		cursor_stack_signature = ""
		return
	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	var item_id: String = _slot_item(cursor_stack)
	var count: int = _slot_count(cursor_stack)
	var signature: String = "%s:%s" % [item_id, count]
	if signature != cursor_stack_signature:
		cursor_stack_slot.configure(
			self,
			"cursor",
			-1,
			item_id,
			count,
			_item_name(item_id),
			_item_description(item_id),
			_item_icon(item_id),
			_item_icon_faces(item_id),
			Vector2(58, 58),
			false
		)
		cursor_stack_signature = signature
	cursor_stack_slot.visible = game_started and not _is_menu_open()
	cursor_stack_slot.global_position = mouse_position + Vector2(14, 14)

func _show_slot_tooltip(slot_type: String, slot_index: int) -> void:
	if tooltip_panel == null or _is_menu_open():
		return
	var slot: Dictionary = _get_slot(slot_type, slot_index)
	var item_id: String = _slot_item(slot)
	if item_id == "":
		_hide_slot_tooltip()
		return
	hovered_slot_type = slot_type
	hovered_slot_index = slot_index
	tooltip_name_label.text = _item_name(item_id)
	tooltip_description_label.text = _item_description(item_id)
	tooltip_panel.visible = true
	tooltip_panel.reset_size()
	_update_hover_tooltip_position()

func _hide_slot_tooltip() -> void:
	hovered_slot_type = ""
	hovered_slot_index = -1
	if tooltip_panel != null:
		tooltip_panel.visible = false

func _update_hover_tooltip_position() -> void:
	if tooltip_panel == null or not tooltip_panel.visible:
		return
	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	var tooltip_size: Vector2 = tooltip_panel.size
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var desired_position: Vector2 = mouse_position + Vector2(18, 18)
	if desired_position.x + tooltip_size.x > viewport_size.x:
		desired_position.x = mouse_position.x - tooltip_size.x - 18
	if desired_position.y + tooltip_size.y > viewport_size.y:
		desired_position.y = mouse_position.y - tooltip_size.y - 18
	tooltip_panel.global_position = Vector2(max(4.0, desired_position.x), max(4.0, desired_position.y))

func _update_hotbar() -> void:
	_clear_children(hotbar_box)
	for i in range(HOTBAR_SLOT_COUNT):
		var slot: Dictionary = inventory_slots[i]
		var slot_node: ItemSlot = _make_item_slot("inventory", i, slot, Vector2(54, 54))
		slot_node.set_selected(i == selected_hotbar_index)
		hotbar_box.add_child(slot_node)
	_sync_held_item()

func _update_inventory_panel() -> void:
	_clear_children(inventory_grid)
	for i in range(inventory_slots.size()):
		var slot: Dictionary = inventory_slots[i]
		inventory_grid.add_child(_make_item_slot("inventory", i, slot, Vector2(78, 54)))

	_clear_children(craft_grid)
	craft_grid.columns = craft_size
	for i in range(craft_slots.size()):
		var slot: Dictionary = craft_slots[i]
		craft_grid.add_child(_make_item_slot("craft", i, slot, Vector2(82, 58)))
	_update_craft_output_slot()

func _update_chest_panel() -> void:
	_clear_children(chest_player_grid)
	for i in range(inventory_slots.size()):
		var slot: Dictionary = inventory_slots[i]
		chest_player_grid.add_child(_make_item_slot("inventory", i, slot, Vector2(76, 52)))

	_clear_children(chest_grid)
	var chest_slots: Array = _get_slots_for_type("chest")
	for i in range(chest_slots.size()):
		var slot: Dictionary = chest_slots[i]
		chest_grid.add_child(_make_item_slot("chest", i, slot, Vector2(76, 52)))

func _update_craft_output_slot() -> void:
	if craft_output_holder == null:
		return
	_clear_children(craft_output_holder)
	var output_slot: Dictionary = _current_craft_output_slot()
	craft_output_holder.add_child(_make_item_slot("craft_output", 0, output_slot, Vector2(82, 58)))
	if _slot_item(output_slot) == "":
		craft_result_label.text = ""
	else:
		craft_result_label.text = "%s x%s" % [_item_name(_slot_item(output_slot)), _slot_count(output_slot)]

func _make_item_slot(slot_type: String, slot_index: int, slot: Dictionary, slot_size: Vector2) -> ItemSlot:
	var item_id: String = _slot_item(slot)
	var count: int = _slot_count(slot)
	var node: ItemSlot = ItemSlot.new()
	node.configure(
		self,
		slot_type,
		slot_index,
		item_id,
		count,
		_item_name(item_id),
		_item_description(item_id),
		_item_icon(item_id),
		_item_icon_faces(item_id),
		slot_size
	)
	return node

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _message(text: String) -> void:
	message_label.text = text
	message_time = 3.5
