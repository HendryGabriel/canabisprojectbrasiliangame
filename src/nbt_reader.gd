class_name NbtReader
extends RefCounted
## Leitor de NBT (formato do Minecraft) para importar schematics.
## Suporta .schem (Sponge v1/v2/v3), .schematic (MCEdit) e .nbt (structure block),
## todos gzip ou sem compressao. Retorna Dictionaries/Arrays GDScript.

const TAG_END := 0
const TAG_BYTE := 1
const TAG_SHORT := 2
const TAG_INT := 3
const TAG_LONG := 4
const TAG_FLOAT := 5
const TAG_DOUBLE := 6
const TAG_BYTE_ARRAY := 7
const TAG_STRING := 8
const TAG_LIST := 9
const TAG_COMPOUND := 10
const TAG_INT_ARRAY := 11
const TAG_LONG_ARRAY := 12

var _dados: PackedByteArray
var _pos: int = 0
var erro: String = ""


static func abrir(caminho: String) -> Dictionary:
	## Le um arquivo NBT (gzip ou nao) e retorna o compound raiz ({} se falhar).
	var bruto: PackedByteArray = FileAccess.get_file_as_bytes(caminho)
	if bruto.is_empty():
		push_error("NBT: arquivo vazio ou inexistente: " + caminho)
		return {}
	# gzip comeca com 0x1f 0x8b
	if bruto.size() > 2 and bruto[0] == 0x1f and bruto[1] == 0x8b:
		bruto = bruto.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
		if bruto.is_empty():
			push_error("NBT: falha ao descomprimir gzip: " + caminho)
			return {}
	var leitor = (load("res://src/nbt_reader.gd") as GDScript).new()
	leitor._dados = bruto
	var raiz: Dictionary = leitor._ler_raiz()
	if leitor.erro != "":
		push_error("NBT: " + leitor.erro)
	return raiz


func _ler_raiz() -> Dictionary:
	var tipo := _u8()
	if tipo != TAG_COMPOUND:
		erro = "raiz nao e TAG_Compound (tipo %d)" % tipo
		return {}
	var _nome := _string()
	var corpo: Dictionary = _payload(TAG_COMPOUND)
	# Sponge v3 embrulha tudo em "Schematic"
	if corpo.has("Schematic") and corpo["Schematic"] is Dictionary:
		return corpo["Schematic"]
	return corpo


func _payload(tipo: int) -> Variant:
	match tipo:
		TAG_BYTE:
			return _i8()
		TAG_SHORT:
			return _i16()
		TAG_INT:
			return _i32()
		TAG_LONG:
			return _i64()
		TAG_FLOAT:
			return _f32()
		TAG_DOUBLE:
			return _f64()
		TAG_BYTE_ARRAY:
			var n := _i32()
			var fatia := _dados.slice(_pos, _pos + n)
			_pos += n
			return fatia
		TAG_STRING:
			return _string()
		TAG_LIST:
			var t := _u8()
			var qtd := _i32()
			var lista: Array = []
			for i in qtd:
				lista.append(_payload(t))
			return lista
		TAG_COMPOUND:
			var d := {}
			while _pos < _dados.size():
				var t2 := _u8()
				if t2 == TAG_END:
					break
				var nome := _string()
				d[nome] = _payload(t2)
			return d
		TAG_INT_ARRAY:
			var n2 := _i32()
			var ints: Array = []
			for i in n2:
				ints.append(_i32())
			return ints
		TAG_LONG_ARRAY:
			var n3 := _i32()
			var longs: Array = []
			for i in n3:
				longs.append(_i64())
			return longs
	erro = "tag desconhecida %d em %d" % [tipo, _pos]
	return null


# ---- leituras big-endian (NBT e sempre big-endian; Godot decode_* e little) ----

func _u8() -> int:
	_pos += 1
	return _dados[_pos - 1]


func _i8() -> int:
	var v := _u8()
	return v - 256 if v > 127 else v


func _i16() -> int:
	var v := (_dados[_pos] << 8) | _dados[_pos + 1]
	_pos += 2
	return v - 65536 if v > 32767 else v


func _i32() -> int:
	var v := (_dados[_pos] << 24) | (_dados[_pos + 1] << 16) | (_dados[_pos + 2] << 8) | _dados[_pos + 3]
	_pos += 4
	return v - 4294967296 if v > 2147483647 else v


func _i64() -> int:
	var v := 0
	for i in 8:
		v = (v << 8) | _dados[_pos + i]
	_pos += 8
	return v  # GDScript int e 64-bit com sinal; overflow ja da o complemento certo


func _f32() -> float:
	var b := PackedByteArray([_dados[_pos + 3], _dados[_pos + 2], _dados[_pos + 1], _dados[_pos]])
	_pos += 4
	return b.decode_float(0)


func _f64() -> float:
	var b := PackedByteArray()
	for i in 8:
		b.append(_dados[_pos + 7 - i])
	_pos += 8
	return b.decode_double(0)


func _string() -> String:
	var n := (_dados[_pos] << 8) | _dados[_pos + 1]
	_pos += 2
	var s := _dados.slice(_pos, _pos + n).get_string_from_utf8()
	_pos += n
	return s
