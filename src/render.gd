extends Node2D
# Renderizador: desenha o estado da Sim por cima (GDD §9). Placeholders geometricos
# ate os sprites chegarem em assets/ — a logica nao sabe que isso existe.

const TILE := 32

const COR_TERRENO := {
	Sim.T.GRAMA: Color(0.30, 0.52, 0.28),
	Sim.T.AGUA: Color(0.18, 0.38, 0.65),
	Sim.T.ARVORE: Color(0.12, 0.30, 0.12),
	Sim.T.AREIA: Color(0.78, 0.70, 0.45),
	Sim.T.PISO: Color(0.55, 0.45, 0.35),
	Sim.T.BECO: Color(0.22, 0.20, 0.24),
}

const COR_PREDIO := {
	"esteira": Color(0.45, 0.45, 0.50), "cano": Color(0.25, 0.55, 0.75),
	"poco": Color(0.15, 0.45, 0.80), "canteiro": Color(0.35, 0.24, 0.14),
	"bancada": Color(0.60, 0.40, 0.20), "maq_pura": Color(0.55, 0.75, 0.35),
	"maq_blend": Color(0.75, 0.55, 0.25), "maq_haxixe": Color(0.45, 0.30, 0.15),
	"maq_ice": Color(0.60, 0.85, 0.95), "maq_cbd": Color(0.30, 0.70, 0.60),
	"maq_baseado": Color(0.85, 0.80, 0.60), "maq_semente": Color(0.50, 0.65, 0.30),
	"estufa_mini": Color(0.40, 0.80, 0.45), "estufa_grande": Color(0.25, 0.70, 0.35),
	"extrator_madeira": Color(0.50, 0.35, 0.20), "fab_seda": Color(0.85, 0.85, 0.80),
	"fab_gelo": Color(0.75, 0.90, 1.0), "extrator_areia": Color(0.85, 0.75, 0.50),
	"fornalha": Color(0.80, 0.40, 0.20), "gerador": Color(0.35, 0.35, 0.30),
	"solar": Color(0.20, 0.25, 0.50), "filtro": Color(0.30, 0.30, 0.35),
	"pc": Color(0.20, 0.20, 0.60), "traficante": Color(0.55, 0.15, 0.45),
}

const ROTULO := {
	"esteira": "", "cano": "", "poco": "P", "canteiro": "", "bancada": "BAN",
	"maq_pura": "PUR", "maq_blend": "MIX", "maq_haxixe": "HAX", "maq_ice": "ICE",
	"maq_cbd": "CBD", "maq_baseado": "BAS", "maq_semente": "SEM",
	"estufa_mini": "estufa", "estufa_grande": "ESTUFA", "extrator_madeira": "MAD",
	"fab_seda": "SEDA", "fab_gelo": "GELO", "extrator_areia": "ARE",
	"fornalha": "FORN", "gerador": "GER", "solar": "SOL", "filtro": "FIL",
	"pc": "PC", "traficante": "BECO", }

var ui: CanvasLayer  # p/ ghost de construcao
var _fundo: ImageTexture
var _fonte: Font


func _ready() -> void:
	_fonte = ThemeDB.fallback_font
	var img := Image.create(Sim.W, Sim.H, false, Image.FORMAT_RGB8)
	for x in Sim.W:
		for y in Sim.H:
			img.set_pixel(x, y, COR_TERRENO[Sim.terreno_em(Vector2i(x, y))])
	_fundo = ImageTexture.create_from_image(img)


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_texture_rect(_fundo, Rect2(0, 0, Sim.W * TILE, Sim.H * TILE), false)
	_draw_lotes()
	var ids := Sim.ents.keys()
	ids.sort()
	for id in ids:
		_draw_ent(Sim.ents[id])
	_draw_ghost()


func _draw_lotes() -> void:
	for i in Defs.LOTES.size():
		var r: Rect2i = Defs.LOTES[i]["rect"]
		var px := Rect2(r.position * TILE, r.size * TILE)
		if i >= Sim.lotes_comprados:
			draw_rect(px, Color(0, 0, 0, 0.55), true)
			draw_string(_fonte, px.position + Vector2(20, 40), "LOTE %d — $%d (compre no PC)" % [i, Defs.LOTES[i]["custo"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		draw_rect(px, Color(1, 1, 1, 0.15), false, 1.0)


func _draw_ent(e: Dictionary) -> void:
	var t: String = e["t"]
	var tam: Vector2i = Defs.PREDIOS[t]["tam"] if Defs.PREDIOS.has(t) else Vector2i(1, 1)
	var px := Rect2(e["pos"] * TILE, tam * TILE)
	var cor: Color = COR_PREDIO.get(t, Color.GRAY)
	match t:
		"esteira":
			draw_rect(px.grow(-2), cor, true)
			_draw_seta(px, e["dir"], Color(0.8, 0.8, 0.85))
			if e["item"] != "":
				var frac: float = float(e["prog"]) / Sim.BELT_T
				var dv: Vector2 = Vector2(Sim.DIRS[e["dir"]]) * (frac - 0.5) * TILE
				_draw_item(px.get_center() + dv, e["item"])
		"cano":
			draw_rect(px.grow(-8), cor, true)
			for d in Sim.DIRS:
				var viz = Sim.ent_em(e["pos"] + d)
				if viz != null and (viz["t"] == "cano" or viz["t"] == "poco"):
					draw_rect(Rect2(px.get_center() + Vector2(d) * 8 - Vector2(4, 4), Vector2(8, 8) + Vector2(d).abs() * 8), cor, true)
		"canteiro":
			draw_rect(px.grow(-2), cor, true)
			var fase: int = e["fase"]
			if fase >= 1:
				var cores := [Color.TRANSPARENT, Color(0.7, 0.6, 0.3), Color(0.4, 0.7, 0.3), Color(0.3, 1.0, 0.4)]
				draw_circle(px.get_center(), 4 + fase * 3, cores[fase])
			if fase == 1:
				draw_string(_fonte, px.position + Vector2(2, 12), "seco", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.YELLOW)
		_:
			draw_rect(px.grow(-2), cor, true)
			draw_rect(px.grow(-2), cor.lightened(0.3), false, 2.0)
			if e.has("dir") and (Defs.RECEITAS.has(t) or Defs.ESTUFAS.has(t)):
				_draw_seta_saida(e, tam)
			var rot: String = ROTULO.get(t, t)
			if rot != "":
				draw_string(_fonte, px.position + Vector2(3, px.size.y / 2 + 5), rot, HORIZONTAL_ALIGNMENT_LEFT, px.size.x, 12, Color.WHITE)
			if e.get("prog", 0) > 0:
				var total := 1
				if Defs.RECEITAS.has(t):
					total = Defs.RECEITAS[t]["t"] * 256
				elif Defs.ESTUFAS.has(t):
					total = Defs.ESTUFAS[t]["t"] * 256
				var w: float = px.size.x * clampf(float(e["prog"]) / total, 0.0, 1.0)
				draw_rect(Rect2(px.position + Vector2(0, px.size.y - 4), Vector2(w, 4)), Color.GREEN_YELLOW, true)
			if e.get("out_n", 0) > 0:
				_draw_item(px.position + Vector2(px.size.x - 8, 8), e["out_item"])
			if t == "gerador" and e["fuel"] > 0:
				draw_rect(Rect2(px.position + Vector2(0, 0), Vector2(4, px.size.y * minf(1.0, e["fuel"] / 300.0))), Color.ORANGE, true)


func _draw_seta(px: Rect2, dir: int, cor: Color) -> void:
	var c := px.get_center()
	var v := Vector2(Sim.DIRS[dir])
	var p := Vector2(-v.y, v.x)
	draw_colored_polygon(PackedVector2Array([c + v * 10, c - v * 4 + p * 6, c - v * 4 - p * 6]), cor)


func _draw_seta_saida(e: Dictionary, _tam: Vector2i) -> void:
	var alvo: Vector2i = Sim._celula_frente(e)
	var c := Vector2(alvo) * TILE + Vector2(TILE / 2.0, TILE / 2.0)
	var v := Vector2(Sim.DIRS[e["dir"]])
	draw_colored_polygon(PackedVector2Array([c + v * 6, c - v * 4 + Vector2(-v.y, v.x) * 5, c - v * 4 - Vector2(-v.y, v.x) * 5]), Color(1, 1, 0.5, 0.7))


func _draw_item(pos: Vector2, item: String) -> void:
	var cor := Color.from_hsv(float(hash(item) % 360) / 360.0, 0.75, 0.95)
	draw_circle(pos, 7, cor)
	draw_circle(pos, 7, Color.BLACK, false, 1.0)
	draw_string(_fonte, pos + Vector2(-4, 4), Defs.item_prod(item).left(1).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.BLACK)


func _draw_ghost() -> void:
	if ui == null or ui.build_type == "":
		return
	var cell := Vector2i((get_global_mouse_position() / TILE).floor())
	var tam: Vector2i = Defs.PREDIOS[ui.build_type]["tam"]
	var px := Rect2(cell * TILE, tam * TILE)
	var ok := true
	for dx in tam.x:
		for dy in tam.y:
			var c: Vector2i = cell + Vector2i(dx, dy)
			if Sim.grid.has(c) or not Sim.celula_comprada(c):
				ok = false
	draw_rect(px, Color(0, 1, 0, 0.35) if ok else Color(1, 0, 0, 0.35), true)
	var fake := {"t": ui.build_type, "pos": cell, "dir": ui.rot}
	if Defs.RECEITAS.has(ui.build_type) or Defs.ESTUFAS.has(ui.build_type):
		_draw_seta_saida(fake, tam)
	elif ui.build_type == "esteira":
		_draw_seta(px, ui.rot, Color(1, 1, 1, 0.7))
