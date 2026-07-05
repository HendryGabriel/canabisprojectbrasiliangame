extends Node
# Nucleo deterministico da simulacao (GDD §9): passo fixo, so inteiros/strings/Vector2i.
# O Godot so renderiza por cima. Toda mutacao de estado entra por cmd_* — pronto para
# lockstep (no coop, cmd_* viram os inputs que trafegam pela rede).
# ponytail: netcode ausente no v1; a fundacao (comandos + determinismo) ja esta aqui.

signal msg(texto: String)
signal vitoria_sig
signal mato_limpo(cell: Vector2i)

const TICK_HZ := 10
const FRAMES_POR_TICK := 6  # 60 fps fisica / 10 ticks
const BELT_T := 3           # ticks por celula de esteira
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]  # N E S O

enum T { GRAMA, AGUA, ARVORE, AREIA, PISO, BECO, CIDADE, MATO, PEDRA }

var tick := 0
var money := 80
var heat := 0            # 0..100; 100 = batida policial
var heat_frac := 0
var tier := 0
var meta_atual := 0
var vendas := {}         # produto -> total vendido
var venceu := false

var _chunks := {}        # Vector2i -> PackedByteArray (cache do terreno procedural)
var _limpo := {}         # celulas de mato limpas pelo player (estado da sim, entra no hash)
var next_id := 1
var ents := {}           # id -> Dictionary
var grid := {}           # Vector2i -> id (toda celula coberta)
var redes := []          # redes de cano: [{"vol": int, "cap": int}]
var redes_sujas := true

var inv := {}            # inventario do jogador (compartilhado no coop v1)
var player_cell := Vector2i(7, 6)  # atualizado pelo player p/ bancada manual

var energia_uso := 0
var ger_propria := 0
var fator := 256         # velocidade das maquinas (1/256; 256 = 100%)
var luz_cortada := false
var conta_ultima := 0
var dev := false         # F2: libera tudo, sem custo/tier/lote (so p/ testar)

var _frame_acc := 0


func _ready() -> void:
	inv["semente:ruderalis"] = 3
	# pre-colocados: PC na casa, bancada na cozinha, traficante no beco (GDD §6)
	_criar("pc", Vector2i(5, 4), 2)
	_criar("bancada", Vector2i(9, 5), 2)
	_criar("traficante", Vector2i(1, 7), 1)


func _physics_process(_d: float) -> void:
	_frame_acc += 1
	if _frame_acc >= FRAMES_POR_TICK:
		_frame_acc = 0
		_step()


# ---------------- terreno procedural (estilo Minecraft: chunks por seed) ----------------
# O mundo e uma FUNCAO PURA de (x, y, SEED): qualquer maquina, em qualquer ordem de
# visita, gera o mesmo terreno — obrigatorio pro lockstep (GDD §9). Chunks sao so cache.
# Em cima (y<0) fica a cidade (limite do mapa); a zona da casa e feita a mao e garante
# agua/arvores/areia a poucos tiles de distancia.

const CHUNK := 16
const SEMENTE_MUNDO := 420133742  # troque para gerar outro mundo

const ZONA_CASA := Rect2i(0, 0, 42, 34)  # feita a mao (casa, beco, recursos iniciais)

func pegar_chunk(cc: Vector2i) -> PackedByteArray:
	var ch: PackedByteArray = _chunks.get(cc, PackedByteArray())
	if ch.is_empty():
		ch.resize(CHUNK * CHUNK)
		for dy in CHUNK:
			for dx in CHUNK:
				ch[dy * CHUNK + dx] = _gen_tile(cc.x * CHUNK + dx, cc.y * CHUNK + dy)
		_chunks[cc] = ch
	return ch


func terreno_em(c: Vector2i) -> int:
	if c.y < 0:
		return T.CIDADE
	var cc := Vector2i(_fdiv(c.x, CHUNK), _fdiv(c.y, CHUNK))
	var t: int = pegar_chunk(cc)[posmod(c.y, CHUNK) * CHUNK + posmod(c.x, CHUNK)]
	if (t == T.MATO or t == T.PEDRA) and _limpo.has(c):
		return T.GRAMA  # obstaculo ja removido pelo player
	return t


func dentro_do_mapa(c: Vector2i) -> bool:
	return c.y >= 0  # acima e a cidade; resto do mundo e infinito


func _gen_tile(x: int, y: int) -> int:
	if y < 0:
		return T.CIDADE
	if ZONA_CASA.has_point(Vector2i(x, y)):
		if x >= 4 and x < 11 and y >= 3 and y < 9:
			return T.PISO   # casa
		if x >= 0 and x < 2 and y >= 4 and y < 12:
			return T.BECO   # beco escuro
		# lago garantido (blob organico, com praia fina)
		if _d2(x, y, 32, 8) <= 7 or _d2(x, y, 34, 9) <= 5:
			return T.AGUA
		if _d2(x, y, 32, 8) <= 13 or _d2(x, y, 34, 9) <= 10:
			return T.AREIA
		if _d2(x, y, 33, 27) <= 14:
			return T.AREIA  # areial garantido
		if x >= 3 and x < 23 and y >= 23 and y < 33 and (x * 7 + y * 13) % 9 == 0:
			return T.ARVORE # bosque garantido (esparso)
		# mato e pedras leves no quintal, longe da casa/porta (nao atrapalha o tutorial)
		if x >= 16 or y >= 16:
			if _h(x, y, 21) % 100 < 6:
				return T.MATO
			if _h(x, y, 22) % 100 < 3:
				return T.PEDRA
		return T.GRAMA
	# lagos raros e espacados: UNIAO de circulos (1 possivel por supercelula de 32x32).
	# checar cada lago independente evita as "mordidas" quando dois lagos se encostam.
	var agua := false
	var praia := false
	var perto_da_agua := false
	var sx0 := _fdiv(x, 32)
	var sy0 := _fdiv(y, 32)
	for sy in range(sy0 - 1, sy0 + 2):
		for sx in range(sx0 - 1, sx0 + 2):
			if _h(sx, sy, 1) % 100 < 12:
				var cx := sx * 32 + 8 + _h(sx, sy, 2) % 16
				var cy := sy * 32 + 8 + _h(sx, sy, 3) % 16
				var d := (x - cx) * (x - cx) + (y - cy) * (y - cy)
				var r := 3 + _h(sx, sy, 4) % 4
				if d <= r * r:
					agua = true
				elif d <= (r + 1) * (r + 1):
					praia = true
				if d <= (r + 3) * (r + 3):
					perto_da_agua = true  # vegetacao nunca colada na agua
	if agua:
		return T.AGUA
	if praia:
		return T.AREIA
	# florestas em manchas (regiao 8x8 define mata fechada / esparsa / campo aberto)
	if not perto_da_agua:
		var f := _h(x >> 3, y >> 3, 5) % 100
		var dens := 20 if f < 15 else (3 if f < 45 else 0)
		if dens > 0 and _h(x, y, 6) % 100 < dens:
			return T.ARVORE
		# mato alto em manchas — o player limpa com E pra liberar o terreno
		var m := _h(x >> 3, y >> 3, 20) % 100
		if _h(x, y, 21) % 100 < (22 if m < 30 else 4):
			return T.MATO
	# pedras esparsas — obstaculo que o player tira com E
	if _h(x, y, 22) % 100 < 2:
		return T.PEDRA
	return T.GRAMA


static func _d2(x: int, y: int, cx: int, cy: int) -> int:
	return (x - cx) * (x - cx) + (y - cy) * (y - cy)


static func _h(x: int, y: int, sal: int) -> int:
	# hash inteiro deterministico (mesmo resultado em toda maquina — lockstep)
	var n := x * 374761393 + y * 668265263 + sal * 974634541 + SEMENTE_MUNDO
	n = (n ^ (n >> 13)) * 1274126177
	return (n ^ (n >> 16)) & 0x7fffffff


static func _fdiv(a: int, b: int) -> int:
	@warning_ignore("integer_division")
	var q := a / b
	if (a % b != 0) and ((a < 0) != (b < 0)):
		q -= 1
	return q


# ---------------- entidades ----------------

func _criar(t: String, pos: Vector2i, dir: int) -> int:
	var e := {"id": next_id, "t": t, "pos": pos, "dir": dir}
	match t:
		"esteira":
			e["item"] = ""
			e["prog"] = 0
		"canteiro":
			e["cepa"] = ""
			e["fase"] = 0   # 0 vazio, 1 plantado(seco), 2 regado, 3 pronto
			e["tempo"] = 0
			e["plant_tick"] = 0
		"bancada":
			e["cepa"] = ""
			e["prog"] = 0
		"gerador":
			e["fuel"] = 0
		_:
			if Defs.RECEITAS.has(t):
				e["ins"] = {}
				e["cepa"] = ""
				e["blend"] = []
				e["prog"] = 0
				e["out_item"] = ""
				e["out_n"] = 0
			elif Defs.ESTUFAS.has(t):
				e["sementes"] = []
				e["cepa_ciclo"] = ""
				e["prog"] = 0
				e["out_item"] = ""
				e["out_n"] = 0
	ents[next_id] = e
	var tam: Vector2i = Defs.PREDIOS[t]["tam"] if Defs.PREDIOS.has(t) else Vector2i(1, 1)
	for dx in tam.x:
		for dy in tam.y:
			grid[pos + Vector2i(dx, dy)] = next_id
	next_id += 1
	redes_sujas = true
	return next_id - 1


func ent_em(c: Vector2i):
	var id = grid.get(c, 0)
	return ents.get(id)


# ---------------- tick ----------------

func _step() -> void:
	tick += 1
	if redes_sujas:
		_rebuild_redes()
	var ids := ents.keys()
	ids.sort()  # ordem deterministica (GDD §9)
	energia_uso = 0
	ger_propria = 0
	for id in ids:
		var e: Dictionary = ents[id]
		match e["t"]:
			"poco":
				_tick_poco(e)
			"canteiro":
				_tick_canteiro(e)
			"bancada":
				_tick_bancada(e)
			"gerador":
				_tick_gerador(e)
			"solar":
				ger_propria += 6
			_:
				if Defs.RECEITAS.has(e["t"]):
					_tick_maquina(e)
				elif Defs.ESTUFAS.has(e["t"]):
					_tick_estufa(e)
	_tick_esteiras(ids)
	_tick_energia()
	_tick_heat()


func _tick_energia() -> void:
	var avail := ger_propria + (0 if luz_cortada else 100000)  # cidade = infinita, mas paga
	fator = 256 if energia_uso <= avail else maxi(32, floori(float(avail * 256) / float(maxi(1, energia_uso))))
	if tick % 100 == 0:
		var conta := maxi(0, energia_uso - ger_propria)
		conta_ultima = conta
		if money >= conta:
			money -= conta
			if luz_cortada:
				luz_cortada = false
				msg.emit("Luz religada.")
		elif conta > 0:
			luz_cortada = true
			msg.emit("Sem dinheiro pra conta de luz — LUZ CORTADA!")


func _tick_heat() -> void:
	if tick % 10 == 0:
		heat = maxi(0, heat - 1)
	if heat >= 100:
		money = floori(float(money * 7) / 10.0)
		heat = 35
		msg.emit("BATIDA POLICIAL! Multa de 30% do seu dinheiro.")


func _n_filtros() -> int:
	var n := 0
	for id in ents:
		if ents[id]["t"] == "filtro":
			n += 1
	return n


# ---------------- venda ----------------

func _vender(item: String) -> bool:
	var p: int = Defs.item_preco(item)
	if p <= 0:
		return false
	money += p
	var prod: String = Defs.item_prod(item)
	vendas[prod] = vendas.get(prod, 0) + 1
	# calor por venda, reduzido por filtros de carvao (GDD §8)
	heat_frac += maxi(20, 100 - _n_filtros() * 15)
	heat = mini(100, heat + floori(float(heat_frac) / 100.0))
	heat_frac %= 100
	_checa_meta()
	return true


func _checa_meta() -> void:
	if meta_atual >= Defs.METAS.size():
		return
	var m: Dictionary = Defs.METAS[meta_atual]
	if meta_progresso() >= m["qtd"]:
		tier = m["tier"]
		meta_atual += 1
		msg.emit("META CUMPRIDA! Tier %d desbloqueado." % tier)
		if tier >= 5 and not venceu:
			venceu = true
			vitoria_sig.emit()


func meta_progresso() -> int:
	if meta_atual >= Defs.METAS.size():
		return 0
	var soma := 0
	for it in Defs.METAS[meta_atual]["itens"]:
		soma += vendas.get(it, 0)
	return soma


# ---------------- cultivo ----------------

func _tick_canteiro(e: Dictionary) -> void:
	if e["fase"] == 2:
		e["tempo"] += 1
		if e["tempo"] >= Defs.STRAINS[e["cepa"]]["grow"]:
			e["fase"] = 3


func _tick_estufa(e: Dictionary) -> void:
	var d: Dictionary = Defs.ESTUFAS[e["t"]]
	if e["prog"] == 0:
		if e["sementes"].size() > 0 and e["out_n"] < 6 and _consome_agua(e, d["agua"]):
			e["cepa_ciclo"] = e["sementes"].pop_front()
			e["prog"] = 1
	else:
		energia_uso += Defs.PREDIOS[e["t"]]["energia"]
		e["prog"] += fator
		if e["prog"] >= d["t"] * 256:
			e["out_item"] = "bud:" + e["cepa_ciclo"]
			e["out_n"] += d["buds"]
			e["prog"] = 0
	_empurra_saida(e)


# ---------------- maquinas ----------------

func _tick_bancada(e: Dictionary) -> void:
	# manual: so progride com o jogador ao lado segurando E (via cmd_bancada)
	pass


func _tick_gerador(e: Dictionary) -> void:
	if e["fuel"] > 0:
		e["fuel"] -= 1
		ger_propria += 30


func _tick_maquina(e: Dictionary) -> void:
	var r: Dictionary = Defs.RECEITAS[e["t"]]
	if r.get("manual", false):
		return
	if e["prog"] == 0:
		if e["out_n"] < 6 and _receita_pronta(e, r) and _consome_agua(e, r.get("agua", 0)):
			_consome_ins(e, r)
			e["prog"] = 1
	else:
		energia_uso += Defs.PREDIOS[e["t"]]["energia"]
		e["prog"] += fator
		if e["prog"] >= r["t"] * 256:
			_produz(e, r)
			e["prog"] = 0
	_empurra_saida(e)


func _receita_pronta(e: Dictionary, r: Dictionary) -> bool:
	for k in r["in"]:
		if k == "bud2cat":
			if e["blend"].size() < 2:
				return false
		elif e["ins"].get(k, 0) < r["in"][k]:
			return false
	return true


func _consome_ins(e: Dictionary, r: Dictionary) -> void:
	for k in r["in"]:
		if k == "bud2cat":
			continue  # blend consumido em _produz (precisa das cepas)
		e["ins"][k] = e["ins"].get(k, 0) - r["in"][k]


func _produz(e: Dictionary, r: Dictionary) -> void:
	var out: String = r["out"]
	if out == "blend":
		var cat: int = Defs.STRAINS[e["blend"][0]]["cat"]
		var nome := {Defs.Cat.SATIVA: "blend_sativa", Defs.Cat.INDICA: "blend_indica", Defs.Cat.HYBRID: "blend_hibrida"}
		e["out_item"] = nome[cat]
		e["blend"] = []
	elif Defs.PROD_MULT.has(out):
		e["out_item"] = "%s:%s" % [out, e["cepa"]]
	else:
		e["out_item"] = out
	e["out_n"] += r["n"]
	# libera a cepa quando os buffers com cepa zeram (permite trocar a linha)
	var vazio := true
	for k in e["ins"]:
		if e["ins"][k] > 0 and (k == "bud" or k == "pura"):
			vazio = false
	if vazio:
		e["cepa"] = ""


func _empurra_saida(e: Dictionary) -> void:
	if e.get("out_n", 0) <= 0:
		return
	var alvo := _celula_frente(e)
	var a = ent_em(alvo)
	if a == null:
		return
	if a["t"] == "esteira" and a["item"] == "":
		a["item"] = e["out_item"]
		a["prog"] = 0
		e["out_n"] -= 1
	elif a["t"] == "traficante":
		if _vender(e["out_item"]):
			e["out_n"] -= 1


func _celula_frente(e: Dictionary) -> Vector2i:
	var tam: Vector2i = Defs.PREDIOS[e["t"]]["tam"] if Defs.PREDIOS.has(e["t"]) else Vector2i(1, 1)
	var p: Vector2i = e["pos"]
	var center_x: int = floori(float(tam.x - 1) / 2.0)
	var center_y: int = floori(float(tam.y - 1) / 2.0)
	match e["dir"]:
		0: return Vector2i(p.x + center_x, p.y - 1)
		1: return Vector2i(p.x + tam.x, p.y + center_y)
		2: return Vector2i(p.x + center_x, p.y + tam.y)
		_: return Vector2i(p.x - 1, p.y + center_y)


# ---------------- esteiras ----------------

func _tick_esteiras(ids: Array) -> void:
	var belts: Array = []
	for id in ids:
		if ents[id]["t"] == "esteira":
			belts.append(ents[id])
	for b in belts:
		if b["item"] != "" and b["prog"] < BELT_T:
			b["prog"] += 1
	# ponytail: relaxacao ate estabilizar; O(n^2) no pior caso, ok nesta escala
	var moveu := true
	var passes := 0
	while moveu and passes < 64:
		moveu = false
		passes += 1
		for b in belts:
			if b["item"] == "" or b["prog"] < BELT_T:
				continue
			if _transfere(b):
				moveu = true


func _transfere(b: Dictionary) -> bool:
	var alvo: Vector2i = b["pos"] + DIRS[b["dir"]]
	var a = ent_em(alvo)
	if a == null:
		return false
	match a["t"]:
		"esteira":
			if a["item"] == "":
				a["item"] = b["item"]
				a["prog"] = 0
				b["item"] = ""
				return true
		"traficante":
			if _vender(b["item"]):
				b["item"] = ""
				return true
		"gerador":
			return _abastece_gerador(a, b)
		_:
			if Defs.ESTUFAS.has(a["t"]):
				if Defs.item_prod(b["item"]) == "semente" and a["sementes"].size() < 3:
					a["sementes"].append(Defs.item_cepa(b["item"]))
					b["item"] = ""
					return true
			elif Defs.RECEITAS.has(a["t"]):
				if _aceita_input(a, b["item"]):
					b["item"] = ""
					return true
	return false


func _abastece_gerador(g: Dictionary, b: Dictionary) -> bool:
	var prod := Defs.item_prod(b["item"])
	if g["fuel"] < 300 and (prod == "madeira" or prod == "bud"):
		g["fuel"] += 100 if prod == "madeira" else 60
		b["item"] = ""
		return true
	return false


func _aceita_input(m: Dictionary, item: String) -> bool:
	var r: Dictionary = Defs.RECEITAS[m["t"]]
	if r.get("manual", false):
		return false
	var prod := Defs.item_prod(item)
	var cepa := Defs.item_cepa(item)
	if r["in"].has("bud2cat"):
		if prod != "bud" or cepa == "":
			return false
		var cat: int = Defs.STRAINS[cepa]["cat"]
		if cat == Defs.Cat.RUDERALIS:
			return false  # ruderalis nao entra em blend (GDD §5)
		if m["blend"].has(cepa) or m["blend"].size() >= 2:
			return false
		if m["blend"].size() == 1 and Defs.STRAINS[m["blend"][0]]["cat"] != cat:
			return false
		m["blend"].append(cepa)
		return true
	if (prod == "bud" or prod == "pura") and r["in"].has(prod):
		if m["cepa"] != "" and m["cepa"] != cepa:
			return false  # linha travada na cepa (GDD §3)
		if m["ins"].get(prod, 0) >= r["in"][prod] * 2:
			return false
		m["cepa"] = cepa
		m["ins"][prod] = m["ins"].get(prod, 0) + 1
		return true
	if r["in"].has(item):  # generico exato (vidro, seda, gelo, madeira, areia)
		if m["ins"].get(item, 0) >= r["in"][item] * 2:
			return false
		m["ins"][item] = m["ins"].get(item, 0) + 1
		return true
	return false


# ---------------- agua / canos ----------------

func _tick_poco(e: Dictionary) -> void:
	energia_uso += 4
	var n: int = e.get("net", -1)
	if n >= 0 and n < redes.size():
		redes[n]["vol"] = mini(redes[n]["cap"], redes[n]["vol"] + 3)


func _rebuild_redes() -> void:
	# ponytail: reconstruir zera o volume; aceitavel, agua reenche rapido
	redes_sujas = false
	redes = []
	var visto := {}
	var ids := ents.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = ents[id]
		if (e["t"] != "cano" and e["t"] != "poco") or visto.has(id):
			continue
		var fila: Array = [id]
		var nos := 0
		var ni := redes.size()
		while fila.size() > 0:
			var cur: int = fila.pop_back()
			if visto.has(cur):
				continue
			visto[cur] = true
			ents[cur]["net"] = ni
			nos += 1
			for d in DIRS:
				var viz = ent_em(ents[cur]["pos"] + d)
				if viz != null and (viz["t"] == "cano" or viz["t"] == "poco") and not visto.has(viz["id"]):
					fila.append(viz["id"])
		redes.append({"vol": 0, "cap": nos * 40})


func _rede_adjacente(e: Dictionary) -> int:
	var tam: Vector2i = Defs.PREDIOS[e["t"]]["tam"] if Defs.PREDIOS.has(e["t"]) else Vector2i(1, 1)
	for dx in tam.x:
		for dy in tam.y:
			for d in DIRS:
				var viz = ent_em(e["pos"] + Vector2i(dx, dy) + d)
				if viz != null and (viz["t"] == "cano" or viz["t"] == "poco"):
					return viz.get("net", -1)
	return -1


func _consome_agua(e: Dictionary, qtd: int) -> bool:
	if qtd <= 0:
		return true
	var n := _rede_adjacente(e)
	if n < 0 or n >= redes.size() or redes[n]["vol"] < qtd:
		return false
	redes[n]["vol"] -= qtd
	return true


# ---------------- inventario ----------------

func inv_add(item: String, n: int) -> void:
	inv[item] = inv.get(item, 0) + n


func inv_take(item: String, n: int) -> bool:
	if inv.get(item, 0) < n:
		return false
	inv[item] -= n
	if inv[item] == 0:
		inv.erase(item)
	return true


# ---------------- comandos (inputs deterministicos — futuros pacotes de rede) ----------------

func motivo_nao_construir(t: String, pos: Vector2i) -> String:
	# "" = pode construir. Uma fonte so de verdade p/ cmd_place e p/ a UI explicar o erro.
	if not Defs.PREDIOS.has(t):
		return "Prédio inválido"
	var d: Dictionary = Defs.PREDIOS[t]
	if not dev and tier < d["tier"]:
		return "Precisa do Tier %d (cumpra a meta)" % d["tier"]
	if not dev and money < d["custo"]:
		return "Sem dinheiro (custa $%d)" % d["custo"]
	var tam: Vector2i = d["tam"]
	for dx in tam.x:
		for dy in tam.y:
			var c: Vector2i = pos + Vector2i(dx, dy)
			if not dentro_do_mapa(c):
				return "Aí é a cidade — construa pro outro lado"
			if grid.has(c):
				return "Espaço ocupado"
			var ter := terreno_em(c)
			match t:
				"extrator_madeira":
					if ter != T.ARVORE:
						return "Coloque em cima de uma árvore"
				"extrator_areia":
					if ter != T.AREIA:
						return "Coloque em cima da areia"
				"canteiro":
					if ter == T.MATO or ter == T.PEDRA:
						return "Limpe o terreno primeiro (E no obstáculo)"
					if ter != T.GRAMA:
						return "Canteiro só na grama"
				_:
					if ter == T.MATO or ter == T.PEDRA:
						return "Limpe o terreno primeiro (E no obstáculo)"
					if ter == T.AGUA or ter == T.ARVORE or ter == T.CIDADE:
						return "Terreno inválido"
	if t == "poco":
		var tem_agua := false
		for dv in DIRS:
			if terreno_em(pos + dv) == T.AGUA:
				tem_agua = true
		if not tem_agua:
			return "Poço precisa de água ao lado"
	return ""


func cmd_place(t: String, pos: Vector2i, dir: int) -> bool:
	if motivo_nao_construir(t, pos) != "":
		return false
	if not dev:
		money -= Defs.PREDIOS[t]["custo"]
	_criar(t, pos, dir)
	return true


func cmd_dev_toggle() -> void:
	dev = not dev
	if dev:
		for cepa in Defs.STRAINS:  # libera semente de todas as cepas
			inv["semente:" + cepa] = inv.get("semente:" + cepa, 0) + 50
		msg.emit("MODO DEV LIGADO — tudo liberado, sem custo (F2 desliga)")
	else:
		msg.emit("Modo dev desligado.")


func cmd_rotate(pos: Vector2i, dir: int) -> void:
	var e = ent_em(pos)
	if e != null and e.has("dir") and dir >= 0 and dir < 4 and e["t"] != "pc" and e["t"] != "traficante":
		e["dir"] = dir


func cmd_remove(pos: Vector2i) -> bool:
	var e = ent_em(pos)
	if e == null or e["t"] == "pc" or e["t"] == "traficante":
		return false
	var custo: int = Defs.PREDIOS[e["t"]]["custo"] if Defs.PREDIOS.has(e["t"]) else 0
	money += floori(float(custo) / 2.0)
	var tam: Vector2i = Defs.PREDIOS[e["t"]]["tam"] if Defs.PREDIOS.has(e["t"]) else Vector2i(1, 1)
	for dx in tam.x:
		for dy in tam.y:
			grid.erase(e["pos"] + Vector2i(dx, dy))
	ents.erase(e["id"])
	redes_sujas = true
	return true


func cmd_interact(pos: Vector2i) -> void:
	var e = ent_em(pos)
	if e == null:
		var ter := terreno_em(pos)
		if ter == T.MATO or ter == T.PEDRA:
			_limpo[pos] = true  # remove o obstaculo, libera o terreno
			mato_limpo.emit(pos)
		return
	match e["t"]:
		"traficante":
			_vende_inventario()
		"esteira":
			if e["item"] != "":
				inv_add(e["item"], 1)
				e["item"] = ""
		"canteiro":
			_interage_canteiro(e)
		"gerador":
			_insere_do_inv(e)
		_:
			if Defs.RECEITAS.has(e["t"]) or Defs.ESTUFAS.has(e["t"]):
				_coleta_ou_insere(e)


func _vende_inventario() -> void:
	var total := 0
	for item in inv.keys().duplicate():
		if Defs.item_prod(item) == "semente":
			continue  # nao vender sementes sem querer
		var p: int = Defs.item_preco(item)
		if p > 0:
			var n: int = inv[item]
			for i in n:
				_vender(item)
			inv.erase(item)
			total += p * n
	if total > 0:
		msg.emit("Vendeu tudo por $%d" % total)


func _interage_canteiro(e: Dictionary) -> void:
	match e["fase"]:
		0:
			var chaves := inv.keys()
			chaves.sort()
			for item in chaves:
				if Defs.item_prod(item) == "semente" and inv_take(item, 1):
					e["cepa"] = Defs.item_cepa(item)
					e["fase"] = 1
					return
			msg.emit("Sem sementes! Compre no PC.")
		1:
			e["fase"] = 2  # regar e gratis no manual (GDD §5)
			e["tempo"] = 0
			e["plant_tick"] = tick
		3:
			var n: int = 2 + (e["pos"].x + e["pos"].y + e["plant_tick"]) % 2
			inv_add("bud:" + e["cepa"], n)
			e["fase"] = 0
			e["cepa"] = ""


func _coleta_ou_insere(e: Dictionary) -> void:
	if e.get("out_n", 0) > 0:
		inv_add(e["out_item"], e["out_n"])
		e["out_n"] = 0
		return
	_insere_do_inv(e)


func _insere_do_inv(e: Dictionary) -> void:
	var chaves := inv.keys()
	chaves.sort()
	for item in chaves:
		var ok := false
		if e["t"] == "gerador":
			var fake := {"item": item}
			ok = _abastece_gerador(e, fake)
			if ok:
				inv_take(item, 1)
				return
		elif Defs.ESTUFAS.has(e["t"]):
			if Defs.item_prod(item) == "semente" and e["sementes"].size() < 3:
				e["sementes"].append(Defs.item_cepa(item))
				inv_take(item, 1)
				return
		elif _aceita_input(e, item):
			inv_take(item, 1)
			return


func cmd_bancada(pos: Vector2i) -> void:
	# segurar E perto da bancada (manual, GDD §10)
	var e = ent_em(pos)
	if e == null or e["t"] != "bancada":
		return
	if e["prog"] == 0:
		var chaves := inv.keys()
		chaves.sort()
		for item in chaves:
			if Defs.item_prod(item) == "bud" and inv.get(item, 0) >= 2:
				inv_take(item, 2)
				e["cepa"] = Defs.item_cepa(item)
				e["prog"] = 1
				return
	else:
		e["prog"] += 256
		if e["prog"] >= Defs.RECEITAS["bancada"]["t"] * 256:
			inv_add("prensado:" + e["cepa"], 1)
			e["prog"] = 0
			e["cepa"] = ""


func cmd_buy_seed(cepa: String) -> bool:
	if not Defs.STRAINS.has(cepa):
		return false
	var s: Dictionary = Defs.STRAINS[cepa]
	if not dev and (tier < s["tier"] or money < s["semente"]):
		return false
	if not dev:
		money -= s["semente"]
	inv_add("semente:" + cepa, 1)
	return true


func cmd_advogado() -> bool:
	if money < 500 or heat < 10:
		return false
	money -= 500
	heat = maxi(0, heat - 30)
	msg.emit("O advogado deu um jeito. Calor -30.")
	return true


# ---------------- lockstep ----------------

func state_hash() -> int:
	# mesmo input -> mesmo hash em toda maquina, todo tick (GDD §9)
	var chaves := ents.keys()
	chaves.sort()
	var limpos := _limpo.keys()
	limpos.sort()
	var s := "%d|%d|%d|%d|%s|%s" % [tick, money, heat, tier, str(inv), str(limpos)]
	for id in chaves:
		s += str(ents[id])
	return hash(s)
