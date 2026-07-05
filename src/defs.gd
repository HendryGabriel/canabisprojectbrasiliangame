extends Node
# Dados estaticos do jogo: cepas, itens, precos, receitas, predios, metas, lotes.
# Item = "produto:cepa" (ex "bud:og_kush") ou generico (ex "madeira"). GDD §3.

enum Cat { RUDERALIS, SATIVA, INDICA, HYBRID }

const TILE_SIZE := 16

const CAT_NOME := {Cat.RUDERALIS: "Ruderalis", Cat.SATIVA: "Sativa", Cat.INDICA: "Indica", Cat.HYBRID: "Híbrida"}

# grow em ticks (10/s). Ciclos curtos no inicio (GDD: progressao rapida).
const STRAINS := {
	"ruderalis": {"nome": "Ruderalis", "cat": Cat.RUDERALIS, "preco": 8, "grow": 100, "semente": 10, "tier": 0},
	"jack_herer": {"nome": "Jack Herer", "cat": Cat.SATIVA, "preco": 18, "grow": 160, "semente": 40, "tier": 1},
	"northern_lights": {"nome": "Northern Lights", "cat": Cat.INDICA, "preco": 20, "grow": 170, "semente": 50, "tier": 1},
	"sour_diesel": {"nome": "Sour Diesel", "cat": Cat.SATIVA, "preco": 24, "grow": 190, "semente": 70, "tier": 2},
	"granddaddy_purple": {"nome": "Granddaddy Purple", "cat": Cat.INDICA, "preco": 26, "grow": 200, "semente": 80, "tier": 2},
	"durban_poison": {"nome": "Durban Poison", "cat": Cat.SATIVA, "preco": 30, "grow": 220, "semente": 110, "tier": 3},
	"purple_kush": {"nome": "Purple Kush", "cat": Cat.INDICA, "preco": 32, "grow": 230, "semente": 120, "tier": 3},
	"blue_dream": {"nome": "Blue Dream", "cat": Cat.HYBRID, "preco": 38, "grow": 260, "semente": 170, "tier": 3},
	"gsc": {"nome": "Girl Scout Cookies", "cat": Cat.HYBRID, "preco": 44, "grow": 280, "semente": 220, "tier": 4},
	"og_kush": {"nome": "OG Kush", "cat": Cat.HYBRID, "preco": 52, "grow": 300, "semente": 280, "tier": 4},
}

# Itens genericos (sem cepa) -> preco de venda
const GENERICOS := {
	"madeira": 2, "seda": 3, "vidro": 12, "areia": 1, "gelo": 4,
	"blend_sativa": 55, "blend_indica": 60, "blend_hibrida": 95,
}

# Multiplicador (%) do preco da cepa por produto processado
const PROD_MULT := {
	"bud": 100, "semente": 50, "prensado": 260, "pura": 300,
	"haxixe": 700, "ice": 480, "cbd": 620, "baseado": 230,
}

const PROD_NOME := {
	"bud": "Bud", "semente": "Semente", "prensado": "Prensado", "pura": "M. Pura",
	"haxixe": "Haxixe", "ice": "Ice", "cbd": "CBD", "baseado": "Baseado",
	"madeira": "Madeira", "seda": "Seda", "vidro": "Vidro", "areia": "Areia",
	"gelo": "Gelo", "blend_sativa": "Blend Sativa", "blend_indica": "Blend Indica",
	"blend_hibrida": "Blend Híbrida",
}

# Predios construiveis. energia<0 = gera. tier = quando destrava.
const PREDIOS := {
	"esteira": {"nome": "Esteira", "tam": Vector2i(1, 1), "custo": 5, "energia": 0, "tier": 0},
	"canteiro": {"nome": "Canteiro", "tam": Vector2i(1, 1), "custo": 15, "energia": 0, "tier": 0},
	"bancada": {"nome": "Bancada de Prensa", "tam": Vector2i(1, 1), "custo": 40, "energia": 0, "tier": 0},
	"cano": {"nome": "Cano", "tam": Vector2i(1, 1), "custo": 8, "energia": 0, "tier": 1},
	"poco": {"nome": "Poço (ao lado de água)", "tam": Vector2i(1, 1), "custo": 120, "energia": 4, "tier": 1},
	"maq_pura": {"nome": "Máquina de Pura", "tam": Vector2i(1, 1), "custo": 250, "energia": 5, "tier": 1},
	"maq_semente": {"nome": "Extrator de Sementes", "tam": Vector2i(1, 1), "custo": 350, "energia": 5, "tier": 1},
	"estufa_mini": {"nome": "Mini Estufa", "tam": Vector2i(2, 2), "custo": 400, "energia": 6, "tier": 1},
	"maq_blend": {"nome": "Misturadora", "tam": Vector2i(2, 2), "custo": 500, "energia": 8, "tier": 2},
	"maq_baseado": {"nome": "Boladora", "tam": Vector2i(2, 2), "custo": 600, "energia": 8, "tier": 2},
	"extrator_madeira": {"nome": "Extrator de Madeira (na árvore)", "tam": Vector2i(1, 1), "custo": 150, "energia": 4, "tier": 2},
	"fab_seda": {"nome": "Fábrica de Seda", "tam": Vector2i(1, 1), "custo": 200, "energia": 4, "tier": 2},
	"solar": {"nome": "Painel Solar", "tam": Vector2i(1, 1), "custo": 800, "energia": -6, "tier": 2},
	"gerador": {"nome": "Gerador a Biomassa", "tam": Vector2i(2, 2), "custo": 1200, "energia": -30, "tier": 2},
	"filtro": {"nome": "Filtro de Carvão", "tam": Vector2i(1, 1), "custo": 500, "energia": 2, "tier": 2},
	"maq_haxixe": {"nome": "Prensa de Haxixe", "tam": Vector2i(2, 2), "custo": 800, "energia": 10, "tier": 3},
	"fab_gelo": {"nome": "Fazedor de Gelo", "tam": Vector2i(1, 1), "custo": 300, "energia": 8, "tier": 3},
	"maq_ice": {"nome": "Extrator de Ice", "tam": Vector2i(2, 2), "custo": 900, "energia": 12, "tier": 3},
	"extrator_areia": {"nome": "Extrator de Areia (na areia)", "tam": Vector2i(1, 1), "custo": 150, "energia": 4, "tier": 3},
	"fornalha": {"nome": "Fornalha de Vidro", "tam": Vector2i(2, 2), "custo": 700, "energia": 15, "tier": 3},
	"estufa_grande": {"nome": "Grande Estufa", "tam": Vector2i(3, 3), "custo": 1500, "energia": 14, "tier": 3},
	"maq_cbd": {"nome": "Extrator de CBD", "tam": Vector2i(3, 3), "custo": 1500, "energia": 15, "tier": 4},
}

# Receitas. t em ticks. "in": produto-com-cepa (bud/pura) trava a cepa; genericos casam por id.
# "bud2cat": 2 buds de cepas DIFERENTES da MESMA categoria -> blend (GDD §5).
# "agua": volume consumido da rede de canos adjacente por craft.
const RECEITAS := {
	"bancada": {"t": 25, "in": {"bud": 2}, "out": "prensado", "n": 1, "manual": true},
	"maq_pura": {"t": 40, "in": {"bud": 2}, "out": "pura", "n": 1},
	"maq_blend": {"t": 50, "in": {"bud2cat": 2}, "out": "blend", "n": 1},
	"maq_haxixe": {"t": 80, "in": {"bud": 4}, "out": "haxixe", "n": 1},
	"maq_ice": {"t": 120, "in": {"pura": 1, "gelo": 1}, "out": "ice", "n": 1},
	"maq_cbd": {"t": 100, "in": {"bud": 2, "vidro": 1}, "agua": 50, "out": "cbd", "n": 1},
	"maq_baseado": {"t": 40, "in": {"bud": 1, "seda": 1}, "out": "baseado", "n": 1},
	"maq_semente": {"t": 60, "in": {"bud": 2}, "out": "semente", "n": 1},
	"fab_seda": {"t": 40, "in": {"madeira": 1}, "out": "seda", "n": 2},
	"fab_gelo": {"t": 50, "in": {}, "agua": 30, "out": "gelo", "n": 1},
	"fornalha": {"t": 60, "in": {"areia": 2}, "out": "vidro", "n": 1},
	"extrator_madeira": {"t": 80, "in": {}, "out": "madeira", "n": 1},
	"extrator_areia": {"t": 60, "in": {}, "out": "areia", "n": 1},
}

# Sprites de maquina fornecidos (substituem o icone procedural no mundo e na hotbar).
const MACHINE_SPRITES := {
	"maq_pura": "res://src/ASSETS/MACHINE_ICONS/refine_weed.png",
	"fab_seda": "res://src/ASSETS/MACHINE_ICONS/silk_machine.png",
	"estufa_mini": "res://src/ASSETS/MACHINE_ICONS/mini_estufa.png",
}

# Estufas: consomem 1 semente + agua por ciclo, produzem buds (GDD §5).
const ESTUFAS := {
	"estufa_mini": {"t": 150, "agua": 20, "buds": 3},
	"estufa_grande": {"t": 200, "agua": 40, "buds": 8},
}

# Metas de producao (estilo Space Elevator): vender X do produto destrava o tier.
const METAS := [
	{"tier": 1, "desc": "Venda 20 Buds", "itens": ["bud"], "qtd": 20},
	{"tier": 2, "desc": "Venda 15 Maconha Pura", "itens": ["pura"], "qtd": 15},
	{"tier": 3, "desc": "Venda 10 Blends ou Baseados", "itens": ["blend_sativa", "blend_indica", "blend_hibrida", "baseado"], "qtd": 10},
	{"tier": 4, "desc": "Venda 10 Haxixe ou Ice", "itens": ["haxixe", "ice"], "qtd": 10},
	{"tier": 5, "desc": "Venda 10 CBD — vire o Maior Produtor!", "itens": ["cbd"], "qtd": 10},
]

# Lotes de terra (indice 0 = casa+quintal, gratis). Comprados em ordem no PC.
const LOTES := [
	{"custo": 0, "rect": Rect2i(0, 0, 26, 20)},
	{"custo": 300, "rect": Rect2i(26, 0, 16, 20)},
	{"custo": 800, "rect": Rect2i(0, 20, 26, 16)},
	{"custo": 2000, "rect": Rect2i(26, 20, 16, 16)},
	{"custo": 5000, "rect": Rect2i(42, 0, 22, 36)},
]


func item_preco(item: String) -> int:
	if GENERICOS.has(item):
		return GENERICOS[item]
	var p := item.split(":")
	if p.size() == 2 and PROD_MULT.has(p[0]) and STRAINS.has(p[1]):
		return STRAINS[p[1]]["preco"] * PROD_MULT[p[0]] / 100
	return 0


func item_nome(item: String) -> String:
	if PROD_NOME.has(item):
		return PROD_NOME[item]
	var p := item.split(":")
	if p.size() == 2:
		var prod: String = PROD_NOME.get(p[0], p[0])
		var cepa: String = STRAINS[p[1]]["nome"] if STRAINS.has(p[1]) else p[1]
		return "%s (%s)" % [prod, cepa]
	return item


func item_prod(item: String) -> String:
	return item.split(":")[0] if ":" in item else item


func item_cepa(item: String) -> String:
	var p := item.split(":")
	return p[1] if p.size() == 2 else ""
