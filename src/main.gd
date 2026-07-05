extends Node2D
# Bootstrap: monta renderizador, avatar, camera e UI em codigo (cena unica).

const FLOOR_TERRAIN_SET := 0
const TERRAIN_GRASS := 0
const TERRAIN_STONE := 1
const TERRAIN_DIRT := 2
const TERRAIN_STONEBRICKS := 3
const TERRAIN_SNOW := 4
const TERRAIN_SAND := 5
const FLOOR_SOURCE_ID := 0
const WATER_TERRAIN_SET := 0
const TERRAIN_WATER := 0

func _ready() -> void:
	var floor_base: TileMapLayer = get_node_or_null("FloorBase") as TileMapLayer
	var floor_transitions: TileMapLayer = get_node_or_null("FloorTransitions") as TileMapLayer
	var water: TileMapLayer = get_node_or_null("Water") as TileMapLayer
	if floor_base != null:
		_generate_floor_map(floor_base, floor_transitions)
	if water != null:
		_generate_water_map(water)
		if water.has_method("refresh_animation_cells"):
			water.call_deferred("refresh_animation_cells")

	var render := Node2D.new()
	render.set_script(load("res://src/render.gd"))
	add_child(render)

	var player := Node2D.new()
	player.set_script(load("res://src/player.gd"))
	add_child(player)

	var cam := Camera2D.new()
	cam.zoom = Vector2(2.8, 2.8)
	cam.position_smoothing_enabled = true
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = Sim.W * Defs.TILE_SIZE
	cam.limit_bottom = Sim.H * Defs.TILE_SIZE
	player.add_child(cam)

	var ui := CanvasLayer.new()
	ui.set_script(load("res://src/ui.gd"))
	add_child(ui)

	render.ui = ui
	player.ui = ui
	ui.cam = cam


func _generate_floor_map(floor_base: TileMapLayer, floor_transitions: TileMapLayer) -> void:
	floor_base.clear()
	if floor_base.tile_set == null:
		push_warning("FloorBase precisa de um TileSet para gerar o mapa.")
		return
	if floor_transitions == null:
		push_warning("FloorTransitions precisa existir para desenhar as bordas transparentes do terreno.")
		return
	floor_transitions.clear()
	if floor_transitions.tile_set == null:
		push_warning("FloorTransitions precisa de um TileSet para gerar as transicoes.")
		return
	if floor_transitions.tile_set.get_terrain_sets_count() <= FLOOR_TERRAIN_SET:
		push_warning("Configure o Terrain Set 0 em Floors_Tiles.tres antes de gerar o mapa automatico.")
		return
	var grass_cells: Array[Vector2i] = []
	for x in Sim.W:
		for y in Sim.H:
			var cell: Vector2i = Vector2i(x, y)
			var terrain: int = _floor_terrain_for(Sim.terreno_em(cell))
			if terrain < 0:
				continue
			var base_terrain: int = terrain
			if terrain == TERRAIN_GRASS:
				base_terrain = _base_terrain_for_cell(cell, terrain)
			floor_base.set_cell(cell, FLOOR_SOURCE_ID, _solid_floor_cell(base_terrain))
			if terrain == TERRAIN_GRASS:
				grass_cells.append(cell)
	_paint_terrain_cells(floor_transitions, TERRAIN_GRASS, grass_cells)


func _paint_terrain_cells(floor_base: TileMapLayer, terrain: int, cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	floor_base.set_cells_terrain_connect(cells, FLOOR_TERRAIN_SET, terrain, false)


func _generate_water_map(water: TileMapLayer) -> void:
	if not water.get_used_cells().is_empty():
		return
	if water.tile_set == null:
		push_warning("Water precisa de um TileSet para gerar a agua.")
		return
	if water.tile_set.get_terrain_sets_count() <= WATER_TERRAIN_SET:
		push_warning("Configure o Terrain Set 0 em Water_tiles.tres antes de gerar a agua automatica.")
		return
	var water_cells: Array[Vector2i] = []
	for x in Sim.W:
		for y in Sim.H:
			var cell: Vector2i = Vector2i(x, y)
			if Sim.terreno_em(cell) == Sim.T.AGUA:
				water_cells.append(cell)
	if water_cells.is_empty():
		return
	water.set_cells_terrain_connect(water_cells, WATER_TERRAIN_SET, TERRAIN_WATER, false)


func _base_terrain_for_cell(cell: Vector2i, terrain: int) -> int:
	var neighbor_terrain: int = _different_neighbor_terrain(cell, terrain)
	if neighbor_terrain >= 0:
		return neighbor_terrain
	return terrain


func _different_neighbor_terrain(cell: Vector2i, terrain: int) -> int:
	var offsets: Array[Vector2i] = [
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
		Vector2i(1, -1),
		Vector2i(1, 1),
		Vector2i(-1, 1),
		Vector2i(-1, -1),
	]
	for offset: Vector2i in offsets:
		var other_cell: Vector2i = cell + offset
		if other_cell.x < 0 or other_cell.y < 0 or other_cell.x >= Sim.W or other_cell.y >= Sim.H:
			continue
		var other_terrain: int = _floor_terrain_for(Sim.terreno_em(other_cell))
		if other_terrain >= 0 and other_terrain != terrain:
			return other_terrain
	return -1


func _solid_floor_cell(terrain: int) -> Vector2i:
	match terrain:
		TERRAIN_GRASS:
			return Vector2i(2, 10)
		TERRAIN_STONE:
			return Vector2i(7, 10)
		TERRAIN_DIRT:
			return Vector2i(12, 10)
		TERRAIN_STONEBRICKS:
			return Vector2i(17, 2)
		TERRAIN_SNOW:
			return Vector2i(2, 22)
		TERRAIN_SAND:
			return Vector2i(7, 22)
	return Vector2i(2, 10)


func _floor_terrain_for(sim_terrain: int) -> int:
	match sim_terrain:
		Sim.T.AGUA:
			return -1
		Sim.T.ARVORE:
			return TERRAIN_GRASS
		Sim.T.GRAMA:
			return TERRAIN_GRASS
		Sim.T.AREIA:
			return TERRAIN_SAND
		Sim.T.PISO:
			return TERRAIN_STONEBRICKS
		Sim.T.BECO:
			return TERRAIN_STONE
	return TERRAIN_GRASS
