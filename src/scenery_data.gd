class_name SceneryData
extends RefCounted
## Cenário estático do Editor de Mapa: uma lista de cubos coloridos em várias escalas.
## Coordenadas em MICRO-UNIDADES de 1/8 de bloco (int) pra encaixar 1, 1/2, 1/4, 1/8.
## _bake() funde tudo numa ArrayMesh única (vertex color) + uma colisão só — o jogo
## trata como um objeto estático, sem editar. "Pintar" grava a cor no vértice do bake,
## então o resultado ja sai com a textura embutida no proprio mesh.

const MICRO: float = 0.125          # 1/8 de bloco
const FORMAT: String = "trumancraft_scenery"
const VERSION: int = 1
const MAX_CUBOS: int = 40000

# cada cubo: {"p": Vector3i (micro), "u": int (lado em micro-unidades), "c": Color}
var cubos: Array = []


func adicionar(micro_pos: Vector3i, lado_micro: int, cor: Color) -> bool:
	if cubos.size() >= MAX_CUBOS:
		return false
	remover_em(micro_pos, lado_micro)  # substitui o que ocupa a mesma celula/escala
	cubos.append({"p": micro_pos, "u": lado_micro, "c": cor})
	return true


func remover_em(micro_pos: Vector3i, lado_micro: int) -> bool:
	# remove o cubo cuja AABB contem o centro da celula alvo
	var centro: Vector3 = Vector3(micro_pos) + Vector3(lado_micro, lado_micro, lado_micro) * 0.5
	for i in range(cubos.size() - 1, -1, -1):
		var c: Dictionary = cubos[i]
		var p: Vector3i = c["p"]
		var u: int = c["u"]
		if centro.x >= p.x and centro.x <= p.x + u and centro.y >= p.y and centro.y <= p.y + u and centro.z >= p.z and centro.z <= p.z + u:
			cubos.remove_at(i)
			return true
	return false


func raycast(origem: Vector3, direcao: Vector3, alcance: float) -> Dictionary:
	# raycast analitico contra as AABBs dos cubos (escala de editor aguenta).
	# Retorna {"hit": bool, "cubo": Dictionary, "normal": Vector3i, "t": float}
	var melhor_t: float = alcance
	var achou: Dictionary = {"hit": false}
	var inv: Vector3 = Vector3(
		1.0 / direcao.x if absf(direcao.x) > 1e-6 else 1e30,
		1.0 / direcao.y if absf(direcao.y) > 1e-6 else 1e30,
		1.0 / direcao.z if absf(direcao.z) > 1e-6 else 1e30
	)
	for c in cubos:
		var mn: Vector3 = Vector3(c["p"]) * MICRO
		var mx: Vector3 = (Vector3(c["p"]) + Vector3(c["u"], c["u"], c["u"])) * MICRO
		var t1: Vector3 = (mn - origem) * inv
		var t2: Vector3 = (mx - origem) * inv
		var tmin: float = maxf(maxf(minf(t1.x, t2.x), minf(t1.y, t2.y)), minf(t1.z, t2.z))
		var tmax: float = minf(minf(maxf(t1.x, t2.x), maxf(t1.y, t2.y)), maxf(t1.z, t2.z))
		if tmax >= maxf(tmin, 0.0) and tmin < melhor_t:
			melhor_t = tmin
			var ponto: Vector3 = origem + direcao * tmin
			var centro: Vector3 = (mn + mx) * 0.5
			var d: Vector3 = ponto - centro
			var ad: Vector3 = d.abs()
			var normal: Vector3i
			if ad.x >= ad.y and ad.x >= ad.z:
				normal = Vector3i(sign(d.x), 0, 0)
			elif ad.y >= ad.z:
				normal = Vector3i(0, sign(d.y), 0)
			else:
				normal = Vector3i(0, 0, sign(d.z))
			achou = {"hit": true, "cubo": c, "normal": normal, "t": tmin}
	return achou


func bake_mesh() -> ArrayMesh:
	# funde todos os cubos numa ArrayMesh unica com vertex color (uma superficie so)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in cubos:
		_emite_cubo(st, c["p"], c["u"], c["c"])
	st.generate_normals()
	return st.commit()


func bake_collision() -> ConcavePolygonShape3D:
	var faces: PackedVector3Array = PackedVector3Array()
	for c in cubos:
		_emite_cubo_colisao(faces, c["p"], c["u"])
	var forma: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	forma.set_faces(faces)
	return forma


func bake_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	return mat


const _CUBE_FACES := [
	# [normal, 4 cantos em ordem CCW] (unidade = 1 micro)
	[Vector3(0, 0, 1), [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)]],
	[Vector3(0, 0, -1), [Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)]],
	[Vector3(1, 0, 0), [Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1)]],
	[Vector3(-1, 0, 0), [Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)]],
	[Vector3(0, 1, 0), [Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)]],
	[Vector3(0, -1, 0), [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]],
]


func _emite_cubo(st: SurfaceTool, p: Vector3i, u: int, cor: Color) -> void:
	var base: Vector3 = Vector3(p) * MICRO
	var s: float = float(u) * MICRO
	for face in _CUBE_FACES:
		var cantos: Array = face[1]
		var v0: Vector3 = base + cantos[0] * s
		var v1: Vector3 = base + cantos[1] * s
		var v2: Vector3 = base + cantos[2] * s
		var v3: Vector3 = base + cantos[3] * s
		st.set_color(cor)
		st.add_vertex(v0); st.set_color(cor); st.add_vertex(v1); st.set_color(cor); st.add_vertex(v2)
		st.set_color(cor); st.add_vertex(v0); st.set_color(cor); st.add_vertex(v2); st.set_color(cor); st.add_vertex(v3)


func _emite_cubo_colisao(faces: PackedVector3Array, p: Vector3i, u: int) -> void:
	var base: Vector3 = Vector3(p) * MICRO
	var s: float = float(u) * MICRO
	for face in _CUBE_FACES:
		var cantos: Array = face[1]
		var v0: Vector3 = base + cantos[0] * s
		var v1: Vector3 = base + cantos[1] * s
		var v2: Vector3 = base + cantos[2] * s
		var v3: Vector3 = base + cantos[3] * s
		faces.append(v0); faces.append(v1); faces.append(v2)
		faces.append(v0); faces.append(v2); faces.append(v3)


func to_dictionary() -> Dictionary:
	var lista: Array = []
	for c in cubos:
		var p: Vector3i = c["p"]
		var cor: Color = c["c"]
		lista.append([p.x, p.y, p.z, c["u"], cor.to_html(false)])
	return {"format": FORMAT, "version": VERSION, "cubos": lista}


func save_to_file(caminho: String) -> bool:
	var arquivo: FileAccess = FileAccess.open(caminho, FileAccess.WRITE)
	if arquivo == null:
		return false
	arquivo.store_string(JSON.stringify(to_dictionary(), "\t"))
	return true


static func load_from_file(caminho: String) -> SceneryData:
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
	var cenario = (load("res://src/scenery_data.gd") as GDScript).new()
	for entrada in dados.get("cubos", []):
		if entrada is Array and entrada.size() >= 5:
			cenario.cubos.append({
				"p": Vector3i(int(entrada[0]), int(entrada[1]), int(entrada[2])),
				"u": int(entrada[3]),
				"c": Color.html(str(entrada[4]))
			})
	return cenario
