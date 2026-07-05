extends TileMapLayer

const ANIMATION_INTERVAL := 0.28
const WATER_TERRAIN_SET := 0

const PEERING_BITS: Array = [
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
	TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
	TileSet.CELL_NEIGHBOR_LEFT_SIDE,
	TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
	TileSet.CELL_NEIGHBOR_TOP_SIDE,
	TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
]

var _time := 0.0
var _frame := 0
var _groups := {}
var _animated_cells := {}


func _ready() -> void:
	call_deferred("refresh_animation_cells")


func refresh_animation_cells() -> void:
	_groups = _build_compatible_tile_groups()
	_animated_cells.clear()
	for cell in get_used_cells():
		var source_id: int = get_cell_source_id(cell)
		var atlas: Vector2i = get_cell_atlas_coords(cell)
		var alternative: int = get_cell_alternative_tile(cell)
		var key: String = _tile_key(source_id, atlas, alternative)
		var variants: Array = _groups.get(key, [])
		if variants.size() > 1:
			_animated_cells[cell] = variants


func _process(delta: float) -> void:
	if _animated_cells.is_empty():
		return
	_time += delta
	if _time < ANIMATION_INTERVAL:
		return
	_time = 0.0
	_frame += 1
	for cell in _animated_cells:
		var variants: Array = _animated_cells[cell]
		var variant: Dictionary = variants[(_frame + _cell_offset(cell)) % variants.size()]
		set_cell(cell, variant["source_id"], variant["atlas"], variant["alternative"])


func _build_compatible_tile_groups() -> Dictionary:
	var groups := {}
	if tile_set == null:
		return groups
	for source_index in tile_set.get_source_count():
		var source_id: int = tile_set.get_source_id(source_index)
		var source := tile_set.get_source(source_id)
		if not (source is TileSetAtlasSource):
			continue
		var atlas_source := source as TileSetAtlasSource
		for tile_index in atlas_source.get_tiles_count():
			var atlas: Vector2i = atlas_source.get_tile_id(tile_index)
			for alternative_index in atlas_source.get_alternative_tiles_count(atlas):
				var alternative: int = atlas_source.get_alternative_tile_id(atlas, alternative_index)
				var key: String = _tile_key(source_id, atlas, alternative)
				if key == "":
					continue
				if not groups.has(key):
					groups[key] = []
				groups[key].append({
					"source_id": source_id,
					"atlas": atlas,
					"alternative": alternative,
				})
	return groups


func _tile_key(source_id: int, atlas: Vector2i, alternative: int) -> String:
	if tile_set == null:
		return ""
	var source := tile_set.get_source(source_id)
	if not (source is TileSetAtlasSource):
		return ""
	var atlas_source := source as TileSetAtlasSource
	var tile_data := atlas_source.get_tile_data(atlas, alternative)
	if tile_data == null or tile_data.terrain_set != WATER_TERRAIN_SET:
		return ""
	var bits: Array[String] = []
	for bit in PEERING_BITS:
		bits.append(str(tile_data.get_terrain_peering_bit(bit)))
	return "|".join(bits)


func _cell_offset(cell: Vector2i) -> int:
	return abs((cell.x * 17 + cell.y * 31) % 997)
