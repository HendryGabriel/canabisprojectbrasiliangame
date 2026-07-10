class_name AuthoringHistory
extends RefCounted


const MAX_COMMANDS: int = 128

var _undo: Array = []
var _redo: Array = []


func push(command: Dictionary) -> void:
	if command.is_empty():
		return
	_undo.append(command.duplicate(true))
	_redo.clear()
	if _undo.size() > MAX_COMMANDS:
		_undo.pop_front()


func pop_undo() -> Dictionary:
	if _undo.is_empty():
		return {}
	var command: Dictionary = _undo.pop_back()
	_redo.append(command)
	return command


func pop_redo() -> Dictionary:
	if _redo.is_empty():
		return {}
	var command: Dictionary = _redo.pop_back()
	_undo.append(command)
	return command


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func clear() -> void:
	_undo.clear()
	_redo.clear()
