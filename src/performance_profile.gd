## Manual graphics-quality presets for the finite voxel renderer.
##
## `HIGH` is intentionally non-destructive: it restores the rendering values that
## were present before this object applied `PERFORMANCE`. `PERFORMANCE` keeps voxel
## ambient occlusion under the caller's control while reducing the most expensive
## scene-level effects. Attach generated section meshes below `section_root` and
## tag foliage geometry with the `foliage` group (or `voxel_foliage` metadata) for
## foliage-shadow control.
class_name PerformanceProfile
extends RefCounted


## Stable values saved in user settings. Do not reorder these values.
enum Preset {
	HIGH,
	PERFORMANCE,
}


const CONFIG_SECTION: String = "video"
const CONFIG_KEY: String = "performance_preset"

## A section root should contain only world section render instances. Every
## GeometryInstance3D below it receives the visibility-distance override.
const SECTION_GROUP: StringName = &"voxel_section"
## Mark cutout foliage MeshInstance3D nodes with this group.
const FOLIAGE_GROUP: StringName = &"foliage"
const FOLIAGE_META: StringName = &"voxel_foliage"

## Existing high-quality values in main.gd. HIGH restores the captured live values
## instead of forcing these constants, so explicit user rendering settings survive.
const HIGH_LEAF_PARTICLE_MAX: int = 28

## Conservative settings for 1280x720 on the stated minimum-spec target.
const PERFORMANCE_LEAF_PARTICLE_MAX: int = 8
const PERFORMANCE_SUN_SHADOW_DISTANCE: float = 40.0
const PERFORMANCE_MOON_SHADOW_DISTANCE: float = 30.0
const PERFORMANCE_SECTION_VISIBILITY_DISTANCE: float = 48.0
const PERFORMANCE_SECTION_VISIBILITY_MARGIN: float = 8.0


var _preset: int = Preset.HIGH

# Baselines exist only while PERFORMANCE is active. That lets HIGH restore the
# actual scene settings rather than assuming which quality options were enabled.
var _saved_ssao_enabled: Variant = null
var _saved_sun_shadow_distance: float = -1.0
var _saved_moon_shadow_distance: float = -1.0
var _section_baselines: Dictionary = {}
var _foliage_baselines: Dictionary = {}


func _init(initial_preset: int = Preset.HIGH) -> void:
	_preset = sanitize_preset(initial_preset)


## Changes the active preset. Call apply_to() after this to affect a live scene.
func set_preset(value: int) -> void:
	_preset = sanitize_preset(value)


func get_preset() -> int:
	return _preset


func is_performance() -> bool:
	return _preset == Preset.PERFORMANCE


## Returns a serializable name so saved settings do not depend on enum ordering.
func get_preset_name() -> String:
	return preset_name(_preset)


## A caller can use this Dictionary without calling apply_to(), for example to
## update its leaf-particle budget and own section renderer. `null` means preserve
## the current value; voxel AO is deliberately never overridden by this profile.
func get_settings() -> Dictionary:
	if _preset == Preset.PERFORMANCE:
		return {
			"preset": preset_name(_preset),
			"ssao_enabled": false,
			"sun_shadow_max_distance": PERFORMANCE_SUN_SHADOW_DISTANCE,
			"moon_shadow_max_distance": PERFORMANCE_MOON_SHADOW_DISTANCE,
			"section_visibility_distance": PERFORMANCE_SECTION_VISIBILITY_DISTANCE,
			"section_visibility_margin": PERFORMANCE_SECTION_VISIBILITY_MARGIN,
			"foliage_shadows_enabled": false,
			"leaf_particle_max": PERFORMANCE_LEAF_PARTICLE_MAX,
			"micro_foliage_density": 2,
			"micro_foliage_distance": 40.0,
			"micro_foliage_shadows": false,
			"voxel_debris_max": 96,
			"voxel_ao_override": null,
		}
	return {
		"preset": preset_name(_preset),
		"ssao_enabled": null,
		"sun_shadow_max_distance": null,
		"moon_shadow_max_distance": null,
		"section_visibility_distance": null,
		"section_visibility_margin": null,
		"foliage_shadows_enabled": null,
		"leaf_particle_max": HIGH_LEAF_PARTICLE_MAX,
		"micro_foliage_density": 4,
		"micro_foliage_distance": 80.0,
		"micro_foliage_shadows": true,
		"voxel_debris_max": 256,
		"voxel_ao_override": null,
	}


## Reads the selected preset from an existing ConfigFile. Missing or invalid data
## safely falls back to the currently selected preset.
func load_from_config(config: ConfigFile, section: String = CONFIG_SECTION, key: String = CONFIG_KEY) -> int:
	if config == null:
		return _preset
	var stored_value: Variant = config.get_value(section, key, get_preset_name())
	_preset = preset_from_value(stored_value, _preset)
	return _preset


## Writes only this profile's setting, leaving all unrelated ConfigFile values.
func save_to_config(config: ConfigFile, section: String = CONFIG_SECTION, key: String = CONFIG_KEY) -> void:
	if config != null:
		config.set_value(section, key, get_preset_name())


## Convenience loader for a standalone settings file. A missing file is not an
## error because a first launch should retain the default HIGH preset.
func load_from_path(path: String) -> Error:
	var config: ConfigFile = ConfigFile.new()
	var load_error: Error = config.load(path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return load_error
	if load_error == OK:
		load_from_config(config)
	return OK


## Convenience saver that preserves other values already present in the file.
func save_to_path(path: String) -> Error:
	var config: ConfigFile = ConfigFile.new()
	var load_error: Error = config.load(path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return load_error
	save_to_config(config)
	return config.save(path)


## Applies scene-level changes and returns get_settings() for caller-owned systems.
##
## `section_root` is optional. When supplied, all GeometryInstance3D descendants
## are treated as voxel section render geometry. Foliage geometry must be marked
## with FOLIAGE_GROUP or FOLIAGE_META so only foliage loses shadow casting.
func apply_to(
	environment: Environment = null,
	sun: DirectionalLight3D = null,
	moon: DirectionalLight3D = null,
	section_root: Node = null,
) -> Dictionary:
	_prune_freed_baselines()
	var settings: Dictionary = get_settings()
	if _preset == Preset.PERFORMANCE:
		_apply_performance(environment, sun, moon, section_root)
	else:
		_restore_high(environment, sun, moon, section_root)
	return settings


static func sanitize_preset(value: int) -> int:
	return Preset.PERFORMANCE if value == Preset.PERFORMANCE else Preset.HIGH


static func preset_name(value: int) -> String:
	return "performance" if sanitize_preset(value) == Preset.PERFORMANCE else "high"


static func preset_from_value(value: Variant, fallback: int = Preset.HIGH) -> int:
	if value is int:
		return sanitize_preset(int(value))
	var normalized: String = str(value).strip_edges().to_lower()
	match normalized:
		"performance", "perf", "1":
			return Preset.PERFORMANCE
		"high", "0":
			return Preset.HIGH
		_:
			return sanitize_preset(fallback)


func _apply_performance(
	environment: Environment,
	sun: DirectionalLight3D,
	moon: DirectionalLight3D,
	section_root: Node,
) -> void:
	if environment != null:
		if _saved_ssao_enabled == null:
			_saved_ssao_enabled = environment.ssao_enabled
		environment.ssao_enabled = false
	if sun != null:
		if _saved_sun_shadow_distance < 0.0:
			_saved_sun_shadow_distance = sun.directional_shadow_max_distance
		sun.directional_shadow_max_distance = PERFORMANCE_SUN_SHADOW_DISTANCE
	if moon != null:
		if _saved_moon_shadow_distance < 0.0:
			_saved_moon_shadow_distance = moon.directional_shadow_max_distance
		moon.directional_shadow_max_distance = PERFORMANCE_MOON_SHADOW_DISTANCE
	_apply_section_overrides(section_root)


func _restore_high(
	environment: Environment,
	sun: DirectionalLight3D,
	moon: DirectionalLight3D,
	section_root: Node,
) -> void:
	if environment != null and _saved_ssao_enabled != null:
		environment.ssao_enabled = bool(_saved_ssao_enabled)
		_saved_ssao_enabled = null
	if sun != null and _saved_sun_shadow_distance >= 0.0:
		sun.directional_shadow_max_distance = _saved_sun_shadow_distance
		_saved_sun_shadow_distance = -1.0
	if moon != null and _saved_moon_shadow_distance >= 0.0:
		moon.directional_shadow_max_distance = _saved_moon_shadow_distance
		_saved_moon_shadow_distance = -1.0
	_restore_section_overrides(section_root)


func _apply_section_overrides(section_root: Node) -> void:
	for geometry in _section_geometry(section_root):
		_capture_section_baseline(geometry)
		geometry.visibility_range_end = PERFORMANCE_SECTION_VISIBILITY_DISTANCE
		geometry.visibility_range_end_margin = PERFORMANCE_SECTION_VISIBILITY_MARGIN
		if _is_foliage_geometry(geometry):
			_capture_foliage_baseline(geometry)
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _restore_section_overrides(section_root: Node) -> void:
	for geometry in _section_geometry(section_root):
		_restore_section_baseline(geometry)
		_restore_foliage_baseline(geometry)


func _section_geometry(section_root: Node) -> Array[GeometryInstance3D]:
	var result: Array[GeometryInstance3D] = []
	if section_root == null:
		return result
	var pending: Array[Node] = [section_root]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		var geometry: GeometryInstance3D = current as GeometryInstance3D
		if geometry != null:
			result.append(geometry)
		for child in current.get_children():
			if child is Node:
				pending.append(child)
	return result


func _is_foliage_geometry(geometry: GeometryInstance3D) -> bool:
	return geometry.is_in_group(FOLIAGE_GROUP) or bool(geometry.get_meta(FOLIAGE_META, false))


func _capture_section_baseline(geometry: GeometryInstance3D) -> void:
	var id: int = geometry.get_instance_id()
	if _section_baselines.has(id):
		return
	_section_baselines[id] = {
		"node": weakref(geometry),
		"visibility_range_end": geometry.visibility_range_end,
		"visibility_range_end_margin": geometry.visibility_range_end_margin,
	}


func _restore_section_baseline(geometry: GeometryInstance3D) -> void:
	var id: int = geometry.get_instance_id()
	if not _section_baselines.has(id):
		return
	var baseline: Dictionary = _section_baselines[id]
	geometry.visibility_range_end = float(baseline["visibility_range_end"])
	geometry.visibility_range_end_margin = float(baseline["visibility_range_end_margin"])
	_section_baselines.erase(id)


func _capture_foliage_baseline(geometry: GeometryInstance3D) -> void:
	var id: int = geometry.get_instance_id()
	if _foliage_baselines.has(id):
		return
	_foliage_baselines[id] = {
		"node": weakref(geometry),
		"cast_shadow": geometry.cast_shadow,
	}


func _restore_foliage_baseline(geometry: GeometryInstance3D) -> void:
	var id: int = geometry.get_instance_id()
	if not _foliage_baselines.has(id):
		return
	var baseline: Dictionary = _foliage_baselines[id]
	geometry.cast_shadow = int(baseline["cast_shadow"])
	_foliage_baselines.erase(id)


func _prune_freed_baselines() -> void:
	_prune_baseline_dictionary(_section_baselines)
	_prune_baseline_dictionary(_foliage_baselines)


func _prune_baseline_dictionary(baselines: Dictionary) -> void:
	var stale_ids: Array = []
	for raw_id in baselines:
		var baseline: Dictionary = baselines[raw_id]
		var reference: WeakRef = baseline.get("node") as WeakRef
		if reference == null or reference.get_ref() == null:
			stale_ids.append(raw_id)
	for raw_id in stale_ids:
		baselines.erase(raw_id)
