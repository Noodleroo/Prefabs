@tool
extends Node3D
class_name ProceduralWaterChunk

@export_group("Chunk Grid Configuration")
@export var chunk_size: Vector2 = Vector2(64.0, 64.0):
	set(value):
		chunk_size = value
		_update_mesh()

@export_range(2, 256, 1) var subdivisions: int = 32:
	set(value):
		subdivisions = value
		_update_mesh()

@export_group("Material Settings")
@export var water_material: ShaderMaterial:
	set(value):
		water_material = value
		_update_material()

@export var wave_texture: Texture2D:
	set(value):
		wave_texture = value
		_update_material()

@export var global_world_seed: Vector2 = Vector2(0.0, 0.0):
	set(value):
		global_world_seed = value
		_update_material_params()

func get_mesh_instance() -> MeshInstance3D:
	return get_node_or_null("WaterMesh") as MeshInstance3D

func _ready() -> void:
	_update_mesh()
	_update_material()

func _update_mesh() -> void:
	if not is_inside_tree(): return
	var mesh_inst := get_mesh_instance()
	if mesh_inst:
		var plane_mesh := PlaneMesh.new()
		plane_mesh.size = chunk_size
		plane_mesh.subdivide_width = subdivisions
		plane_mesh.subdivide_depth = subdivisions
		
		# Align pivot point to the corner so chunks tile like grid blocks
		plane_mesh.center_offset = Vector3(chunk_size.x * 0.5, 0.0, chunk_size.y * 0.5)
		mesh_inst.mesh = plane_mesh

func _update_material() -> void:
	var mesh_inst := get_mesh_instance()
	if not mesh_inst: return
	
	# SAFE GUARD: If you haven't assigned your water_material yet, don't crash
	if water_material:
		mesh_inst.material_override = water_material
		_update_material_params()

func _update_material_params() -> void:
	var mesh_inst := get_mesh_instance()
	if not mesh_inst or not mesh_inst.material_override: return
	
	var active_mat = mesh_inst.material_override as ShaderMaterial
	if active_mat:
		if wave_texture:
			active_mat.set_shader_parameter("wave_texture", wave_texture)
		
		active_mat.set_shader_parameter("water_size", chunk_size)
		active_mat.set_shader_parameter("world_seed_offset", global_world_seed)
