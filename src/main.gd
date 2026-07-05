extends Node2D
# Bootstrap + streaming de chunks (estilo Minecraft): o terreno da Sim e uma funcao
# pura de (x,y,seed); aqui a gente so PINTA o TileMap dos chunks perto do player,
# alguns por frame, pra nunca travar. Chunks ja pintados ficam pintados.

const FLOOR_TERRAIN_SET := 0
const TERRAIN_GRASS := 0
const FLOOR_SOURCE_ID := 0
const WATER_TERRAIN_SET := 0
const TERRAIN_WATER := 0
const RAIO_CHUNKS := 3       # gera/pinta chunks neste raio ao redor do player
const CHUNKS_POR_FRAME := 2  # orcamento p/ nao causar hitch

var _floor_base: TileMapLayer
var _floor_transitions: TileMapLayer
var _water: TileMapLayer
var _player: Node2D
var _pintados := {}
var _fila: Array = []
var _agua_suja := false
var _agua_timer := 0.0


func _ready() -> void:
	_floor_base = get_node_or_null("FloorBase") as TileMapLayer
	_floor_transitions = get_node_or_null("FloorTransitions") as TileMapLayer
	_water = get_node_or_null("Water") as TileMapLayer

	var render := Node2D.new()
	render.set_script(load("res://src/render.gd"))
	add_child(render)

	_player = Node2D.new()
	_player.set_script(load("res://src/player.gd"))
	add_child(_player)

	var cam := Camera2D.new()
	cam.zoom = Vector2(2.8, 2.8)
	cam.position_smoothing_enabled = true
	cam.limit_top = -6 * Defs.TILE_SIZE  # mostra uma faixa da cidade no topo
	_player.add_child(cam)

	var ui := CanvasLayer.new()
	ui.set_script(load("res://src/ui.gd"))
	add_child(ui)

	render.ui = ui
	_player.ui = ui
	ui.cam = cam

	# pinta a area inicial inteira antes do primeiro frame (sem pop-in na casa)
	_enfileira_ao_redor(Vector2i(0, 0))
	while _fila.size() > 0:
		_pinta_chunk(_fila.pop_front())


func _physics_process(delta: float) -> void:
	var pc := Vector2i(Sim._fdiv(Sim.player_cell.x, Sim.CHUNK), Sim._fdiv(Sim.player_cell.y, Sim.CHUNK))
	_enfileira_ao_redor(pc)
	var n := 0
	while _fila.size() > 0 and n < CHUNKS_POR_FRAME:
		_pinta_chunk(_fila.pop_front())
		n += 1
	if _agua_suja:
		_agua_timer += delta
		if _agua_timer > 0.5:  # debounce: re-escanear animacao da agua e caro
			_agua_suja = false
			_agua_timer = 0.0
			if _water != null and _water.has_method("refresh_animation_cells"):
				_water.refresh_animation_cells()


func _enfileira_ao_redor(pc: Vector2i) -> void:
	for cy in range(maxi(pc.y - RAIO_CHUNKS, -1), pc.y + RAIO_CHUNKS + 1):
		for cx in range(pc.x - RAIO_CHUNKS, pc.x + RAIO_CHUNKS + 1):
			var cc := Vector2i(cx, cy)
			if not _pintados.has(cc):
				_pintados[cc] = true
				_fila.append(cc)


func _pinta_chunk(cc: Vector2i) -> void:
	if _floor_base == null or _floor_base.tile_set == null:
		return
	var grama: Array[Vector2i] = []
	var agua: Array[Vector2i] = []
	for dy in Sim.CHUNK:
		for dx in Sim.CHUNK:
			var cell := Vector2i(cc.x * Sim.CHUNK + dx, cc.y * Sim.CHUNK + dy)
			var t := Sim.terreno_em(cell)
			match t:
				Sim.T.AGUA:
					agua.append(cell)
				Sim.T.GRAMA, Sim.T.ARVORE, Sim.T.MATO, Sim.T.PEDRA:
					_floor_base.set_cell(cell, FLOOR_SOURCE_ID, Vector2i(2, 10))
					grama.append(cell)
				Sim.T.AREIA:
					_floor_base.set_cell(cell, FLOOR_SOURCE_ID, Vector2i(7, 22))
				Sim.T.PISO:
					_floor_base.set_cell(cell, FLOOR_SOURCE_ID, Vector2i(17, 2))
				Sim.T.BECO, Sim.T.CIDADE:
					_floor_base.set_cell(cell, FLOOR_SOURCE_ID, Vector2i(7, 10))
	if _floor_transitions != null and _floor_transitions.tile_set != null \
			and _floor_transitions.tile_set.get_terrain_sets_count() > FLOOR_TERRAIN_SET and grama.size() > 0:
		_floor_transitions.set_cells_terrain_connect(grama, FLOOR_TERRAIN_SET, TERRAIN_GRASS, false)
	if _water != null and _water.tile_set != null \
			and _water.tile_set.get_terrain_sets_count() > WATER_TERRAIN_SET and agua.size() > 0:
		_water.set_cells_terrain_connect(agua, WATER_TERRAIN_SET, TERRAIN_WATER, false)
		_agua_suja = true
