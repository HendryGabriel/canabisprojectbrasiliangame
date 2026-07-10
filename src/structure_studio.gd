extends "res://src/authoring_scene_base.gd"

const WorkspaceScript = preload("res://src/structure_workspace.gd")
const StructureTemplateScript = preload("res://src/structure_template_data.gd")
const HistoryScript = preload("res://src/authoring_history.gd")
const PlayerScript = preload("res://src/player.gd")
const VoxelDependencyResolverScript = preload("res://src/voxel_dependency_resolver.gd")
const VoxelDebrisSystemScript = preload("res://src/voxel_debris_system.gd")

const AUTOSAVE_PATH: String = "user://authoring/structure_autosave.tstructure.json"
const BRUSH_PATH: String = "user://authoring/brushes/last_brush.tstructure.json"

var workspace
var history
var tool_option: OptionButton
var block_option: OptionButton
var block_search_edit: LineEdit
var template_id_edit: LineEdit
var template_name_edit: LineEdit
var selection_a: Vector3i = Vector3i(20, 1, 20)
var selection_b: Vector3i = Vector3i(43, 24, 43)
var clipboard_template = null
var export_dialog: FileDialog
var load_dialog: FileDialog
var marker_root: Node3D
var advanced_panel: Control
var creative_inventory_panel: Control
var creative_grid: GridContainer
var creative_search: LineEdit
var creative_category: OptionButton
var hotbar_root: HBoxContainer
var hotbar_blocks: Array[String] = []
var hotbar_buttons: Array[Button] = []
var selected_hotbar: int = 0
var crosshair: Label
var studio_player
var autosave_elapsed: float = 0.0
var voxel_debris


func _ready() -> void:
	right_mouse_toggles_capture = false
	free_camera_controls_enabled = false
	_ensure_input_actions()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://authoring/brushes"))
	workspace = WorkspaceScript.new(BlockCatalogScript.blocks())
	history = HistoryScript.new()
	workspace.pivot = Vector3i(32, 1, 32)
	var autosave = StructureTemplateScript.load_from_file(AUTOSAVE_PATH)
	if autosave != null:
		workspace.load_template(autosave, Vector3i(0, 1, 0))
		selection_a = Vector3i(0, 1, 0)
		selection_b = Vector3i(0, 1, 0) + autosave.size - Vector3i.ONE
	_ensure_visible_workspace_floor()
	setup_authoring_world(workspace, Vector3(32, 8, 52))
	voxel_debris = VoxelDebrisSystemScript.new()
	voxel_debris.name = "VoxelDebris"
	add_child(voxel_debris)
	voxel_debris.configure(BlockCatalogScript.blocks(), 256)
	_create_gameplay_player()
	marker_root = Node3D.new()
	marker_root.name = "StudioMarkers"
	add_child(marker_root)
	_build_ui()
	_build_creative_ui()
	_rebuild_markers()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	set_status("Criativo: E inventario, Tab ferramentas, LMB quebra, RMB coloca, 1-9 hotbar.")


func _ensure_visible_workspace_floor() -> void:
	for x in range(WorkspaceScript.SIZE):
		for z in range(WorkspaceScript.SIZE):
			var pos: Vector3i = Vector3i(x, 0, z)
			if not workspace.has_block(pos): workspace.set_block(pos, "grass")


func _create_gameplay_player() -> void:
	if camera != null:
		camera.current = false
		camera.queue_free()
	studio_player = PlayerScript.new()
	studio_player.name = "CreativePlayer"
	studio_player.creative_flight = true
	studio_player.creative_flight_speed = 12.0
	studio_player.block_reach = 12.0
	studio_player.position = Vector3(32.5, 3.0, 52.5)
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
	autosave_elapsed += delta
	if autosave_elapsed >= 20.0:
		autosave_elapsed = 0.0
		_autosave()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and studio_player != null:
			studio_player.set_controls_enabled(false)
		if event.keycode == KEY_E:
			_toggle_creative_inventory(); get_viewport().set_input_as_handled(); return
		if event.keycode == KEY_TAB:
			_toggle_advanced_tools(); get_viewport().set_input_as_handled(); return
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			_select_hotbar(int(event.keycode - KEY_1)); return
		if event.ctrl_pressed and event.keycode == KEY_Z: _undo(); return
		if event.ctrl_pressed and event.keycode == KEY_Y: _redo(); return
	if event is InputEventMouseButton and event.pressed and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE and not creative_inventory_panel.visible and not advanced_panel.visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED); crosshair.visible = true
		if studio_player != null: studio_player.set_controls_enabled(true)
		return
	super._unhandled_input(event)
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED or creative_inventory_panel.visible or advanced_panel.visible:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT: _creative_break()
		elif event.button_index == MOUSE_BUTTON_RIGHT: _creative_place()
		elif event.button_index == MOUSE_BUTTON_MIDDLE: _creative_pick_block()


func _build_ui() -> void:
	var root: VBoxContainer = make_side_panel("Estudio de Estruturas", 365)
	advanced_panel = root.get_parent().get_parent() as Control
	tool_option = OptionButton.new()
	for label in ["Colocar", "Apagar", "Linha", "Caixa", "Esfera", "Preencher", "Substituir", "Copiar", "Colar", "Pivot", "Fundacao", "Ar explicito", "Conector"]:
		tool_option.add_item(label)
	root.add_child(_labeled("Ferramenta", tool_option))
	block_search_edit = LineEdit.new()
	block_search_edit.placeholder_text = "Buscar bloco..."
	block_search_edit.text_changed.connect(_filter_block_palette)
	root.add_child(block_search_edit)
	block_option = OptionButton.new()
	_filter_block_palette("")
	root.add_child(_labeled("Bloco", block_option))
	template_id_edit = LineEdit.new(); template_id_edit.text = "nova_estrutura"; template_id_edit.placeholder_text = "structure_id"
	template_name_edit = LineEdit.new(); template_name_edit.text = "Nova estrutura"; template_name_edit.placeholder_text = "Nome"
	root.add_child(template_id_edit); root.add_child(template_name_edit)
	var select_row: HBoxContainer = HBoxContainer.new()
	select_row.add_child(make_button("Definir A", func(): _set_selection_point(true)))
	select_row.add_child(make_button("Definir B", func(): _set_selection_point(false)))
	root.add_child(select_row)
	root.add_child(make_button("Executar ferramenta", _execute_selection_tool))
	var transform_row: HBoxContainer = HBoxContainer.new()
	transform_row.add_child(make_button("Girar 90", func(): _transform_selection(1, false, false)))
	transform_row.add_child(make_button("Espelhar X", func(): _transform_selection(0, true, false)))
	transform_row.add_child(make_button("Espelhar Z", func(): _transform_selection(0, false, true)))
	root.add_child(transform_row)
	var history_row: HBoxContainer = HBoxContainer.new()
	history_row.add_child(make_button("Desfazer", _undo)); history_row.add_child(make_button("Refazer", _redo))
	root.add_child(history_row)
	var brush_row: HBoxContainer = HBoxContainer.new()
	brush_row.add_child(make_button("Salvar pincel", _save_brush)); brush_row.add_child(make_button("Carregar pincel", _load_brush))
	root.add_child(brush_row)
	root.add_child(make_button("Carregar estrutura", func(): load_dialog.popup_centered_ratio(0.75)))
	root.add_child(make_button("Exportar estrutura", func(): export_dialog.popup_centered_ratio(0.75)))
	root.add_child(make_button("Voltar ao menu", return_to_main_menu))
	_create_file_dialogs()
	advanced_panel.visible = false


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


func _build_creative_ui() -> void:
	var blocks: Dictionary = BlockCatalogScript.blocks()
	var names: Array = blocks.keys(); names.sort()
	for index in range(mini(9, names.size())): hotbar_blocks.append(str(names[index]))
	while hotbar_blocks.size() < 9: hotbar_blocks.append("stone")

	creative_inventory_panel = PanelContainer.new()
	creative_inventory_panel.set_anchors_preset(Control.PRESET_CENTER)
	creative_inventory_panel.position = Vector2(-365, -260)
	creative_inventory_panel.custom_minimum_size = Vector2(730, 520)
	ui_layer.add_child(creative_inventory_panel)
	var inventory_root: VBoxContainer = VBoxContainer.new()
	inventory_root.add_theme_constant_override("separation", 8)
	creative_inventory_panel.add_child(inventory_root)
	var title: Label = Label.new(); title.text = "Inventario Criativo — todos os blocos"; title.add_theme_font_size_override("font_size", 21)
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
	creative_grid = GridContainer.new(); creative_grid.columns = 8; creative_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(creative_grid)
	var close_hint: Label = Label.new(); close_hint.text = "Clique em um bloco para colocá-lo no slot selecionado. E fecha o inventario."
	inventory_root.add_child(close_hint)
	creative_inventory_panel.visible = false

	var hotbar_panel: PanelContainer = PanelContainer.new()
	hotbar_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar_panel.position = Vector2(-243, -76)
	hotbar_panel.custom_minimum_size = Vector2(486, 62)
	ui_layer.add_child(hotbar_panel)
	hotbar_root = HBoxContainer.new(); hotbar_root.add_theme_constant_override("separation", 3); hotbar_panel.add_child(hotbar_root)
	for index in range(9):
		var button: Button = Button.new(); button.custom_minimum_size = Vector2(50, 50); button.pressed.connect(func(): _select_hotbar(index))
		hotbar_buttons.append(button); hotbar_root.add_child(button)

	crosshair = Label.new(); crosshair.text = "+"; crosshair.add_theme_font_size_override("font_size", 24)
	crosshair.set_anchors_preset(Control.PRESET_CENTER); crosshair.position = Vector2(-7, -15); crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(crosshair)
	_rebuild_creative_grid(); _update_hotbar_ui()


func _rebuild_creative_grid() -> void:
	if creative_grid == null: return
	for child in creative_grid.get_children(): child.queue_free()
	var definitions: Dictionary = BlockCatalogScript.blocks()
	var names: Array = definitions.keys(); names.sort()
	var query: String = creative_search.text.strip_edges().to_lower() if creative_search != null else ""
	var wanted_category: String = creative_category.get_item_text(creative_category.selected).to_lower() if creative_category != null else "todos"
	for raw_id in names:
		var block_id: String = str(raw_id)
		var definition: Dictionary = definitions[block_id] as Dictionary
		var display_name: String = str(definition.get("name", block_id))
		if query != "" and not block_id.to_lower().contains(query) and not display_name.to_lower().contains(query): continue
		if wanted_category != "todos" and _creative_category_for(block_id, definition) != wanted_category: continue
		var button: Button = Button.new(); button.custom_minimum_size = Vector2(76, 76); button.tooltip_text = "%s\n%s" % [display_name, block_id]
		var icon_path: String = str(definition.get("icon", definition.get("texture", "")))
		if icon_path != "" and ResourceLoader.exists(icon_path):
			button.icon = load(icon_path) as Texture2D; button.expand_icon = true
		else: button.text = display_name.left(8)
		button.pressed.connect(func(): _choose_creative_block(block_id))
		creative_grid.add_child(button)


func _creative_category_for(block_id: String, definition: Dictionary) -> String:
	if block_id.ends_with("_ore"): return "minerios"
	if bool(definition.get("plant", false)) or block_id in ["leaves", "short_grass", "wild_grass", "poppy", "dandelion", "cornflower", "oxeye_daisy"]: return "decoracao"
	if block_id in ["grass", "dirt", "wood", "leaves"]: return "natureza"
	if block_id in ["crafting_table", "chest"]: return "utilidade"
	return "construcao"


func _choose_creative_block(block_id: String) -> void:
	hotbar_blocks[selected_hotbar] = block_id
	for index in range(block_option.item_count):
		if block_option.get_item_text(index) == block_id: block_option.select(index); break
	_update_hotbar_ui()
	set_status("%s selecionado no slot %d." % [block_id, selected_hotbar + 1])


func _select_hotbar(index: int) -> void:
	selected_hotbar = clampi(index, 0, 8)
	_update_hotbar_ui()


func _update_hotbar_ui() -> void:
	if hotbar_buttons.is_empty(): return
	var definitions: Dictionary = BlockCatalogScript.blocks()
	for index in range(hotbar_buttons.size()):
		var button: Button = hotbar_buttons[index]
		var block_id: String = hotbar_blocks[index]
		var definition: Dictionary = definitions.get(block_id, {}) as Dictionary
		button.text = str(index + 1)
		button.tooltip_text = str(definition.get("name", block_id))
		button.modulate = Color(1.0, 0.92, 0.45) if index == selected_hotbar else Color.WHITE
		var icon_path: String = str(definition.get("icon", definition.get("texture", "")))
		button.icon = load(icon_path) as Texture2D if icon_path != "" and ResourceLoader.exists(icon_path) else null
		button.expand_icon = true
	_sync_creative_held_item()


func _sync_creative_held_item() -> void:
	if studio_player == null or hotbar_blocks.is_empty(): return
	var block_id: String = hotbar_blocks[selected_hotbar]
	var definition: Dictionary = BlockCatalogScript.blocks().get(block_id, {}) as Dictionary
	var icon_path: String = str(definition.get("icon", definition.get("texture", "")))
	var icon: Texture2D = load(icon_path) as Texture2D if icon_path != "" and ResourceLoader.exists(icon_path) else null
	studio_player.set_held_item(block_id, icon, null)


func _toggle_creative_inventory() -> void:
	creative_inventory_panel.visible = not creative_inventory_panel.visible
	if creative_inventory_panel.visible: advanced_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if creative_inventory_panel.visible else Input.MOUSE_MODE_CAPTURED)
	if studio_player != null: studio_player.set_controls_enabled(not creative_inventory_panel.visible)
	crosshair.visible = not creative_inventory_panel.visible and not advanced_panel.visible


func _toggle_advanced_tools() -> void:
	advanced_panel.visible = not advanced_panel.visible
	if advanced_panel.visible: creative_inventory_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if advanced_panel.visible else Input.MOUSE_MODE_CAPTURED)
	if studio_player != null: studio_player.set_controls_enabled(not advanced_panel.visible)
	crosshair.visible = not advanced_panel.visible


func _creative_break() -> void:
	var hit = _current_hit()
	if hit != null:
		var block_id: String = workspace.get_block_id(hit.pos)
		var removals: Array[Vector3i] = VoxelDependencyResolverScript.collect_removal_positions(workspace, hit.pos, BlockCatalogScript.blocks())
		var command: Dictionary = _apply_block_positions(removals, "")
		if not command.is_empty() and voxel_debris != null:
			voxel_debris.emit_burst(hit.pos, hit.normal, block_id)
		if studio_player != null: studio_player.play_break_finish()


func _creative_place() -> void:
	var hit = _current_hit()
	if hit == null: return
	var target: Vector3i = hit.pos + hit.normal
	if _block_overlaps_creative_player(target):
		set_status("Nao e possivel colocar um bloco dentro do jogador.")
		return
	var block_id: String = hotbar_blocks[selected_hotbar]
	if not VoxelDependencyResolverScript.can_place(workspace, target, block_id, BlockCatalogScript.blocks()):
		set_status("Plantas precisam de um bloco solido abaixo.")
		return
	_apply_block_positions([target], block_id)
	if studio_player != null: studio_player.play_place_swing()


func _creative_pick_block() -> void:
	var hit = _current_hit()
	if hit == null: return
	var block_id: String = workspace.get_block_id(hit.pos)
	var existing: int = hotbar_blocks.find(block_id)
	if existing >= 0: _select_hotbar(existing)
	else: _choose_creative_block(block_id)


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
		_: set_status("Use esta ferramenta diretamente com LMB.")


func selected_block() -> String:
	return block_option.get_item_text(block_option.selected) if block_option != null and block_option.item_count > 0 else "stone"


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
		var before_air: bool = workspace.explicit_air.has(pos)
		var before_meta: Dictionary = workspace.get_metadata(pos)
		if before == block_id and not before_air and before_meta.is_empty():
			continue
		if block_id == "": workspace.clear_block(pos)
		else: workspace.set_block(pos, block_id)
		workspace.clear_metadata(pos)
		changes.append({"pos": pos, "before": before, "after": block_id, "before_air": before_air, "after_air": false, "before_meta": before_meta, "after_meta": {}})
		workspace.explicit_air.erase(pos)
		for section in workspace.get_affected_sections(pos): affected[section] = true
	if changes.is_empty(): return {}
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
		changes.append({"pos": pos, "before": before, "after": after_block, "before_air": before_air, "after_air": after_air, "before_meta": before_meta, "after_meta": after_meta})
		for section in workspace.get_affected_sections(pos): affected[section] = true
	var commands: Array = []
	if not changes.is_empty():
		commands.append({"type": "voxels", "changes": changes})
		section_system.queue_sections(affected.keys(), true)
	if not clipboard_template.markers.is_empty():
		var before_markers: Array = workspace.markers.duplicate(true)
		for raw_marker in clipboard_template.markers:
			var marker: Dictionary = (raw_marker as Dictionary).duplicate(true)
			var raw_pos: Array = marker.get("pos", [0, 0, 0]) as Array
			var pos: Vector3i = origin + Vector3i(int(raw_pos[0]), int(raw_pos[1]), int(raw_pos[2]))
			marker["pos"] = [pos.x, pos.y, pos.z]
			workspace.markers.append(marker)
		commands.append({"type": "markers", "before": before_markers, "after": workspace.markers.duplicate(true)})
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
	for raw_marker in clipboard_template.markers:
		var marker: Dictionary = (raw_marker as Dictionary).duplicate(true)
		var raw_marker_pos: Array = marker.get("pos", [0, 0, 0]) as Array
		var marker_pos: Vector3i = Vector3i(int(raw_marker_pos[0]), int(raw_marker_pos[1]), int(raw_marker_pos[2]))
		var transformed_marker: Vector3i = clipboard_template.transform_position(marker_pos, rotation, mirror_x, mirror_z)
		marker["pos"] = [transformed_marker.x, transformed_marker.y, transformed_marker.z]
		transformed.markers.append(marker)
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
	history.push({"type": "pivot", "before": before, "after": pos})
	_rebuild_markers()


func _add_marker(type: String, pos: Vector3i) -> void:
	if not workspace.is_inside_world(pos): return
	var before: Array = workspace.markers.duplicate(true)
	workspace.markers.append({"type": type, "pos": [pos.x, pos.y, pos.z], "facing": [0, 0, -1], "block": selected_block()})
	history.push({"type": "markers", "before": before, "after": workspace.markers.duplicate(true)})
	_rebuild_markers()


func _mark_selection(type: String) -> void:
	var before: Array = workspace.markers.duplicate(true)
	for pos in _selection_positions():
		workspace.markers.append({"type": type, "pos": [pos.x, pos.y, pos.z], "facing": [0, 0, -1], "block": selected_block()})
	history.push({"type": "markers", "before": before, "after": workspace.markers.duplicate(true)})
	_rebuild_markers()


func _mark_explicit_air(pos: Vector3i) -> void:
	if not workspace.is_inside_world(pos): return
	var before_block: String = workspace.get_block_id(pos)
	var before_air: bool = workspace.explicit_air.has(pos)
	var before_meta: Dictionary = workspace.get_metadata(pos)
	workspace.clear_block(pos); workspace.explicit_air[pos] = true
	history.push({"type": "voxels", "changes": [{"pos": pos, "before": before_block, "after": "", "before_air": before_air, "after_air": true, "before_meta": before_meta, "after_meta": {}}]})
	section_system.queue_sections(workspace.get_affected_sections(pos), true)
	_rebuild_markers()


func _mark_air_selection() -> void:
	var changes: Array = []
	var affected: Dictionary = {}
	for raw_pos in _selection_positions():
		var pos: Vector3i = raw_pos
		var before_block: String = workspace.get_block_id(pos)
		var before_air: bool = workspace.explicit_air.has(pos)
		var before_meta: Dictionary = workspace.get_metadata(pos)
		if before_block == "" and before_air:
			continue
		workspace.clear_block(pos)
		workspace.explicit_air[pos] = true
		changes.append({"pos": pos, "before": before_block, "after": "", "before_air": before_air, "after_air": true, "before_meta": before_meta, "after_meta": {}})
		for section in workspace.get_affected_sections(pos): affected[section] = true
	if not changes.is_empty():
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
		"markers": workspace.markers = (command[side] as Array).duplicate(true)
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
	var template = workspace.to_template(_selection_min(), _selection_max(), template_id_edit.text.strip_edges(), template_name_edit.text.strip_edges())
	var error: Error = template.save_to_file(path, BlockCatalogScript.blocks())
	set_status("Estrutura exportada: %s" % path if error == OK else "Falha ao exportar: %s" % error_string(error))


func _load_structure(path: String) -> void:
	var template = StructureTemplateScript.load_from_file(path)
	if template == null:
		set_status("Template invalido."); return
	workspace.load_template(template, Vector3i(0, 1, 0))
	_ensure_visible_workspace_floor()
	selection_a = Vector3i(0, 1, 0); selection_b = Vector3i(0, 1, 0) + template.size - Vector3i.ONE
	template_id_edit.text = template.structure_id; template_name_edit.text = template.display_name
	history.clear(); section_system.queue_rebuild_all(true); _rebuild_markers()


func _autosave() -> void:
	var template = workspace.to_template(_selection_min(), _selection_max(), template_id_edit.text.strip_edges(), template_name_edit.text.strip_edges())
	if template.validate(BlockCatalogScript.blocks()).is_empty(): template.save_to_file(AUTOSAVE_PATH, BlockCatalogScript.blocks())


func _save_brush() -> void:
	_copy_selection()
	if clipboard_template != null:
		clipboard_template.structure_id = "last_brush"; clipboard_template.display_name = "Ultimo pincel"
		clipboard_template.save_to_file(BRUSH_PATH, BlockCatalogScript.blocks())
		set_status("Pincel salvo.")


func _load_brush() -> void:
	clipboard_template = StructureTemplateScript.load_from_file(BRUSH_PATH)
	set_status("Pincel carregado." if clipboard_template != null else "Nenhum pincel salvo.")


func _rebuild_markers() -> void:
	for child in marker_root.get_children(): child.queue_free()
	_add_marker_visual(workspace.pivot, Color(1, 0.2, 0.1, 0.8), Vector3(0.65, 1.8, 0.65))
	_add_marker_visual(selection_a, Color(0.1, 1, 0.2, 0.75), Vector3(0.35, 1.2, 0.35))
	_add_marker_visual(selection_b, Color(0.15, 0.45, 1, 0.75), Vector3(0.35, 1.2, 0.35))
	for raw_marker in workspace.markers:
		var marker: Dictionary = raw_marker as Dictionary
		var raw_pos: Array = marker.get("pos", [0, 0, 0]) as Array
		var pos: Vector3i = Vector3i(int(raw_pos[0]), int(raw_pos[1]), int(raw_pos[2]))
		var color: Color = Color(1, 0.7, 0.1, 0.7) if str(marker.get("type", "")) == "foundation" else Color(0.8, 0.1, 1, 0.7)
		_add_marker_visual(pos, color, Vector3(0.3, 0.8, 0.3))
	for raw_pos in workspace.explicit_air.keys(): _add_marker_visual(raw_pos as Vector3i, Color(0.1, 0.9, 1, 0.24), Vector3(0.8, 0.8, 0.8))


func _add_marker_visual(pos: Vector3i, color: Color, size: Vector3) -> void:
	var node: MeshInstance3D = MeshInstance3D.new(); var mesh: BoxMesh = BoxMesh.new(); mesh.size = size; node.mesh = mesh; node.position = Vector3(pos)
	var material: StandardMaterial3D = StandardMaterial3D.new(); material.albedo_color = color; material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = material; marker_root.add_child(node)


func _labeled(text: String, control: Control) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new(); var label: Label = Label.new(); label.text = text; box.add_child(label); box.add_child(control); return box


func _ensure_input_actions() -> void:
	var keys: Dictionary = {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D}
	for action in keys.keys():
		if not InputMap.has_action(action): InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			var event: InputEventKey = InputEventKey.new(); event.physical_keycode = keys[action]; InputMap.action_add_event(action, event)
