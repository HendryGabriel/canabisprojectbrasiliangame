extends CanvasLayer
# HUD + hotbar de construcao + loja do PC + mensagens + vitoria. Tudo em codigo.

const TILE := 32
const Icons := preload("res://src/icons.gd")

const NUM_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]

var build_type := ""
var rot := 1  # 0 N, 1 E, 2 S, 3 O
var _slots_tipos: Array = []  # ordem dos predios na hotbar (p/ teclas 1-9,0)
var _topo: Label
var _inv_lbl: Label
var _msg_lbl: Label
var _msg_timer := 0.0
var _hotbar: HBoxContainer
var _shop: PanelContainer
var _shop_box: VBoxContainer
var _tier_hotbar := -1


func _ready() -> void:
	_topo = _label(Vector2(8, 4), 16)
	_inv_lbl = _label(Vector2(8, 622), 14)
	_msg_lbl = _label(Vector2(8, 30), 18)
	_msg_lbl.modulate = Color.YELLOW

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

	Sim.msg.connect(_on_msg)
	Sim.vitoria_sig.connect(_on_vitoria)
	_on_msg("Bem-vindo! Plante no quintal (canteiro na hotbar). E interage, R gira, botão direito remove.")


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
	var luz := " LUZ CORTADA!" if Sim.luz_cortada else ""
	_topo.text = "$ %d   |   Energia: %d (própria %d, conta $%d/10s)%s   |   Calor: %d/100   |   Tier %d   |   %s" % [
		Sim.money, Sim.energia_uso, Sim.ger_propria, Sim.conta_ultima, luz, Sim.heat, Sim.tier, meta]
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
	if _tier_hotbar != Sim.tier:
		_tier_hotbar = Sim.tier
		_monta_hotbar()


func _on_msg(texto: String) -> void:
	_msg_lbl.text = texto
	_msg_timer = 5.0


func _monta_hotbar() -> void:
	for c in _hotbar.get_children():
		c.queue_free()
	_slots_tipos = []
	for t in Defs.PREDIOS:
		if Defs.PREDIOS[t]["tier"] > Sim.tier:
			continue
		_slots_tipos.append(t)
		_hotbar.add_child(Slot.new(t, _slots_tipos.size(), self))


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.physical_keycode:
			KEY_R:
				rot = (rot + 1) % 4
			KEY_ESCAPE:
				if _shop.visible:
					_shop.visible = false
				else:
					build_type = ""
			KEY_TAB:
				toggle_shop()
			KEY_Q:
				build_type = ""
			_:
				# teclas 1-9,0 selecionam o slot da hotbar (aperta de novo = solta)
				var idx := NUM_KEYS.find(ev.physical_keycode)
				if idx >= 0 and idx < _slots_tipos.size() and not _shop.visible:
					build_type = "" if build_type == _slots_tipos[idx] else _slots_tipos[idx]
	elif ev is InputEventMouseButton and ev.pressed and not _shop.visible:
		var cell := _mouse_cell()
		if ev.button_index == MOUSE_BUTTON_LEFT and build_type != "":
			if not Sim.cmd_place(build_type, cell, rot):
				_on_msg("Não dá pra construir aí (dinheiro, terreno ou lote).")
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			if build_type != "":
				build_type = ""
			else:
				Sim.cmd_remove(cell)


func _mouse_cell() -> Vector2i:
	var main := get_parent() as Node2D
	return Vector2i((main.get_global_mouse_position() / TILE).floor())


# ---------------- loja (PC) ----------------

func toggle_shop() -> void:
	_shop.visible = not _shop.visible
	if _shop.visible:
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
		if s["tier"] > Sim.tier:
			continue
		var b := Button.new()
		b.text = "Semente %s [%s] — $%d  (bud vende a $%d)" % [s["nome"], Defs.CAT_NOME[s["cat"]], s["semente"], s["preco"]]
		b.pressed.connect(func():
			if not Sim.cmd_buy_seed(cepa):
				_on_msg("Dinheiro insuficiente.")
			_monta_shop())
		_shop_box.add_child(b)

	_shop_box.add_child(_sep("Terreno"))
	if Sim.lotes_comprados < Defs.LOTES.size():
		var lb := Button.new()
		lb.text = "Comprar Lote %d — $%d" % [Sim.lotes_comprados, Defs.LOTES[Sim.lotes_comprados]["custo"]]
		lb.pressed.connect(func():
			if not Sim.cmd_buy_lote():
				_on_msg("Dinheiro insuficiente.")
			_monta_shop())
		_shop_box.add_child(lb)
	else:
		_shop_box.add_child(_sep("(todo o terreno é seu)"))

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
		Icons.desenha(self, tipo, Vector2(27, 28), 1.0)
		if not pode:
			draw_rect(Rect2(1, 1, 52, 52), Color(0, 0, 0, 0.55), true)
		draw_rect(Rect2(1, 1, 52, 52), Color.YELLOW if sel else Color(0.42, 0.42, 0.48), false, 2.0 if sel else 1.0)
		if num <= 10:
			draw_rect(Rect2(3, 3, 12, 13), Color(0, 0, 0, 0.6), true)
			draw_string(ThemeDB.fallback_font, Vector2(6, 14), str(num % 10), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		draw_string(ThemeDB.fallback_font, Vector2(0, 66), "$%d" % d["custo"], HORIZONTAL_ALIGNMENT_CENTER, 54, 11, Color.GREEN_YELLOW if pode else Color(1, 0.4, 0.4))

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
