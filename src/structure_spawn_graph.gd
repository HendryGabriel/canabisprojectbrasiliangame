## Declarative, deterministic structure-spawn graph compiler and evaluator.
class_name StructureSpawnGraph
extends RefCounted


const LOGIC_TYPES: Array[String] = ["and", "or", "not"]
const CONDITION_TYPES: Array[String] = [
	"biome", "zone", "surface", "cave_floor", "underground", "buried",
	"height", "depth", "slope", "sky_visible", "distance_edge",
	"volume_air", "support_block", "distance_spawn",
]
const RELAXABLE_TYPES: Array[String] = ["height", "depth", "slope", "distance_edge", "volume_air", "support_block", "distance_spawn"]
const SETTING_TYPES: Array[String] = [
	"candidate_grid", "chance", "minimum_count", "maximum_count", "exact_count",
	"priority", "minimum_distance", "transform", "generate",
]


static func node_definitions() -> Dictionary:
	return {
		"candidate_grid": {"name": "Candidatos em grade", "category": "Entrada", "description": "Cria pontos candidatos em uma grade regular dentro do bioma.", "defaults": {"spacing": 24}},
		"biome": {"name": "Bioma", "category": "Condição", "description": "Restringe o perfil ao bioma 100x100 indicado. Esta condição é sempre rígida.", "defaults": {"coord": [0, 0]}},
		"zone": {"name": "Zona", "category": "Condição", "description": "Exige que a célula pertença à máscara de zonas informada.", "defaults": {"mask": 1}},
		"surface": {"name": "Superfície", "category": "Ambiente", "description": "Alinha o pivot e as fundações à superfície do terreno.", "defaults": {}},
		"cave_floor": {"name": "Piso de caverna", "category": "Ambiente", "description": "Procura um piso sólido com espaço livre acima dentro de uma caverna.", "defaults": {}},
		"underground": {"name": "Subterrâneo", "category": "Ambiente", "description": "Posiciona a estrutura a uma profundidade determinística sob a superfície.", "defaults": {"min_depth": 12, "max_depth": 42}},
		"buried": {"name": "Completamente soterrada", "category": "Ambiente", "description": "Posiciona a estrutura dentro de terreno sólido; apenas ar explícito escava o interior.", "defaults": {"min_depth": 12, "max_depth": 42, "minimum_cover": 4}},
		"height": {"name": "Altura Y", "category": "Condição", "description": "Aceita somente anchors dentro do intervalo vertical configurado.", "defaults": {"min": -64, "max": 126}},
		"depth": {"name": "Profundidade", "category": "Condição", "description": "Limita a distância entre a superfície e o anchor da estrutura.", "defaults": {"min": 0, "max": 96}},
		"slope": {"name": "Inclinação", "category": "Condição", "description": "Limita a diferença de altura sob o volume horizontal da estrutura.", "defaults": {"max": 8}},
		"sky_visible": {"name": "Céu visível", "category": "Condição", "description": "Exige que não existam blocos entre o anchor e o topo do mundo.", "defaults": {"required": true}},
		"distance_edge": {"name": "Distância da borda", "category": "Condição", "description": "Mantém o pivot afastado das bordas do bioma.", "defaults": {"min": 0}},
		"volume_air": {"name": "Ar no volume", "category": "Volume 3D", "description": "Exige uma proporção mínima e máxima de ar dentro do AABB transformado.", "defaults": {"min_ratio": 0.0, "max_ratio": 1.0}},
		"support_block": {"name": "Bloco de apoio", "category": "Volume 3D", "description": "Exige um dos blocos permitidos abaixo de todos os pontos de fundação.", "defaults": {"blocks": ["stone", "dirt", "grass"]}},
		"distance_spawn": {"name": "Distância do spawn", "category": "Relação", "description": "Mantém a estrutura afastada do ponto de spawn do bioma.", "defaults": {"min": 0, "spawn": [50, 50]}},
		"and": {"name": "E", "category": "Lógica", "description": "Aprova somente quando todas as condições conectadas forem verdadeiras.", "defaults": {}},
		"or": {"name": "OU", "category": "Lógica", "description": "Aprova quando ao menos uma condição conectada for verdadeira.", "defaults": {}},
		"not": {"name": "NÃO", "category": "Lógica", "description": "Inverte o resultado da única condição conectada.", "defaults": {}},
		"chance": {"name": "Chance", "category": "Distribuição", "description": "Aplica uma chance determinística a cada candidato válido.", "defaults": {"value": 0.1}},
		"minimum_count": {"name": "Mínimo por bioma", "category": "Distribuição", "description": "Tenta gerar pelo menos X instâncias no bioma.", "defaults": {"value": 0}},
		"maximum_count": {"name": "Máximo por bioma", "category": "Distribuição", "description": "Nunca permite mais que X instâncias deste perfil no bioma.", "defaults": {"value": 1}},
		"exact_count": {"name": "Quantidade exata", "category": "Distribuição", "description": "Tenta atingir exatamente X instâncias, relaxando apenas condições flexíveis.", "defaults": {"value": 1}},
		"priority": {"name": "Prioridade", "category": "Distribuição", "description": "Perfis com maior prioridade reservam espaço primeiro.", "defaults": {"value": 0}},
		"minimum_distance": {"name": "Distância entre estruturas", "category": "Distribuição", "description": "Mantém pivots deste perfil separados pela distância mínima.", "defaults": {"value": 0}},
		"transform": {"name": "Transformar", "category": "Transformação", "description": "Escolhe rotação e espelhamento de forma determinística.", "defaults": {"rotations": [0], "mirror_x_chance": 0.0, "mirror_z_chance": 0.0}},
		"generate": {"name": "Gerar estrutura", "category": "Saída", "description": "Reserva o AABB e aplica somente blocos e ar explícito do asset.", "defaults": {}},
	}


static func default_profile(biome_coord: Vector2i = Vector2i.ZERO) -> Dictionary:
	return {
		"version": 1,
		"id": "perfil_principal",
		"name": "Perfil principal",
		"nodes": [
			_node("candidatos", "candidate_grid", Vector2(40, 220), {"spacing": 24}),
			_node("bioma", "biome", Vector2(270, 120), {"coord": [biome_coord.x, biome_coord.y]}),
			_node("superficie", "surface", Vector2(270, 300), {}),
			_node("chance", "chance", Vector2(500, 170), {"value": 0.1}),
			_node("maximo", "maximum_count", Vector2(500, 340), {"value": 1}),
			_node("transformar", "transform", Vector2(730, 220), {"rotations": [0], "mirror_x_chance": 0.0, "mirror_z_chance": 0.0}),
			_node("gerar", "generate", Vector2(970, 220), {}),
		],
		"connections": [
			{"from": "candidatos", "to": "bioma"},
			{"from": "candidatos", "to": "superficie"},
			{"from": "bioma", "to": "chance"},
			{"from": "superficie", "to": "chance"},
			{"from": "chance", "to": "maximo"},
			{"from": "maximo", "to": "transformar"},
			{"from": "transformar", "to": "gerar"},
		],
	}


static func validate_profile(profile: Dictionary) -> Array[String]:
	return compile(profile).get("errors", []) as Array[String]


static func compile(profile: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var definitions: Dictionary = node_definitions()
	var nodes: Dictionary = {}
	for raw_node in profile.get("nodes", []) as Array:
		if typeof(raw_node) != TYPE_DICTIONARY:
			errors.append("No invalido no perfil %s." % str(profile.get("id", "")))
			continue
		var node: Dictionary = (raw_node as Dictionary).duplicate(true)
		var node_id: String = str(node.get("id", "")).strip_edges()
		var node_type: String = str(node.get("type", ""))
		if node_id == "" or nodes.has(node_id):
			errors.append("IDs de no devem ser unicos e nao vazios.")
			continue
		if not definitions.has(node_type):
			errors.append("No %s possui tipo desconhecido: %s." % [node_id, node_type])
			continue
		node["params"] = _merged_params(node_type, node.get("params", {}) as Dictionary, definitions)
		nodes[node_id] = node
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}
	for node_id in nodes.keys():
		incoming[node_id] = []
		outgoing[node_id] = []
	for raw_connection in profile.get("connections", []) as Array:
		if typeof(raw_connection) != TYPE_DICTIONARY:
			errors.append("Conexao invalida.")
			continue
		var connection: Dictionary = raw_connection as Dictionary
		var from_id: String = str(connection.get("from", ""))
		var to_id: String = str(connection.get("to", ""))
		if not nodes.has(from_id) or not nodes.has(to_id) or from_id == to_id:
			errors.append("Conexao referencia no ausente ou o proprio no.")
			continue
		if not (outgoing[from_id] as Array).has(to_id):
			(outgoing[from_id] as Array).append(to_id)
			(incoming[to_id] as Array).append(from_id)
	if _has_cycle(nodes.keys(), outgoing):
		errors.append("O grafo possui ciclo.")
	var generate_ids: Array[String] = []
	var biome_ids: Array[String] = []
	var candidate_ids: Array[String] = []
	for node_id in nodes.keys():
		match str((nodes[node_id] as Dictionary).get("type", "")):
			"generate": generate_ids.append(str(node_id))
			"biome": biome_ids.append(str(node_id))
			"candidate_grid": candidate_ids.append(str(node_id))
	if generate_ids.size() != 1:
		errors.append("Cada perfil deve possuir exatamente uma saida Gerar estrutura.")
	if biome_ids.size() != 1:
		errors.append("Cada perfil deve possuir exatamente um no Bioma rigido.")
	if candidate_ids.size() != 1:
		errors.append("Cada perfil deve possuir exatamente uma entrada de candidatos.")
	if not generate_ids.is_empty() and (incoming[generate_ids[0]] as Array).is_empty():
		errors.append("A saida Gerar estrutura precisa estar conectada.")
	for node_id in nodes.keys():
		var node: Dictionary = nodes[node_id] as Dictionary
		var node_type: String = str(node.get("type", ""))
		if node_type == "not" and (incoming[node_id] as Array).size() != 1:
			errors.append("O no NAO precisa de exatamente uma entrada.")
		elif node_type in ["and", "or"] and (incoming[node_id] as Array).size() < 2:
			errors.append("O no %s precisa de ao menos duas entradas." % node_id)
		_validate_params(node, errors)
	var reachable: Dictionary = {}
	if not generate_ids.is_empty():
		_collect_ancestors(generate_ids[0], incoming, reachable)
	for required_id in biome_ids + candidate_ids:
		if not reachable.has(required_id):
			errors.append("No obrigatorio %s nao alcanca a saida." % required_id)
	var condition_roots: Array[String] = []
	var consumed_by_logic: Dictionary = {}
	for node_id in reachable.keys():
		var node_type: String = str((nodes[node_id] as Dictionary).get("type", ""))
		if node_type in LOGIC_TYPES:
			for child_id in incoming[node_id] as Array:
				if str((nodes.get(child_id, {}) as Dictionary).get("type", "")) in CONDITION_TYPES + LOGIC_TYPES:
					consumed_by_logic[child_id] = true
	for node_id in reachable.keys():
		var node_type: String = str((nodes[node_id] as Dictionary).get("type", ""))
		if node_type in CONDITION_TYPES + LOGIC_TYPES and not consumed_by_logic.has(node_id):
			condition_roots.append(str(node_id))
	condition_roots.sort()
	var reachable_counts: Dictionary = {}
	for node_id in reachable.keys():
		var node_type: String = str((nodes[node_id] as Dictionary).get("type", ""))
		reachable_counts[node_type] = int(reachable_counts.get(node_type, 0)) + 1
	var placement_count: int = 0
	for placement_type in ["surface", "cave_floor", "underground", "buried"]:
		placement_count += int(reachable_counts.get(placement_type, 0))
	if placement_count != 1:
		errors.append("Cada perfil precisa de exatamente um modo: Superficie, Piso de caverna, Subterranea ou Soterrada.")
	for singleton_type in ["chance", "priority", "minimum_distance", "transform"]:
		if int(reachable_counts.get(singleton_type, 0)) > 1:
			errors.append("O perfil possui mais de um no %s ativo." % singleton_type)
	if int(reachable_counts.get("exact_count", 0)) > 0 and (int(reachable_counts.get("minimum_count", 0)) > 0 or int(reachable_counts.get("maximum_count", 0)) > 0):
		errors.append("Quantidade exata nao pode ser combinada com quantidade minima ou maxima.")
	var settings: Dictionary = _compile_settings(nodes, reachable)
	if int(settings.get("exact_count", -1)) < 0 and int(settings.get("max_count", -1)) >= 0 and int(settings.get("min_count", 0)) > int(settings.get("max_count", -1)):
		errors.append("Quantidade minima nao pode exceder a quantidade maxima.")
	return {
		"errors": errors, "profile": profile.duplicate(true), "nodes": nodes,
		"incoming": incoming, "outgoing": outgoing, "reachable": reachable,
		"condition_roots": condition_roots, "settings": settings,
	}


static func evaluate(compiled: Dictionary, context: Dictionary, relaxations: Dictionary = {}) -> Dictionary:
	if not (compiled.get("errors", []) as Array).is_empty():
		return {"ok": false, "reasons": [{"node_id": "compile", "message": "Grafo invalido."}]}
	var reasons: Array = []
	var memo: Dictionary = {}
	for root_id in compiled.get("condition_roots", []) as Array:
		var result: Dictionary = _evaluate_node(str(root_id), compiled, context, relaxations, memo)
		if not bool(result.get("ok", false)):
			reasons.append_array(result.get("reasons", []) as Array)
	return {"ok": reasons.is_empty(), "reasons": reasons}


static func flexible_nodes(compiled: Dictionary) -> Array:
	var result: Array = []
	for raw_node in (compiled.get("nodes", {}) as Dictionary).values():
		var node: Dictionary = raw_node as Dictionary
		if bool(node.get("flexible", false)) and float(node.get("relax_limit", 0.0)) > 0.0 and str(node.get("type", "")) in RELAXABLE_TYPES:
			result.append(node)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: int = int(a.get("relax_priority", 0)); var pb: int = int(b.get("relax_priority", 0))
		return pa < pb if pa != pb else str(a.get("id", "")) < str(b.get("id", ""))
	)
	return result


static func _compile_settings(nodes: Dictionary, reachable: Dictionary) -> Dictionary:
	var settings: Dictionary = {
		"spacing": 24, "chance": 1.0, "min_count": 0, "max_count": -1,
		"exact_count": -1, "priority": 0, "min_distance": 0.0,
		"rotations": [0], "mirror_x_chance": 0.0, "mirror_z_chance": 0.0,
		"mode": "surface_adaptive", "min_depth": 12, "max_depth": 42, "minimum_cover": 4,
	}
	for node_id in reachable.keys():
		var node: Dictionary = nodes[node_id] as Dictionary
		var params: Dictionary = node.get("params", {}) as Dictionary
		match str(node.get("type", "")):
			"candidate_grid": settings["spacing"] = maxi(4, int(params.get("spacing", 24)))
			"chance": settings["chance"] = clampf(float(params.get("value", 1.0)), 0.0, 1.0)
			"minimum_count": settings["min_count"] = maxi(0, int(params.get("value", 0)))
			"maximum_count": settings["max_count"] = maxi(0, int(params.get("value", 1)))
			"exact_count": settings["exact_count"] = maxi(0, int(params.get("value", 1)))
			"priority": settings["priority"] = int(params.get("value", 0))
			"minimum_distance": settings["min_distance"] = maxf(0.0, float(params.get("value", 0.0)))
			"transform":
				settings["rotations"] = _normalized_rotations(params.get("rotations", [0]) as Array)
				settings["mirror_x_chance"] = clampf(float(params.get("mirror_x_chance", 0.0)), 0.0, 1.0)
				settings["mirror_z_chance"] = clampf(float(params.get("mirror_z_chance", 0.0)), 0.0, 1.0)
			"cave_floor": settings["mode"] = "cave_floor"
			"underground":
				settings["mode"] = "underground"
				settings["min_depth"] = maxi(1, int(params.get("min_depth", 12)))
				settings["max_depth"] = maxi(int(settings["min_depth"]), int(params.get("max_depth", 42)))
			"buried":
				settings["mode"] = "buried"
				settings["min_depth"] = maxi(1, int(params.get("min_depth", 12)))
				settings["max_depth"] = maxi(int(settings["min_depth"]), int(params.get("max_depth", 42)))
				settings["minimum_cover"] = maxi(1, int(params.get("minimum_cover", 4)))
	return settings


static func _evaluate_node(node_id: String, compiled: Dictionary, context: Dictionary, relaxations: Dictionary, memo: Dictionary) -> Dictionary:
	if memo.has(node_id):
		return memo[node_id]
	var nodes: Dictionary = compiled.get("nodes", {}) as Dictionary
	var incoming: Dictionary = compiled.get("incoming", {}) as Dictionary
	var node: Dictionary = nodes.get(node_id, {}) as Dictionary
	var node_type: String = str(node.get("type", ""))
	var children: Array = incoming.get(node_id, []) as Array
	var result: Dictionary
	if node_type in LOGIC_TYPES:
		var child_results: Array = []
		for child_id in children:
			child_results.append(_evaluate_node(str(child_id), compiled, context, relaxations, memo))
		match node_type:
			"and":
				var and_reasons: Array = []
				for child in child_results:
					if not bool((child as Dictionary).get("ok", false)): and_reasons.append_array((child as Dictionary).get("reasons", []) as Array)
				result = {"ok": and_reasons.is_empty(), "reasons": and_reasons}
			"or":
				var any_ok: bool = false; var or_reasons: Array = []
				for child in child_results:
					if bool((child as Dictionary).get("ok", false)): any_ok = true
					else: or_reasons.append_array((child as Dictionary).get("reasons", []) as Array)
				result = {"ok": any_ok, "reasons": [] if any_ok else or_reasons}
			_:
				var original_ok: bool = bool((child_results[0] as Dictionary).get("ok", false)) if child_results.size() == 1 else false
				result = {"ok": not original_ok, "reasons": [] if not original_ok else [_reason(node, "A condicao negada foi verdadeira.")]}
	else:
		result = _evaluate_condition(node, context, float(relaxations.get(node_id, 0.0)))
	memo[node_id] = result
	return result


static func _evaluate_condition(node: Dictionary, context: Dictionary, relax: float) -> Dictionary:
	var params: Dictionary = node.get("params", {}) as Dictionary
	var node_type: String = str(node.get("type", ""))
	var ok: bool = true
	var message: String = "Condicao nao atendida."
	match node_type:
		"biome":
			var coord: Array = params.get("coord", [0, 0]) as Array
			ok = context.get("tile_coord", Vector2i.ZERO) == Vector2i(int(coord[0]), int(coord[1]))
			message = "O candidato pertence a outro bioma."
		"zone":
			var mask: int = int(params.get("mask", 1))
			ok = (int(context.get("zone_flags", 0)) & mask) == mask
			message = "A zona exigida nao esta presente."
		"surface":
			ok = str(context.get("mode", "")) == "surface_adaptive"
			message = "O candidato nao esta na superficie."
		"cave_floor":
			ok = str(context.get("mode", "")) == "cave_floor"
			message = "Nenhum piso de caverna compativel foi encontrado."
		"underground":
			ok = str(context.get("mode", "")) == "underground"
			message = "O candidato nao atende ao modo subterraneo."
		"buried":
			ok = str(context.get("mode", "")) == "buried"
			message = "O volume nao esta completamente soterrado."
		"height":
			var y: float = float(context.get("anchor_y", 0)); ok = y >= float(params.get("min", -64)) - relax and y <= float(params.get("max", 126)) + relax
			message = "Altura Y fora do intervalo."
		"depth":
			var depth: float = float(context.get("depth", 0)); ok = depth >= maxf(0.0, float(params.get("min", 0)) - relax) and depth <= float(params.get("max", 96)) + relax
			message = "Profundidade fora do intervalo."
		"slope":
			ok = float(context.get("slope", 0)) <= float(params.get("max", 8)) + relax
			message = "Inclinacao excede o limite."
		"sky_visible":
			ok = bool(context.get("sky_visible", false)) == bool(params.get("required", true))
			message = "Visibilidade do ceu incompativel."
		"distance_edge":
			ok = float(context.get("distance_edge", 0)) >= maxf(0.0, float(params.get("min", 0)) - relax)
			message = "Candidato muito proximo da borda do bioma."
		"volume_air":
			var ratio: float = float(context.get("volume_air_ratio", 0.0)); ok = ratio >= maxf(0.0, float(params.get("min_ratio", 0.0)) - relax) and ratio <= minf(1.0, float(params.get("max_ratio", 1.0)) + relax)
			message = "Proporcao de ar no volume incompativel."
		"support_block":
			ok = bool(context.get("support_blocks_ok", false)) or relax >= 1.0
			message = "Bloco de apoio nao permitido."
		"distance_spawn":
			ok = float(context.get("distance_spawn", 0.0)) >= maxf(0.0, float(params.get("min", 0)) - relax)
			message = "Candidato muito proximo do spawn."
		_:
			ok = true
	return {"ok": ok, "reasons": [] if ok else [_reason(node, message)]}


static func _validate_params(node: Dictionary, errors: Array[String]) -> void:
	var node_id: String = str(node.get("id", "")); var node_type: String = str(node.get("type", "")); var params: Dictionary = node.get("params", {}) as Dictionary
	if node_type == "biome":
		var coord: Variant = params.get("coord", [])
		if typeof(coord) != TYPE_ARRAY or (coord as Array).size() < 2 or int((coord as Array)[0]) not in [0, 1] or int((coord as Array)[1]) not in [0, 1]: errors.append("No %s possui bioma invalido." % node_id)
	elif node_type == "candidate_grid" and int(params.get("spacing", 0)) < 4:
		errors.append("No %s exige spacing >= 4." % node_id)
	elif node_type in ["chance"] and (float(params.get("value", 0.0)) < 0.0 or float(params.get("value", 0.0)) > 1.0):
		errors.append("No %s exige valor entre 0 e 1." % node_id)
	elif node_type in ["minimum_count", "maximum_count", "exact_count"] and int(params.get("value", 0)) < 0:
		errors.append("No %s exige quantidade nao negativa." % node_id)
	if bool(node.get("flexible", false)) and float(node.get("relax_limit", 0.0)) <= 0.0:
		errors.append("No flexivel %s precisa de relax_limit positivo." % node_id)
	if bool(node.get("flexible", false)) and node_type not in RELAXABLE_TYPES:
		errors.append("No %s e uma condicao rigida e nao pode ser flexivel." % node_id)


static func _merged_params(node_type: String, params: Dictionary, definitions: Dictionary) -> Dictionary:
	var result: Dictionary = ((definitions[node_type] as Dictionary).get("defaults", {}) as Dictionary).duplicate(true)
	result.merge(params, true)
	return result


static func _node(id: String, type: String, position: Vector2, params: Dictionary) -> Dictionary:
	return {"id": id, "type": type, "position": [position.x, position.y], "params": params, "flexible": false, "relax_priority": 0, "relax_limit": 0.0}


static func _reason(node: Dictionary, message: String) -> Dictionary:
	return {"node_id": str(node.get("id", "")), "node_type": str(node.get("type", "")), "message": message}


static func _collect_ancestors(node_id: String, incoming: Dictionary, result: Dictionary) -> void:
	if result.has(node_id): return
	result[node_id] = true
	for parent_id in incoming.get(node_id, []) as Array: _collect_ancestors(str(parent_id), incoming, result)


static func _has_cycle(node_ids: Array, outgoing: Dictionary) -> bool:
	var state: Dictionary = {}
	for node_id in node_ids:
		if _visit_cycle(str(node_id), outgoing, state): return true
	return false


static func _visit_cycle(node_id: String, outgoing: Dictionary, state: Dictionary) -> bool:
	var current: int = int(state.get(node_id, 0))
	if current == 1: return true
	if current == 2: return false
	state[node_id] = 1
	for child_id in outgoing.get(node_id, []) as Array:
		if _visit_cycle(str(child_id), outgoing, state): return true
	state[node_id] = 2
	return false


static func _normalized_rotations(values: Array) -> Array:
	var result: Array[int] = []
	for value in values:
		var rotation: int = posmod(int(value), 4)
		if not result.has(rotation): result.append(rotation)
	if result.is_empty(): result.append(0)
	return result
