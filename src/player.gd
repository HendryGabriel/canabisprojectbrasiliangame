extends Node2D
# Avatar: movimento livre em 8 direcoes (GDD §10). So as construcoes respeitam o grid.
# O player NAO faz parte da sim deterministica; ele injeta comandos (cmd_*).

const TILE := 32
const VEL := 150.0

var ui: CanvasLayer
var facing := Vector2i(0, 1)


func _ready() -> void:
	position = Vector2(7.5, 10.5) * TILE  # porta da casa


func _physics_process(delta: float) -> void:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): v.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): v.x += 1
	if v != Vector2.ZERO:
		v = v.normalized() * VEL * delta
		facing = Vector2i(v.sign())
		var np := position + Vector2(v.x, 0)
		if _anda(np):
			position = np
		np = position + Vector2(0, v.y)
		if _anda(np):
			position = np
	Sim.player_cell = Vector2i((position / TILE).floor())
	# segurar E na bancada = prensar manual (GDD §5)
	if Input.is_physical_key_pressed(KEY_E):
		var alvo := _celula_alvo()
		var e = Sim.ent_em(alvo)
		if e != null and e["t"] == "bancada" and _perto(alvo):
			Sim.cmd_bancada(alvo)
	queue_redraw()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.physical_keycode == KEY_E:
		var alvo := _celula_alvo()
		if not _perto(alvo):
			return
		var e = Sim.ent_em(alvo)
		if e != null and e["t"] == "pc":
			ui.toggle_shop()
		elif e != null and e["t"] != "bancada":
			Sim.cmd_interact(alvo)


func _celula_alvo() -> Vector2i:
	# mira: celula do mouse se perto; senao a celula a frente do avatar
	var m := Vector2i((get_global_mouse_position() / TILE).floor())
	if _perto(m) and Sim.ent_em(m) != null:
		return m
	return Vector2i((position / TILE).floor()) + facing


func _perto(c: Vector2i) -> bool:
	return Vector2(c * TILE + Vector2i(16, 16)).distance_to(position) < TILE * 2.5


func _anda(p: Vector2) -> bool:
	var c := Vector2i((p / TILE).floor())
	var t := Sim.terreno_em(c)
	if t == Sim.T.AGUA or t == Sim.T.ARVORE or not Sim.celula_comprada(c):
		return false
	var e = Sim.ent_em(c)
	if e != null and e["t"] != "esteira" and e["t"] != "cano" and e["t"] != "canteiro":
		return false
	return true


func _draw() -> void:
	# bonequinho: sombra, corpo, cabeca, bone; olhos seguem a direcao
	draw_circle(Vector2(0, 8), 8, Color(0, 0, 0, 0.3))
	draw_rect(Rect2(-6, -4, 12, 13), Color(0.20, 0.45, 0.25), true)      # camisa
	draw_rect(Rect2(-5, 7, 4, 5), Color(0.25, 0.25, 0.35), true)         # pernas
	draw_rect(Rect2(1, 7, 4, 5), Color(0.25, 0.25, 0.35), true)
	draw_circle(Vector2(0, -9), 7, Color(0.95, 0.80, 0.62))              # cabeca
	draw_rect(Rect2(-7, -16, 14, 5), Color(0.60, 0.20, 0.20), true)      # bone
	var f := Vector2(facing).normalized() * 2.5
	draw_circle(Vector2(-2.5, -9) + f, 1.2, Color.BLACK)                 # olhos
	draw_circle(Vector2(2.5, -9) + f, 1.2, Color.BLACK)
	# realce da celula alvo de interacao
	var alvo := _celula_alvo()
	if _perto(alvo) and Sim.ent_em(alvo) != null:
		draw_rect(Rect2(Vector2(alvo * TILE) - position, Vector2(TILE, TILE)), Color(1, 1, 1, 0.5), false, 2.0)
