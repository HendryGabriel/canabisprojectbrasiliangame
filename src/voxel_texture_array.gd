## Runtime texture-array builder for voxel terrain.
##
## All active block textures are currently 16x16.  Combining them into one
## Texture2DArray lets each section use one material per render class instead of
## one material surface per texture.
class_name VoxelTextureArray
extends RefCounted


var texture_array: Texture2DArray = null
var layer_by_path: Dictionary = {}
var _materials: Dictionary = {}


func build(block_definitions: Dictionary) -> bool:
	var paths: Array = []
	for raw_definition in block_definitions.values():
		var definition: Dictionary = raw_definition as Dictionary
		var textures: Dictionary = definition.get("textures", {})
		for raw_path in textures.values():
			var texture_path: String = str(raw_path)
			if texture_path != "" and not paths.has(texture_path):
				paths.append(texture_path)
		var fallback_path: String = str(definition.get("texture", ""))
		if fallback_path != "" and not paths.has(fallback_path):
			paths.append(fallback_path)
	paths.sort()
	if paths.is_empty():
		return false
	var images: Array[Image] = []
	for texture_path in paths:
		var texture: Texture2D = load(texture_path) as Texture2D
		if texture == null:
			return false
		var image: Image = texture.get_image()
		if image == null or image.get_width() != 16 or image.get_height() != 16:
			return false
		# Imported PNGs can have different internal formats even at the same
		# dimensions. Texture2DArray requires every layer to share one format.
		image = image.duplicate()
		image.convert(Image.FORMAT_RGBA8)
		layer_by_path[texture_path] = images.size()
		images.append(image)
	texture_array = Texture2DArray.new()
	return texture_array.create_from_images(images) == OK


func is_ready() -> bool:
	return texture_array != null and not layer_by_path.is_empty()


func material_for(render_class: String) -> Material:
	if not is_ready():
		return null
	if _materials.has(render_class):
		return _materials[render_class] as Material
	var material: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	shader.code = _shader_code_for(render_class)
	material.shader = shader
	material.set_shader_parameter("block_textures", texture_array)
	_materials[render_class] = material
	return material


func update_micro_foliage(player_position: Vector3, player_velocity: Vector3) -> void:
	var material: ShaderMaterial = material_for("micro_foliage") as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("voxel_player_position", player_position)
	material.set_shader_parameter("voxel_player_velocity", player_velocity)


func _shader_code_for(render_class: String) -> String:
	var render_mode: String = "render_mode cull_back, diffuse_lambert;"
	var vertex_code: String = ""
	# Writing ALPHA at all makes a spatial shader use Godot's transparent
	# pipeline. Opaque voxel faces must not write it, even when the sampled PNG
	# happens to contain an alpha channel.
	var alpha_code: String = ""
	if render_class == "cutout":
		render_mode = "render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_lambert;"
		vertex_code = """
float phase = MODEL_MATRIX[3].x * 0.83 + MODEL_MATRIX[3].z * 0.61 + VERTEX.y * 0.37;
float sway = sin(TIME * 1.05 + phase) * 0.032;
VERTEX.x += sway;
VERTEX.z += cos(TIME * 0.86 + phase) * 0.011;
"""
		alpha_code = "ALPHA = step(0.08, tex.a * COLOR.a);\n\tALPHA_SCISSOR_THRESHOLD = 0.5;"
	elif render_class == "micro_foliage":
		render_mode = "render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_lambert;"
		vertex_code = """
vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
float phase = world_position.x * 0.71 + world_position.z * 0.53 + VERTEX.y * 0.37;
vec2 wind = vec2(sin(TIME * 1.15 + phase), cos(TIME * 0.79 + phase * 1.31)) * 0.035;
vec2 from_player = world_position.xz - voxel_player_position.xz;
float distance_to_player = length(from_player);
float player_weight = 1.0 - smoothstep(0.15, 1.15, distance_to_player);
vec2 push_direction = distance_to_player > 0.001 ? from_player / distance_to_player : vec2(0.0);
vec2 movement_push = push_direction * player_weight * min(length(voxel_player_velocity.xz) * 0.025, 0.11);
VERTEX.xz += (wind + movement_push) * COLOR.a;
"""
		alpha_code = "ALPHA = step(0.08, tex.a);\n\tALPHA_SCISSOR_THRESHOLD = 0.5;"
	elif render_class == "transparent":
		render_mode = "render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_lambert;"
		alpha_code = "ALPHA = tex.a * COLOR.a;"
	return """
shader_type spatial;
%s
uniform sampler2DArray block_textures : source_color, filter_nearest, repeat_enable;
uniform vec3 voxel_player_position = vec3(100000.0);
uniform vec3 voxel_player_velocity = vec3(0.0);
void vertex() {
	%s
}
void fragment() {
	vec4 tex = texture(block_textures, vec3(fract(UV), UV2.x));
	ALBEDO = tex.rgb * COLOR.rgb;
	%s
}
""" % [render_mode, vertex_code, alpha_code]
