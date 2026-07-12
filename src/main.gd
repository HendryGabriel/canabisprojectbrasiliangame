extends Node3D

const VoxelWorldScript = preload("res://src/voxel_world.gd")
const VoxelSectionSystemScript = preload("res://src/voxel_section_system.gd")
const PerformanceProfileScript = preload("res://src/performance_profile.gd")
const VoxelTextureArrayScript = preload("res://src/voxel_texture_array.gd")
const EditResultScript = preload("res://src/edit_result.gd")
const TerrainTileDataScript = preload("res://src/terrain_tile_data.gd")
const TerrainGeneratorScript = preload("res://src/terrain_generator.gd")
const StructureRegistryScript = preload("res://src/structure_registry.gd")
const VoxelDependencyResolverScript = preload("res://src/voxel_dependency_resolver.gd")
const VoxelDebrisSystemScript = preload("res://src/voxel_debris_system.gd")
const EntityManagerScript = preload("res://src/entity_manager.gd")
const LightRegistryScript = preload("res://src/light_registry.gd")
const ThumbstoneScript = preload("res://src/thumbstone.gd")
const SchematicImporterScript = preload("res://src/schematic_importer.gd")
const SceneryDataScript = preload("res://src/scenery_data.gd")
const BlueprintDataScript = preload("res://src/blueprint_data.gd")
const SCENERY_DIR: String = "res://data/scenery/"
const BLUEPRINT_DIR: String = "res://data/blueprints/"

const BIOME_SIZE: int = 100
const SURFACE_BASE_Y: int = 0
const BEDROCK_Y: int = -65
const WORLD_SEED: int = 1235571
const BIOME_MIN_X: int = 0
const BIOME_MAX_X: int = BIOME_SIZE - 1
const BIOME_MIN_Z: int = 0
const BIOME_MAX_Z: int = BIOME_SIZE - 1
## Covers the complete -65..126 voxel volume so the four locked regions cannot
## be bypassed above the former 64-block terrain depth.
const WORLD_WALL_HEIGHT: float = 192.0
const INVENTORY_SLOT_COUNT: int = 27
const CHEST_SLOT_COUNT: int = 18
const CHEST_METADATA_KEY: String = "chest_inventory"
const MANA_MAX: float = 100.0
const MANA_REGEN_PER_SECOND: float = 5.0
const MANITA_PICKAXE_MANA_COST: float = 5.0
const HOTBAR_SLOT_COUNT: int = 9
const SAVE_PATH: String = "user://savegame_v4.json"
const V3_SAVE_PATH: String = "user://savegame_v3.json"
const V2_SAVE_PATH: String = "user://savegame_v2.json"
const LEGACY_SAVE_PATH: String = "user://savegame.json"
const SETTINGS_PATH: String = "user://settings.cfg"
const DEFAULT_TERRAIN_TILE_PATH: String = "res://data/terrain/biome_1.tterrain.json"
const DEFAULT_STRUCTURE_REGISTRY_PATH: String = "res://data/structures/registry.json"
const SHADOW_OPACITY: float = 0.4
const LEAF_PARTICLE_MAX: int = 28
const LEAF_PARTICLE_SPAWN_INTERVAL: float = 0.34
const LEAF_PARTICLE_SEARCH_RADIUS: int = 10
const BENCHMARK_DURATION_SECONDS: float = 30.0
const PLAYER_MAX_HEALTH: float = 20.0

var breaking_pos: Vector3i = Vector3i(-999, -999, -999)
var breaking_progress: float = 0.0
var breaking_overlay: MeshInstance3D = null
var breaking_crack_textures: Array = []
var target_outline: MeshInstance3D = null
var target_outline_pos: Vector3i = Vector3i(-999, -999, -999)
var dropped_items: Array = []
var is_loading_world: bool = false
var continue_on_load_finish: bool = false
var loaded_game_data: Dictionary = {}
var last_load_error: String = ""
var place_cooldown: float = 0.0
var leaf_particles: Array = []
var leaf_particle_spawn_timer: float = 0.0
var leaf_particle_texture: Texture2D = null
var leaf_particle_mesh: QuadMesh = null
var leaf_particle_limit: int = LEAF_PARTICLE_MAX

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
var surface_heights: Dictionary = {}
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
var game_started: bool = false
var fullscreen_enabled: bool = false
var shadows_enabled: bool = true
var ssao_enabled: bool = true
var voxel_ao_enabled: bool = true
var options_origin: String = "main"
var player_skin_path: String = ""
var saved_camera_mode: int = 0
var performance_preset: int = PerformanceProfileScript.Preset.HIGH
var performance_profile = null
var voxel_world = null
var voxel_sections = null
var voxel_texture_array = null
var voxel_debris = null
var active_terrain_tile = null
var active_structure_registry = null
var active_terrain_hash: String = ""
var active_registry_hash: String = ""
var last_generation_report = null
var cached_target = null # VoxelHit from VoxelWorld.raycast_hit().
## One DDA result is authoritative for all interaction visuals and edits until
## the next physics tick. This keeps plants targetable without physics bodies.
var cached_target_physics_frame: int = -1
var hotbar_slots: Array[ItemSlot] = []
var last_status_text: String = ""
var benchmark_active: bool = false
var benchmark_elapsed: float = 0.0
var benchmark_samples_ms: Array[float] = []
var pending_player_health: float = PLAYER_MAX_HEALTH
var left_click_consumed: bool = false
var right_click_consumed: bool = false
var light_registry = null
var entity_manager = null
var thumbstones: Array = []

# --- modo criativo / superplano / schematic / ferramenta de area ---
var creative_mode: bool = false
var world_type: String = "normal"   # "normal" | "superflat"
var flat_size: int = 100            # lado da area desbloqueada no superplano
var flat_surface_y: int = 0
var creative_items: Array = []
var creative_panel: PanelContainer
var creative_grid: GridContainer
var creative_inv_grid: GridContainer
var schematic_mode: bool = false
var schematic_data: Dictionary = {}
var schematic_rot: int = 0
var schematic_preview: MeshInstance3D = null
var schematic_dialog: FileDialog
var flat_size_slider: HSlider
var flat_size_value_label: Label
var flat_size_row: VBoxContainer
var sel_a: Vector3i = Vector3i.ZERO
var sel_b: Vector3i = Vector3i.ZERO
var sel_count: int = 0
var sel_box: MeshInstance3D = null
# construtor de mundo (dev constroi o mapa que o jogador real recebe)
const BUILDER_DIR: String = "user://builder_worlds/"
const OFFICIAL_MAP_PATH: String = "res://data/world/mapa_oficial.json"
var builder_mode: bool = false
var builder_world_name: String = ""
var builder_pending: Dictionary = {}
var builder_panel: PanelContainer
var builder_list: ItemList
var builder_status: Label
var builder_create_panel: PanelContainer
var builder_name_edit: LineEdit
var builder_type_button: Button
var builder_type_flat: bool = false
var publicar_button: Button
var _mapa_oficial_cache: Dictionary = {}
var _mapa_oficial_lido: bool = false
# blueprints multibloco (estilo Satisfactory)
var blueprint_menu: PanelContainer
var blueprint_mode: bool = false
var active_blueprint = null
var bp_rot: int = 0
var bp_ghost: MeshInstance3D = null
var construction_sites: Array = []   # [{bp, base, rot, next_layer, ghost}]

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
var performance_preset_option: OptionButton
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
	voxel_world = VoxelWorldScript.new(block_defs)
	performance_profile = PerformanceProfileScript.new()
	inventory_slots = _make_slots(INVENTORY_SLOT_COUNT)
	craft_slots = _make_slots(4)

	_load_settings()
	_apply_fullscreen(fullscreen_enabled)
	_setup_materials()
	_create_lighting()
	_create_ui()
	_show_main_menu()
	_message("Mundo finito pronto. Inicie um novo jogo para gerar o Bioma 1.")


func _physics_process(_delta: float) -> void:
	if not is_loading_world:
		_update_cached_target()


func _process(delta: float) -> void:
	if is_loading_world:
		if voxel_sections != null:
			voxel_sections.process_updates(true)
			var pct: float = voxel_sections.get_loading_progress() * 100.0
			loading_progress_bar.value = pct
			loading_label.text = "Construindo o Mundo: %d%%" % int(pct)
			if voxel_sections.is_idle():
				_finish_world_loading()
		return

	if voxel_sections != null:
		voxel_sections.process_updates(false)
	if voxel_texture_array != null and player != null:
		voxel_texture_array.update_micro_foliage(player.global_position, player.velocity)
	if voxel_debris != null:
		voxel_debris.update_particles(delta, voxel_world)

	mana = min(MANA_MAX, mana + MANA_REGEN_PER_SECOND * delta)
	if place_cooldown > 0.0:
		place_cooldown -= delta

	_update_day_night_cycle(delta)
	_update_leaf_particles(delta)
	_update_frame_benchmark(delta)
	
	if message_time > 0:
		message_time -= delta
		if message_time <= 0:
			message_label.text = ""
	if player != null and is_instance_valid(player) and player.is_inside_tree():
		# Handle held left-click block breaking & held right-click block placing
		if game_started and not _is_menu_open() and not inventory_panel.visible and not chest_panel.visible and not (creative_panel != null and creative_panel.visible):
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not left_click_consumed and not schematic_mode and not blueprint_mode and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				_handle_block_breaking(delta)
			else:
				_cancel_block_breaking()
				
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not right_click_consumed and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				if place_cooldown <= 0.0:
					if _use_or_place_target():
						place_cooldown = 0.2
		else:
			_cancel_block_breaking()
		_update_target_outline()
		_update_schematic_preview()
		_update_blueprint_preview()
	_update_cursor_stack_label()
	_update_hover_tooltip_position()
	_update_status()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if not mouse_event.pressed:
			if mouse_event.button_index == MOUSE_BUTTON_LEFT:
				left_click_consumed = false
				if left_drag_active:
					_finish_left_drag()
			elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
				right_click_consumed = false
				right_drag_active = false
				right_drag_keys.clear()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F9:
			_toggle_frame_benchmark()
			return
		if event.keycode == KEY_ESCAPE:
			if options_panel != null and options_panel.visible:
				_close_options_panel()
			elif builder_create_panel != null and builder_create_panel.visible:
				builder_create_panel.visible = false
				builder_panel.visible = true
			elif builder_panel != null and builder_panel.visible:
				builder_panel.visible = false
				_show_main_menu()
			elif main_menu_panel != null and main_menu_panel.visible:
				return
			elif pause_menu_panel != null and pause_menu_panel.visible:
				_resume_game()
			elif blueprint_mode:
				_cancelar_blueprint()
			elif blueprint_menu != null and blueprint_menu.visible:
				blueprint_menu.visible = false
				_set_ui_mode(false)
			elif schematic_mode:
				_cancelar_schematic()
			elif inventory_panel.visible or chest_panel.visible or (creative_panel != null and creative_panel.visible):
				_close_all_panels()
			else:
				_show_pause_menu()
			return
		if not game_started or _is_menu_open():
			return
		if event.keycode == KEY_SHIFT:
			_collect_nearby_thumbstone()
		if event.keycode == KEY_E:
			if chest_panel.visible or inventory_panel.visible or (creative_panel != null and creative_panel.visible):
				_close_all_panels()
			elif creative_mode:
				_open_creative_panel()
			else:
				_open_inventory_craft()
			return
		if event.keycode == KEY_F4:
			_toggle_creative_mode()
			return
		if event.keycode == KEY_F3:
			_toggle_blueprint_menu()
			return
		if event.keycode == KEY_G:
			_entregar_material_para_obra()
			return
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			if event.keycode == KEY_R:
				if schematic_mode:
					schematic_rot = (schematic_rot + 1) % 4
					_message("Schematic girado para %d graus." % (schematic_rot * 90))
				elif blueprint_mode:
					bp_rot = (bp_rot + 1) % 4
					_message("Projeto girado para %d graus." % (bp_rot * 90))
				else:
					_marcar_canto_selecao()
				return
			if event.keycode == KEY_F:
				_preencher_selecao()
				return
			if event.keycode == KEY_X:
				_limpar_selecao(true)
				return
			if event.keycode == KEY_B:
				_salvar_selecao_como_blueprint()
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

	if not game_started or _is_menu_open() or inventory_panel.visible or chest_panel.visible or (creative_panel != null and creative_panel.visible):
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
		if event.button_index == MOUSE_BUTTON_LEFT:
			if blueprint_mode:
				_posicionar_obra()
				left_click_consumed = true
				get_viewport().set_input_as_handled()
				return
			if schematic_mode:
				_estampar_schematic()
				left_click_consumed = true
				get_viewport().set_input_as_handled()
				return
			left_click_consumed = _handle_primary_click()
			if left_click_consumed:
				get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if Input.is_key_pressed(KEY_SHIFT) and _collect_target_thumbstone():
				right_click_consumed = true
				get_viewport().set_input_as_handled()
				return
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
	voxel_texture_array = VoxelTextureArrayScript.new()
	if voxel_texture_array.build(block_defs):
		voxel_world.configure_texture_layers(voxel_texture_array.layer_by_path)
	else:
		voxel_texture_array = null


func _material_for_voxel_surface(surface: Dictionary) -> Material:
	if bool(surface.get("use_texture_array", false)) and voxel_texture_array != null:
		var array_material: Material = voxel_texture_array.material_for(str(surface.get("render_class", "opaque")))
		if array_material != null:
			return array_material
	return _material_for_texture(
		str(surface.get("texture_path", "")),
		surface.get("fallback_color", Color.WHITE),
		float(surface.get("alpha", 1.0)),
		bool(surface.get("transparent", false)),
		bool(surface.get("foliage", false))
	)

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
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED if transparent or foliage else BaseMaterial3D.CULL_BACK
	# Godot exposes texture_repeat as an enum-backed integer; 1 is repeat enabled.
	mat.texture_repeat = 1
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

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
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
	ALPHA = step(0.08, tex.a * COLOR.a * tint.a);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
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
	if leaf_particles.size() >= leaf_particle_limit:
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
			if voxel_world != null and _is_foliage_block_id(voxel_world.get_block_id(pos)):
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
	if texture == null:
		# bloco de cor pura (sem textura): gera um icone de cor solida
		var place_block2: String = str(item_data.get("place_block", ""))
		var bd: Dictionary = block_defs.get(place_block2, {})
		if bd.has("color") and not bd.has("texture") and not bd.has("textures"):
			texture = _solid_color_icon(bd["color"])
	item_icons[item_id] = texture
	return texture

func _solid_color_icon(cor: Color) -> Texture2D:
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(cor)
	# leve borda escura pra separar os slots
	for i in range(16):
		img.set_pixel(i, 0, cor.darkened(0.4))
		img.set_pixel(i, 15, cor.darkened(0.4))
		img.set_pixel(0, i, cor.darkened(0.4))
		img.set_pixel(15, i, cor.darkened(0.4))
	return ImageTexture.create_from_image(img)

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
	sun_light.light_energy = 1.3
	sun_light.light_color = Color(1.0, 0.97, 0.9)
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
	moon_light.light_color = Color(0.62, 0.70, 0.92)
	moon_light.shadow_enabled = shadows_enabled
	moon_light.shadow_opacity = SHADOW_OPACITY
	moon_light.shadow_bias = 0.04
	moon_light.shadow_normal_bias = 2.5
	moon_light.directional_shadow_max_distance = 60.0
	add_child(moon_light)

	# --- Procedural Sky ---
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.30, 0.55, 0.88)
	sky_material.sky_horizon_color = Color(0.72, 0.84, 0.95)
	sky_material.ground_bottom_color = Color(0.12, 0.13, 0.15)
	sky_material.ground_horizon_color = Color(0.72, 0.84, 0.95)
	sky_material.sun_angle_max = 30.0
	sky_material.sun_curve = 0.15

	var sky: Sky = Sky.new()
	sky.sky_material = sky_material

	# --- Environment ---
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.84, 0.94)
	env.ambient_light_energy = 0.55

	# Tonemapping ACES
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0

	# SSAO
	env.ssao_enabled = ssao_enabled
	env.ssao_radius = 0.45
	env.ssao_intensity = 0.65

	# Fog
	env.volumetric_fog_enabled = false
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.85, 0.97)
	env.fog_light_energy = 0.7
	env.fog_density = 0.0025

	fog_env = env
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	_apply_performance_profile()

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
		sun_light.light_energy = max(sun_factor * 1.3, 0.08) if sun_altitude > 0.0 else 0.0
		sun_light.shadow_enabled = shadows_enabled and sun_altitude > 0.08
		if is_sunrise_sunset:
			sun_light.light_color = Color(1.0, 0.62, 0.35).lerp(Color(1.0, 0.97, 0.9), sun_factor)
		else:
			sun_light.light_color = Color(1.0, 0.97, 0.9)

	# --- Moon intensity ---
	if moon_light != null:
		var moon_factor: float = clamp(-sun_altitude - 0.1, 0.0, 1.0)
		moon_light.light_color = Color(0.62, 0.70, 0.92)
		moon_light.light_energy = moon_factor * 0.35
		moon_light.shadow_enabled = shadows_enabled and moon_factor > 0.08

	# --- Sky colors ---
	if sky_material != null:
		var day_top: Color = Color(0.30, 0.55, 0.88)
		var day_horizon: Color = Color(0.72, 0.84, 0.95)
		var night_top: Color = Color(0.02, 0.03, 0.09)
		var night_horizon: Color = Color(0.07, 0.10, 0.18)
		var sunset_top: Color = Color(0.28, 0.32, 0.55)
		var sunset_horizon: Color = Color(0.98, 0.58, 0.28)

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
		var ambient_energy: float = lerp(0.40, 0.55, sun_factor) if not is_night else 0.32
		fog_env.ambient_light_energy = ambient_energy

		if is_night:
			fog_env.ambient_light_color = Color(0.16, 0.20, 0.32)
		elif is_sunrise_sunset:
			var t: float = clamp(sun_altitude / 0.25, 0.0, 1.0)
			fog_env.ambient_light_color = Color(0.88, 0.68, 0.52).lerp(Color(0.78, 0.84, 0.94), t)
		else:
			fog_env.ambient_light_color = Color(0.78, 0.84, 0.94)

		# --- Fog color follows sky ---
		if is_night:
			fog_env.fog_light_color = Color(0.05, 0.07, 0.13)
		elif is_sunrise_sunset:
			var t: float = clamp(sun_altitude / 0.25, 0.0, 1.0)
			fog_env.fog_light_color = Color(0.95, 0.62, 0.38).lerp(Color(0.75, 0.85, 0.97), t)
		else:
			fog_env.fog_light_color = Color(0.75, 0.85, 0.97)

	# --- HUD time label ---
	if hud_time_label != null:
		var hours: int = int(time_of_day) % 24
		var minutes: int = int(fmod(time_of_day, 1.0) * 60.0)
		hud_time_label.text = "Dia %d - %02d:%02d" % [day_count, hours, minutes]

func _create_world() -> void:
	if voxel_world == null:
		voxel_world = VoxelWorldScript.new(block_defs)
	voxel_world.reset(WORLD_SEED)
	world_root = Node3D.new()
	world_root.name = "FiniteVoxelWorld_200x200"
	add_child(world_root)
	voxel_debris = VoxelDebrisSystemScript.new()
	voxel_debris.name = "VoxelDebris"
	world_root.add_child(voxel_debris)
	voxel_debris.configure(block_defs, int(performance_profile.get_settings().get("voxel_debris_max", 256)))
	voxel_sections = VoxelSectionSystemScript.new()
	voxel_sections.name = "VoxelSectionSystem"
	world_root.add_child(voxel_sections)
	voxel_sections.setup(voxel_world, Callable(self, "_material_for_voxel_surface"), voxel_ao_enabled)
	_apply_performance_profile()
	_generate_biome_one_data()

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
	if world_type == "superflat":
		_generate_superflat_data()
		return
	if voxel_world != null:
		voxel_world.set_unlocked_size(BIOME_SIZE)
	surface_heights.clear()
	_clear_chest_inventories()
	active_terrain_tile = TerrainTileDataScript.load_from_file(DEFAULT_TERRAIN_TILE_PATH)
	if active_terrain_tile == null:
		active_terrain_tile = TerrainTileDataScript.create_draft(WORLD_SEED, Vector2i.ZERO)
	# mapa fixo: suaviza/aplaina o relevo e reserva a zona da cidade ANTES do hash,
	# entao todo mundo gera exatamente o mesmo mapa e os saves continuam validos
	_suaviza_terreno(active_terrain_tile)
	var altura_cidade: int = _prepara_zona_cidade(active_terrain_tile)
	active_structure_registry = StructureRegistryScript.load_from_file(DEFAULT_STRUCTURE_REGISTRY_PATH)
	if active_structure_registry == null:
		active_structure_registry = StructureRegistryScript.empty_registry()
	active_terrain_hash = active_terrain_tile.content_hash()
	active_registry_hash = active_structure_registry.content_hash()
	var generator = TerrainGeneratorScript.new()
	last_generation_report = generator.generate_into(voxel_world, active_terrain_tile, active_structure_registry, WORLD_SEED)
	if not last_generation_report.is_ok():
		push_error(last_generation_report.summary())
	_construir_cidade(altura_cidade)
	_aplicar_mapa_oficial()
	for z in range(TerrainTileDataScript.TILE_SIZE):
		for x in range(TerrainTileDataScript.TILE_SIZE):
			surface_heights[Vector2i(x, z)] = active_terrain_tile.get_height(x, z)


# ---------------- terreno natural + cidade fixa ----------------

const CIDADE_RECT := Rect2i(28, 28, 48, 48)  # zona urbana no tile 100x100

func _suaviza_terreno(tile) -> void:
	# 3 passadas de blur + reducao de amplitude: relevo rolando suave, bem mais plano
	var ts: int = TerrainTileDataScript.TILE_SIZE
	for passada in 3:
		var copia: PackedInt32Array = tile.heights.duplicate()
		for z in range(ts):
			for x in range(ts):
				var soma: int = 0
				var qtd: int = 0
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var nx: int = x + dx
						var nz: int = z + dz
						if nx >= 0 and nx < ts and nz >= 0 and nz < ts:
							soma += copia[nz * ts + nx]
							qtd += 1
				tile.heights[z * ts + x] = int(round(float(soma) / float(qtd)))
	var total: int = 0
	for i in range(tile.heights.size()):
		total += tile.heights[i]
	var media: float = float(total) / float(tile.heights.size())
	for i in range(tile.heights.size()):
		var h: float = media + (float(tile.heights[i]) - media) * 0.45
		tile.heights[i] = clampi(int(round(h)), TerrainTileDataScript.MIN_SURFACE_Y, TerrainTileDataScript.MAX_SURFACE_Y)


func _prepara_zona_cidade(tile) -> int:
	# aplaina a zona urbana na altura media dela e bloqueia cavernas/vegetacao/estruturas
	var ts: int = TerrainTileDataScript.TILE_SIZE
	var soma: int = 0
	var qtd: int = 0
	for z in range(CIDADE_RECT.position.y, CIDADE_RECT.end.y):
		for x in range(CIDADE_RECT.position.x, CIDADE_RECT.end.x):
			soma += tile.heights[z * ts + x]
			qtd += 1
	var altura: int = int(round(float(soma) / float(qtd)))
	for z in range(CIDADE_RECT.position.y - 2, CIDADE_RECT.end.y + 2):
		for x in range(CIDADE_RECT.position.x - 2, CIDADE_RECT.end.x + 2):
			if x < 0 or z < 0 or x >= ts or z >= ts:
				continue
			var indice: int = z * ts + x
			if CIDADE_RECT.has_point(Vector2i(x, z)):
				tile.heights[indice] = altura
				tile.zone_flags[indice] = TerrainTileDataScript.ZONE_PROTECTED | TerrainTileDataScript.ZONE_NO_CAVES
				tile.cave_density[indice] = 0
			else:
				# borda de 2 celulas faz rampa suave pra fora da cidade
				tile.heights[indice] = int(round(lerpf(float(tile.heights[indice]), float(altura), 0.5)))
	return altura


func _construir_cidade(altura: int) -> void:
	# ruas em grade + lotes com casas; deterministico (mapa fixo)
	var ox: int = CIDADE_RECT.position.x
	var oz: int = CIDADE_RECT.position.y
	var lado: int = CIDADE_RECT.size.x
	# ruas de pedra (linhas a cada 12, largura 2)
	for z in range(oz, oz + lado):
		for x in range(ox, ox + lado):
			var lx: int = x - ox
			var lz: int = z - oz
			var na_rua: bool = (lx % 12) < 2 or (lz % 12) < 2
			if na_rua:
				voxel_world.set_base_block(Vector3i(x, altura, z), "cobblestone")
				for y in range(altura + 1, altura + 6):
					voxel_world.clear_base_block(Vector3i(x, y, z))
	# postes de luz nos cruzamentos
	for iz in range(0, lado, 12):
		for ix in range(0, lado, 12):
			var px: int = ox + ix
			var pz: int = oz + iz
			for y in range(altura + 1, altura + 4):
				voxel_world.set_base_block(Vector3i(px, y, pz), "wood")
			voxel_world.set_base_block(Vector3i(px, altura + 4, pz), "torch")
	# lotes 4x4 (origem a cada 12, offset 2 da rua)
	var indice_lote: int = 0
	for iz in range(0, lado - 2, 12):
		for ix in range(0, lado - 2, 12):
			var lote_x: int = ox + ix + 2
			var lote_z: int = oz + iz + 2
			indice_lote += 1
			if lote_x <= 50 and lote_x + 9 >= 44 and lote_z <= 50 and lote_z + 9 >= 44:
				_construir_casa(lote_x + 1, lote_z + 1, altura, "planks")  # casa do jogador
			elif indice_lote % 5 == 0:
				_construir_praca(lote_x, lote_z, altura)
			else:
				var parede: String = "planks" if (indice_lote % 3) != 0 else "cobblestone"
				_construir_casa(lote_x + 1, lote_z + 1, altura, parede)


func _construir_casa(cx: int, cz: int, altura: int, parede: String) -> void:
	var larg: int = 7
	var prof: int = 6
	# limpa o volume e poe piso
	for x in range(cx, cx + larg):
		for z in range(cz, cz + prof):
			for y in range(altura + 1, altura + 7):
				voxel_world.clear_base_block(Vector3i(x, y, z))
			voxel_world.set_base_block(Vector3i(x, altura, z), "cobblestone")
	# paredes com cantos de madeira
	for y in range(altura + 1, altura + 4):
		for x in range(cx, cx + larg):
			for z in range(cz, cz + prof):
				var na_borda: bool = x == cx or x == cx + larg - 1 or z == cz or z == cz + prof - 1
				if not na_borda:
					continue
				var canto: bool = (x == cx or x == cx + larg - 1) and (z == cz or z == cz + prof - 1)
				voxel_world.set_base_block(Vector3i(x, y, z), "wood" if canto else parede)
	# porta (sul, 1x2) e janelas (leste/oeste)
	var porta_x: int = cx + int(larg / 2.0)
	voxel_world.clear_base_block(Vector3i(porta_x, altura + 1, cz + prof - 1))
	voxel_world.clear_base_block(Vector3i(porta_x, altura + 2, cz + prof - 1))
	voxel_world.clear_base_block(Vector3i(cx, altura + 2, cz + int(prof / 2.0)))
	voxel_world.clear_base_block(Vector3i(cx + larg - 1, altura + 2, cz + int(prof / 2.0)))
	# telhado
	for x in range(cx, cx + larg):
		for z in range(cz, cz + prof):
			voxel_world.set_base_block(Vector3i(x, altura + 4, z), "planks")
	# tocha interna
	voxel_world.set_base_block(Vector3i(cx + 1, altura + 1, cz + 1), "torch")


func _construir_praca(cx: int, cz: int, altura: int) -> void:
	for x in range(cx, cx + 10):
		for z in range(cz, cz + 10):
			for y in range(altura + 1, altura + 6):
				voxel_world.clear_base_block(Vector3i(x, y, z))
			voxel_world.set_base_block(Vector3i(x, altura, z), "stone")
	for canto in [Vector2i(cx + 1, cz + 1), Vector2i(cx + 8, cz + 1), Vector2i(cx + 1, cz + 8), Vector2i(cx + 8, cz + 8)]:
		voxel_world.set_base_block(Vector3i(canto.x, altura + 1, canto.y), "torch")


# ---------------- mundo superplano ----------------

func _generate_superflat_data() -> void:
	surface_heights.clear()
	_clear_chest_inventories()
	# se ha mapa oficial superplano publicado, novos jogos herdam o tamanho dele
	if not builder_mode:
		var oficial: Dictionary = _carregar_mapa_oficial()
		if str(oficial.get("world_type", "")) == "superflat":
			flat_size = clampi(maxi(flat_size, int(oficial.get("flat_size", 100))), 100, VoxelWorldScript.WORLD_WIDTH)
	var tile = TerrainTileDataScript.new()
	tile.tile_coord = Vector2i.ZERO
	tile.draft_seed = WORLD_SEED
	tile.heights.fill(flat_surface_y)
	tile.surface_profiles.fill(TerrainTileDataScript.PROFILE_GRASS)
	tile.cave_density.fill(0)   # sem cavernas
	tile.zone_flags.fill(0)     # sem florestas/decoracao/estruturas
	active_terrain_tile = tile
	active_structure_registry = StructureRegistryScript.empty_registry()
	active_terrain_hash = active_terrain_tile.content_hash()
	active_registry_hash = active_structure_registry.content_hash()
	var generator = TerrainGeneratorScript.new()
	last_generation_report = generator.generate_into(voxel_world, active_terrain_tile, active_structure_registry, WORLD_SEED)
	if not last_generation_report.is_ok():
		push_error(last_generation_report.summary())
	for z in range(TerrainTileDataScript.TILE_SIZE):
		for x in range(TerrainTileDataScript.TILE_SIZE):
			surface_heights[Vector2i(x, z)] = flat_surface_y
	# a area alem do tile de 100x100 (expansao salva) e gerada direto, plana
	voxel_world.set_unlocked_size(flat_size)
	if flat_size > TerrainTileDataScript.TILE_SIZE:
		for x in range(flat_size):
			for z in range(flat_size):
				if x >= TerrainTileDataScript.TILE_SIZE or z >= TerrainTileDataScript.TILE_SIZE:
					_gera_coluna_flat(x, z)
	_aplicar_mapa_oficial()


func _gera_coluna_flat(x: int, z: int) -> void:
	for y in range(BEDROCK_Y, flat_surface_y + 1):
		var id: String
		if y == BEDROCK_Y:
			id = "bedrock"
		elif y == flat_surface_y:
			id = "grass"
		elif flat_surface_y - y <= 3:
			id = "dirt"
		else:
			id = "stone"
		voxel_world.set_base_block(Vector3i(x, y, z), id)
	voxel_world.set_surface_height(x, z, flat_surface_y)
	surface_heights[Vector2i(x, z)] = flat_surface_y


func _aplicar_tamanho_flat() -> void:
	if world_type != "superflat" or voxel_world == null:
		if pause_status_label != null:
			pause_status_label.text = "Ajuste de tamanho so vale em mundos superplanos."
		return
	var novo: int = int(flat_size_slider.value)
	var atual: int = voxel_world.unlocked_size
	if novo <= atual:
		pause_status_label.text = "O mapa ja tem %d x %d — so da pra aumentar." % [atual, atual]
		return
	for x in range(novo):
		for z in range(novo):
			if x >= atual or z >= atual:
				_gera_coluna_flat(x, z)
	flat_size = novo
	voxel_world.set_unlocked_size(novo)
	_rebuild_world_bounds()
	if voxel_sections != null:
		voxel_sections.queue_rebuild_all(false)
	pause_status_label.text = "Mapa expandido para %d x %d." % [novo, novo]


func _peek_save_meta() -> void:
	# le so os metadados do save ANTES de gerar a base (tipo/tamanho definem a geracao)
	world_type = "normal"
	flat_size = 100
	flat_surface_y = 0
	creative_mode = false
	var caminho: String = SAVE_PATH if FileAccess.file_exists(SAVE_PATH) else V3_SAVE_PATH
	var arquivo: FileAccess = FileAccess.open(caminho, FileAccess.READ)
	if arquivo == null:
		return
	var json: JSON = JSON.new()
	if json.parse(arquivo.get_as_text()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	var dados: Dictionary = json.data
	world_type = str(dados.get("world_type", "normal"))
	flat_size = clampi(int(dados.get("flat_size", 100)), 100, VoxelWorldScript.WORLD_WIDTH)
	flat_surface_y = int(dados.get("flat_surface_y", 0))
	creative_mode = bool(dados.get("creative_mode", false))


# ---------------- construtor de mundo (dev -> mapa do jogador) ----------------

func _create_builder_panels() -> void:
	# lista de mundos (estilo Singleplayer do Minecraft)
	builder_panel = _make_center_menu_panel(Vector2(520, 560))
	builder_panel.visible = false
	ui_layer.add_child(builder_panel)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	builder_panel.add_child(root)
	var titulo: Label = Label.new()
	titulo.text = "Construtor de Mundo"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 26)
	titulo.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.12))
	titulo.add_theme_constant_override("outline_size", 5)
	root.add_child(titulo)
	var sub: Label = Label.new()
	sub.text = "O mundo salvo aqui pode ser publicado como o mapa que o jogador real recebe."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(sub)
	builder_list = ItemList.new()
	builder_list.custom_minimum_size = Vector2(480, 220)
	root.add_child(builder_list)
	var linha1: HBoxContainer = HBoxContainer.new()
	linha1.add_theme_constant_override("separation", 8)
	root.add_child(linha1)
	var b_jogar: Button = _make_menu_button("Jogar Mundo Selecionado", _builder_play_selected)
	b_jogar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	linha1.add_child(b_jogar)
	var b_criar: Button = _make_menu_button("Criar Novo Mundo", _builder_open_create)
	b_criar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	linha1.add_child(b_criar)
	var linha2: HBoxContainer = HBoxContainer.new()
	linha2.add_theme_constant_override("separation", 8)
	root.add_child(linha2)
	var b_publicar: Button = _make_menu_button("Publicar p/ Jogadores", _builder_publish_selected)
	b_publicar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	linha2.add_child(b_publicar)
	var b_apagar: Button = _make_menu_button("Apagar", _builder_delete_selected)
	b_apagar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	linha2.add_child(b_apagar)
	builder_status = Label.new()
	builder_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(builder_status)
	root.add_child(_make_menu_button("Voltar", func() -> void:
		builder_panel.visible = false
		_show_main_menu()))

	# criar novo mundo (estilo Create New World do Minecraft)
	builder_create_panel = _make_center_menu_panel(Vector2(460, 380))
	builder_create_panel.visible = false
	ui_layer.add_child(builder_create_panel)
	var croot: VBoxContainer = VBoxContainer.new()
	croot.add_theme_constant_override("separation", 12)
	builder_create_panel.add_child(croot)
	var ctitulo: Label = Label.new()
	ctitulo.text = "Criar Novo Mundo"
	ctitulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ctitulo.add_theme_font_size_override("font_size", 24)
	croot.add_child(ctitulo)
	var nome_label: Label = Label.new()
	nome_label.text = "Nome do Mundo"
	croot.add_child(nome_label)
	builder_name_edit = LineEdit.new()
	builder_name_edit.text = "Novo Mundo"
	builder_name_edit.custom_minimum_size = Vector2(0, 38)
	croot.add_child(builder_name_edit)
	builder_type_button = _make_menu_button("Tipo de Mundo: Normal", _builder_cycle_type)
	croot.add_child(builder_type_button)
	croot.add_child(_make_menu_button("Criar Mundo", _builder_confirm_create))
	croot.add_child(_make_menu_button("Voltar", func() -> void:
		builder_create_panel.visible = false
		builder_panel.visible = true))


func _show_builder_menu() -> void:
	main_menu_panel.visible = false
	builder_create_panel.visible = false
	builder_panel.visible = true
	builder_status.text = ""
	_refresh_builder_list()


func _refresh_builder_list() -> void:
	builder_list.clear()
	DirAccess.make_dir_recursive_absolute(BUILDER_DIR)
	var dir: DirAccess = DirAccess.open(BUILDER_DIR)
	if dir == null:
		return
	var nomes: Array = []
	for arquivo in dir.get_files():
		if arquivo.ends_with(".json"):
			nomes.append(arquivo)
	nomes.sort()
	for arquivo in nomes:
		builder_list.add_item(arquivo.trim_suffix(".json"))


func _builder_selected_file() -> String:
	var sel: PackedInt32Array = builder_list.get_selected_items()
	if sel.is_empty():
		return ""
	return BUILDER_DIR + builder_list.get_item_text(sel[0]) + ".json"


func _builder_open_create() -> void:
	builder_panel.visible = false
	builder_create_panel.visible = true
	builder_type_flat = false
	builder_type_button.text = "Tipo de Mundo: Normal"


func _builder_cycle_type() -> void:
	builder_type_flat = not builder_type_flat
	builder_type_button.text = "Tipo de Mundo: Superplano" if builder_type_flat else "Tipo de Mundo: Normal"


func _builder_confirm_create() -> void:
	var nome: String = builder_name_edit.text.strip_edges()
	if nome == "":
		nome = "Novo Mundo"
	builder_world_name = nome
	builder_mode = true
	creative_mode = true
	world_type = "superflat" if builder_type_flat else "normal"
	flat_size = 100
	builder_pending = {}
	builder_create_panel.visible = false
	_start_world_loading(false)


func _builder_play_selected() -> void:
	var caminho: String = _builder_selected_file()
	if caminho == "":
		builder_status.text = "Selecione um mundo na lista."
		return
	var arquivo: FileAccess = FileAccess.open(caminho, FileAccess.READ)
	if arquivo == null:
		builder_status.text = "Nao foi possivel abrir o mundo."
		return
	var json: JSON = JSON.new()
	if json.parse(arquivo.get_as_text()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		builder_status.text = "Arquivo de mundo corrompido."
		return
	var dados: Dictionary = json.data
	builder_pending = dados
	builder_world_name = str(dados.get("name", builder_list.get_item_text(builder_list.get_selected_items()[0])))
	builder_mode = true
	creative_mode = true
	world_type = str(dados.get("world_type", "normal"))
	flat_size = clampi(int(dados.get("flat_size", 100)), 100, VoxelWorldScript.WORLD_WIDTH)
	flat_surface_y = int(dados.get("flat_surface_y", 0))
	builder_panel.visible = false
	_start_world_loading(false)


func _builder_delete_selected() -> void:
	var caminho: String = _builder_selected_file()
	if caminho == "":
		builder_status.text = "Selecione um mundo pra apagar."
		return
	DirAccess.remove_absolute(caminho)
	_refresh_builder_list()
	builder_status.text = "Mundo apagado."


func _builder_publish_selected() -> void:
	var caminho: String = _builder_selected_file()
	if caminho == "":
		builder_status.text = "Selecione o mundo que sera o mapa dos jogadores."
		return
	if _publicar_arquivo(caminho):
		builder_status.text = "Publicado! Novos jogos vao usar esse mapa."
	else:
		builder_status.text = "Falha ao publicar."


func _publicar_arquivo(caminho: String) -> bool:
	var arquivo: FileAccess = FileAccess.open(caminho, FileAccess.READ)
	if arquivo == null:
		return false
	var texto: String = arquivo.get_as_text()
	DirAccess.make_dir_recursive_absolute(OFFICIAL_MAP_PATH.get_base_dir())
	var destino: FileAccess = FileAccess.open(OFFICIAL_MAP_PATH, FileAccess.WRITE)
	if destino == null:
		return false
	destino.store_string(texto)
	_mapa_oficial_lido = false  # invalida o cache
	return true


func _salvar_mundo_construtor() -> bool:
	if not builder_mode or voxel_world == null:
		return false
	DirAccess.make_dir_recursive_absolute(BUILDER_DIR)
	var dados: Dictionary = {
		"format": "trumancraft_builder_world",
		"version": 1,
		"name": builder_world_name,
		"world_type": world_type,
		"flat_size": voxel_world.unlocked_size,
		"flat_surface_y": flat_surface_y,
		"changes": voxel_world.export_changes(),
		"metadata": voxel_world.export_metadata(),
	}
	var caminho: String = BUILDER_DIR + builder_world_name.validate_filename() + ".json"
	var arquivo: FileAccess = FileAccess.open(caminho, FileAccess.WRITE)
	if arquivo == null:
		return false
	arquivo.store_string(JSON.stringify(dados))
	return true


func _carregar_mapa_oficial() -> Dictionary:
	if _mapa_oficial_lido:
		return _mapa_oficial_cache
	_mapa_oficial_lido = true
	_mapa_oficial_cache = {}
	if not FileAccess.file_exists(OFFICIAL_MAP_PATH):
		return _mapa_oficial_cache
	var arquivo: FileAccess = FileAccess.open(OFFICIAL_MAP_PATH, FileAccess.READ)
	if arquivo == null:
		return _mapa_oficial_cache
	var texto: String = arquivo.get_as_text()
	var json: JSON = JSON.new()
	if json.parse(texto) == OK and typeof(json.data) == TYPE_DICTIONARY:
		_mapa_oficial_cache = json.data
		_mapa_oficial_cache["_hash"] = texto.md5_text()
	return _mapa_oficial_cache


func _aplicar_mapa_oficial() -> void:
	# o mapa construido pelo dev vira parte da BASE de todo jogo real
	if builder_mode:
		return  # o construtor edita a base crua
	var dados: Dictionary = _carregar_mapa_oficial()
	if dados.is_empty() or str(dados.get("world_type", "normal")) != world_type:
		return
	voxel_world.apply_changes_as_base(dados.get("changes", []))
	voxel_world.import_metadata(dados.get("metadata", []))
	# muda a base -> entra no hash de compatibilidade dos saves
	active_terrain_hash += "|mapa:" + str(dados.get("_hash", ""))


# ---------------- modo criativo ----------------

func _toggle_creative_mode() -> void:
	creative_mode = not creative_mode
	_sync_creative_player()
	if creative_mode:
		_message("Modo criativo LIGADO: voo com espaco duplo, E abre todos os blocos, R marca area, F preenche.")
	else:
		_message("Modo criativo desligado.")


func _sync_creative_player() -> void:
	if player == null:
		return
	player.can_fly = creative_mode
	player.invulnerable = creative_mode
	if not creative_mode:
		player.creative_flight = false


func _create_creative_panel() -> void:
	creative_panel = PanelContainer.new()
	creative_panel.visible = false
	creative_panel.position = Vector2(215, 30)
	creative_panel.size = Vector2(850, 640)
	_apply_square_panel_style(creative_panel)
	ui_layer.add_child(creative_panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	creative_panel.add_child(root)

	var titulo: Label = Label.new()
	titulo.text = "Inventário Criativo"
	titulo.add_theme_font_size_override("font_size", 20)
	root.add_child(titulo)

	var dica: Label = Label.new()
	dica.text = "Clique pega 64 - clique direito pega 1 - Shift+clique manda pro inventário - clique com item na mão descarta."
	dica.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(dica)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(820, 340)
	root.add_child(scroll)
	creative_grid = GridContainer.new()
	creative_grid.columns = 9
	scroll.add_child(creative_grid)

	root.add_child(HSeparator.new())
	var inv_label: Label = Label.new()
	inv_label.text = "Inventário do Jogador"
	root.add_child(inv_label)
	creative_inv_grid = GridContainer.new()
	creative_inv_grid.columns = 9
	creative_inv_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(creative_inv_grid)


func _open_creative_panel() -> void:
	_return_craft_slots_to_inventory()
	inventory_panel.visible = false
	chest_panel.visible = false
	creative_panel.visible = true
	_update_creative_panel(true)
	_set_ui_mode(true)


func _update_creative_panel(rebuild_catalog: bool = false) -> void:
	if creative_panel == null or not creative_panel.visible:
		return
	if creative_items.is_empty():
		creative_items = item_defs.keys()
		creative_items.sort()
	if rebuild_catalog or creative_grid.get_child_count() == 0:
		_clear_children(creative_grid)
		for i in range(creative_items.size()):
			creative_grid.add_child(_make_item_slot("creative", i, {"item": str(creative_items[i]), "count": 1}, Vector2(78, 54)))
	_clear_children(creative_inv_grid)
	for i in range(inventory_slots.size()):
		creative_inv_grid.add_child(_make_item_slot("inventory", i, inventory_slots[i], Vector2(78, 54)))


# ---------------- importacao de schematics do Minecraft ----------------

func _abrir_dialogo_schematic() -> void:
	if not game_started:
		if pause_status_label != null:
			pause_status_label.text = "Entre num mundo antes de importar."
		return
	if schematic_dialog == null:
		_create_schematic_dialog()
	schematic_dialog.popup_centered(Vector2i(760, 520))


func _create_schematic_dialog() -> void:
	schematic_dialog = FileDialog.new()
	schematic_dialog.access = FileDialog.ACCESS_FILESYSTEM
	schematic_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	schematic_dialog.title = "Importar Schematic do Minecraft"
	schematic_dialog.filters = PackedStringArray([
		"*.schem ; Schematic (WorldEdit/Sponge)",
		"*.schematic ; Schematic (MCEdit legado)",
		"*.nbt ; Structure Block",
	])
	schematic_dialog.file_selected.connect(_on_schematic_selected)
	ui_layer.add_child(schematic_dialog)


func _on_schematic_selected(caminho: String) -> void:
	var resultado: Dictionary = SchematicImporterScript.importar(caminho, block_defs)
	if not bool(resultado.get("ok", false)):
		if pause_status_label != null:
			pause_status_label.text = str(resultado.get("erro", "Falha na importacao."))
		return
	var blocos: Dictionary = resultado.get("blocks", {})
	if blocos.size() > 500000:
		pause_status_label.text = "Schematic grande demais (%d blocos; maximo 500 mil)." % blocos.size()
		return
	if blocos.is_empty():
		pause_status_label.text = "Nenhum bloco compativel encontrado no schematic."
		return
	schematic_data = resultado
	schematic_rot = 0
	schematic_mode = true
	_limpar_selecao(false)
	_resume_game()
	var unmapped: Dictionary = resultado.get("unmapped", {})
	var aviso: String = "" if unmapped.is_empty() else " (%d tipos sem equivalente viram ar)" % unmapped.size()
	var tamanho: Vector3i = resultado.get("size", Vector3i.ONE)
	_message("Schematic %dx%dx%d carregado%s. Clique posiciona, R gira, ESC cancela." % [tamanho.x, tamanho.y, tamanho.z, aviso])


func _cancelar_schematic() -> void:
	schematic_mode = false
	schematic_data = {}
	if schematic_preview != null and is_instance_valid(schematic_preview):
		schematic_preview.queue_free()
	schematic_preview = null
	_message("Importacao de schematic encerrada.")


func _schematic_tamanho_girado() -> Vector3i:
	var s: Vector3i = schematic_data.get("size", Vector3i.ONE)
	return Vector3i(s.z, s.y, s.x) if schematic_rot % 2 == 1 else s


func _schematic_base() -> Vector3i:
	var hit = _get_target_block()
	if hit == null or not hit.is_valid():
		return Vector3i(-9999, -9999, -9999)
	var s: Vector3i = _schematic_tamanho_girado()
	# assenta em cima do bloco mirado, centralizado em X/Z
	return hit.pos + Vector3i(-int(s.x / 2.0), 1, -int(s.z / 2.0))


func _rot_schematic_pos(p: Vector3i, s: Vector3i) -> Vector3i:
	match schematic_rot:
		1: return Vector3i(s.z - 1 - p.z, p.y, p.x)
		2: return Vector3i(s.x - 1 - p.x, p.y, s.z - 1 - p.z)
		3: return Vector3i(p.z, p.y, s.x - 1 - p.x)
		_: return p


func _update_schematic_preview() -> void:
	if not schematic_mode:
		if schematic_preview != null and is_instance_valid(schematic_preview):
			schematic_preview.visible = false
		return
	var base: Vector3i = _schematic_base()
	if base.y < -9000:
		if schematic_preview != null and is_instance_valid(schematic_preview):
			schematic_preview.visible = false
		return
	if schematic_preview == null or not is_instance_valid(schematic_preview):
		schematic_preview = MeshInstance3D.new()
		var caixa: BoxMesh = BoxMesh.new()
		caixa.size = Vector3.ONE
		schematic_preview.mesh = caixa
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.2, 1.0, 0.4, 0.22)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		schematic_preview.material_override = mat
		world_root.add_child(schematic_preview)
	var s: Vector3i = _schematic_tamanho_girado()
	schematic_preview.visible = true
	schematic_preview.scale = Vector3(s)
	schematic_preview.position = Vector3(base) + Vector3(s) * 0.5 - Vector3(0.5, 0.5, 0.5)


func _estampar_schematic() -> void:
	var base: Vector3i = _schematic_base()
	if base.y < -9000:
		_message("Mire num bloco pra posicionar o schematic.")
		return
	var blocos: Dictionary = schematic_data.get("blocks", {})
	var s: Vector3i = schematic_data.get("size", Vector3i.ONE)
	var colocados: int = 0
	var fora: int = 0
	var minimo: Vector3i = Vector3i(999999, 999999, 999999)
	var maximo: Vector3i = Vector3i(-999999, -999999, -999999)
	for p in blocos:
		var wp: Vector3i = base + _rot_schematic_pos(p, s)
		# escrita RASTREADA (set_block): a construcao entra no save
		if voxel_world.set_block(wp, str(blocos[p])):
			colocados += 1
			minimo = minimo.min(wp)
			maximo = maximo.max(wp)
		else:
			fora += 1
	if colocados > 0:
		_queue_sections_aabb(minimo, maximo)
	var extra: String = "" if fora == 0 else " (%d fora do mapa)" % fora
	_message("Schematic aplicado: %d blocos%s. R gira, ESC encerra." % [colocados, extra])


# ---------------- ferramenta de area (marcar, preencher, destruir) ----------------

func _marcar_canto_selecao() -> void:
	var hit = _get_target_block()
	if hit == null or not hit.is_valid():
		_message("Mire num bloco pra marcar o canto (R).")
		return
	if sel_count == 0 or sel_count >= 2:
		sel_a = hit.pos
		sel_count = 1
		_message("Canto A em %s. Marque o canto B com R." % str(sel_a))
	else:
		sel_b = hit.pos
		sel_count = 2
		var t: Vector3i = (sel_b - sel_a).abs() + Vector3i.ONE
		_message("Área %d x %d x %d. F preenche com o item da mão (mão vazia destrói). X cancela." % [t.x, t.y, t.z])
	_update_selection_box()


func _limpar_selecao(avisar: bool) -> void:
	sel_count = 0
	if sel_box != null and is_instance_valid(sel_box):
		sel_box.visible = false
	if avisar:
		_message("Seleção de área limpa.")


func _update_selection_box() -> void:
	if sel_count == 0:
		if sel_box != null and is_instance_valid(sel_box):
			sel_box.visible = false
		return
	if sel_box == null or not is_instance_valid(sel_box):
		sel_box = MeshInstance3D.new()
		var caixa: BoxMesh = BoxMesh.new()
		caixa.size = Vector3.ONE
		sel_box.mesh = caixa
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.85, 0.2, 0.20)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		sel_box.material_override = mat
		world_root.add_child(sel_box)
	var b: Vector3i = sel_b if sel_count == 2 else sel_a
	var minimo: Vector3i = Vector3i(mini(sel_a.x, b.x), mini(sel_a.y, b.y), mini(sel_a.z, b.z))
	var maximo: Vector3i = Vector3i(maxi(sel_a.x, b.x), maxi(sel_a.y, b.y), maxi(sel_a.z, b.z))
	var tam: Vector3 = Vector3(maximo - minimo) + Vector3.ONE
	sel_box.visible = true
	sel_box.scale = tam + Vector3(0.04, 0.04, 0.04)
	sel_box.position = Vector3(minimo) + tam * 0.5 - Vector3(0.5, 0.5, 0.5)


func _preencher_selecao() -> void:
	if sel_count < 2:
		_message("Marque os dois cantos com R primeiro.")
		return
	if not creative_mode:
		_message("A ferramenta de área só funciona no modo criativo (F4).")
		return
	var minimo: Vector3i = Vector3i(mini(sel_a.x, sel_b.x), mini(sel_a.y, sel_b.y), mini(sel_a.z, sel_b.z))
	var maximo: Vector3i = Vector3i(maxi(sel_a.x, sel_b.x), maxi(sel_a.y, sel_b.y), maxi(sel_a.z, sel_b.z))
	var volume: int = (maximo.x - minimo.x + 1) * (maximo.y - minimo.y + 1) * (maximo.z - minimo.z + 1)
	if volume > 500000:
		_message("Área grande demais (%d blocos; máximo 500 mil)." % volume)
		return
	var selected_item: String = _get_selected_hotbar_item()
	var place_block: String = str((item_defs.get(selected_item, {}) as Dictionary).get("place_block", ""))
	var alterados: int = 0
	for y in range(minimo.y, maximo.y + 1):
		for z in range(minimo.z, maximo.z + 1):
			for x in range(minimo.x, maximo.x + 1):
				var pos: Vector3i = Vector3i(x, y, z)
				if place_block == "":
					if voxel_world.get_block_id(pos) == "chest":
						_erase_chest_inventory(pos)
					if voxel_world.remove_block(pos):
						alterados += 1
				else:
					if voxel_world.set_block(pos, place_block):
						alterados += 1
	_queue_sections_aabb(minimo, maximo)
	if place_block == "":
		_message("Área destruída: %d blocos removidos." % alterados)
	else:
		_message("Área preenchida com %s: %d blocos." % [_item_name(selected_item), alterados])
	_limpar_selecao(false)


# ---------------- blueprints multibloco (estilo Satisfactory) ----------------

func _salvar_selecao_como_blueprint() -> void:
	# DEV: captura a area selecionada (2 cantos) como molde de maquina
	if sel_count < 2:
		_message("Marque a área da máquina com R (2 cantos) antes de salvar o projeto (B).")
		return
	var minimo: Vector3i = Vector3i(mini(sel_a.x, sel_b.x), mini(sel_a.y, sel_b.y), mini(sel_a.z, sel_b.z))
	var maximo: Vector3i = Vector3i(maxi(sel_a.x, sel_b.x), maxi(sel_a.y, sel_b.y), maxi(sel_a.z, sel_b.z))
	DirAccess.make_dir_recursive_absolute(BLUEPRINT_DIR)
	var n: int = 1
	while FileAccess.file_exists(BLUEPRINT_DIR + "maquina_%d.json" % n):
		n += 1
	var nome: String = "Maquina %d" % n
	var bp = BlueprintDataScript.capturar(voxel_world, minimo, maximo, nome)
	if bp.blocks.is_empty():
		_message("A área selecionada está vazia — construa a máquina primeiro.")
		return
	if bp.save_to_file(BLUEPRINT_DIR + "maquina_%d.json" % n):
		_message("Projeto salvo: %s (%d blocos). Jogadores acham em F3." % [nome, bp.blocks.size()])
		_limpar_selecao(false)


func _toggle_blueprint_menu() -> void:
	if blueprint_menu == null:
		_create_blueprint_menu()
	if blueprint_menu.visible:
		blueprint_menu.visible = false
		_set_ui_mode(false)
	else:
		_preencher_blueprint_menu()
		blueprint_menu.visible = true
		_set_ui_mode(true)


func _create_blueprint_menu() -> void:
	blueprint_menu = PanelContainer.new()
	blueprint_menu.visible = false
	blueprint_menu.position = Vector2(360, 90)
	blueprint_menu.custom_minimum_size = Vector2(560, 420)
	_apply_square_panel_style(blueprint_menu)
	ui_layer.add_child(blueprint_menu)


func _preencher_blueprint_menu() -> void:
	_clear_children(blueprint_menu)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	blueprint_menu.add_child(root)
	var titulo: Label = Label.new()
	titulo.text = "Projetos de Máquina"
	titulo.add_theme_font_size_override("font_size", 20)
	root.add_child(titulo)
	var dica: Label = Label.new()
	dica.text = "Escolha um projeto, posicione o holograma (clique), gire com R, e entregue os materiais camada por camada com G."
	dica.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(dica)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 320)
	root.add_child(scroll)
	var lista: VBoxContainer = VBoxContainer.new()
	scroll.add_child(lista)
	var dir: DirAccess = DirAccess.open(BLUEPRINT_DIR)
	var achou: bool = false
	if dir != null:
		for arquivo in dir.get_files():
			if not arquivo.ends_with(".json"):
				continue
			var bp = BlueprintDataScript.load_from_file(BLUEPRINT_DIR + arquivo)
			if bp == null:
				continue
			achou = true
			var custo: Dictionary = bp.custo()
			var texto_custo: PackedStringArray = PackedStringArray()
			for id_bloco in custo:
				texto_custo.append("%dx %s" % [custo[id_bloco], _item_name(str((block_defs.get(id_bloco, {}) as Dictionary).get("drop", id_bloco)))])
			var botao: Button = _make_menu_button("%s  (%dx%dx%d)  —  %s" % [bp.display_name, bp.size.x, bp.size.y, bp.size.z, ", ".join(texto_custo)], func() -> void:
				_iniciar_blueprint(bp))
			lista.add_child(botao)
	if not achou:
		var vazio: Label = Label.new()
		vazio.text = "Nenhum projeto ainda. Um dev cria assim: modo criativo (F4), constrói a máquina, seleciona a área com R (2 cantos) e salva com B."
		vazio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lista.add_child(vazio)
	root.add_child(_make_menu_button("Fechar (F3)", _toggle_blueprint_menu))


func _iniciar_blueprint(bp) -> void:
	active_blueprint = bp
	bp_rot = 0
	blueprint_mode = true
	blueprint_menu.visible = false
	_set_ui_mode(false)
	_message("Posicione o holograma de %s: clique coloca a obra, R gira, ESC cancela." % bp.display_name)


func _cancelar_blueprint() -> void:
	blueprint_mode = false
	active_blueprint = null
	if bp_ghost != null and is_instance_valid(bp_ghost):
		bp_ghost.queue_free()
	bp_ghost = null
	_message("Colocação de projeto cancelada.")


func _blueprint_base() -> Vector3i:
	var hit = _get_target_block()
	if hit == null or not hit.is_valid() or active_blueprint == null:
		return Vector3i(-9999, -9999, -9999)
	var s: Vector3i = active_blueprint.size_rotacionado(bp_rot)
	return hit.pos + Vector3i(-int(s.x / 2.0), 1, -int(s.z / 2.0))


func _update_blueprint_preview() -> void:
	if not blueprint_mode or active_blueprint == null:
		if bp_ghost != null and is_instance_valid(bp_ghost):
			bp_ghost.visible = false
		return
	var base: Vector3i = _blueprint_base()
	if base.y < -9000:
		if bp_ghost != null and is_instance_valid(bp_ghost):
			bp_ghost.visible = false
		return
	if bp_ghost == null or not is_instance_valid(bp_ghost):
		bp_ghost = MeshInstance3D.new()
		bp_ghost.mesh = BoxMesh.new()
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.3, 0.7, 1.0, 0.22)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		bp_ghost.material_override = mat
		world_root.add_child(bp_ghost)
	var s: Vector3i = active_blueprint.size_rotacionado(bp_rot)
	bp_ghost.visible = true
	bp_ghost.scale = Vector3(s)
	bp_ghost.position = Vector3(base) + Vector3(s) * 0.5 - Vector3(0.5, 0.5, 0.5)


func _posicionar_obra() -> void:
	var base: Vector3i = _blueprint_base()
	if base.y < -9000:
		_message("Mire num bloco pra assentar a obra.")
		return
	var s: Vector3i = active_blueprint.size_rotacionado(bp_rot)
	# cria o canteiro de obras (holograma fantasma que enche conforme entrega material)
	var ghost: MeshInstance3D = MeshInstance3D.new()
	ghost.mesh = BoxMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.9, 0.75, 0.2, 0.16)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ghost.material_override = mat
	ghost.scale = Vector3(s)
	ghost.position = Vector3(base) + Vector3(s) * 0.5 - Vector3(0.5, 0.5, 0.5)
	world_root.add_child(ghost)
	construction_sites.append({"bp": active_blueprint, "base": base, "rot": bp_rot, "next_layer": 0, "ghost": ghost})
	blueprint_mode = false
	if bp_ghost != null and is_instance_valid(bp_ghost):
		bp_ghost.queue_free()
	bp_ghost = null
	_message("Canteiro de obras criado. Aproxime, segure o material e aperte G pra entregar cada camada.")


func _entregar_material_para_obra() -> void:
	# entrega a proxima camada da obra mais proxima (dentro de 8 blocos)
	if construction_sites.is_empty() or player == null:
		return
	var alvo: Dictionary = {}
	var melhor: float = 8.0
	for site in construction_sites:
		var s: Vector3i = site["bp"].size_rotacionado(site["rot"])
		var centro: Vector3 = Vector3(site["base"]) + Vector3(s) * 0.5
		var d: float = player.global_position.distance_to(centro)
		if d < melhor:
			melhor = d
			alvo = site
	if alvo.is_empty():
		_message("Chegue mais perto de um canteiro de obras (G).")
		return
	var bp = alvo["bp"]
	var camada: int = alvo["next_layer"]
	var custo: Dictionary = bp.custo_camada(camada)
	if custo.is_empty():
		# camada vazia, avanca de graca
		alvo["next_layer"] = camada + 1
		_pos_entrega(alvo)
		return
	# no criativo, entrega de graca; senao precisa dos itens no inventario
	if not creative_mode:
		for id_bloco in custo:
			var item_id: String = _item_para_bloco(id_bloco)
			if _item_total(item_id) < int(custo[id_bloco]):
				_message("Faltam materiais para a camada %d: %dx %s." % [camada + 1, custo[id_bloco], _item_name(item_id)])
				return
		for id_bloco in custo:
			_consumir_item(_item_para_bloco(id_bloco), int(custo[id_bloco]))
	# coloca os blocos da camada
	var minimo: Vector3i = Vector3i(999999, 999999, 999999)
	var maximo: Vector3i = Vector3i(-999999, -999999, -999999)
	for b in bp.blocos_camada_mundo(camada, alvo["base"], alvo["rot"]):
		if voxel_world.set_block(b["pos"], b["id"]):
			minimo = minimo.min(b["pos"])
			maximo = maximo.max(b["pos"])
	if maximo.x >= minimo.x:
		_queue_sections_aabb(minimo, maximo)
	alvo["next_layer"] = camada + 1
	_pos_entrega(alvo)


func _pos_entrega(site: Dictionary) -> void:
	var bp = site["bp"]
	if site["next_layer"] >= bp.size.y:
		# obra concluida
		if is_instance_valid(site["ghost"]):
			site["ghost"].queue_free()
		construction_sites.erase(site)
		var pts: int = bp.functional.size()
		_message("Máquina %s construída!%s" % [bp.display_name, (" %d pontos funcionais ativos." % pts) if pts > 0 else ""])
	else:
		# sobe o holograma pra mostrar o progresso
		var s: Vector3i = bp.size_rotacionado(site["rot"])
		var restante: int = bp.size.y - site["next_layer"]
		var g: MeshInstance3D = site["ghost"]
		g.scale = Vector3(s.x, restante, s.z)
		g.position = Vector3(site["base"]) + Vector3(s.x, 0, s.z) * 0.5 + Vector3(0, site["next_layer"] + restante * 0.5, 0) - Vector3(0.5, 0.5, 0.5)
		_message("Camada %d/%d entregue. Continue com G." % [site["next_layer"], bp.size.y])


func _item_para_bloco(block_id: String) -> String:
	var drop: String = str((block_defs.get(block_id, {}) as Dictionary).get("drop", ""))
	if drop != "" and item_defs.has(drop):
		return drop
	# procura um item que coloca esse bloco
	for item_id in item_defs:
		if str((item_defs[item_id] as Dictionary).get("place_block", "")) == block_id:
			return item_id
	return block_id


func _consumir_item(item_id: String, quantidade: int) -> void:
	var restante: int = quantidade
	for i in range(inventory_slots.size()):
		if restante <= 0:
			break
		if _slot_item(inventory_slots[i]) == item_id:
			var tira: int = mini(restante, _slot_count(inventory_slots[i]))
			_remove_from_slot(inventory_slots, i, tira)
			restante -= tira
	_update_all_ui()


func _queue_sections_aabb(minimo: Vector3i, maximo: Vector3i) -> void:
	if voxel_sections == null or voxel_world == null:
		return
	var secoes: Dictionary = {}
	var s0: Vector3i = voxel_world.get_section_coord(minimo - Vector3i.ONE)
	var s1: Vector3i = voxel_world.get_section_coord(maximo + Vector3i.ONE)
	for sy in range(s0.y, s1.y + 1):
		for sz in range(s0.z, s1.z + 1):
			for sx in range(s0.x, s1.x + 1):
				var sec: Vector3i = Vector3i(sx, sy, sz)
				if voxel_world.is_valid_section(sec):
					secoes[sec] = true
	voxel_sections.queue_sections(secoes.keys(), true)


func _load_scenery() -> void:
	# carrega TODOS os cenarios baked do Editor de Mapa como um objeto estatico fundido
	# (uma mesh + uma colisao por arquivo); o jogador so anda e colide, nao edita.
	if world_root == null:
		return
	var velho: Node = world_root.get_node_or_null("BakedScenery")
	if velho != null:
		velho.queue_free()
	var raiz: Node3D = Node3D.new()
	raiz.name = "BakedScenery"
	world_root.add_child(raiz)
	var dir: DirAccess = DirAccess.open(SCENERY_DIR)
	if dir == null:
		return
	for arquivo in dir.get_files():
		if not arquivo.ends_with(".json"):
			continue
		var cenario = SceneryDataScript.load_from_file(SCENERY_DIR + arquivo)
		if cenario == null or cenario.cubos.is_empty():
			continue
		var malha: MeshInstance3D = MeshInstance3D.new()
		malha.mesh = cenario.bake_mesh()
		malha.material_override = cenario.bake_material()
		raiz.add_child(malha)
		var corpo: StaticBody3D = StaticBody3D.new()
		var col: CollisionShape3D = CollisionShape3D.new()
		col.shape = cenario.bake_collision()
		corpo.add_child(col)
		raiz.add_child(corpo)


func _bounds_size() -> int:
	return voxel_world.unlocked_size if voxel_world != null else BIOME_SIZE


func _create_world_bounds() -> void:
	var s: int = _bounds_size()
	_add_world_wall(
		"WorldWall_West",
		Vector3(-1, BEDROCK_Y + WORLD_WALL_HEIGHT * 0.5, s * 0.5 - 0.5),
		Vector3(1, WORLD_WALL_HEIGHT, s + 2)
	)
	_add_world_wall(
		"WorldWall_East",
		Vector3(s, BEDROCK_Y + WORLD_WALL_HEIGHT * 0.5, s * 0.5 - 0.5),
		Vector3(1, WORLD_WALL_HEIGHT, s + 2)
	)
	_add_world_wall(
		"WorldWall_North",
		Vector3(s * 0.5 - 0.5, BEDROCK_Y + WORLD_WALL_HEIGHT * 0.5, -1),
		Vector3(s + 2, WORLD_WALL_HEIGHT, 1)
	)
	_add_world_wall(
		"WorldWall_South",
		Vector3(s * 0.5 - 0.5, BEDROCK_Y + WORLD_WALL_HEIGHT * 0.5, s),
		Vector3(s + 2, WORLD_WALL_HEIGHT, 1)
	)
	_add_world_ceiling()


func _rebuild_world_bounds() -> void:
	if world_root == null:
		return
	for nome in ["WorldWall_West", "WorldWall_East", "WorldWall_North", "WorldWall_South", "WorldSkyBoundary"]:
		var no: Node = world_root.get_node_or_null(nome)
		if no != null:
			no.queue_free()
	_create_world_bounds()

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


func _add_world_ceiling() -> void:
	# The top voxel layer is reserved for the later Skybreaker sequence.  It is
	# a single static bound rather than thousands of ceiling-block colliders.
	var s: int = _bounds_size()
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "WorldSkyBoundary"
	body.position = Vector3(s * 0.5 - 0.5, float(VoxelWorldScript.WORLD_MAX_Y) + 0.5, s * 0.5 - 0.5)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(s + 2, 1.0, s + 2)
	collision.shape = shape
	body.add_child(collision)
	world_root.add_child(body)

func _surface_y_at(x: int, z: int) -> int:
	if voxel_world != null:
		return voxel_world.get_surface_height(x, z, SURFACE_BASE_Y)
	var key: Vector2i = Vector2i(x, z)
	return int(surface_heights.get(key, SURFACE_BASE_Y))

func _create_player() -> void:
	player = TrumanPlayer.new()
	player.name = "Player"
	player.max_health = PLAYER_MAX_HEALTH
	player.health = pending_player_health
	player.position = Vector3(50.5, float(_surface_y_at(50, 50)) + 2.4, 50.5)
	add_child(player)
	player.health_changed.connect(_on_player_health_changed)
	player.died.connect(_on_player_died)
	player.set_camera_mode(saved_camera_mode)
	_apply_current_skin()
	_sync_held_item(true)
	_update_player_visual_visibility()

func _create_runtime_systems() -> void:
	light_registry = LightRegistryScript.new()
	light_registry.name = "LightRegistry"
	world_root.add_child(light_registry)
	light_registry.configure(voxel_world)
	entity_manager = EntityManagerScript.new()
	entity_manager.name = "EntityManager"
	world_root.add_child(entity_manager)
	var special_spawns: Array = last_generation_report.entity_spawns if last_generation_report != null else []
	entity_manager.configure(self, voxel_world, light_registry, special_spawns)
	if continue_on_load_finish:
		_load_thumbstones(loaded_game_data.get("thumbstones", []))

func can_spawn_entities() -> bool:
	return game_started and player != null and not player.dead and not _is_menu_open()

func is_night() -> bool:
	return time_of_day < 6.0 or time_of_day >= 18.0

func find_floor_y(position: Vector3, max_depth: int = 10) -> int:
	if voxel_world == null:
		return -999
	var x: int = floori(position.x + 0.5)
	var z: int = floori(position.z + 0.5)
	var start_y: int = mini(VoxelWorldScript.WORLD_MAX_Y, floori(position.y + 0.5))
	for y in range(start_y, maxi(VoxelWorldScript.WORLD_MIN_Y - 1, start_y - max_depth - 1), -1):
		if _is_solid_block_at(Vector3i(x, y, z)):
			return y
	return -999

func has_sky_access(pos: Vector3i) -> bool:
	if voxel_world == null:
		return false
	for y in range(pos.y, VoxelWorldScript.WORLD_MAX_Y + 1):
		if voxel_world.has_block(Vector3i(pos.x, y, pos.z)):
			return false
	return true

func is_rabbit_step_safe(from: Vector3, to: Vector3) -> bool:
	var current_floor: int = find_floor_y(from + Vector3.UP, 3)
	var next_floor: int = find_floor_y(to + Vector3.UP, 3)
	if current_floor <= -999 or next_floor <= -999 or abs(next_floor - current_floor) > 1:
		return false
	var next_cell := Vector3i(floori(to.x + 0.5), next_floor + 1, floori(to.z + 0.5))
	return has_sky_access(next_cell)

func is_spawn_position_visible(position: Vector3) -> bool:
	if player == null or player.camera == null or not player.camera.is_position_in_frustum(position):
		return false
	var query := PhysicsRayQueryParameters3D.create(player.get_interaction_ray_start(), position, 1)
	query.exclude = [player]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _on_player_health_changed(_current: float, _maximum: float) -> void:
	last_status_text = ""

func _on_player_died() -> void:
	call_deferred("_handle_player_death")

func _handle_player_death() -> void:
	if player == null or not player.dead:
		return
	var death_position: Vector3 = player.global_position
	var stone_position: Vector3 = _find_safe_thumbstone_position(death_position)
	var stone := ThumbstoneScript.new()
	stone.configure(self, str(Time.get_ticks_usec()), inventory_slots, stone_position)
	world_root.add_child(stone)
	thumbstones.append(stone)
	inventory_slots = _make_slots(INVENTORY_SLOT_COUNT)
	craft_slots = _make_slots(4)
	cursor_stack = _empty_slot()
	selected_hotbar_index = 0
	player.global_position = Vector3(50.5, float(_surface_y_at(50, 50)) + 2.4, 50.5)
	player.velocity = Vector3.ZERO
	player.restore_health()
	player.set_controls_enabled(true)
	_update_all_ui()
	_message("Voce morreu. Seus itens estao na thumbstone.")

func _find_safe_thumbstone_position(origin: Vector3) -> Vector3:
	for radius in range(0, 5):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var probe := origin + Vector3(dx, 3.0, dz)
				var floor_y: int = find_floor_y(probe, 14)
				if floor_y <= -999:
					continue
				var cell := Vector3i(floori(probe.x + 0.5), floor_y + 1, floori(probe.z + 0.5))
				if not voxel_world.has_block(cell) and not voxel_world.has_block(cell + Vector3i.UP):
					return Vector3(probe.x, floor_y + 0.5, probe.z)
	return Vector3(50.5, float(_surface_y_at(50, 50)) + 0.5, 50.5)

func collect_thumbstone(stone) -> void:
	if stone == null or not is_instance_valid(stone):
		return
	var remaining: Array = []
	for raw_slot in stone.contents:
		if typeof(raw_slot) != TYPE_DICTIONARY:
			continue
		var slot: Dictionary = raw_slot
		var item_id: String = _slot_item(slot)
		var count: int = _slot_count(slot)
		if item_id == "" or count <= 0:
			continue
		if not _inventory_can_accept(item_id) or not _add_item_to_slots(inventory_slots, item_id, count):
			remaining.append(slot.duplicate(true))
	stone.contents = remaining
	_update_all_ui()
	if remaining.is_empty():
		thumbstones.erase(stone)
		stone.queue_free()
		_message("Itens da thumbstone recuperados.")
	else:
		_message("Inventario cheio: o restante continua na thumbstone.")

func _inventory_can_accept(item_id: String) -> bool:
	for raw_slot in inventory_slots:
		var slot: Dictionary = raw_slot
		if _slot_item(slot) in ["", item_id]:
			return true
	return false

func _load_thumbstones(raw_value: Variant) -> void:
	if typeof(raw_value) != TYPE_ARRAY:
		return
	for raw_entry in raw_value as Array:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry
		var slots: Array = _slots_from_data(entry.get("contents", []), INVENTORY_SLOT_COUNT)
		var position: Vector3 = _vector3_from_data(entry.get("position", []), Vector3(50.5, float(_surface_y_at(50, 50)) + 0.5, 50.5))
		var stone := ThumbstoneScript.new()
		stone.configure(self, str(entry.get("id", Time.get_ticks_usec())), slots, position)
		world_root.add_child(stone)
		thumbstones.append(stone)

func _thumbstones_to_data() -> Array:
	var result: Array = []
	for stone in thumbstones:
		if is_instance_valid(stone) and not stone.is_queued_for_deletion():
			result.append(stone.to_data())
	return result

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
	_create_creative_panel()
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
	# painel estilo Minecraft: escuro translucido com contorno preto
	panel.add_theme_stylebox_override("panel", _make_square_box(Color(0.05, 0.05, 0.06, 0.84), Color(0.0, 0.0, 0.0, 0.9), 2, 16.0))

var _mc_style_cache: Dictionary = {}

func _mc_button_style(estado: String) -> StyleBoxTexture:
	# textura classica do botao do Minecraft: cinza pedra com bisel claro em cima,
	# escuro embaixo, contorno preto; hover azulado
	if _mc_style_cache.has(estado):
		return _mc_style_cache[estado]
	var w: int = 64
	var h: int = 20
	var base: Color
	match estado:
		"hover": base = Color(0.51, 0.55, 0.70)
		"pressed": base = Color(0.42, 0.46, 0.60)
		"disabled": base = Color(0.29, 0.29, 0.29)
		_: base = Color(0.475, 0.475, 0.475)
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var c: Color = base
			var ruido: float = float((x * 7 + y * 13) % 5) / 5.0 * 0.06 - 0.03
			c = Color(clampf(c.r + ruido, 0.0, 1.0), clampf(c.g + ruido, 0.0, 1.0), clampf(c.b + ruido, 0.0, 1.0))
			if y <= 1:
				c = c.lightened(0.35)
			elif y >= h - 3:
				c = c.darkened(0.30)
			img.set_pixel(x, y, c)
	for x in range(w):
		img.set_pixel(x, 0, Color.BLACK)
		img.set_pixel(x, h - 1, Color.BLACK)
	for y in range(h):
		img.set_pixel(0, y, Color.BLACK)
		img.set_pixel(w - 1, y, Color.BLACK)
	var sb: StyleBoxTexture = StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.texture_margin_left = 3
	sb.texture_margin_right = 3
	sb.texture_margin_top = 3
	sb.texture_margin_bottom = 3
	sb.set_content_margin(SIDE_LEFT, 10.0)
	sb.set_content_margin(SIDE_RIGHT, 10.0)
	sb.set_content_margin(SIDE_TOP, 6.0)
	sb.set_content_margin(SIDE_BOTTOM, 6.0)
	_mc_style_cache[estado] = sb
	return sb

func _apply_square_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _mc_button_style("normal"))
	button.add_theme_stylebox_override("hover", _mc_button_style("hover"))
	button.add_theme_stylebox_override("pressed", _mc_button_style("pressed"))
	button.add_theme_stylebox_override("disabled", _mc_button_style("disabled"))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.63))   # amarelo MC
	button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 0.63))
	button.add_theme_color_override("font_disabled_color", Color(0.63, 0.63, 0.63))
	button.add_theme_color_override("font_outline_color", Color(0.12, 0.12, 0.14))
	button.add_theme_constant_override("outline_size", 4)
	button.add_theme_font_size_override("font_size", 16)
	button.custom_minimum_size = Vector2(0, 40)

func _make_menu_button(text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	_apply_square_button_style(button)
	button.pressed.connect(callback)
	return button

func _create_menu_panels() -> void:
	main_menu_panel = _make_center_menu_panel(Vector2(420, 580))
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
	main_root.add_child(_make_menu_button("Novo Mundo Superplano (Criativo)", _start_new_flat_world))
	main_root.add_child(_make_menu_button("Construtor de Mundo", _show_builder_menu))
	main_root.add_child(_make_menu_button("Editor de Terreno", _open_terrain_editor))
	main_root.add_child(_make_menu_button("Editor de Mapa (Cidade)", _open_map_editor))
	main_root.add_child(_make_menu_button("Estudio de Estruturas", _open_structure_studio))
	main_root.add_child(_make_menu_button("Opcoes", _open_options_from_main))
	main_root.add_child(_make_menu_button("Sair", _quit_game))

	menu_status_label = Label.new()
	menu_status_label.text = ""
	menu_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_root.add_child(menu_status_label)

	pause_menu_panel = _make_center_menu_panel(Vector2(400, 640))
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
	publicar_button = _make_menu_button("Publicar Mapa p/ Jogadores", _publicar_do_pause)
	pause_root.add_child(publicar_button)
	pause_root.add_child(_make_menu_button("Importar Schematic (Minecraft)", _abrir_dialogo_schematic))

	flat_size_row = VBoxContainer.new()
	flat_size_row.add_theme_constant_override("separation", 4)
	var flat_label: Label = Label.new()
	flat_label.text = "Tamanho do mapa (superplano)"
	flat_size_row.add_child(flat_label)
	flat_size_value_label = Label.new()
	flat_size_value_label.text = "100 x 100"
	flat_size_row.add_child(flat_size_value_label)
	flat_size_slider = HSlider.new()
	flat_size_slider.min_value = 100
	flat_size_slider.max_value = 200
	flat_size_slider.step = 10
	flat_size_slider.value = 100
	flat_size_slider.value_changed.connect(func(v: float) -> void:
		flat_size_value_label.text = "%d x %d" % [int(v), int(v)])
	flat_size_row.add_child(flat_size_slider)
	flat_size_row.add_child(_make_menu_button("Aplicar tamanho", _aplicar_tamanho_flat))
	pause_root.add_child(flat_size_row)

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

	performance_preset_option = OptionButton.new()
	performance_preset_option.add_item("Qualidade alta", PerformanceProfileScript.Preset.HIGH)
	performance_preset_option.add_item("Desempenho 120 FPS", PerformanceProfileScript.Preset.PERFORMANCE)
	performance_preset_option.select(performance_preset)
	performance_preset_option.item_selected.connect(_on_performance_preset_selected)
	options_root.add_child(performance_preset_option)

	options_root.add_child(_make_menu_button("Importar skin", _open_skin_file_dialog))

	options_status_label = Label.new()
	options_status_label.text = ""
	options_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	options_root.add_child(options_status_label)

	options_root.add_child(_make_menu_button("Voltar", _close_options_panel))
	_create_skin_file_dialog()
	_create_builder_panels()
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
		or (builder_panel != null and builder_panel.visible)
		or (builder_create_panel != null and builder_create_panel.visible)
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
	if builder_panel != null:
		builder_panel.visible = false
	if builder_create_panel != null:
		builder_create_panel.visible = false
	if main_menu_panel != null:
		main_menu_panel.visible = true
	if continue_button != null:
		continue_button.disabled = not FileAccess.file_exists(SAVE_PATH) and not FileAccess.file_exists(V3_SAVE_PATH)
	if menu_status_label != null:
		var has_old_save: bool = FileAccess.file_exists(V2_SAVE_PATH) or FileAccess.file_exists(LEGACY_SAVE_PATH)
		menu_status_label.text = "Save V2/antigo preservado: a nova geracao usa mundos V4." if not FileAccess.file_exists(SAVE_PATH) and not FileAccess.file_exists(V3_SAVE_PATH) and has_old_save else ""
	_set_game_hud_visible(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if player != null:
		player.set_controls_enabled(false)

func _start_new_game() -> void:
	world_type = "normal"
	creative_mode = false
	builder_mode = false
	flat_size = 100
	_start_world_loading(false)


func _start_new_flat_world() -> void:
	world_type = "superflat"
	creative_mode = true
	builder_mode = false
	flat_size = 100
	_start_world_loading(false)


func _open_terrain_editor() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/terrain_editor.tscn")


func _open_map_editor() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/map_editor.tscn")


func _open_structure_studio() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/structure_studio.tscn")

func _continue_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH) and not FileAccess.file_exists(V3_SAVE_PATH):
		if menu_status_label != null:
			menu_status_label.text = "Nenhum save encontrado."
		return
	builder_mode = false
	_start_world_loading(true)

func _start_world_loading(is_continue: bool) -> void:
	continue_on_load_finish = is_continue
	game_started = false  # durante o load nao ha gameplay (evita input no mundo antigo)
	if is_continue:
		_peek_save_meta()  # tipo de mundo/tamanho precisam existir ANTES de gerar a base

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
	
	# Reset gameplay state.  The VoxelWorld owns all terrain data and section
	# state, so no per-block node or dictionary teardown is needed here.
	if voxel_world != null:
		voxel_world.set_tracking_changes(false)
	surface_heights.clear()
	_clear_chest_inventories()
	inventory_slots = _make_slots(INVENTORY_SLOT_COUNT)
	craft_slots = _make_slots(4)
	craft_size = 2
	craft_context = "inventory"
	selected_hotbar_index = 0
	pending_player_health = PLAYER_MAX_HEALTH
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
	left_click_consumed = false
	right_click_consumed = false
	loaded_game_data.clear()
	thumbstones.clear()
	light_registry = null
	entity_manager = null
	
	for item in dropped_items:
		if is_instance_valid(item):
			item.queue_free()
	dropped_items.clear()
	_clear_leaf_particles()
	breaking_pos = Vector3i(-999, -999, -999)
	breaking_progress = 0.0
	breaking_overlay = null
	_clear_target_outline()
	target_outline = null
	cached_target = null
	cached_target_physics_frame = -1
	schematic_mode = false
	schematic_data = {}
	schematic_rot = 0
	schematic_preview = null
	sel_count = 0
	sel_box = null

	if world_root != null and is_instance_valid(world_root):
		if voxel_sections != null:
			voxel_sections.shutdown()
		remove_child(world_root)
		world_root.queue_free()
		world_root = null
	voxel_sections = null
	voxel_debris = null
	if player != null and is_instance_valid(player):
		remove_child(player)
		player.queue_free()
		
	_create_world()

	# mundo do construtor: aplica as edicoes salvas COMO mudancas rastreadas
	# (continuam acumulando ao editar e salvar de novo)
	if builder_mode and not builder_pending.is_empty():
		voxel_world.import_changes(builder_pending.get("changes", []))
		voxel_world.import_metadata(builder_pending.get("metadata", []))
		builder_pending = {}

	if is_continue:
		if not _load_game_state():
			if menu_status_label != null:
				menu_status_label.text = last_load_error if last_load_error != "" else "Nao foi possivel carregar o save."
			_show_main_menu()
			if loading_panel != null:
				loading_panel.visible = false
			return
			
	if not is_continue and world_type == "normal" and not builder_mode:
		# bau inicial dentro da casa do jogador na cidade
		var spawn_surface_y: int = _surface_y_at(46, 45)
		var spawn_chest_pos: Vector3i = Vector3i(46, spawn_surface_y + 1, 45)
		_set_block(spawn_chest_pos, "chest")
		var spawn_chest_slots: Array = _make_slots(CHEST_SLOT_COUNT)
		_add_item_to_slots(spawn_chest_slots, "planks", 8)
		_add_item_to_slots(spawn_chest_slots, "coal", 4)
		_set_chest_inventory(spawn_chest_pos, spawn_chest_slots)

	if voxel_sections != null:
		voxel_sections.queue_rebuild_all(true)
	is_loading_world = true

func _finish_world_loading() -> void:
	is_loading_world = false
	if loading_panel != null:
		loading_panel.visible = false
		
	_create_world_bounds()
	_load_scenery()
	_apply_performance_profile()
	_create_player()
	_sync_creative_player()

	if continue_on_load_finish:
		if not loaded_game_data.is_empty():
			player.position = _vector3_from_data(loaded_game_data.get("player_position", []), player.position)
			player.set_view_angles(
				float(loaded_game_data.get("player_rotation_y", player.get_camera_yaw())),
				float(loaded_game_data.get("camera_pitch", player.get_camera_pitch()))
			)
	else:
		_give_start_items()
	_create_runtime_systems()
	
	if voxel_world != null:
		voxel_world.set_tracking_changes(true)
	_begin_gameplay()
	
	if continue_on_load_finish:
		_message("Save carregado.")
	else:
		_message("Novo jogo iniciado.")

func _begin_gameplay() -> void:
	game_started = true
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
	if creative_panel != null:
		creative_panel.visible = false
	if publicar_button != null:
		publicar_button.visible = builder_mode
	if flat_size_row != null:
		flat_size_row.visible = world_type == "superflat"
		if world_type == "superflat" and voxel_world != null:
			flat_size_slider.min_value = voxel_world.unlocked_size
			flat_size_slider.value = voxel_world.unlocked_size
			flat_size_value_label.text = "%d x %d" % [voxel_world.unlocked_size, voxel_world.unlocked_size]
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
	if performance_preset_option != null:
		performance_preset_option.select(performance_preset)
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
	if builder_mode:
		# no construtor, salvar grava o MUNDO (que pode virar o mapa dos jogadores)
		if _salvar_mundo_construtor():
			pause_status_label.text = "Mundo \"%s\" salvo no Construtor." % builder_world_name
		else:
			pause_status_label.text = "Nao foi possivel salvar o mundo."
		return
	if _save_game_state():
		if pause_status_label != null:
			pause_status_label.text = "Jogo salvo."
		if continue_button != null:
			continue_button.disabled = false
	else:
		if pause_status_label != null:
			pause_status_label.text = "Nao foi possivel salvar."


func _publicar_do_pause() -> void:
	if not builder_mode:
		pause_status_label.text = "So da pra publicar dentro do Construtor de Mundo."
		return
	if not _salvar_mundo_construtor():
		pause_status_label.text = "Falha ao salvar antes de publicar."
		return
	if _publicar_arquivo(BUILDER_DIR + builder_world_name.validate_filename() + ".json"):
		pause_status_label.text = "Publicado! Todo jogo novo dos jogadores usa este mapa."
	else:
		pause_status_label.text = "Falha ao publicar."

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
	if voxel_sections != null:
		voxel_sections.set_voxel_ao_enabled(enabled)
	_save_settings()


func _on_performance_preset_selected(index: int) -> void:
	performance_preset = index
	if performance_profile != null:
		performance_profile.set_preset(performance_preset)
	_apply_performance_profile()
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
	_apply_performance_profile()


func _apply_performance_profile() -> void:
	if performance_profile == null:
		return
	performance_profile.set_preset(performance_preset)
	var settings: Dictionary = performance_profile.apply_to(
		fog_env,
		sun_light,
		moon_light,
		voxel_sections
	)
	leaf_particle_limit = int(settings.get("leaf_particle_max", LEAF_PARTICLE_MAX))
	if voxel_debris != null:
		voxel_debris.set_capacity_limit(int(settings.get("voxel_debris_max", 256)))
	if voxel_sections != null:
		voxel_sections.configure_micro_foliage(
			int(settings.get("micro_foliage_density", 4)),
			float(settings.get("micro_foliage_distance", 80.0)),
			bool(settings.get("micro_foliage_shadows", true))
		)

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

func _set_block(pos: Vector3i, block_id: String):
	if voxel_world == null:
		return EditResultScript.rejected("world_unavailable", pos, block_id)
	if not voxel_world.is_buildable(pos):
		return EditResultScript.rejected("locked_or_out_of_bounds", pos, block_id)
	if not VoxelDependencyResolverScript.can_place(voxel_world, pos, block_id, block_defs):
		return EditResultScript.rejected("missing_solid_support", pos, block_id)
	if not voxel_world.set_block(pos, block_id):
		return EditResultScript.rejected("unchanged_or_unknown_block", pos, block_id)
	if block_id == "torch":
		voxel_world.set_metadata(pos, LightRegistryScript.METADATA_KEY, true)
		if light_registry != null:
			light_registry.register_torch(pos, false)
	_queue_voxel_sections_for_edit(pos)
	return EditResultScript.accepted(pos, block_id)

func _set_block_data(pos: Vector3i, block_id: String) -> void:
	if voxel_world != null:
		voxel_world.set_base_block(pos, block_id)

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

func _is_solid_block_at(pos: Vector3i) -> bool:
	return voxel_world != null and _is_solid_block_id(voxel_world.get_block_id(pos))

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

func _is_foliage_block_id(block_id: String) -> bool:
	if block_id == "" or block_id == "air" or not block_defs.has(block_id):
		return false
	var block_data: Dictionary = block_defs[block_id]
	return bool(block_data.get("foliage", false))

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

func _remove_block(pos: Vector3i):
	if voxel_world == null:
		return EditResultScript.rejected("world_unavailable", pos)
	var block_id: String = voxel_world.get_block_id(pos)
	if block_id == "":
		return EditResultScript.rejected("already_air", pos)
	var removal_positions: Array[Vector3i] = VoxelDependencyResolverScript.collect_removal_positions(voxel_world, pos, block_defs)
	var removed: Array = []
	var affected: Dictionary = {}
	for removal_pos in removal_positions:
		var removed_id: String = voxel_world.get_block_id(removal_pos)
		if not voxel_world.remove_block(removal_pos):
			if removal_pos == pos:
				return EditResultScript.rejected("locked_or_unbreakable", pos, block_id)
			continue
		if removed_id == "torch" and light_registry != null:
			light_registry.unregister_torch(removal_pos)
		removed.append({"pos": removal_pos, "block_id": removed_id})
		for section in voxel_world.get_affected_sections(removal_pos): affected[section] = true
	if removed.is_empty():
		return EditResultScript.rejected("locked_or_unbreakable", pos, block_id)
	if voxel_sections != null: voxel_sections.queue_sections(affected.keys(), true)
	cached_target_physics_frame = -1
	var result = EditResultScript.accepted(pos, block_id)
	result.removed_blocks = removed
	result.affected_sections = affected.keys()
	return result


func _queue_voxel_sections_for_edit(pos: Vector3i) -> void:
	if voxel_world == null or voxel_sections == null:
		return
	voxel_sections.queue_sections(voxel_world.get_affected_sections(pos), true)
	cached_target_physics_frame = -1

func _handle_block_breaking(delta: float) -> void:
	var hit = _get_target_block()
	if hit == null or not hit.is_valid():
		_cancel_block_breaking()
		return
	var pos: Vector3i = hit.pos
	var block_id: String = voxel_world.get_block_id(pos) if voxel_world != null else ""
	if block_id == "":
		_cancel_block_breaking()
		return
		
	var block_data: Dictionary = block_defs.get(block_id, {})
	if not bool(block_data.get("breakable", true)) and not creative_mode:
		_cancel_block_breaking()
		return

	if creative_mode:
		# criativo quebra instantaneo, igual Minecraft
		_complete_block_breaking(pos, hit.normal, block_id, block_data)
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
	if voxel_debris != null:
		voxel_debris.emit_mining(pos, hit.normal, block_id, delta)
	if player != null:
		player.play_mine_swing(breaking_progress)
	
	if breaking_progress >= 1.0:
		_complete_block_breaking(pos, hit.normal, block_id, block_data)

func _cancel_block_breaking() -> void:
	if voxel_debris != null:
		voxel_debris.stop_mining()
	if breaking_pos != Vector3i(-999, -999, -999):
		_clear_breaking_visuals()
		breaking_pos = Vector3i(-999, -999, -999)
		breaking_progress = 0.0

func _complete_block_breaking(pos: Vector3i, normal: Vector3i, block_id: String, block_data: Dictionary) -> void:
	_clear_breaking_visuals()
	if voxel_debris != null:
		voxel_debris.stop_mining()
	breaking_pos = Vector3i(-999, -999, -999)
	breaking_progress = 0.0
	
	var selected_item: String = _get_selected_hotbar_item()
	var uses_manita_pickaxe: bool = selected_item == "manita_pickaxe" and not creative_mode
	if uses_manita_pickaxe:
		if mana < MANITA_PICKAXE_MANA_COST:
			_message("Mana insuficiente para usar a Picareta de Manita.")
			return

	var edit = _remove_block(pos)
	if not bool(edit.succeeded):
		return
	if voxel_debris != null:
		voxel_debris.emit_burst(pos, normal, block_id)

	if uses_manita_pickaxe:
		mana -= MANITA_PICKAXE_MANA_COST
		manita_pickaxe_xp += 1
		if manita_pickaxe_xp >= manita_pickaxe_level * 10:
			manita_pickaxe_xp = 0
			manita_pickaxe_level += 1
			_message("Picareta de Manita subiu para nivel %s." % manita_pickaxe_level)

	var spawned_any_drop: bool = false
	for raw_removed in edit.removed_blocks:
		var removed: Dictionary = raw_removed as Dictionary
		var removed_pos: Vector3i = removed.get("pos", pos)
		var removed_id: String = str(removed.get("block_id", ""))
		var removed_data: Dictionary = block_defs.get(removed_id, {}) as Dictionary
		var drop_id: String = str(removed_data.get("drop", ""))
		if removed_id == "chest": _erase_chest_inventory(removed_pos)
		if drop_id != "" and not creative_mode:
			var spawn_pos: Vector3 = Vector3(removed_pos) + Vector3(0.0, 0.25, 0.0)
			var spawn_vel: Vector3 = Vector3(randf_range(-1.0, 1.0), 2.5, randf_range(-1.0, 1.0))
			_spawn_dropped_item(drop_id, 1, spawn_pos, spawn_vel)
			spawned_any_drop = true
	if player != null:
		player.play_break_finish()
	if spawned_any_drop or block_id == "chest" or selected_item == "manita_pickaxe":
		_update_all_ui()

func _create_breaking_visuals(pos: Vector3i) -> void:
	if breaking_overlay == null or not is_instance_valid(breaking_overlay):
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
	breaking_overlay.visible = true
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
		breaking_overlay.visible = false

func _update_target_outline() -> void:
	if not game_started or _is_menu_open() or inventory_panel.visible or chest_panel.visible:
		_clear_target_outline()
		return
	var hit = _get_target_block()
	if hit == null or not hit.is_valid():
		_clear_target_outline()
		return
	var pos: Vector3i = hit.pos
	if voxel_world == null or not voxel_world.has_block(pos):
		_clear_target_outline()
		return
	if target_outline != null and is_instance_valid(target_outline) and pos == target_outline_pos:
		return
	_create_target_outline(pos)

func _create_target_outline(pos: Vector3i) -> void:
	if target_outline == null or not is_instance_valid(target_outline):
		target_outline = MeshInstance3D.new()
		target_outline.mesh = _make_target_outline_mesh()
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color.BLACK
		target_outline.material_override = mat
		world_root.add_child(target_outline)
	target_outline.visible = true
	target_outline.position = Vector3(pos)
	target_outline_pos = pos

func _clear_target_outline() -> void:
	if target_outline != null and is_instance_valid(target_outline):
		target_outline.visible = false
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

func _interaction_physics_hit() -> Dictionary:
	if player == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(
		player.get_interaction_ray_start(),
		player.get_interaction_ray_end(),
		3
	)
	query.exclude = [player]
	return get_world_3d().direct_space_state.intersect_ray(query)

func _handle_primary_click() -> bool:
	var hit: Dictionary = _interaction_physics_hit()
	if hit.is_empty():
		return false
	var collider: Object = hit.get("collider")
	if collider is Node and (collider as Node).is_in_group("creature"):
		(collider as Node).take_damage(BlockCatalog.attack_damage(_get_selected_hotbar_item()))
		_cancel_block_breaking()
		player.play_attack_swing()
		return true
	if collider is Node and (collider as Node).is_in_group("thumbstone"):
		(collider as Node).collect()
		_cancel_block_breaking()
		player.play_attack_swing()
		return true
	return false

func _collect_target_thumbstone() -> bool:
	var hit: Dictionary = _interaction_physics_hit()
	if hit.is_empty():
		return false
	var collider: Object = hit.get("collider")
	if collider is Node and (collider as Node).is_in_group("thumbstone"):
		(collider as Node).collect()
		player.play_place_swing()
		return true
	return false

func _collect_nearby_thumbstone() -> bool:
	if player == null:
		return false
	var nearest: Node = null
	var nearest_distance: float = 2.0
	for raw_stone in thumbstones:
		if not is_instance_valid(raw_stone):
			continue
		var stone: Node = raw_stone
		var distance: float = player.global_position.distance_to(stone.global_position + Vector3.UP * 0.6)
		if distance < nearest_distance:
			nearest = stone
			nearest_distance = distance
	if nearest == null:
		return false
	nearest.collect()
	return true

func _use_or_place_target() -> bool:
	var hit = _get_target_block()
	if hit == null or not hit.is_valid():
		return false

	var pos: Vector3i = hit.pos
	var block_id: String = voxel_world.get_block_id(pos) if voxel_world != null else ""
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

	var normal: Vector3 = Vector3(hit.normal)
	var offset: Vector3i = Vector3i(int(round(normal.x)), int(round(normal.y)), int(round(normal.z)))
	var target_pos: Vector3i = pos + offset
	if place_block == "":
		_message("Item selecionado nao pode ser colocado.")
		return false
	if voxel_world == null or voxel_world.has_block(target_pos):
		return false
	if voxel_world == null or not voxel_world.is_buildable(target_pos):
		_message("Este MVP esta limitado ao Bioma 1 de 100x100.")
		return false
	if _would_block_player(target_pos):
		_message("Nao da para colocar bloco dentro do jogador.")
		return false
	if not creative_mode and _slot_count(inventory_slots[selected_hotbar_index]) <= 0:
		_message("Sem %s no slot selecionado." % _item_name(selected_item))
		return false

	var edit = _set_block(target_pos, place_block)
	if not bool(edit.succeeded):
		if str(edit.reason) == "missing_solid_support": _message("Plantas precisam de um bloco solido abaixo.")
		return false
	if not creative_mode:
		_remove_from_slot(inventory_slots, selected_hotbar_index, 1)
	if place_block == "chest":
		_set_chest_inventory(target_pos, _make_slots(CHEST_SLOT_COUNT))
	if player != null:
		player.play_place_swing()
	_update_all_ui()
	return true

func _get_target_block():
	return cached_target


func _update_cached_target() -> void:
	if player == null or voxel_world == null:
		cached_target = null
		return
	var physics_frame: int = Engine.get_physics_frames()
	if cached_target_physics_frame == physics_frame:
		return
	cached_target_physics_frame = physics_frame
	cached_target = voxel_world.raycast_hit(
		player.get_interaction_ray_start(),
		player.get_aim_direction(),
		player.block_reach
	)

func _is_inside_current_biome(pos: Vector3i) -> bool:
	return voxel_world != null and voxel_world.is_inside_unlocked_biome(pos)

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
	if not _has_chest_inventory(pos):
		_set_chest_inventory(pos, _make_slots(CHEST_SLOT_COUNT))
	chest_panel.visible = true
	inventory_panel.visible = false
	_update_chest_panel()
	_set_ui_mode(true)

func _close_all_panels() -> void:
	_return_craft_slots_to_inventory()
	inventory_panel.visible = false
	chest_panel.visible = false
	if creative_panel != null:
		creative_panel.visible = false
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
	if slot_type == "creative":
		# clique pega um stack de 64; com item na mao, descarta (lixeira do criativo)
		if _slot_item(cursor_stack) == "":
			cursor_stack = {"item": str(creative_items[slot_index]), "count": 64}
		else:
			cursor_stack = _empty_slot()
		_update_all_ui()
		_update_cursor_stack_label()
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
	if slot_type == "creative":
		# clique direito pega 1 (ou incrementa se ja segura o mesmo item)
		var id_criativo: String = str(creative_items[slot_index])
		if _slot_item(cursor_stack) == "":
			cursor_stack = {"item": id_criativo, "count": 1}
		elif _slot_item(cursor_stack) == id_criativo:
			cursor_stack["count"] = mini(64, _slot_count(cursor_stack) + 1)
		_update_all_ui()
		_update_cursor_stack_label()
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
	if slot_type == "craft_output" or slot_type == "creative":
		return false
	if _slot_item(cursor_stack) == "" or not _is_valid_slot(slot_type, slot_index):
		return false
	var slot: Dictionary = _get_slot(slot_type, slot_index)
	return _slot_item(slot) == "" or _slot_item(slot) == _slot_item(cursor_stack)

func _slot_key(slot_type: String, slot_index: int) -> String:
	return "%s:%s" % [slot_type, slot_index]

func _is_valid_slot(slot_type: String, slot_index: int) -> bool:
	if slot_type == "creative":
		return slot_index >= 0 and slot_index < creative_items.size()
	if slot_type == "craft_output":
		return slot_index == 0 and _slot_item(_current_craft_output_slot()) != ""
	var slots: Array = _get_slots_for_type(slot_type)
	return slot_index >= 0 and slot_index < slots.size()

func _get_slot(slot_type: String, slot_index: int) -> Dictionary:
	if slot_type == "creative":
		if slot_index >= 0 and slot_index < creative_items.size():
			return {"item": str(creative_items[slot_index]), "count": 64}
		return _empty_slot()
	if slot_type == "craft_output":
		return _current_craft_output_slot()
	var slots: Array = _get_slots_for_type(slot_type)
	if slot_index < 0 or slot_index >= slots.size():
		return _empty_slot()
	var slot: Dictionary = slots[slot_index]
	return slot

func _set_slot(slot_type: String, slot_index: int, slot: Dictionary) -> void:
	if slot_type == "craft_output" or slot_type == "creative":
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
			if has_current_chest and _has_chest_inventory(current_chest_pos):
				return _get_chest_inventory(current_chest_pos)
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
				_set_chest_inventory(current_chest_pos, slots)

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
	if slot_type == "creative":
		if _is_valid_slot("creative", slot_index):
			_add_item(str(creative_items[slot_index]), 64)
			_update_all_ui()
		return
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
	if not game_started or voxel_world == null:
		return false
	_return_cursor_stack_to_inventory()
	_return_craft_slots_to_inventory()
	_cancel_slot_drags()

	var save_data: Dictionary = {
		"format": "trumancraft_save_v4",
		"version": 4,
		"terrain_hash": active_terrain_hash,
		"structure_registry_hash": active_registry_hash,
		"world": voxel_world.build_save_data(),
		"player_position": _vector3_to_array(player.global_position),
		"player_rotation_y": player.get_camera_yaw(),
		"camera_pitch": player.get_camera_pitch(),
		"inventory_slots": inventory_slots,
		"player_health": player.health,
		"thumbstones": _thumbstones_to_data(),
		"selected_hotbar_index": selected_hotbar_index,
		"mana": mana,
		"manita_pickaxe_xp": manita_pickaxe_xp,
		"manita_pickaxe_level": manita_pickaxe_level,
		"time_of_day": time_of_day,
		"day_count": day_count,
		"world_type": world_type,
		"flat_size": voxel_world.unlocked_size,
		"flat_surface_y": flat_surface_y,
		"creative_mode": creative_mode
	}

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(save_data, "\t"))
	return true

func _load_game_state() -> bool:
	last_load_error = ""
	if voxel_world == null:
		last_load_error = "O mundo base V3 nao foi inicializado."
		return false
	var load_path: String = SAVE_PATH if FileAccess.file_exists(SAVE_PATH) else V3_SAVE_PATH
	var file: FileAccess = FileAccess.open(load_path, FileAccess.READ)
	if file == null:
		last_load_error = "Nao foi possivel abrir o save."
		return false
	var text: String = file.get_as_text()
	var json: JSON = JSON.new()
	var parse_error: int = json.parse(text)
	if parse_error != OK:
		last_load_error = "O arquivo de save esta corrompido."
		return false

	var raw_data: Variant = json.data
	if typeof(raw_data) != TYPE_DICTIONARY:
		last_load_error = "O save nao contem um objeto valido."
		return false
	var data: Dictionary = raw_data as Dictionary
	var format: String = str(data.get("format", ""))
	var version: int = int(data.get("version", 0))
	if not ((format == "trumancraft_save_v4" and version == 4) or (format == "trumancraft_save_v3" and version == 3)):
		last_load_error = "Save incompativel: somente mundos V3 ou V4 podem ser carregados."
		return false
	if str(data.get("terrain_hash", "")) != active_terrain_hash or str(data.get("structure_registry_hash", "")) != active_registry_hash:
		last_load_error = "Save incompativel com os tiles ou templates de geracao atuais."
		return false
	var raw_world: Variant = data.get("world", {})
	if typeof(raw_world) != TYPE_DICTIONARY or not voxel_world.load_save_data(raw_world as Dictionary):
		last_load_error = "Dados voxel do save sao invalidos ou usam outra paleta."
		return false

	voxel_world.set_tracking_changes(false)

	inventory_slots = _slots_from_data(data.get("inventory_slots", []), INVENTORY_SLOT_COUNT)
	pending_player_health = clampf(float(data.get("player_health", PLAYER_MAX_HEALTH)), 0.01, PLAYER_MAX_HEALTH)
	craft_slots = _make_slots(4)
	cursor_stack = _empty_slot()
	selected_hotbar_index = clamp(int(data.get("selected_hotbar_index", 0)), 0, HOTBAR_SLOT_COUNT - 1)
	mana = clamp(float(data.get("mana", MANA_MAX)), 0.0, MANA_MAX)
	manita_pickaxe_xp = max(0, int(data.get("manita_pickaxe_xp", 0)))
	manita_pickaxe_level = max(1, int(data.get("manita_pickaxe_level", 1)))
	time_of_day = clamp(float(data.get("time_of_day", 8.0)), 0.0, 24.0)
	day_count = max(1, int(data.get("day_count", 1)))
	creative_mode = bool(data.get("creative_mode", false))
	for raw_pos in voxel_world.get_metadata_positions(CHEST_METADATA_KEY):
		var chest_pos: Vector3i = raw_pos
		if voxel_world.get_block_id(chest_pos) == "chest":
			_set_chest_inventory(chest_pos, _slots_from_data(_get_chest_inventory(chest_pos), CHEST_SLOT_COUNT))
		else:
			_erase_chest_inventory(chest_pos)

	loaded_game_data = data

	voxel_world.set_tracking_changes(false)
	_update_all_ui()
	return true

func _load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		fullscreen_enabled = bool(config.get_value("video", "fullscreen", false))
		shadows_enabled = bool(config.get_value("video", "shadows", true))
		ssao_enabled = bool(config.get_value("video", "ssao", true))
		voxel_ao_enabled = bool(config.get_value("video", "voxel_ao", true))
		performance_preset = PerformanceProfileScript.preset_from_value(config.get_value("video", "performance_preset", "high"))
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
	config.set_value("video", "performance_preset", PerformanceProfileScript.preset_name(performance_preset))
	config.set_value("player", "skin_path", player_skin_path)
	config.set_value("player", "camera_mode", saved_camera_mode)
	config.save(SETTINGS_PATH)

func _clear_chest_inventories() -> void:
	if voxel_world != null:
		voxel_world.clear_metadata(CHEST_METADATA_KEY)


func _has_chest_inventory(pos: Vector3i) -> bool:
	return voxel_world != null and voxel_world.has_metadata(pos, CHEST_METADATA_KEY)


func _get_chest_inventory(pos: Vector3i) -> Array:
	if voxel_world == null:
		return []
	var raw_slots: Variant = voxel_world.get_metadata(pos, CHEST_METADATA_KEY, [])
	return raw_slots as Array if typeof(raw_slots) == TYPE_ARRAY else []


func _set_chest_inventory(pos: Vector3i, slots: Array) -> void:
	if voxel_world != null:
		voxel_world.set_metadata(pos, CHEST_METADATA_KEY, slots)


func _erase_chest_inventory(pos: Vector3i) -> void:
	if voxel_world != null:
		voxel_world.erase_metadata(pos, CHEST_METADATA_KEY)

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
	if creative_panel != null and creative_panel.visible:
		_update_creative_panel()
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
	var current_health: float = player.health if player != null else pending_player_health
	var next_text: String = "Bioma 1/4: Inicio 100x100 | Vida: %s/%s\nMana: %s/%s | Picareta Manita Nv.%s XP %s/%s\nSelecionado: %s x%s | E: craft 2x2 | F5: camera" % [
		current_health,
		PLAYER_MAX_HEALTH,
		int(mana),
		int(MANA_MAX),
		manita_pickaxe_level,
		manita_pickaxe_xp,
		manita_pickaxe_level * 10,
		selected_name,
		_get_selected_hotbar_count()
	]
	if next_text == last_status_text:
		return
	last_status_text = next_text
	status_label.text = next_text

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
	if hotbar_box == null:
		return
	if hotbar_slots.size() != HOTBAR_SLOT_COUNT:
		_clear_children(hotbar_box)
		hotbar_slots.clear()
		for slot_index in range(HOTBAR_SLOT_COUNT):
			var created_slot: ItemSlot = ItemSlot.new()
			hotbar_box.add_child(created_slot)
			hotbar_slots.append(created_slot)
	for i in range(HOTBAR_SLOT_COUNT):
		var slot: Dictionary = inventory_slots[i]
		var slot_node: ItemSlot = hotbar_slots[i]
		var item_id: String = _slot_item(slot)
		slot_node.configure(
			self,
			"inventory",
			i,
			item_id,
			_slot_count(slot),
			_item_name(item_id),
			_item_description(item_id),
			_item_icon(item_id),
			_item_icon_faces(item_id),
			Vector2(54, 54)
		)
		slot_node.set_selected(i == selected_hotbar_index)
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


## Records a repeatable 30-second interactive route. Start at the Biome 1
## spawn, press F9, then sprint, rotate the camera, mine, and place blocks as
## usual. A second F9 ends it early and reports p95/p99 frame time.
func _toggle_frame_benchmark() -> void:
	if not game_started:
		return
	if benchmark_active:
		_finish_frame_benchmark()
		return
	benchmark_active = true
	benchmark_elapsed = 0.0
	benchmark_samples_ms.clear()
	_message("Benchmark iniciado: corra, gire a camera, minere e coloque blocos por 30 segundos.")


func _update_frame_benchmark(delta: float) -> void:
	if not benchmark_active:
		return
	benchmark_elapsed += delta
	benchmark_samples_ms.append(delta * 1000.0)
	if benchmark_elapsed >= BENCHMARK_DURATION_SECONDS:
		_finish_frame_benchmark()


func _finish_frame_benchmark() -> void:
	if not benchmark_active:
		return
	benchmark_active = false
	if benchmark_samples_ms.is_empty():
		_message("Benchmark sem amostras.")
		return
	var ordered: Array[float] = benchmark_samples_ms.duplicate()
	ordered.sort()
	var p95: float = ordered[clampi(int(floor(float(ordered.size() - 1) * 0.95)), 0, ordered.size() - 1)]
	var p99: float = ordered[clampi(int(floor(float(ordered.size() - 1) * 0.99)), 0, ordered.size() - 1)]
	_message("Benchmark: p95 %.2f ms | p99 %.2f ms | alvo 120 FPS: 8.33 ms." % [p95, p99])
