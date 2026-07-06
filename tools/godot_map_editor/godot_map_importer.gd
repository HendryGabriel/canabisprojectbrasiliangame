@tool
extends Node

@export_file("*.json") var map_json_path := ""
@export var target_parent_path: NodePath
@export var clear_previous := true
@export var rebuild_in_editor := false:
	set(value):
		if value:
			import_map()
	get:
		return false

func import_map() -> Node2D:
	if map_json_path.is_empty():
		push_error("Defina map_json_path com o JSON exportado pelo Godot Map Editor.")
		return null

	var text := FileAccess.get_file_as_string(map_json_path)
	if text.is_empty():
		push_error("Nao foi possivel ler o mapa: " + map_json_path)
		return null

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JSON de mapa invalido.")
		return null

	var parent := get_node_or_null(target_parent_path)
	if parent == null:
		parent = self

	if clear_previous:
		for child in parent.get_children():
			if child.is_in_group("imported_map_editor_map"):
				child.queue_free()

	var root := _build_map(parsed)
	parent.add_child(root)
	if Engine.is_editor_hint():
		root.owner = get_tree().edited_scene_root
		_set_owner_recursive(root, root.owner)
	return root

func _build_map(data: Dictionary) -> Node2D:
	var map_info: Dictionary = data.get("map", {})
	var root := Node2D.new()
	root.name = str(map_info.get("name", "ImportedMap"))
	root.add_to_group("imported_map_editor_map")

	var textures := {}
	for atlas in data.get("atlases", []):
		var atlas_id := str(atlas.get("id", ""))
		var image_path := str(atlas.get("image", ""))
		if atlas_id.is_empty() or image_path.is_empty():
			continue
		var texture := load(image_path)
		if texture == null:
			push_warning("Atlas nao encontrado: " + image_path)
			continue
		textures[atlas_id] = texture

	var sprites := {}
	for sprite in data.get("sprites", []):
		sprites[str(sprite.get("id", ""))] = sprite

	var tile_size := int(map_info.get("tile_size", 16))
	for layer_data in data.get("layers", []):
		if not bool(layer_data.get("visible", true)):
			continue
		var layer := Node2D.new()
		layer.name = str(layer_data.get("name", "Layer"))
		layer.z_index = int(layer_data.get("z_index", 0))
		root.add_child(layer)

		var layer_type := str(layer_data.get("type", "tile"))
		for cell in layer_data.get("cells", []):
			var asset_id := str(cell.get("assetId", cell.get("asset_id", "")))
			if not sprites.has(asset_id):
				continue
			var sprite_data: Dictionary = sprites[asset_id]
			var atlas_id := str(sprite_data.get("atlas_id", ""))
			if not textures.has(atlas_id):
				continue
			var node := _create_sprite_node(textures[atlas_id], sprite_data, cell, layer_type, tile_size)
			layer.add_child(node)
	return root

func _create_sprite_node(atlas: Texture2D, sprite_data: Dictionary, cell: Dictionary, layer_type: String, tile_size: int) -> Sprite2D:
	var region: Array = sprite_data.get("region", [0, 0, tile_size, tile_size])
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = atlas
	atlas_texture.region = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))

	var sprite := Sprite2D.new()
	sprite.name = str(sprite_data.get("name", "Sprite"))
	sprite.texture = atlas_texture
	sprite.centered = false
	sprite.z_index = int(sprite_data.get("z", 0))

	var x := int(cell.get("x", 0))
	var y := int(cell.get("y", 0))
	var pos := Vector2(x * tile_size, y * tile_size)
	var kind := str(sprite_data.get("kind", layer_type))
	if kind == "decor" or layer_type == "decor":
		var pivot: Array = sprite_data.get("pivot", [tile_size / 2.0, tile_size])
		pos += Vector2(tile_size / 2.0 - float(pivot[0]), tile_size - float(pivot[1]))
	sprite.position = pos

	var collision: Dictionary = sprite_data.get("collision", {})
	if bool(collision.get("enabled", false)):
		var rect: Array = collision.get("rect", [0, 0, float(region[2]), float(region[3])])
		var body := StaticBody2D.new()
		body.name = "Collision"
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(float(rect[2]), float(rect[3]))
		shape.shape = rectangle
		shape.position = Vector2(float(rect[0]) + float(rect[2]) / 2.0, float(rect[1]) + float(rect[3]) / 2.0)
		body.add_child(shape)
		sprite.add_child(body)
	return sprite

func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_set_owner_recursive(child, owner_node)
