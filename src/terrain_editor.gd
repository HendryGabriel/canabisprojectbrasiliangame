extends "res://src/authoring_scene_base.gd"

const VoxelWorldScript = preload("res://src/voxel_world.gd")
const TerrainTileScript = preload("res://src/terrain_tile_data.gd")
const TerrainGeneratorScript = preload("res://src/terrain_generator.gd")
const StructureRegistryScript = preload("res://src/structure_registry.gd")
const StructureTemplateScript = preload("res://src/structure_template_data.gd")
const HistoryScript = preload("res://src/authoring_history.gd")
const TerrainMap2DScript = preload("res://src/terrain_map_2d.gd")

const DEFAULT_TILE: String = "res://data/terrain/biome_1.tterrain.json"
const AUTOSAVE_PATH: String = "user://authoring/terrain_autosave.tterrain.json"

var tile
var generator
var registry
var history
var tool_option: OptionButton
var profile_option: OptionButton
var zone_option: OptionButton
var overlay_option: OptionButton
var map_mode_option: OptionButton
var cave_tool_option: OptionButton
var network_option: OptionButton
var slice_y_slider: HSlider
var node_y_slider: HSlider
var node_radius_slider: HSlider
var radius_slider: HSlider
var strength_slider: HSlider
var paint_value_slider: HSlider
var template_id_edit: LineEdit
var export_dialog: FileDialog
var load_dialog: FileDialog
var overlay_instance: MultiMeshInstance3D
var anchor_root: Node3D
var map_2d
var showing_2d: bool = true
var selected_cave_node: String = ""
var connect_from_node: String = ""
var flatten_height: int = 0
var stroke_serial: int = 0
var stroke_active: bool = false
var stroke_changes: Dictionary = {}
var autosave_elapsed: float = 0.0


func _ready() -> void:
	_ensure_input_actions()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://authoring"))
	tile = TerrainTileScript.load_from_file(AUTOSAVE_PATH)
	if tile == null:
		tile = TerrainTileScript.load_from_file(DEFAULT_TILE)
	if tile == null:
		tile = TerrainTileScript.create_draft(1235571, Vector2i.ZERO)
	registry = StructureRegistryScript.load_from_file("res://data/structures/registry.json")
	if registry == null:
		registry = StructureRegistryScript.empty_registry()
	generator = TerrainGeneratorScript.new()
	history = HistoryScript.new()
	var world = VoxelWorldScript.new(BlockCatalogScript.blocks())
	world.reset(tile.draft_seed)
	generator.generate_into(world, tile, registry, tile.draft_seed)
	setup_authoring_world(world, Vector3(50, 82, 128))
	anchor_root = Node3D.new()
	anchor_root.name = "AnchorPreviews"
	add_child(anchor_root)
	_build_ui()
	_create_2d_map()
	_rebuild_overlay()
	_rebuild_anchor_previews()
	set_status("RMB olha; WASD/Q/E voam; clique esquerdo aplica o pincel.")


func _process(delta: float) -> void:
	super._process(delta)
	autosave_elapsed += delta
	if autosave_elapsed >= 20.0:
		autosave_elapsed = 0.0
		tile.save_to_file(AUTOSAVE_PATH)


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			stroke_active = true
			stroke_serial += 1
			stroke_changes.clear()
			_apply_brush_from_camera()
		else:
			_finish_stroke()
	elif event is InputEventMouseMotion and stroke_active and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_apply_brush_from_camera()
	elif event is InputEventKey and event.pressed and event.ctrl_pressed:
		if event.keycode == KEY_Z:
			_undo()
		elif event.keycode == KEY_Y:
			_redo()


func _build_ui() -> void:
	var root: VBoxContainer = make_side_panel("Editor de Terreno", 350)
	root.add_child(make_button("Alternar Mapa 2D / Preview 3D", _toggle_2d_preview))
	map_mode_option = OptionButton.new()
	for label in ["Altura", "Perfis", "Densidade", "Zonas", "Redes", "Camada Y"]:
		map_mode_option.add_item(label)
	map_mode_option.item_selected.connect(_on_map_mode_selected)
	root.add_child(_labeled("Visualizacao 2D", map_mode_option))
	slice_y_slider = _slider(-64, 96, 0, 1)
	slice_y_slider.value_changed.connect(_on_slice_y_changed)
	root.add_child(_labeled("Camada Y", slice_y_slider))
	tool_option = OptionButton.new()
	for label in ["Elevar", "Baixar", "Suavizar", "Achatar", "Ruido", "Perfil", "Cavernas", "Zona", "Protecao", "Entrada", "Ancora"]:
		tool_option.add_item(label)
	root.add_child(_labeled("Ferramenta", tool_option))
	radius_slider = _slider(1, 12, 4, 1)
	root.add_child(_labeled("Raio", radius_slider))
	strength_slider = _slider(1, 8, 2, 1)
	root.add_child(_labeled("Forca", strength_slider))
	paint_value_slider = _slider(0, 255, 160, 1)
	root.add_child(_labeled("Valor de pintura", paint_value_slider))
	profile_option = OptionButton.new()
	profile_option.add_item("Grama", TerrainTileScript.PROFILE_GRASS)
	profile_option.add_item("Rocha", TerrainTileScript.PROFILE_ROCK)
	profile_option.add_item("Terra", TerrainTileScript.PROFILE_DIRT)
	profile_option.add_item("Pradaria", TerrainTileScript.PROFILE_MEADOW)
	root.add_child(_labeled("Perfil", profile_option))
	zone_option = OptionButton.new()
	zone_option.add_item("Estruturas", TerrainTileScript.ZONE_STRUCTURES)
	zone_option.add_item("Floresta", TerrainTileScript.ZONE_FOREST)
	zone_option.add_item("Decoracao", TerrainTileScript.ZONE_DECORATION)
	zone_option.add_item("Sem cavernas", TerrainTileScript.ZONE_NO_CAVES)
	root.add_child(_labeled("Flag de zona", zone_option))
	overlay_option = OptionButton.new()
	overlay_option.add_item("Perfis")
	overlay_option.add_item("Cavernas")
	overlay_option.add_item("Zonas")
	overlay_option.item_selected.connect(func(_index: int): _rebuild_overlay())
	root.add_child(_labeled("Overlay", overlay_option))
	cave_tool_option = OptionButton.new()
	for label in ["Selecionar/Mover", "Adicionar rota", "Adicionar entrada", "Adicionar camara", "Conectar", "Excluir", "Escavar voxel", "Preencher voxel"]:
		cave_tool_option.add_item(label)
	root.add_child(_labeled("Ferramenta de rede", cave_tool_option))
	network_option = OptionButton.new()
	network_option.item_selected.connect(_on_network_selected)
	root.add_child(_labeled("Rede ativa", network_option))
	root.add_child(make_button("Nova rede", _add_cave_network))
	node_y_slider = _slider(-64, 96, -8, 1)
	node_y_slider.drag_ended.connect(func(changed: bool): if changed: _apply_selected_node_controls())
	root.add_child(_labeled("Y do no", node_y_slider))
	node_radius_slider = _slider(2, 9, 4, 1)
	node_radius_slider.drag_ended.connect(func(changed: bool): if changed: _apply_selected_node_controls())
	root.add_child(_labeled("Raio do no", node_radius_slider))
	template_id_edit = LineEdit.new()
	template_id_edit.placeholder_text = "template_id para ancora"
	root.add_child(template_id_edit)
	var history_row: HBoxContainer = HBoxContainer.new()
	history_row.add_child(make_button("Desfazer", _undo))
	history_row.add_child(make_button("Refazer", _redo))
	root.add_child(history_row)
	root.add_child(make_button("Novo rascunho", _new_draft))
	root.add_child(make_button("Carregar tile", func(): load_dialog.popup_centered_ratio(0.75)))
	root.add_child(make_button("Exportar tile", func(): export_dialog.popup_centered_ratio(0.75)))
	root.add_child(make_button("Voltar ao menu", return_to_main_menu))
	_create_file_dialogs()
	_rebuild_network_options()


func _create_2d_map() -> void:
	map_2d = TerrainMap2DScript.new()
	map_2d.name = "TerrainMap2D"
	map_2d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_2d.offset_left = 375
	map_2d.offset_top = 12
	map_2d.offset_right = -12
	map_2d.offset_bottom = -12
	map_2d.set_tile(tile)
	map_2d.cell_input.connect(_on_map_cell_input)
	map_2d.node_clicked.connect(_on_map_node_clicked)
	ui_layer.add_child(map_2d)
	_set_2d_visible(true)


func _toggle_2d_preview() -> void:
	_set_2d_visible(not showing_2d)


func _set_2d_visible(value: bool) -> void:
	showing_2d = value
	if map_2d != null: map_2d.visible = value
	if section_system != null: section_system.visible = not value
	if overlay_instance != null: overlay_instance.visible = not value
	if anchor_root != null: anchor_root.visible = not value
	if value: Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_status("Mapa 2D ativo: roda aplica zoom, botao do meio move." if value else "Preview 3D ativo: RMB captura a camera.")


func _on_map_mode_selected(index: int) -> void:
	if map_2d == null: return
	var modes: Array[String] = ["height", "profile", "cave_density", "zones", "networks", "slice"]
	map_2d.set_view_mode(modes[clampi(index, 0, modes.size() - 1)])


func _on_slice_y_changed(value: float) -> void:
	if map_2d != null: map_2d.set_slice_y(int(value))


func _on_network_selected(index: int) -> void:
	selected_cave_node = ""
	connect_from_node = ""
	if map_2d != null:
		map_2d.selected_network = index
		map_2d.selected_node_id = ""
		map_2d.refresh()


func _on_map_cell_input(cell: Vector2i, phase: int) -> void:
	if map_2d.view_mode in ["networks", "slice"]:
		if phase == 0: _handle_cave_map_cell(cell)
		return
	if phase == 0:
		stroke_active = true; stroke_serial += 1; stroke_changes.clear()
		_apply_brush_at_cell(cell.x, cell.y)
	elif phase == 1 and stroke_active:
		_apply_brush_at_cell(cell.x, cell.y)
	elif phase == 2:
		_finish_stroke()


func _handle_cave_map_cell(cell: Vector2i) -> void:
	if tile.cave_networks.is_empty(): _add_cave_network()
	var network_index: int = clampi(network_option.selected, 0, tile.cave_networks.size() - 1)
	var tool: int = cave_tool_option.selected
	if tool == 0 and selected_cave_node != "":
		var before: Array = tile.cave_networks.duplicate(true)
		var node: Dictionary = _find_cave_node(network_index, selected_cave_node)
		if not node.is_empty():
			var pos: Vector3i = TerrainTileScript._vector3i_from_value(node.get("pos", []))
			node["pos"] = [cell.x, pos.y, cell.y]
			_commit_cave_network_change(before, "No movido para %s." % cell)
		return
	if tool >= 1 and tool <= 3:
		var before: Array = tile.cave_networks.duplicate(true)
		var network: Dictionary = tile.cave_networks[network_index] as Dictionary
		var node_type: String = ["route", "route", "entrance", "chamber"][tool]
		var node_id: String = _next_node_id(network)
		var y: int = tile.get_height(cell.x, cell.y) + 1 if node_type == "entrance" else int(node_y_slider.value)
		var radius: int = clampi(int(node_radius_slider.value), 2, 7) if node_type == "entrance" else clampi(int(node_radius_slider.value), 3, 9)
		(network.get("nodes", []) as Array).append({"id": node_id, "pos": [cell.x, y, cell.y], "radius": radius, "type": node_type})
		selected_cave_node = node_id
		_commit_cave_network_change(before, "No %s adicionado." % node_id)
		return
	if tool == 6 or tool == 7:
		var before: Dictionary = tile.cave_overrides.duplicate(true)
		var target_key: String = "carve" if tool == 6 else "fill"
		var opposite_key: String = "fill" if tool == 6 else "carve"
		var target: Array = tile.cave_overrides.get(target_key, []) as Array
		var opposite: Array = tile.cave_overrides.get(opposite_key, []) as Array
		var radius: int = int(radius_slider.value)
		for z in range(cell.y - radius, cell.y + radius + 1):
			for x in range(cell.x - radius, cell.x + radius + 1):
				if tile.index_of(x, z) < 0 or Vector2(x - cell.x, z - cell.y).length() > radius: continue
				var row: Array = [x, int(slice_y_slider.value), z]
				if not target.has(row): target.append(row)
				if opposite.has(row): opposite.erase(row)
		tile.cave_overrides[target_key] = target; tile.cave_overrides[opposite_key] = opposite
		history.push({"type": "cave_overrides", "before": before, "after": tile.cave_overrides.duplicate(true)})
		_regenerate_all()
		set_status("Correcao %s aplicada na camada Y=%d." % [target_key, int(slice_y_slider.value)])


func _on_map_node_clicked(network_index: int, node_id: String) -> void:
	network_option.select(network_index)
	if map_2d != null: map_2d.selected_network = network_index
	var tool: int = cave_tool_option.selected
	if tool == 4:
		if connect_from_node == "":
			connect_from_node = node_id; selected_cave_node = node_id
			set_status("Primeiro no selecionado; escolha o destino.")
		else:
			var before: Array = tile.cave_networks.duplicate(true)
			var network: Dictionary = tile.cave_networks[network_index] as Dictionary
			var edge: Array = [connect_from_node, node_id]
			if connect_from_node != node_id and not (network.get("edges", []) as Array).has(edge):
				(network.get("edges", []) as Array).append(edge)
			connect_from_node = ""
			_commit_cave_network_change(before, "Aresta conectada.")
		return
	if tool == 5:
		_delete_cave_node(network_index, node_id)
		return
	selected_cave_node = node_id
	if map_2d != null:
		map_2d.selected_node_id = node_id; map_2d.refresh()
	_sync_selected_node_controls()


func _add_cave_network() -> void:
	var before: Array = tile.cave_networks.duplicate(true)
	var serial: int = tile.cave_networks.size() + 1
	tile.cave_networks.append({"id": "network_%d" % serial, "name": "Rede %d" % serial, "nodes": [], "edges": []})
	_commit_cave_network_change(before, "Nova rede criada.")
	network_option.select(tile.cave_networks.size() - 1)
	_on_network_selected(tile.cave_networks.size() - 1)


func _delete_cave_node(network_index: int, node_id: String) -> void:
	var before: Array = tile.cave_networks.duplicate(true)
	var network: Dictionary = tile.cave_networks[network_index] as Dictionary
	var nodes: Array = network.get("nodes", []) as Array
	for index in range(nodes.size() - 1, -1, -1):
		if str((nodes[index] as Dictionary).get("id", "")) == node_id: nodes.remove_at(index)
	var kept_edges: Array = []
	for raw_edge in network.get("edges", []) as Array:
		var endpoints: PackedStringArray = TerrainTileScript._edge_endpoints(raw_edge)
		if endpoints.size() == 2 and endpoints[0] != node_id and endpoints[1] != node_id: kept_edges.append(raw_edge)
	network["edges"] = kept_edges
	selected_cave_node = ""; connect_from_node = ""
	_commit_cave_network_change(before, "No removido.")


func _apply_selected_node_controls() -> void:
	if selected_cave_node == "" or tile.cave_networks.is_empty(): return
	var network_index: int = clampi(network_option.selected, 0, tile.cave_networks.size() - 1)
	var node: Dictionary = _find_cave_node(network_index, selected_cave_node)
	if node.is_empty(): return
	var before: Array = tile.cave_networks.duplicate(true)
	var pos: Vector3i = TerrainTileScript._vector3i_from_value(node.get("pos", []))
	node["pos"] = [pos.x, int(node_y_slider.value), pos.z]
	var is_entry: bool = str(node.get("type", "route")) == "entrance"
	node["radius"] = clampi(int(node_radius_slider.value), 2, 7) if is_entry else clampi(int(node_radius_slider.value), 3, 9)
	_commit_cave_network_change(before, "No atualizado.")


func _sync_selected_node_controls() -> void:
	if selected_cave_node == "" or tile.cave_networks.is_empty(): return
	var node: Dictionary = _find_cave_node(network_option.selected, selected_cave_node)
	if node.is_empty(): return
	var pos: Vector3i = TerrainTileScript._vector3i_from_value(node.get("pos", []))
	node_y_slider.set_value_no_signal(pos.y)
	node_radius_slider.set_value_no_signal(int(node.get("radius", 4)))


func _find_cave_node(network_index: int, node_id: String) -> Dictionary:
	if network_index < 0 or network_index >= tile.cave_networks.size(): return {}
	var network: Dictionary = tile.cave_networks[network_index] as Dictionary
	for raw_node in network.get("nodes", []) as Array:
		var node: Dictionary = raw_node as Dictionary
		if str(node.get("id", "")) == node_id: return node
	return {}


func _next_node_id(network: Dictionary) -> String:
	var used: Dictionary = {}
	for raw_node in network.get("nodes", []) as Array: used[str((raw_node as Dictionary).get("id", ""))] = true
	var serial: int = 0
	while used.has("n%d" % serial): serial += 1
	return "n%d" % serial


func _commit_cave_network_change(before: Array, message: String) -> void:
	history.push({"type": "cave_networks", "before": before, "after": tile.cave_networks.duplicate(true)})
	_rebuild_network_options()
	_regenerate_all()
	if map_2d != null:
		map_2d.selected_node_id = selected_cave_node; map_2d.refresh()
	set_status(message)


func _rebuild_network_options() -> void:
	if network_option == null: return
	var previous: int = network_option.selected
	network_option.clear()
	for raw_network in tile.cave_networks:
		var network: Dictionary = raw_network as Dictionary
		network_option.add_item(str(network.get("name", network.get("id", "Rede"))))
	if network_option.item_count > 0: network_option.select(clampi(previous, 0, network_option.item_count - 1))


func _create_file_dialogs() -> void:
	export_dialog = FileDialog.new()
	export_dialog.title = "Exportar Terrain Tile"
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.filters = PackedStringArray(["*.tterrain.json ; Truman Terrain Tile"])
	export_dialog.file_selected.connect(_export_tile)
	ui_layer.add_child(export_dialog)
	load_dialog = FileDialog.new()
	load_dialog.title = "Carregar Terrain Tile"
	load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	load_dialog.filters = PackedStringArray(["*.tterrain.json ; Truman Terrain Tile"])
	load_dialog.file_selected.connect(_load_tile)
	ui_layer.add_child(load_dialog)


func _apply_brush_from_camera() -> void:
	var hit = authoring_world.raycast_hit(camera_ray_origin(), camera_ray_direction(), 256.0)
	if hit == null:
		return
	var center_x: int = hit.pos.x - tile.tile_coord.x * TerrainTileScript.TILE_SIZE
	var center_z: int = hit.pos.z - tile.tile_coord.y * TerrainTileScript.TILE_SIZE
	if tile.index_of(center_x, center_z) < 0:
		return
	_apply_brush_at_cell(center_x, center_z)


func _apply_brush_at_cell(center_x: int, center_z: int) -> void:
	if tile.index_of(center_x, center_z) < 0:
		return
	if tool_option.selected == 9:
		var before_networks: Array = tile.cave_networks.duplicate(true)
		var serial: int = tile.cave_networks.size() + 1
		var prefix: String = "entrance_%d" % serial
		var surface_y: int = tile.get_height(center_x, center_z)
		var entry_radius: int = clampi(int(radius_slider.value), 2, 7)
		tile.cave_networks.append({
			"id": prefix, "name": "Entrada %d" % serial,
			"nodes": [
				{"id": "%s_a" % prefix, "pos": [center_x, surface_y + 1, center_z], "radius": entry_radius, "type": "entrance"},
				{"id": "%s_b" % prefix, "pos": [center_x, maxi(-61, surface_y - int(strength_slider.value) * 4), center_z], "radius": maxi(3, entry_radius), "type": "route"},
			],
			"edges": [["%s_a" % prefix, "%s_b" % prefix]],
		})
		history.push({"type": "cave_networks", "before": before_networks, "after": tile.cave_networks.duplicate(true)})
		_rebuild_network_options()
		_regenerate_all()
		set_status("Entrada de caverna adicionada.")
		stroke_active = false
		return
	if tool_option.selected == 10:
		var template_id: String = template_id_edit.text.strip_edges()
		if template_id == "":
			set_status("Informe um template_id para a ancora.")
			return
		var before_anchors: Array = tile.anchors.duplicate(true)
		tile.anchors.append({"template_id": template_id, "x": center_x, "z": center_z, "rotation": 0, "mode": "surface_adaptive"})
		history.push({"type": "anchors", "before": before_anchors, "after": tile.anchors.duplicate(true)})
		_rebuild_anchor_previews()
		set_status("Ancora %s adicionada." % template_id)
		stroke_active = false
		return
	if tool_option.selected == 3 and stroke_changes.is_empty():
		flatten_height = tile.get_height(center_x, center_z)
	var radius: int = int(radius_slider.value)
	var changes: Array = []
	var affected_indices: Array = []
	for z in range(center_z - radius, center_z + radius + 1):
		for x in range(center_x - radius, center_x + radius + 1):
			var index: int = tile.index_of(x, z)
			if index < 0:
				continue
			var distance: float = Vector2(float(x - center_x), float(z - center_z)).length()
			if distance > float(radius):
				continue
			var falloff: float = clampf(1.0 - distance / float(radius + 1), 0.08, 1.0)
			var before: Array = _cell_state(index)
			_apply_tool_to_cell(x, z, index, falloff)
			var after: Array = _cell_state(index)
			if before != after:
				if not stroke_changes.has(index):
					stroke_changes[index] = {"index": index, "before": before, "after": after}
				else:
					(stroke_changes[index] as Dictionary)["after"] = after
				changes.append(stroke_changes[index])
				affected_indices.append(index)
	if changes.is_empty():
		return
	_rebuild_changed_columns(affected_indices)
	set_status("Pincel ativo: %d celulas unicas." % stroke_changes.size())


func _finish_stroke() -> void:
	if not stroke_active:
		return
	stroke_active = false
	var changes: Array = []
	for raw_change in stroke_changes.values():
		var change: Dictionary = raw_change as Dictionary
		if change.get("before", []) != change.get("after", []):
			changes.append(change)
	stroke_changes.clear()
	if changes.is_empty():
		return
	history.push({"type": "cells", "changes": changes})
	set_status("Stroke concluido: %d celulas. Autosave ativo." % changes.size())


func _apply_tool_to_cell(x: int, z: int, index: int, falloff: float) -> void:
	var amount: int = maxi(1, int(round(strength_slider.value * falloff)))
	match tool_option.selected:
		0: tile.heights[index] = clampi(int(tile.heights[index]) + amount, TerrainTileScript.MIN_SURFACE_Y, TerrainTileScript.MAX_SURFACE_Y)
		1: tile.heights[index] = clampi(int(tile.heights[index]) - amount, TerrainTileScript.MIN_SURFACE_Y, TerrainTileScript.MAX_SURFACE_Y)
		2:
			var total: int = 0
			var count: int = 0
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var neighbor: int = tile.index_of(x + dx, z + dz)
					if neighbor >= 0:
						total += int(tile.heights[neighbor]); count += 1
			tile.heights[index] = int(round(lerpf(float(tile.heights[index]), float(total) / float(count), falloff)))
		3: tile.heights[index] = int(round(lerpf(float(tile.heights[index]), float(flatten_height), falloff)))
		4:
			var noise: float = sin(float(x * 31 + z * 17 + stroke_serial * 13))
			tile.heights[index] = clampi(int(tile.heights[index]) + int(round(noise * float(amount))), TerrainTileScript.MIN_SURFACE_Y, TerrainTileScript.MAX_SURFACE_Y)
		5: tile.surface_profiles[index] = profile_option.get_selected_id()
		6: tile.cave_density[index] = clampi(int(paint_value_slider.value * falloff), 0, 255)
		7:
			var flag: int = zone_option.get_selected_id()
			tile.zone_flags[index] = int(tile.zone_flags[index]) & ~flag if Input.is_key_pressed(KEY_SHIFT) else int(tile.zone_flags[index]) | flag
		8:
			if Input.is_key_pressed(KEY_SHIFT): tile.zone_flags[index] = int(tile.zone_flags[index]) & ~TerrainTileScript.ZONE_PROTECTED
			else: tile.zone_flags[index] = int(tile.zone_flags[index]) | TerrainTileScript.ZONE_PROTECTED


func _cell_state(index: int) -> Array:
	return [int(tile.heights[index]), int(tile.surface_profiles[index]), int(tile.cave_density[index]), int(tile.zone_flags[index])]


func _set_cell_state(index: int, state: Array) -> void:
	tile.heights[index] = int(state[0])
	tile.surface_profiles[index] = int(state[1])
	tile.cave_density[index] = int(state[2])
	tile.zone_flags[index] = int(state[3])


func _undo() -> void:
	var command: Dictionary = history.pop_undo()
	_apply_history(command, "before")


func _redo() -> void:
	var command: Dictionary = history.pop_redo()
	_apply_history(command, "after")


func _apply_history(command: Dictionary, side: String) -> void:
	if command.is_empty():
		return
	if str(command.get("type", "")) == "entrances":
		tile.cave_entrances = (command[side] as Array).duplicate(true)
		_regenerate_all()
		return
	if str(command.get("type", "")) == "anchors":
		tile.anchors = (command[side] as Array).duplicate(true)
		_rebuild_anchor_previews()
		return
	if str(command.get("type", "")) == "cave_networks":
		tile.cave_networks = (command[side] as Array).duplicate(true)
		selected_cave_node = ""; connect_from_node = ""
		_rebuild_network_options(); _regenerate_all()
		return
	if str(command.get("type", "")) == "cave_overrides":
		tile.cave_overrides = (command[side] as Dictionary).duplicate(true)
		_regenerate_all()
		return
	var affected: Array = []
	for raw_change in command.get("changes", []) as Array:
		var change: Dictionary = raw_change as Dictionary
		var index: int = int(change["index"])
		_set_cell_state(index, change[side] as Array)
		affected.append(index)
	_rebuild_changed_columns(affected)


func _rebuild_changed_columns(indices: Array) -> void:
	var unique: Dictionary = {}
	for index in indices: unique[int(index)] = true
	var affected_sections: Array = generator.regenerate_columns(authoring_world, tile, unique.keys(), tile.draft_seed)
	section_system.queue_sections(affected_sections, true)
	_rebuild_overlay()
	_rebuild_anchor_previews()
	if map_2d != null: map_2d.refresh()


func _new_draft() -> void:
	tile = TerrainTileScript.create_draft(int(Time.get_unix_time_from_system()), tile.tile_coord)
	history.clear()
	_rebuild_network_options()
	if map_2d != null: map_2d.set_tile(tile)
	_regenerate_all()
	set_status("Novo rascunho criado.")


func _regenerate_all() -> void:
	authoring_world.reset(tile.draft_seed)
	generator.generate_into(authoring_world, tile, registry, tile.draft_seed)
	section_system.queue_rebuild_all(true)
	_rebuild_overlay()
	_rebuild_anchor_previews()
	if map_2d != null:
		map_2d.set_tile(tile); map_2d.refresh()


func _export_tile(path: String) -> void:
	var error: Error = tile.save_to_file(path)
	set_status("Tile exportado: %s" % path if error == OK else "Falha ao exportar: %s" % error_string(error))


func _load_tile(path: String) -> void:
	var loaded = TerrainTileScript.load_from_file(path)
	if loaded == null:
		set_status("Arquivo de tile invalido.")
		return
	tile = loaded
	history.clear()
	_rebuild_network_options()
	if map_2d != null: map_2d.set_tile(tile)
	_regenerate_all()
	set_status("Tile carregado: %s" % path)


func _rebuild_overlay() -> void:
	if overlay_instance != null and is_instance_valid(overlay_instance):
		overlay_instance.queue_free()
	overlay_instance = MultiMeshInstance3D.new()
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.instance_count = TerrainTileScript.CELL_COUNT
	var marker_mesh: BoxMesh = BoxMesh.new()
	marker_mesh.size = Vector3(0.92, 0.025, 0.92)
	multimesh.mesh = marker_mesh
	for z in range(TerrainTileScript.TILE_SIZE):
		for x in range(TerrainTileScript.TILE_SIZE):
			var index: int = tile.index_of(x, z)
			var world_x: float = float(tile.tile_coord.x * 100 + x)
			var world_z: float = float(tile.tile_coord.y * 100 + z)
			multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(world_x, float(tile.heights[index]) + 0.53, world_z)))
			multimesh.set_instance_color(index, _overlay_color(index))
	overlay_instance.multimesh = multimesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	overlay_instance.material_override = material
	add_child(overlay_instance)


func _overlay_color(index: int) -> Color:
	match overlay_option.selected:
		0:
			return [Color(0.2, 0.9, 0.25, 0.26), Color(0.65, 0.65, 0.68, 0.30), Color(0.48, 0.25, 0.08, 0.30), Color(0.75, 0.9, 0.25, 0.26)][clampi(int(tile.surface_profiles[index]), 0, 3)]
		1:
			var value: float = float(tile.cave_density[index]) / 255.0
			return Color(value, 0.15, 1.0 - value, 0.12 + value * 0.38)
		_:
			var flags: int = int(tile.zone_flags[index])
			if (flags & TerrainTileScript.ZONE_PROTECTED) != 0: return Color(1.0, 0.1, 0.1, 0.48)
			if (flags & TerrainTileScript.ZONE_FOREST) != 0: return Color(0.05, 0.75, 0.18, 0.36)
			if (flags & TerrainTileScript.ZONE_STRUCTURES) != 0: return Color(0.1, 0.55, 1.0, 0.28)
			return Color(0.3, 0.3, 0.3, 0.12)


func _rebuild_anchor_previews() -> void:
	for child in anchor_root.get_children(): child.queue_free()
	for raw_anchor in tile.anchors:
		var anchor: Dictionary = raw_anchor as Dictionary
		var x: int = int(anchor.get("x", 0))
		var z: int = int(anchor.get("z", 0))
		var marker: MeshInstance3D = MeshInstance3D.new()
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(1.2, 2.4, 1.2)
		marker.mesh = mesh
		marker.position = Vector3(tile.tile_coord.x * 100 + x, tile.get_height(x, z) + 1.7, tile.tile_coord.y * 100 + z)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.35, 0.05, 0.55)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		marker.material_override = material
		anchor_root.add_child(marker)
		var rule: Dictionary = registry.get_rule(str(anchor.get("template_id", "")))
		if rule.is_empty():
			material.albedo_color = Color(1.0, 0.05, 0.05, 0.7)
			continue
		var template = StructureTemplateScript.load_from_file(str(rule.get("path", "")))
		if template == null:
			material.albedo_color = Color(1.0, 0.05, 0.05, 0.7)
			continue
		var rotation: int = posmod(int(anchor.get("rotation", 0)), 4)
		var mirror_x: bool = bool(anchor.get("mirror_x", false))
		var mirror_z: bool = bool(anchor.get("mirror_z", false))
		var transformed_size: Vector3i = template.transformed_size(rotation)
		var transformed_pivot: Vector3i = template.transform_position(template.pivot, rotation, mirror_x, mirror_z)
		var anchor_y: int = int(anchor.get("y", tile.get_height(x, z)))
		var origin: Vector3i = Vector3i(tile.tile_coord.x * 100 + x, anchor_y, tile.tile_coord.y * 100 + z) - transformed_pivot
		var bounds: MeshInstance3D = MeshInstance3D.new()
		var bounds_mesh: BoxMesh = BoxMesh.new()
		bounds_mesh.size = Vector3(transformed_size)
		bounds.mesh = bounds_mesh
		bounds.position = Vector3(origin) + (Vector3(transformed_size) - Vector3.ONE) * 0.5
		var bounds_material: StandardMaterial3D = StandardMaterial3D.new()
		bounds_material.albedo_color = Color(0.1, 0.85, 1.0, 0.16)
		bounds_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bounds_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bounds.material_override = bounds_material
		anchor_root.add_child(bounds)


func _labeled(text: String, control: Control) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	var label: Label = Label.new(); label.text = text
	box.add_child(label); box.add_child(control)
	return box


func _slider(minimum: float, maximum: float, value: float, step: float) -> HSlider:
	var slider: HSlider = HSlider.new()
	slider.min_value = minimum; slider.max_value = maximum; slider.value = value; slider.step = step
	return slider


func _ensure_input_actions() -> void:
	var keys: Dictionary = {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D}
	for action in keys.keys():
		if not InputMap.has_action(action): InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			var event: InputEventKey = InputEventKey.new(); event.physical_keycode = keys[action]; InputMap.action_add_event(action, event)
