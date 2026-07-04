extends Node2D
# Avatar: movimento livre em 8 direcoes (GDD §10). So as construcoes respeitam o grid.
# O player NAO faz parte da sim deterministica; ele injeta comandos (cmd_*).

const DefsData := preload("res://src/defs.gd")
const TILE := DefsData.TILE_SIZE
const VEL := TILE * 4.6875
const HALF_TILE := TILE * 0.5

var ui: CanvasLayer
var facing := Vector2i(0, 1)
var _walk := 0.0  # fase da animacao de andar

const ASSET_DIR := "res://Vector Parts/"
const SPRITE_SCALE := 0.20

var tex_body := {}
var tex_head := {}
var tex_face := {}
var tex_l_arm := {}
var tex_r_arm := {}
var tex_l_hand := {}
var tex_r_hand := {}
var tex_l_leg := {}
var tex_r_leg := {}

# Joint positions relative to Body center (in unscaled pixels 0..160)
var joint_offsets := {
	"Front": {
		"neck": Vector2(0, -35),
		"face": Vector2(-1, -33),
		"l_shoulder": Vector2(45, -31),
		"r_shoulder": Vector2(-47, -31),
		"l_hip": Vector2(-17, 29),
		"r_hip": Vector2(17, 29),
		"l_wrist": Vector2(9, 44),
		"r_wrist": Vector2(-5, 44)
	},
	"Back": {
		"neck": Vector2(0, -35),
		"face": Vector2.ZERO,
		"l_shoulder": Vector2(45, -31),
		"r_shoulder": Vector2(-47, -31),
		"l_hip": Vector2(-17, 29),
		"r_hip": Vector2(17, 29),
		"l_wrist": Vector2(9, 44),
		"r_wrist": Vector2(-5, 44)
	},
	"L View": {
		"neck": Vector2(2, -35),
		"face": Vector2(-45, -33),
		"l_shoulder": Vector2(-9, -31),
		"r_shoulder": Vector2(9, -31),
		"l_hip": Vector2(-10, 29),
		"r_hip": Vector2(5, 29),
		"l_wrist": Vector2(-2, 44),
		"r_wrist": Vector2(0, 44)
	},
	"R View": {
		"neck": Vector2(-2, -35),
		"face": Vector2(45, -33),
		"l_shoulder": Vector2(-9, -31),
		"r_shoulder": Vector2(9, -31),
		"l_hip": Vector2(-5, 29),
		"r_hip": Vector2(10, 29),
		"l_wrist": Vector2(0, 44),
		"r_wrist": Vector2(2, 44)
	}
}


func _ready() -> void:
	position = Vector2(7.5, 10.5) * TILE  # porta da casa
	
	# Load textures
	var dirs: Array[String] = ["Front", "Back", "L View", "R View"]
	for d in dirs:
		var suffix: String = " - " + d + ".png"
		tex_body[d] = _load_texture(ASSET_DIR + "Body" + suffix)
		tex_head[d] = _load_texture(ASSET_DIR + "Head" + suffix)
		if d != "Back":
			tex_face[d] = _load_texture(ASSET_DIR + "Face 01" + suffix)
		tex_l_arm[d] = _load_texture(ASSET_DIR + "Left Arm" + suffix)
		tex_r_arm[d] = _load_texture(ASSET_DIR + "Right Arm" + suffix)
		tex_l_hand[d] = _load_texture(ASSET_DIR + "Left Hand" + suffix)
		tex_r_hand[d] = _load_texture(ASSET_DIR + "Right Hand" + suffix)
		tex_l_leg[d] = _load_texture(ASSET_DIR + "Left Leg" + suffix)
		tex_r_leg[d] = _load_texture(ASSET_DIR + "Right Leg" + suffix)


func _process(delta: float) -> void:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): v.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): v.x += 1
	if v != Vector2.ZERO:
		_walk += delta * 11.0
		v = v.normalized() * VEL * delta
		facing = Vector2i(v.sign())
		var np := position + Vector2(v.x, 0)
		if _anda(np):
			position = np
		np = position + Vector2(0, v.y)
		if _anda(np):
			position = np
	else:
		_walk = 0.0
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
	return (Vector2(c) * TILE + Vector2(HALF_TILE, HALF_TILE)).distance_to(position) < TILE * 2.5


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
	# 1. Desenha a sombra
	draw_circle(Vector2(0, 8), 10, Color(0, 0, 0, 0.3))
	
	# 2. Determina a direcao do sprite
	var dir := _get_dir_string()
	var offsets = joint_offsets[dir]
	
	# 3. Calcula valores da animacao
	var leg_rot := 0.0
	var arm_rot := 0.0
	var body_bob := 0.0
	var head_rot := 0.0
	var head_bob := 0.0
	
	var leg_l_y := 0.0
	var leg_r_y := 0.0
	
	if _walk > 0.0:
		if dir == "Front" or dir == "Back":
			# Pernas sobem/descem levemente (marchando), bracos mexem muito de leve (como na idle)
			leg_rot = 0.0
			arm_rot = sin(_walk * 0.5) * 0.05
			body_bob = -absf(sin(_walk)) * 3.0
			head_rot = 0.0
			head_bob = -absf(sin(_walk)) * 1.0
			leg_l_y = sin(_walk) * 4.0
			leg_r_y = -sin(_walk) * 4.0
		else:
			# Visoes laterais: andar tradicional com rotacao de pernas/bracos
			leg_rot = sin(_walk) * 0.4
			arm_rot = -sin(_walk) * 0.3
			body_bob = -absf(sin(_walk)) * 6.0
			head_rot = sin(_walk) * 0.05
			head_bob = -absf(sin(_walk)) * 2.0
	else:
		# Animacao ociosa de respirar (idle)
		var t := Time.get_ticks_msec() * 0.003
		body_bob = sin(t) * 1.5
		head_bob = sin(t) * 0.8
		arm_rot = sin(t) * 0.05
		leg_rot = 0.0
	
	var body_base_pos := Vector2(0, -3) + Vector2(0, body_bob) * SPRITE_SCALE
	var body_pos := body_base_pos
	var body_rot := 0.0
	
	# 4. Desenha as partes na ordem correta de camadas (z-index) por direcao
	if dir == "Front":
		# 1. Calcula as posicoes globais das articulacoes antes
		var l_arm_info = _get_part_transform(offsets["l_shoulder"], arm_rot, body_pos, body_rot)
		var r_arm_info = _get_part_transform(offsets["r_shoulder"], -arm_rot, body_pos, body_rot)
		var head_info = _get_part_transform(offsets["neck"] + Vector2(0, head_bob), head_rot, body_pos, body_rot)
		
		# 2. Desenha na ordem do Z-Index:
		# Z = 0: Perna Esquerda
		_draw_part(tex_l_leg[dir], offsets["l_hip"] + Vector2(0, leg_l_y), leg_rot, Vector2(40, 25), body_pos, body_rot)
		# Z = 1: Perna Direita
		_draw_part(tex_r_leg[dir], offsets["r_hip"] + Vector2(0, leg_r_y), -leg_rot, Vector2(40, 25), body_pos, body_rot)
		# Z = 2: Mao Esquerda
		_draw_part(tex_l_hand[dir], offsets["l_wrist"], arm_rot * 0.5, Vector2(40, 40), l_arm_info.pos, l_arm_info.rot)
		# Z = 2: Mao Direita
		_draw_part(tex_r_hand[dir], offsets["r_wrist"], -arm_rot * 0.5, Vector2(40, 40), r_arm_info.pos, r_arm_info.rot)
		# Z = 2: Corpo
		_draw_part(tex_body[dir], Vector2.ZERO, 0.0, Vector2(80, 80), body_pos, body_rot)
		# Z = 3: Braco Esquerdo
		_draw_part(tex_l_arm[dir], offsets["l_shoulder"], arm_rot, Vector2(40, 25), body_pos, body_rot)
		# Z = 3: Braco Direito
		_draw_part(tex_r_arm[dir], offsets["r_shoulder"], -arm_rot, Vector2(40, 25), body_pos, body_rot)
		# Z = 9: Cabeca
		_draw_part(tex_head[dir], offsets["neck"] + Vector2(0, head_bob), head_rot, Vector2(160, 240), body_pos, body_rot)
		# Z = 10: Rosto
		_draw_part(tex_face[dir], offsets["face"], 0.0, Vector2(80, 64), head_info.pos, head_info.rot)
		
	elif dir == "Back":
		# 1. Calcula as posicoes globais das articulacoes antes
		var l_arm_info = _get_part_transform(offsets["l_shoulder"], arm_rot, body_pos, body_rot)
		var r_arm_info = _get_part_transform(offsets["r_shoulder"], -arm_rot, body_pos, body_rot)
		
		# 2. Desenha na ordem do Z-Index:
		# Z = 0: Perna Esquerda
		_draw_part(tex_l_leg[dir], offsets["l_hip"] + Vector2(0, leg_l_y), leg_rot, Vector2(40, 25), body_pos, body_rot)
		# Z = 1: Perna Direita
		_draw_part(tex_r_leg[dir], offsets["r_hip"] + Vector2(0, leg_r_y), -leg_rot, Vector2(40, 25), body_pos, body_rot)
		# Z = 1: Mao Esquerda
		_draw_part(tex_l_hand[dir], offsets["l_wrist"], arm_rot * 0.5, Vector2(40, 40), l_arm_info.pos, l_arm_info.rot)
		# Z = 1: Mao Direita
		_draw_part(tex_r_hand[dir], offsets["r_wrist"], -arm_rot * 0.5, Vector2(40, 40), r_arm_info.pos, r_arm_info.rot)
		# Z = 2: Braco Esquerdo
		_draw_part(tex_l_arm[dir], offsets["l_shoulder"], arm_rot, Vector2(40, 25), body_pos, body_rot)
		# Z = 2: Braco Direito
		_draw_part(tex_r_arm[dir], offsets["r_shoulder"], -arm_rot, Vector2(40, 25), body_pos, body_rot)
		# Z = 3: Corpo
		_draw_part(tex_body[dir], Vector2.ZERO, 0.0, Vector2(80, 80), body_pos, body_rot)
		# Z = 9: Cabeca
		_draw_part(tex_head[dir], offsets["neck"] + Vector2(0, head_bob), head_rot, Vector2(160, 240), body_pos, body_rot)
		
	elif dir == "L View":
		# 1. Calcula as posicoes globais das articulacoes antes
		var l_arm_info = _get_part_transform(offsets["l_shoulder"], arm_rot, body_pos, body_rot)
		var r_arm_info = _get_part_transform(offsets["r_shoulder"], -arm_rot, body_pos, body_rot)
		var head_info = _get_part_transform(offsets["neck"] + Vector2(0, head_bob), head_rot, body_pos, body_rot)
		
		# 2. Desenha na ordem do Z-Index (L View: r_leg=0, r_hand=0, r_arm=1, l_leg=1, body=3, l_hand=4, l_arm=5, head=9, face=10):
		# Z = 0: Perna Direita
		_draw_part(tex_r_leg[dir], offsets["r_hip"] + Vector2(0, leg_r_y), -leg_rot, Vector2(40, 25), body_pos, body_rot)
		# Z = 0: Mao Direita
		_draw_part(tex_r_hand[dir], offsets["r_wrist"], -arm_rot * 0.5, Vector2(40, 40), r_arm_info.pos, r_arm_info.rot)
		# Z = 1: Perna Esquerda
		_draw_part(tex_l_leg[dir], offsets["l_hip"] + Vector2(0, leg_l_y), leg_rot, Vector2(40, 25), body_pos, body_rot)
		# Z = 1: Braco Direito
		_draw_part(tex_r_arm[dir], offsets["r_shoulder"], -arm_rot, Vector2(40, 25), body_pos, body_rot)
		# Z = 3: Corpo
		_draw_part(tex_body[dir], Vector2.ZERO, 0.0, Vector2(80, 80), body_pos, body_rot)
		# Z = 4: Mao Esquerda
		_draw_part(tex_l_hand[dir], offsets["l_wrist"], arm_rot * 0.5, Vector2(40, 40), l_arm_info.pos, l_arm_info.rot)
		# Z = 5: Braco Esquerdo
		_draw_part(tex_l_arm[dir], offsets["l_shoulder"], arm_rot, Vector2(40, 25), body_pos, body_rot)
		# Z = 9: Cabeca
		_draw_part(tex_head[dir], offsets["neck"] + Vector2(0, head_bob), head_rot, Vector2(160, 240), body_pos, body_rot)
		# Z = 10: Rosto
		_draw_part(tex_face[dir], offsets["face"], 0.0, Vector2(64, 64), head_info.pos, head_info.rot)
		
	elif dir == "R View":
		# 1. Calcula as posicoes globais das articulacoes antes
		var l_arm_info = _get_part_transform(offsets["l_shoulder"], arm_rot, body_pos, body_rot)
		var r_arm_info = _get_part_transform(offsets["r_shoulder"], -arm_rot, body_pos, body_rot)
		var head_info = _get_part_transform(offsets["neck"] + Vector2(0, head_bob), head_rot, body_pos, body_rot)
		
		# 2. Desenha na ordem do Z-Index (R View: l_leg=0, l_hand=0, l_arm=1, r_leg=1, body=3, r_hand=4, r_arm=5, head=9, face=10):
		# Z = 0: Perna Esquerda
		_draw_part(tex_l_leg[dir], offsets["l_hip"] + Vector2(0, leg_l_y), leg_rot, Vector2(40, 25), body_pos, body_rot)
		# Z = 0: Mao Esquerda
		_draw_part(tex_l_hand[dir], offsets["l_wrist"], arm_rot * 0.5, Vector2(40, 40), l_arm_info.pos, l_arm_info.rot)
		# Z = 1: Braco Esquerdo
		_draw_part(tex_l_arm[dir], offsets["l_shoulder"], arm_rot, Vector2(40, 25), body_pos, body_rot)
		# Z = 1: Perna Direita (Corrigido para Z=1, atras do corpo)
		_draw_part(tex_r_leg[dir], offsets["r_hip"] + Vector2(0, leg_r_y), -leg_rot, Vector2(40, 25), body_pos, body_rot)
		# Z = 3: Corpo
		_draw_part(tex_body[dir], Vector2.ZERO, 0.0, Vector2(80, 80), body_pos, body_rot)
		# Z = 4: Mao Direita
		_draw_part(tex_r_hand[dir], offsets["r_wrist"], -arm_rot * 0.5, Vector2(40, 40), r_arm_info.pos, r_arm_info.rot)
		# Z = 5: Braco Direito
		_draw_part(tex_r_arm[dir], offsets["r_shoulder"], -arm_rot, Vector2(40, 25), body_pos, body_rot)
		# Z = 9: Cabeca
		_draw_part(tex_head[dir], offsets["neck"] + Vector2(0, head_bob), head_rot, Vector2(160, 240), body_pos, body_rot)
		# Z = 10: Rosto
		_draw_part(tex_face[dir], offsets["face"], 0.0, Vector2(64, 64), head_info.pos, head_info.rot)
	
	# Realce da celula alvo de interacao (mantido do original)
	var alvo := _celula_alvo()
	if _perto(alvo) and Sim.ent_em(alvo) != null:
		draw_rect(Rect2(Vector2(alvo * TILE) - position, Vector2(TILE, TILE)), Color(1, 1, 1, 0.5), false, 2.0)


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	printerr("Failed to load texture at: ", path)
	return null


func _get_dir_string() -> String:
	if facing.y < 0:
		return "Back"
	elif facing.y > 0:
		return "Front"
	elif facing.x < 0:
		return "L View"
	elif facing.x > 0:
		return "R View"
	return "Front"


func _get_part_transform(pos: Vector2, rot: float, parent_pos: Vector2, parent_rot: float) -> Dictionary:
	return {
		"pos": parent_pos + (pos * SPRITE_SCALE).rotated(parent_rot),
		"rot": parent_rot + rot
	}


func _draw_part(tex: Texture2D, pos: Vector2, rot: float, pivot: Vector2, parent_pos := Vector2.ZERO, parent_rot := 0.0) -> Dictionary:
	var trans := _get_part_transform(pos, rot, parent_pos, parent_rot)
	if tex:
		draw_set_transform(trans.pos, trans.rot, Vector2(SPRITE_SCALE, SPRITE_SCALE))
		draw_texture(tex, -pivot)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return trans
