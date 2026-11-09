extends Node

const MANIFEST_PATH := "res://data/catalog_manifest.json"

var is_loaded := false
var errors: PackedStringArray = []
var _catalogs: Dictionary = {}
var _indices: Dictionary = {}
var source_file_count := 0

func _ready() -> void:
	_load_catalogs()
	if not is_loaded:
		push_error("ContentRegistry: " + "; ".join(errors))

func get_record(catalog: StringName, id: String) -> Dictionary:
	return _indices.get(String(catalog), {}).get(id, {}).duplicate(true)

func get_records(catalog: StringName) -> Array:
	return _catalogs.get(String(catalog), []).duplicate(true)

func get_count(catalog: StringName) -> int:
	return _catalogs.get(String(catalog), []).size()

func _load_catalogs() -> void:
	var manifest = _read_json(MANIFEST_PATH)
	if not manifest is Array or manifest.is_empty():
		errors.append("Пустой или некорректный манифест каталогов")
		return
	var pending: Dictionary = {}
	var formats: Dictionary = {}
	for definition in manifest:
		if not definition is Dictionary:
			errors.append("Некорректная запись манифеста")
			continue
		var path := str(definition.get("path", ""))
		var format := str(definition.get("format", ""))
		var rows = _read_json(path) if format == "json" else _read_csv(path)
		var issues := validate_records(rows, definition)
		if not issues.is_empty():
			for issue in issues:
				errors.append(path.get_file() + ": " + issue)
			continue
		var key := str(definition["catalog"])
		var id_field := str(definition["id_field"])
		var index: Dictionary = {}
		for row in rows:
			index[str(row[id_field])] = row
		if pending.has(key):
			var old_ids: Array = pending[key]["index"].keys()
			var new_ids: Array = index.keys()
			old_ids.sort()
			new_ids.sort()
			if old_ids != new_ids:
				errors.append(key + ": ID в CSV и JSON различаются")
		if not pending.has(key) or format == "json":
			pending[key] = {"rows": rows, "index": index}
		var source_key := key + ":" + format
		if formats.has(source_key):
			errors.append("Повторный источник " + source_key)
		formats[source_key] = true
	if not errors.is_empty():
		return
	for key in pending:
		_catalogs[key] = pending[key]["rows"]
		_indices[key] = pending[key]["index"]
	source_file_count = formats.size()
	is_loaded = true
	print("ContentRegistry: %d sources, %d catalogs loaded" % [source_file_count, _catalogs.size()])

func _read_utf8(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Не удалось прочитать " + path)
		return ""
	var bytes := file.get_buffer(file.get_length())
	if bytes.size() >= 3 and bytes.slice(0, 3) == PackedByteArray([0xef, 0xbb, 0xbf]):
		bytes = bytes.slice(3)
	var value := bytes.get_string_from_utf8()
	if value.to_utf8_buffer() != bytes:
		errors.append("Некорректный UTF-8: " + path)
	return value.trim_prefix("\ufeff")

func _read_json(path: String) -> Variant:
	var parser := JSON.new()
	var result := parser.parse(_read_utf8(path))
	if result != OK:
		errors.append("JSON %s, строка %d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return null
	return parser.data

func _read_csv(path: String) -> Array:
	_read_utf8(path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var header := file.get_csv_line()
	if header.is_empty():
		return []
	header[0] = header[0].trim_prefix("\ufeff")
	var unique_headers: Dictionary = {}
	for field in header:
		if field.is_empty() or unique_headers.has(field):
			errors.append("Некорректный заголовок CSV: " + path)
			return []
		unique_headers[field] = true
	var rows: Array = []
	while not file.eof_reached():
		var cells := file.get_csv_line()
		if cells.size() == 1 and cells[0].is_empty():
			continue
		if cells.size() != header.size():
			errors.append("Неверное число столбцов CSV: " + path)
			continue
		var row: Dictionary = {}
		for i in header.size():
			row[header[i]] = cells[i]
		rows.append(row)
	return rows

static func validate_records(rows: Variant, definition: Dictionary) -> PackedStringArray:
	var issues: PackedStringArray = []
	if not rows is Array:
		issues.append("Ожидался массив записей")
		return issues
	if rows.size() != int(definition.get("count", -1)):
		issues.append("Ожидалось %s записей, найдено %d" % [definition.get("count", "?"), rows.size()])
	var id_field := str(definition.get("id_field", "id"))
	var ids: Dictionary = {}
	for row in rows:
		if not row is Dictionary:
			issues.append("Запись должна быть объектом")
			continue
		for field in definition.get("required_fields", []):
			if not row.has(field):
				issues.append("Нет обязательного поля " + str(field))
		var id := str(row.get(id_field, ""))
		if id.strip_edges().is_empty() or row.get(id_field) == null:
			issues.append("Пустой ID")
		elif ids.has(id):
			issues.append("Повторный ID: " + id)
		ids[id] = true
	return issues
