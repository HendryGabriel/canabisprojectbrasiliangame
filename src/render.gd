extends Node2D
# Renderizador procedural detalhado: desenha o estado da Sim por cima (GDD Â§9).
# Tudo em codigo â€” quando os sprites chegarem em assets/, substituem estes desenhos
# sem tocar na simulacao.

const DefsData := preload("res://src/defs.gd")
const TILE := DefsData.TILE_SIZE
const HALF_TILE := TILE * 0.5
const Icons := preload("res://src/icons.gd")

# cor base por cepa (folha/bud/chip nas maquinas)
const COR_CEPA := {
	"ruderalis": Color(0.45, 0.60, 0.30), "jack_herer": Color(0.35, 0.75, 0.30),
	"sour_diesel": Color(0.75, 0.80, 0.25), "durban_poison": Color(0.20, 0.65, 0.45),
	"northern_lights": Color(0.30, 0.45, 0.75), "granddaddy_purple": Color(0.55, 0.30, 0.70),
	"purple_kush": Color(0.45, 0.20, 0.60), "blue_dream": Color(0.35, 0.55, 0.85),
	"gsc": Color(0.70, 0.50, 0.25), "og_kush": Color(0.25, 0.55, 0.20),
}

var ui: CanvasLayer
var _fonte: Font
var _has_painted_interior_walls := false
var _traficante_pos := Vector2.ZERO
var _money_antes := -1
var _floats: Array = []  # {pos, txt, ttl, cor}


func _ready() -> void:
	_fonte = ThemeDB.fallback_font
	var interior_walls_layer := get_parent().get_node_or_null("InteriorWalls") as TileMapLayer
	_has_painted_interior_walls = interior_walls_layer != null and not interior_walls_layer.get_used_cells().is_empty()
	_carrega_atlases()
	for id in Sim.ents:
		if Sim.ents[id]["t"] == "traficante":
			_traficante_pos = _cell_center(Sim.ents[id]["pos"])


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


# ---------------- decor manual: pedras, vegetacao e arvores dos atlases ----------------
# As celulas vem das camadas ObjectsTrees, ObjectsTallGrass e ObjectsRocks.

const VEG_TRONCOS := [Rect2(197, 65, 34, 31), Rect2(196, 98, 39, 46)]
const VEG_COPAS := [Rect2(2, 5, 43, 91), Rect2(50, 5, 43, 91), Rect2(98, 5, 43, 91), Rect2(146, 5, 43, 91)]
const PEDRAS_CINZAS := [Rect2(131, 19, 26, 27), Rect2(161, 17, 31, 14), Rect2(144, 51, 15, 10)]

var _atlas: Array = [null, null, null]  # [rocks, vegetation, tallgrass]
var _arado: Texture2D                   # terra arada (sprite do canteiro)


func _carrega_atlases() -> void:
	# ImageTexture recriada: CompressedTexture2D renderiza branco (mesmo bug das maquinas)
	_atlas[0] = ImageTexture.create_from_image(load("res://src/ASSETS/STATIC/Rocks.png").get_image())
	_atlas[1] = ImageTexture.create_from_image(load("res://src/ASSETS/STATIC/Vegetation.png").get_image())
	_atlas[2] = ImageTexture.create_from_image(load("res://src/ASSETS/EARLYGAME/TALLGRASS.png").get_image())
	var ar: Image = load("res://src/ASSETS/STATIC/arado.png").get_image()
	ar.convert(Image.FORMAT_RGBA8)
	_arado = ImageTexture.create_from_image(ar.get_region(ar.get_used_rect()))  # corta o fundo


func _draw_decor(vis: Rect2) -> void:
	var alcance := vis.grow(TILE * 6)
	for cell in Sim.decor_cells():
		var t := Sim.decor_terrain(cell)
		if t == Sim.T.GRAMA:
			continue
		var base := Vector2((cell.x + 0.5) * TILE, (cell.y + 1) * TILE)
		if not alcance.has_point(base):
			continue
		match t:
			Sim.T.ARVORE:
				_draw_tree_decor(cell, base)
			Sim.T.PEDRA:
				_draw_rock_decor(cell, base)
			Sim.T.MATO:
				_draw_tallgrass_decor(cell, base)


func _draw_tree_decor(cell: Vector2i, base: Vector2) -> void:
	var tr: Rect2 = VEG_TRONCOS[Sim.cell_hash(cell, 10) % VEG_TRONCOS.size()]
	var sorteio := Sim.cell_hash(cell, 11) % 20
	var co: Rect2 = VEG_COPAS[0]
	if sorteio >= 9 and sorteio < 18:
		co = VEG_COPAS[1]
	elif sorteio == 18:
		co = VEG_COPAS[2]
	elif sorteio == 19:
		co = VEG_COPAS[3]
	var th := TILE * 1.6
	var tw := tr.size.x * th / tr.size.y
	var ch := TILE * 3.6
	var cw := co.size.x * ch / co.size.y
	draw_texture_rect_region(_atlas[1], Rect2(base.x - tw * 0.5, base.y - th, tw, th), tr)
	draw_texture_rect_region(_atlas[1], Rect2(base.x - cw * 0.5, base.y - th * 0.7 - ch, cw, ch), co)


func _draw_rock_decor(cell: Vector2i, base: Vector2) -> void:
	var pr: Rect2 = PEDRAS_CINZAS[Sim.cell_hash(cell, 17) % PEDRAS_CINZAS.size()]
	var ph := minf(TILE * 1.1, pr.size.y * TILE / 16.0)
	var pw := pr.size.x * ph / pr.size.y
	draw_texture_rect_region(_atlas[0], Rect2(base.x - pw * 0.5, base.y - ph, pw, ph), pr)


func _draw_tallgrass_decor(cell: Vector2i, base: Vector2) -> void:
	var tex2: Texture2D = _atlas[2]
	var lado := float(TILE) * (0.9 + 0.25 * (Sim.cell_hash(cell, 16) % 3))
	draw_texture_rect_region(tex2, Rect2(base.x - lado * 0.5, base.y - lado, lado, lado), Rect2(Vector2.ZERO, tex2.get_size()))


# ---------------- draw principal ----------------

func _draw() -> void:
	# culling: so desenha o que a camera ve (fabricas grandes continuam a 60fps)
	var vis: Rect2 = (get_canvas_transform().affine_inverse() * get_viewport_rect()).grow(TILE * 2)
	_draw_decor(vis)
	if not _has_painted_interior_walls:
		_draw_casa()
	var ids := Sim.ents.keys()
	ids.sort()
	# canos e esteiras primeiro (chao), depois maquinas (em cima)
	for id in ids:
		var e: Dictionary = Sim.ents[id]
		if (e["t"] == "cano" or e["t"] == "esteira") and vis.intersects(_ent_rect(e)):
			_draw_ent(e)
	for id in ids:
		var e: Dictionary = Sim.ents[id]
		if e["t"] != "cano" and e["t"] != "esteira" and vis.intersects(_ent_rect(e)):
			_draw_ent(e)
	for f in _floats:
		draw_string(_fonte, f["pos"], f["txt"], HORIZONTAL_ALIGNMENT_CENTER, -1, 16, f["cor"])
	_draw_ghost()


func _ent_rect(e: Dictionary) -> Rect2:
	var tam: Vector2i = Defs.PREDIOS[e["t"]]["tam"] if Defs.PREDIOS.has(e["t"]) else Vector2i(1, 1)
	return _grid_rect(e["pos"], tam)


func _grid_rect(pos: Vector2i, tam: Vector2i) -> Rect2:
	return Rect2(Vector2(pos) * TILE, Vector2(tam) * TILE)


func _draw_texture_in_grid(texture: Texture2D, pos: Vector2i, tam: Vector2i) -> void:
	draw_texture_rect(texture, _grid_rect(pos, tam), false)


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE + Vector2(HALF_TILE, HALF_TILE)


func _draw_casa() -> void:
	# paredes da casa com porta embaixo (o avatar nasce na porta)
	var cor := Color(0.32, 0.20, 0.11)
	var p := Vector2(4, 3) * TILE
	var s := Vector2(7, 6) * TILE
	draw_line(p + Vector2(-2, 0), p + Vector2(s.x + 2, 0), cor, 6.0)
	draw_line(p, p + Vector2(0, s.y), cor, 6.0)
	draw_line(p + Vector2(s.x, 0), p + s, cor, 6.0)
	draw_line(p + Vector2(0, s.y), p + Vector2(3 * TILE, s.y), cor, 6.0)   # porta no tile 7
	draw_line(p + Vector2(4 * TILE, s.y), p + s, cor, 6.0)
	draw_rect(Rect2(p + Vector2(3 * TILE, s.y - 2), Vector2(TILE, 4)), Color(0.65, 0.50, 0.30), true)  # soleira


func _draw_ent(e: Dictionary) -> void:
	var t: String = e["t"]
	var tam: Vector2i = Defs.PREDIOS[t]["tam"] if Defs.PREDIOS.has(t) else Vector2i(1, 1)
	var px := _grid_rect(e["pos"], tam)
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

const COR_SUPERFICIE := Color(0.13, 0.13, 0.15)
const COR_GOMO := Color(0.24, 0.24, 0.28)
const COR_TRILHO := Color(0.55, 0.53, 0.48)
const COR_CHEVRON := Color(0.95, 0.78, 0.18, 0.95)


func _draw_esteira(e: Dictionary, px: Rect2) -> void:
	# estilo Factorio: superficie escura CONTINUA entre tiles (tampa so nas pontas da
	# linha), gomos e chevrons amarelos animados correndo na direcao do fluxo.
	# Posicoes calculadas em coordenada de MUNDO -> tiles vizinhos emendam sem costura.
	var dir: int = e["dir"]
	var v := Vector2(Sim.DIRS[dir])
	var p := Vector2(-v.y, v.x)
	var c := px.get_center()
	var anim := (Sim.tick * Sim.FRAMES_POR_TICK + Sim._frame_acc) * 0.35
	var curva := _curva_esteira(e, dir)
	if curva != 0:
		_draw_esteira_curva(c, dir, curva, anim)
		if e["item"] != "":
			var frac0 := clampf((e["prog"] + Sim._frame_acc / float(Sim.FRAMES_POR_TICK)) / Sim.BELT_T, 0.0, 1.0)
			_draw_item(c + v * (frac0 - 0.5) * TILE, e["item"])
		return
	var horizontal := dir == 1 or dir == 3
	draw_rect(px, COR_SUPERFICIE, true)  # superficie
	# trilhos laterais (bordas perpendiculares ao fluxo)
	var trilho := COR_TRILHO
	if horizontal:
		draw_rect(Rect2(px.position, Vector2(TILE, 2)), trilho, true)
		draw_rect(Rect2(px.position + Vector2(0, TILE - 2), Vector2(TILE, 2)), trilho, true)
	else:
		draw_rect(Rect2(px.position, Vector2(2, TILE)), trilho, true)
		draw_rect(Rect2(px.position + Vector2(TILE - 2, 0), Vector2(2, TILE)), trilho, true)
	# fase LOCAL igual em todo tile (periodos dividem o tile: gomos 8px, chevron 16px)
	# -> todas as esteiras animam em sincronia e o padrao emenda perfeito entre tiles,
	# em qualquer direcao. Offset medido da borda de TRAS, andando na direcao do fluxo.
	var tras := c - v * HALF_TILE
	var ot := fmod(anim, 8.0)
	for k in 3:
		var og := ot + k * 8.0
		if og < TILE:
			var pg := tras + v * og
			draw_line(pg + p * (HALF_TILE - 2.0), pg - p * (HALF_TILE - 2.0), COR_GOMO, 1.5)
	# chevron amarelo (1 por tile, correndo em fase com os vizinhos)
	var pt := tras + v * fmod(anim, float(TILE))
	draw_line(pt - v * 2.5 + p * 3.0, pt + v * 2.5, COR_CHEVRON, 1.5)
	draw_line(pt + v * 2.5, pt - v * 2.5 - p * 3.0, COR_CHEVRON, 1.5)
	# tampas so onde a linha comeca/termina (vizinho nao e esteira)
	var atras = Sim.ent_em(e["pos"] - Sim.DIRS[dir])
	var frente = Sim.ent_em(e["pos"] + Sim.DIRS[dir])
	if atras == null or atras["t"] != "esteira":
		_tampa_esteira(px, -v, trilho)
	if frente == null or frente["t"] != "esteira":
		_tampa_esteira(px, v, trilho)
	if e["item"] != "":
		# interpolacao suave entre ticks (GDD Â§9: sim discreta, visual fluido)
		var frac := clampf((e["prog"] + Sim._frame_acc / float(Sim.FRAMES_POR_TICK)) / Sim.BELT_T, 0.0, 1.0)
		_draw_item(c + v * (frac - 0.5) * TILE, e["item"])


func _curva_esteira(e: Dictionary, dir: int) -> int:
	# 0 = reta; 1 = curva canonica (alimentada pelo lado (dir+1)%4); -1 = espelhada.
	# Regra Factorio: alimentacao por tras vence; senao, exatamente UM lado alimentando
	# vira curva; dois lados (T) ou nenhum = reta.
	var atras = Sim.ent_em(e["pos"] - Sim.DIRS[dir])
	if atras != null and atras["t"] == "esteira" and atras["dir"] == dir:
		return 0
	var lado_a := (dir + 1) % 4
	var lado_b := (dir + 3) % 4
	var va = Sim.ent_em(e["pos"] + Sim.DIRS[lado_a])
	var vb = Sim.ent_em(e["pos"] + Sim.DIRS[lado_b])
	var alimenta_a: bool = va != null and va["t"] == "esteira" and va["dir"] == lado_b
	var alimenta_b: bool = vb != null and vb["t"] == "esteira" and vb["dir"] == lado_a
	if alimenta_a and not alimenta_b:
		return 1
	if alimenta_b and not alimenta_a:
		return -1
	return 0


func _draw_esteira_curva(c: Vector2, dir: int, lado: int, anim: float) -> void:
	# quarto-de-anel canonico (entra pelo Oeste, sai pro Sul, pivo no canto SO);
	# rotacao leva pro `dir` real e o espelho cobre a entrada pelo outro lado
	draw_set_transform(c, (dir - 2) * PI / 2.0, Vector2(lado, 1))
	var P := Vector2(-HALF_TILE, HALF_TILE)  # pivo: canto da curva
	var pts := PackedVector2Array()
	for i in 9:  # borda externa do anel
		var a := -PI / 2.0 + i * PI / 16.0
		pts.append(P + Vector2(cos(a), sin(a)) * (TILE - 2.0))
	for i in 9:  # borda interna (volta)
		var a2 := -i * PI / 16.0
		pts.append(P + Vector2(cos(a2), sin(a2)) * 2.0)
	draw_colored_polygon(pts, COR_SUPERFICIE)
	draw_arc(P, TILE - 1.0, -PI / 2.0, 0.0, 10, COR_TRILHO, 2.0)   # trilho externo
	draw_arc(P, 1.5, -PI / 2.0, 0.0, 6, COR_TRILHO, 2.0)           # trilho interno
	# gomos radiais em fase com as retas: mesma fracao do caminho -> emenda sincronizada
	# (2 gomos por tile na reta = 2 por arco; chevron 1 por tile = 1 por arco)
	var a0 := -PI / 2.0 + fmod(anim, 8.0) / 8.0 * (PI / 4.0)
	for k in 2:
		var ag := a0 + k * PI / 4.0
		if ag < 0.0:
			var dv := Vector2(cos(ag), sin(ag))
			draw_line(P + dv * 4.0, P + dv * (TILE - 3.0), COR_GOMO, 1.5)
	# chevron seguindo o arco, na mesma fracao do caminho das retas
	var ac := -PI / 2.0 + fmod(anim, float(TILE)) / TILE * (PI / 2.0)
	var pm := P + Vector2(cos(ac), sin(ac)) * HALF_TILE
	var tg := Vector2(-sin(ac), cos(ac))
	var pp := Vector2(cos(ac), sin(ac))
	draw_line(pm - tg * 2.5 + pp * 3.0, pm + tg * 2.5, COR_CHEVRON, 1.5)
	draw_line(pm + tg * 2.5, pm - tg * 2.5 - pp * 3.0, COR_CHEVRON, 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _tampa_esteira(px: Rect2, lado: Vector2, cor: Color) -> void:
	# barra na borda apontada por `lado` (fecha a ponta da linha de esteiras)
	if lado.x > 0.0:
		draw_rect(Rect2(px.position + Vector2(TILE - 3, 0), Vector2(3, TILE)), cor, true)
	elif lado.x < 0.0:
		draw_rect(Rect2(px.position, Vector2(3, TILE)), cor, true)
	elif lado.y > 0.0:
		draw_rect(Rect2(px.position + Vector2(0, TILE - 3), Vector2(TILE, 3)), cor, true)
	else:
		draw_rect(Rect2(px.position, Vector2(TILE, 3)), cor, true)


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
	if _arado != null:
		# sprite de terra arada; mais clarinho enquanto seco (esperando rega)
		var mod := Color(1.2, 1.1, 0.95) if fase == 1 else Color.WHITE
		draw_texture_rect(_arado, px, false, mod)
	else:
		var solo := Color(0.42, 0.30, 0.18) if fase == 1 else Color(0.30, 0.20, 0.12)
		draw_rect(px.grow(-2), solo, true)
		draw_rect(px.grow(-2), Color(0.20, 0.13, 0.08), false, 2.0)
		for i in 3:  # sulcos
			var sy: float = px.position.y + 8 + i * 8
			draw_line(Vector2(px.position.x + 4, sy), Vector2(px.end.x - 4, sy), solo.darkened(0.25), 2.0)
	var c := px.get_center()
	var cor: Color = COR_CEPA.get(e["cepa"], Color(0.4, 0.7, 0.3))
	match fase:
		1:  # plantado, seco â€” esperando rega
			draw_circle(c, 3, Color(0.75, 0.65, 0.40))
			draw_string(_fonte, px.position + Vector2(1, 11), "seco!", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.YELLOW)
		2:  # crescendo â€” broto escala com o tempo
			var g: float = clampf(float(e["tempo"]) / Defs.STRAINS[e["cepa"]]["grow"], 0.0, 1.0)
			_draw_planta(c + Vector2(0, 6), 4.0 + g * 10.0, cor.darkened(0.15))
		3:  # pronto â€” pe cheio de buds brilhando
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
	var d: Dictionary = Defs.ESTUFAS[e["t"]]
	var g: float = clampf(float(e["prog"]) / (d["t"] * 256), 0.0, 1.0)
	var cor: Color = COR_CEPA.get(e.get("cepa_ciclo", ""), Color(0.3, 0.6, 0.3))
	var tex := _sprite_maq(e["t"])
	if tex != null:
		draw_texture_rect(tex, px, false)  # sprite fornecido preenche o tile, centralizado
	else:
		draw_rect(px.grow(-2), Color(0.55, 0.58, 0.55), true)               # base
		draw_rect(px.grow(-4), Color(0.65, 0.85, 0.90, 0.75), true)          # vidro
		for i in range(1, 4):                                                # caixilhos
			var gx: float = px.position.x + px.size.x * i / 4.0
			draw_line(Vector2(gx, px.position.y + 4), Vector2(gx, px.end.y - 4), Color.WHITE * Color(1, 1, 1, 0.6), 2.0)
		draw_line(px.position + Vector2(4, px.size.y / 2), px.position + Vector2(px.size.x - 4, px.size.y / 2), Color(1, 1, 1, 0.6), 2.0)
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
	var tex := _sprite_maq(t)
	if tex != null:
		draw_texture_rect(tex, px, false)  # sprite fornecido preenche o tile, centralizado
	else:
		var cor: Color = MAQ_COR.get(t, Color.GRAY)
		# corpo com "chassi"
		draw_rect(px.grow(-2), cor.darkened(0.35), true)
		draw_rect(px.grow(-4), cor, true)
		draw_rect(px.grow(-2), cor.lightened(0.25), false, 2.0)
		for canto in [px.position + Vector2(5, 5), Vector2(px.end.x - 5, px.position.y + 5), px.position + Vector2(5, px.size.y - 5), px.end - Vector2(5, 5)]:
			draw_circle(canto, 1.5, cor.darkened(0.5))  # parafusos
		_icone_maquina(t, px.get_center(), px)
	# chip da cepa travada na linha (GDD Â§3)
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


func _icone_maquina(t: String, c: Vector2, _px: Rect2) -> void:
	Icons.desenha(self, t, c, 1.0, false)  # mesmo icone da hotbar, sem o chassi


var _spr_cache := {}
func _sprite_maq(t: String) -> Texture2D:
	if not Defs.MACHINE_SPRITES.has(t):
		return null
	if not _spr_cache.has(t):
		var info: Array = Defs.MACHINE_SPRITES[t]
		var img: Image = load(info[0]).get_image()
		var r: Rect2 = info[1]
		if r.size.x > 0:
			img = img.get_region(Rect2i(r))  # recorta a maquina da folha
		_spr_cache[t] = ImageTexture.create_from_image(img)
	return _spr_cache[t]


func _draw_bancada(e: Dictionary, px: Rect2) -> void:
	var tex := _sprite_maq("bancada")
	if tex != null:
		draw_texture_rect(tex, px, false)
	else:
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


func _celula_na_dir(pos: Vector2i, tam: Vector2i, dir: int) -> Vector2i:
	match dir:
		0: return Vector2i(pos.x + (tam.x - 1) / 2, pos.y - 1)
		1: return Vector2i(pos.x + tam.x, pos.y + (tam.y - 1) / 2)
		2: return Vector2i(pos.x + (tam.x - 1) / 2, pos.y + tam.y)
		_: return Vector2i(pos.x - 1, pos.y + (tam.y - 1) / 2)


func _seta(c: Vector2, v: Vector2, cor: Color) -> void:
	# seta pequena colada na lateral do tile (fora dele)
	v = v.normalized()
	var p := Vector2(-v.y, v.x)
	draw_line(c - v * 3.0, c + v * 1.5, cor, 2.0)
	draw_colored_polygon(PackedVector2Array([c + v * 4.0, c - v * 0.5 + p * 3.0, c - v * 0.5 - p * 3.0]), cor)


func _draw_chute_saida(e: Dictionary) -> void:
	var tam: Vector2i = Defs.PREDIOS[e["t"]]["tam"] if Defs.PREDIOS.has(e["t"]) else Vector2i.ONE
	var px := _grid_rect(e["pos"], tam)
	var ctr := px.get_center()
	var dir: int = e["dir"]
	var vo := Vector2(Sim.DIRS[dir])
	# saida: colada na lateral da frente, um pouco pra fora (amarelo)
	var borda_out := ctr + Vector2(vo.x * px.size.x * 0.5, vo.y * px.size.y * 0.5)
	_seta(borda_out + vo * 4.0, vo, Color(1, 0.85, 0.2, 0.95))
	# entrada: lado oposto, apontando pra dentro (azul)
	var vi := Vector2(Sim.DIRS[(dir + 2) % 4])
	var borda_in := ctr + Vector2(vi.x * px.size.x * 0.5, vi.y * px.size.y * 0.5)
	_seta(borda_in + vi * 4.0, -vi, Color(0.35, 0.75, 1.0, 0.95))


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
	var px := _grid_rect(cell, tam)
	var ok := true
	for dx in tam.x:
		for dy in tam.y:
			var c: Vector2i = cell + Vector2i(dx, dy)
			if Sim.grid.has(c) or not Sim.dentro_do_mapa(c):
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
