extends Object
# Icones procedurais dos predios: usados na hotbar (ui.gd) e nas maquinas do mundo
# (render.gd). Um desenho so por tipo - sprites depois substituem aqui.

static func desenha(ci: CanvasItem, t: String, c: Vector2, s: float = 1.0, caixa: bool = true) -> void:
	# caixa=false: so o simbolo (usado nas maquinas do mundo, que ja tem chassi proprio)
	match t:
		"esteira":
			ci.draw_rect(Rect2(c - Vector2(12, 9) * s, Vector2(24, 18) * s), Color(0.28, 0.28, 0.32), true)
			ci.draw_rect(Rect2(c - Vector2(12, 6) * s, Vector2(24, 12) * s), Color(0.48, 0.48, 0.54), true)
			for i in 2:
				var b := c + Vector2((i * 12 - 6) * s, 0)
				ci.draw_colored_polygon(PackedVector2Array([b + Vector2(5, 0) * s, b + Vector2(-3, 6) * s, b + Vector2(-3, -6) * s]), Color(0.78, 0.78, 0.84))
		"cano":
			ci.draw_line(c + Vector2(-11, 4) * s, c + Vector2(3, 4) * s, Color(0.55, 0.55, 0.60), 9.0 * s)
			ci.draw_line(c + Vector2(3, 4) * s, c + Vector2(3, -10) * s, Color(0.55, 0.55, 0.60), 9.0 * s)
			ci.draw_line(c + Vector2(-11, 4) * s, c + Vector2(3, 4) * s, Color(0.25, 0.60, 0.90), 5.0 * s)
			ci.draw_line(c + Vector2(3, 4) * s, c + Vector2(3, -10) * s, Color(0.25, 0.60, 0.90), 5.0 * s)
			ci.draw_circle(c + Vector2(3, 4) * s, 5.0 * s, Color(0.62, 0.62, 0.68))
		"poco":
			ci.draw_circle(c, 11 * s, Color(0.48, 0.48, 0.52))
			ci.draw_circle(c, 7.5 * s, Color(0.22, 0.22, 0.26))
			ci.draw_circle(c, 5.5 * s, Color(0.20, 0.45, 0.78))
			ci.draw_rect(Rect2(c - Vector2(2, 16) * s, Vector2(4, 6) * s), Color(0.5, 0.35, 0.2), true)
		"canteiro":
			ci.draw_rect(Rect2(c - Vector2(11, 8) * s, Vector2(22, 16) * s), Color(0.36, 0.25, 0.14), true)
			ci.draw_line(c + Vector2(-8, 0) * s, c + Vector2(8, 0) * s, Color(0.28, 0.18, 0.10), 2.0 * s)
			_folha(ci, c + Vector2(0, 2) * s, 10.0 * s, Color(0.40, 0.75, 0.35))
		"bancada":
			ci.draw_rect(Rect2(c - Vector2(12, 4) * s, Vector2(24, 10) * s), Color(0.55, 0.38, 0.20), true)
			ci.draw_rect(Rect2(c - Vector2(9, 14) * s, Vector2(18, 6) * s), Color(0.70, 0.70, 0.76), true)
			ci.draw_rect(Rect2(c - Vector2(4, 8) * s, Vector2(8, 5) * s), Color(0.52, 0.52, 0.58), true)
			ci.draw_line(c + Vector2(0, -14) * s, c + Vector2(0, -8) * s, Color(0.35, 0.35, 0.40), 3.0 * s)
		"maq_pura":
			if caixa:
				_caixa(ci, c, s, Color(0.42, 0.55, 0.30))
			_folha(ci, c + Vector2(0, 7) * s, 13.0 * s, Color(0.55, 0.88, 0.40))
		"maq_semente":
			if caixa:
				_caixa(ci, c, s, Color(0.45, 0.52, 0.25))
			ci.draw_circle(c, 5 * s, Color(0.45, 0.30, 0.15))
			ci.draw_circle(c + Vector2(1.5, -1.5) * s, 2 * s, Color(0.68, 0.52, 0.32))
		"estufa_mini", "estufa_grande":
			var w := (10.0 if t == "estufa_mini" else 13.0) * s
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-w, -2 * s), c + Vector2(0, -12 * s), c + Vector2(w, -2 * s)]), Color(0.80, 0.92, 0.95))
			ci.draw_rect(Rect2(c + Vector2(-w, -2 * s), Vector2(w * 2, 12 * s)), Color(0.65, 0.85, 0.90, 0.85), true)
			ci.draw_line(c + Vector2(0, -2 * s), c + Vector2(0, 10 * s), Color.WHITE, 1.5)
			_folha(ci, c + Vector2(0, 9) * s, 7.0 * s, Color(0.30, 0.65, 0.30))
		"maq_blend":
			if caixa:
				_caixa(ci, c, s, Color(0.65, 0.45, 0.20))
			ci.draw_line(c + Vector2(-8, -6) * s, c + Vector2(8, 6) * s, Color.WHITE, 3.0 * s)
			ci.draw_line(c + Vector2(-8, 6) * s, c + Vector2(8, -6) * s, Color(1, 0.8, 0.4), 3.0 * s)
		"maq_baseado":
			if caixa:
				_caixa(ci, c, s, Color(0.70, 0.65, 0.45))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-9, 6) * s, c + Vector2(9, -2) * s, c + Vector2(7, -6) * s, c + Vector2(-9, 2) * s]), Color.WHITE)
			ci.draw_circle(c + Vector2(-9, 4) * s, 2.5 * s, Color.ORANGE)
		"maq_haxixe":
			if caixa:
				_caixa(ci, c, s, Color(0.42, 0.28, 0.14))
			ci.draw_rect(Rect2(c - Vector2(8, 5) * s, Vector2(16, 10) * s), Color(0.28, 0.17, 0.08), true)
			ci.draw_rect(Rect2(c - Vector2(8, 5) * s, Vector2(16, 10) * s), Color(0.5, 0.35, 0.2), false, 1.5)
		"maq_ice":
			if caixa:
				_caixa(ci, c, s, Color(0.45, 0.65, 0.75))
			for i in 3:
				var ang := i * PI / 3
				ci.draw_line(c - Vector2(cos(ang), sin(ang)) * 8 * s, c + Vector2(cos(ang), sin(ang)) * 8 * s, Color.WHITE, 2.0 * s)
		"maq_cbd":
			if caixa:
				_caixa(ci, c, s, Color(0.25, 0.55, 0.50))
			ci.draw_circle(c + Vector2(0, 3) * s, 5 * s, Color(0.75, 0.95, 0.85))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9) * s, c + Vector2(-4.5, -1) * s, c + Vector2(4.5, -1) * s]), Color(0.75, 0.95, 0.85))
		"extrator_madeira":
			if caixa:
				_caixa(ci, c, s, Color(0.45, 0.32, 0.18))
			ci.draw_circle(c, 7 * s, Color(0.75, 0.75, 0.78))
			for i in 8:
				var ang := i * PI / 4
				ci.draw_circle(c + Vector2(cos(ang), sin(ang)) * 7 * s, 1.5 * s, Color(0.55, 0.55, 0.58))
			ci.draw_circle(c, 2 * s, Color(0.4, 0.4, 0.44))
		"fab_seda":
			if caixa:
				_caixa(ci, c, s, Color(0.72, 0.72, 0.68))
			ci.draw_rect(Rect2(c - Vector2(5, 7) * s, Vector2(10, 14) * s), Color.WHITE, true)
			ci.draw_line(c + Vector2(-3, -3) * s, c + Vector2(3, -3) * s, Color(0.6, 0.6, 0.6), 1.0)
			ci.draw_line(c + Vector2(-3, 0) * s, c + Vector2(3, 0) * s, Color(0.6, 0.6, 0.6), 1.0)
			ci.draw_line(c + Vector2(-3, 3) * s, c + Vector2(3, 3) * s, Color(0.6, 0.6, 0.6), 1.0)
		"fab_gelo":
			if caixa:
				_caixa(ci, c, s, Color(0.60, 0.75, 0.85))
			ci.draw_rect(Rect2(c - Vector2(6, 6) * s, Vector2(12, 12) * s), Color(0.80, 0.92, 1.0, 0.9), true)
			ci.draw_rect(Rect2(c - Vector2(6, 6) * s, Vector2(12, 12) * s), Color.WHITE, false, 1.5)
		"extrator_areia":
			if caixa:
				_caixa(ci, c, s, Color(0.70, 0.60, 0.40))
			ci.draw_line(c + Vector2(-4, 8) * s, c + Vector2(2, -4) * s, Color(0.5, 0.35, 0.2), 2.5 * s)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8) * s, c + Vector2(7, -5) * s, c + Vector2(2, -2) * s]), Color(0.72, 0.72, 0.78))
		"fornalha":
			if caixa:
				_caixa(ci, c, s, Color(0.45, 0.30, 0.25))
			ci.draw_rect(Rect2(c - Vector2(8, 3) * s, Vector2(16, 10) * s), Color(0.15, 0.10, 0.10), true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-5, 7) * s, c + Vector2(0, -3) * s, c + Vector2(5, 7) * s]), Color(1.0, 0.55, 0.10))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-2, 7) * s, c + Vector2(0, 1) * s, c + Vector2(2, 7) * s]), Color(1.0, 0.85, 0.30))
		"gerador":
			if caixa:
				_caixa(ci, c, s, Color(0.30, 0.30, 0.28))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(2, -10) * s, c + Vector2(-6, 2) * s, c + Vector2(-1, 2) * s, c + Vector2(-3, 10) * s, c + Vector2(6, -2) * s, c + Vector2(1, -2) * s]), Color.YELLOW)
		"solar":
			ci.draw_rect(Rect2(c - Vector2(11, 9) * s, Vector2(22, 18) * s), Color(0.12, 0.16, 0.35), true)
			for i in range(1, 3):
				ci.draw_line(c + Vector2(-11 + 22 * i / 3.0, -9) * s, c + Vector2(-11 + 22 * i / 3.0, 9) * s, Color(0.4, 0.5, 0.8), 1.5)
			ci.draw_line(c + Vector2(-11, 0) * s, c + Vector2(11, 0) * s, Color(0.4, 0.5, 0.8), 1.5)
			ci.draw_line(c + Vector2(-8, -5) * s, c + Vector2(-4, -9) * s, Color(0.9, 0.95, 1.0), 2.0)
		"filtro":
			if caixa:
				_caixa(ci, c, s, Color(0.28, 0.28, 0.32))
			for i in 3:
				var a := i * TAU / 3 + 0.5
				ci.draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a), sin(a)) * 8 * s, c + Vector2(cos(a + 0.5), sin(a + 0.5)) * 8 * s]), Color(0.62, 0.62, 0.68))
			ci.draw_circle(c, 2.5 * s, Color(0.18, 0.18, 0.20))
		_:
			ci.draw_circle(c, 9 * s, Color.GRAY)


static func _caixa(ci: CanvasItem, c: Vector2, s: float, cor: Color) -> void:
	# chassi padrao de maquina, atras do icone
	ci.draw_rect(Rect2(c - Vector2(12, 11) * s, Vector2(24, 22) * s), cor.darkened(0.3), true)
	ci.draw_rect(Rect2(c - Vector2(10, 9) * s, Vector2(20, 18) * s), cor, true)
	ci.draw_rect(Rect2(c - Vector2(12, 11) * s, Vector2(24, 22) * s), cor.lightened(0.25), false, 1.5)


static func _folha(ci: CanvasItem, base: Vector2, altura: float, cor: Color) -> void:
	ci.draw_line(base, base + Vector2(0, -altura), Color(0.25, 0.40, 0.15), 2.0)
	for i in 3:
		var h := altura * (0.35 + i * 0.3)
		var w := altura * (0.55 - i * 0.12)
		var o := base + Vector2(0, -h)
		ci.draw_colored_polygon(PackedVector2Array([o, o + Vector2(-w, -3), o + Vector2(-w * 0.5, -6)]), cor)
		ci.draw_colored_polygon(PackedVector2Array([o, o + Vector2(w, -3), o + Vector2(w * 0.5, -6)]), cor)
