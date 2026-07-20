class_name PlacedAssetSystem
extends RefCounted


const StructureTemplateScript = preload("res://src/structure_template_data.gd")


var world
var registry
var instances: Dictionary = {} # root Vector3i -> runtime record
var owned_cells: Dictionary = {} # atomic/custom cell -> root
var assembly_cells: Dictionary = {} # required cell -> assembly root
var utility_handlers: Dictionary = {}
var warned_utilities: Dictionary = {}


func configure(p_world, p_registry) -> void:
	world = p_world
	registry = p_registry
	instances.clear(); owned_cells.clear(); assembly_cells.clear()


func register_utility(utility_id: String, handler: Object) -> void:
	if utility_id.strip_edges() == "" or handler == null: return
	utility_handlers[utility_id] = handler
	for root in _sorted_roots():
		var record: Dictionary = instances[root] as Dictionary
		var template = registry.get_asset(str((record as Dictionary).get("asset_id", ""))) if registry != null else null
		if template != null and template.utility_id == utility_id and bool((record as Dictionary).get("active", false)) and handler.has_method("activated"): handler.call("activated", record)


func process_tick(tick: int) -> void:
	for root in _sorted_roots():
		var typed_record: Dictionary = instances[root] as Dictionary
		if not bool(typed_record.get("active", false)): continue
		var template = registry.get_asset(str(typed_record.get("asset_id", ""))) if registry != null else null
		var handler: Object = utility_handlers.get(template.utility_id, null) if template != null else null
		if handler != null and handler.has_method("tick"): handler.call("tick", typed_record, tick)


func item_definitions() -> Dictionary:
	var result: Dictionary = {}
	if registry == null: return result
	for template in registry.get_placeable_assets():
		if template.asset_kind == "multiblock" and template.placement_mode == "assembled": continue
		result[template.structure_id] = {
			"name": template.display_name,
			"description": "Custom Block" if template.asset_kind == "custom_block" else "Multiblock",
			"place_asset": template.structure_id,
			"tool": "",
		}
	return result


func asset_for_item(item_id: String):
	var template = registry.get_asset(item_id) if registry != null else null
	return template if template != null and template.asset_kind in ["custom_block", "multiblock"] else null


func assembled_for_anchor_item(item_id: String):
	if registry == null: return null
	for template in registry.get_placeable_assets():
		if template.asset_kind != "multiblock" or template.placement_mode != "assembled": continue
		for raw_requirement in template.requirements:
			var requirement: Dictionary = raw_requirement as Dictionary
			if StructureTemplateScript._vector3i_from_value(requirement.get("pos", [])) == template.anchor and str(requirement.get("item_id", "")) == item_id:
				return template
	return null


func transformed_cells(template, pivot_world: Vector3i, rotation: int) -> Array:
	var cells: Array = []
	_append_transformed_cells(cells, template, pivot_world, posmod(rotation, 4), {})
	return cells


func can_place(template, pivot_world: Vector3i, rotation: int) -> Dictionary:
	if world == null or template == null: return {"ok": false, "reason": "asset_unavailable", "cells": []}
	var cells: Array = transformed_cells(template, pivot_world, rotation)
	if cells.is_empty(): return {"ok": false, "reason": "asset_empty", "cells": []}
	var seen: Dictionary = {}
	for raw_cell in cells:
		var cell: Dictionary = raw_cell as Dictionary
		var pos: Vector3i = cell.get("pos", Vector3i.ZERO)
		if seen.has(pos): return {"ok": false, "reason": "asset_overlap", "cells": cells}
		seen[pos] = true
		if not world.is_buildable(pos): return {"ok": false, "reason": "outside_buildable_world", "cells": cells}
		if world.has_block(pos): return {"ok": false, "reason": "occupied", "cells": cells}
		if owned_cells.has(pos): return {"ok": false, "reason": "owned_by_asset", "cells": cells}
		if assembly_cells.has(pos) and not _assembly_accepts_asset(pos, template.structure_id, posmod(rotation, 4)):
			return {"ok": false, "reason": "assembly_reserved", "cells": cells}
	return {"ok": true, "reason": "", "cells": cells}


func place_atomic(asset_id: String, pivot_world: Vector3i, rotation: int) -> Dictionary:
	var template = registry.get_asset(asset_id) if registry != null else null
	if template == null or (template.asset_kind == "multiblock" and template.placement_mode != "atomic"):
		return {"ok": false, "reason": "asset_unavailable"}
	var check: Dictionary = can_place(template, pivot_world, rotation)
	if not bool(check.get("ok", false)): return check
	var written: Array[Vector3i] = []
	for raw_cell in check.get("cells", []) as Array:
		var cell: Dictionary = raw_cell as Dictionary
		var pos: Vector3i = cell.get("pos", Vector3i.ZERO)
		var kind: String = str(cell.get("kind", ""))
		if kind == "air": continue
		var changed: bool = world.set_micro_cell(pos, cell.get("cell", null)) if kind == "micro" else world.set_block(pos, str(cell.get("block_id", "")))
		if not changed:
			for rollback_pos in written: world.remove_block(rollback_pos)
			return {"ok": false, "reason": "write_failed"}
		written.append(pos)
	var record: Dictionary = {"asset_id": asset_id, "origin": pivot_world, "rotation": posmod(rotation, 4), "state": {}, "assembled": false, "active": true, "cells": written}
	instances[pivot_world] = record
	for pos in written: owned_cells[pos] = pivot_world
	_activate(record)
	return {"ok": true, "reason": "", "cells": written, "root": pivot_world}


func begin_assembly(asset_id: String, anchor_world: Vector3i, rotation: int) -> Dictionary:
	var template = registry.get_asset(asset_id) if registry != null else null
	if template == null or template.asset_kind != "multiblock" or template.placement_mode != "assembled": return {"ok": false, "reason": "asset_unavailable"}
	var check: Dictionary = can_begin_assembly(template, anchor_world, rotation)
	if not bool(check.get("ok", false)): return check
	var requirements: Array = check.get("requirements", []) as Array
	var record: Dictionary = {"asset_id": asset_id, "origin": anchor_world, "rotation": posmod(rotation, 4), "state": {}, "assembled": true, "active": false, "requirements": requirements}
	instances[anchor_world] = record
	for raw_requirement in requirements: assembly_cells[(raw_requirement as Dictionary).get("pos", Vector3i.ZERO)] = anchor_world
	_refresh_assembly(record)
	return {"ok": true, "reason": "", "root": anchor_world, "requirements": requirements}


func can_begin_assembly(template, anchor_world: Vector3i, rotation: int) -> Dictionary:
	if world == null or template == null: return {"ok": false, "reason": "asset_unavailable", "requirements": []}
	var requirements: Array = transformed_requirements(template, anchor_world, rotation)
	for raw_requirement in requirements:
		var requirement: Dictionary = raw_requirement as Dictionary
		var pos: Vector3i = requirement.get("pos", Vector3i.ZERO)
		if not world.is_buildable(pos) or assembly_cells.has(pos): return {"ok": false, "reason": "assembly_overlap", "requirements": requirements}
		if owned_cells.has(pos) and not _requirement_satisfied(requirement): return {"ok": false, "reason": "assembly_overlap", "requirements": requirements}
	return {"ok": true, "reason": "", "requirements": requirements}


func transformed_requirements(template, anchor_world: Vector3i, rotation: int) -> Array:
	var result: Array = []
	var transformed_anchor: Vector3i = template.transform_position(template.anchor, rotation)
	var base_origin: Vector3i = anchor_world - transformed_anchor
	for raw_requirement in template.requirements:
		var requirement: Dictionary = (raw_requirement as Dictionary).duplicate(true)
		var local: Vector3i = StructureTemplateScript._vector3i_from_value(requirement.get("pos", []))
		requirement["pos"] = base_origin + template.transform_position(local, rotation)
		requirement["rotation"] = posmod(rotation + int(requirement.get("rotation", 0)), 4)
		result.append(requirement)
	return result


func assembled_anchor_piece_rotation(template, assembly_rotation: int) -> int:
	if template == null: return posmod(assembly_rotation, 4)
	for raw_requirement in template.requirements:
		var requirement: Dictionary = raw_requirement as Dictionary
		if StructureTemplateScript._vector3i_from_value(requirement.get("pos", [])) == template.anchor:
			return posmod(assembly_rotation + int(requirement.get("rotation", 0)), 4)
	return posmod(assembly_rotation, 4)


func notify_world_changed(pos: Vector3i) -> void:
	if assembly_cells.has(pos):
		var record: Dictionary = instances.get(assembly_cells[pos], {}) as Dictionary
		if not record.is_empty(): _refresh_assembly(record)


func get_instance_at(pos: Vector3i) -> Dictionary:
	var root: Variant = assembly_cells.get(pos, owned_cells.get(pos, null))
	return instances.get(root, {}) as Dictionary if root != null else {}


func missing_requirements_at(pos: Vector3i) -> Array:
	var record: Dictionary = get_instance_at(pos)
	if record.is_empty() or not bool(record.get("assembled", false)): return []
	var result: Array = []
	for raw_requirement in record.get("requirements", []) as Array:
		var requirement: Dictionary = raw_requirement as Dictionary
		if not _requirement_satisfied(requirement): result.append(requirement)
	return result


func nearest_missing_assembly(world_position: Vector3, max_distance: float = 14.0) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance: float = max_distance
	for raw_root in instances.keys():
		var record: Dictionary = instances[raw_root] as Dictionary
		if not bool(record.get("assembled", false)) or bool(record.get("active", false)): continue
		var distance: float = world_position.distance_to(Vector3(raw_root as Vector3i))
		if distance > nearest_distance: continue
		var missing: Array = []
		for raw_requirement in record.get("requirements", []) as Array:
			var requirement: Dictionary = raw_requirement as Dictionary
			if not _requirement_satisfied(requirement): missing.append(requirement)
		if missing.is_empty(): continue
		nearest_distance = distance
		nearest = {"asset_id": record.get("asset_id", ""), "origin": raw_root, "rotation": record.get("rotation", 0), "requirements": missing}
	return nearest


func remove_owned_at(pos: Vector3i) -> Dictionary:
	if not owned_cells.has(pos): return {"ok": false}
	var root: Vector3i = owned_cells[pos]
	var record: Dictionary = instances.get(root, {}) as Dictionary
	if record.is_empty(): return {"ok": false}
	_deactivate(record)
	var removed: Array = []
	for raw_pos in record.get("cells", []) as Array:
		var cell_pos: Vector3i = raw_pos
		if world.remove_block(cell_pos): removed.append(cell_pos)
		owned_cells.erase(cell_pos)
	instances.erase(root)
	return {"ok": true, "asset_id": str(record.get("asset_id", "")), "root": root, "removed": removed}


func interact_at(pos: Vector3i, player: Node) -> Dictionary:
	var record: Dictionary = get_instance_at(pos)
	if record.is_empty() or not bool(record.get("active", false)): return {"handled": false}
	var template = registry.get_asset(str(record.get("asset_id", "")))
	var utility_id: String = template.utility_id if template != null else ""
	var handler: Object = utility_handlers.get(utility_id, null)
	if handler == null:
		_warn_missing_utility(utility_id, str(record.get("asset_id", "")))
		return {"handled": true, "message": "Utilidade ainda nao registrada: %s" % utility_id}
	if handler.has_method("interact"): handler.call("interact", record, player)
	return {"handled": true, "message": ""}


func build_save_data() -> Array:
	var rows: Array = []
	for raw_root in _sorted_roots():
		var root: Vector3i = raw_root
		var record: Dictionary = instances[root] as Dictionary
		var template = registry.get_asset(str(record.get("asset_id", ""))) if registry != null else null
		var handler: Object = utility_handlers.get(template.utility_id, null) if template != null else null
		if handler != null and handler.has_method("save_state"):
			var saved_state: Variant = handler.call("save_state", record)
			if typeof(saved_state) == TYPE_DICTIONARY: record["state"] = (saved_state as Dictionary).duplicate(true)
		rows.append({
			"asset_id": str(record.get("asset_id", "")), "origin": [root.x, root.y, root.z],
			"rotation": int(record.get("rotation", 0)), "state": (record.get("state", {}) as Dictionary).duplicate(true),
			"assembled": bool(record.get("assembled", false)), "active": bool(record.get("active", false)),
		})
	return rows


func _sorted_roots() -> Array:
	var roots: Array = instances.keys()
	roots.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return a.x < b.x if a.x != b.x else (a.y < b.y if a.y != b.y else a.z < b.z)
	)
	return roots


func load_save_data(rows: Array) -> bool:
	instances.clear(); owned_cells.clear(); assembly_cells.clear()
	for raw_row in rows:
		if typeof(raw_row) != TYPE_DICTIONARY: return false
		var row: Dictionary = raw_row as Dictionary
		var asset_id: String = str(row.get("asset_id", ""))
		var template = registry.get_asset(asset_id) if registry != null else null
		if template == null: return false
		var root: Vector3i = StructureTemplateScript._vector3i_from_value(row.get("origin", []), Vector3i(999999, 999999, 999999))
		var rotation: int = posmod(int(row.get("rotation", 0)), 4)
		var assembled: bool = bool(row.get("assembled", false))
		var record: Dictionary = {"asset_id": asset_id, "origin": root, "rotation": rotation, "state": (row.get("state", {}) as Dictionary).duplicate(true), "assembled": assembled, "active": false}
		if assembled:
			record["requirements"] = transformed_requirements(template, root, rotation)
			for raw_requirement in record["requirements"] as Array: assembly_cells[(raw_requirement as Dictionary).get("pos", Vector3i.ZERO)] = root
			instances[root] = record; _refresh_assembly(record)
		else:
			var cells: Array[Vector3i] = []
			for raw_cell in transformed_cells(template, root, rotation):
				var cell: Dictionary = raw_cell as Dictionary
				if str(cell.get("kind", "")) == "air": continue
				var pos: Vector3i = cell.get("pos", Vector3i.ZERO); cells.append(pos); owned_cells[pos] = root
			record["cells"] = cells; record["active"] = true; instances[root] = record
	return true


func _append_transformed_cells(output: Array, template, pivot_world: Vector3i, rotation: int, visiting: Dictionary) -> void:
	if visiting.has(template.structure_id): return
	visiting[template.structure_id] = true
	var transformed_pivot: Vector3i = template.transform_position(template.pivot, rotation)
	var base_origin: Vector3i = pivot_world - transformed_pivot
	for raw_local in template.blocks.keys():
		var local: Vector3i = raw_local
		output.append({"pos": base_origin + template.transform_position(local, rotation), "kind": "block", "block_id": str(template.blocks[local])})
	for raw_local in template.micro_cells.keys():
		var local: Vector3i = raw_local
		output.append({"pos": base_origin + template.transform_position(local, rotation), "kind": "micro", "cell": template.micro_cells[local].transformed(rotation)})
	for raw_local in template.explicit_air.keys():
		var local: Vector3i = raw_local
		output.append({"pos": base_origin + template.transform_position(local, rotation), "kind": "air"})
	for raw_component in template.components:
		var component: Dictionary = raw_component as Dictionary
		var child = registry.get_asset(str(component.get("asset_id", ""))) if registry != null else null
		if child == null: continue
		var local: Vector3i = StructureTemplateScript._vector3i_from_value(component.get("pos", []))
		var child_pivot: Vector3i = base_origin + template.transform_position(local, rotation)
		_append_transformed_cells(output, child, child_pivot, rotation + int(component.get("rotation", 0)), visiting.duplicate())


func _refresh_assembly(record: Dictionary) -> void:
	var complete: bool = true
	var any_piece: bool = false
	for raw_requirement in record.get("requirements", []) as Array:
		var requirement: Dictionary = raw_requirement as Dictionary
		var satisfied: bool = _requirement_satisfied(requirement)
		complete = complete and satisfied; any_piece = any_piece or satisfied
	var was_active: bool = bool(record.get("active", false))
	record["active"] = complete
	if complete and not was_active: _activate(record)
	elif was_active and not complete: _deactivate(record)
	if not any_piece:
		var root: Vector3i = record.get("origin", Vector3i.ZERO)
		for raw_requirement in record.get("requirements", []) as Array: assembly_cells.erase((raw_requirement as Dictionary).get("pos", Vector3i.ZERO))
		instances.erase(root)


func _requirement_satisfied(requirement: Dictionary) -> bool:
	var pos: Vector3i = requirement.get("pos", Vector3i.ZERO)
	var asset_id: String = str(requirement.get("asset_id", ""))
	if asset_id != "":
		var record: Dictionary = instances.get(owned_cells.get(pos, null), {}) as Dictionary
		return str(record.get("asset_id", "")) == asset_id and int(record.get("rotation", -1)) == int(requirement.get("rotation", 0))
	return world.get_block_id(pos) == str(requirement.get("block_id", ""))


func _assembly_accepts_asset(pos: Vector3i, asset_id: String, rotation: int) -> bool:
	var record: Dictionary = instances.get(assembly_cells.get(pos, null), {}) as Dictionary
	for raw_requirement in record.get("requirements", []) as Array:
		var requirement: Dictionary = raw_requirement as Dictionary
		if requirement.get("pos", Vector3i.ZERO) == pos and str(requirement.get("asset_id", "")) == asset_id and int(requirement.get("rotation", 0)) == rotation:
			return not _requirement_satisfied(requirement)
	return false


func _activate(record: Dictionary) -> void:
	var template = registry.get_asset(str(record.get("asset_id", ""))) if registry != null else null
	if template == null or template.utility_id == "": return
	var handler: Object = utility_handlers.get(template.utility_id, null)
	if handler == null: _warn_missing_utility(template.utility_id, template.structure_id)
	elif handler.has_method("activated"): handler.call("activated", record)


func _deactivate(record: Dictionary) -> void:
	var template = registry.get_asset(str(record.get("asset_id", ""))) if registry != null else null
	if template == null or template.utility_id == "": return
	var handler: Object = utility_handlers.get(template.utility_id, null)
	if handler != null and handler.has_method("deactivated"): handler.call("deactivated", record)


func _warn_missing_utility(utility_id: String, asset_id: String) -> void:
	if utility_id == "" or warned_utilities.has(utility_id): return
	warned_utilities[utility_id] = true
	push_warning("Asset %s carregado sem utilidade registrada para utility_id=%s." % [asset_id, utility_id])
