class_name GenerationReport
extends RefCounted


var errors: Array[String] = []
var warnings: Array[String] = []
var instances: Array = []
var entity_spawns: Array = []
var generated_columns: int = 0
var generated_blocks: int = 0
var carved_voxels: int = 0


func add_error(message: String) -> void:
	errors.append(message)


func add_warning(message: String) -> void:
	warnings.append(message)


func is_ok() -> bool:
	return errors.is_empty()


func summary() -> String:
	if not errors.is_empty():
		return "Erros: %s" % "; ".join(errors)
	if not warnings.is_empty():
		return "Concluido com avisos: %s" % "; ".join(warnings)
	return "Geracao concluida: %d colunas, %d blocos, %d voxels escavados, %d estruturas." % [generated_columns, generated_blocks, carved_voxels, instances.size()]
