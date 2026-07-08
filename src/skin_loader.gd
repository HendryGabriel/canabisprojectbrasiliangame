extends RefCounted
class_name SkinLoader

const DEFAULT_SKIN_SIZE: Vector2i = Vector2i(64, 64)
const LEGACY_SKIN_SIZE: Vector2i = Vector2i(64, 32)
const PLAYER_SKIN_PATH: String = "user://player_skin.png"

static func load_skin(path: String) -> Texture2D:
	var image: Image = Image.new()
	if path == "" or image.load(path) != OK:
		return default_skin_texture()
	if not is_valid_skin_image(image):
		return default_skin_texture()
	return ImageTexture.create_from_image(_normalize_skin_image(image))

static func import_skin(source_path: String) -> Dictionary:
	var image: Image = Image.new()
	if source_path == "" or source_path.get_extension().to_lower() != "png":
		return {"ok": false, "message": "Escolha um arquivo PNG de skin do Minecraft."}
	if image.load(source_path) != OK:
		return {"ok": false, "message": "Nao foi possivel ler a skin."}
	if not is_valid_skin_image(image):
		return {"ok": false, "message": "A skin precisa ter 64x64 ou 64x32 pixels."}

	var normalized: Image = _normalize_skin_image(image)
	var save_error: int = normalized.save_png(PLAYER_SKIN_PATH)
	if save_error != OK:
		return {"ok": false, "message": "Nao foi possivel salvar a skin importada."}
	return {"ok": true, "message": "Skin importada.", "path": PLAYER_SKIN_PATH}

static func is_valid_skin_path(path: String) -> bool:
	var image: Image = Image.new()
	return path != "" and image.load(path) == OK and is_valid_skin_image(image)

static func is_valid_skin_image(image: Image) -> bool:
	var size: Vector2i = image.get_size()
	return size == DEFAULT_SKIN_SIZE or size == LEGACY_SKIN_SIZE

static func default_skin_texture() -> Texture2D:
	return ImageTexture.create_from_image(default_skin_image())

static func default_skin_image() -> Image:
	var image: Image = Image.create(DEFAULT_SKIN_SIZE.x, DEFAULT_SKIN_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	_fill_rect(image, Rect2i(8, 8, 8, 8), Color(0.72, 0.52, 0.38, 1.0))
	_fill_rect(image, Rect2i(20, 20, 8, 12), Color(0.12, 0.42, 0.66, 1.0))
	_fill_rect(image, Rect2i(44, 20, 4, 12), Color(0.72, 0.52, 0.38, 1.0))
	_fill_rect(image, Rect2i(36, 52, 4, 12), Color(0.72, 0.52, 0.38, 1.0))
	_fill_rect(image, Rect2i(4, 20, 4, 12), Color(0.24, 0.24, 0.70, 1.0))
	_fill_rect(image, Rect2i(20, 52, 4, 12), Color(0.24, 0.24, 0.70, 1.0))

	_fill_rect(image, Rect2i(8, 0, 8, 8), Color(0.20, 0.12, 0.06, 1.0))
	_fill_rect(image, Rect2i(0, 8, 8, 8), Color(0.20, 0.12, 0.06, 1.0))
	_fill_rect(image, Rect2i(16, 8, 8, 8), Color(0.20, 0.12, 0.06, 1.0))
	_fill_rect(image, Rect2i(8, 16, 8, 4), Color(0.72, 0.52, 0.38, 1.0))

	return image

static func skin_material(texture: Texture2D, _uv_rects: Dictionary) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = texture if texture != null else default_skin_texture()
	mat.albedo_color = Color.WHITE
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

static func make_skin_box_mesh(size: Vector3, uv_rects: Dictionary, texture_size: Vector2 = Vector2(64, 64)) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	_add_face(mesh, _face_vertices(size, "north"), Vector3(0, 0, -1), _uvs(uv_rects.get("north", Rect2(8, 8, 8, 8)), texture_size))
	_add_face(mesh, _face_vertices(size, "south"), Vector3(0, 0, 1), _uvs(uv_rects.get("south", Rect2(24, 8, 8, 8)), texture_size))
	_add_face(mesh, _face_vertices(size, "east"), Vector3(1, 0, 0), _uvs(uv_rects.get("east", Rect2(16, 8, 8, 8)), texture_size))
	_add_face(mesh, _face_vertices(size, "west"), Vector3(-1, 0, 0), _uvs(uv_rects.get("west", Rect2(0, 8, 8, 8)), texture_size))
	_add_face(mesh, _face_vertices(size, "top"), Vector3(0, 1, 0), _uvs(uv_rects.get("top", Rect2(8, 0, 8, 8)), texture_size))
	_add_face(mesh, _face_vertices(size, "bottom"), Vector3(0, -1, 0), _uvs(uv_rects.get("bottom", Rect2(16, 0, 8, 8)), texture_size))
	return mesh

static func head_uvs() -> Dictionary:
	return {
		"west": Rect2(0, 8, 8, 8),
		"north": Rect2(8, 8, 8, 8),
		"east": Rect2(16, 8, 8, 8),
		"south": Rect2(24, 8, 8, 8),
		"top": Rect2(8, 0, 8, 8),
		"bottom": Rect2(16, 0, 8, 8)
	}

static func hat_uvs() -> Dictionary:
	return {
		"west": Rect2(32, 8, 8, 8),
		"north": Rect2(40, 8, 8, 8),
		"east": Rect2(48, 8, 8, 8),
		"south": Rect2(56, 8, 8, 8),
		"top": Rect2(40, 0, 8, 8),
		"bottom": Rect2(48, 0, 8, 8)
	}

static func body_uvs() -> Dictionary:
	return {
		"west": Rect2(16, 20, 4, 12),
		"north": Rect2(20, 20, 8, 12),
		"east": Rect2(28, 20, 4, 12),
		"south": Rect2(32, 20, 8, 12),
		"top": Rect2(20, 16, 8, 4),
		"bottom": Rect2(28, 16, 8, 4)
	}

static func right_arm_uvs() -> Dictionary:
	return _limb_uvs(40, 16)

static func left_arm_uvs() -> Dictionary:
	return _limb_uvs(32, 48)

static func right_leg_uvs() -> Dictionary:
	return _limb_uvs(0, 16)

static func left_leg_uvs() -> Dictionary:
	return _limb_uvs(16, 48)

static func _limb_uvs(x: int, y: int) -> Dictionary:
	return {
		"west": Rect2(x, y + 4, 4, 12),
		"north": Rect2(x + 4, y + 4, 4, 12),
		"east": Rect2(x + 8, y + 4, 4, 12),
		"south": Rect2(x + 12, y + 4, 4, 12),
		"top": Rect2(x + 4, y, 4, 4),
		"bottom": Rect2(x + 8, y, 4, 4)
	}

static func _normalize_skin_image(source: Image) -> Image:
	var image: Image = source.duplicate()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	if image.get_size() == LEGACY_SKIN_SIZE:
		var expanded: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		expanded.fill(Color(0, 0, 0, 0))
		expanded.blit_rect(image, Rect2i(Vector2i.ZERO, LEGACY_SKIN_SIZE), Vector2i.ZERO)
		expanded.blit_rect(image, Rect2i(40, 16, 16, 16), Vector2i(32, 48))
		expanded.blit_rect(image, Rect2i(0, 16, 16, 16), Vector2i(16, 48))
		image = expanded
	return image

static func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			image.set_pixel(x, y, color)

static func _add_face(mesh: ArrayMesh, vertices: PackedVector3Array, normal: Vector3, uvs: PackedVector2Array) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([normal, normal, normal, normal])
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

static func _uvs(rect: Rect2, texture_size: Vector2) -> PackedVector2Array:
	var left: float = rect.position.x / texture_size.x
	var top: float = rect.position.y / texture_size.y
	var right: float = (rect.position.x + rect.size.x) / texture_size.x
	var bottom: float = (rect.position.y + rect.size.y) / texture_size.y
	return PackedVector2Array([
		Vector2(left, bottom),
		Vector2(right, bottom),
		Vector2(right, top),
		Vector2(left, top)
	])

static func _face_vertices(size: Vector3, face_name: String) -> PackedVector3Array:
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	var hz: float = size.z * 0.5
	match face_name:
		"north":
			return PackedVector3Array([Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, hy, -hz), Vector3(-hx, hy, -hz)])
		"south":
			return PackedVector3Array([Vector3(hx, -hy, hz), Vector3(-hx, -hy, hz), Vector3(-hx, hy, hz), Vector3(hx, hy, hz)])
		"east":
			return PackedVector3Array([Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz), Vector3(hx, hy, hz), Vector3(hx, hy, -hz)])
		"west":
			return PackedVector3Array([Vector3(-hx, -hy, hz), Vector3(-hx, -hy, -hz), Vector3(-hx, hy, -hz), Vector3(-hx, hy, hz)])
		"top":
			return PackedVector3Array([Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz)])
	return PackedVector3Array([Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(hx, -hy, -hz), Vector3(-hx, -hy, -hz)])
