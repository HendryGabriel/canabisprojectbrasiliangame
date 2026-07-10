## Interactive top-down authoring canvas for a 100x100 TerrainTileData asset.
class_name TerrainMap2D
extends Control


const TerrainTileScript = preload("res://src/terrain_tile_data.gd")

signal cell_input(cell: Vector2i, phase: int)
signal node_clicked(network_index: int, node_id: String)

var tile
var view_mode: String = "height"
var slice_y: int = 0
var selected_network: int = 0
var selected_node_id: String = ""
var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO
var _panning: bool = false
var _last_mouse: Vector2 = Vector2.ZERO
var _painting: bool = false
var _last_cell: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	queue_redraw()


func set_tile(value) -> void:
	tile = value
	selected_node_id = ""
	queue_redraw()


func set_view_mode(value: String) -> void:
	view_mode = value
	queue_redraw()


func set_slice_y(value: int) -> void:
	slice_y = value
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.018, 0.022, 0.028, 0.98))
	if tile == null:
		return
	var scale: float = _cell_scale()
	var origin: Vector2 = _map_origin(scale)
	for z in range(TerrainTileScript.TILE_SIZE):
		for x in range(TerrainTileScript.TILE_SIZE):
			var index: int = tile.index_of(x, z)
			var rect: Rect2 = Rect2(origin + Vector2(x, z) * scale, Vector2(scale + 0.35, scale + 0.35))
			if rect.end.x < 0 or rect.end.y < 0 or rect.position.x > size.x or rect.position.y > size.y:
				continue
			draw_rect(rect, _cell_color(index))
	_draw_networks(origin, scale)
	if scale >= 8.0:
		for line in range(0, TerrainTileScript.TILE_SIZE + 1, 10):
			var color: Color = Color(1, 1, 1, 0.12)
			draw_line(origin + Vector2(line, 0) * scale, origin + Vector2(line, 100) * scale, color, 1.0)
			draw_line(origin + Vector2(0, line) * scale, origin + Vector2(100, line) * scale, color, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(12, 22), "%s | Y=%d | zoom %.1fx" % [view_mode.capitalize(), slice_y, zoom], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.92, 0.95, 1.0))


func _cell_color(index: int) -> Color:
	match view_mode:
		"profile":
			return [Color("5fae4f"), Color("76797e"), Color("79512f"), Color("a7bd4c")][clampi(int(tile.surface_profiles[index]), 0, 3)]
		"cave_density":
			var density: float = float(tile.cave_density[index]) / 255.0
			return Color(0.08 + density * 0.58, 0.08, 0.16 + density * 0.76)
		"zones":
			var flags: int = int(tile.zone_flags[index])
			if (flags & TerrainTileScript.ZONE_PROTECTED) != 0: return Color("c53e45")
			if (flags & TerrainTileScript.ZONE_FOREST) != 0: return Color("247a37")
			if (flags & TerrainTileScript.ZONE_STRUCTURES) != 0: return Color("2d659e")
			return Color("34383d")
		"networks", "slice":
			var height_value: float = inverse_lerp(TerrainTileScript.MIN_SURFACE_Y, TerrainTileScript.MAX_SURFACE_Y, int(tile.heights[index]))
			return Color(0.075, 0.09 + height_value * 0.08, 0.095, 1.0)
		_:
			var normalized: float = inverse_lerp(TerrainTileScript.MIN_SURFACE_Y, TerrainTileScript.MAX_SURFACE_Y, int(tile.heights[index]))
			return Color(0.12, 0.26, 0.10).lerp(Color(0.82, 0.78, 0.56), normalized)


func _draw_networks(origin: Vector2, scale: float) -> void:
	if view_mode not in ["networks", "slice"]:
		return
	for network_index in range(tile.cave_networks.size()):
		var network: Dictionary = tile.cave_networks[network_index] as Dictionary
		var nodes: Dictionary = {}
		for raw_node in network.get("nodes", []) as Array:
			if typeof(raw_node) == TYPE_DICTIONARY:
				var node: Dictionary = raw_node as Dictionary
				nodes[str(node.get("id", ""))] = node
		for raw_edge in network.get("edges", []) as Array:
			var endpoints: PackedStringArray = TerrainTileScript._edge_endpoints(raw_edge)
			if endpoints.size() != 2 or not nodes.has(endpoints[0]) or not nodes.has(endpoints[1]): continue
			var a: Dictionary = nodes[endpoints[0]] as Dictionary
			var b: Dictionary = nodes[endpoints[1]] as Dictionary
			var pa: Vector3i = TerrainTileScript._vector3i_from_value(a.get("pos", []))
			var pb: Vector3i = TerrainTileScript._vector3i_from_value(b.get("pos", []))
			var radius: float = (float(a.get("radius", 3)) + float(b.get("radius", 3))) * 0.5
			if view_mode == "slice" and not _edge_intersects_slice(pa, pb, radius): continue
			var average_y: float = (float(pa.y) + float(pb.y)) * 0.5
			var color: Color = _depth_color(average_y)
			if network_index != selected_network: color.a *= 0.5
			draw_line(origin + Vector2(pa.x + 0.5, pa.z + 0.5) * scale, origin + Vector2(pb.x + 0.5, pb.z + 0.5) * scale, color, maxf(2.0, radius * scale * 0.35), true)
		for raw_node in nodes.values():
			var node: Dictionary = raw_node as Dictionary
			var pos: Vector3i = TerrainTileScript._vector3i_from_value(node.get("pos", []))
			var radius: float = float(node.get("radius", 3))
			if view_mode == "slice" and abs(pos.y - slice_y) > radius: continue
			var node_id: String = str(node.get("id", ""))
			var color: Color = Color("ff9638") if str(node.get("type", "route")) == "entrance" else (Color("b96bf0") if str(node.get("type", "route")) == "chamber" else _depth_color(pos.y))
			var center: Vector2 = origin + Vector2(pos.x + 0.5, pos.z + 0.5) * scale
			draw_circle(center, maxf(4.0, radius * scale * 0.30), color)
			if network_index == selected_network and node_id == selected_node_id:
				draw_arc(center, maxf(7.0, radius * scale * 0.34), 0, TAU, 32, Color.YELLOW, 2.5)
			if scale >= 9.0:
				draw_string(ThemeDB.fallback_font, center + Vector2(6, -6), "%s (%d)" % [node_id, pos.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


func _edge_intersects_slice(a: Vector3i, b: Vector3i, radius: float) -> bool:
	return slice_y >= mini(a.y, b.y) - radius and slice_y <= maxi(a.y, b.y) + radius


func _depth_color(y: float) -> Color:
	var depth: float = clampf(inverse_lerp(16.0, -64.0, y), 0.0, 1.0)
	return Color("45d9ff").lerp(Color("ff4d7d"), depth)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			zoom = minf(8.0, zoom * 1.2); queue_redraw(); accept_event(); return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			zoom = maxf(1.0, zoom / 1.2); pan = Vector2.ZERO if zoom <= 1.01 else pan; queue_redraw(); accept_event(); return
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mouse_event.pressed; _last_mouse = mouse_event.position; accept_event(); return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var cell: Vector2i = _cell_at(mouse_event.position)
			if mouse_event.pressed:
				var hit_node: Dictionary = _node_at(mouse_event.position)
				if not hit_node.is_empty() and view_mode in ["networks", "slice"]:
					node_clicked.emit(int(hit_node["network"]), str(hit_node["id"]))
				else:
					_painting = true; _last_cell = cell; cell_input.emit(cell, 0)
			else:
				if _painting: cell_input.emit(cell, 2)
				_painting = false
			accept_event()
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if _panning:
			pan += motion.position - _last_mouse; _last_mouse = motion.position; queue_redraw(); accept_event()
		elif _painting:
			var cell: Vector2i = _cell_at(motion.position)
			if cell != _last_cell:
				_last_cell = cell; cell_input.emit(cell, 1)
			accept_event()


func _node_at(mouse_position: Vector2) -> Dictionary:
	if tile == null: return {}
	var scale: float = _cell_scale()
	var origin: Vector2 = _map_origin(scale)
	var best_distance: float = 12.0
	var result: Dictionary = {}
	for network_index in range(tile.cave_networks.size()):
		var network: Dictionary = tile.cave_networks[network_index] as Dictionary
		for raw_node in network.get("nodes", []) as Array:
			var node: Dictionary = raw_node as Dictionary
			var pos: Vector3i = TerrainTileScript._vector3i_from_value(node.get("pos", []))
			var distance: float = mouse_position.distance_to(origin + Vector2(pos.x + 0.5, pos.z + 0.5) * scale)
			if distance < best_distance:
				best_distance = distance; result = {"network": network_index, "id": str(node.get("id", ""))}
	return result


func _cell_at(mouse_position: Vector2) -> Vector2i:
	var scale: float = _cell_scale()
	var local: Vector2 = (mouse_position - _map_origin(scale)) / scale
	return Vector2i(clampi(floori(local.x), 0, 99), clampi(floori(local.y), 0, 99))


func _cell_scale() -> float:
	return maxf(1.0, minf(size.x, size.y) / 100.0) * zoom


func _map_origin(scale: float) -> Vector2:
	return (size - Vector2(100, 100) * scale) * 0.5 + pan
