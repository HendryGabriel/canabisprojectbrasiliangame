extends Node3D
class_name DroppedItem

const MAX_LIFETIME_SECONDS: float = 90.0

var item_id: String = ""
var count: int = 1
var slot_data: Dictionary = {}
var velocity: Vector3 = Vector3.ZERO
var on_ground: bool = false
var time_alive: float = 0.0
var main_game: Node = null

# Visual child
var visual: Node3D = null

func configure(p_main: Node, p_item_id: String, p_count: int, p_pos: Vector3, p_vel: Vector3, p_data: Dictionary = {}) -> void:
	main_game = p_main
	item_id = p_item_id
	count = p_count
	slot_data = {"item": p_item_id, "count": p_count}
	if not p_data.is_empty(): slot_data["data"] = p_data.duplicate(true)
	global_position = p_pos
	velocity = p_vel
	_create_visuals()

func _create_visuals() -> void:
	# Check if item_id is a block
	var is_block: bool = false
	if main_game != null and main_game.block_defs.has(item_id):
		is_block = true
		
	if is_block:
		# Create a small 3D block using the exact same block mesh
		visual = MeshInstance3D.new()
		visual.mesh = main_game._block_mesh(item_id)
		visual.scale = Vector3(0.25, 0.25, 0.25)
		add_child(visual)
	else:
		# Create a 2D Sprite3D
		var sprite = Sprite3D.new()
		var icon_texture = main_game._item_icon(item_id)
		if icon_texture != null:
			sprite.texture = icon_texture
		sprite.pixel_size = 0.015
		sprite.billboard = StandardMaterial3D.BILLBOARD_ENABLED
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		visual = sprite
		add_child(visual)

func _process(delta: float) -> void:
	time_alive += delta
	if time_alive >= MAX_LIFETIME_SECONDS:
		if main_game != null and "dropped_items" in main_game:
			main_game.dropped_items.erase(self)
		queue_free()
		return
	
	# Apply rotation to visual if it is a 3D block (Sprite3D is billboarded)
	if visual is MeshInstance3D:
		visual.rotate_y(delta * 2.0)
		visual.rotate_x(delta * 0.5)
		
	# Floating animation (bobbing)
	var bob_offset: float = sin(time_alive * 4.0) * 0.05
	visual.position.y = bob_offset
	
	if not on_ground:
		# Apply gravity
		velocity.y -= 9.8 * delta
		# Apply air resistance horizontally
		velocity.x *= 0.95
		velocity.z *= 0.95
		
		global_position += velocity * delta
		
		# Collision check against terrain blocks
		var block_x = int(floor(global_position.x))
		var block_y = int(floor(global_position.y - 0.15))
		var block_z = int(floor(global_position.z))
		var pos_below = Vector3i(block_x, block_y, block_z)
		
		if main_game != null and main_game.has_method("_is_solid_block_at"):
			if main_game._is_solid_block_at(pos_below):
				# Landed!
				on_ground = true
				velocity = Vector3.ZERO
				global_position.y = float(block_y) + 0.5 + 0.15 # Snap to top of block + half item height
	else:
		# Slide check: what if the block underneath was removed?
		var block_x = int(floor(global_position.x))
		var block_y = int(floor(global_position.y - 0.15))
		var block_z = int(floor(global_position.z))
		var pos_below = Vector3i(block_x, block_y, block_z)
		if main_game == null or not main_game.has_method("_is_solid_block_at") or not main_game._is_solid_block_at(pos_below):
			on_ground = false
			
	# Pickup logic
	if main_game != null and main_game.player != null:
		var player_node = main_game.player
		var dist = global_position.distance_to(player_node.global_position)
		
		if dist < 2.0:
			# Pull towards player (magnet effect)
			var target_pos = player_node.global_position + Vector3(0, 0.5, 0)
			global_position = global_position.move_toward(target_pos, delta * 4.0)
			
		if dist < 0.6:
			# Collect item
			var success = main_game._add_item_slot(slot_data)
			if success:
				main_game._message("Coletado: %s x%s" % [main_game._item_name(item_id), count])
				main_game._update_all_ui()
				# Remove from main game list
				main_game.dropped_items.erase(self)
				queue_free()
