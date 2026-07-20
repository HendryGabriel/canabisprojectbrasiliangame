extends "res://src/authoring_scene_base.gd"

const WorkspaceScript = preload("res://src/structure_workspace.gd")
const StructureTemplateScript = preload("res://src/structure_template_data.gd")
const HistoryScript = preload("res://src/authoring_history.gd")
const PlayerScript = preload("res://src/player.gd")
const VoxelDependencyResolverScript = preload("res://src/voxel_dependency_resolver.gd")
const VoxelDebrisSystemScript = preload("res://src/voxel_debris_system.gd")
const SpawnGraphScript = preload("res://src/structure_spawn_graph.gd")
const StructureRegistryScript = preload("res://src/structure_registry.gd")
const TerrainTileScript = preload("res://src/terrain_tile_data.gd")
const TerrainGeneratorScript = preload("res://src/terrain_generator.gd")
const VoxelWorldScript = preload("res://src/voxel_world.gd")
const UIStyleScript = preload("res://src/ui_style.gd")
const MicroCellScript = preload("res://src/micro_cell_data.gd")
const VoxelSectionMesherScript = preload("res://src/voxel_section_mesher.gd")
const PlacedAssetSystemScript = preload("res://src/placed_asset_system.gd")

const AUTOSAVE_PATH: String = "user://authoring/structure_autosave.tstructure.json"
const PATTERN_PATH: String = "user://authoring/structure_pattern_clipboard.json"
const PREVIEW_PATH: String = "user://authoring/structure_preview.tstructure.json"
const PROJECT_STRUCTURE_DIR: String = "res://data/structures"
const DEFAULT_TILE_PATH: String = "res://data/terrain/biome_1.tterrain.json"
const GUIDE_POS: Vector3i = Vector3i(32, 0, 32)
const DOUBLE_SPACE_MS: int = 320

var workspace
var history
var tool_option: OptionButton
var block_option: OptionButton
var block_search_edit: LineEdit
var template_id_edit: LineEdit
var template_name_edit: LineEdit
var asset_kind_option: OptionButton
var placement_mode_option: OptionButton
var utility_id_edit: LineEdit
var selection_a: Vector3i = Vector3i(20, 1, 20)
var selection_b: Vector3i = Vector3i(43, 24, 43)
var clipboard_template = null
var export_dialog: FileDialog
var load_dialog: FileDialog
var marker_root: Node3D
var advanced_panel: Control
var radial_panel: Control
var voxel_size_option: OptionButton
var active_tool_label: Label
var creative_inventory_panel: Control
var creative_grid: GridContainer
var creative_search: LineEdit
var creative_category: OptionButton
var creative_visible_blocks: Array[String] = []
var hotbar_root: HBoxContainer
var hotbar_blocks: Array[String] = []
var hotbar_buttons: Array[ItemSlot] = []
var hotbar_patterns: Dictionary = {}
var selected_hotbar: int = 0
var crosshair: Label
var studio_player
var autosave_elapsed: float = 0.0
var voxel_debris
var spawn_profiles: Array = []
var graph_panel: PanelContainer
var graph_edit: GraphEdit
var graph_profile_option: OptionButton
var graph_node_type_option: OptionButton
var graph_inspector: VBoxContainer
var selected_graph_node_id: String = ""
var biome_preview_world
var biome_preview_sections
var biome_preview_active: bool = false
var last_preview_report = null
var studio_transform_before_preview: Transform3D
var preview_refresh_pending: bool = false
var preview_refresh_elapsed: float = 0.0
var guide_active: bool = false
var last_space_press_ms: int = -1000
var studio_ui_theme: Theme
var active_tool: String = "hand"
var micro_edge: int = 8
var pattern_clipboard = null
var pattern_stamp_active: bool = false
var pattern_mesh_cache: Dictionary = {}
var placement_outline: MeshInstance3D
var brush_radius: int = 1
var project_asset_registry
var studio_asset_system
var studio_asset_rotation: int = 0


func _ready() -> void:
	right_mouse_toggles_capture = false
	free_camera_controls_enabled = false
	_ensure_input_actions()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://authoring"))
	workspace = WorkspaceScript.new(BlockCatalogScript.blocks())
	_reload_project_assets()
	history = HistoryScript.new()
	workspace.pivot = GUIDE_POS
	var autosave = StructureTemplateScript.load_from_file(AUTOSAVE_PATH)
	if autosave != null:
		_strip_legacy_autosave_floor(autosave)
		workspace.load_template(autosave, Vector3i(0, 1, 0))
		_materialize_workspace_components()
		selection_a = Vector3i(0, 1, 0)
		selection_b = Vector3i(0, 1, 0) + autosave.size - Vector3i.ONE
		spawn_profiles = autosave.spawn_profiles.duplicate(true)
		if _template_content_is_empty(autosave): _create_guide_block()
	else:
		_create_guide_block()
	if spawn_profiles.is_empty():
		spawn_profiles = [SpawnGraphScript.default_profile(Vector2i.ZERO)]
	setup_authoring_world(workspace, Vector3(32, 8, 52))
	studio_ui_theme = UIStyleScript.make_theme()
	voxel_debris = VoxelDebrisSystemScript.new()
	voxel_debris.name = "VoxelDebris"
	add_child(voxel_debris)
	voxel_debris.configure(BlockCatalogScript.blocks(), 256)
	_create_gameplay_player()
	marker_root = Node3D.new()
	marker_root.name = "StudioMarkers"
	add_child(marker_root)
	_create_placement_outline()
	_build_ui()
	_build_creative_ui()
	_build_graph_ui()
	_load_pattern_clipboard()
	_rebuild_markers()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	set_status("Estudio: gameplay normal; Espaco duplo alterna voo; E inventario; Tab ferramentas; G grafo.")


func _create_guide_block() -> void:
	workspace.set_block(GUIDE_POS, "stone")
	workspace.pivot = GUIDE_POS
	selection_a = GUIDE_POS
	selection_b = GUIDE_POS
	guide_active = true


func _template_content_is_empty(template) -> bool:
	return template.blocks.is_empty() and template.micro_cells.is_empty() and template.explicit_air.is_empty() and template.metadata.is_empty() and template.markers.is_empty() and template.components.is_empty()


func _strip_legacy_autosave_floor(template) -> void:
	if template.size.x != WorkspaceScript.SIZE or template.size.z != WorkspaceScript.SIZE: return
	for z in range(WorkspaceScript.SIZE):
		for x in range(WorkspaceScript.SIZE):
			if str(template.blocks.get(Vector3i(x, 0, z), "")) != "grass": return
	for z in range(WorkspaceScript.SIZE):
		for x in range(WorkspaceScript.SIZE): template.blocks.erase(Vector3i(x, 0, z))


func _deactivate_guide_for_changes(changes: Array) -> void:
	if not guide_active: return
	for raw_change in changes:
		if (raw_change as Dictionary).get("pos", Vector3i(-1, -1, -1)) == GUIDE_POS:
			guide_active = false
			_rebuild_markers()
			return


func _strip_guide_from_template(template) -> void:
	if not guide_active: return
	var local_pos: Vector3i = GUIDE_POS - _selection_min()
	if template.is_inside(local_pos): template.blocks.erase(local_pos)


func _include_authored_position(pos: Vector3i) -> void:
	var minimum: Vector3i = _selection_min()
	var maximum: Vector3i = _selection_max()
	selection_a = Vector3i(mini(minimum.x, pos.x), mini(minimum.y, pos.y), mini(minimum.z, pos.z))
	selection_b = Vector3i(maxi(maximum.x, pos.x), maxi(maximum.y, pos.y), maxi(maximum.z, pos.z))


func _create_gameplay_player() -> void:
	if camera != null:
		camera.current = false
		camera.queue_free()
	studio_player = PlayerScript.new()
	studio_player.name = "CreativePlayer"
	studio_player.creative_flight = false
	studio_player.creative_flight_speed = 12.0
	studio_player.position = Vector3(GUIDE_POS) + Vector3(0, 2.5, 0)
	add_child(studio_player)
	studio_player.set_camera_mode(0)
	studio_player.set_view_angles(0.0, deg_to_rad(-24.0))
	studio_player.set_visuals_visible(true)
	camera = studio_player.camera


func _process(delta: float) -> void:
	super._process(delta)
	if texture_array != null and studio_player != null:
		texture_array.update_micro_foliage(studio_player.global_position, studio_player.velocity)
	if voxel_debris != null:
		voxel_debris.update_particles(delta, workspace)
	if studio_player != null and studio_player.global_position.y < -8.0:
		studio_player.global_position = Vector3(GUIDE_POS) + Vector3(0, 2.5, 0)
		studio_player.velocity = Vector3.ZERO
		studio_player.creative_flight = true
		set_status("Voce caiu no void. Reposicionado no centro com voo ativo.")
	if biome_preview_sections != null:
		biome_preview_sections.process_updates(false)
	if preview_refresh_pending and biome_preview_active:
		preview_refresh_elapsed += delta
		if preview_refresh_elapsed >= 0.45:
			preview_refresh_pending = false
			_refresh_biome_preview(false)
	_update_placement_outline()
	autosave_elapsed += delta
	if autosave_elapsed >= 20.0:
		autosave_elapsed = 0.0
		_autosave()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and active_tool in ["wand", "forms", "brush", "replace", "clone", "marks"] and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			selection_b = selection_a; _rebuild_markers(); set_status("Preview de area cancelado."); get_viewport().set_input_as_handled(); return
		if event.keycode == KEY_ESCAPE and studio_player != null:
			studio_player.set_controls_enabled(false)
		if event.keycode == KEY_E:
			_toggle_creative_inventory(); get_viewport().set_input_as_handled(); return
		if event.keycode == KEY_TAB:
			_toggle_tool_wheel(); get_viewport().set_input_as_handled(); return
		if event.keycode == KEY_G:
			_toggle_graph_editor(); get_viewport().set_input_as_handled(); return
		if event.keycode == KEY_R and _selected_project_asset() != null:
			studio_asset_rotation = posmod(studio_asset_rotation + 1, 4)
			set_status("Rotacao do asset: %d graus." % (studio_asset_rotation * 90)); return
		if event.keycode == KEY_SPACE and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and studio_player != null and studio_player.controls_enabled:
			_handle_double_space()
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			_select_hotbar(int(event.keycode - KEY_1)); return
		if event.ctrl_pressed and event.keycode == KEY_Z: _undo(); return
		if event.ctrl_pressed and event.keycode == KEY_Y: _redo(); return
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and active_tool in ["wand", "forms", "brush", "replace", "clone", "marks"]:
			_execute_selection_tool(); return
	if event is InputEventMouseButton and event.pressed and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE and not creative_inventory_panel.visible and not advanced_panel.visible and not radial_panel.visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED); crosshair.visible = true
		if studio_player != null: studio_player.set_controls_enabled(true)
		return
	super._unhandled_input(event)
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED or creative_inventory_panel.visible or advanced_panel.visible or radial_panel.visible:
		return
	if event is InputEventMouseButton and event.pressed and not biome_preview_active:
		_handle_tool_mouse(event.button_index, event.shift_pressed)


func _handle_double_space() -> void:
	var now: int = Time.get_ticks_msec()
	if now - last_space_press_ms <= DOUBLE_SPACE_MS:
		studio_player.creative_flight = not studio_player.creative_flight
		studio_player.velocity = Vector3.ZERO
		last_space_press_ms = -1000
		set_status("Voo ativo: Espaco sobe, Shift desce, Ctrl acelera." if studio_player.creative_flight else "Voo desativado: movimentacao normal da gameplay.")
	else:
		last_space_press_ms = now


func _is_solid_block_at(pos: Vector3i) -> bool:
	var block_id: String = workspace.get_block_id(pos)
	if block_id == "": return false
	return bool((BlockCatalogScript.blocks().get(block_id, {}) as Dictionary).get("solid", true))


func _build_ui() -> void:
	var root: VBoxContainer = make_side_panel("Estrutura", 330)
	advanced_panel = root.get_parent().get_parent() as Control
	tool_option = OptionButton.new()
	for label in ["Colocar", "Apagar", "Linha", "Caixa", "Esfera", "Preencher", "Substituir", "Copiar", "Colar", "Pivot", "Fundacao", "Ar explicito", "Conector", "Spawn Fantasma"]:
		tool_option.add_item(label)
	block_search_edit = LineEdit.new()
	block_search_edit.placeholder_text = "Buscar bloco..."
	block_search_edit.text_changed.connect(_filter_block_palette)
	block_option = OptionButton.new()
	_filter_block_palette("")
	template_id_edit = LineEdit.new(); template_id_edit.text = "nova_estrutura"; template_id_edit.placeholder_text = "structure_id"
	template_name_edit = LineEdit.new(); template_name_edit.text = "Nova estrutura"; template_name_edit.placeholder_text = "Nome"
	root.add_child(template_id_edit); root.add_child(template_name_edit)
	asset_kind_option = OptionButton.new()
	for entry in [["Custom Block", "custom_block"], ["Multiblock", "multiblock"], ["Estrutura", "structure"]]:
		asset_kind_option.add_item(str(entry[0])); asset_kind_option.set_item_metadata(asset_kind_option.item_count - 1, entry[1])
	asset_kind_option.select(2); asset_kind_option.item_selected.connect(_update_export_controls); root.add_child(asset_kind_option)
	placement_mode_option = OptionButton.new()
	for entry in [["Item inteiro", "atomic"], ["Montagem por pecas", "assembled"]]:
		placement_mode_option.add_item(str(entry[0])); placement_mode_option.set_item_metadata(placement_mode_option.item_count - 1, entry[1])
	root.add_child(placement_mode_option)
	utility_id_edit = LineEdit.new(); utility_id_edit.placeholder_text = "utility_id do multibloco"; root.add_child(utility_id_edit)
	var history_row: HBoxContainer = HBoxContainer.new()
	history_row.add_child(make_button("Desfazer", _undo)); history_row.add_child(make_button("Refazer", _redo))
	root.add_child(history_row)
	root.add_child(make_button("Editor de spawn (G)", _toggle_graph_editor))
	root.add_child(make_button("Carregar estrutura", func(): load_dialog.popup_centered_ratio(0.75)))
	root.add_child(make_button("Salvar no projeto", _save_structure_to_project))
	root.add_child(make_button("Exportar copia", func(): export_dialog.popup_centered_ratio(0.75)))
	root.add_child(make_button("Voltar ao menu", return_to_main_menu))
	_create_file_dialogs()
	_update_export_controls(asset_kind_option.selected)
	advanced_panel.visible = false
	_build_tool_wheel()


func _build_tool_wheel() -> void:
	radial_panel = PanelContainer.new()
	radial_panel.theme = studio_ui_theme
	radial_panel.set_anchors_preset(Control.PRESET_CENTER)
	radial_panel.position = Vector2(-230, -195)
	radial_panel.custom_minimum_size = Vector2(460, 390)
	UIStyleScript.apply_panel(radial_panel, "stone", 10.0)
	ui_layer.add_child(radial_panel)
	var root: VBoxContainer = VBoxContainer.new(); root.add_theme_constant_override("separation", 8); radial_panel.add_child(root)
	var title: Label = Label.new(); title.text = "FERRAMENTAS"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; UIStyleScript.apply_title(title, 22); root.add_child(title)
	var size_row: HBoxContainer = HBoxContainer.new(); size_row.alignment = BoxContainer.ALIGNMENT_CENTER; root.add_child(size_row)
	var size_label: Label = Label.new(); size_label.text = "Tamanho do voxel"; size_row.add_child(size_label)
	voxel_size_option = OptionButton.new()
	for label in ["1x (bloco)", "1/2", "1/4", "1/8"]: voxel_size_option.add_item(label)
	voxel_size_option.item_selected.connect(_select_voxel_size)
	size_row.add_child(voxel_size_option)
	var grid: GridContainer = GridContainer.new(); grid.columns = 3; grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; root.add_child(grid)
	var tools: Array = [
		["wand", "VARINHA", "Define A/B e cria linhas; Enter confirma."], ["forms", "FORMAS", "Cria caixas ou esferas dentro de A/B."], ["brush", "PINCEL", "Pinta ou apaga volumes; a roda muda o raio."],
		["replace", "TROCAR", "Substitui na selecao o material encontrado em A."], ["hand", "MAO", "Gameplay normal: quebrar, colocar e copiar material."], ["clone", "CLONAR", "Copia A/B e cola como um padrao reutilizavel."],
		["marks", "MARCAS", "Posiciona pivot, fundacao, conectores e spawns."], ["anchor", "ANCORA", "Marca a peca inicial de um multibloco montavel."], ["build", "CONSTRUIR", "Coloca microvoxels em 1x, 1/2, 1/4 ou 1/8; meio copia a celula."], ["structure", "ESTRUTURA", "Abre nome, spawn, salvar, carregar e exportar."],
	]
	for raw_tool in tools:
		var tool: Array = raw_tool as Array
		var button: Button = make_button(str(tool[1]), func(): _equip_tool(str(tool[0])))
		button.custom_minimum_size = Vector2(132, 72); button.tooltip_text = str(tool[2]); grid.add_child(button)
	active_tool_label = Label.new(); active_tool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; root.add_child(active_tool_label)
	_update_tool_label()
	radial_panel.visible = false


func _create_file_dialogs() -> void:
	export_dialog = FileDialog.new()
	export_dialog.title = "Exportar Estrutura"
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.filters = PackedStringArray(["*.tstructure.json ; Truman Structure"])
	export_dialog.file_selected.connect(_export_structure)
	ui_layer.add_child(export_dialog)
	load_dialog = FileDialog.new()
	load_dialog.title = "Carregar Estrutura"
	load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	load_dialog.filters = PackedStringArray(["*.tstructure.json ; Truman Structure"])
	load_dialog.file_selected.connect(_load_structure)
	ui_layer.add_child(load_dialog)


func _update_export_controls(_selected: int) -> void:
	if asset_kind_option == null: return
	var is_multiblock: bool = _selected_asset_kind() == "multiblock"
	placement_mode_option.visible = is_multiblock
	utility_id_edit.visible = is_multiblock


func _selected_asset_kind() -> String:
	return str(asset_kind_option.get_item_metadata(asset_kind_option.selected)) if asset_kind_option != null and asset_kind_option.selected >= 0 else "structure"


func _selected_placement_mode() -> String:
	return str(placement_mode_option.get_item_metadata(placement_mode_option.selected)) if placement_mode_option != null and placement_mode_option.selected >= 0 else "atomic"


func _build_creative_ui() -> void:
	var blocks: Dictionary = BlockCatalogScript.blocks()
	var names: Array = blocks.keys(); names.sort()
	for index in range(mini(9, names.size())): hotbar_blocks.append(str(names[index]))
	while hotbar_blocks.size() < 9: hotbar_blocks.append("stone")

	creative_inventory_panel = PanelContainer.new()
	creative_inventory_panel.theme = studio_ui_theme
	creative_inventory_panel.set_anchors_preset(Control.PRESET_CENTER)
	creative_inventory_panel.position = Vector2(-365, -260)
	creative_inventory_panel.custom_minimum_size = Vector2(730, 520)
	UIStyleScript.apply_panel(creative_inventory_panel, "stone", 10.0)
	ui_layer.add_child(creative_inventory_panel)
	var inventory_root: VBoxContainer = VBoxContainer.new()
	inventory_root.add_theme_constant_override("separation", 8)
	creative_inventory_panel.add_child(inventory_root)
	var title: Label = Label.new(); title.text = "Inventario Criativo — todos os blocos"; title.add_theme_font_size_override("font_size", 21)
	UIStyleScript.apply_title(title, 21)
	inventory_root.add_child(title)
	var filters: HBoxContainer = HBoxContainer.new(); inventory_root.add_child(filters)
	creative_search = LineEdit.new(); creative_search.placeholder_text = "Buscar por nome ou ID..."; creative_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	creative_search.text_changed.connect(func(_text: String): _rebuild_creative_grid())
	filters.add_child(creative_search)
	creative_category = OptionButton.new()
	for category in ["Todos", "Construcao", "Natureza", "Minerios", "Decoracao", "Utilidade"]: creative_category.add_item(category)
	creative_category.item_selected.connect(func(_index: int): _rebuild_creative_grid())
	filters.add_child(creative_category)
	var scroll: ScrollContainer = ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_root.add_child(scroll)
	creative_grid = GridContainer.new(); creative_grid.columns = 9; creative_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scroll.add_child(creative_grid)
	var close_hint: Label = Label.new(); close_hint.text = "Clique em um bloco para colocá-lo no slot selecionado. E fecha o inventario."
	inventory_root.add_child(close_hint)
	creative_inventory_panel.visible = false

	var hotbar_panel: PanelContainer = PanelContainer.new()
	hotbar_panel.theme = studio_ui_theme
	hotbar_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar_panel.position = Vector2(-224, -76)
	hotbar_panel.custom_minimum_size = Vector2(448, 60)
	UIStyleScript.apply_panel(hotbar_panel, "hotbar", 4.0)
	ui_layer.add_child(hotbar_panel)
	hotbar_root = HBoxContainer.new(); hotbar_root.add_theme_constant_override("separation", 3); hotbar_panel.add_child(hotbar_root)
	for index in range(9):
		var slot: ItemSlot = ItemSlot.new(); slot.theme = studio_ui_theme
		hotbar_buttons.append(slot); hotbar_root.add_child(slot)

	crosshair = Label.new(); crosshair.text = "+"; crosshair.add_theme_font_size_override("font_size", 24)
	crosshair.set_anchors_preset(Control.PRESET_CENTER); crosshair.position = Vector2(-7, -15); crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(crosshair)
	_rebuild_creative_grid(); _update_hotbar_ui()


func _build_graph_ui() -> void:
	graph_panel = PanelContainer.new()
	graph_panel.set_anchors_preset(Control.PRESET_CENTER)
	graph_panel.position = Vector2(-560, -330)
	graph_panel.custom_minimum_size = Vector2(1120, 660)
	ui_layer.add_child(graph_panel)
	var root: VBoxContainer = VBoxContainer.new(); root.add_theme_constant_override("separation", 8); graph_panel.add_child(root)
	var title: Label = Label.new(); title.text = "Grafo de Spawn da Estrutura"; title.add_theme_font_size_override("font_size", 22); root.add_child(title)
	var toolbar: HBoxContainer = HBoxContainer.new(); root.add_child(toolbar)
	graph_profile_option = OptionButton.new(); graph_profile_option.custom_minimum_size.x = 190; graph_profile_option.item_selected.connect(func(_index: int): _rebuild_graph())
	toolbar.add_child(graph_profile_option)
	toolbar.add_child(make_button("+ Perfil", _add_spawn_profile)); toolbar.add_child(make_button("- Perfil", _remove_spawn_profile))
	graph_node_type_option = OptionButton.new(); graph_node_type_option.custom_minimum_size.x = 210
	var definitions: Dictionary = SpawnGraphScript.node_definitions(); var node_types: Array = definitions.keys(); node_types.sort()
	for raw_type in node_types:
		var node_type: String = str(raw_type); var definition: Dictionary = definitions[node_type] as Dictionary
		graph_node_type_option.add_item("%s / %s" % [definition.get("category", ""), definition.get("name", node_type)])
		graph_node_type_option.set_item_metadata(graph_node_type_option.item_count - 1, node_type)
		graph_node_type_option.set_item_tooltip(graph_node_type_option.item_count - 1, str(definition.get("description", "")))
	toolbar.add_child(graph_node_type_option)
	toolbar.add_child(make_button("Adicionar no", _add_graph_node)); toolbar.add_child(make_button("Remover no", _remove_selected_graph_node))
	toolbar.add_child(make_button("Validar", _validate_current_graph)); toolbar.add_child(make_button("Preview estrutura", _show_structure_preview)); toolbar.add_child(make_button("Simular bioma 3D", _show_biome_preview)); toolbar.add_child(make_button("Fechar", _toggle_graph_editor))
	var split: HSplitContainer = HSplitContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; root.add_child(split)
	graph_edit = GraphEdit.new(); graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL; graph_edit.custom_minimum_size.x = 780
	graph_edit.connection_request.connect(_graph_connect_nodes); graph_edit.disconnection_request.connect(_graph_disconnect_nodes); graph_edit.node_selected.connect(_graph_node_selected)
	split.add_child(graph_edit)
	var inspector_scroll: ScrollContainer = ScrollContainer.new(); inspector_scroll.custom_minimum_size.x = 300; inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; split.add_child(inspector_scroll)
	graph_inspector = VBoxContainer.new(); graph_inspector.custom_minimum_size.x = 280; graph_inspector.add_theme_constant_override("separation", 6); inspector_scroll.add_child(graph_inspector)
	graph_panel.visible = false
	_rebuild_graph_profiles(); _rebuild_graph()


func _toggle_graph_editor() -> void:
	graph_panel.visible = not graph_panel.visible
	if graph_panel.visible:
		creative_inventory_panel.visible = false; advanced_panel.visible = false; radial_panel.visible = false; _rebuild_graph_profiles(); _rebuild_graph()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if graph_panel.visible else Input.MOUSE_MODE_CAPTURED)
	if studio_player != null: studio_player.set_controls_enabled(not graph_panel.visible)
	crosshair.visible = not graph_panel.visible


func _current_profile_index() -> int:
	return clampi(graph_profile_option.selected if graph_profile_option != null else 0, 0, maxi(0, spawn_profiles.size() - 1))


func _current_profile() -> Dictionary:
	return spawn_profiles[_current_profile_index()] as Dictionary


func _rebuild_graph_profiles() -> void:
	if graph_profile_option == null: return
	var selected: int = graph_profile_option.selected
	graph_profile_option.clear()
	for raw_profile in spawn_profiles:
		var profile: Dictionary = raw_profile as Dictionary; graph_profile_option.add_item(str(profile.get("name", profile.get("id", "Perfil"))))
	if graph_profile_option.item_count > 0: graph_profile_option.select(clampi(selected, 0, graph_profile_option.item_count - 1))


func _add_spawn_profile() -> void:
	var profile: Dictionary = SpawnGraphScript.default_profile(Vector2i.ZERO)
	var used_ids: Dictionary = {}
	for raw_profile in spawn_profiles: used_ids[str((raw_profile as Dictionary).get("id", ""))] = true
	var suffix: int = 1
	while used_ids.has("perfil_%d" % suffix): suffix += 1
	profile["id"] = "perfil_%d" % suffix; profile["name"] = "Perfil %d" % suffix
	spawn_profiles.append(profile); _rebuild_graph_profiles(); graph_profile_option.select(spawn_profiles.size() - 1); _rebuild_graph(); _mark_graph_preview_dirty()


func _remove_spawn_profile() -> void:
	if spawn_profiles.size() <= 1:
		set_status("A estrutura precisa manter ao menos um perfil."); return
	spawn_profiles.remove_at(_current_profile_index()); _rebuild_graph_profiles(); _rebuild_graph(); _mark_graph_preview_dirty()


func _rebuild_graph() -> void:
	if graph_edit == null or spawn_profiles.is_empty(): return
	graph_edit.clear_connections()
	for child in graph_edit.get_children():
		if child is GraphNode: graph_edit.remove_child(child); child.queue_free()
	var profile: Dictionary = _current_profile()
	var definitions: Dictionary = SpawnGraphScript.node_definitions()
	for raw_node in profile.get("nodes", []) as Array:
		var node_data: Dictionary = raw_node as Dictionary; var node_id: String = str(node_data.get("id", "")); var node_type: String = str(node_data.get("type", "")); var definition: Dictionary = definitions.get(node_type, {}) as Dictionary
		var graph_node: GraphNode = GraphNode.new(); graph_node.name = node_id; graph_node.title = str(definition.get("name", node_type)); graph_node.set_meta("base_title", graph_node.title); graph_node.tooltip_text = str(definition.get("description", "")); graph_node.custom_minimum_size = Vector2(210, 92)
		var position: Array = node_data.get("position", [0, 0]) as Array; graph_node.position_offset = Vector2(float(position[0]), float(position[1]))
		var summary: Label = Label.new(); summary.text = str(definition.get("description", "")); summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; summary.custom_minimum_size = Vector2(185, 48); summary.tooltip_text = graph_node.tooltip_text; graph_node.add_child(summary)
		var input_enabled: bool = node_type != "candidate_grid"; var output_enabled: bool = node_type != "generate"
		graph_node.set_slot(0, input_enabled, 0, Color(0.85, 0.7, 0.25), output_enabled, 0, Color(0.25, 0.7, 0.95))
		graph_node.position_offset_changed.connect(func(): _store_graph_node_position(node_id, graph_node.position_offset))
		graph_edit.add_child(graph_node)
	for raw_connection in profile.get("connections", []) as Array:
		var connection: Dictionary = raw_connection as Dictionary; var from_id: String = str(connection.get("from", "")); var to_id: String = str(connection.get("to", ""))
		if graph_edit.has_node(NodePath(from_id)) and graph_edit.has_node(NodePath(to_id)): graph_edit.connect_node(from_id, 0, to_id, 0)
	selected_graph_node_id = ""; _rebuild_graph_inspector()
	_update_graph_counters()


func _store_graph_node_position(node_id: String, position: Vector2) -> void:
	var node_data: Dictionary = _find_graph_node_data(node_id)
	if not node_data.is_empty(): node_data["position"] = [position.x, position.y]


func _graph_connect_nodes(from_node: StringName, _from_port: int, to_node: StringName, _to_port: int) -> void:
	var profile: Dictionary = _current_profile(); var connection: Dictionary = {"from": str(from_node), "to": str(to_node)}
	if from_node == to_node or (profile.get("connections", []) as Array).has(connection): return
	(profile.get("connections", []) as Array).append(connection); graph_edit.connect_node(from_node, 0, to_node, 0); _validate_current_graph()
	_mark_graph_preview_dirty()


func _graph_disconnect_nodes(from_node: StringName, _from_port: int, to_node: StringName, _to_port: int) -> void:
	var connections: Array = _current_profile().get("connections", []) as Array
	for index in range(connections.size() - 1, -1, -1):
		var connection: Dictionary = connections[index] as Dictionary
		if str(connection.get("from", "")) == str(from_node) and str(connection.get("to", "")) == str(to_node): connections.remove_at(index)
	graph_edit.disconnect_node(from_node, 0, to_node, 0)
	_mark_graph_preview_dirty()


func _graph_node_selected(node: Node) -> void:
	selected_graph_node_id = str(node.name); _rebuild_graph_inspector()


func _add_graph_node() -> void:
	if graph_node_type_option.item_count == 0: return
	var node_type: String = str(graph_node_type_option.get_item_metadata(graph_node_type_option.selected)); var definitions: Dictionary = SpawnGraphScript.node_definitions(); var definition: Dictionary = definitions[node_type] as Dictionary
	var profile: Dictionary = _current_profile(); var serial: int = (profile.get("nodes", []) as Array).size() + 1; var node_id: String = "%s_%d" % [node_type, serial]
	while not _find_graph_node_data(node_id).is_empty(): serial += 1; node_id = "%s_%d" % [node_type, serial]
	(profile.get("nodes", []) as Array).append({"id": node_id, "type": node_type, "position": [360 + serial * 12, 220 + serial * 10], "params": (definition.get("defaults", {}) as Dictionary).duplicate(true), "flexible": false, "relax_priority": 0, "relax_limit": 0.0})
	_rebuild_graph(); selected_graph_node_id = node_id; _rebuild_graph_inspector(); _mark_graph_preview_dirty()


func _remove_selected_graph_node() -> void:
	if selected_graph_node_id == "": return
	var profile: Dictionary = _current_profile(); var nodes: Array = profile.get("nodes", []) as Array
	for index in range(nodes.size() - 1, -1, -1):
		if str((nodes[index] as Dictionary).get("id", "")) == selected_graph_node_id: nodes.remove_at(index)
	var connections: Array = profile.get("connections", []) as Array
	for index in range(connections.size() - 1, -1, -1):
		var connection: Dictionary = connections[index] as Dictionary
		if str(connection.get("from", "")) == selected_graph_node_id or str(connection.get("to", "")) == selected_graph_node_id: connections.remove_at(index)
	selected_graph_node_id = ""; _rebuild_graph(); _mark_graph_preview_dirty()


func _find_graph_node_data(node_id: String) -> Dictionary:
	if spawn_profiles.is_empty(): return {}
	for raw_node in _current_profile().get("nodes", []) as Array:
		var node: Dictionary = raw_node as Dictionary
		if str(node.get("id", "")) == node_id: return node
	return {}


func _rebuild_graph_inspector() -> void:
	if graph_inspector == null: return
	for child in graph_inspector.get_children(): child.queue_free()
	var profile: Dictionary = _current_profile()
	var profile_id: LineEdit = LineEdit.new(); profile_id.text = str(profile.get("id", "")); profile_id.tooltip_text = "ID estavel usado nos logs e no planejamento deterministico."
	profile_id.text_submitted.connect(func(_text: String): _store_profile_identity(profile, profile_id.text, str(profile.get("name", ""))))
	profile_id.focus_exited.connect(func(): _store_profile_identity(profile, profile_id.text, str(profile.get("name", ""))))
	graph_inspector.add_child(_labeled("ID do perfil", profile_id))
	var profile_name: LineEdit = LineEdit.new(); profile_name.text = str(profile.get("name", "")); profile_name.tooltip_text = "Nome legivel exibido no Estudio."
	profile_name.text_submitted.connect(func(_text: String): _store_profile_identity(profile, str(profile.get("id", "")), profile_name.text))
	profile_name.focus_exited.connect(func(): _store_profile_identity(profile, str(profile.get("id", "")), profile_name.text))
	graph_inspector.add_child(_labeled("Nome do perfil", profile_name))
	var heading: Label = Label.new(); heading.text = "Propriedades do no"; heading.add_theme_font_size_override("font_size", 18); graph_inspector.add_child(heading)
	var node: Dictionary = _find_graph_node_data(selected_graph_node_id)
	if node.is_empty():
		var hint: Label = Label.new(); hint.text = "Selecione um no. Passe o mouse sobre qualquer funcao para ver uma descricao."; hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; graph_inspector.add_child(hint); return
	var definition: Dictionary = SpawnGraphScript.node_definitions().get(str(node.get("type", "")), {}) as Dictionary
	var description: Label = Label.new(); description.text = str(definition.get("description", "")); description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; description.tooltip_text = description.text; graph_inspector.add_child(description)
	var params: Dictionary = node.get("params", {}) as Dictionary
	var keys: Array = params.keys(); keys.sort()
	for raw_key in keys:
		var key: String = str(raw_key); var value: Variant = params[key]; var box: VBoxContainer = VBoxContainer.new(); var label: Label = Label.new(); label.text = key; label.tooltip_text = description.text; box.add_child(label)
		if typeof(value) == TYPE_BOOL:
			var checkbox: CheckBox = CheckBox.new(); checkbox.button_pressed = bool(value); checkbox.tooltip_text = description.text; checkbox.toggled.connect(func(pressed: bool): _set_graph_param(params, key, pressed)); box.add_child(checkbox)
		elif typeof(value) in [TYPE_INT, TYPE_FLOAT]:
			var integer_value: bool = typeof(value) == TYPE_INT
			var spin: SpinBox = SpinBox.new(); spin.min_value = -10000; spin.max_value = 10000; spin.step = 1.0 if integer_value else 0.01; spin.value = float(value); spin.tooltip_text = description.text; spin.value_changed.connect(func(new_value: float): _set_graph_param(params, key, int(new_value) if integer_value else new_value)); box.add_child(spin)
		else:
			var edit: LineEdit = LineEdit.new(); edit.text = JSON.stringify(value); edit.tooltip_text = "JSON do parametro. %s" % description.text; edit.text_submitted.connect(func(text: String): _set_graph_complex_param(params, key, text)); edit.focus_exited.connect(func(): _set_graph_complex_param(params, key, edit.text)); box.add_child(edit)
		graph_inspector.add_child(box)
	if str(node.get("type", "")) in SpawnGraphScript.RELAXABLE_TYPES:
		var flexible: CheckBox = CheckBox.new(); flexible.text = "Condicao flexivel"; flexible.tooltip_text = "Permite relaxar esta condicao quando uma quantidade exata nao pode ser atingida."; flexible.button_pressed = bool(node.get("flexible", false)); flexible.toggled.connect(func(value: bool): _set_graph_param(node, "flexible", value)); graph_inspector.add_child(flexible)
		var priority: SpinBox = SpinBox.new(); priority.min_value = 0; priority.max_value = 999; priority.step = 1; priority.value = int(node.get("relax_priority", 0)); priority.tooltip_text = "Menores prioridades relaxam primeiro."; priority.value_changed.connect(func(value: float): _set_graph_param(node, "relax_priority", int(value))); graph_inspector.add_child(_labeled("Prioridade de relaxamento", priority))
		var limit: SpinBox = SpinBox.new(); limit.min_value = 0; limit.max_value = 1000; limit.step = 0.1; limit.value = float(node.get("relax_limit", 0.0)); limit.tooltip_text = "Maior alteracao permitida para esta condicao."; limit.value_changed.connect(func(value: float): _set_graph_param(node, "relax_limit", value)); graph_inspector.add_child(_labeled("Limite de relaxamento", limit))


func _store_profile_identity(profile: Dictionary, profile_id: String, profile_name: String) -> void:
	profile["id"] = profile_id.strip_edges()
	profile["name"] = profile_name.strip_edges()
	_rebuild_graph_profiles()
	_mark_graph_preview_dirty()


func _set_graph_param(target: Dictionary, key: String, value: Variant) -> void:
	target[key] = value
	_mark_graph_preview_dirty()


func _set_graph_complex_param(params: Dictionary, key: String, text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if parsed != null: _set_graph_param(params, key, parsed)
	else: set_status("JSON invalido no parametro %s." % key)


func _validate_current_graph() -> void:
	var errors: Array[String] = SpawnGraphScript.validate_profile(_current_profile())
	set_status("Grafo valido." if errors.is_empty() else "Grafo invalido: %s" % "; ".join(errors))


func _mark_graph_preview_dirty() -> void:
	if not biome_preview_active: return
	preview_refresh_pending = true
	preview_refresh_elapsed = 0.0


func _update_graph_counters() -> void:
	if graph_edit == null or last_preview_report == null or spawn_profiles.is_empty(): return
	var profile_key: String = "%s::%s" % [template_id_edit.text.strip_edges(), _current_profile().get("id", "")]
	var by_node: Dictionary = last_preview_report.rejection_counts.get(profile_key, {}) as Dictionary
	var candidate_count: int = int(last_preview_report.candidate_counts.get(profile_key, 0))
	var generated_count: int = 0
	for raw_instance in last_preview_report.instances:
		var instance: Dictionary = raw_instance as Dictionary
		if str(instance.get("id", "")) == template_id_edit.text.strip_edges() and str(instance.get("profile_id", "")) == str(_current_profile().get("id", "")): generated_count += 1
	for child in graph_edit.get_children():
		if not (child is GraphNode): continue
		var graph_node: GraphNode = child as GraphNode
		var node_data: Dictionary = _find_graph_node_data(str(graph_node.name))
		var node_type: String = str(node_data.get("type", ""))
		var suffix: String = ""
		if node_type == "candidate_grid": suffix = " · %d candidatos" % candidate_count
		elif node_type == "generate": suffix = " · %d geradas" % generated_count
		elif by_node.has(str(graph_node.name)):
			var rejected: int = 0
			for count in (by_node[str(graph_node.name)] as Dictionary).values(): rejected += int(count)
			suffix = " · %d rejeicoes" % rejected
		graph_node.title = "%s%s" % [str(graph_node.get_meta("base_title", graph_node.title)), suffix]


func _rebuild_creative_grid() -> void:
	if creative_grid == null: return
	for child in creative_grid.get_children(): child.queue_free()
	creative_visible_blocks.clear()
	var definitions: Dictionary = _studio_catalog_definitions()
	var names: Array = definitions.keys(); names.sort()
	var query: String = creative_search.text.strip_edges().to_lower() if creative_search != null else ""
	var wanted_category: String = creative_category.get_item_text(creative_category.selected).to_lower() if creative_category != null else "todos"
	for raw_id in names:
		var block_id: String = str(raw_id)
		var definition: Dictionary = definitions[block_id] as Dictionary
		var display_name: String = str(definition.get("name", block_id))
		if query != "" and not block_id.to_lower().contains(query) and not display_name.to_lower().contains(query): continue
		if wanted_category != "todos" and _creative_category_for(block_id, definition) != wanted_category: continue
		var slot_index: int = creative_visible_blocks.size(); creative_visible_blocks.append(block_id)
		var slot: ItemSlot = ItemSlot.new(); slot.theme = studio_ui_theme
		var template = definition.get("asset", null)
		slot.configure(self, "studio_catalog", slot_index, block_id, 1, display_name, "Asset criativo infinito." if template != null else "Bloco criativo infinito.", _block_icon(definition), _block_icon_faces(definition), Vector2(58, 58), true, _studio_asset_mesh(template) if template != null else null)
		slot.set_count_text_override("∞"); slot.tooltip_text = "%s\n%s\nInfinito" % [display_name, block_id]
		creative_grid.add_child(slot)


func _creative_category_for(block_id: String, definition: Dictionary) -> String:
	if definition.has("asset"): return "utilidade"
	if block_id.ends_with("_ore"): return "minerios"
	if bool(definition.get("plant", false)) or block_id in ["leaves", "short_grass", "wild_grass", "poppy", "dandelion", "cornflower", "oxeye_daisy"]: return "decoracao"
	if block_id in ["grass", "dirt", "wood", "leaves"]: return "natureza"
	if block_id in ["crafting_table", "chest"]: return "utilidade"
	return "construcao"


func _choose_creative_block(block_id: String) -> void:
	hotbar_blocks[selected_hotbar] = block_id
	hotbar_patterns.erase(selected_hotbar)
	pattern_stamp_active = false
	for index in range(block_option.item_count):
		if block_option.get_item_text(index) == block_id: block_option.select(index); break
	_update_hotbar_ui()
	set_status("%s selecionado no slot %d." % [block_id, selected_hotbar + 1])


func _select_hotbar(index: int) -> void:
	selected_hotbar = clampi(index, 0, 8)
	pattern_stamp_active = hotbar_patterns.has(selected_hotbar)
	_update_hotbar_ui()


func _update_hotbar_ui() -> void:
	if hotbar_buttons.is_empty(): return
	var definitions: Dictionary = _studio_catalog_definitions()
	for index in range(hotbar_buttons.size()):
		var slot: ItemSlot = hotbar_buttons[index]
		var block_id: String = hotbar_blocks[index]
		var definition: Dictionary = definitions.get(block_id, {}) as Dictionary
		var pattern = hotbar_patterns.get(index, null)
		var display_name: String = "Padrao 8x8x8" if pattern != null else str(definition.get("name", block_id))
		var item_id: String = "studio_pattern_%s" % pattern.content_hash() if pattern != null else block_id
		var asset = definition.get("asset", null)
		var pattern_mesh: Mesh = _pattern_mesh(pattern) if pattern != null else (_studio_asset_mesh(asset) if asset != null else null)
		slot.configure(self, "studio_hotbar", index, item_id, 1, display_name, "Padrao copiado infinito." if pattern != null else "Bloco criativo infinito.", _block_icon(definition), {} if pattern != null else _block_icon_faces(definition), Vector2(44, 44), true, pattern_mesh)
		slot.set_visual_kind("hotbar"); slot.set_selected(index == selected_hotbar); slot.set_count_text_override("∞")
		slot.tooltip_text = "%d · %s\nInfinito" % [index + 1, display_name]
	_sync_creative_held_item()


func slot_mouse_button(slot_type: String, slot_index: int, _button_index: int, pressed: bool) -> void:
	if not pressed: return
	if slot_type == "studio_catalog" and slot_index >= 0 and slot_index < creative_visible_blocks.size():
		_choose_creative_block(creative_visible_blocks[slot_index])
	elif slot_type == "studio_hotbar":
		_select_hotbar(slot_index)


func slot_mouse_entered(slot_type: String, slot_index: int) -> void:
	var block_id: String = ""
	if slot_type == "studio_catalog" and slot_index >= 0 and slot_index < creative_visible_blocks.size(): block_id = creative_visible_blocks[slot_index]
	elif slot_type == "studio_hotbar" and slot_index >= 0 and slot_index < hotbar_blocks.size(): block_id = hotbar_blocks[slot_index]
	if block_id != "": set_status("%s · material infinito" % str((_studio_catalog_definitions().get(block_id, {}) as Dictionary).get("name", block_id)))


func slot_mouse_exited(_slot_type: String, _slot_index: int) -> void:
	pass


func _block_icon(definition: Dictionary) -> Texture2D:
	var path: String = str(definition.get("icon", definition.get("texture", "")))
	return load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null


func _block_icon_faces(definition: Dictionary) -> Dictionary:
	if bool(definition.get("plant", false)): return {}
	var result: Dictionary = {}
	for face_name in ["north", "south", "east", "west", "top", "bottom"]:
		var path: String = _block_texture_for_face(definition, face_name)
		if path != "" and ResourceLoader.exists(path): result[face_name] = load(path) as Texture2D
	result["front"] = result.get("north", null); result["side"] = result.get("west", result.get("east", null))
	return result


func _block_texture_for_face(definition: Dictionary, face_name: String) -> String:
	var textures: Dictionary = definition.get("textures", {}) as Dictionary
	if textures.has(face_name): return str(textures[face_name])
	if face_name == "north" and textures.has("front"): return str(textures["front"])
	if face_name in ["south", "east", "west"] and textures.has("side"): return str(textures["side"])
	if textures.has("side"): return str(textures["side"])
	if textures.has("all"): return str(textures["all"])
	return str(definition.get("texture", ""))


func _sync_creative_held_item() -> void:
	if studio_player == null or hotbar_blocks.is_empty(): return
	var block_id: String = hotbar_blocks[selected_hotbar]
	var definition: Dictionary = _studio_catalog_definitions().get(block_id, {}) as Dictionary
	var pattern = hotbar_patterns.get(selected_hotbar, null)
	if pattern != null:
		studio_player.set_held_item("studio_pattern_%s" % pattern.content_hash(), _block_icon(definition), _pattern_mesh(pattern), {})
	elif definition.has("asset"):
		studio_player.set_held_item(block_id, null, _studio_asset_mesh(definition.get("asset", null)), {})
	else:
		studio_player.set_held_item(block_id, _block_icon(definition), null, _block_icon_faces(definition))


func _pattern_mesh(cell) -> Mesh:
	if cell == null: return null
	var signature: String = cell.content_hash()
	if pattern_mesh_cache.has(signature): return pattern_mesh_cache[signature] as Mesh
	var preview_workspace = WorkspaceScript.new(BlockCatalogScript.blocks())
	if texture_array != null: preview_workspace.configure_texture_layers(texture_array.layer_by_path)
	preview_workspace.set_micro_cell(Vector3i.ZERO, cell)
	var result: Dictionary = VoxelSectionMesherScript.build(preview_workspace.make_section_snapshot(Vector3i.ZERO), preview_workspace.get_render_palette(), false)
	var surfaces: Array = []
	for render_class in ["opaque", "cutout", "transparent"]:
		surfaces.append_array(result.get(render_class, []) as Array)
	var mesh: Mesh = section_system._build_mesh(surfaces)
	pattern_mesh_cache[signature] = mesh
	return mesh


func _reload_project_assets() -> void:
	project_asset_registry = StructureRegistryScript.load_from_file(PROJECT_STRUCTURE_DIR.path_join("registry.json"))
	if project_asset_registry == null: project_asset_registry = StructureRegistryScript.empty_registry()
	studio_asset_system = PlacedAssetSystemScript.new(); studio_asset_system.configure(workspace, project_asset_registry)
	if creative_grid != null: _rebuild_creative_grid()


func _studio_catalog_definitions() -> Dictionary:
	var result: Dictionary = BlockCatalogScript.blocks().duplicate(true)
	if project_asset_registry == null: return result
	for template in project_asset_registry.get_placeable_assets():
		result[template.structure_id] = {"name": template.display_name, "asset": template}
	return result


func _selected_project_asset():
	if project_asset_registry == null or hotbar_blocks.is_empty(): return null
	var template = project_asset_registry.get_asset(hotbar_blocks[selected_hotbar])
	return template if template != null and template.asset_kind in ["custom_block", "multiblock"] else null


func _studio_asset_mesh(template) -> Mesh:
	if template == null: return null
	var signature: String = "asset:%s" % template.content_hash()
	if pattern_mesh_cache.has(signature): return pattern_mesh_cache[signature] as Mesh
	var preview_workspace = WorkspaceScript.new(BlockCatalogScript.blocks())
	if texture_array != null: preview_workspace.configure_texture_layers(texture_array.layer_by_path)
	# Resolve component references here as well, so the item in the catalog and in
	# the player's hand represents the exact asset that will be placed.
	for raw_cell in studio_asset_system.transformed_cells(template, template.pivot, 0):
		var cell: Dictionary = raw_cell as Dictionary
		var pos: Vector3i = cell.get("pos", Vector3i.ZERO)
		match str(cell.get("kind", "")):
			"block": preview_workspace.set_block(pos, str(cell.get("block_id", "")))
			"micro": preview_workspace.set_micro_cell(pos, cell.get("cell", null))
	var surfaces: Array = []
	for raw_section in preview_workspace.get_nonempty_sections():
		var result: Dictionary = VoxelSectionMesherScript.build(preview_workspace.make_section_snapshot(raw_section as Vector3i), preview_workspace.get_render_palette(), false)
		for render_class in ["opaque", "cutout", "transparent"]: surfaces.append_array(result.get(render_class, []) as Array)
	var mesh: Mesh = section_system._build_mesh(surfaces)
	pattern_mesh_cache[signature] = mesh
	return mesh


func _representative_material(cell) -> String:
	for raw_material in cell.palette:
		var material_id: String = str(raw_material)
		if material_id != "": return material_id
	return "stone"


func _toggle_creative_inventory() -> void:
	creative_inventory_panel.visible = not creative_inventory_panel.visible
	if creative_inventory_panel.visible: advanced_panel.visible = false; radial_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if creative_inventory_panel.visible else Input.MOUSE_MODE_CAPTURED)
	if studio_player != null: studio_player.set_controls_enabled(not creative_inventory_panel.visible)
	crosshair.visible = not creative_inventory_panel.visible and not advanced_panel.visible and not radial_panel.visible


func _toggle_advanced_tools() -> void:
	advanced_panel.visible = not advanced_panel.visible
	if advanced_panel.visible: creative_inventory_panel.visible = false; radial_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if advanced_panel.visible else Input.MOUSE_MODE_CAPTURED)
	if studio_player != null: studio_player.set_controls_enabled(not advanced_panel.visible)
	crosshair.visible = not advanced_panel.visible


func _toggle_tool_wheel() -> void:
	radial_panel.visible = not radial_panel.visible
	if radial_panel.visible:
		creative_inventory_panel.visible = false; advanced_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if radial_panel.visible else Input.MOUSE_MODE_CAPTURED)
	if studio_player != null: studio_player.set_controls_enabled(not radial_panel.visible)
	crosshair.visible = not radial_panel.visible


func _equip_tool(tool_id: String) -> void:
	if tool_id == "structure":
		radial_panel.visible = false; _toggle_advanced_tools(); return
	active_tool = tool_id
	var option_by_tool: Dictionary = {"hand": 0, "build": 0, "wand": 2, "forms": 3, "brush": 5, "replace": 6, "clone": 7, "marks": 9}
	tool_option.select(int(option_by_tool.get(tool_id, 0)))
	pattern_stamp_active = hotbar_patterns.has(selected_hotbar)
	_update_tool_label()
	radial_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if studio_player != null: studio_player.set_controls_enabled(true)
	crosshair.visible = true
	set_status("Ferramenta equipada: %s." % active_tool_label.text)


func _select_voxel_size(index: int) -> void:
	micro_edge = [8, 4, 2, 1][clampi(index, 0, 3)]
	_update_tool_label()


func _update_tool_label() -> void:
	if active_tool_label == null: return
	var names: Dictionary = {"hand": "Mao", "build": "Construir", "wand": "Varinha", "forms": "Formas", "brush": "Pincel", "replace": "Trocar", "clone": "Clonar", "marks": "Marcas"}
	var size_text: String = {8: "1x", 4: "1/2", 2: "1/4", 1: "1/8"}.get(micro_edge, "1x")
	active_tool_label.text = "%s  |  voxel %s" % [names.get(active_tool, active_tool), size_text]


func _create_placement_outline() -> void:
	placement_outline = MeshInstance3D.new()
	placement_outline.name = "PlacementOutline"
	placement_outline.mesh = _make_placement_outline_mesh()
	placement_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.BLACK
	placement_outline.material_override = material
	placement_outline.visible = false
	add_child(placement_outline)


func _update_placement_outline() -> void:
	if placement_outline == null: return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED or biome_preview_active or active_tool not in ["hand", "build"]:
		placement_outline.visible = false
		return
	var hit = _current_hit()
	if hit == null:
		placement_outline.visible = false
		return
	var edge: int = MicroCellScript.SIZE if pattern_stamp_active else micro_edge
	var target: Dictionary = _micro_target(hit, edge)
	var base_pos: Vector3i = target.get("base", Vector3i(-1, -1, -1))
	if not workspace.is_inside_world(base_pos):
		placement_outline.visible = false
		return
	var local: Vector3i = target.get("local", Vector3i.ZERO)
	placement_outline.transform = _placement_outline_transform(base_pos, local, edge)
	placement_outline.visible = true


func _placement_outline_transform(base_pos: Vector3i, local: Vector3i, edge: int) -> Transform3D:
	var size: float = float(edge) / float(MicroCellScript.SIZE)
	var center: Vector3 = Vector3(base_pos) - Vector3.ONE * 0.5 + (Vector3(local) + Vector3.ONE * float(edge) * 0.5) / float(MicroCellScript.SIZE)
	return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), center)


func _make_placement_outline_mesh() -> ArrayMesh:
	var s: float = 0.515
	var vertices: PackedVector3Array = PackedVector3Array([
		Vector3(-s, -s, -s), Vector3(s, -s, -s), Vector3(s, -s, -s), Vector3(s, -s, s),
		Vector3(s, -s, s), Vector3(-s, -s, s), Vector3(-s, -s, s), Vector3(-s, -s, -s),
		Vector3(-s, s, -s), Vector3(s, s, -s), Vector3(s, s, -s), Vector3(s, s, s),
		Vector3(s, s, s), Vector3(-s, s, s), Vector3(-s, s, s), Vector3(-s, s, -s),
		Vector3(-s, -s, -s), Vector3(-s, s, -s), Vector3(s, -s, -s), Vector3(s, s, -s),
		Vector3(s, -s, s), Vector3(s, s, s), Vector3(-s, -s, s), Vector3(-s, s, s),
	])
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh: ArrayMesh = ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func _handle_tool_mouse(button_index: MouseButton, shift_pressed: bool = false) -> void:
	if button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if active_tool == "brush" and shift_pressed:
			brush_radius = clampi(brush_radius + (1 if button_index == MOUSE_BUTTON_WHEEL_UP else -1), 1, 8)
			set_status("Raio do pincel: %d." % brush_radius)
		else:
			_select_hotbar(posmod(selected_hotbar + (-1 if button_index == MOUSE_BUTTON_WHEEL_UP else 1), hotbar_blocks.size()))
		return
	if active_tool in ["hand", "build"]:
		if button_index == MOUSE_BUTTON_MIDDLE:
			_copy_cell_pattern()
		elif button_index == MOUSE_BUTTON_LEFT:
			if not _uses_micro_placement(): _creative_break()
			else: _micro_remove()
		elif button_index == MOUSE_BUTTON_RIGHT:
			if not _uses_micro_placement(): _creative_place()
			else: _micro_place()
		return
	if active_tool == "brush":
		var hit = _current_hit()
		if hit == null: return
		var center: Vector3i = hit.pos + hit.normal if button_index == MOUSE_BUTTON_LEFT else hit.pos
		if button_index == MOUSE_BUTTON_LEFT: _apply_block_positions(_brush_positions(center), selected_block())
		elif button_index == MOUSE_BUTTON_RIGHT: _apply_block_positions(_brush_positions(center), "")
		return
	if active_tool == "anchor" and button_index == MOUSE_BUTTON_LEFT:
		_set_assembly_anchor()
		return
	if button_index == MOUSE_BUTTON_LEFT:
		_set_selection_point(true)
	elif button_index == MOUSE_BUTTON_RIGHT:
		_set_selection_point(false)
	elif button_index == MOUSE_BUTTON_MIDDLE and active_tool == "clone":
		_copy_selection()


func _uses_micro_placement() -> bool:
	return micro_edge != MicroCellScript.SIZE or pattern_stamp_active


func _brush_positions(center: Vector3i) -> Array:
	var result: Array = []
	var squared_radius: int = brush_radius * brush_radius
	for y in range(center.y - brush_radius + 1, center.y + brush_radius):
		for z in range(center.z - brush_radius + 1, center.z + brush_radius):
			for x in range(center.x - brush_radius + 1, center.x + brush_radius):
				var pos: Vector3i = Vector3i(x, y, z)
				if (pos - center).length_squared() < squared_radius: result.append(pos)
	return result


func _cell_as_micro(pos: Vector3i):
	var existing = workspace.get_micro_cell(pos)
	if existing != null:
		return existing.duplicate_cell()
	var block_id: String = workspace.get_block_id(pos)
	var cell = MicroCellScript.new()
	if block_id != "": cell.fill_region(Vector3i.ZERO, MicroCellScript.SIZE, block_id)
	return cell


func _micro_place() -> void:
	var hit = _current_hit()
	if hit == null: return
	var pattern = hotbar_patterns.get(selected_hotbar, null) if pattern_stamp_active else null
	var target: Dictionary = _micro_target(hit, MicroCellScript.SIZE if pattern != null else micro_edge)
	var base_pos: Vector3i = target.get("base", Vector3i(-1, -1, -1))
	if not workspace.is_inside_world(base_pos): return
	if pattern != null:
		if not _can_place_full_cell(base_pos): return
		_apply_micro_cell(base_pos, pattern.duplicate_cell())
		set_status("Padrao aplicado em %s." % base_pos)
		return
	var cell = _cell_as_micro(base_pos)
	if cell.fill_region(target.get("local", Vector3i.ZERO), micro_edge, selected_block(), true):
		_apply_micro_cell(base_pos, cell)
	else:
		set_status("Espaco ocupado: o voxel existente foi preservado.")


func _micro_remove() -> void:
	var hit = _current_hit()
	if hit == null: return
	var removal_edge: int = _selected_removal_edge()
	if removal_edge == MicroCellScript.SIZE:
		_apply_micro_cell(hit.pos, MicroCellScript.new()); return
	var cell = _cell_as_micro(hit.pos)
	var local: Vector3i = hit.micro_pos if hit.is_micro else _micro_at_hit_point(hit, true)
	local = Vector3i((local.x / removal_edge) * removal_edge, (local.y / removal_edge) * removal_edge, (local.z / removal_edge) * removal_edge)
	if cell.clear_region(local, removal_edge):
		_apply_micro_cell(hit.pos, cell)


func _selected_removal_edge() -> int:
	return MicroCellScript.SIZE if pattern_stamp_active else micro_edge


func _micro_target(hit, edge: int) -> Dictionary:
	if edge == MicroCellScript.SIZE:
		return {"base": _full_cell_target(hit), "local": Vector3i.ZERO}
	var base_pos: Vector3i
	var local: Vector3i
	if hit.is_micro:
		base_pos = hit.pos
		var support_normal: Vector3i = hit.normal
		if support_normal == Vector3i.ZERO:
			var ray_origin: Vector3 = studio_player.get_interaction_ray_start() if studio_player != null else camera_ray_origin()
			var ray_direction: Vector3 = studio_player.get_aim_direction() if studio_player != null else camera_ray_direction()
			support_normal = _base_cell_entry_normal(hit.pos, ray_origin, ray_direction)
		local = Vector3i((hit.micro_pos.x / edge) * edge, (hit.micro_pos.y / edge) * edge, (hit.micro_pos.z / edge) * edge) + support_normal * edge
	else:
		base_pos = hit.pos + hit.normal
		local = _micro_at_world_point(base_pos, _hit_world_point(hit))
		local = Vector3i((local.x / edge) * edge, (local.y / edge) * edge, (local.z / edge) * edge)
		if hit.normal.x > 0: local.x = 0
		elif hit.normal.x < 0: local.x = MicroCellScript.SIZE - edge
		if hit.normal.y > 0: local.y = 0
		elif hit.normal.y < 0: local.y = MicroCellScript.SIZE - edge
		if hit.normal.z > 0: local.z = 0
		elif hit.normal.z < 0: local.z = MicroCellScript.SIZE - edge
	while local.x < 0: base_pos.x -= 1; local.x += MicroCellScript.SIZE
	while local.x >= MicroCellScript.SIZE: base_pos.x += 1; local.x -= MicroCellScript.SIZE
	while local.y < 0: base_pos.y -= 1; local.y += MicroCellScript.SIZE
	while local.y >= MicroCellScript.SIZE: base_pos.y += 1; local.y -= MicroCellScript.SIZE
	while local.z < 0: base_pos.z -= 1; local.z += MicroCellScript.SIZE
	while local.z >= MicroCellScript.SIZE: base_pos.z += 1; local.z -= MicroCellScript.SIZE
	return {"base": base_pos, "local": local}


func _full_cell_target(hit) -> Vector3i:
	var ray_origin: Vector3 = studio_player.get_interaction_ray_start() if studio_player != null else camera_ray_origin()
	var ray_direction: Vector3 = studio_player.get_aim_direction() if studio_player != null else camera_ray_direction()
	return _full_cell_target_for_ray(hit, ray_origin, ray_direction)


func _full_cell_target_for_ray(hit, ray_origin: Vector3, ray_direction: Vector3) -> Vector3i:
	var normal: Vector3i = hit.normal
	if hit.is_micro or normal == Vector3i.ZERO:
		normal = _base_cell_entry_normal(hit.pos, ray_origin, ray_direction)
	return hit.pos + normal


func _base_cell_entry_normal(base_pos: Vector3i, ray_origin: Vector3, ray_direction: Vector3) -> Vector3i:
	var direction: Vector3 = ray_direction.normalized()
	var minimum: Vector3 = Vector3(base_pos) - Vector3.ONE * 0.5
	var maximum: Vector3 = Vector3(base_pos) + Vector3.ONE * 0.5
	var entry_distance: float = -INF
	var entry_normal: Vector3i = Vector3i.ZERO
	for axis in range(3):
		var component: float = direction[axis]
		if absf(component) < 0.000001: continue
		var plane: float = minimum[axis] if component > 0.0 else maximum[axis]
		var distance: float = (plane - ray_origin[axis]) / component
		if distance > entry_distance:
			entry_distance = distance
			entry_normal = Vector3i.ZERO
			entry_normal[axis] = -1 if component > 0.0 else 1
	return entry_normal


func _hit_world_point(hit) -> Vector3:
	var origin: Vector3 = studio_player.get_interaction_ray_start() if studio_player != null else camera_ray_origin()
	var direction: Vector3 = studio_player.get_aim_direction() if studio_player != null else camera_ray_direction()
	return origin + direction.normalized() * hit.distance


func _micro_at_hit_point(hit, inside: bool) -> Vector3i:
	var point: Vector3 = _hit_world_point(hit)
	if inside: point += (studio_player.get_aim_direction() if studio_player != null else camera_ray_direction()).normalized() * 0.0001
	return _micro_at_world_point(hit.pos, point)


func _micro_at_world_point(base_pos: Vector3i, point: Vector3) -> Vector3i:
	var relative: Vector3 = (point - (Vector3(base_pos) - Vector3.ONE * 0.5)) * float(MicroCellScript.SIZE)
	return Vector3i(clampi(floori(relative.x), 0, 7), clampi(floori(relative.y), 0, 7), clampi(floori(relative.z), 0, 7))


func _apply_micro_cell(pos: Vector3i, cell, record_history: bool = true) -> Dictionary:
	var before: Dictionary = _cell_state(pos)
	if cell == null or cell.is_empty(): workspace.clear_block(pos)
	else: workspace.set_micro_cell(pos, cell)
	workspace.explicit_air.erase(pos); workspace.clear_metadata(pos)
	var after: Dictionary = _cell_state(pos)
	if before == after: return {}
	var command: Dictionary = {"type": "micro_cells", "changes": [{"pos": pos, "before": before, "after": after}]}
	if record_history: history.push(command)
	_include_authored_position(pos); _deactivate_guide_for_changes([{"pos": pos}])
	section_system.queue_sections(workspace.get_affected_sections(pos), true)
	return command


func _cell_state(pos: Vector3i) -> Dictionary:
	var micro_cell = workspace.get_micro_cell(pos)
	if micro_cell != null: return {"kind": "micro", "cell": micro_cell.to_dictionary()}
	var block_id: String = workspace.get_block_id(pos)
	return {"kind": "block", "block": block_id} if block_id != "" else {"kind": "air"}


func _restore_cell_state(pos: Vector3i, state: Dictionary) -> void:
	match str(state.get("kind", "air")):
		"block": workspace.set_block(pos, str(state.get("block", "")))
		"micro":
			var cell = MicroCellScript.from_dictionary(state.get("cell", {}) as Dictionary, BlockCatalogScript.blocks())
			if cell != null: workspace.set_micro_cell(pos, cell)
		_: workspace.clear_block(pos)


func _copy_cell_pattern() -> void:
	var hit = _current_hit()
	if hit == null: return
	pattern_clipboard = _cell_as_micro(hit.pos)
	if pattern_clipboard.is_empty(): return
	_store_pattern_in_hotbar(pattern_clipboard)
	_save_pattern_clipboard()
	set_status("Celula 8x8x8 copiada para o slot %d. RMB estampa o padrao." % [selected_hotbar + 1])


func _store_pattern_in_hotbar(cell) -> void:
	hotbar_blocks[selected_hotbar] = _representative_material(cell)
	hotbar_patterns[selected_hotbar] = cell.duplicate_cell()
	pattern_stamp_active = true
	_update_hotbar_ui()


func _save_pattern_clipboard() -> void:
	if pattern_clipboard == null: return
	var file: FileAccess = FileAccess.open(PATTERN_PATH, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"format": "trumancraft_structure_pattern", "version": 1, "cell": pattern_clipboard.to_dictionary()}, "\t"))


func _load_pattern_clipboard() -> void:
	var file: FileAccess = FileAccess.open(PATTERN_PATH, FileAccess.READ)
	if file == null: return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY and str((parsed as Dictionary).get("format", "")) == "trumancraft_structure_pattern":
		pattern_clipboard = MicroCellScript.from_dictionary((parsed as Dictionary).get("cell", {}) as Dictionary, BlockCatalogScript.blocks())


func _creative_break() -> void:
	var hit = _current_hit()
	if hit != null:
		var component: Dictionary = _workspace_component_at(hit.pos)
		if not component.is_empty():
			_remove_workspace_component(component)
			if studio_player != null: studio_player.play_break_finish()
			return
		if hit.is_micro:
			var micro_command: Dictionary = _apply_micro_cell(hit.pos, MicroCellScript.new())
			if not micro_command.is_empty() and voxel_debris != null: voxel_debris.emit_burst(hit.pos, hit.normal, hit.block_id)
			if studio_player != null: studio_player.play_break_finish()
			return
		var block_id: String = workspace.get_block_id(hit.pos)
		var removals: Array[Vector3i] = VoxelDependencyResolverScript.collect_removal_positions(workspace, hit.pos, BlockCatalogScript.blocks())
		var command: Dictionary = _apply_block_positions(removals, "")
		if not command.is_empty() and voxel_debris != null:
			voxel_debris.emit_burst(hit.pos, hit.normal, block_id)
		if studio_player != null: studio_player.play_break_finish()


func _creative_place() -> void:
	var hit = _current_hit()
	if hit == null: return
	var target: Vector3i = _full_cell_target(hit)
	var asset = _selected_project_asset()
	if asset != null:
		_place_project_asset(asset, target); return
	if not _can_place_full_cell(target): return
	var block_id: String = hotbar_blocks[selected_hotbar]
	if not VoxelDependencyResolverScript.can_place(workspace, target, block_id, BlockCatalogScript.blocks()):
		set_status("Plantas precisam de um bloco solido abaixo.")
		return
	_apply_block_positions([target], block_id)
	if studio_player != null: studio_player.play_place_swing()


func _place_project_asset(template, pivot_world: Vector3i) -> void:
	var cells: Array = studio_asset_system.transformed_cells(template, pivot_world, studio_asset_rotation)
	var owned_positions: Array = []
	for raw_cell in cells:
		var cell: Dictionary = raw_cell as Dictionary
		var pos: Vector3i = cell.get("pos", Vector3i.ZERO)
		if not workspace.is_inside_world(pos) or workspace.has_block(pos) or _block_overlaps_creative_player(pos):
			set_status("Asset nao cabe aqui; nenhum bloco foi substituido."); return
		if str(cell.get("kind", "")) != "air": owned_positions.append([pos.x, pos.y, pos.z])
	var commands: Array = []
	for raw_cell in cells:
		var cell: Dictionary = raw_cell as Dictionary
		var pos: Vector3i = cell.get("pos", Vector3i.ZERO)
		var command: Dictionary = {}
		match str(cell.get("kind", "")):
			"block": command = _apply_block_positions([pos], str(cell.get("block_id", "")), false)
			"micro": command = _apply_micro_cell(pos, cell.get("cell", null), false)
		if not command.is_empty(): commands.append(command)
	var before_components: Array = workspace.components.duplicate(true)
	workspace.components.append({"asset_id": template.structure_id, "pos": [pivot_world.x, pivot_world.y, pivot_world.z], "rotation": studio_asset_rotation, "owned_positions": owned_positions})
	commands.append({"type": "components", "before": before_components, "after": workspace.components.duplicate(true)})
	history.push({"type": "batch", "commands": commands})
	set_status("%s colocado como componente; R gira antes de posicionar." % template.display_name)
	if studio_player != null: studio_player.play_place_swing()


func _workspace_component_at(pos: Vector3i) -> Dictionary:
	for raw_component in workspace.components:
		var component: Dictionary = raw_component as Dictionary
		for raw_owned in component.get("owned_positions", []) as Array:
			if StructureTemplateScript._vector3i_from_value(raw_owned) == pos: return component
	return {}


func _remove_workspace_component(component: Dictionary) -> void:
	var positions: Array = []
	for raw_owned in component.get("owned_positions", []) as Array: positions.append(StructureTemplateScript._vector3i_from_value(raw_owned))
	var commands: Array = []
	var voxel_command: Dictionary = _apply_block_positions(positions, "", false)
	if not voxel_command.is_empty(): commands.append(voxel_command)
	var before_components: Array = workspace.components.duplicate(true)
	workspace.components.erase(component)
	commands.append({"type": "components", "before": before_components, "after": workspace.components.duplicate(true)})
	history.push({"type": "batch", "commands": commands})
	set_status("Componente %s removido por inteiro." % str(component.get("asset_id", "")))


func _can_place_full_cell(pos: Vector3i) -> bool:
	if not workspace.is_inside_world(pos): return false
	if workspace.has_block(pos):
		set_status("Espaco ocupado: a celula existente foi preservada.")
		return false
	if _block_overlaps_creative_player(pos):
		set_status("Nao e possivel colocar uma celula dentro do jogador.")
		return false
	return true


func _block_overlaps_creative_player(pos: Vector3i) -> bool:
	if studio_player == null: return false
	var block_box: AABB = AABB(Vector3(pos) - Vector3(0.5, 0.5, 0.5), Vector3.ONE)
	var player_box: AABB = AABB(studio_player.global_position + Vector3(-0.35, 0.0, -0.35), Vector3(0.7, 1.8, 0.7))
	return block_box.intersects(player_box)


func _current_hit():
	if studio_player != null:
		return workspace.raycast_hit(studio_player.get_interaction_ray_start(), studio_player.get_aim_direction(), studio_player.block_reach)
	return workspace.raycast_hit(camera_ray_origin(), camera_ray_direction(), 12.0)


func _use_direct_tool() -> void:
	var hit = _current_hit()
	if hit == null:
		return
	var target: Vector3i = hit.pos + hit.normal
	match tool_option.selected:
		0: _apply_block_positions([target], selected_block())
		1: _apply_block_positions([hit.pos], "")
		9: _set_pivot(target)
		10: _add_marker("foundation", target)
		11: _mark_explicit_air(hit.pos)
		12: _add_marker("connector", target)
		13: _add_marker("entity_spawn", target)


func _set_selection_point(first: bool) -> void:
	var hit = _current_hit()
	if hit == null:
		set_status("Nenhum voxel sob a mira.")
		return
	var point: Vector3i = hit.pos + hit.normal
	if first: selection_a = point
	else: selection_b = point
	_rebuild_markers()
	set_status("Selecao: %s ate %s" % [selection_a, selection_b])


func _execute_selection_tool() -> void:
	var option_by_tool: Dictionary = {"wand": 2, "forms": 3, "brush": 5, "replace": 6, "clone": 7, "marks": 9}
	if option_by_tool.has(active_tool): tool_option.select(int(option_by_tool[active_tool]))
	match tool_option.selected:
		2: _apply_block_positions(_line_positions(selection_a, selection_b), selected_block())
		3: _apply_block_positions(_box_positions(), selected_block())
		4: _apply_block_positions(_ellipsoid_positions(), selected_block())
		5: _apply_block_positions(_selection_positions(), selected_block())
		6: _replace_selection()
		7: _copy_selection()
		8: _paste_clipboard(selection_a)
		9: _set_pivot(selection_a)
		10: _mark_selection("foundation")
		11: _mark_air_selection()
		12: _mark_selection("connector")
		13: _mark_selection("entity_spawn")
		_: set_status("Use esta ferramenta diretamente com LMB.")


func selected_block() -> String:
	return hotbar_blocks[selected_hotbar] if not hotbar_blocks.is_empty() and selected_hotbar < hotbar_blocks.size() else (block_option.get_item_text(block_option.selected) if block_option != null and block_option.item_count > 0 else "stone")


func _filter_block_palette(query: String) -> void:
	if block_option == null:
		return
	var previous: String = selected_block()
	block_option.clear()
	var normalized: String = query.strip_edges().to_lower()
	var block_names: Array = BlockCatalogScript.blocks().keys()
	block_names.sort()
	for block_id in block_names:
		var name: String = str(block_id)
		if normalized == "" or name.to_lower().contains(normalized):
			block_option.add_item(name)
			if name == previous:
				block_option.select(block_option.item_count - 1)
	if block_option.item_count == 0:
		set_status("Nenhum bloco encontrado para '%s'." % query)


func _apply_block_positions(positions: Array, block_id: String, record_history: bool = true) -> Dictionary:
	var changes: Array = []
	var affected: Dictionary = {}
	for raw_pos in positions:
		var pos: Vector3i = raw_pos
		if not workspace.is_inside_world(pos):
			continue
		var before: String = workspace.get_block_id(pos)
		var before_state: Dictionary = _cell_state(pos)
		var before_air: bool = workspace.explicit_air.has(pos)
		var before_meta: Dictionary = workspace.get_metadata(pos)
		if before == block_id and not workspace.has_micro_cell(pos) and not before_air and before_meta.is_empty():
			continue
		if block_id == "": workspace.clear_block(pos)
		else: workspace.set_block(pos, block_id)
		workspace.clear_metadata(pos)
		changes.append({"pos": pos, "before": before, "after": block_id, "before_cell": before_state, "after_cell": _cell_state(pos), "before_air": before_air, "after_air": false, "before_meta": before_meta, "after_meta": {}})
		workspace.explicit_air.erase(pos)
		for section in workspace.get_affected_sections(pos): affected[section] = true
	if changes.is_empty(): return {}
	_deactivate_guide_for_changes(changes)
	if block_id != "":
		for raw_change in changes:
			var changed: Dictionary = raw_change as Dictionary
			var changed_pos: Vector3i = changed.get("pos", GUIDE_POS)
			_include_authored_position(changed_pos)
		_rebuild_markers()
	var command: Dictionary = {"type": "voxels", "changes": changes}
	if record_history: history.push(command)
	section_system.queue_sections(affected.keys(), true)
	if record_history: set_status("%d voxels alterados." % changes.size())
	return command


func _replace_selection() -> void:
	var source: String = workspace.get_block_id(selection_a)
	if source == "":
		set_status("O ponto A precisa conter o bloco que sera substituido.")
		return
	var positions: Array = []
	for pos in _selection_positions():
		if workspace.get_block_id(pos) == source: positions.append(pos)
	_apply_block_positions(positions, selected_block())


func _copy_selection() -> void:
	clipboard_template = workspace.to_template(_selection_min(), _selection_max(), "clipboard", "Clipboard")
	_strip_guide_from_template(clipboard_template)
	set_status("Selecao copiada: %s" % clipboard_template.size)


func _paste_clipboard(origin: Vector3i, record_history: bool = true) -> Dictionary:
	if clipboard_template == null:
		set_status("Clipboard vazio.")
		return {}
	var writes: Dictionary = {}
	for raw_local in clipboard_template.blocks.keys():
		var pos: Vector3i = origin + (raw_local as Vector3i)
		writes[pos] = {"block": str(clipboard_template.blocks[raw_local]), "air": false, "meta": {}}
	for raw_local in clipboard_template.explicit_air.keys():
		var pos: Vector3i = origin + (raw_local as Vector3i)
		writes[pos] = {"block": "", "air": true, "meta": {}}
	for raw_local in clipboard_template.metadata.keys():
		var pos: Vector3i = origin + (raw_local as Vector3i)
		var write: Dictionary = (writes.get(pos, {"block": "", "air": false, "meta": {}}) as Dictionary).duplicate(true)
		write["meta"] = (clipboard_template.metadata[raw_local] as Dictionary).duplicate(true)
		writes[pos] = write
	var changes: Array = []
	var affected: Dictionary = {}
	for raw_pos in writes.keys():
		var pos: Vector3i = raw_pos
		if not workspace.is_inside_world(pos): continue
		var write: Dictionary = writes[pos] as Dictionary
		var before: String = workspace.get_block_id(pos)
		var before_state: Dictionary = _cell_state(pos)
		var before_air: bool = workspace.explicit_air.has(pos)
		var before_meta: Dictionary = workspace.get_metadata(pos)
		var after_block: String = str(write.get("block", ""))
		var after_air: bool = bool(write.get("air", false))
		var after_meta: Dictionary = (write.get("meta", {}) as Dictionary).duplicate(true)
		if after_block == "": workspace.clear_block(pos)
		else: workspace.set_block(pos, after_block)
		if after_air: workspace.explicit_air[pos] = true
		else: workspace.explicit_air.erase(pos)
		workspace.clear_metadata(pos)
		if not after_meta.is_empty(): workspace.set_metadata(pos, after_meta)
		changes.append({"pos": pos, "before": before, "after": after_block, "before_cell": before_state, "after_cell": _cell_state(pos), "before_air": before_air, "after_air": after_air, "before_meta": before_meta, "after_meta": after_meta})
		for section in workspace.get_affected_sections(pos): affected[section] = true
	var commands: Array = []
	if not changes.is_empty():
		_deactivate_guide_for_changes(changes)
		for change in changes:
			var written: Dictionary = change as Dictionary
			if str(written.get("after", "")) != "" or bool(written.get("after_air", false)) or not (written.get("after_meta", {}) as Dictionary).is_empty():
				var written_pos: Vector3i = written.get("pos", GUIDE_POS)
				_include_authored_position(written_pos)
		commands.append({"type": "voxels", "changes": changes})
		section_system.queue_sections(affected.keys(), true)
	for raw_local in clipboard_template.micro_cells.keys():
		var micro_command: Dictionary = _apply_micro_cell(origin + (raw_local as Vector3i), clipboard_template.micro_cells[raw_local], false)
		if not micro_command.is_empty(): commands.append(micro_command)
	if not clipboard_template.markers.is_empty():
		var before_markers: Array = workspace.markers.duplicate(true)
		for raw_marker in clipboard_template.markers:
			var marker: Dictionary = (raw_marker as Dictionary).duplicate(true)
			var raw_pos: Array = marker.get("pos", [0, 0, 0]) as Array
			var pos: Vector3i = origin + Vector3i(int(raw_pos[0]), int(raw_pos[1]), int(raw_pos[2]))
			marker["pos"] = [pos.x, pos.y, pos.z]
			workspace.markers.append(marker)
			_include_authored_position(pos)
		commands.append({"type": "markers", "before": before_markers, "after": workspace.markers.duplicate(true)})
	if not clipboard_template.components.is_empty():
		var before_components: Array = workspace.components.duplicate(true)
		for raw_component in clipboard_template.components:
			var component: Dictionary = (raw_component as Dictionary).duplicate(true)
			var local_component: Vector3i = StructureTemplateScript._vector3i_from_value(component.get("pos", []))
			var component_pos: Vector3i = origin + local_component
			component["pos"] = [component_pos.x, component_pos.y, component_pos.z]
			workspace.components.append(component)
		_materialize_workspace_components()
		commands.append({"type": "components", "before": before_components, "after": workspace.components.duplicate(true)})
	_rebuild_markers()
	if commands.is_empty(): return {}
	var command: Dictionary = commands[0] if commands.size() == 1 else {"type": "batch", "commands": commands}
	if record_history: history.push(command)
	return command


func _transform_selection(rotation: int, mirror_x: bool, mirror_z: bool) -> void:
	_copy_selection()
	if clipboard_template == null: return
	var minimum: Vector3i = _selection_min()
	var maximum: Vector3i = _selection_max()
	var commands: Array = []
	var old: Array = _selection_positions()
	var clear_command: Dictionary = _apply_block_positions(old, "", false)
	if not clear_command.is_empty(): commands.append(clear_command)
	var before_markers: Array = workspace.markers.duplicate(true)
	var kept_markers: Array = []
	for raw_marker in workspace.markers:
		var marker: Dictionary = raw_marker as Dictionary
		var raw_pos: Array = marker.get("pos", [0, 0, 0]) as Array
		var pos: Vector3i = Vector3i(int(raw_pos[0]), int(raw_pos[1]), int(raw_pos[2]))
		if pos.x < minimum.x or pos.x > maximum.x or pos.y < minimum.y or pos.y > maximum.y or pos.z < minimum.z or pos.z > maximum.z:
			kept_markers.append(marker.duplicate(true))
	workspace.markers = kept_markers
	if workspace.markers != before_markers:
		commands.append({"type": "markers", "before": before_markers, "after": workspace.markers.duplicate(true)})
	var before_components: Array = workspace.components.duplicate(true)
	workspace.components = workspace.components.filter(func(raw: Dictionary) -> bool:
		var pos: Vector3i = StructureTemplateScript._vector3i_from_value(raw.get("pos", []))
		return pos.x < minimum.x or pos.x > maximum.x or pos.y < minimum.y or pos.y > maximum.y or pos.z < minimum.z or pos.z > maximum.z
	)
	if workspace.components != before_components: commands.append({"type": "components", "before": before_components, "after": workspace.components.duplicate(true)})
	var transformed = StructureTemplateScript.new()
	transformed.structure_id = "clipboard_transform"
	transformed.display_name = "Clipboard transform"
	transformed.size = clipboard_template.transformed_size(rotation)
	transformed.pivot = clipboard_template.transform_position(clipboard_template.pivot, rotation, mirror_x, mirror_z)
	for raw_pos in clipboard_template.blocks.keys():
		transformed.blocks[clipboard_template.transform_position(raw_pos as Vector3i, rotation, mirror_x, mirror_z)] = clipboard_template.blocks[raw_pos]
	for raw_pos in clipboard_template.explicit_air.keys():
		transformed.explicit_air[clipboard_template.transform_position(raw_pos as Vector3i, rotation, mirror_x, mirror_z)] = true
	for raw_pos in clipboard_template.metadata.keys():
		transformed.metadata[clipboard_template.transform_position(raw_pos as Vector3i, rotation, mirror_x, mirror_z)] = clipboard_template.metadata[raw_pos]
	for raw_pos in clipboard_template.micro_cells.keys():
		transformed.micro_cells[clipboard_template.transform_position(raw_pos as Vector3i, rotation, mirror_x, mirror_z)] = clipboard_template.micro_cells[raw_pos].transformed(rotation, mirror_x, mirror_z)
	for raw_marker in clipboard_template.markers:
		var marker: Dictionary = (raw_marker as Dictionary).duplicate(true)
		var raw_marker_pos: Array = marker.get("pos", [0, 0, 0]) as Array
		var marker_pos: Vector3i = Vector3i(int(raw_marker_pos[0]), int(raw_marker_pos[1]), int(raw_marker_pos[2]))
		var transformed_marker: Vector3i = clipboard_template.transform_position(marker_pos, rotation, mirror_x, mirror_z)
		marker["pos"] = [transformed_marker.x, transformed_marker.y, transformed_marker.z]
		transformed.markers.append(marker)
	for raw_component in clipboard_template.components:
		var component: Dictionary = (raw_component as Dictionary).duplicate(true)
		var component_pos: Vector3i = StructureTemplateScript._vector3i_from_value(component.get("pos", []))
		var transformed_component: Vector3i = clipboard_template.transform_position(component_pos, rotation, mirror_x, mirror_z)
		component["pos"] = [transformed_component.x, transformed_component.y, transformed_component.z]
		component["rotation"] = posmod(int(component.get("rotation", 0)) + rotation, 4)
		transformed.components.append(component)
	clipboard_template = transformed
	selection_b = selection_a + transformed.size - Vector3i.ONE
	var before_pivot: Vector3i = workspace.pivot
	workspace.pivot = selection_a + transformed.pivot
	if workspace.pivot != before_pivot:
		commands.append({"type": "pivot", "before": before_pivot, "after": workspace.pivot})
	var paste_command: Dictionary = _paste_clipboard(selection_a, false)
	if not paste_command.is_empty(): commands.append(paste_command)
	if not commands.is_empty():
		history.push({"type": "batch", "commands": commands})
	_rebuild_markers()
	set_status("Transformacao aplicada como uma operacao de undo.")


func _set_pivot(pos: Vector3i) -> void:
	if not workspace.is_inside_world(pos): return
	var before: Vector3i = workspace.pivot
	workspace.pivot = pos
	_include_authored_position(pos)
	history.push({"type": "pivot", "before": before, "after": pos})
	_rebuild_markers()


func _add_marker(type: String, pos: Vector3i) -> void:
	if not workspace.is_inside_world(pos): return
	var before: Array = workspace.markers.duplicate(true)
	var marker: Dictionary = {"type": type, "pos": [pos.x, pos.y, pos.z], "facing": [0, 0, -1], "block": selected_block()}
	if type == "entity_spawn": marker["entity_id"] = "ghost"
	workspace.markers.append(marker)
	_include_authored_position(pos)
	history.push({"type": "markers", "before": before, "after": workspace.markers.duplicate(true)})
	_rebuild_markers()


func _set_assembly_anchor() -> void:
	var hit = _current_hit()
	if hit == null: return
	var pos: Vector3i = hit.pos
	var before: Array = workspace.markers.duplicate(true)
	workspace.markers = workspace.markers.filter(func(raw: Dictionary) -> bool: return str(raw.get("type", "")) != "anchor")
	workspace.markers.append({"type": "anchor", "pos": [pos.x, pos.y, pos.z]})
	history.push({"type": "markers", "before": before, "after": workspace.markers.duplicate(true)})
	_rebuild_markers(); set_status("Ancora de montagem marcada em %s." % pos)


func _mark_selection(type: String) -> void:
	var before: Array = workspace.markers.duplicate(true)
	for pos in _selection_positions():
		var marker: Dictionary = {"type": type, "pos": [pos.x, pos.y, pos.z], "facing": [0, 0, -1], "block": selected_block()}
		if type == "entity_spawn": marker["entity_id"] = "ghost"
		workspace.markers.append(marker)
	history.push({"type": "markers", "before": before, "after": workspace.markers.duplicate(true)})
	_rebuild_markers()


func _mark_explicit_air(pos: Vector3i) -> void:
	if not workspace.is_inside_world(pos): return
	var before_block: String = workspace.get_block_id(pos)
	var before_state: Dictionary = _cell_state(pos)
	var before_air: bool = workspace.explicit_air.has(pos)
	var before_meta: Dictionary = workspace.get_metadata(pos)
	workspace.clear_block(pos); workspace.explicit_air[pos] = true
	_deactivate_guide_for_changes([{"pos": pos}])
	_include_authored_position(pos)
	history.push({"type": "voxels", "changes": [{"pos": pos, "before": before_block, "after": "", "before_cell": before_state, "after_cell": {"kind": "air"}, "before_air": before_air, "after_air": true, "before_meta": before_meta, "after_meta": {}}]})
	section_system.queue_sections(workspace.get_affected_sections(pos), true)
	_rebuild_markers()


func _mark_air_selection() -> void:
	var changes: Array = []
	var affected: Dictionary = {}
	for raw_pos in _selection_positions():
		var pos: Vector3i = raw_pos
		var before_block: String = workspace.get_block_id(pos)
		var before_state: Dictionary = _cell_state(pos)
		var before_air: bool = workspace.explicit_air.has(pos)
		var before_meta: Dictionary = workspace.get_metadata(pos)
		if before_block == "" and before_air:
			continue
		workspace.clear_block(pos)
		workspace.explicit_air[pos] = true
		changes.append({"pos": pos, "before": before_block, "after": "", "before_cell": before_state, "after_cell": {"kind": "air"}, "before_air": before_air, "after_air": true, "before_meta": before_meta, "after_meta": {}})
		for section in workspace.get_affected_sections(pos): affected[section] = true
	if not changes.is_empty():
		_deactivate_guide_for_changes(changes)
		history.push({"type": "voxels", "changes": changes})
		section_system.queue_sections(affected.keys(), true)
		_rebuild_markers()


func _undo() -> void:
	_apply_history(history.pop_undo(), "before")


func _redo() -> void:
	_apply_history(history.pop_redo(), "after")


func _apply_history(command: Dictionary, side: String) -> void:
	if command.is_empty(): return
	match str(command.get("type", "")):
		"batch":
			var commands: Array = command.get("commands", []) as Array
			if side == "before":
				for index in range(commands.size() - 1, -1, -1):
					_apply_history(commands[index] as Dictionary, side)
			else:
				for raw_command in commands:
					_apply_history(raw_command as Dictionary, side)
		"voxels":
			var affected: Dictionary = {}
			for raw_change in command.get("changes", []) as Array:
				var change: Dictionary = raw_change as Dictionary
				var pos: Vector3i = change["pos"]
				if change.has("%s_cell" % side):
					_restore_cell_state(pos, change["%s_cell" % side] as Dictionary)
				else:
					var block_id: String = str(change[side])
					if block_id == "": workspace.clear_block(pos)
					else: workspace.set_block(pos, block_id)
				if bool(change["%s_air" % side]): workspace.explicit_air[pos] = true
				else: workspace.explicit_air.erase(pos)
				workspace.clear_metadata(pos)
				var metadata: Dictionary = (change.get("%s_meta" % side, {}) as Dictionary).duplicate(true)
				if not metadata.is_empty(): workspace.set_metadata(pos, metadata)
				for section in workspace.get_affected_sections(pos): affected[section] = true
			section_system.queue_sections(affected.keys(), true)
		"micro_cells":
			var affected: Dictionary = {}
			for raw_change in command.get("changes", []) as Array:
				var change: Dictionary = raw_change as Dictionary
				var pos: Vector3i = change.get("pos", Vector3i.ZERO)
				_restore_cell_state(pos, change.get(side, {"kind": "air"}) as Dictionary)
				for section in workspace.get_affected_sections(pos): affected[section] = true
			section_system.queue_sections(affected.keys(), true)
		"markers": workspace.markers = (command[side] as Array).duplicate(true)
		"components": workspace.components = (command[side] as Array).duplicate(true)
		"pivot": workspace.pivot = command[side]
	_rebuild_markers()


func _selection_min() -> Vector3i:
	return Vector3i(min(selection_a.x, selection_b.x), min(selection_a.y, selection_b.y), min(selection_a.z, selection_b.z))


func _selection_max() -> Vector3i:
	return Vector3i(max(selection_a.x, selection_b.x), max(selection_a.y, selection_b.y), max(selection_a.z, selection_b.z))


func _selection_positions() -> Array:
	var result: Array = []
	var minimum: Vector3i = _selection_min(); var maximum: Vector3i = _selection_max()
	for y in range(minimum.y, maximum.y + 1):
		for z in range(minimum.z, maximum.z + 1):
			for x in range(minimum.x, maximum.x + 1): result.append(Vector3i(x, y, z))
	return result


func _box_positions() -> Array:
	return _selection_positions()


func _ellipsoid_positions() -> Array:
	var result: Array = []
	var minimum: Vector3i = _selection_min(); var maximum: Vector3i = _selection_max()
	var center: Vector3 = (Vector3(minimum) + Vector3(maximum)) * 0.5
	var radius: Vector3 = (Vector3(maximum - minimum) + Vector3.ONE) * 0.5
	for pos in _selection_positions():
		var normalized: Vector3 = (Vector3(pos) - center) / radius
		if normalized.length_squared() <= 1.0: result.append(pos)
	return result


func _line_positions(a: Vector3i, b: Vector3i) -> Array:
	var result: Array = []
	var steps: int = maxi(abs(b.x - a.x), maxi(abs(b.y - a.y), abs(b.z - a.z)))
	if steps == 0: return [a]
	for index in range(steps + 1):
		var t: float = float(index) / float(steps)
		var pos: Vector3i = Vector3i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)), roundi(lerpf(a.z, b.z, t)))
		if not result.has(pos): result.append(pos)
	return result


func _export_structure(path: String) -> void:
	var template = _make_current_template()
	var reference_errors: Array[String] = _project_asset_errors(template)
	if not reference_errors.is_empty(): set_status("Falha ao exportar: %s" % "; ".join(reference_errors)); return
	var error: Error = template.save_to_file(path, BlockCatalogScript.blocks())
	set_status("Estrutura exportada: %s" % path if error == OK else "Falha ao exportar: %s" % error_string(error))


func _save_structure_to_project() -> void:
	var template = _make_current_template()
	var errors: Array[String] = template.validate(BlockCatalogScript.blocks())
	errors.append_array(_project_asset_errors(template))
	if not errors.is_empty():
		set_status("Estrutura nao ativada: %s" % "; ".join(errors)); return
	var filename: String = _safe_structure_filename(template.structure_id)
	if filename == "":
		set_status("structure_id precisa conter letras ou numeros."); return
	var absolute_dir: String = ProjectSettings.globalize_path(PROJECT_STRUCTURE_DIR)
	var dir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if dir_error != OK:
		set_status("Projeto nao permite gravar em data/structures: %s" % error_string(dir_error)); return
	var path: String = PROJECT_STRUCTURE_DIR.path_join("%s.tstructure.json" % filename)
	var error: Error = template.save_to_file(path, BlockCatalogScript.blocks())
	if error == OK: _reload_project_assets()
	set_status("Estrutura salva e ativada: %s" % path if error == OK else "Falha ao salvar no projeto: %s" % error_string(error))


func _project_asset_errors(template) -> Array[String]:
	var errors: Array[String] = []
	for raw_component in template.components:
		var component_id: String = str((raw_component as Dictionary).get("asset_id", ""))
		if component_id == template.structure_id: errors.append("Um asset nao pode conter a si mesmo.")
		elif project_asset_registry == null or project_asset_registry.get_asset(component_id) == null: errors.append("Componente desconhecido: %s." % component_id)
	return errors


func _load_structure(path: String) -> void:
	var template = StructureTemplateScript.load_from_file(path)
	if template == null:
		set_status("Template invalido."); return
	guide_active = false
	workspace.load_template(template, Vector3i(0, 1, 0))
	_materialize_workspace_components()
	selection_a = Vector3i(0, 1, 0); selection_b = Vector3i(0, 1, 0) + template.size - Vector3i.ONE
	template_id_edit.text = template.structure_id; template_name_edit.text = template.display_name
	_select_option_metadata(asset_kind_option, template.asset_kind)
	_select_option_metadata(placement_mode_option, template.placement_mode)
	utility_id_edit.text = template.utility_id
	_update_export_controls(asset_kind_option.selected)
	spawn_profiles = template.spawn_profiles.duplicate(true)
	if spawn_profiles.is_empty(): spawn_profiles = [SpawnGraphScript.default_profile(Vector2i.ZERO)]
	history.clear(); section_system.queue_rebuild_all(true); _rebuild_markers()
	_rebuild_graph_profiles(); _rebuild_graph()


func _autosave() -> void:
	var template = _make_current_template()
	if template.validate(BlockCatalogScript.blocks()).is_empty(): template.save_to_file(AUTOSAVE_PATH, BlockCatalogScript.blocks())


func _make_current_template():
	var template = workspace.to_template(_selection_min(), _selection_max(), template_id_edit.text.strip_edges(), template_name_edit.text.strip_edges())
	_strip_guide_from_template(template)
	template.asset_kind = _selected_asset_kind()
	template.placement_mode = _selected_placement_mode()
	template.utility_id = utility_id_edit.text.strip_edges()
	if template.asset_kind == "custom_block": template.pivot = Vector3i.ZERO
	template.spawn_profiles = spawn_profiles.duplicate(true) if template.asset_kind == "structure" else []
	for raw_marker in template.markers:
		var marker: Dictionary = raw_marker as Dictionary
		if str(marker.get("type", "")) == "anchor": template.anchor = StructureTemplateScript._vector3i_from_value(marker.get("pos", []))
	if template.asset_kind == "multiblock" and template.placement_mode == "assembled":
		template.requirements = _assembly_requirements(template)
	return template


func _assembly_requirements(template) -> Array:
	var result: Array = []
	var block_definitions: Dictionary = BlockCatalogScript.blocks()
	for raw_pos in template.blocks.keys():
		var pos: Vector3i = raw_pos
		var block_id: String = str(template.blocks[pos])
		var item_id: String = str((block_definitions.get(block_id, {}) as Dictionary).get("place_item", ""))
		if item_id == "": item_id = block_id
		result.append({"pos": [pos.x, pos.y, pos.z], "item_id": item_id, "block_id": block_id})
	for raw_component in template.components:
		var component: Dictionary = raw_component as Dictionary
		var component_pos: Vector3i = StructureTemplateScript._vector3i_from_value(component.get("pos", []))
		var asset_id: String = str(component.get("asset_id", ""))
		result.append({"pos": [component_pos.x, component_pos.y, component_pos.z], "item_id": asset_id, "asset_id": asset_id, "rotation": posmod(int(component.get("rotation", 0)), 4)})
	return result


func _select_option_metadata(option: OptionButton, value: String) -> void:
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == value: option.select(index); return


func _materialize_workspace_components() -> void:
	for raw_component in workspace.components:
		var component: Dictionary = raw_component as Dictionary
		var template = project_asset_registry.get_asset(str(component.get("asset_id", ""))) if project_asset_registry != null else null
		if template == null: continue
		var pivot_world: Vector3i = StructureTemplateScript._vector3i_from_value(component.get("pos", []))
		var owned: Array = []
		for raw_cell in studio_asset_system.transformed_cells(template, pivot_world, int(component.get("rotation", 0))):
			var cell: Dictionary = raw_cell as Dictionary
			var pos: Vector3i = cell.get("pos", Vector3i.ZERO)
			if not workspace.is_inside_world(pos) or str(cell.get("kind", "")) == "air": continue
			if str(cell.get("kind", "")) == "micro": workspace.set_micro_cell(pos, cell.get("cell", null))
			else: workspace.set_block(pos, str(cell.get("block_id", "")))
			owned.append([pos.x, pos.y, pos.z])
		component["owned_positions"] = owned


func _safe_structure_filename(value: String) -> String:
	var result: String = ""
	for index in range(value.length()):
		var character: String = value.substr(index, 1).to_lower()
		if character >= "a" and character <= "z" or character >= "0" and character <= "9" or character == "_" or character == "-": result += character
		elif character == " ": result += "_"
	return result.strip_edges().trim_prefix("_").trim_suffix("_")


func _show_biome_preview() -> void:
	_refresh_biome_preview(true)


func _refresh_biome_preview(enter_preview: bool) -> void:
	var template = _make_current_template()
	var errors: Array[String] = template.validate(BlockCatalogScript.blocks())
	if not errors.is_empty():
		set_status("Preview indisponivel: %s" % "; ".join(errors)); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://authoring"))
	if template.save_to_file(PREVIEW_PATH, BlockCatalogScript.blocks()) != OK:
		set_status("Nao foi possivel preparar o preview."); return
	var tile = TerrainTileScript.load_from_file(DEFAULT_TILE_PATH)
	if tile == null: tile = TerrainTileScript.create_draft(1235571, Vector2i.ZERO)
	var registry = StructureRegistryScript.empty_registry()
	for raw_profile in template.spawn_profiles:
		var profile: Dictionary = raw_profile as Dictionary; var compiled: Dictionary = SpawnGraphScript.compile(profile)
		registry.embedded_profiles.append({"id": template.structure_id, "path": PREVIEW_PATH, "profile_id": str(profile.get("id", "")), "profile": profile.duplicate(true), "compiled": compiled, "compile_errors": compiled.get("errors", []), "template_hash": template.content_hash(), "embedded": true})
	biome_preview_world = VoxelWorldScript.new(BlockCatalogScript.blocks()); biome_preview_world.reset(tile.draft_seed)
	if texture_array != null: biome_preview_world.configure_texture_layers(texture_array.layer_by_path)
	last_preview_report = TerrainGeneratorScript.new().generate_into(biome_preview_world, tile, registry, tile.draft_seed)
	if biome_preview_sections != null:
		biome_preview_sections.shutdown(); remove_child(biome_preview_sections); biome_preview_sections.queue_free()
	biome_preview_sections = VoxelSectionSystemScript.new(); biome_preview_sections.name = "BiomePreviewSections"; add_child(biome_preview_sections)
	biome_preview_sections.setup(biome_preview_world, Callable(self, "_material_for_surface"), true); biome_preview_sections.queue_rebuild_all(true)
	section_system.visible = false; marker_root.visible = false; biome_preview_active = true
	preview_refresh_pending = false; preview_refresh_elapsed = 0.0
	if enter_preview:
		studio_transform_before_preview = studio_player.transform; studio_player.position = Vector3(50, 72, 118); studio_player.set_view_angles(0.0, deg_to_rad(-28.0))
		graph_panel.visible = false; Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED); studio_player.set_controls_enabled(true); crosshair.visible = true
	_update_graph_counters()
	set_status("Preview Bioma 3D: %s Pressione G e use 'Preview estrutura' para voltar." % last_preview_report.summary())


func _show_structure_preview() -> void:
	if biome_preview_sections != null:
		biome_preview_sections.shutdown(); remove_child(biome_preview_sections); biome_preview_sections.queue_free(); biome_preview_sections = null
	biome_preview_world = null; biome_preview_active = false; section_system.visible = true; marker_root.visible = true
	preview_refresh_pending = false; preview_refresh_elapsed = 0.0
	if studio_player != null and studio_transform_before_preview != Transform3D(): studio_player.transform = studio_transform_before_preview
	graph_panel.visible = false; Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if studio_player != null: studio_player.set_controls_enabled(true)
	crosshair.visible = true; set_status("Preview Estrutura: bounds, pivot, fundacoes e ar explicito no workspace 64x64x64.")


func _rebuild_markers() -> void:
	for child in marker_root.get_children(): child.queue_free()
	if guide_active: _add_marker_visual(GUIDE_POS, Color(0.1, 0.9, 1.0, 0.34), Vector3(1.08, 1.08, 1.08))
	_add_marker_visual(workspace.pivot, Color(1, 0.2, 0.1, 0.8), Vector3(0.65, 1.8, 0.65))
	_add_marker_visual(selection_a, Color(0.1, 1, 0.2, 0.75), Vector3(0.35, 1.2, 0.35))
	_add_marker_visual(selection_b, Color(0.15, 0.45, 1, 0.75), Vector3(0.35, 1.2, 0.35))
	if active_tool in ["wand", "forms", "replace", "clone", "marks"]:
		var minimum: Vector3i = _selection_min(); var maximum: Vector3i = _selection_max()
		_add_marker_visual(Vector3i((minimum.x + maximum.x) / 2, (minimum.y + maximum.y) / 2, (minimum.z + maximum.z) / 2), Color(0.15, 0.75, 1.0, 0.12), Vector3(maximum - minimum + Vector3i.ONE))
	for raw_marker in workspace.markers:
		var marker: Dictionary = raw_marker as Dictionary
		var raw_pos: Array = marker.get("pos", [0, 0, 0]) as Array
		var pos: Vector3i = Vector3i(int(raw_pos[0]), int(raw_pos[1]), int(raw_pos[2]))
		var marker_type: String = str(marker.get("type", ""))
		var color: Color = Color(0.2, 0.85, 1.0, 0.8) if marker_type == "entity_spawn" else (Color(1, 0.7, 0.1, 0.7) if marker_type == "foundation" else Color(0.8, 0.1, 1, 0.7))
		_add_marker_visual(pos, color, Vector3(0.3, 0.8, 0.3))
	for raw_pos in workspace.explicit_air.keys(): _add_marker_visual(raw_pos as Vector3i, Color(0.1, 0.9, 1, 0.24), Vector3(0.8, 0.8, 0.8))


func _add_marker_visual(pos: Vector3i, color: Color, size: Vector3) -> void:
	var node: MeshInstance3D = MeshInstance3D.new(); var mesh: BoxMesh = BoxMesh.new(); mesh.size = size; node.mesh = mesh; node.position = Vector3(pos)
	var material: StandardMaterial3D = StandardMaterial3D.new(); material.albedo_color = color; material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = material; marker_root.add_child(node)


func _labeled(text: String, control: Control) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new(); var label: Label = Label.new(); label.text = text; box.add_child(label); box.add_child(control); return box


func _ensure_input_actions() -> void:
	var keys: Dictionary = {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "jump": KEY_SPACE}
	for action in keys.keys():
		if not InputMap.has_action(action): InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			var event: InputEventKey = InputEventKey.new(); event.physical_keycode = keys[action]; InputMap.action_add_event(action, event)
