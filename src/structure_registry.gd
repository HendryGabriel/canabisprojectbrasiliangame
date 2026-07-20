class_name StructureRegistry
extends RefCounted


const FORMAT: String = "trumancraft_structure_registry"
const VERSION: int = 1
const StructureTemplateScript = preload("res://src/structure_template_data.gd")
const SpawnGraphScript = preload("res://src/structure_spawn_graph.gd")
const BlockCatalogScript = preload("res://src/block_catalog.gd")


var entries: Dictionary = {} # template id -> normalized rule
var embedded_profiles: Array = [] # V2 assets discovered below data/structures.
var assets: Dictionary = {} # every valid V4 template id -> StructureTemplateData
var asset_paths: Dictionary = {}
var invalid_asset_ids: Dictionary = {}
var diagnostics: Array[String] = []
var source_path: String = ""


static func empty_registry():
	return (load("res://src/structure_registry.gd") as Script).new()


static func load_from_file(path: String):
	if not FileAccess.file_exists(path):
		var discovered_registry = empty_registry()
		discovered_registry.source_path = path
		discovered_registry.discover_directory(path.get_base_dir())
		return discovered_registry
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = parsed as Dictionary
	if str(data.get("format", "")) != FORMAT or int(data.get("version", 0)) != VERSION:
		return null
	var registry = (load("res://src/structure_registry.gd") as Script).new()
	registry.source_path = path
	var raw_entries: Variant = data.get("entries", [])
	if typeof(raw_entries) == TYPE_ARRAY:
		for raw_entry in raw_entries as Array:
			if typeof(raw_entry) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = _normalized_rule(raw_entry as Dictionary)
			var template_id: String = str(entry.get("id", ""))
			if template_id != "":
				registry.entries[template_id] = entry
	registry.discover_directory(path.get_base_dir())
	return registry


func get_rule(template_id: String) -> Dictionary:
	for raw_rule in embedded_profiles:
		var rule: Dictionary = raw_rule as Dictionary
		if str(rule.get("id", "")) == template_id:
			return _anchor_rule_from_embedded(rule)
	if entries.has(template_id):
		return (entries[template_id] as Dictionary).duplicate(true)
	return {}


func get_rules() -> Array:
	var embedded_ids: Dictionary = {}
	for raw_rule in embedded_profiles:
		embedded_ids[str((raw_rule as Dictionary).get("id", ""))] = true
	var rules: Array = []
	for template_id in entries.keys():
		if not embedded_ids.has(str(template_id)):
			rules.append(entries[template_id])
	rules.append_array(embedded_profiles)
	return rules


func get_asset(asset_id: String):
	return assets.get(asset_id, null) if not invalid_asset_ids.has(asset_id) else null


func get_placeable_assets() -> Array:
	var result: Array = []
	var ids: Array = assets.keys(); ids.sort()
	for raw_id in ids:
		var asset_id: String = str(raw_id)
		var template = get_asset(asset_id)
		if template != null and template.asset_kind in ["custom_block", "multiblock"]: result.append(template)
	return result


func discover_directory(path: String) -> void:
	embedded_profiles.clear()
	assets.clear()
	asset_paths.clear()
	invalid_asset_ids.clear()
	diagnostics.clear()
	_discover_recursive(path)
	_validate_asset_links()
	embedded_profiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: String = "%s::%s" % [a.get("id", ""), a.get("profile_id", "")]
		var right: String = "%s::%s" % [b.get("id", ""), b.get("profile_id", "")]
		return left < right
	)


func validate() -> Array[String]:
	var errors: Array[String] = []
	for template_id in entries.keys():
		var rule: Dictionary = entries[template_id] as Dictionary
		if str(rule.get("path", "")) == "":
			errors.append("Template %s sem path." % template_id)
		if str(rule.get("mode", "")) not in ["surface_adaptive", "cave_floor", "underground", "buried"]:
			errors.append("Template %s com modo invalido." % template_id)
	return errors


func get_diagnostics() -> Array[String]:
	return diagnostics.duplicate()


func content_hash() -> String:
	var rows: Array = []
	var ids: Array = entries.keys()
	ids.sort()
	for template_id in ids:
		rows.append(entries[template_id])
	var embedded_rows: Array = []
	for raw_rule in embedded_profiles:
		var rule: Dictionary = raw_rule as Dictionary
		embedded_rows.append({"id": rule.get("id", ""), "profile_id": rule.get("profile_id", ""), "path": rule.get("path", ""), "template_hash": rule.get("template_hash", "")})
	var asset_rows: Array = []
	var asset_ids: Array = assets.keys(); asset_ids.sort()
	for raw_id in asset_ids:
		var asset_id: String = str(raw_id)
		if not invalid_asset_ids.has(asset_id): asset_rows.append([asset_id, assets[asset_id].content_hash()])
	return JSON.stringify({"format": FORMAT, "version": VERSION, "entries": rows, "embedded": embedded_rows, "assets": asset_rows}).sha256_text()


func _discover_recursive(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name: String = directory.get_next()
	while name != "":
		if name != "." and name != "..":
			var child_path: String = path.path_join(name)
			if directory.current_is_dir():
				_discover_recursive(child_path)
			elif name.ends_with(".tstructure.json"):
				_register_embedded_asset(child_path)
		name = directory.get_next()
	directory.list_dir_end()


func _register_embedded_asset(path: String) -> void:
	var template = StructureTemplateScript.load_from_file(path)
	if template == null:
		diagnostics.append("Asset de estrutura invalido ignorado: %s." % path)
		return
	var template_errors: Array[String] = template.validate(BlockCatalogScript.blocks())
	if not template_errors.is_empty():
		diagnostics.append("Asset %s ignorado: %s" % [path, "; ".join(template_errors)])
		return
	var duplicate_asset: bool = assets.has(template.structure_id) or invalid_asset_ids.has(template.structure_id)
	if duplicate_asset:
		invalid_asset_ids[template.structure_id] = true
		assets.erase(template.structure_id); asset_paths.erase(template.structure_id)
		embedded_profiles = embedded_profiles.filter(func(row: Dictionary) -> bool: return str(row.get("id", "")) != template.structure_id)
		diagnostics.append("ID %s duplicado; assets conflitantes foram ignorados." % template.structure_id)
		return
	assets[template.structure_id] = template
	asset_paths[template.structure_id] = path
	if template.asset_kind != "structure": return
	for raw_profile in template.spawn_profiles:
		if typeof(raw_profile) != TYPE_DICTIONARY:
			continue
		var profile: Dictionary = raw_profile as Dictionary
		var compiled: Dictionary = SpawnGraphScript.compile(profile)
		var compile_errors: Array = (compiled.get("errors", []) as Array).duplicate()
		embedded_profiles.append({
			"id": template.structure_id,
			"path": path,
			"profile_id": str(profile.get("id", "")),
			"profile": profile.duplicate(true),
			"compiled": compiled,
			"compile_errors": compile_errors,
			"template_hash": template.content_hash(),
			"embedded": true,
		})


func _validate_asset_links() -> void:
	var anchor_owners: Dictionary = {}
	for raw_id in assets.keys():
		var asset_id: String = str(raw_id)
		var template = assets[asset_id]
		for raw_component in template.components:
			var component_id: String = str((raw_component as Dictionary).get("asset_id", ""))
			if not assets.has(component_id): _invalidate_asset(asset_id, "componente desconhecido: %s" % component_id)
		if template.asset_kind != "multiblock" or template.placement_mode != "assembled": continue
		var anchor_item: String = ""
		for raw_requirement in template.requirements:
			var requirement: Dictionary = raw_requirement as Dictionary
			var item_id: String = str(requirement.get("item_id", ""))
			if not BlockCatalogScript.items().has(item_id) and not assets.has(item_id): _invalidate_asset(asset_id, "item de montagem desconhecido: %s" % item_id)
			if StructureTemplateScript._vector3i_from_value(requirement.get("pos", [])) == template.anchor: anchor_item = item_id
		if anchor_item == "":
			_invalidate_asset(asset_id, "a ancora nao possui requisito")
		elif anchor_owners.has(anchor_item):
			_invalidate_asset(asset_id, "item ancora ambiguo: %s" % anchor_item)
			_invalidate_asset(str(anchor_owners[anchor_item]), "item ancora ambiguo: %s" % anchor_item)
		else: anchor_owners[anchor_item] = asset_id
	for raw_id in assets.keys():
		if _has_component_cycle(str(raw_id), str(raw_id), {}): _invalidate_asset(str(raw_id), "ciclo de componentes")
	for raw_id in assets.keys():
		var asset_id: String = str(raw_id)
		for raw_component in assets[asset_id].components:
			var component_id: String = str((raw_component as Dictionary).get("asset_id", ""))
			if invalid_asset_ids.has(component_id): _invalidate_asset(asset_id, "componente invalido: %s" % component_id)


func _has_component_cycle(root_id: String, current_id: String, visiting: Dictionary) -> bool:
	if visiting.has(current_id): return current_id == root_id
	visiting[current_id] = true
	var template = assets.get(current_id, null)
	if template != null:
		for raw_component in template.components:
			if _has_component_cycle(root_id, str((raw_component as Dictionary).get("asset_id", "")), visiting.duplicate()): return true
	return false


func _invalidate_asset(asset_id: String, reason: String) -> void:
	if invalid_asset_ids.has(asset_id): return
	invalid_asset_ids[asset_id] = true
	diagnostics.append("Asset %s ignorado (%s): %s." % [asset_id, asset_paths.get(asset_id, "sem caminho"), reason])


static func _anchor_rule_from_embedded(rule: Dictionary) -> Dictionary:
	var settings: Dictionary = ((rule.get("compiled", {}) as Dictionary).get("settings", {}) as Dictionary)
	return {
		"id": str(rule.get("id", "")), "path": str(rule.get("path", "")),
		"mode": str(settings.get("mode", "surface_adaptive")), "zone_mask": 1,
		"weight": 0.0, "spacing": int(settings.get("spacing", 24)),
		"rotations": (settings.get("rotations", [0]) as Array).duplicate(),
		"allow_mirror_x": float(settings.get("mirror_x_chance", 0.0)) > 0.0,
		"allow_mirror_z": float(settings.get("mirror_z_chance", 0.0)) > 0.0,
		"max_slope": 8, "min_depth": int(settings.get("min_depth", 12)),
		"max_depth": int(settings.get("max_depth", 42)), "minimum_cover": int(settings.get("minimum_cover", 4)),
	}


static func _normalized_rule(raw: Dictionary) -> Dictionary:
	var rotations: Array = raw.get("rotations", [0, 1, 2, 3]) as Array
	var normalized_rotations: Array[int] = []
	for value in rotations:
		var rotation: int = posmod(int(value), 4)
		if not normalized_rotations.has(rotation):
			normalized_rotations.append(rotation)
	return {
		"id": str(raw.get("id", "")),
		"path": str(raw.get("path", "")),
		"mode": str(raw.get("mode", "surface_adaptive")),
		"zone_mask": int(raw.get("zone_mask", 1)),
		"weight": clampf(float(raw.get("weight", 0.0)), 0.0, 1.0),
		"spacing": maxi(4, int(raw.get("spacing", 24))),
		"rotations": normalized_rotations,
		"allow_mirror_x": bool(raw.get("allow_mirror_x", false)),
		"allow_mirror_z": bool(raw.get("allow_mirror_z", false)),
		"max_slope": maxi(0, int(raw.get("max_slope", 8))),
		"max_support_depth": maxi(0, int(raw.get("max_support_depth", 24))),
		"min_depth": maxi(4, int(raw.get("min_depth", 12))),
		"max_depth": maxi(5, int(raw.get("max_depth", 42))),
		"minimum_cover": maxi(1, int(raw.get("minimum_cover", 4))),
	}

