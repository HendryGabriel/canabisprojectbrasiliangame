extends Node2D
# Cena principal: o mapa agora vem dos TileMapLayers pintados a mao na Godot.
# A Sim continua consultando Sim.terreno_em(cell), mas a fonte deixou de ser seed/chunk.

const DEFAULT_MAP_BOUNDS := Rect2i(Vector2i(-8, -6), Vector2i(80, 60))

var _water: TileMapLayer
var _player: Node2D


func _ready() -> void:
	_water = get_node_or_null("Water") as TileMapLayer
	_registra_mapa_manual()

	var render := Node2D.new()
	render.set_script(load("res://src/render.gd"))
	add_child(render)

	_player = Node2D.new()
	_player.set_script(load("res://src/player.gd"))
	add_child(_player)

	var cam := Camera2D.new()
	cam.zoom = Vector2(2.8, 2.8)
	cam.position_smoothing_enabled = true
	cam.limit_top = -6 * Defs.TILE_SIZE
	_player.add_child(cam)

	var ui := CanvasLayer.new()
	ui.set_script(load("res://src/ui.gd"))
	add_child(ui)

	render.ui = ui
	_player.ui = ui
	ui.cam = cam

	if _water != null and _water.has_method("refresh_animation_cells"):
		_water.refresh_animation_cells()


func _registra_mapa_manual() -> void:
	var terrain := {}
	var obstacles := {}
	var used := []

	# Camadas visuais principais. FloorBase vira grama por padrao; camadas
	# especificas sobrescrevem isso com areia, piso, beco e cidade.
	_coleta_terreno("FloorBase", Sim.T.GRAMA, terrain, used)
	_coleta_terreno("FloorTransitions", Sim.T.GRAMA, terrain, used)
	_coleta_terreno("FloorSand", Sim.T.AREIA, terrain, used)
	_coleta_terreno("FloorInterior", Sim.T.PISO, terrain, used)
	_coleta_terreno("FloorAlley", Sim.T.BECO, terrain, used)
	_coleta_terreno("FloorCity", Sim.T.CIDADE, terrain, used)
	_coleta_terreno("Water", Sim.T.AGUA, terrain, used)

	# Camadas de gameplay/obstaculos. Elas podem ficar invisiveis no runtime se
	# voce preferir desenhar os sprites pelo render.gd.
	_coleta_obstaculo("ObjectsTrees", Sim.T.ARVORE, obstacles, used)
	_coleta_obstaculo("ObjectsTallGrass", Sim.T.MATO, obstacles, used)
	_coleta_obstaculo("ObjectsRocks", Sim.T.PEDRA, obstacles, used)

	var bounds := _bounds_das_celulas(used)
	if bounds.size == Vector2i.ZERO:
		bounds = DEFAULT_MAP_BOUNDS
		push_warning("Mapa manual vazio. Pinte FloorBase/Water/etc. em src/main.tscn para definir o mapa.")
	Sim.set_manual_map(terrain, obstacles, bounds)


func _coleta_terreno(layer_name: String, terrain_type: int, out: Dictionary, used: Array) -> void:
	var layer := get_node_or_null(layer_name) as TileMapLayer
	if layer == null:
		return
	for cell in layer.get_used_cells():
		out[cell] = terrain_type
		used.append(cell)


func _coleta_obstaculo(layer_name: String, terrain_type: int, out: Dictionary, used: Array) -> void:
	var layer := get_node_or_null(layer_name) as TileMapLayer
	if layer == null:
		return
	for cell in layer.get_used_cells():
		out[cell] = terrain_type
		used.append(cell)


func _bounds_das_celulas(cells: Array) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var min_c: Vector2i = cells[0]
	var max_c: Vector2i = cells[0]
	for c in cells:
		min_c.x = mini(min_c.x, c.x)
		min_c.y = mini(min_c.y, c.y)
		max_c.x = maxi(max_c.x, c.x)
		max_c.y = maxi(max_c.y, c.y)
	return Rect2i(min_c, max_c - min_c + Vector2i.ONE)
