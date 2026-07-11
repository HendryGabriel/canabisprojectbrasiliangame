extends AuthoringSceneBase
## Editor de Mapa (dev): constroi cenario estatico em varias escalas (1, 1/2, 1/4, 1/8),
## pinta com color picker, e faz bake pra uma mesh unica fundida que o jogo carrega
## como cenario solido nao-editavel.

const SceneryDataScript = preload("res://src/scenery_data.gd")
const MICRO := SceneryDataScript.MICRO
const ESCALAS := [8, 4, 2, 1]           # lado em micro-unidades: 1x, 1/2, 1/4, 1/8
const NOMES_ESCALA := ["1x (bloco)", "1/2", "1/4", "1/8 (detalhe)"]
const DIR_CENARIOS := "res://data/scenery/"

var cenario: SceneryData
var escala_idx: int = 0
var cor_atual: Color = Color(0.7, 0.7, 0.72)
var preview: MeshInstance3D
var bake_node: MeshInstance3D
var bake_body: StaticBody3D
var color_button: ColorPickerButton
var escala_option: OptionButton
var nome_edit: LineEdit
var salvar_dialog: FileDialog
var abrir_dialog: FileDialog


func _ready() -> void:
	cenario = SceneryDataScript.new()
	# mundo voxel minimo so pra ter o AuthoringSceneBase feliz (chao de referencia)
	var VoxelWorldScript = load("res://src/voxel_world.gd")
	var mundo = VoxelWorldScript.new(BlockCatalogScript.blocks())
	mundo.reset(1)
	for x in range(0, 40):
		for z in range(0, 40):
			mundo.set_base_block(Vector3i(x, 0, z), "grass")
	setup_authoring_world(mundo, Vector3(20, 12, 34))
	pitch = -0.5
	_apply_camera_rotation()
	_montar_ui()
	_criar_preview()
	_atualizar_bake()
	DirAccess.make_dir_recursive_absolute(DIR_CENARIOS)


func _montar_ui() -> void:
	var root: VBoxContainer = make_side_panel("Editor de Mapa", 340.0)

	root.add_child(_rotulo("Escala do bloco:"))
	escala_option = OptionButton.new()
	for i in range(ESCALAS.size()):
		escala_option.add_item(NOMES_ESCALA[i], i)
	escala_option.select(0)
	escala_option.item_selected.connect(func(i: int) -> void: escala_idx = i)
	root.add_child(escala_option)

	root.add_child(_rotulo("Cor (pincel) — pinta e vira textura no bake:"))
	color_button = ColorPickerButton.new()
	color_button.color = cor_atual
	color_button.custom_minimum_size = Vector2(0, 34)
	color_button.color_changed.connect(func(c: Color) -> void: cor_atual = c)
	root.add_child(color_button)

	root.add_child(_rotulo("Clique esq: coloca - Clique dir: remove\n(segure botao direito do mouse pra girar a camera)\nWASD move, E sobe, Q desce, Shift acelera."))

	root.add_child(HSeparator.new())
	root.add_child(_rotulo("Nome do cenario:"))
	nome_edit = LineEdit.new()
	nome_edit.text = "cidade"
	root.add_child(nome_edit)
	root.add_child(make_button("Salvar cenario", _salvar))
	root.add_child(make_button("Abrir cenario", _abrir))
	root.add_child(make_button("Limpar tudo", _limpar))
	root.add_child(HSeparator.new())
	root.add_child(make_button("Voltar ao menu", return_to_main_menu))

	_criar_dialogos()
	set_status("Cenario vazio. Construa e salve em data/scenery/ pra o jogo carregar.")


func _rotulo(texto: String) -> Label:
	var l: Label = Label.new()
	l.text = texto
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _criar_dialogos() -> void:
	salvar_dialog = FileDialog.new()
	salvar_dialog.access = FileDialog.ACCESS_RESOURCES
	salvar_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	salvar_dialog.current_dir = DIR_CENARIOS
	salvar_dialog.filters = PackedStringArray(["*.json ; Cenario"])
	salvar_dialog.file_selected.connect(func(p: String) -> void:
		if cenario.save_to_file(p):
			set_status("Salvo: %s (%d cubos). O jogo carrega ao entrar." % [p, cenario.cubos.size()])
		else:
			set_status("Falha ao salvar."))
	ui_layer.add_child(salvar_dialog)

	abrir_dialog = FileDialog.new()
	abrir_dialog.access = FileDialog.ACCESS_RESOURCES
	abrir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	abrir_dialog.current_dir = DIR_CENARIOS
	abrir_dialog.filters = PackedStringArray(["*.json ; Cenario"])
	abrir_dialog.file_selected.connect(func(p: String) -> void:
		var carregado = SceneryDataScript.load_from_file(p)
		if carregado != null:
			cenario = carregado
			_atualizar_bake()
			set_status("Aberto: %s (%d cubos)." % [p, cenario.cubos.size()])
		else:
			set_status("Falha ao abrir."))
	ui_layer.add_child(abrir_dialog)


func _salvar() -> void:
	salvar_dialog.current_file = "%s.json" % nome_edit.text.strip_edges()
	salvar_dialog.popup_centered(Vector2i(720, 500))


func _abrir() -> void:
	abrir_dialog.popup_centered(Vector2i(720, 500))


func _limpar() -> void:
	cenario = SceneryDataScript.new()
	_atualizar_bake()
	set_status("Cenario limpo.")


func _criar_preview() -> void:
	preview = MeshInstance3D.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.35)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview.material_override = mat
	add_child(preview)


func _atualizar_bake() -> void:
	# refunde a mesh estatica inteira (o "bake": vira uma coisa so)
	if bake_node != null and is_instance_valid(bake_node):
		bake_node.queue_free()
	if bake_body != null and is_instance_valid(bake_body):
		bake_body.queue_free()
	bake_node = MeshInstance3D.new()
	bake_node.mesh = cenario.bake_mesh()
	bake_node.material_override = cenario.bake_material()
	add_child(bake_node)
	bake_body = StaticBody3D.new()
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = cenario.bake_collision()
	bake_body.add_child(col)
	add_child(bake_body)


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if event is InputEventMouseButton and event.pressed and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_colocar()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			escala_idx = maxi(0, escala_idx - 1)
			escala_option.select(escala_idx)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			escala_idx = mini(ESCALAS.size() - 1, escala_idx + 1)
			escala_option.select(escala_idx)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_DELETE:
		_remover()


func _celula_alvo() -> Dictionary:
	# retorna {"pos": Vector3i micro (canto), "hit": bool, "remove_pos": Vector3i}
	var origem: Vector3 = camera_ray_origin()
	var dir: Vector3 = camera_ray_direction()
	var lado: int = ESCALAS[escala_idx]
	var hit: Dictionary = cenario.raycast(origem, dir, 60.0)
	if bool(hit.get("hit", false)):
		var cubo: Dictionary = hit["cubo"]
		var normal: Vector3i = hit["normal"]
		var ponto: Vector3 = origem + dir * float(hit["t"]) + Vector3(normal) * (MICRO * 0.5)
		var micro: Vector3i = Vector3i((ponto / MICRO).floor())
		return {"hit": true, "pos": _snap(micro, lado), "remove_pos": cubo["p"], "remove_u": cubo["u"]}
	# chao: intersecta plano y=0
	if absf(dir.y) > 1e-5:
		var t: float = -origem.y / dir.y
		if t > 0.0 and t < 60.0:
			var ponto: Vector3 = origem + dir * t
			var micro: Vector3i = Vector3i((ponto / MICRO).floor())
			micro.y = 0
			return {"hit": true, "pos": _snap(micro, lado)}
	return {"hit": false}


func _snap(micro: Vector3i, lado: int) -> Vector3i:
	return Vector3i(
		int(floor(float(micro.x) / lado)) * lado,
		int(floor(float(micro.y) / lado)) * lado,
		int(floor(float(micro.z) / lado)) * lado
	)


func _colocar() -> void:
	var alvo: Dictionary = _celula_alvo()
	if not bool(alvo.get("hit", false)):
		return
	if cenario.adicionar(alvo["pos"], ESCALAS[escala_idx], cor_atual):
		_atualizar_bake()
	else:
		set_status("Limite de %d cubos atingido." % SceneryDataScript.MAX_CUBOS)


func _remover() -> void:
	var alvo: Dictionary = _celula_alvo()
	if alvo.has("remove_pos"):
		cenario.remover_em(alvo["remove_pos"], alvo["remove_u"])
		_atualizar_bake()


func _process(delta: float) -> void:
	super._process(delta)
	if preview == null:
		return
	var alvo: Dictionary = _celula_alvo()
	if not bool(alvo.get("hit", false)):
		preview.visible = false
		return
	preview.visible = true
	var lado: int = ESCALAS[escala_idx]
	if preview.mesh == null or int(preview.get_meta("lado", -1)) != lado:
		var bm: BoxMesh = BoxMesh.new()
		bm.size = Vector3.ONE * (lado * MICRO)
		preview.mesh = bm
		preview.set_meta("lado", lado)
	var pos: Vector3i = alvo["pos"]
	preview.position = Vector3(pos) * MICRO + Vector3.ONE * (lado * MICRO * 0.5)
	(preview.material_override as StandardMaterial3D).albedo_color = Color(cor_atual.r, cor_atual.g, cor_atual.b, 0.4)
