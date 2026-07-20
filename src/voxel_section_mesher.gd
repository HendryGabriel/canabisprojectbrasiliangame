## CPU-only section meshing for the fixed VoxelWorld.
##
## This class deliberately creates no scene nodes or GPU resources.  Its input is
## an immutable padded section snapshot, so `build()` can run from a worker task.
class_name VoxelSectionMesher
extends RefCounted


const VoxelWorldScript = preload("res://src/voxel_world.gd")
const MicroCellScript = preload("res://src/micro_cell_data.gd")

## PackedStringArray constructors are runtime expressions in Godot 4, so this
## must remain a literal Array to be usable as a script constant.
const FACE_NAMES: Array = [
	"north", "south", "east", "west", "top", "bottom"
]


static func build(snapshot: Dictionary, render_palette: Dictionary, voxel_ao_enabled: bool = true, micro_density: int = 4) -> Dictionary:
	var opaque_builders: Dictionary = {}
	var cutout_builders: Dictionary = {}
	var transparent_builders: Dictionary = {}
	var micro_builders: Dictionary = {}
	var collision_faces: PackedVector3Array = PackedVector3Array()

	for face_name in FACE_NAMES:
		_build_greedy_opaque_face(snapshot, render_palette, face_name, voxel_ao_enabled, opaque_builders)
		_build_greedy_collision_face(snapshot, render_palette, face_name, collision_faces)
	_append_micro_cells(snapshot, render_palette, opaque_builders, cutout_builders, transparent_builders, collision_faces)

	# Cutout foliage and plants require their original small quads.  Greedy merging
	# them would change alpha sorting, wind, and crossed-plant silhouettes.
	var size: int = int(snapshot.get("size", VoxelWorldScript.SECTION_SIZE))
	for local_y in range(size):
		for local_z in range(size):
			for local_x in range(size):
				var pos: Vector3i = Vector3i(local_x, local_y, local_z)
				var palette_id: int = _id_at(snapshot, pos)
				if palette_id == 0:
					continue
				var descriptor: Dictionary = render_palette.get(palette_id, {})
				if descriptor.is_empty():
					continue
				if bool(descriptor.get("plant", false)):
					_append_plant(cutout_builders, descriptor, pos)
					continue
				var block_id: String = str(descriptor.get("block_id", ""))
				var global_pos: Vector3i = (snapshot.get("origin", Vector3i.ZERO) as Vector3i) + pos
				if block_id == "grass" and _face_is_visible(snapshot, render_palette, pos, palette_id, "top"):
					_append_micro_grass(micro_builders, descriptor, pos, global_pos, maxi(1, micro_density))
				elif block_id == "leaves":
					for micro_face in FACE_NAMES:
						if _face_is_visible(snapshot, render_palette, pos, palette_id, micro_face):
							_append_micro_leaf_face(micro_builders, descriptor, micro_face, pos, global_pos, maxi(1, micro_density))
				if not bool(descriptor.get("transparent", false)) and not bool(descriptor.get("foliage", false)):
					continue
				for face_name in FACE_NAMES:
					if not _face_is_visible(snapshot, render_palette, pos, palette_id, face_name):
						continue
					var target_builders: Dictionary = cutout_builders if bool(descriptor.get("foliage", false)) else transparent_builders
					var ao: PackedFloat32Array = _face_ao(snapshot, render_palette, pos, face_name, voxel_ao_enabled)
					_append_face(target_builders, descriptor, face_name, pos, Vector2i(1, 1), ao, 0)

	return {
		"section": snapshot.get("section", Vector3i.ZERO),
		"origin": snapshot.get("origin", Vector3i.ZERO),
		"revision": int(snapshot.get("revision", 0)),
		"opaque": _builders_to_surfaces(opaque_builders),
		"cutout": _builders_to_surfaces(cutout_builders),
		"transparent": _builders_to_surfaces(transparent_builders),
		"micro_foliage": _builders_to_surfaces(micro_builders),
		"collision_faces": collision_faces,
	}


static func _append_micro_cells(snapshot: Dictionary, render_palette: Dictionary, opaque_builders: Dictionary, cutout_builders: Dictionary, transparent_builders: Dictionary, collision_faces: PackedVector3Array) -> void:
	var cells: Dictionary = {}
	for raw_row in snapshot.get("micro_cells", []) as Array:
		if typeof(raw_row) != TYPE_ARRAY or (raw_row as Array).size() < 4 or typeof((raw_row as Array)[3]) != TYPE_DICTIONARY:
			continue
		var row: Array = raw_row as Array
		var cell = MicroCellScript.from_dictionary(row[3] as Dictionary)
		if cell != null:
			cells[Vector3i(int(row[0]), int(row[1]), int(row[2]))] = cell
	if cells.is_empty():
		return
	var descriptor_by_name: Dictionary = {}
	for raw_descriptor in render_palette.values():
		var descriptor: Dictionary = raw_descriptor as Dictionary
		descriptor_by_name[str(descriptor.get("block_id", ""))] = descriptor
	var section_size: int = int(snapshot.get("size", VoxelWorldScript.SECTION_SIZE))
	for raw_base_pos in cells.keys():
		var base_pos: Vector3i = raw_base_pos
		if base_pos.x < 0 or base_pos.x >= section_size or base_pos.y < 0 or base_pos.y >= section_size or base_pos.z < 0 or base_pos.z >= section_size:
			continue
		var cell = cells[base_pos]
		_append_greedy_micro_cell(snapshot, render_palette, cells, descriptor_by_name, base_pos, cell, opaque_builders, cutout_builders, transparent_builders, collision_faces)


static func _append_greedy_micro_cell(snapshot: Dictionary, render_palette: Dictionary, cells: Dictionary, descriptor_by_name: Dictionary, base_pos: Vector3i, cell, opaque_builders: Dictionary, cutout_builders: Dictionary, transparent_builders: Dictionary, collision_faces: PackedVector3Array) -> void:
	var size: int = MicroCellScript.SIZE
	for face_name in FACE_NAMES:
		for slice in range(size):
			var candidates: Array = []; candidates.resize(size * size)
			for v in range(size):
				for u in range(size):
					var micro_pos: Vector3i = _face_position(face_name, slice, u, v)
					var material_id: String = cell.get_material(micro_pos)
					if material_id != "" and _micro_face_visible(snapshot, render_palette, cells, base_pos, micro_pos, face_name):
						var piece_edge: int = cell.get_piece_edge(micro_pos)
						var piece_origin: Vector3i = cell.get_piece_origin(micro_pos)
						candidates[v * size + u] = {
							"material": material_id,
							"piece_edge": piece_edge,
							"piece_origin": piece_origin,
							"signature": "%s|%d|%d:%d:%d" % [material_id, piece_edge, piece_origin.x, piece_origin.y, piece_origin.z],
						}
			for v in range(size):
				for u in range(size):
					var index: int = v * size + u
					if candidates[index] == null: continue
					var candidate: Dictionary = candidates[index] as Dictionary
					var material_id: String = str(candidate.get("material", ""))
					var signature: String = str(candidate.get("signature", ""))
					var width: int = 1; var height: int = 1
					while u + width < size and _same_micro_piece(candidates[v * size + u + width], signature): width += 1
					var can_extend: bool = true
					while v + height < size and can_extend:
						for test_u in range(width):
							if not _same_micro_piece(candidates[(v + height) * size + u + test_u], signature): can_extend = false; break
						if can_extend: height += 1
					for clear_v in range(height):
						for clear_u in range(width): candidates[(v + clear_v) * size + u + clear_u] = null
					var descriptor: Dictionary = descriptor_by_name.get(material_id, {}) as Dictionary
					if descriptor.is_empty(): continue
					var target_builders: Dictionary = transparent_builders if bool(descriptor.get("transparent", false)) else (cutout_builders if bool(descriptor.get("foliage", false)) or bool(descriptor.get("plant", false)) else opaque_builders)
					var corners: PackedVector3Array = _micro_rect_face_corners(base_pos, _face_position(face_name, slice, u, v), face_name, width, height)
					var face_uvs: PackedVector2Array = _micro_piece_face_uvs(face_name, u, v, width, height, candidate.get("piece_origin", Vector3i.ZERO), int(candidate.get("piece_edge", 1)))
					_append_micro_face(target_builders, descriptor, face_name, corners, face_uvs)
					if bool(descriptor.get("solid", true)) and not bool(descriptor.get("plant", false)):
						collision_faces.append_array(PackedVector3Array([corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]]))


static func _same_micro_piece(candidate: Variant, signature: String) -> bool:
	return typeof(candidate) == TYPE_DICTIONARY and str((candidate as Dictionary).get("signature", "")) == signature


static func _micro_piece_face_uvs(face_name: String, u: int, v: int, width: int, height: int, piece_origin: Vector3i, piece_edge: int) -> PackedVector2Array:
	var piece_u: int = piece_origin.z if face_name in ["east", "west"] else piece_origin.x
	var piece_v: int = piece_origin.z if face_name in ["top", "bottom"] else piece_origin.y
	var u0: float = float(u - piece_u) / float(piece_edge)
	var v0: float = float(v - piece_v) / float(piece_edge)
	var u1: float = u0 + float(width) / float(piece_edge)
	var v1: float = v0 + float(height) / float(piece_edge)
	if face_name in ["top", "bottom"]:
		return PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])
	return PackedVector2Array([Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0)])


static func _micro_rect_face_corners(base_pos: Vector3i, micro_pos: Vector3i, face_name: String, width: int, height: int) -> PackedVector3Array:
	var edge: float = 1.0 / float(MicroCellScript.SIZE)
	var minimum: Vector3 = Vector3(base_pos) - Vector3.ONE * 0.5 + Vector3(micro_pos) * edge
	var maximum: Vector3 = minimum + Vector3.ONE * edge
	match face_name:
		"north": maximum.x = minimum.x + width * edge; maximum.y = minimum.y + height * edge
		"south": maximum.x = minimum.x + width * edge; maximum.y = minimum.y + height * edge
		"east": maximum.z = minimum.z + width * edge; maximum.y = minimum.y + height * edge
		"west": maximum.z = minimum.z + width * edge; maximum.y = minimum.y + height * edge
		"top": maximum.x = minimum.x + width * edge; maximum.z = minimum.z + height * edge
		"bottom": maximum.x = minimum.x + width * edge; maximum.z = minimum.z + height * edge
	match face_name:
		"north": return PackedVector3Array([Vector3(minimum.x, minimum.y, minimum.z), Vector3(maximum.x, minimum.y, minimum.z), Vector3(maximum.x, maximum.y, minimum.z), Vector3(minimum.x, maximum.y, minimum.z)])
		"south": return PackedVector3Array([Vector3(maximum.x, minimum.y, maximum.z), Vector3(minimum.x, minimum.y, maximum.z), Vector3(minimum.x, maximum.y, maximum.z), Vector3(maximum.x, maximum.y, maximum.z)])
		"east": return PackedVector3Array([Vector3(maximum.x, minimum.y, minimum.z), Vector3(maximum.x, minimum.y, maximum.z), Vector3(maximum.x, maximum.y, maximum.z), Vector3(maximum.x, maximum.y, minimum.z)])
		"west": return PackedVector3Array([Vector3(minimum.x, minimum.y, maximum.z), Vector3(minimum.x, minimum.y, minimum.z), Vector3(minimum.x, maximum.y, minimum.z), Vector3(minimum.x, maximum.y, maximum.z)])
		"top": return PackedVector3Array([Vector3(minimum.x, maximum.y, minimum.z), Vector3(maximum.x, maximum.y, minimum.z), Vector3(maximum.x, maximum.y, maximum.z), Vector3(minimum.x, maximum.y, maximum.z)])
		"bottom": return PackedVector3Array([Vector3(minimum.x, minimum.y, maximum.z), Vector3(maximum.x, minimum.y, maximum.z), Vector3(maximum.x, minimum.y, minimum.z), Vector3(minimum.x, minimum.y, minimum.z)])
	return PackedVector3Array()


static func _micro_face_visible(snapshot: Dictionary, render_palette: Dictionary, cells: Dictionary, base_pos: Vector3i, micro_pos: Vector3i, face_name: String) -> bool:
	var neighbor_micro: Vector3i = micro_pos + _face_offset(face_name)
	var neighbor_base: Vector3i = base_pos
	if neighbor_micro.x < 0: neighbor_base.x -= 1; neighbor_micro.x = MicroCellScript.SIZE - 1
	elif neighbor_micro.x >= MicroCellScript.SIZE: neighbor_base.x += 1; neighbor_micro.x = 0
	if neighbor_micro.y < 0: neighbor_base.y -= 1; neighbor_micro.y = MicroCellScript.SIZE - 1
	elif neighbor_micro.y >= MicroCellScript.SIZE: neighbor_base.y += 1; neighbor_micro.y = 0
	if neighbor_micro.z < 0: neighbor_base.z -= 1; neighbor_micro.z = MicroCellScript.SIZE - 1
	elif neighbor_micro.z >= MicroCellScript.SIZE: neighbor_base.z += 1; neighbor_micro.z = 0
	if cells.has(neighbor_base) and cells[neighbor_base].get_material(neighbor_micro) != "":
		return false
	var neighbor_id: int = _id_at(snapshot, neighbor_base)
	if neighbor_id == 0:
		return true
	var neighbor: Dictionary = render_palette.get(neighbor_id, {}) as Dictionary
	return not bool(neighbor.get("solid", false)) or bool(neighbor.get("transparent", false))


static func _micro_face_corners(base_pos: Vector3i, micro_pos: Vector3i, face_name: String) -> PackedVector3Array:
	var edge: float = 1.0 / float(MicroCellScript.SIZE)
	var minimum: Vector3 = Vector3(base_pos) - Vector3.ONE * 0.5 + Vector3(micro_pos) * edge
	var maximum: Vector3 = minimum + Vector3.ONE * edge
	match face_name:
		"north": return PackedVector3Array([Vector3(minimum.x, minimum.y, minimum.z), Vector3(maximum.x, minimum.y, minimum.z), Vector3(maximum.x, maximum.y, minimum.z), Vector3(minimum.x, maximum.y, minimum.z)])
		"south": return PackedVector3Array([Vector3(maximum.x, minimum.y, maximum.z), Vector3(minimum.x, minimum.y, maximum.z), Vector3(minimum.x, maximum.y, maximum.z), Vector3(maximum.x, maximum.y, maximum.z)])
		"east": return PackedVector3Array([Vector3(maximum.x, minimum.y, minimum.z), Vector3(maximum.x, minimum.y, maximum.z), Vector3(maximum.x, maximum.y, maximum.z), Vector3(maximum.x, maximum.y, minimum.z)])
		"west": return PackedVector3Array([Vector3(minimum.x, minimum.y, maximum.z), Vector3(minimum.x, minimum.y, minimum.z), Vector3(minimum.x, maximum.y, minimum.z), Vector3(minimum.x, maximum.y, maximum.z)])
		"top": return PackedVector3Array([Vector3(minimum.x, maximum.y, minimum.z), Vector3(maximum.x, maximum.y, minimum.z), Vector3(maximum.x, maximum.y, maximum.z), Vector3(minimum.x, maximum.y, maximum.z)])
		"bottom": return PackedVector3Array([Vector3(minimum.x, minimum.y, maximum.z), Vector3(maximum.x, minimum.y, maximum.z), Vector3(maximum.x, minimum.y, minimum.z), Vector3(minimum.x, minimum.y, minimum.z)])
	return PackedVector3Array()


static func _append_micro_face(builders: Dictionary, descriptor: Dictionary, face_name: String, corners: PackedVector3Array, face_uvs: PackedVector2Array) -> void:
	var builder: Dictionary = _get_builder(builders, descriptor, face_name)
	var vertices: PackedVector3Array = builder["vertices"] as PackedVector3Array
	var normals: PackedVector3Array = builder["normals"] as PackedVector3Array
	var uvs: PackedVector2Array = builder["uvs"] as PackedVector2Array
	var uv2: PackedVector2Array = builder["uv2"] as PackedVector2Array
	var colors: PackedColorArray = builder["colors"] as PackedColorArray
	var indices: PackedInt32Array = builder["indices"] as PackedInt32Array
	var first: int = vertices.size()
	for index in range(4):
		vertices.append(corners[index])
		normals.append(Vector3(_face_offset(face_name)))
		uvs.append(face_uvs[index])
		uv2.append(Vector2(float(_texture_layer_for_face(descriptor, face_name)), 0.0))
		colors.append(Color(1.0, 1.0, 1.0, float(descriptor.get("alpha", 1.0))))
	indices.append_array(PackedInt32Array([first, first + 1, first + 2, first, first + 2, first + 3]))
	builder["vertices"] = vertices; builder["normals"] = normals; builder["uvs"] = uvs
	builder["uv2"] = uv2; builder["colors"] = colors; builder["indices"] = indices


static func _build_greedy_opaque_face(snapshot: Dictionary, render_palette: Dictionary, face_name: String, voxel_ao_enabled: bool, builders: Dictionary) -> void:
	var size: int = int(snapshot.get("size", VoxelWorldScript.SECTION_SIZE))
	for slice in range(size):
		var candidates: Array = []
		candidates.resize(size * size)
		for v in range(size):
			for u in range(size):
				var pos: Vector3i = _face_position(face_name, slice, u, v)
				var palette_id: int = _id_at(snapshot, pos)
				if palette_id == 0:
					continue
				var descriptor: Dictionary = render_palette.get(palette_id, {})
				if descriptor.is_empty() or bool(descriptor.get("transparent", false)) or bool(descriptor.get("foliage", false)) or bool(descriptor.get("plant", false)):
					continue
				if not _face_is_visible(snapshot, render_palette, pos, palette_id, face_name):
					continue
				var ao: PackedFloat32Array = _face_ao(snapshot, render_palette, pos, face_name, voxel_ao_enabled)
				var rotation: int = _top_rotation(descriptor, pos, face_name)
				var mergeable: bool = not (face_name == "top" and bool(descriptor.get("random_top_rotation", false)))
				candidates[v * size + u] = {
					"descriptor": descriptor,
					"ao": ao,
					"signature": _face_signature(palette_id, face_name, ao, rotation),
					"rotation": rotation,
					"mergeable": mergeable,
				}
		_greedy_emit(face_name, slice, size, candidates, builders)


static func _build_greedy_collision_face(snapshot: Dictionary, render_palette: Dictionary, face_name: String, collision_faces: PackedVector3Array) -> void:
	var size: int = int(snapshot.get("size", VoxelWorldScript.SECTION_SIZE))
	for slice in range(size):
		var candidates: Array = []
		candidates.resize(size * size)
		for v in range(size):
			for u in range(size):
				var pos: Vector3i = _face_position(face_name, slice, u, v)
				var palette_id: int = _id_at(snapshot, pos)
				if palette_id == 0:
					continue
				var descriptor: Dictionary = render_palette.get(palette_id, {})
				if descriptor.is_empty() or not bool(descriptor.get("solid", true)) or bool(descriptor.get("plant", false)):
					continue
				var neighbor_id: int = _id_at(snapshot, pos + _face_offset(face_name))
				var neighbor_descriptor: Dictionary = render_palette.get(neighbor_id, {})
				if neighbor_id != 0 and bool(neighbor_descriptor.get("solid", false)):
					continue
				candidates[v * size + u] = {"signature": "collision", "mergeable": true}
		_greedy_emit_collision(face_name, slice, size, candidates, collision_faces)


static func _greedy_emit(face_name: String, slice: int, size: int, candidates: Array, builders: Dictionary) -> void:
	for v in range(size):
		for u in range(size):
			var index: int = v * size + u
			var candidate: Variant = candidates[index]
			if candidate == null:
				continue
			var data: Dictionary = candidate as Dictionary
			var width: int = 1
			var height: int = 1
			if bool(data.get("mergeable", false)):
				while u + width < size and _same_signature(candidates[v * size + u + width], data):
					width += 1
				var can_extend: bool = true
				while v + height < size and can_extend:
					for test_u in range(width):
						if not _same_signature(candidates[(v + height) * size + u + test_u], data):
							can_extend = false
							break
					if can_extend:
						height += 1
			for clear_v in range(height):
				for clear_u in range(width):
					candidates[(v + clear_v) * size + u + clear_u] = null
			var base_pos: Vector3i = _face_position(face_name, slice, u, v)
			_append_face(
				builders,
				data["descriptor"] as Dictionary,
				face_name,
				base_pos,
				Vector2i(width, height),
				data["ao"] as PackedFloat32Array,
				int(data.get("rotation", 0))
			)


static func _greedy_emit_collision(face_name: String, slice: int, size: int, candidates: Array, collision_faces: PackedVector3Array) -> void:
	for v in range(size):
		for u in range(size):
			var index: int = v * size + u
			var candidate: Variant = candidates[index]
			if candidate == null:
				continue
			var data: Dictionary = candidate as Dictionary
			var width: int = 1
			var height: int = 1
			while u + width < size and _same_signature(candidates[v * size + u + width], data):
				width += 1
			var can_extend: bool = true
			while v + height < size and can_extend:
				for test_u in range(width):
					if not _same_signature(candidates[(v + height) * size + u + test_u], data):
						can_extend = false
						break
				if can_extend:
					height += 1
			for clear_v in range(height):
				for clear_u in range(width):
					candidates[(v + clear_v) * size + u + clear_u] = null
			var corners: PackedVector3Array = _face_corners(face_name, _face_position(face_name, slice, u, v), Vector2i(width, height))
			collision_faces.append(corners[0])
			collision_faces.append(corners[1])
			collision_faces.append(corners[2])
			collision_faces.append(corners[0])
			collision_faces.append(corners[2])
			collision_faces.append(corners[3])


static func _append_face(builders: Dictionary, descriptor: Dictionary, face_name: String, pos: Vector3i, dimensions: Vector2i, ao: PackedFloat32Array, rotation: int) -> void:
	var builder: Dictionary = _get_builder(builders, descriptor, face_name)
	var corners: PackedVector3Array = _face_corners(face_name, pos, dimensions)
	# Packed arrays are copy-on-write values when read from a Dictionary. Keep
	# local buffers and assign them back once populated so worker results retain
	# their vertices on every Godot 4 renderer backend.
	var vertices: PackedVector3Array = builder["vertices"] as PackedVector3Array
	var normals: PackedVector3Array = builder["normals"] as PackedVector3Array
	var uvs_out: PackedVector2Array = builder["uvs"] as PackedVector2Array
	var uv2_out: PackedVector2Array = builder["uv2"] as PackedVector2Array
	var colors: PackedColorArray = builder["colors"] as PackedColorArray
	var indices: PackedInt32Array = builder["indices"] as PackedInt32Array
	var first_index: int = vertices.size()
	var normal: Vector3 = Vector3(_face_offset(face_name))
	var uvs: PackedVector2Array = _face_uvs(dimensions, face_name, rotation)
	for corner_index in range(4):
		vertices.append(corners[corner_index])
		normals.append(normal)
		uvs_out.append(uvs[corner_index])
		uv2_out.append(Vector2(float(_texture_layer_for_face(descriptor, face_name)), 0.0))
		var brightness: float = ao[corner_index] if corner_index < ao.size() else 1.0
		colors.append(Color(brightness, brightness, brightness, float(descriptor.get("alpha", 1.0))))
	if ao.size() >= 4 and ao[0] + ao[2] > ao[1] + ao[3]:
		indices.append_array(PackedInt32Array([first_index, first_index + 1, first_index + 3, first_index + 1, first_index + 2, first_index + 3]))
	else:
		indices.append_array(PackedInt32Array([first_index, first_index + 1, first_index + 2, first_index, first_index + 2, first_index + 3]))
	builder["vertices"] = vertices
	builder["normals"] = normals
	builder["uvs"] = uvs_out
	builder["uv2"] = uv2_out
	builder["colors"] = colors
	builder["indices"] = indices


static func _append_plant(builders: Dictionary, descriptor: Dictionary, pos: Vector3i) -> void:
	var builder: Dictionary = _get_builder(builders, descriptor, "plant")
	var vertices_out: PackedVector3Array = builder["vertices"] as PackedVector3Array
	var normals_out: PackedVector3Array = builder["normals"] as PackedVector3Array
	var uvs_out: PackedVector2Array = builder["uvs"] as PackedVector2Array
	var uv2_out: PackedVector2Array = builder["uv2"] as PackedVector2Array
	var colors_out: PackedColorArray = builder["colors"] as PackedColorArray
	var indices_out: PackedInt32Array = builder["indices"] as PackedInt32Array
	var center: Vector3 = Vector3(pos)
	var height: float = 0.8
	var planes: Array[PackedVector3Array] = [
		PackedVector3Array([
			center + Vector3(-0.5, -0.5, -0.5), center + Vector3(0.5, -0.5, 0.5),
			center + Vector3(0.5, -0.5 + height, 0.5), center + Vector3(-0.5, -0.5 + height, -0.5),
		]),
		PackedVector3Array([
			center + Vector3(-0.5, -0.5, 0.5), center + Vector3(0.5, -0.5, -0.5),
			center + Vector3(0.5, -0.5 + height, -0.5), center + Vector3(-0.5, -0.5 + height, 0.5),
		]),
	]
	var normals: Array[Vector3] = [Vector3(-0.7071, 0.0, 0.7071), Vector3(0.7071, 0.0, 0.7071)]
	for plane_index in range(planes.size()):
		var first_index: int = vertices_out.size()
		var vertices: PackedVector3Array = planes[plane_index]
		var uvs: PackedVector2Array = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
		for vertex_index in range(4):
			vertices_out.append(vertices[vertex_index])
			normals_out.append(normals[plane_index])
			uvs_out.append(uvs[vertex_index])
			uv2_out.append(Vector2(float(_texture_layer_for_face(descriptor, "plant")), 0.0))
			colors_out.append(Color(1.0, 1.0, 1.0, float(descriptor.get("alpha", 1.0))))
		indices_out.append_array(PackedInt32Array([
			first_index, first_index + 1, first_index + 2, first_index, first_index + 2, first_index + 3,
			first_index + 2, first_index + 1, first_index, first_index + 3, first_index + 2, first_index,
		]))
	builder["vertices"] = vertices_out
	builder["normals"] = normals_out
	builder["uvs"] = uvs_out
	builder["uv2"] = uv2_out
	builder["colors"] = colors_out
	builder["indices"] = indices_out


static func _append_micro_grass(builders: Dictionary, descriptor: Dictionary, pos: Vector3i, global_pos: Vector3i, density: int) -> void:
	var count: int = 4 if density >= 4 else 2
	for index in range(count):
		var hash_value: int = _micro_hash(global_pos, "top", index)
		var center: Vector3 = Vector3(pos) + Vector3(
			(float(hash_value & 255) / 255.0 - 0.5) * 0.72,
			0.5,
			(float((hash_value >> 8) & 255) / 255.0 - 0.5) * 0.72
		)
		var tangent: Vector3 = Vector3.RIGHT if (hash_value & 1) == 0 else Vector3.FORWARD
		var height: float = float(1 + ((hash_value >> 16) % 3)) / 16.0
		_append_micro_fin(builders, descriptor, "top", center, tangent, Vector3.UP, height, hash_value)


static func _append_micro_leaf_face(builders: Dictionary, descriptor: Dictionary, face_name: String, pos: Vector3i, global_pos: Vector3i, density: int) -> void:
	var count: int = 4 if density >= 4 else 2
	var outward: Vector3 = Vector3(_face_offset(face_name))
	var tangent_a: Vector3 = Vector3.RIGHT
	var tangent_b: Vector3 = Vector3.UP
	if face_name in ["north", "south"]:
		tangent_a = Vector3.RIGHT; tangent_b = Vector3.UP
	elif face_name in ["east", "west"]:
		tangent_a = Vector3.FORWARD; tangent_b = Vector3.UP
	else:
		tangent_a = Vector3.RIGHT; tangent_b = Vector3.FORWARD
	for index in range(count):
		var hash_value: int = _micro_hash(global_pos, face_name, index)
		var offset_a: float = (float(hash_value & 255) / 255.0 - 0.5) * 0.7
		var offset_b: float = (float((hash_value >> 8) & 255) / 255.0 - 0.5) * 0.7
		var center: Vector3 = Vector3(pos) + outward * 0.5 + tangent_a * offset_a + tangent_b * offset_b
		var tangent: Vector3 = tangent_a if (hash_value & 1) == 0 else tangent_b
		var height: float = float(1 + ((hash_value >> 16) % 3)) / 16.0
		_append_micro_fin(builders, descriptor, face_name, center, tangent, outward, height, hash_value)


static func _append_micro_fin(builders: Dictionary, descriptor: Dictionary, face_name: String, center: Vector3, tangent: Vector3, outward: Vector3, height: float, hash_value: int) -> void:
	var builder: Dictionary = _get_micro_builder(builders, descriptor, face_name)
	var vertices: PackedVector3Array = builder["vertices"] as PackedVector3Array
	var normals: PackedVector3Array = builder["normals"] as PackedVector3Array
	var uvs: PackedVector2Array = builder["uvs"] as PackedVector2Array
	var uv2: PackedVector2Array = builder["uv2"] as PackedVector2Array
	var colors: PackedColorArray = builder["colors"] as PackedColorArray
	var indices: PackedInt32Array = builder["indices"] as PackedInt32Array
	var first: int = vertices.size()
	var half_width: float = 1.0 / 16.0
	var base_a: Vector3 = center - tangent * half_width
	var base_b: Vector3 = center + tangent * half_width
	var tip_offset: Vector3 = outward * height
	vertices.append_array(PackedVector3Array([base_a, base_b, base_b + tip_offset, base_a + tip_offset]))
	for _index in range(4): normals.append(outward)
	var pixel_x: int = (hash_value >> 4) & 15
	var pixel_y: int = (hash_value >> 12) & 15
	var u0: float = float(pixel_x) / 16.0
	var u1: float = float(pixel_x + 1) / 16.0
	var v0: float = float(pixel_y) / 16.0
	var v1: float = float(pixel_y + 1) / 16.0
	uvs.append_array(PackedVector2Array([Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0)]))
	var face_code: float = float(FACE_NAMES.find(face_name))
	for _index in range(4): uv2.append(Vector2(float(_texture_layer_for_face(descriptor, face_name)), face_code))
	colors.append_array(PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1)]))
	indices.append_array(PackedInt32Array([first, first + 1, first + 2, first, first + 2, first + 3]))
	builder["vertices"] = vertices; builder["normals"] = normals; builder["uvs"] = uvs
	builder["uv2"] = uv2; builder["colors"] = colors; builder["indices"] = indices


static func _get_micro_builder(builders: Dictionary, descriptor: Dictionary, face_name: String) -> Dictionary:
	var key: String = "array|micro_foliage" if descriptor.has("texture_layers") else "micro|%s" % str((descriptor.get("textures", {}) as Dictionary).get(face_name, descriptor.get("texture", "")))
	if not builders.has(key):
		builders[key] = {
			"texture_path": str((descriptor.get("textures", {}) as Dictionary).get(face_name, descriptor.get("texture", ""))),
			"fallback_color": descriptor.get("color", Color.WHITE), "alpha": 1.0,
			"transparent": false, "foliage": true, "render_class": "micro_foliage",
			"use_texture_array": descriptor.has("texture_layers"),
			"vertices": PackedVector3Array(), "normals": PackedVector3Array(),
			"uvs": PackedVector2Array(), "uv2": PackedVector2Array(),
			"colors": PackedColorArray(), "indices": PackedInt32Array(),
		}
	return builders[key] as Dictionary


static func _micro_hash(pos: Vector3i, face_name: String, index: int) -> int:
	var value: int = pos.x * 73856093 ^ pos.y * 19349663 ^ pos.z * 83492791 ^ face_name.hash() ^ index * 265443576
	return absi(value)


static func _get_builder(builders: Dictionary, descriptor: Dictionary, face_name: String) -> Dictionary:
	var texture_path: String = str((descriptor.get("textures", {}) as Dictionary).get(face_name, (descriptor.get("textures", {}) as Dictionary).get("top", "")))
	var fallback: Color = descriptor.get("color", Color.WHITE)
	var alpha: float = float(descriptor.get("alpha", 1.0))
	var transparent: bool = bool(descriptor.get("transparent", false))
	var foliage: bool = bool(descriptor.get("foliage", false))
	var plant: bool = bool(descriptor.get("plant", false))
	var render_class: String = "cutout" if foliage or plant else ("transparent" if transparent else "opaque")
	var use_texture_array: bool = descriptor.has("texture_layers")
	var key: String = "array|%s" % render_class if use_texture_array else "%s|%s|%.3f|%s|%s" % [texture_path, fallback.to_html(), alpha, str(transparent), str(foliage)]
	if not builders.has(key):
		builders[key] = {
			"texture_path": texture_path,
			"fallback_color": fallback,
			"alpha": alpha,
			"transparent": transparent,
			"foliage": foliage,
			"render_class": render_class,
			"use_texture_array": use_texture_array,
			"vertices": PackedVector3Array(),
			"normals": PackedVector3Array(),
			"uvs": PackedVector2Array(),
			"uv2": PackedVector2Array(),
			"colors": PackedColorArray(),
			"indices": PackedInt32Array(),
		}
	return builders[key] as Dictionary


static func _builders_to_surfaces(builders: Dictionary) -> Array:
	var surfaces: Array = []
	for raw_builder in builders.values():
		var builder: Dictionary = raw_builder as Dictionary
		if (builder["vertices"] as PackedVector3Array).is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = builder["vertices"]
		arrays[Mesh.ARRAY_NORMAL] = builder["normals"]
		arrays[Mesh.ARRAY_TEX_UV] = builder["uvs"]
		arrays[Mesh.ARRAY_TEX_UV2] = builder["uv2"]
		arrays[Mesh.ARRAY_COLOR] = builder["colors"]
		arrays[Mesh.ARRAY_INDEX] = builder["indices"]
		surfaces.append({
			"texture_path": builder["texture_path"],
			"fallback_color": builder["fallback_color"],
			"alpha": builder["alpha"],
			"transparent": builder["transparent"],
			"foliage": builder["foliage"],
			"render_class": builder["render_class"],
			"use_texture_array": builder["use_texture_array"],
			"arrays": arrays,
		})
	return surfaces


static func _face_position(face_name: String, slice: int, u: int, v: int) -> Vector3i:
	match face_name:
		"north", "south":
			return Vector3i(u, v, slice)
		"east", "west":
			return Vector3i(slice, v, u)
		"top", "bottom":
			return Vector3i(u, slice, v)
	return Vector3i.ZERO


static func _face_corners(face_name: String, pos: Vector3i, dimensions: Vector2i) -> PackedVector3Array:
	var width: float = float(dimensions.x)
	var height: float = float(dimensions.y)
	var x0: float = float(pos.x) - 0.5
	var y0: float = float(pos.y) - 0.5
	var z0: float = float(pos.z) - 0.5
	match face_name:
		"north":
			return PackedVector3Array([Vector3(x0, y0, z0), Vector3(x0 + width, y0, z0), Vector3(x0 + width, y0 + height, z0), Vector3(x0, y0 + height, z0)])
		"south":
			return PackedVector3Array([Vector3(x0 + width, y0, z0 + 1.0), Vector3(x0, y0, z0 + 1.0), Vector3(x0, y0 + height, z0 + 1.0), Vector3(x0 + width, y0 + height, z0 + 1.0)])
		"east":
			return PackedVector3Array([Vector3(x0 + 1.0, y0, z0), Vector3(x0 + 1.0, y0, z0 + width), Vector3(x0 + 1.0, y0 + height, z0 + width), Vector3(x0 + 1.0, y0 + height, z0)])
		"west":
			return PackedVector3Array([Vector3(x0, y0, z0 + width), Vector3(x0, y0, z0), Vector3(x0, y0 + height, z0), Vector3(x0, y0 + height, z0 + width)])
		"top":
			return PackedVector3Array([Vector3(x0, y0 + 1.0, z0), Vector3(x0 + width, y0 + 1.0, z0), Vector3(x0 + width, y0 + 1.0, z0 + height), Vector3(x0, y0 + 1.0, z0 + height)])
		"bottom":
			return PackedVector3Array([Vector3(x0, y0, z0 + height), Vector3(x0 + width, y0, z0 + height), Vector3(x0 + width, y0, z0), Vector3(x0, y0, z0)])
	return PackedVector3Array()


static func _face_uvs(dimensions: Vector2i, face_name: String, rotation: int) -> PackedVector2Array:
	var width: float = float(dimensions.x)
	var height: float = float(dimensions.y)
	var uvs: PackedVector2Array
	if face_name in ["top", "bottom"]:
		uvs = PackedVector2Array([Vector2(0, 0), Vector2(width, 0), Vector2(width, height), Vector2(0, height)])
	else:
		uvs = PackedVector2Array([Vector2(0, height), Vector2(width, height), Vector2(width, 0), Vector2(0, 0)])
	if face_name in ["top", "bottom"] and rotation > 0:
		var rotated: PackedVector2Array = PackedVector2Array()
		for index in range(4):
			rotated.append(uvs[(index + rotation) % 4])
		return rotated
	return uvs


static func _face_is_visible(snapshot: Dictionary, render_palette: Dictionary, pos: Vector3i, palette_id: int, face_name: String) -> bool:
	var descriptor: Dictionary = render_palette.get(palette_id, {})
	if face_name == "bottom" and str(descriptor.get("block_id", "")) == "bedrock":
		return false
	var neighbor_pos: Vector3i = pos + _face_offset(face_name)
	var neighbor_id: int = _id_at(snapshot, neighbor_pos)
	var neighbor: Dictionary = render_palette.get(neighbor_id, {})
	if bool(descriptor.get("foliage", false)) and bool(neighbor.get("foliage", false)):
		return false
	if neighbor_id == 0:
		return true
	if bool(neighbor.get("transparent", false)):
		return true
	return not bool(neighbor.get("solid", false))


static func _face_ao(snapshot: Dictionary, render_palette: Dictionary, pos: Vector3i, face_name: String, enabled: bool) -> PackedFloat32Array:
	if not enabled:
		return PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
	var result: PackedFloat32Array = PackedFloat32Array()
	for vertex in _face_vertex_signs(face_name):
		var sx: int = int(vertex.x)
		var sy: int = int(vertex.y)
		var sz: int = int(vertex.z)
		var a: Vector3i = Vector3i.ZERO
		var b: Vector3i = Vector3i.ZERO
		match face_name:
			"north", "south":
				a = Vector3i(sx, 0, 0)
				b = Vector3i(0, sy, 0)
			"east", "west":
				a = Vector3i(0, 0, sz)
				b = Vector3i(0, sy, 0)
			"top", "bottom":
				a = Vector3i(sx, 0, 0)
				b = Vector3i(0, 0, sz)
		var side_a: bool = _is_ao_occluder(snapshot, render_palette, pos + a)
		var side_b: bool = _is_ao_occluder(snapshot, render_palette, pos + b)
		var corner: bool = _is_ao_occluder(snapshot, render_palette, pos + a + b)
		var occluders: int = (1 if side_a else 0) + (1 if side_b else 0) + (1 if corner else 0)
		var level: int = 0 if side_a and side_b else 3 - occluders
		result.append([0.72, 0.82, 0.92, 1.0][level])
	return result


static func _face_vertex_signs(face_name: String) -> Array[Vector3i]:
	match face_name:
		"north":
			return [Vector3i(-1, -1, -1), Vector3i(1, -1, -1), Vector3i(1, 1, -1), Vector3i(-1, 1, -1)]
		"south":
			return [Vector3i(1, -1, 1), Vector3i(-1, -1, 1), Vector3i(-1, 1, 1), Vector3i(1, 1, 1)]
		"east":
			return [Vector3i(1, -1, 1), Vector3i(1, -1, -1), Vector3i(1, 1, -1), Vector3i(1, 1, 1)]
		"west":
			return [Vector3i(-1, -1, -1), Vector3i(-1, -1, 1), Vector3i(-1, 1, 1), Vector3i(-1, 1, -1)]
		"top":
			return [Vector3i(-1, 1, 1), Vector3i(1, 1, 1), Vector3i(1, 1, -1), Vector3i(-1, 1, -1)]
		"bottom":
			return [Vector3i(-1, -1, -1), Vector3i(1, -1, -1), Vector3i(1, -1, 1), Vector3i(-1, -1, 1)]
	return []


static func _face_offset(face_name: String) -> Vector3i:
	match face_name:
		"north": return Vector3i(0, 0, -1)
		"south": return Vector3i(0, 0, 1)
		"east": return Vector3i(1, 0, 0)
		"west": return Vector3i(-1, 0, 0)
		"top": return Vector3i(0, 1, 0)
		"bottom": return Vector3i(0, -1, 0)
	return Vector3i.ZERO


static func _id_at(snapshot: Dictionary, pos: Vector3i) -> int:
	var padded_size: int = int(snapshot.get("padded_size", VoxelWorldScript.PADDED_SECTION_SIZE))
	var x: int = pos.x + 1
	var y: int = pos.y + 1
	var z: int = pos.z + 1
	if x < 0 or x >= padded_size or y < 0 or y >= padded_size or z < 0 or z >= padded_size:
		return 0
	var voxels: Variant = snapshot["voxels"]
	return int(voxels[(y * padded_size + z) * padded_size + x])


static func _is_ao_occluder(snapshot: Dictionary, render_palette: Dictionary, pos: Vector3i) -> bool:
	var palette_id: int = _id_at(snapshot, pos)
	if palette_id == 0:
		return false
	var descriptor: Dictionary = render_palette.get(palette_id, {})
	return bool(descriptor.get("solid", false)) and not bool(descriptor.get("transparent", false))


static func _face_signature(palette_id: int, face_name: String, ao: PackedFloat32Array, rotation: int) -> String:
	return "%s|%s|%s|%s|%s|%s|%s" % [palette_id, face_name, ao[0], ao[1], ao[2], ao[3], rotation]


static func _same_signature(candidate: Variant, reference: Dictionary) -> bool:
	if candidate == null:
		return false
	var data: Dictionary = candidate as Dictionary
	return bool(data.get("mergeable", false)) and str(data.get("signature", "")) == str(reference.get("signature", ""))


static func _top_rotation(descriptor: Dictionary, pos: Vector3i, face_name: String) -> int:
	if face_name != "top" or not bool(descriptor.get("random_top_rotation", false)):
		return 0
	var value: float = sin(float(pos.x) * 12.9898 + float(pos.y) * 78.233 + float(pos.z) * 37.719 + 909.0 * 19.19) * 43758.5453
	return clampi(int(floor((value - floor(value)) * 4.0)), 0, 3)


static func _texture_layer_for_face(descriptor: Dictionary, face_name: String) -> int:
	var layers: Dictionary = descriptor.get("texture_layers", {}) as Dictionary
	if layers.has(face_name):
		return int(layers[face_name])
	if layers.has("top"):
		return int(layers["top"])
	return 0
