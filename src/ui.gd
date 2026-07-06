extends CanvasLayer
# HUD + hotbar de construcao + loja do PC + mensagens + vitoria. Tudo em codigo.

const DefsData := preload("res://src/defs.gd")
const TILE := DefsData.TILE_SIZE
const Icons := preload("res://src/icons.gd")

const NUM_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]

var build_type := ""
var rot := 1  # 0 N, 1 E, 2 S, 3 O
var cam: Camera2D
var _slots_tipos: Array = []  # ordem dos predios na hotbar (p/ teclas 1-9,0)
var _topo: Label
var _inv_lbl: Label
var _msg_lbl: Label
var _dica_lbl: Label
var _coord_lbl: Label
var _msg_timer := 0.0
var _hotbar: HBoxContainer
var _shop: PanelContainer
var _shop_box: VBoxContainer
var _tier_hotbar := -1
var _hover: PanelContainer
var _hover_lbl: Label
var _drag_build := false
var _drag_prev := Vector2i.ZERO
var _drag_rem := false
var _tutorial: Array = []   # passos {txt, ok:Callable} — avanca sozinho lendo a Sim
var _tut_passo := 0
var _tut_off := false
var _tut_panel: PanelContainer
var _tut_lbl: Label
var _shop_aberto := false


func _ready() -> void:
	_topo = _label(Vector2(8, 4), 16)
	_inv_lbl = _label(Vector2(8, 622), 14)
	_dica_lbl = _label(Vector2(8, 56), 14)
	_dica_lbl.modulate = Color(0.6, 0.9, 1.0)
	_msg_lbl = _label(Vector2(8, 76), 18)
	_msg_lbl.modulate = Color.YELLOW
	_coord_lbl = _label(Vector2(8, 104), 13)
	_coord_lbl.modulate = Color(0.85, 0.95, 1.0)

	var barras := Barras.new()
	barras.position = Vector2(8, 26)
	add_child(barras)

	_hover = PanelContainer.new()
	_hover.visible = false
	_hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_lbl = Label.new()
	_hover_lbl.add_theme_font_size_override("font_size", 13)
	_hover_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover.add_child(_hover_lbl)
	add_child(_hover)

	_hotbar = HBoxContainer.new()
	_hotbar.position = Vector2(8, 644)
	_hotbar.add_theme_constant_override("separation", 4)
	add_child(_hotbar)

	_shop = PanelContainer.new()
	_shop.position = Vector2(340, 60)
	_shop.custom_minimum_size = Vector2(600, 560)
	_shop.visible = false
	add_child(_shop)
	var scroll := ScrollContainer.new()
	_shop.add_child(scroll)
	_shop_box = VBoxContainer.new()
	_shop_box.custom_minimum_size = Vector2(580, 0)
	scroll.add_child(_shop_box)

	_tut_panel = PanelContainer.new()
	_tut_panel.position = Vector2(890, 40)
	add_child(_tut_panel)
	var tv := VBoxContainer.new()
	_tut_panel.add_child(tv)
	_tut_lbl = Label.new()
	_tut_lbl.custom_minimum_size = Vector2(370, 0)
	_tut_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tut_lbl.add_theme_font_size_override("font_size", 14)
	tv.add_child(_tut_lbl)
	_monta_tutorial()

	Sim.msg.connect(_on_msg)
	Sim.vitoria_sig.connect(_on_vitoria)
	_on_msg("Bem-vindo! Você chegou de mudança. Siga o TUTORIAL à direita.")


func _label(pos: Vector2, tam: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l


func _process(delta: float) -> void:
	var meta := ""
	if Sim.meta_atual < Defs.METAS.size():
		var m: Dictionary = Defs.METAS[Sim.meta_atual]
		meta = "META: %s (%d/%d)" % [m["desc"], Sim.meta_progresso(), m["qtd"]]
	else:
		meta = "Sandbox — você é o Maior Produtor"
	var devtag := "  [ MODO DEV — F2 ]" if Sim.dev else ""
	_topo.text = "$ %d   |   Tier %d   |   %s   |   %d fps%s" % [Sim.money, Sim.tier, meta, Engine.get_frames_per_second(), devtag]
	_topo.modulate = Color(1, 0.6, 1) if Sim.dev else Color.WHITE
	_coord_lbl.text = _coord_text()
	_dica_lbl.text = _dica()
	_atualiza_hover()
	_atualiza_tutorial()
	var linhas := []
	var chaves := Sim.inv.keys()
	chaves.sort()
	for k in chaves:
		linhas.append("%s x%d" % [Defs.item_nome(k), Sim.inv[k]])
	_inv_lbl.text = "Inventário: " + (", ".join(linhas) if linhas.size() else "(vazio)")
	if _msg_timer > 0:
		_msg_timer -= delta
		if _msg_timer <= 0:
			_msg_lbl.text = ""
	if _tier_hotbar != Sim.tier + (1000 if Sim.dev else 0):
		_tier_hotbar = Sim.tier + (1000 if Sim.dev else 0)
		_monta_hotbar()


func _on_msg(texto: String) -> void:
	_msg_lbl.text = texto
	_msg_timer = 5.0


func _monta_hotbar() -> void:
	for c in _hotbar.get_children():
		c.queue_free()
	_slots_tipos = []
	for t in Defs.PREDIOS:
		if not Sim.dev and Defs.PREDIOS[t]["tier"] > Sim.tier:
			continue
		_slots_tipos.append(t)
		_hotbar.add_child(Slot.new(t, _slots_tipos.size(), self))


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.physical_keycode:
			KEY_R:
				if build_type != "":
					rot = (rot + 1) % 4
				else:
					# R sobre um predio existente: gira ele
					var e = Sim.ent_em(_mouse_cell())
					if e != null and e.has("dir"):
						Sim.cmd_rotate(e["pos"], (e["dir"] + 1) % 4)
			KEY_ESCAPE:
				if _shop.visible:
					_shop.visible = false
				else:
					build_type = ""
			KEY_TAB:
				toggle_shop()
			KEY_Q:
				build_type = ""
			KEY_T:
				_tut_off = not _tut_off
			KEY_F2:
				Sim.cmd_dev_toggle()
			_:
				# teclas 1-9,0 selecionam o slot da hotbar (aperta de novo = solta)
				var idx := NUM_KEYS.find(ev.physical_keycode)
				if idx >= 0 and idx < _slots_tipos.size() and not _shop.visible:
					build_type = "" if build_type == _slots_tipos[idx] else _slots_tipos[idx]
	elif ev is InputEventMouseButton:
		if ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(1.15)
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0 / 1.15)
		elif _shop.visible:
			pass
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed and build_type != "":
				_drag_prev = _mouse_cell()
				_tenta_construir(_drag_prev)
				_drag_build = true
			elif not ev.pressed:
				_drag_build = false
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			if ev.pressed:
				if build_type != "":
					build_type = ""
				else:
					Sim.cmd_remove(_mouse_cell())
					_drag_rem = true
			else:
				_drag_rem = false
	elif ev is InputEventMouseMotion and not _shop.visible:
		if _drag_build and (build_type == "esteira" or build_type == "cano"):
			# arrastar pinta uma linha; esteiras viram sozinhas na direcao do arrasto
			var cell := _mouse_cell()
			while cell != _drag_prev:
				var d := cell - _drag_prev
				var passo := Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
				if build_type == "esteira":
					rot = Sim.DIRS.find(passo)
					var ant = Sim.ent_em(_drag_prev)
					if ant != null and ant["t"] == "esteira":
						Sim.cmd_rotate(_drag_prev, rot)  # linha continua
				_drag_prev += passo
				_tenta_construir(_drag_prev)
		elif _drag_rem:
			Sim.cmd_remove(_mouse_cell())


func _zoom(f: float) -> void:
	if cam != null:
		var z: float = clampf(cam.zoom.x * f, 1.2, 5.2)
		cam.zoom = Vector2(z, z)


func _tenta_construir(cell: Vector2i) -> void:
	if not Sim.cmd_place(build_type, cell, rot):
		var motivo := Sim.motivo_nao_construir(build_type, cell)
		if motivo != "" and motivo != "Espaço ocupado":  # ocupado no arrasto e normal, sem spam
			_on_msg(motivo)


func _mouse_cell() -> Vector2i:
	var main := get_parent() as Node2D
	return Vector2i((main.get_global_mouse_position() / TILE).floor())


func _coord_text() -> String:
	var mc := _mouse_cell()
	return "Mouse %s   |   Player %s" % [Sim.coord_label(mc), Sim.coord_label(Sim.player_cell)]


# ---------------- loja (PC) ----------------

func toggle_shop() -> void:
	_shop.visible = not _shop.visible
	if _shop.visible:
		_shop_aberto = true
		_monta_shop()


func _monta_shop() -> void:
	for c in _shop_box.get_children():
		c.queue_free()
	var titulo := Label.new()
	titulo.text = "== PC — COMPRAS =="
	titulo.add_theme_font_size_override("font_size", 20)
	_shop_box.add_child(titulo)

	_shop_box.add_child(_sep("Sementes (Tier atual: %d)" % Sim.tier))
	for cepa in Defs.STRAINS:
		var s: Dictionary = Defs.STRAINS[cepa]
		if not Sim.dev and s["tier"] > Sim.tier:
			continue
		var b := Button.new()
		b.text = "Semente %s [%s] — $%d  (bud vende a $%d)" % [s["nome"], Defs.CAT_NOME[s["cat"]], s["semente"], s["preco"]]
		b.pressed.connect(func():
			if not Sim.cmd_buy_seed(cepa):
				_on_msg("Dinheiro insuficiente.")
			_monta_shop())
		_shop_box.add_child(b)

	_shop_box.add_child(_sep("Serviços"))
	var adv := Button.new()
	adv.text = "Advogado (Calor -30) — $500"
	adv.pressed.connect(func():
		if not Sim.cmd_advogado():
			_on_msg("Sem dinheiro (ou sem calor).")
		_monta_shop())
	_shop_box.add_child(adv)

	var fechar := Button.new()
	fechar.text = "Fechar (Esc)"
	fechar.pressed.connect(func(): _shop.visible = false)
	_shop_box.add_child(fechar)


func _sep(texto: String) -> Label:
	var l := Label.new()
	l.text = "\n" + texto
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	return l


# ---------------- tutorial (quests do inicio) ----------------

func _monta_tutorial() -> void:
	_tutorial = [
		{"txt": "Ande com WASD ou as setas até o quintal (atrás da casa).",
			"ok": func() -> bool: return Sim.player_cell != Vector2i(7, 10)},
		{"txt": "Aperte Tab (ou E no PC da casa) pra abrir a loja. Você já tem 3 sementes de Ruderalis. Feche com Esc.",
			"ok": func() -> bool: return _shop_aberto},
		{"txt": "Coloque um Canteiro: aperte a tecla 2 e clique num tile de grama do quintal.",
			"ok": func() -> bool: return _canteiro_fase(0)},
		{"txt": "Plante: chegue perto do canteiro e aperte E.",
			"ok": func() -> bool: return _canteiro_fase(1)},
		{"txt": "A planta está SECA. Aperte E de novo pra regar.",
			"ok": func() -> bool: return _canteiro_fase(2)},
		{"txt": "Espere crescer (uns 10 segundos) e colha com E quando aparecer \"PRONTO\".",
			"ok": func() -> bool: return _tem_prod("bud")},
		{"txt": "Venda: leve os buds até o TRAFICANTE no beco escuro (à esquerda da casa) e aperte E.",
			"ok": func() -> bool: return Sim.vendas.get("bud", 0) > 0},
		{"txt": "Plante mais e junte 2 buds da mesma cepa. Na BANCADA da cozinha, segure E pra prensar (vale 2.6x mais!).",
			"ok": func() -> bool: return _tem_prod("prensado")},
		{"txt": "Agora escale: venda 20 buds pra cumprir a META (topo da tela) e destravar o Tier 1 — esteiras, máquinas e estufas!",
			"ok": func() -> bool: return Sim.tier >= 1},
		{"txt": "Tier 1! Coloque uma Máquina de Pura, ligue esteiras (arraste com o botão esquerdo) dela até o traficante, e alimente com buds. Fábrica começando!",
			"ok": func() -> bool: return Sim.vendas.get("pura", 0) > 0},
	]


func _atualiza_tutorial() -> void:
	if _tut_off or _tut_passo >= _tutorial.size():
		_tut_panel.visible = false
		return
	_tut_panel.visible = true
	var passo: Dictionary = _tutorial[_tut_passo]
	if passo["ok"].call():
		_tut_passo += 1
		if _tut_passo >= _tutorial.size():
			_on_msg("✓ Tutorial completo! Agora siga as METAS no topo da tela. Boa sorte!")
		else:
			_on_msg("✓ Passo concluído!")
		return
	_tut_lbl.text = "TUTORIAL — passo %d de %d\n\n%s\n\n(T esconde o tutorial)" % [_tut_passo + 1, _tutorial.size(), passo["txt"]]


func _canteiro_fase(minimo: int) -> bool:
	for id in Sim.ents:
		var e: Dictionary = Sim.ents[id]
		if e["t"] == "canteiro" and e["fase"] >= minimo:
			return true
	return false


func _tem_prod(prod: String) -> bool:
	if Sim.vendas.get(prod, 0) > 0:
		return true
	for k in Sim.inv:
		if Defs.item_prod(k) == prod:
			return true
	return false


# ---------------- hover: o que essa coisa esta fazendo? ----------------

func _atualiza_hover() -> void:
	var mc := _mouse_cell()
	var e = Sim.ent_em(mc)
	var ter := Sim.terreno_em(mc)
	var obst := ter == Sim.T.MATO or ter == Sim.T.PEDRA
	if build_type != "" or _shop.visible or (e == null and not obst):
		_hover.visible = false
		return
	_hover.visible = true
	if e != null:
		_hover_lbl.text = _info_ent(e)
	else:
		_hover_lbl.text = "Mato alto — aperte E pra limpar o terreno" if ter == Sim.T.MATO else "Pedra — aperte E pra tirar do caminho"
	_hover.reset_size()
	var mp := get_viewport().get_mouse_position() + Vector2(18, 18)
	var tela := get_viewport().get_visible_rect().size
	mp.x = clampf(mp.x, 0, tela.x - _hover.size.x - 8)
	mp.y = clampf(mp.y, 0, tela.y - _hover.size.y - 8)
	_hover.position = mp


func _info_ent(e: Dictionary) -> String:
	var t: String = e["t"]
	var l: Array = []
	match t:
		"pc":
			return "PC — aperte E pra comprar"
		"traficante":
			return "Traficante do beco\nVenda com E ou entregue por esteira\n(vender aumenta o calor!)"
		"esteira":
			l.append("Esteira")
			if e["item"] != "":
				l.append("Levando: " + Defs.item_nome(e["item"]))
		"cano", "poco":
			l.append("Poço (+3 água/tick)" if t == "poco" else "Cano")
			var n: int = e.get("net", -1)
			if n >= 0 and n < Sim.redes.size():
				l.append("Água na rede: %d / %d" % [Sim.redes[n]["vol"], Sim.redes[n]["cap"]])
		"canteiro":
			l.append("Canteiro")
			if e["cepa"] != "":
				l.append("Cepa: " + Defs.STRAINS[e["cepa"]]["nome"])
			match e["fase"]:
				0: l.append("Vazio — E pra plantar")
				1: l.append("SECO — E pra regar")
				2: l.append("Crescendo... faltam %ds" % maxi(0, floori(float(Defs.STRAINS[e["cepa"]]["grow"] - e["tempo"]) / 10.0)))
				3: l.append("PRONTO — E pra colher")
		"bancada":
			l.append("Bancada de Prensa (manual)")
			l.append("2x Bud → 1x Prensado")
			l.append("Segure E com 2 buds da mesma cepa")
		"gerador":
			l.append("Gerador a Biomassa (+30 energia)")
			l.append("Queima madeira/buds (esteira ou E)")
			l.append("Combustível: %ds" % floori(float(e["fuel"]) / 10.0) if e["fuel"] > 0 else "SEM COMBUSTÍVEL")
		"solar":
			return "Painel Solar (+6 energia)"
		"filtro":
			return "Filtro de Carvão\nReduz o calor por venda"
		_:
			if Defs.ESTUFAS.has(t):
				var d: Dictionary = Defs.ESTUFAS[t]
				l.append(Defs.PREDIOS[t]["nome"])
				l.append("1 Semente + %d água → %d Buds" % [d["agua"], d["buds"]])
				l.append("Sementes na fila: %d" % e["sementes"].size())
				if e["prog"] > 0:
					l.append("Ciclo (%s): %d%%" % [Defs.STRAINS[e["cepa_ciclo"]]["nome"], floori(float(e["prog"] * 100) / float(d["t"] * 256))])
				elif e["sementes"].is_empty():
					l.append("PARADA: sem sementes")
				elif Sim._rede_adjacente(e) < 0:
					l.append("PARADA: sem cano com água do lado")
			elif Defs.RECEITAS.has(t):
				var r: Dictionary = Defs.RECEITAS[t]
				l.append(Defs.PREDIOS[t]["nome"])
				l.append(_nome_receita(r))
				if e.get("cepa", "") != "":
					l.append("Linha travada: " + Defs.STRAINS[e["cepa"]]["nome"])
				for k in e.get("ins", {}):
					if e["ins"][k] > 0:
						l.append("Dentro: %dx %s" % [e["ins"][k], Defs.PROD_NOME.get(k, k)])
				for cepa_b in e.get("blend", []):
					l.append("Dentro: Bud " + Defs.STRAINS[cepa_b]["nome"])
				if e["prog"] > 0:
					l.append("Produzindo: %d%%" % floori(float(e["prog"] * 100) / float(r["t"] * 256)))
				if r.get("agua", 0) > 0 and Sim._rede_adjacente(e) < 0:
					l.append("PARADA: precisa de cano com água do lado")
	if e.get("out_n", 0) > 0:
		l.append("Saída: %dx %s (E coleta)" % [e["out_n"], Defs.item_nome(e["out_item"])])
	var energia: int = Defs.PREDIOS[t]["energia"] if Defs.PREDIOS.has(t) else 0
	if energia > 0 and Sim.fator < 256:
		l.append("ENERGIA FRACA: rodando a %d%%" % floori(float(Sim.fator * 100) / 256.0))
	return "\n".join(l)


func _nome_receita(r: Dictionary) -> String:
	var ins: Array = []
	for k in r["in"]:
		if k == "bud2cat":
			ins.append("2x Bud (cepas diferentes, mesma categoria)")
		else:
			ins.append("%dx %s" % [r["in"][k], Defs.PROD_NOME.get(k, k)])
	if r.get("agua", 0) > 0:
		ins.append("%d água" % r["agua"])
	var out: String = "Blend" if r["out"] == "blend" else Defs.PROD_NOME.get(r["out"], r["out"])
	return "%s → %dx %s" % [" + ".join(ins) if ins.size() else "(nada)", r["n"], out]


# ---------------- dica contextual (o que fazer agora) ----------------

func _dica() -> String:
	if Sim.venceu:
		return ""
	if Sim.luz_cortada:
		return "DICA: sem luz! Venda algo pra pagar a conta na próxima cobrança"
	if Sim.heat >= 70:
		return "DICA: calor alto — pare de vender um pouco ou contrate o advogado no PC"
	if _tut_passo < _tutorial.size() and not _tut_off:
		return ""  # tutorial ativo ja guia; dica so pros avisos urgentes acima
	var tem_canteiro := false
	var seco := false
	var pronto := false
	var tem_auto := false
	for id in Sim.ents:
		var e: Dictionary = Sim.ents[id]
		if e["t"] == "canteiro":
			tem_canteiro = true
			seco = seco or e["fase"] == 1
			pronto = pronto or e["fase"] == 3
		elif Defs.RECEITAS.has(e["t"]) and not Defs.RECEITAS[e["t"]].get("manual", false):
			tem_auto = true
	if pronto:
		return "DICA: colheita pronta! Aperte E no canteiro"
	if seco:
		return "DICA: planta seca — aperte E no canteiro pra regar"
	if not tem_canteiro:
		return "DICA: coloque um canteiro no quintal (tecla 2) e plante uma semente (E)"
	var tem_semente := false
	var buds := 0
	for k in Sim.inv:
		if Defs.item_prod(k) == "semente":
			tem_semente = true
		elif Defs.item_prod(k) == "bud":
			buds += Sim.inv[k]
	if buds >= 2:
		return "DICA: venda buds no beco (E no traficante) ou prense 2 na bancada da cozinha"
	if not tem_semente and buds == 0:
		return "DICA: compre sementes no PC (Tab ou E no PC)"
	if Sim.tier >= 1 and not tem_auto:
		return "DICA: Tier 1! Monte uma Máquina de Pura com esteiras levando até o beco"
	return ""


class Barras extends Control:
	# energia (quanto da fabrica roda com geracao propria) e calor da policia
	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var f := ThemeDB.fallback_font
		var cob := 1.0 if Sim.energia_uso == 0 else clampf(float(Sim.ger_propria) / Sim.energia_uso, 0.0, 1.0)
		draw_string(f, Vector2(0, 11), "Energia", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		draw_rect(Rect2(58, 2, 140, 11), Color(0.12, 0.12, 0.16, 0.9), true)
		draw_rect(Rect2(58, 2, 140 * cob, 11), Color(0.30, 0.75, 0.40), true)   # verde = geracao propria
		draw_rect(Rect2(58, 2, 140, 11), Color(0.5, 0.5, 0.55), false, 1.0)
		var txt := "uso %d | própria %d | conta $%d/10s" % [Sim.energia_uso, Sim.ger_propria, Sim.conta_ultima]
		if Sim.luz_cortada:
			txt += "  LUZ CORTADA!"
		draw_string(f, Vector2(204, 11), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.RED if Sim.luz_cortada else Color(0.85, 0.85, 0.9))
		draw_string(f, Vector2(0, 27), "Calor", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		var hc := Color(0.3, 0.8, 0.3).lerp(Color(0.95, 0.2, 0.2), Sim.heat / 100.0)
		draw_rect(Rect2(58, 18, 140, 11), Color(0.12, 0.12, 0.16, 0.9), true)
		draw_rect(Rect2(58, 18, 140 * Sim.heat / 100.0, 11), hc, true)
		draw_rect(Rect2(58, 18, 140, 11), Color(0.5, 0.5, 0.55), false, 1.0)
		if Sim.heat >= 70:
			draw_string(f, Vector2(204, 27), "POLÍCIA DE OLHO!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.RED)


class Slot extends Control:
	# slot da hotbar: icone procedural + numero do atalho + preco
	var tipo := ""
	var num := 0
	var dono: CanvasLayer

	func _init(t: String, n: int, u: CanvasLayer) -> void:
		tipo = t
		num = n
		dono = u
		custom_minimum_size = Vector2(54, 70)
		var d: Dictionary = Defs.PREDIOS[t]
		var extra := ""
		if d["energia"] > 0:
			extra = "\nEnergia: %d" % d["energia"]
		elif d["energia"] < 0:
			extra = "\nGera energia: %d" % -d["energia"]
		tooltip_text = "%s\nCusto: $%d — %dx%d%s" % [d["nome"], d["custo"], d["tam"].x, d["tam"].y, extra]

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var d: Dictionary = Defs.PREDIOS[tipo]
		var sel: bool = dono.build_type == tipo
		var pode: bool = Sim.money >= d["custo"]
		draw_rect(Rect2(1, 1, 52, 52), Color(0.10, 0.10, 0.14, 0.92), true)
		if Defs.MACHINE_SPRITES.has(tipo):
			draw_texture_rect(_spr(tipo), Rect2(4, 4, 46, 46), false)
		else:
			Icons.desenha(self, tipo, Vector2(27, 28), 1.0)
		if not pode:
			draw_rect(Rect2(1, 1, 52, 52), Color(0, 0, 0, 0.55), true)
		draw_rect(Rect2(1, 1, 52, 52), Color.YELLOW if sel else Color(0.42, 0.42, 0.48), false, 2.0 if sel else 1.0)
		if num <= 10:
			draw_rect(Rect2(3, 3, 12, 13), Color(0, 0, 0, 0.6), true)
			draw_string(ThemeDB.fallback_font, Vector2(6, 14), str(num % 10), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		draw_string(ThemeDB.fallback_font, Vector2(0, 66), "$%d" % d["custo"], HORIZONTAL_ALIGNMENT_CENTER, 54, 11, Color.GREEN_YELLOW if pode else Color(1, 0.4, 0.4))

	# CompressedTexture2D renderiza branco via draw_texture_rect; ImageTexture resolve.
	static var _tex_cache := {}
	static func _spr(tipo: String) -> Texture2D:
		if not _tex_cache.has(tipo):
			var info: Array = Defs.MACHINE_SPRITES[tipo]
			var img: Image = load(info[0]).get_image()
			var r: Rect2 = info[1]
			if r.size.x > 0:
				img = img.get_region(Rect2i(r))
			_tex_cache[tipo] = ImageTexture.create_from_image(img)
		return _tex_cache[tipo]

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			dono.build_type = "" if dono.build_type == tipo else tipo
			accept_event()


func _on_vitoria() -> void:
	var v := _label(Vector2(240, 280), 34)
	v.text = "VOCÊ VIROU O MAIOR PRODUTOR!\n(o sandbox continua — GDD §1)"
	v.modulate = Color.GOLD
	var t := get_tree().create_timer(8.0)
	t.timeout.connect(func(): v.queue_free())
