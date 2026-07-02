extends Node2D
# Renderizador procedural detalhado: desenha o estado da Sim por cima (GDD §9).
# Tudo em codigo — quando os sprites chegarem em assets/, substituem estes desenhos
# sem tocar na simulacao.

const TILE := 32

# cor base por cepa (folha/bud/chip nas maquinas)
const COR_CEPA := {
	"ruderalis": Color(0.45, 0.60, 0.30), "jack_herer": Color(0.35, 0.75, 0.30),
	"sour_diesel": Color(0.75, 0.80, 0.25), "durban_poison": Color(0.20, 0.65, 0.45),
	"northern_lights": Color(0.30, 0.45, 0.75), "granddaddy_purple": Color(0.55, 0.30, 0.70),
	"purple_kush": Color(0.45, 0.20, 0.60), "blue_dream": Color(0.35, 0.55, 0.85),
	"gsc": Color(0.70, 0.50, 0.25), "og_kush": Color(0.25, 0.55, 0.20),
}

var ui: CanvasLayer
var _fundo: ImageTexture
var _fonte: Font
var _traficante_pos := Vector2.ZERO
var _money_antes := -1
var _floats: Array = []  # {pos, txt, ttl, cor}


func _ready() -> void:
	_fonte = ThemeDB.fallback_font
	_bake_terreno()
	for id in Sim.ents:
		if Sim.ents[id]["t"] == "traficante":
			_traficante_pos = Vector2(Sim.ents[id]["pos"] * TILE) + Vector2(16, 16)


func _process(delta: float) -> void:
	# feedback de venda: dinheiro subiu -> texto flutuante no beco
	if _money_antes >= 0 and Sim.money > _money_antes:
		_floats.append({"pos": _traficante_pos + Vector2(0, -20), "txt": "+$%d" % (Sim.money - _money_antes), "ttl": 1.5, "cor": Color.GREEN_YELLOW})
	_money_antes = Sim.money
	for f in _floats:
		f["ttl"] -= delta
		f["pos"] += Vector2(0, -25) * delta
	_floats = _floats.filter(func(f): return f["ttl"] > 0)
	queue_redraw()


# ---------------- terreno (assado uma vez, variantes por tile) ----------------

func _bake_terreno() -> void:
	var tiles := {}
	for t in [Sim.T.GRAMA, Sim.T.AGUA, Sim.T.ARVORE, Sim.T.AREIA, Sim.T.PISO, Sim.T.BECO]:
		tiles[t] = []
		for v in 3:
			tiles[t].append(_tile_img(t, v))
	var img := Image.create(Sim.W * TILE, Sim.H * TILE, false, Image.FORMAT_RGB8)
	for x in Sim.W:
		for y in Sim.H:
			var t := Sim.terreno_em(Vector2i(x, y))
			var v := (x * 7 + y * 13) % 3
			img.blit_rect(tiles[t][v], Rect2i(0, 0, TILE, TILE), Vector2i(x * TILE, y * TILE))
	_fundo = ImageTexture.create_from_image(img)


func _tile_img(t: int, variante: int) -> Image:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGB8)
	var rnd := variante * 97
	match t:
		Sim.T.GRAMA:
			img.fill(Color(0.32, 0.52, 0.28).lightened(variante * 0.02))
			for i in 26:  # tufos de grama
				var px := (i * 13 + rnd) % TILE
				var py := (i * 23 + rnd * 3) % TILE
				img.set_pixel(px, py, Color(0.24, 0.44, 0.20))
				img.set_pixel(px, maxi(0, py - 1), Color(0.40, 0.62, 0.32))
		Sim.T.AGUA:
			img.fill(Color(0.16, 0.36, 0.62))
			for i in 5:  # ondinhas
				var wy := (i * 7 + rnd) % (TILE - 2) + 1
				for wx in range(2 + (i * 5) % 8, TILE - 4, 9):
					img.set_pixel(wx, wy, Color(0.35, 0.55, 0.80))
					img.set_pixel(wx + 1, wy, Color(0.35, 0.55, 0.80))
		Sim.T.ARVORE:
			img.fill(Color(0.30, 0.48, 0.26))
			for px in range(13, 19):  # tronco
				for py in range(20, 30):
					img.set_pixel(px, py, Color(0.35, 0.22, 0.10))
			for px in TILE:  # copa
				for py in TILE:
					var d := Vector2(px - 16, py - 13).length()
					if d < 12 - ((px * 3 + py * 7 + rnd) % 3):
						img.set_pixel(px, py, Color(0.10, 0.32, 0.10) if (px + py + rnd) % 4 else Color(0.16, 0.42, 0.14))
		Sim.T.AREIA:
			img.fill(Color(0.78, 0.70, 0.46))
			for i in 20:
				img.set_pixel((i * 17 + rnd) % TILE, (i * 29 + rnd) % TILE, Color(0.68, 0.58, 0.36))
		Sim.T.PISO:
			img.fill(Color(0.56, 0.46, 0.36))
			for px in TILE:  # tabuas
				for py in range(0, TILE, 8):
					img.set_pixel(px, py, Color(0.46, 0.36, 0.28))
		Sim.T.BECO:
			img.fill(Color(0.20, 0.19, 0.23))
			for px in TILE:
				if px % 8 == 0:
					for py in TILE:
						img.set_pixel(px, py, Color(0.15, 0.14, 0.18))
	return img


# ---------------- draw principal ----------------

func _draw() -> void:
	draw_texture_rect(_fundo, Rect2(0, 0, Sim.W * TILE, Sim.H * TILE), false)
	_draw_lotes()
	var ids := Sim.ents.keys()
	ids.sort()
	# canos e esteiras primeiro (chao), depois maquinas (em cima)
	for id in ids:
		var e: Dictionary = Sim.ents[id]
		if e["t"] == "cano" or e["t"] == "esteira":
			_draw_ent(e)
	for id in ids:
		var e: Dictionary = Sim.ents[id]
		if e["t"] != "cano" and e["t"] != "esteira":
			_draw_ent(e)
	for f in _floats:
		draw_string(_fonte, f["pos"], f["txt"], HORIZONTAL_ALIGNMENT_CENTER, -1, 16, f["cor"])
	_draw_ghost()


func _draw_lotes() -> void:
	for i in Defs.LOTES.size():
		var r: Rect2i = Defs.LOTES[i]["rect"]
		var px := Rect2(r.position * TILE, r.size * TILE)
		if i >= Sim.lotes_comprados:
			draw_rect(px, Color(0, 0, 0, 0.55), true)
			draw_string(_fonte, px.position + Vector2(20, 40), "LOTE %d — $%d (compre no PC)" % [i, Defs.LOTES[i]["custo"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		draw_rect(px, Color(1, 1, 1, 0.12), false, 1.0)


func _draw_ent(e: Dictionary) -> void:
	var t: String = e["t"]
	var tam: Vector2i = Defs.PREDIOS[t]["tam"] if Defs.PREDIOS.has(t) else Vector2i(1, 1)
	var px := Rect2(e["pos"] * TILE, tam * TILE)
	match t:
		"esteira": _draw_esteira(e, px)
		"cano": _draw_cano(e, px)
		"poco": _draw_poco(e, px)
		"canteiro": _draw_canteiro(e, px)
		"bancada": _draw_bancada(e, px)
		"pc": _draw_pc(px)
		"traficante": _draw_traficante(px)
		"gerador": _draw_gerador(e, px)
		"solar": _draw_solar(px)
		"filtro": _draw_filtro(px)
		"estufa_mini", "estufa_grande": _draw_estufa(e, px)
		_: _draw_maquina(e, px)


# ---------------- esteira / cano / poco ----------------

func _draw_esteira(e: Dictionary, px: Rect2) -> void:
	draw_rect(px.grow(-1), Color(0.30, 0.30, 0.34), true)
	draw_rect(px.grow(-4), Color(0.45, 0.45, 0.50), true)
	# trilhos laterais
	var v := Vector2(Sim.DIRS[e["dir"]])
	var p := Vector2(-v.y, v.x)
	# setas animadas correndo na direcao (visual apenas — nao afeta a sim)
	var anim := fmod((Sim.tick * Sim.FRAMES_POR_TICK + Sim._frame_acc) * 0.55, 12.0)
	var c := px.get_center()
	for i in range(-1, 2):
		var base := c + v * (i * 12.0 + anim - 6.0)
		draw_colored_polygon(PackedVector2Array([base + v * 4, base - v * 2 + p * 5, base - v * 2 - p * 5]), Color(0.62, 0.62, 0.68))
	if e["item"] != "":
		# interpolacao suave entre ticks (GDD §9: sim discreta, visual fluido)
		var frac := clampf((e["prog"] + Sim._frame_acc / float(Sim.FRAMES_POR_TICK)) / Sim.BELT_T, 0.0, 1.0)
		_draw_item(c + v * (frac - 0.5) * TILE, e["item"])


func _draw_cano(e: Dictionary, px: Rect2) -> void:
	var n: int = e.get("net", -1)
	var nivel := 0.0
	if n >= 0 and n < Sim.redes.size() and Sim.redes[n]["cap"] > 0:
		nivel = float(Sim.redes[n]["vol"]) / Sim.redes[n]["cap"]
	var cor_agua := Color(0.35, 0.35, 0.40).lerp(Color(0.20, 0.55, 0.90), nivel)
	var c := px.get_center()
	var sozinho := true
	for d in Sim.DIRS:
		var viz = Sim.ent_em(e["pos"] + Vector2i(d))
		if viz != null and (viz["t"] == "cano" or viz["t"] == "poco"):
			sozinho = false
			var fim := c + Vector2(d) * 16
			draw_line(c, fim, Color(0.55, 0.55, 0.60), 10.0)
			draw_line(c, fim, cor_agua, 6.0)
	if sozinho:
		draw_line(c - Vector2(10, 0), c + Vector2(10, 0), Color(0.55, 0.55, 0.60), 10.0)
		draw_line(c - Vector2(10, 0), c + Vector2(10, 0), cor_agua, 6.0)
	draw_circle(c, 6, Color(0.60, 0.60, 0.66))
	draw_circle(c, 4, cor_agua)


func _draw_poco(e: Dictionary, px: Rect2) -> void:
	var c := px.get_center()
	draw_circle(c, 13, Color(0.45, 0.45, 0.48))   # pedra
	draw_circle(c, 9, Color(0.25, 0.25, 0.28))
	draw_circle(c, 7, Color(0.18, 0.40, 0.70))    # agua dentro
	# medidor da rede
	var n: int = e.get("net", -1)
	if n >= 0 and n < Sim.redes.size() and Sim.redes[n]["cap"] > 0:
		var nivel: float = float(Sim.redes[n]["vol"]) / float(Sim.redes[n]["cap"])
		draw_rect(Rect2(px.position + Vector2(2, 26), Vector2(28, 4)), Color(0, 0, 0, 0.5), true)
		draw_rect(Rect2(px.position + Vector2(2, 26), Vector2(28 * nivel, 4)), Color(0.25, 0.65, 1.0), true)


# ---------------- cultivo ----------------

func _draw_canteiro(e: Dictionary, px: Rect2) -> void:
	var fase: int = e["fase"]
	var solo := Color(0.42, 0.30, 0.18) if fase == 1 else Color(0.30, 0.20, 0.12)  # seco mais claro
	draw_rect(px.grow(-2), solo, true)
	draw_rect(px.grow(-2), Color(0.20, 0.13, 0.08), false, 2.0)
	for i in 3:  # sulcos
		var sy: float = px.position.y + 8 + i * 8
		draw_line(Vector2(px.position.x + 4, sy), Vector2(px.end.x - 4, sy), solo.darkened(0.25), 2.0)
	var c := px.get_center()
	var cor: Color = COR_CEPA.get(e["cepa"], Color(0.4, 0.7, 0.3))
	match fase:
		1:  # plantado, seco — esperando rega
			draw_circle(c, 3, Color(0.75, 0.65, 0.40))
			draw_string(_fonte, px.position + Vector2(1, 11), "seco!", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.YELLOW)
		2:  # crescendo — broto escala com o tempo
			var g: float = clampf(float(e["tempo"]) / Defs.STRAINS[e["cepa"]]["grow"], 0.0, 1.0)
			_draw_planta(c + Vector2(0, 6), 4.0 + g * 10.0, cor.darkened(0.15))
		3:  # pronto — pe cheio de buds brilhando
			_draw_planta(c + Vector2(0, 6), 14.0, cor)
			for i in 3:
				draw_circle(c + Vector2([-6, 6, 0][i], [-4, -4, -12][i]), 3, cor.lightened(0.35))
			draw_string(_fonte, px.position + Vector2(4, 11), "E!", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.GREEN_YELLOW)


func _draw_planta(base: Vector2, altura: float, cor: Color) -> void:
	draw_line(base, base + Vector2(0, -altura), Color(0.25, 0.40, 0.15), 2.0)
	for i in 3:  # pares de folhas
		var h: float = altura * (0.35 + i * 0.3)
		var w: float = altura * (0.55 - i * 0.12)
		var o := base + Vector2(0, -h)
		draw_colored_polygon(PackedVector2Array([o, o + Vector2(-w, -3), o + Vector2(-w * 0.5, -6)]), cor)
		draw_colored_polygon(PackedVector2Array([o, o + Vector2(w, -3), o + Vector2(w * 0.5, -6)]), cor)


func _draw_estufa(e: Dictionary, px: Rect2) -> void:
	draw_rect(px.grow(-2), Color(0.55, 0.58, 0.55), true)               # base
	draw_rect(px.grow(-4), Color(0.65, 0.85, 0.90, 0.75), true)          # vidro
	for i in range(1, 4):                                                # caixilhos
		var gx: float = px.position.x + px.size.x * i / 4.0
		draw_line(Vector2(gx, px.position.y + 4), Vector2(gx, px.end.y - 4), Color.WHITE * Color(1, 1, 1, 0.6), 2.0)
	draw_line(px.position + Vector2(4, px.size.y / 2), px.position + Vector2(px.size.x - 4, px.size.y / 2), Color(1, 1, 1, 0.6), 2.0)
	var d: Dictionary = Defs.ESTUFAS[e["t"]]
	var g: float = clampf(float(e["prog"]) / (d["t"] * 256), 0.0, 1.0)
	var cor: Color = COR_CEPA.get(e.get("cepa_ciclo", ""), Color(0.3, 0.6, 0.3))
	var n_plantas: int = 2 if e["t"] == "estufa_mini" else 4
	for i in n_plantas:  # fileira de plantas crescendo com o ciclo
		var bx: float = px.position.x + px.size.x * (i + 1) / (n_plantas + 1.0)
		if e["prog"] > 0:
			_draw_planta(Vector2(bx, px.end.y - 8), 4.0 + g * (px.size.y * 0.35), cor)
	draw_string(_fonte, px.position + Vector2(4, 14), "%s  sem:%d" % [("Estufa" if e["t"] == "estufa_mini" else "ESTUFA G"), e["sementes"].size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.1, 0.25, 0.1))
	_barra_prog(px, e["prog"], d["t"] * 256)
	_draw_chute_saida(e)
	_badge_saida(e, px)


# ---------------- maquinas ----------------

const MAQ_COR := {
	"maq_pura": Color(0.42, 0.55, 0.30), "maq_blend": Color(0.65, 0.45, 0.20),
	"maq_haxixe": Color(0.42, 0.28, 0.14), "maq_ice": Color(0.45, 0.65, 0.75),
	"maq_cbd": Color(0.25, 0.55, 0.50), "maq_baseado": Color(0.70, 0.65, 0.45),
	"maq_semente": Color(0.45, 0.52, 0.25), "extrator_madeira": Color(0.45, 0.32, 0.18),
	"fab_seda": Color(0.72, 0.72, 0.68), "fab_gelo": Color(0.60, 0.75, 0.85),
	"extrator_areia": Color(0.70, 0.60, 0.40), "fornalha": Color(0.45, 0.30, 0.25),
}


func _draw_maquina(e: Dictionary, px: Rect2) -> void:
	var t: String = e["t"]
	var cor: Color = MAQ_COR.get(t, Color.GRAY)
	# corpo com "chassi"
	draw_rect(px.grow(-2), cor.darkened(0.35), true)
	draw_rect(px.grow(-4), cor, true)
	draw_rect(px.grow(-2), cor.lightened(0.25), false, 2.0)
	for canto in [px.position + Vector2(5, 5), Vector2(px.end.x - 5, px.position.y + 5), px.position + Vector2(5, px.size.y - 5), px.end - Vector2(5, 5)]:
		draw_circle(canto, 1.5, cor.darkened(0.5))  # parafusos
	var c := px.get_center()
	_icone_maquina(t, c, px)
	# chip da cepa travada na linha (GDD §3)
	if e.get("cepa", "") != "":
		draw_circle(px.position + Vector2(8, 8), 5, COR_CEPA.get(e["cepa"], Color.WHITE))
		draw_circle(px.position + Vector2(8, 8), 5, Color.BLACK, false, 1.0)
	# buffers de entrada (bolinhas embaixo)
	var bx := 0
	for k in e.get("ins", {}):
		for i in e["ins"][k]:
			draw_circle(px.position + Vector2(8 + bx * 7, px.size.y - 9), 2.5, Color.WHITE)
			bx += 1
	for cepa_b in e.get("blend", []):
		draw_circle(px.position + Vector2(8 + bx * 7, px.size.y - 9), 3, COR_CEPA.get(cepa_b, Color.WHITE))
		bx += 1
	var total: int = Defs.RECEITAS[t]["t"] * 256 if Defs.RECEITAS.has(t) else 1
	_barra_prog(px, e.get("prog", 0), total)
	_draw_chute_saida(e)
	_badge_saida(e, px)


func _icone_maquina(t: String, c: Vector2, px: Rect2) -> void:
	match t:
		"maq_pura":     # folha grande
			_draw_planta(c + Vector2(0, 9), 15.0, Color(0.55, 0.85, 0.40))
		"maq_blend":    # duas setas se cruzando
			draw_line(c + Vector2(-8, -6), c + Vector2(8, 6), Color.WHITE, 3.0)
			draw_line(c + Vector2(-8, 6), c + Vector2(8, -6), Color(1, 0.8, 0.4), 3.0)
		"maq_haxixe":   # tijolo marrom
			draw_rect(Rect2(c - Vector2(9, 6), Vector2(18, 12)), Color(0.30, 0.18, 0.08), true)
			draw_rect(Rect2(c - Vector2(9, 6), Vector2(18, 12)), Color(0.5, 0.35, 0.2), false, 1.5)
		"maq_ice":      # floco de neve
			for i in 3:
				var ang := i * PI / 3
				draw_line(c - Vector2(cos(ang), sin(ang)) * 9, c + Vector2(cos(ang), sin(ang)) * 9, Color.WHITE, 2.0)
		"maq_cbd":      # gota + frasco
			draw_circle(c + Vector2(0, 2), 6, Color(0.75, 0.95, 0.85))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -10), c + Vector2(-5, -1), c + Vector2(5, -1)]), Color(0.75, 0.95, 0.85))
		"maq_baseado":  # cone de baseado
			draw_colored_polygon(PackedVector2Array([c + Vector2(-10, 6), c + Vector2(10, -2), c + Vector2(8, -6), c + Vector2(-10, 2)]), Color.WHITE)
			draw_circle(c + Vector2(-10, 4), 2.5, Color.ORANGE)
		"maq_semente":  # semente
			draw_circle(c, 5, Color(0.45, 0.30, 0.15))
			draw_circle(c + Vector2(1, -1), 2, Color(0.65, 0.50, 0.30))
		"extrator_madeira":  # serra circular
			draw_circle(c, 8, Color(0.75, 0.75, 0.78))
			for i in 8:
				var ang := i * PI / 4
				draw_circle(c + Vector2(cos(ang), sin(ang)) * 8, 1.5, Color(0.55, 0.55, 0.58))
		"fab_seda":     # folha de papel
			draw_rect(Rect2(c - Vector2(6, 8), Vector2(12, 16)), Color.WHITE, true)
			draw_line(c + Vector2(-3, -4), c + Vector2(3, -4), Color(0.6, 0.6, 0.6), 1.0)
			draw_line(c + Vector2(-3, 0), c + Vector2(3, 0), Color(0.6, 0.6, 0.6), 1.0)
		"fab_gelo":     # cubo de gelo
			draw_rect(Rect2(c - Vector2(7, 7), Vector2(14, 14)), Color(0.80, 0.92, 1.0, 0.9), true)
			draw_rect(Rect2(c - Vector2(7, 7), Vector2(14, 14)), Color.WHITE, false, 1.5)
		"extrator_areia":  # pa
			draw_line(c + Vector2(-4, 8), c + Vector2(2, -4), Color(0.5, 0.35, 0.2), 2.5)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(7, -5), c + Vector2(2, -2)]), Color(0.7, 0.7, 0.75))
		"fornalha":     # boca de fogo
			draw_rect(Rect2(c - Vector2(8, 4), Vector2(16, 10)), Color(0.15, 0.10, 0.10), true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-5, 6), c + Vector2(0, -4), c + Vector2(5, 6)]), Color(1.0, 0.55, 0.10))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-2, 6), c + Vector2(0, 0), c + Vector2(2, 6)]), Color(1.0, 0.85, 0.30))
		_:
			draw_string(_fonte, px.position + Vector2(4, px.size.y / 2), t, HORIZONTAL_ALIGNMENT_LEFT, px.size.x, 10, Color.WHITE)


func _draw_bancada(e: Dictionary, px: Rect2) -> void:
	draw_rect(px.grow(-2), Color(0.55, 0.38, 0.20), true)     # mesa
	draw_rect(px.grow(-2), Color(0.35, 0.22, 0.10), false, 2.0)
	draw_rect(Rect2(px.position + Vector2(8, 6), Vector2(16, 8)), Color(0.70, 0.70, 0.75), true)   # prensa
	draw_rect(Rect2(px.position + Vector2(11, 14), Vector2(10, 6)), Color(0.50, 0.50, 0.55), true)
	if e["prog"] > 0:
		_barra_prog(px, e["prog"], Defs.RECEITAS["bancada"]["t"] * 256)
		draw_string(_fonte, px.position + Vector2(0, -4), "segure E!", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.YELLOW)
	else:
		draw_string(_fonte, px.position + Vector2(2, 30), "prensa", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.8))


func _draw_gerador(e: Dictionary, px: Rect2) -> void:
	draw_rect(px.grow(-3), Color(0.30, 0.30, 0.28), true)
	draw_rect(px.grow(-3), Color(0.45, 0.45, 0.42), false, 2.0)
	var c := px.get_center()
	# raio
	draw_colored_polygon(PackedVector2Array([c + Vector2(2, -10), c + Vector2(-6, 2), c + Vector2(-1, 2), c + Vector2(-3, 10), c + Vector2(6, -2), c + Vector2(1, -2)]), Color.YELLOW)
	# chamine + fumaca quando ligado
	draw_rect(Rect2(px.position + Vector2(px.size.x - 14, 2), Vector2(8, 10)), Color(0.2, 0.2, 0.2), true)
	if e["fuel"] > 0:
		var puff := fmod((Sim.tick * Sim.FRAMES_POR_TICK + Sim._frame_acc) * 0.15, 10.0)
		draw_circle(px.position + Vector2(px.size.x - 10, -2 - puff), 4 + puff * 0.4, Color(0.7, 0.7, 0.7, 0.6 - puff * 0.05))
		draw_rect(Rect2(px.position + Vector2(3, px.size.y - 8), Vector2((px.size.x - 6) * minf(1.0, e["fuel"] / 300.0), 5)), Color.ORANGE, true)
	else:
		draw_string(_fonte, px.position + Vector2(4, px.size.y - 6), "sem lenha", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.RED)


func _draw_solar(px: Rect2) -> void:
	draw_rect(px.grow(-3), Color(0.12, 0.16, 0.35), true)
	for i in range(1, 3):
		draw_line(px.position + Vector2(px.size.x * i / 3.0, 3), px.position + Vector2(px.size.x * i / 3.0, px.size.y - 3), Color(0.4, 0.5, 0.8), 1.5)
		draw_line(px.position + Vector2(3, px.size.y * i / 3.0), px.position + Vector2(px.size.x - 3, px.size.y * i / 3.0), Color(0.4, 0.5, 0.8), 1.5)
	draw_line(px.position + Vector2(5, 8), px.position + Vector2(10, 3), Color(0.9, 0.95, 1.0), 2.0)  # brilho


func _draw_filtro(px: Rect2) -> void:
	draw_rect(px.grow(-3), Color(0.28, 0.28, 0.32), true)
	var c := px.get_center()
	var ang := (Sim.tick * Sim.FRAMES_POR_TICK + Sim._frame_acc) * 0.05
	for i in 3:  # ventoinha girando
		var a := ang + i * TAU / 3
		draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a), sin(a)) * 9, c + Vector2(cos(a + 0.5), sin(a + 0.5)) * 9]), Color(0.6, 0.6, 0.65))
	draw_circle(c, 2.5, Color(0.2, 0.2, 0.2))


func _draw_pc(px: Rect2) -> void:
	draw_rect(Rect2(px.position + Vector2(4, 4), Vector2(24, 16)), Color(0.15, 0.15, 0.18), true)   # monitor
	draw_rect(Rect2(px.position + Vector2(6, 6), Vector2(20, 12)), Color(0.20, 0.55, 0.30), true)   # tela
	draw_string(_fonte, px.position + Vector2(8, 15), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.GREEN_YELLOW)
	draw_rect(Rect2(px.position + Vector2(13, 20), Vector2(6, 3)), Color(0.3, 0.3, 0.3), true)      # pe
	draw_rect(Rect2(px.position + Vector2(5, 24), Vector2(22, 5)), Color(0.35, 0.35, 0.38), true)   # teclado
	draw_string(_fonte, px.position + Vector2(2, -2), "PC (E)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.CYAN)


func _draw_traficante(px: Rect2) -> void:
	var c := px.get_center()
	draw_circle(c, 15, Color(0.55, 0.15, 0.45, 0.25))                      # aura do ponto
	draw_circle(c + Vector2(0, 4), 7, Color(0.25, 0.15, 0.30))             # corpo capuz
	draw_circle(c + Vector2(0, -5), 5, Color(0.15, 0.10, 0.20))            # capuz
	draw_circle(c + Vector2(-1.5, -5), 1, Color.WHITE)                     # olhos na sombra
	draw_circle(c + Vector2(1.5, -5), 1, Color.WHITE)
	draw_string(_fonte, px.position + Vector2(-6, -6), "vende aqui (E)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.5, 0.9))


# ---------------- helpers ----------------

func _barra_prog(px: Rect2, prog: int, total: int) -> void:
	if prog <= 0:
		return
	draw_rect(Rect2(px.position + Vector2(2, px.size.y - 4), Vector2(px.size.x - 4, 3)), Color(0, 0, 0, 0.5), true)
	draw_rect(Rect2(px.position + Vector2(2, px.size.y - 4), Vector2((px.size.x - 4) * clampf(float(prog) / total, 0.0, 1.0), 3)), Color.GREEN_YELLOW, true)


func _badge_saida(e: Dictionary, px: Rect2) -> void:
	if e.get("out_n", 0) > 0:
		var p := Vector2(px.end.x - 9, px.position.y + 9)
		_draw_item(p, e["out_item"])
		draw_string(_fonte, p + Vector2(-4, 14), "x%d" % e["out_n"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)


func _draw_chute_saida(e: Dictionary) -> void:
	var alvo: Vector2i = Sim._celula_frente(e)
	var c := Vector2(alvo) * TILE + Vector2(16, 16)
	var v := Vector2(Sim.DIRS[e["dir"]])
	var base := c - v * 10
	draw_line(base - v * 6, base, Color(1, 1, 0.5, 0.8), 4.0)
	draw_colored_polygon(PackedVector2Array([base + v * 5, base + Vector2(-v.y, v.x) * 4, base - Vector2(-v.y, v.x) * 4]), Color(1, 1, 0.5, 0.8))


# ---------------- itens (icones por produto, cor por cepa) ----------------

func _draw_item(pos: Vector2, item: String) -> void:
	var prod := Defs.item_prod(item)
	var cepa := Defs.item_cepa(item)
	var cor: Color = COR_CEPA.get(cepa, Color(0.5, 0.75, 0.4))
	draw_circle(pos + Vector2(1, 1), 8, Color(0, 0, 0, 0.35))  # sombra
	match prod:
		"bud":
			draw_circle(pos, 7, cor.darkened(0.2))
			draw_circle(pos + Vector2(-2, -2), 3, cor.lightened(0.2))
			draw_circle(pos + Vector2(3, 1), 2.5, cor.lightened(0.35))
			draw_circle(pos + Vector2(-1, 3), 2, Color(0.9, 0.6, 0.3))  # pistilo
		"semente":
			draw_circle(pos, 4.5, Color(0.45, 0.30, 0.15))
			draw_circle(pos + Vector2(1, -1), 1.5, Color(0.68, 0.52, 0.32))
		"prensado":
			draw_rect(Rect2(pos - Vector2(7, 5), Vector2(14, 10)), cor.darkened(0.35), true)
			draw_rect(Rect2(pos - Vector2(7, 5), Vector2(14, 10)), cor, false, 1.5)
		"pura":
			draw_rect(Rect2(pos - Vector2(5, 6), Vector2(10, 12)), Color(0.85, 0.95, 1.0, 0.8), true)  # pote
			draw_circle(pos + Vector2(0, 2), 3.5, cor)
			draw_rect(Rect2(pos - Vector2(5, 8), Vector2(10, 3)), Color(0.3, 0.3, 0.3), true)          # tampa
		"haxixe":
			draw_rect(Rect2(pos - Vector2(7, 5), Vector2(14, 10)), Color(0.28, 0.17, 0.08), true)
			draw_rect(Rect2(pos - Vector2(7, 5), Vector2(14, 10)), Color(0.5, 0.35, 0.2), false, 1.5)
		"ice":
			draw_circle(pos, 6, cor.lightened(0.3))
			for i in 3:
				var ang := i * PI / 3
				draw_line(pos - Vector2(cos(ang), sin(ang)) * 7, pos + Vector2(cos(ang), sin(ang)) * 7, Color.WHITE, 1.5)
		"cbd":
			draw_rect(Rect2(pos - Vector2(4, 3), Vector2(8, 10)), Color(0.4, 0.25, 0.15), true)   # frasco ambar
			draw_rect(Rect2(pos - Vector2(2, 7), Vector2(4, 4)), Color(0.2, 0.2, 0.2), true)      # conta-gotas
			draw_circle(pos + Vector2(0, 1), 2, cor.lightened(0.3))
		"baseado":
			draw_colored_polygon(PackedVector2Array([pos + Vector2(-8, 5), pos + Vector2(8, -3), pos + Vector2(6, -6), pos + Vector2(-8, 1)]), Color.WHITE)
			draw_circle(pos + Vector2(-8, 3), 2, Color.ORANGE)
		"madeira":
			draw_rect(Rect2(pos - Vector2(8, 4), Vector2(16, 8)), Color(0.42, 0.27, 0.12), true)
			draw_circle(pos + Vector2(6, 0), 3, Color(0.60, 0.45, 0.25))
		"seda":
			draw_rect(Rect2(pos - Vector2(6, 7), Vector2(12, 14)), Color(0.95, 0.95, 0.92), true)
			draw_line(pos + Vector2(-3, -3), pos + Vector2(3, -3), Color(0.7, 0.7, 0.7), 1.0)
		"vidro":
			draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -7), pos + Vector2(6, 0), pos + Vector2(0, 7), pos + Vector2(-6, 0)]), Color(0.75, 0.90, 1.0, 0.85))
		"areia":
			draw_circle(pos, 6, Color(0.80, 0.72, 0.48))
			draw_circle(pos + Vector2(-2, -1), 1, Color(0.65, 0.55, 0.35))
			draw_circle(pos + Vector2(2, 2), 1, Color(0.65, 0.55, 0.35))
		"gelo":
			draw_rect(Rect2(pos - Vector2(5, 5), Vector2(10, 10)), Color(0.80, 0.92, 1.0, 0.9), true)
			draw_rect(Rect2(pos - Vector2(5, 5), Vector2(10, 10)), Color.WHITE, false, 1.5)
		"blend_sativa", "blend_indica", "blend_hibrida":
			var c2: Color = {"blend_sativa": Color(0.75, 0.80, 0.25), "blend_indica": Color(0.45, 0.30, 0.70), "blend_hibrida": Color(0.35, 0.55, 0.85)}[prod]
			draw_circle(pos, 7, c2)
			draw_circle(pos + Vector2(-2, -2), 4, c2.lightened(0.4))
			draw_circle(pos, 7, Color.BLACK, false, 1.0)
		_:
			draw_circle(pos, 7, Color.GRAY)


# ---------------- ghost de construcao ----------------

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
	draw_rect(px, Color(0, 1, 0, 0.30) if ok else Color(1, 0, 0, 0.30), true)
	draw_rect(px, Color(0, 1, 0, 0.8) if ok else Color(1, 0, 0, 0.8), false, 2.0)
	var fake := {"t": ui.build_type, "pos": cell, "dir": ui.rot}
	if Defs.RECEITAS.has(ui.build_type) or Defs.ESTUFAS.has(ui.build_type):
		_draw_chute_saida(fake)
	elif ui.build_type == "esteira":
		var v := Vector2(Sim.DIRS[ui.rot])
		var cc := px.get_center()
		draw_colored_polygon(PackedVector2Array([cc + v * 10, cc - v * 4 + Vector2(-v.y, v.x) * 6, cc - v * 4 - Vector2(-v.y, v.x) * 6]), Color(1, 1, 1, 0.8))
	draw_string(_fonte, px.position + Vector2(0, -6), "%s  (R gira)" % Defs.PREDIOS[ui.build_type]["nome"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
