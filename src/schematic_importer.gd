class_name SchematicImporter
extends RefCounted
## Converte schematics do Minecraft em blocos do TRUMANCRAFT.
## Suporta: .schem (Sponge v1/v2/v3 - WorldEdit moderno), .nbt (structure block)
## e .schematic (MCEdit legado). Nomes minecraft:* sao mapeados para o catalogo;
## o que nao tem equivalente vira ar e e reportado em "unmapped".

const NbtReaderScript = preload("res://src/nbt_reader.gd")

# minecraft:<nome> -> id do BlockCatalog (mapeamento direto)
const MAPA_MC := {
	"stone": "stone", "cobblestone": "cobblestone", "mossy_cobblestone": "cobblestone",
	"dirt": "dirt", "coarse_dirt": "dirt", "rooted_dirt": "dirt", "podzol": "dirt",
	"mycelium": "dirt", "mud": "dirt", "clay": "dirt", "grass_block": "grass",
	"bedrock": "bedrock", "gravel": "cobblestone",
	"coal_ore": "coal_ore", "deepslate_coal_ore": "coal_ore",
	"iron_ore": "iron_ore", "deepslate_iron_ore": "iron_ore",
	"gold_ore": "iron_ore", "deepslate_gold_ore": "iron_ore",
	"copper_ore": "copper_ore", "deepslate_copper_ore": "copper_ore",
	"diamond_ore": "manita_ore", "deepslate_diamond_ore": "manita_ore",
	"emerald_ore": "manita_ore", "lapis_ore": "copper_ore", "redstone_ore": "iron_ore",
	"crafting_table": "crafting_table", "chest": "chest", "barrel": "chest",
	"trapped_chest": "chest", "torch": "torch", "wall_torch": "torch",
	"soul_torch": "torch", "lantern": "torch",
	"short_grass": "short_grass", "grass": "short_grass", "fern": "short_grass",
	"tall_grass": "wild_grass", "large_fern": "wild_grass",
	"poppy": "poppy", "dandelion": "dandelion", "cornflower": "cornflower",
	"oxeye_daisy": "oxeye_daisy", "azure_bluet": "oxeye_daisy",
	"blue_orchid": "cornflower", "allium": "poppy",
}

# ids numericos do .schematic legado (MCEdit) -> id do catalogo ("" = ar/pular)
const MAPA_LEGADO := {
	0: "", 1: "stone", 2: "grass", 3: "dirt", 4: "cobblestone", 5: "planks",
	7: "bedrock", 12: "dirt", 13: "cobblestone", 14: "iron_ore", 15: "iron_ore",
	16: "coal_ore", 17: "wood", 18: "leaves", 19: "stone", 21: "copper_ore",
	24: "stone", 31: "short_grass", 37: "dandelion", 38: "poppy", 41: "stone",
	42: "stone", 43: "stone", 44: "stone", 45: "stone", 47: "planks",
	48: "cobblestone", 49: "stone", 50: "torch", 53: "planks", 54: "chest",
	56: "manita_ore", 58: "crafting_table", 61: "stone", 62: "stone",
	67: "cobblestone", 73: "iron_ore", 82: "dirt", 85: "planks", 87: "stone",
	89: "torch", 98: "stone", 109: "stone", 112: "stone", 125: "planks",
	126: "planks", 128: "stone", 134: "planks", 135: "planks", 136: "planks",
	139: "cobblestone", 155: "stone", 156: "stone", 162: "wood", 161: "leaves",
	179: "stone", 180: "stone",
}


## Retorna {"ok": bool, "erro": String, "size": Vector3i,
##          "blocks": {Vector3i: id}, "unmapped": {nome: qtd}, "total": int}
static func importar(caminho: String, block_defs: Dictionary) -> Dictionary:
	var raiz: Dictionary = NbtReaderScript.abrir(caminho)
	if raiz.is_empty():
		return {"ok": false, "erro": "Nao foi possivel ler o arquivo NBT."}
	var ext := caminho.get_extension().to_lower()
	if raiz.has("BlockData") or (raiz.has("Blocks") and raiz["Blocks"] is Dictionary):
		return _importa_sponge(raiz, block_defs)
	if raiz.has("blocks") and raiz.has("palette"):
		return _importa_structure_nbt(raiz, block_defs)
	if ext == "schematic" or (raiz.has("Blocks") and raiz.has("Width")):
		return _importa_legado(raiz, block_defs)
	return {"ok": false, "erro": "Formato de schematic nao reconhecido."}


static func _mapear(nome_mc: String, block_defs: Dictionary) -> String:
	var nome := nome_mc.replace("minecraft:", "")
	var estado := nome.find("[")
	if estado >= 0:
		nome = nome.substr(0, estado)
	if nome == "air" or nome == "cave_air" or nome == "void_air" or nome == "water" or nome == "lava":
		return ""
	if MAPA_MC.has(nome):
		return MAPA_MC[nome]
	if block_defs.has(nome):
		return nome  # ja existe no catalogo com o mesmo nome
	# heuristica por familia (cobre a maioria dos blocos de construcao)
	if nome.contains("leaves"):
		return "leaves"
	if nome.ends_with("_log") or nome.ends_with("_stem") or nome.ends_with("_hyphae") or nome.ends_with("_wood") or nome == "bamboo_block":
		return "wood"
	if nome.contains("plank") or nome.contains("_fence") or nome.ends_with("_stairs") and nome.contains("oak"):
		return "planks"
	if nome.contains("cobble"):
		return "cobblestone"
	var pedra := ["stone", "deepslate", "granite", "diorite", "andesite", "tuff", "calcite",
		"basalt", "blackstone", "sandstone", "brick", "concrete", "terracotta", "quartz",
		"purpur", "prismarine", "obsidian", "netherrack", "end_stone", "sand", "snow", "ice",
		"packed_mud", "wool", "glass"]
	for familia in pedra:
		if nome.contains(familia):
			return "stone"
	if nome.ends_with("_stairs") or nome.ends_with("_slab") or nome.ends_with("_wall"):
		return "stone"
	return ""  # desconhecido: vira ar e conta em unmapped


static func _importa_sponge(raiz: Dictionary, block_defs: Dictionary) -> Dictionary:
	var largura := int(raiz.get("Width", 0))
	var altura := int(raiz.get("Height", 0))
	var comprimento := int(raiz.get("Length", 0))
	if largura <= 0 or altura <= 0 or comprimento <= 0:
		return {"ok": false, "erro": "Dimensoes invalidas no schematic."}
	var paleta: Dictionary = {}
	var dados: PackedByteArray = PackedByteArray()
	if raiz.has("Blocks") and raiz["Blocks"] is Dictionary:  # Sponge v3
		var blocos_v3: Dictionary = raiz["Blocks"]
		paleta = blocos_v3.get("Palette", {})
		dados = blocos_v3.get("Data", PackedByteArray())
	else:  # Sponge v1/v2
		paleta = raiz.get("Palette", {})
		dados = raiz.get("BlockData", PackedByteArray())
	if paleta.is_empty() or dados.is_empty():
		return {"ok": false, "erro": "Schematic sem paleta ou dados de blocos."}
	# paleta: nome -> indice; inverte e ja mapeia pro catalogo
	var por_indice: Dictionary = {}
	var unmapped: Dictionary = {}
	for nome_mc in paleta:
		var id_jogo := _mapear(str(nome_mc), block_defs)
		por_indice[int(paleta[nome_mc])] = id_jogo
		if id_jogo == "" and not str(nome_mc).contains("air"):
			unmapped[str(nome_mc)] = 0
	# BlockData: varints em ordem YZX (i = x + z*W + y*W*L)
	var blocks: Dictionary = {}
	var i := 0
	var pos_dado := 0
	var total := largura * altura * comprimento
	while pos_dado < dados.size() and i < total:
		var valor := 0
		var shift := 0
		while true:
			var b := dados[pos_dado]
			pos_dado += 1
			valor |= (b & 0x7f) << shift
			if (b & 0x80) == 0:
				break
			shift += 7
		var id_jogo: String = por_indice.get(valor, "")
		if id_jogo != "":
			var x := i % largura
			var z := (i / largura) % comprimento
			var y := i / (largura * comprimento)
			blocks[Vector3i(x, y, z)] = id_jogo
		else:
			var nome_original := _nome_da_paleta(paleta, valor)
			if nome_original != "" and unmapped.has(nome_original):
				unmapped[nome_original] = int(unmapped[nome_original]) + 1
		i += 1
	return {"ok": true, "erro": "", "size": Vector3i(largura, altura, comprimento), "blocks": blocks, "unmapped": unmapped, "total": total}


static func _nome_da_paleta(paleta: Dictionary, indice: int) -> String:
	for nome in paleta:
		if int(paleta[nome]) == indice:
			return str(nome)
	return ""


static func _importa_structure_nbt(raiz: Dictionary, block_defs: Dictionary) -> Dictionary:
	var tamanho_raw: Array = raiz.get("size", [])
	if tamanho_raw.size() != 3:
		return {"ok": false, "erro": "Structure NBT sem tamanho."}
	var tamanho := Vector3i(int(tamanho_raw[0]), int(tamanho_raw[1]), int(tamanho_raw[2]))
	var paleta_raw: Array = raiz.get("palette", [])
	var mapeada: Array = []
	var unmapped: Dictionary = {}
	for entrada in paleta_raw:
		var nome_mc := str((entrada as Dictionary).get("Name", "air"))
		var id_jogo := _mapear(nome_mc, block_defs)
		mapeada.append(id_jogo)
		if id_jogo == "" and not nome_mc.contains("air"):
			unmapped[nome_mc] = 0
	var blocks: Dictionary = {}
	for entrada_bloco in raiz.get("blocks", []):
		var dado: Dictionary = entrada_bloco
		var estado := int(dado.get("state", 0))
		var pos_raw: Array = dado.get("pos", [])
		if estado < 0 or estado >= mapeada.size() or pos_raw.size() != 3:
			continue
		var id_jogo2: String = mapeada[estado]
		if id_jogo2 == "":
			var nome2 := str((paleta_raw[estado] as Dictionary).get("Name", ""))
			if unmapped.has(nome2):
				unmapped[nome2] = int(unmapped[nome2]) + 1
			continue
		blocks[Vector3i(int(pos_raw[0]), int(pos_raw[1]), int(pos_raw[2]))] = id_jogo2
	return {"ok": true, "erro": "", "size": tamanho, "blocks": blocks, "unmapped": unmapped, "total": tamanho.x * tamanho.y * tamanho.z}


static func _importa_legado(raiz: Dictionary, _block_defs: Dictionary) -> Dictionary:
	var largura := int(raiz.get("Width", 0))
	var altura := int(raiz.get("Height", 0))
	var comprimento := int(raiz.get("Length", 0))
	var bytes: PackedByteArray = raiz.get("Blocks", PackedByteArray())
	if largura <= 0 or altura <= 0 or comprimento <= 0 or bytes.is_empty():
		return {"ok": false, "erro": "Schematic MCEdit invalido."}
	var blocks: Dictionary = {}
	var unmapped: Dictionary = {}
	for i in bytes.size():
		var id_num := int(bytes[i])
		var id_jogo: String = MAPA_LEGADO.get(id_num, "")
		if id_jogo == "":
			if id_num != 0 and not MAPA_LEGADO.has(id_num):
				var chave := "id_%d" % id_num
				unmapped[chave] = int(unmapped.get(chave, 0)) + 1
			continue
		var x := i % largura
		var z := (i / largura) % comprimento
		var y := i / (largura * comprimento)
		blocks[Vector3i(x, y, z)] = id_jogo
	return {"ok": true, "erro": "", "size": Vector3i(largura, altura, comprimento), "blocks": blocks, "unmapped": unmapped, "total": bytes.size()}
