extends RefCounted
class_name BlockCatalog

const AIR: String = "air"
const COLOR_COUNT: int = 256   # blocos de cor pura (grade HSV 16 matizes x 16 tons)


## id determinístico do bloco de cor i (color_000..color_255)
static func color_block_id(i: int) -> String:
	return "color_%03d" % i


## a cor do bloco i: 16 colunas de matiz x 16 linhas variando saturação/valor;
## a última coluna é uma escala de cinza (do preto ao branco) para tons neutros.
static func color_of(i: int) -> Color:
	var col: int = i % 16
	var row: int = i / 16
	if col == 15:
		var t: float = float(row) / 15.0
		return Color(t, t, t)  # tons de cinza
	var hue: float = float(col) / 15.0
	var sat: float = 1.0 - float(row) * 0.045      # 1.0 -> ~0.33
	var val: float = 0.35 + float(row) * 0.043     # 0.35 -> ~1.0
	return Color.from_hsv(hue, clampf(sat, 0.2, 1.0), clampf(val, 0.2, 1.0))


static func _add_color_blocks(dict: Dictionary) -> void:
	for i in range(COLOR_COUNT):
		var id: String = color_block_id(i)
		dict[id] = {
			"name": "Cor %03d" % i,
			"drop": id,
			"color": color_of(i),
			"place_item": id,
			"interact": "",
			"solid": true,
		}


static func _add_color_items(dict: Dictionary) -> void:
	for i in range(COLOR_COUNT):
		var id: String = color_block_id(i)
		dict[id] = {"name": "Cor %03d" % i, "place_block": id, "tool": "", "icon": ""}


static func blocks() -> Dictionary:
	var base: Dictionary = _blocks_base()
	_add_color_blocks(base)
	return base


static func _blocks_base() -> Dictionary:
	return {
		"grass": {
			"name": "Grama",
			"drop": "dirt",
			"color": Color(0.24, 0.62, 0.22),
			"texture": "res://texture/used/grass_block_top.png",
			"textures": {
				"top": "res://texture/used/grass_block_top.png",
				"bottom": "res://texture/used/dirt.png",
				"side": "res://texture/used/grass_block_side.png"
			},
			"icon": "res://texture/used/grass_block_top.png",
			"place_item": "",
			"interact": "",
			"random_top_rotation": true
		},
		"dirt": {
			"name": "Terra",
			"drop": "dirt",
			"color": Color(0.42, 0.25, 0.12),
			"texture": "res://texture/used/dirt.png",
			"icon": "res://texture/used/dirt.png",
			"place_item": "dirt",
			"interact": ""
		},
		"stone": {
			"name": "Pedra",
			"drop": "cobblestone",
			"color": Color(0.42, 0.42, 0.42),
			"texture": "res://texture/used/stone.png",
			"icon": "res://texture/used/stone.png",
			"place_item": "cobblestone",
			"interact": ""
		},
		"cobblestone": {
			"name": "Pedregulho",
			"drop": "cobblestone",
			"color": Color(0.35, 0.35, 0.35),
			"texture": "res://texture/used/cobblestone.png",
			"icon": "res://texture/used/cobblestone.png",
			"place_item": "cobblestone",
			"interact": ""
		},
		"bedrock": {
			"name": "Rocha Matriz",
			"drop": "",
			"color": Color(0.08, 0.08, 0.09),
			"texture": "res://texture/used/bedrock.png",
			"icon": "res://texture/used/bedrock.png",
			"place_item": "",
			"interact": "",
			"breakable": false
		},
		"wood": {
			"name": "Madeira",
			"drop": "wood",
			"color": Color(0.45, 0.26, 0.10),
			"texture": "res://texture/used/oak_log.png",
			"textures": {
				"top": "res://texture/used/oak_log_top.png",
				"bottom": "res://texture/used/oak_log_top.png",
				"side": "res://texture/used/oak_log.png"
			},
			"icon": "res://texture/used/oak_log.png",
			"place_item": "wood",
			"interact": ""
		},
		"leaves": {
			"name": "Folhas",
			"drop": "",
			"color": Color(0.11, 0.45, 0.15),
			"texture": "res://texture/used/oak_leaves.png",
			"icon": "res://texture/used/oak_leaves.png",
			"place_item": "",
			"interact": "",
			"transparent": true,
			"alpha": 0.88,
			"foliage": true
		},
		"planks": {
			"name": "Tabuas",
			"drop": "planks",
			"color": Color(0.69, 0.45, 0.20),
			"texture": "res://texture/used/oak_planks.png",
			"icon": "res://texture/used/oak_planks.png",
			"place_item": "planks",
			"interact": ""
		},
		"copper_ore": {
			"name": "Minerio de Cobre",
			"drop": "copper",
			"color": Color(0.72, 0.35, 0.18),
			"texture": "res://texture/used/copper_ore.png",
			"icon": "res://texture/used/copper_ore.png",
			"place_item": "",
			"interact": ""
		},
		"iron_ore": {
			"name": "Minerio de Ferro",
			"drop": "iron",
			"color": Color(0.80, 0.78, 0.70),
			"texture": "res://texture/used/iron_ore.png",
			"icon": "res://texture/used/iron_ore.png",
			"place_item": "",
			"interact": ""
		},
		"coal_ore": {
			"name": "Carvao",
			"drop": "coal",
			"color": Color(0.08, 0.08, 0.08),
			"texture": "res://texture/used/coal_ore.png",
			"icon": "res://texture/used/coal_ore.png",
			"place_item": "",
			"interact": ""
		},
		"manita_ore": {
			"name": "Manita",
			"drop": "manita",
			"color": Color(0.10, 0.45, 1.0),
			"texture": "res://texture/used/diamond_ore.png",
			"icon": "res://texture/used/diamond_ore.png",
			"place_item": "",
			"interact": ""
		},
		"crafting_table": {
			"name": "Bancada 3x3",
			"drop": "crafting_table",
			"color": Color(0.55, 0.32, 0.14),
			"texture": "res://texture/used/crafting_table_side.png",
			"textures": {
				"top": "res://texture/used/crafting_table_top.png",
				"bottom": "res://texture/used/crafting_table_bottom.png",
				"front": "res://texture/used/crafting_table_front.png",
				"side": "res://texture/used/crafting_table_side.png"
			},
			"icon": "res://texture/used/crafting_table_top.png",
			"place_item": "crafting_table",
			"interact": "craft"
		},
		"chest": {
			"name": "Bau",
			"drop": "chest",
			"color": Color(0.78, 0.48, 0.16),
			"texture": "res://texture/used/barrel_side.png",
			"textures": {
				"top": "res://texture/used/barrel_top.png",
				"bottom": "res://texture/used/barrel_bottom.png",
				"front": "res://texture/used/barrel_side.png",
				"side": "res://texture/used/barrel_side.png"
			},
			"icon": "res://texture/used/barrel_top.png",
			"place_item": "chest",
			"interact": "chest"
		},
		"torch": {
			"name": "Tocha",
			"drop": "torch",
			"color": Color(1.0, 0.72, 0.22),
			"texture": "res://texture/minecraft/textures/block/torch.png",
			"icon": "res://texture/minecraft/textures/item/torch_inventory.png",
			"place_item": "torch",
			"interact": "",
			"transparent": true,
			"solid": false,
			"plant": true
		},
		"short_grass": {
			"name": "Grama Curta",
			"drop": "short_grass",
			"color": Color(0.24, 0.62, 0.22),
			"texture": "res://texture/used/short_grass.png",
			"icon": "res://texture/used/short_grass.png",
			"place_item": "short_grass",
			"interact": "",
			"transparent": true,
			"alpha": 1.0,
			"solid": false,
			"plant": true,
			"foliage": true
		},
		"wild_grass": {
			"name": "Grama Selvagem",
			"drop": "wild_grass",
			"color": Color(0.24, 0.62, 0.22),
			"texture": "res://texture/used/grass.png",
			"icon": "res://texture/used/grass.png",
			"place_item": "wild_grass",
			"interact": "",
			"transparent": true,
			"alpha": 1.0,
			"solid": false,
			"plant": true,
			"foliage": true
		},
		"poppy": {
			"name": "Papoula",
			"drop": "poppy",
			"color": Color(0.8, 0.1, 0.1),
			"texture": "res://texture/used/poppy.png",
			"icon": "res://texture/used/poppy.png",
			"place_item": "poppy",
			"interact": "",
			"transparent": true,
			"alpha": 1.0,
			"solid": false,
			"plant": true,
			"foliage": true
		},
		"dandelion": {
			"name": "Dente-de-Leao",
			"drop": "dandelion",
			"color": Color(0.9, 0.8, 0.1),
			"texture": "res://texture/used/dandelion.png",
			"icon": "res://texture/used/dandelion.png",
			"place_item": "dandelion",
			"interact": "",
			"transparent": true,
			"alpha": 1.0,
			"solid": false,
			"plant": true,
			"foliage": true
		},
		"cornflower": {
			"name": "Ciano",
			"drop": "cornflower",
			"color": Color(0.2, 0.4, 0.8),
			"texture": "res://texture/used/cornflower.png",
			"icon": "res://texture/used/cornflower.png",
			"place_item": "cornflower",
			"interact": "",
			"transparent": true,
			"alpha": 1.0,
			"solid": false,
			"plant": true,
			"foliage": true
		},
		"oxeye_daisy": {
			"name": "Margarida",
			"drop": "oxeye_daisy",
			"color": Color(0.8, 0.8, 0.8),
			"texture": "res://texture/used/oxeye_daisy.png",
			"icon": "res://texture/used/oxeye_daisy.png",
			"place_item": "oxeye_daisy",
			"interact": "",
			"transparent": true,
			"alpha": 1.0,
			"solid": false,
			"plant": true,
			"foliage": true
		}
	}

static func items() -> Dictionary:
	var base: Dictionary = _items_base()
	_add_color_items(base)
	return base


static func _items_base() -> Dictionary:
	return {
		"dirt": {"name": "Terra", "place_block": "dirt", "tool": "", "icon": "res://texture/used/dirt.png"},
		"cobblestone": {"name": "Pedregulho", "place_block": "cobblestone", "tool": "", "icon": "res://texture/used/cobblestone.png"},
		"wood": {"name": "Madeira", "place_block": "wood", "tool": "", "icon": "res://texture/used/oak_log.png"},
		"planks": {"name": "Tabuas", "place_block": "planks", "tool": "", "icon": "res://texture/used/oak_planks.png"},
		"crafting_table": {"name": "Bancada 3x3", "place_block": "crafting_table", "tool": "", "icon": "res://texture/used/crafting_table_top.png"},
		"chest": {"name": "Bau", "place_block": "chest", "tool": "", "icon": "res://texture/used/barrel_top.png"},
		"torch": {"name": "Tocha", "place_block": "torch", "tool": "", "icon": "res://texture/minecraft/textures/item/torch_inventory.png"},
		"copper": {"name": "Cobre", "place_block": "", "tool": "", "icon": "res://texture/used/raw_copper.png"},
		"iron": {"name": "Ferro", "place_block": "", "tool": "", "icon": "res://texture/used/raw_iron.png"},
		"coal": {"name": "Carvao", "place_block": "", "tool": "", "icon": "res://texture/used/coal.png"},
		"manita": {"name": "Manita", "place_block": "", "tool": "", "icon": "res://texture/used/diamond.png"},
		"stick": {"name": "Graveto", "place_block": "", "tool": "", "icon": "res://texture/used/stick.png"},
		"manita_pickaxe": {"name": "Picareta de Manita", "place_block": "", "tool": "pickaxe", "icon": "res://texture/used/diamond_pickaxe.png"},
		"wooden_pickaxe": {"name": "Picareta de Madeira", "place_block": "", "tool": "pickaxe", "icon": "res://texture/used/wooden_pickaxe.png"},
		"stone_pickaxe": {"name": "Picareta de Pedra", "place_block": "", "tool": "pickaxe", "icon": "res://texture/used/stone_pickaxe.png"},
		"iron_pickaxe": {"name": "Picareta de Ferro", "place_block": "", "tool": "pickaxe", "icon": "res://texture/used/iron_pickaxe.png"},
		"wooden_axe": {"name": "Machado de Madeira", "place_block": "", "tool": "axe", "icon": "res://texture/used/wooden_axe.png"},
		"stone_axe": {"name": "Machado de Pedra", "place_block": "", "tool": "axe", "icon": "res://texture/used/stone_axe.png"},
		"iron_axe": {"name": "Machado de Ferro", "place_block": "", "tool": "axe", "icon": "res://texture/used/iron_axe.png"},
		"wooden_shovel": {"name": "Pa de Madeira", "place_block": "", "tool": "shovel", "icon": "res://texture/used/wooden_shovel.png"},
		"stone_shovel": {"name": "Pa de Pedra", "place_block": "", "tool": "shovel", "icon": "res://texture/used/stone_shovel.png"},
		"iron_shovel": {"name": "Pa de Ferro", "place_block": "", "tool": "shovel", "icon": "res://texture/used/iron_shovel.png"},
		"wooden_hoe": {"name": "Enxada de Madeira", "place_block": "", "tool": "hoe", "icon": "res://texture/used/wooden_hoe.png"},
		"stone_hoe": {"name": "Enxada de Pedra", "place_block": "", "tool": "hoe", "icon": "res://texture/used/stone_hoe.png"},
		"iron_hoe": {"name": "Enxada de Ferro", "place_block": "", "tool": "hoe", "icon": "res://texture/used/iron_hoe.png"},
		"wooden_sword": {"name": "Espada de Madeira", "place_block": "", "tool": "sword", "icon": "res://texture/used/wooden_sword.png"},
		"stone_sword": {"name": "Espada de Pedra", "place_block": "", "tool": "sword", "icon": "res://texture/used/stone_sword.png"},
		"iron_sword": {"name": "Espada de Ferro", "place_block": "", "tool": "sword", "icon": "res://texture/used/iron_sword.png"},
		"short_grass": {"name": "Grama Curta", "place_block": "short_grass", "tool": "", "icon": "res://texture/used/short_grass.png"},
		"wild_grass": {"name": "Grama Selvagem", "place_block": "wild_grass", "tool": "", "icon": "res://texture/used/grass.png"},
		"poppy": {"name": "Papoula", "place_block": "poppy", "tool": "", "icon": "res://texture/used/poppy.png"},
		"dandelion": {"name": "Dente-de-Leao", "place_block": "dandelion", "tool": "", "icon": "res://texture/used/dandelion.png"},
		"cornflower": {"name": "Ciano", "place_block": "cornflower", "tool": "", "icon": "res://texture/used/cornflower.png"},
		"oxeye_daisy": {"name": "Margarida", "place_block": "oxeye_daisy", "tool": "", "icon": "res://texture/used/oxeye_daisy.png"}
	}

static func attack_damage(item_id: String) -> float:
	if item_id.ends_with("_sword"):
		return _tier_damage(item_id, 5.0, 10.0, 15.0)
	var tool: String = str((items().get(item_id, {}) as Dictionary).get("tool", ""))
	if tool in ["pickaxe", "axe", "shovel", "hoe"]:
		return _tier_damage(item_id, 2.5, 5.0, 7.5)
	return 1.0

static func _tier_damage(item_id: String, wooden: float, stone: float, iron: float) -> float:
	if item_id.begins_with("wooden_"):
		return wooden
	if item_id.begins_with("stone_"):
		return stone
	return iron

static func recipes() -> Array:
	return [
		{
			"name": "Tabuas x4",
			"shape": [["wood"]],
			"output": "planks",
			"count": 4
		},
		{
			"name": "Gravetos x4",
			"shape": [["planks"], ["planks"]],
			"output": "stick",
			"count": 4
		},
		{
			"name": "Bancada 3x3",
			"shape": [["planks", "planks"], ["planks", "planks"]],
			"output": "crafting_table",
			"count": 1
		},
		{
			"name": "Bau",
			"shape": [
				["planks", "planks", "planks"],
				["planks", "", "planks"],
				["planks", "planks", "planks"]
			],
			"output": "chest",
			"count": 1
		},
		{
			"name": "Tocha x4",
			"shape": [["coal"], ["stick"]],
			"output": "torch",
			"count": 4
		},
		{
			"name": "Picareta de Manita",
			"shape": [
				["manita", "manita", "manita"],
				["", "stick", ""],
				["", "stick", ""]
			],
			"output": "manita_pickaxe",
			"count": 1
		},
		{
			"name": "Picareta de Madeira",
			"shape": [
				["planks", "planks", "planks"],
				["", "stick", ""],
				["", "stick", ""]
			],
			"output": "wooden_pickaxe",
			"count": 1
		},
		{
			"name": "Picareta de Pedra",
			"shape": [
				["cobblestone", "cobblestone", "cobblestone"],
				["", "stick", ""],
				["", "stick", ""]
			],
			"output": "stone_pickaxe",
			"count": 1
		},
		{
			"name": "Picareta de Ferro",
			"shape": [
				["iron", "iron", "iron"],
				["", "stick", ""],
				["", "stick", ""]
			],
			"output": "iron_pickaxe",
			"count": 1
		},
		{
			"name": "Machado de Madeira",
			"shape": [
				["planks", "planks"],
				["planks", "stick"],
				["", "stick"]
			],
			"output": "wooden_axe",
			"count": 1
		},
		{
			"name": "Machado de Pedra",
			"shape": [
				["cobblestone", "cobblestone"],
				["cobblestone", "stick"],
				["", "stick"]
			],
			"output": "stone_axe",
			"count": 1
		},
		{
			"name": "Machado de Ferro",
			"shape": [
				["iron", "iron"],
				["iron", "stick"],
				["", "stick"]
			],
			"output": "iron_axe",
			"count": 1
		},
		{
			"name": "Pa de Madeira",
			"shape": [
				["planks"],
				["stick"],
				["stick"]
			],
			"output": "wooden_shovel",
			"count": 1
		},
		{
			"name": "Pa de Pedra",
			"shape": [
				["cobblestone"],
				["stick"],
				["stick"]
			],
			"output": "stone_shovel",
			"count": 1
		},
		{
			"name": "Pa de Ferro",
			"shape": [
				["iron"],
				["stick"],
				["stick"]
			],
			"output": "iron_shovel",
			"count": 1
		},
		{
			"name": "Enxada de Madeira",
			"shape": [
				["planks", "planks"],
				["", "stick"],
				["", "stick"]
			],
			"output": "wooden_hoe",
			"count": 1
		},
		{
			"name": "Enxada de Pedra",
			"shape": [
				["cobblestone", "cobblestone"],
				["", "stick"],
				["", "stick"]
			],
			"output": "stone_hoe",
			"count": 1
		},
		{
			"name": "Enxada de Ferro",
			"shape": [
				["iron", "iron"],
				["", "stick"],
				["", "stick"]
			],
			"output": "iron_hoe",
			"count": 1
		},
		{
			"name": "Espada de Madeira",
			"shape": [
				["planks"],
				["planks"],
				["stick"]
			],
			"output": "wooden_sword",
			"count": 1
		},
		{
			"name": "Espada de Pedra",
			"shape": [
				["cobblestone"],
				["cobblestone"],
				["stick"]
			],
			"output": "stone_sword",
			"count": 1
		},
		{
			"name": "Espada de Ferro",
			"shape": [
				["iron"],
				["iron"],
				["stick"]
			],
			"output": "iron_sword",
			"count": 1
		}
	]
