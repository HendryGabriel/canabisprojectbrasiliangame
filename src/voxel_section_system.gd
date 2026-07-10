## Runtime owner for fixed voxel section meshes and static collision shapes.
##
## CPU meshing is performed in WorkerThreadPool tasks.  All scene-tree and GPU
## work remains in this Node on the main thread.
class_name VoxelSectionSystem
extends Node3D


const VoxelWorldScript = preload("res://src/voxel_world.gd")
const VoxelSectionMesherScript = preload("res://src/voxel_section_mesher.gd")
const PerformanceProfileScript = preload("res://src/performance_profile.gd")

class MeshBuildJob extends RefCounted:
	var snapshot: Dictionary
	var render_palette: Dictionary
	var voxel_ao_enabled: bool
	var micro_density: int
	var result: Dictionary = {}

	func _init(p_snapshot: Dictionary, p_render_palette: Dictionary, p_voxel_ao_enabled: bool, p_micro_density: int) -> void:
		snapshot = p_snapshot
		render_palette = p_render_palette
		voxel_ao_enabled = p_voxel_ao_enabled
		micro_density = p_micro_density

	func run() -> void:
		result = VoxelSectionMesherScript.build(snapshot, render_palette, voxel_ao_enabled, micro_density)


class SectionState extends RefCounted:
	var root: Node3D
	var opaque: MeshInstance3D
	var cutout: MeshInstance3D
	var transparent: MeshInstance3D
	var micro_foliage: MeshInstance3D
	var body: StaticBody3D
	var collision: CollisionShape3D
	var applied_revision: int = -1


const GAMEPLAY_WORKER_LIMIT: int = 2
const LOADING_WORKER_LIMIT: int = 3
const GAMEPLAY_APPLY_LIMIT: int = 1
const LOADING_APPLY_LIMIT: int = 6
const GAMEPLAY_APPLY_BUDGET_USEC: int = 1000
const LOADING_APPLY_BUDGET_USEC: int = 12000


var _world
var _render_palette: Dictionary = {}
var _material_provider: Callable
var _voxel_ao_enabled: bool = true
var _micro_density: int = 4
var _micro_visibility_distance: float = 80.0
var _micro_shadows_enabled: bool = true
var _pending: Dictionary = {} # Vector3i -> priority
var _in_flight: Dictionary = {} # task id -> MeshBuildJob
var _in_flight_sections: Dictionary = {} # Vector3i -> task id
var _ready_results: Array = []
var _sections: Dictionary = {} # Vector3i -> SectionState
var _loading_total: int = 0
var _loading_completed: int = 0
var _shutting_down: bool = false


func setup(world, material_provider: Callable, voxel_ao_enabled: bool = true) -> void:
	_world = world
	_render_palette = world.get_render_palette() if world != null else {}
	_material_provider = material_provider
	_voxel_ao_enabled = voxel_ao_enabled


func set_voxel_ao_enabled(enabled: bool) -> void:
	if _voxel_ao_enabled == enabled:
		return
	_voxel_ao_enabled = enabled
	queue_rebuild_all(true)


func configure_micro_foliage(density: int, visibility_distance: float, shadows_enabled: bool) -> void:
	var normalized_density: int = 4 if density >= 4 else 2
	var rebuild: bool = normalized_density != _micro_density
	_micro_density = normalized_density
	_micro_visibility_distance = maxf(0.0, visibility_distance)
	_micro_shadows_enabled = shadows_enabled
	for raw_state in _sections.values():
		var state: SectionState = raw_state as SectionState
		if state.micro_foliage != null:
			state.micro_foliage.visibility_range_end = _micro_visibility_distance
			state.micro_foliage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _micro_shadows_enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if rebuild: queue_rebuild_all(true)


func queue_rebuild_all(high_priority: bool = false) -> void:
	if _world == null:
		return
	_loading_total = 0
	_loading_completed = 0
	for raw_section in _world.get_nonempty_sections():
		queue_section(raw_section as Vector3i, high_priority)
		_loading_total += 1
	# Existing visual sections may become empty after a reset or save import.
	for raw_section in _sections.keys():
		queue_section(raw_section as Vector3i, high_priority)


func queue_sections(sections: Array, high_priority: bool = true) -> void:
	for raw_section in sections:
		if raw_section is Vector3i:
			queue_section(raw_section as Vector3i, high_priority)


func queue_section(section: Vector3i, high_priority: bool = true) -> void:
	if _world == null or not _world.is_valid_section(section):
		return
	var priority: int = 2 if high_priority else 1
	_pending[section] = max(priority, int(_pending.get(section, 0)))


func process_updates(loading: bool = false) -> void:
	if _shutting_down or _world == null:
		return
	_poll_finished_jobs()
	_start_jobs(LOADING_WORKER_LIMIT if loading else GAMEPLAY_WORKER_LIMIT)
	_apply_ready_results(
		LOADING_APPLY_LIMIT if loading else GAMEPLAY_APPLY_LIMIT,
		LOADING_APPLY_BUDGET_USEC if loading else GAMEPLAY_APPLY_BUDGET_USEC
	)


func is_idle() -> bool:
	return _pending.is_empty() and _in_flight.is_empty() and _ready_results.is_empty()


func get_loading_progress() -> float:
	if _loading_total <= 0:
		return 1.0 if is_idle() else 0.0
	return clamp(float(_loading_completed) / float(_loading_total), 0.0, 1.0)


func get_section_root() -> Node3D:
	return self


func shutdown() -> void:
	_shutting_down = true
	for task_id in _in_flight.keys():
		WorkerThreadPool.wait_for_task_completion(int(task_id))
	_in_flight.clear()
	_in_flight_sections.clear()
	_pending.clear()
	_ready_results.clear()


func _exit_tree() -> void:
	shutdown()


func _poll_finished_jobs() -> void:
	var finished_ids: Array = []
	for raw_task_id in _in_flight.keys():
		var task_id: int = int(raw_task_id)
		if WorkerThreadPool.is_task_completed(task_id):
			finished_ids.append(task_id)
	for task_id in finished_ids:
		WorkerThreadPool.wait_for_task_completion(task_id)
		var job: MeshBuildJob = _in_flight.get(task_id, null) as MeshBuildJob
		_in_flight.erase(task_id)
		if job == null:
			continue
		var section: Vector3i = job.snapshot.get("section", Vector3i.ZERO)
		_in_flight_sections.erase(section)
		var built_revision: int = int(job.snapshot.get("revision", -1))
		if built_revision != _world.get_section_revision(section):
			queue_section(section, true)
			continue
		_ready_results.append(job.result)


func _start_jobs(max_workers: int) -> void:
	while _in_flight.size() < max_workers and not _pending.is_empty():
		var section: Vector3i = _take_next_pending()
		if section == Vector3i(-999, -999, -999):
			return
		if _in_flight_sections.has(section):
			continue
		var snapshot: Dictionary = _world.make_section_snapshot(section)
		var job: MeshBuildJob = MeshBuildJob.new(snapshot, _render_palette, _voxel_ao_enabled, _micro_density)
		var task_id: int = WorkerThreadPool.add_task(job.run, false, "VoxelMesh_%s_%s_%s" % [section.x, section.y, section.z])
		_in_flight[task_id] = job
		_in_flight_sections[section] = task_id


func _take_next_pending() -> Vector3i:
	var selected: Vector3i = Vector3i(-999, -999, -999)
	var selected_priority: int = -1
	for raw_section in _pending.keys():
		var priority: int = int(_pending[raw_section])
		if priority > selected_priority:
			selected = raw_section as Vector3i
			selected_priority = priority
	if selected_priority >= 0:
		_pending.erase(selected)
	return selected


func _apply_ready_results(max_results: int, budget_usec: int) -> void:
	var applied: int = 0
	var started_usec: int = Time.get_ticks_usec()
	while applied < max_results and not _ready_results.is_empty():
		var result: Dictionary = _ready_results.pop_front() as Dictionary
		var section: Vector3i = result.get("section", Vector3i.ZERO)
		if int(result.get("revision", -1)) != _world.get_section_revision(section):
			queue_section(section, true)
			continue
		_apply_result(section, result)
		_loading_completed += 1
		applied += 1
		if Time.get_ticks_usec() - started_usec >= budget_usec:
			break


func _apply_result(section: Vector3i, result: Dictionary) -> void:
	var state: SectionState = _get_or_create_section(section)
	state.opaque.mesh = _build_mesh(result.get("opaque", []) as Array)
	state.cutout.mesh = _build_mesh(result.get("cutout", []) as Array)
	state.transparent.mesh = _build_mesh(result.get("transparent", []) as Array)
	state.micro_foliage.mesh = _build_mesh(result.get("micro_foliage", []) as Array)
	state.cutout.visible = state.cutout.mesh != null
	state.transparent.visible = state.transparent.mesh != null
	state.opaque.visible = state.opaque.mesh != null
	state.micro_foliage.visible = state.micro_foliage.mesh != null

	var collision_faces: PackedVector3Array = result.get("collision_faces", PackedVector3Array()) as PackedVector3Array
	if collision_faces.is_empty():
		state.collision.shape = null
		state.collision.disabled = true
	else:
		var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
		shape.set_faces(collision_faces)
		state.collision.shape = shape
		state.collision.disabled = false
	state.applied_revision = int(result.get("revision", 0))


func _get_or_create_section(section: Vector3i) -> SectionState:
	if _sections.has(section):
		return _sections[section] as SectionState
	var state: SectionState = SectionState.new()
	state.root = Node3D.new()
	state.root.name = "VoxelSection_%s_%s_%s" % [section.x, section.y, section.z]
	state.root.position = Vector3(_world.get_section_origin(section))
	add_child(state.root)

	state.opaque = MeshInstance3D.new()
	state.opaque.name = "Opaque"
	state.opaque.add_to_group(PerformanceProfileScript.SECTION_GROUP)
	state.root.add_child(state.opaque)

	state.cutout = MeshInstance3D.new()
	state.cutout.name = "Cutout"
	state.cutout.add_to_group(PerformanceProfileScript.SECTION_GROUP)
	state.cutout.add_to_group(PerformanceProfileScript.FOLIAGE_GROUP)
	state.cutout.set_meta(PerformanceProfileScript.FOLIAGE_META, true)
	state.root.add_child(state.cutout)

	state.transparent = MeshInstance3D.new()
	state.transparent.name = "Transparent"
	state.transparent.add_to_group(PerformanceProfileScript.SECTION_GROUP)
	state.root.add_child(state.transparent)

	state.micro_foliage = MeshInstance3D.new()
	state.micro_foliage.name = "MicroFoliage"
	state.micro_foliage.add_to_group(PerformanceProfileScript.SECTION_GROUP)
	state.micro_foliage.add_to_group(PerformanceProfileScript.FOLIAGE_GROUP)
	state.micro_foliage.set_meta(PerformanceProfileScript.FOLIAGE_META, true)
	state.micro_foliage.visibility_range_end = _micro_visibility_distance
	state.micro_foliage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _micro_shadows_enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	state.root.add_child(state.micro_foliage)

	state.body = StaticBody3D.new()
	state.body.name = "VoxelCollision"
	state.body.collision_layer = 1
	state.body.collision_mask = 1
	state.collision = CollisionShape3D.new()
	state.body.add_child(state.collision)
	state.root.add_child(state.body)
	_sections[section] = state
	return state


func _build_mesh(surfaces: Array) -> ArrayMesh:
	if surfaces.is_empty():
		return null
	var mesh: ArrayMesh = ArrayMesh.new()
	for raw_surface in surfaces:
		if typeof(raw_surface) != TYPE_DICTIONARY:
			continue
		var surface: Dictionary = raw_surface as Dictionary
		var arrays: Array = surface.get("arrays", []) as Array
		if arrays.is_empty() or arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var surface_index: int = mesh.get_surface_count() - 1
		if _material_provider.is_valid():
			var material: Material = _material_provider.call(surface) as Material
			if material != null:
				mesh.surface_set_material(surface_index, material)
	return mesh if mesh.get_surface_count() > 0 else null
