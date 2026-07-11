class_name BlueprintData
extends RefCounted
## Molde de maquina multibloco (estilo Satisfactory). O dev captura uma regiao do
## mundo como blueprint; o jogador posiciona um holograma e entrega os materiais
## camada por camada ate a maquina ficar pronta e funcional.

const FORMAT: String = "trumancraft_blueprint"
const VERSION: int = 1

var id: String = ""
var display_name: String = ""
var size: Vector3i = Vector3i.ONE
# blocos: Vector3i (local, base no canto minimo) -> block_id
var blocks: Dictionary = {}
# pontos funcionais: [{"pos": Vector3i, "type": String}]  (type: input/output/power/core)
var functional: Array = []


static func capturar(world, minimo: Vector3i, maximo: Vector3i, nome: String) -> BlueprintData:
	var bp = (load("res://src/blueprint_data.gd") as GDScript).new()
	bp.id = nome.to_snake_case()
	bp.display_name = nome
	bp.size = maximo - minimo + Vector3i.ONE
	for y in range(minimo.y, maximo.y + 1):
		for z in range(minimo.z, maximo.z + 1):
			for x in range(minimo.x, maximo.x + 1):
				var id_bloco: String = world.get_block_id(Vector3i(x, y, z))
				if id_bloco != "":
					bp.blocks[Vector3i(x, y, z) - minimo] = id_bloco
	return bp


## Custo total: block_id -> quantidade (pro HUD e pra checar o inventario).
func custo() -> Dictionary:
	var total: Dictionary = {}
	for pos in blocks:
		var id_bloco: String = blocks[pos]
		total[id_bloco] = int(total.get(id_bloco, 0)) + 1
	return total


## Requisito de UMA camada (y local): block_id -> quantidade.
func custo_camada(y: int) -> Dictionary:
	var total: Dictionary = {}
	for pos in blocks:
		if (pos as Vector3i).y == y:
			var id_bloco: String = blocks[pos]
			total[id_bloco] = int(total.get(id_bloco, 0)) + 1
	return total


## Blocos de uma camada apos rotacao, em coordenadas de mundo. Retorna [{pos,id}].
func blocos_camada_mundo(y: int, base: Vector3i, rot: int) -> Array:
	var lista: Array = []
	for pos in blocks:
		var p: Vector3i = pos
		if p.y == y:
			lista.append({"pos": base + _rotacionar(p, rot), "id": blocks[pos]})
	return lista


func _rotacionar(p: Vector3i, rot: int) -> Vector3i:
	match rot:
		1: return Vector3i(size.z - 1 - p.z, p.y, p.x)
		2: return Vector3i(size.x - 1 - p.x, p.y, size.z - 1 - p.z)
		3: return Vector3i(p.z, p.y, size.x - 1 - p.x)
		_: return p


func size_rotacionado(rot: int) -> Vector3i:
	return Vector3i(size.z, size.y, size.x) if rot % 2 == 1 else size


func to_dictionary() -> Dictionary:
	var lista_blocos: Array = []
	for pos in blocks:
		var p: Vector3i = pos
		lista_blocos.append([p.x, p.y, p.z, blocks[pos]])
	var lista_func: Array = []
	for f in functional:
		var fp: Vector3i = f["pos"]
		lista_func.append([fp.x, fp.y, fp.z, f["type"]])
	return {
		"format": FORMAT, "version": VERSION, "id": id, "display_name": display_name,
		"size": [size.x, size.y, size.z], "blocks": lista_blocos, "functional": lista_func
	}


func save_to_file(caminho: String) -> bool:
	var arquivo: FileAccess = FileAccess.open(caminho, FileAccess.WRITE)
	if arquivo == null:
		return false
	arquivo.store_string(JSON.stringify(to_dictionary(), "\t"))
	return true


static func load_from_file(caminho: String) -> BlueprintData:
	if not FileAccess.file_exists(caminho):
		return null
	var arquivo: FileAccess = FileAccess.open(caminho, FileAccess.READ)
	if arquivo == null:
		return null
	var json: JSON = JSON.new()
	if json.parse(arquivo.get_as_text()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return null
	var dados: Dictionary = json.data
	if str(dados.get("format", "")) != FORMAT:
		return null
	var bp = (load("res://src/blueprint_data.gd") as GDScript).new()
	bp.id = str(dados.get("id", ""))
	bp.display_name = str(dados.get("display_name", bp.id))
	var s: Array = dados.get("size", [1, 1, 1])
	bp.size = Vector3i(int(s[0]), int(s[1]), int(s[2]))
	for entrada in dados.get("blocks", []):
		if entrada is Array and entrada.size() >= 4:
			bp.blocks[Vector3i(int(entrada[0]), int(entrada[1]), int(entrada[2]))] = str(entrada[3])
	for entrada in dados.get("functional", []):
		if entrada is Array and entrada.size() >= 4:
			bp.functional.append({"pos": Vector3i(int(entrada[0]), int(entrada[1]), int(entrada[2])), "type": str(entrada[3])})
	return bp
