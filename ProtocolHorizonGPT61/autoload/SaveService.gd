extends Node

const GameStateScript = preload("res://autoload/GameState.gd")

const BACKUP_SUFFIX := ".bak"
const TEMP_SUFFIX := ".tmp"
const BACKUP_TEMP_SUFFIX := ".bak.tmp"
const SETTINGS_KEYS := ["master", "music", "sfx", "ambience", "vibration", "quality", "fps", "reduce_motion"]
const PROFILE_KEYS := ["profile_id", "money_cents", "shards", "research_points", "inventory", "active_site", "sites", "local", "route", "story"]
const SITE_IDS := ["site_earth_fe_17", "site_earth_pd_7", "site_earth_ir_9"]
const LOCAL_MAP_KEYS := ["upgrades", "machines", "workers", "equipment"]

var status_message: String = ""
var recovered_from_backup: bool = false
var _profile_available: bool = false
var _writes_blocked: bool = false

func _ready() -> void:
	_load_existing()

func has_profile() -> bool:
	return _profile_available

func has_existing_files() -> bool:
	return _path_exists(GameStateScript.SAVE_PATH) or _path_exists(_backup_path())

func requires_reset_confirmation() -> bool:
	return has_existing_files() and (_profile_available or _writes_blocked)

func save_settings(candidate: Dictionary) -> Error:
	if _writes_blocked:
		status_message = "Сохранение повреждено или имеет неподдерживаемую версию; настройки не сохранены."
		return ERR_FILE_CORRUPT
	var normalized_settings = _normalize_settings(candidate)
	if normalized_settings == null:
		status_message = "Настройки отклонены; файл не изменён."
		return ERR_INVALID_PARAMETER
	var normalized_profile = _normalize_profile(_game_state().profile)
	if normalized_profile == null:
		status_message = "Профиль некорректен; настройки не сохранены."
		return ERR_INVALID_DATA
	var result := _write_envelope(normalized_settings, normalized_profile)
	if result != OK:
		return result
	_game_state().settings = normalized_settings.duplicate(true)
	_game_state().profile = normalized_profile.duplicate(true)
	_profile_available = not _game_state().profile.is_empty()
	recovered_from_backup = false
	status_message = "Настройки сохранены."
	return OK

func new_game() -> Error:
	var normalized_settings = _normalize_settings(_game_state().settings)
	if normalized_settings == null:
		status_message = "Текущие настройки некорректны; новая игра не сохранена."
		return ERR_INVALID_DATA
	var fresh_profile: Dictionary = GameStateScript.make_new_profile()
	var result := _write_envelope(normalized_settings, fresh_profile)
	if result != OK:
		return result
	_game_state().settings = normalized_settings.duplicate(true)
	_game_state().profile = fresh_profile.duplicate(true)
	_profile_available = true
	_writes_blocked = false
	recovered_from_backup = false
	status_message = "Новая игра сохранена."
	return OK

func commit_profile(candidate: Dictionary) -> Error:
	if _writes_blocked:
		status_message = "Сохранение повреждено или имеет неподдерживаемую версию; профиль не сохранён."
		return ERR_FILE_CORRUPT
	var normalized_settings = _normalize_settings(_game_state().settings)
	var normalized_profile = _normalize_profile(candidate)
	if normalized_settings == null or normalized_profile == null or normalized_profile.is_empty():
		status_message = "Профиль или настройки некорректны; файл не изменён."
		return ERR_INVALID_PARAMETER
	var result := _write_envelope(normalized_settings, normalized_profile)
	if result != OK:
		return result
	_game_state().settings = normalized_settings.duplicate(true)
	_game_state().profile = normalized_profile.duplicate(true)
	_profile_available = true
	_writes_blocked = false
	recovered_from_backup = false
	status_message = "Профиль сохранён."
	return OK

func _load_existing() -> void:
	_game_state().settings = GameStateScript.default_settings()
	_game_state().profile = {}
	_profile_available = false
	_writes_blocked = false
	recovered_from_backup = false
	var primary_exists := _path_exists(GameStateScript.SAVE_PATH)
	var backup_exists := _path_exists(_backup_path())
	if not primary_exists and not backup_exists:
		status_message = "Сохранённый профиль не найден."
		return
	if primary_exists:
		var primary_result := _read_envelope(GameStateScript.SAVE_PATH)
		if primary_result["ok"]:
			_apply_envelope(primary_result["envelope"])
			status_message = "Сохранение загружено."
			return
		if primary_result["error"] == ERR_UNAVAILABLE:
			_writes_blocked = true
			status_message = "Версия сохранения не поддерживается; продолжение отключено."
			return
		var backup_result: Dictionary = {}
		if backup_exists:
			backup_result = _read_envelope(_backup_path())
			if backup_result["ok"]:
				_apply_envelope(backup_result["envelope"])
				recovered_from_backup = true
				status_message = "Основное сохранение повреждено; загружена резервная копия."
				return
		_writes_blocked = true
		status_message = "Сохранение отклонено: %s; резервная копия: %s" % [primary_result["message"], "отсутствует" if not backup_exists else backup_result["message"]]
		return
	var backup_result := _read_envelope(_backup_path())
	if backup_result["ok"]:
		_apply_envelope(backup_result["envelope"])
		recovered_from_backup = true
		status_message = "Основное сохранение отсутствует; загружена резервная копия."
	else:
		_writes_blocked = true
		status_message = "Резервная копия отклонена: " + backup_result["message"]

func _apply_envelope(envelope: Dictionary) -> void:
	_game_state().settings = envelope["settings"].duplicate(true)
	_game_state().profile = envelope["profile"].duplicate(true)
	_profile_available = not _game_state().profile.is_empty()

func _write_envelope(candidate_settings: Dictionary, candidate_profile: Dictionary) -> Error:
	var normalized_settings = _normalize_settings(candidate_settings)
	var normalized_profile = _normalize_profile(candidate_profile)
	if normalized_settings == null or normalized_profile == null:
		status_message = "Данные сохранения не прошли проверку."
		return ERR_INVALID_DATA
	var envelope := {
		"schema_version": GameStateScript.SCHEMA_VERSION,
		"settings": normalized_settings,
		"profile": normalized_profile,
	}
	var temp_path := GameStateScript.SAVE_PATH + TEMP_SUFFIX
	var temp_file := FileAccess.open(temp_path, FileAccess.WRITE)
	if temp_file == null:
		status_message = "Не удалось открыть временный файл сохранения."
		return FileAccess.get_open_error()
	temp_file.store_string(JSON.stringify(envelope, "\t"))
	temp_file.flush()
	var write_error: Error = temp_file.get_error()
	temp_file.close()
	if write_error != OK:
		_remove_file(temp_path)
		status_message = "Не удалось записать временный файл сохранения."
		return write_error
	var temp_validation := _read_envelope(temp_path)
	if not temp_validation["ok"]:
		_remove_file(temp_path)
		status_message = "Временный файл сохранения не прошёл проверку: " + temp_validation["message"]
		return ERR_FILE_CORRUPT
	if _path_exists(GameStateScript.SAVE_PATH) and FileAccess.file_exists(GameStateScript.SAVE_PATH):
		var primary_validation := _read_envelope(GameStateScript.SAVE_PATH)
		if primary_validation["ok"]:
			var backup_result := _replace_backup_from_primary()
			if backup_result != OK:
				_remove_file(temp_path)
				status_message = "Не удалось сохранить резервную копию предыдущей версии."
				return backup_result
	var rename_result: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(GameStateScript.SAVE_PATH)
	)
	if rename_result != OK:
		_remove_file(temp_path)
		status_message = "Не удалось завершить запись сохранения."
		return rename_result
	var committed := _read_envelope(GameStateScript.SAVE_PATH)
	if not committed["ok"]:
		status_message = "Записанное сохранение не прошло проверку."
		return ERR_FILE_CORRUPT
	return OK

func _replace_backup_from_primary() -> Error:
	var source := FileAccess.open(GameStateScript.SAVE_PATH, FileAccess.READ)
	if source == null:
		return FileAccess.get_open_error()
	var bytes := source.get_buffer(source.get_length())
	source.close()
	var backup_temp_path := GameStateScript.SAVE_PATH + BACKUP_TEMP_SUFFIX
	var backup_temp := FileAccess.open(backup_temp_path, FileAccess.WRITE)
	if backup_temp == null:
		return FileAccess.get_open_error()
	backup_temp.store_buffer(bytes)
	backup_temp.flush()
	var write_error: Error = backup_temp.get_error()
	backup_temp.close()
	if write_error != OK:
		_remove_file(backup_temp_path)
		return write_error
	var validation := _read_envelope(backup_temp_path)
	if not validation["ok"]:
		_remove_file(backup_temp_path)
		return ERR_FILE_CORRUPT
	var rename_result: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(backup_temp_path),
		ProjectSettings.globalize_path(_backup_path())
	)
	if rename_result != OK:
		_remove_file(backup_temp_path)
	return rename_result

func _read_envelope(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure(FileAccess.get_open_error(), "Не удалось прочитать файл")
	var contents := file.get_as_text()
	file.close()
	var parser := JSON.new()
	var parse_result: Error = parser.parse(contents)
	if parse_result != OK:
		return _failure(ERR_FILE_CORRUPT, "Некорректный JSON")
	var data: Variant = parser.data
	if not data is Dictionary or not _has_exact_keys(data, ["schema_version", "settings", "profile"]):
		return _failure(ERR_FILE_CORRUPT, "Неверная структура сохранения")
	if not _is_integer_number(data["schema_version"]):
		return _failure(ERR_FILE_CORRUPT, "Неверная версия схемы")
	if int(data["schema_version"]) != GameStateScript.SCHEMA_VERSION:
		return _failure(ERR_UNAVAILABLE, "Неподдерживаемая версия схемы")
	var normalized_settings = _normalize_settings(data["settings"])
	if normalized_settings == null:
		return _failure(ERR_FILE_CORRUPT, "Некорректные настройки")
	var normalized_profile = _normalize_profile(data["profile"])
	if normalized_profile == null:
		return _failure(ERR_FILE_CORRUPT, "Некорректный профиль")
	return {
		"ok": true,
		"error": OK,
		"message": "",
		"envelope": {
			"schema_version": GameStateScript.SCHEMA_VERSION,
			"settings": normalized_settings,
			"profile": normalized_profile,
		},
	}

func _normalize_settings(value: Variant) -> Variant:
	if not value is Dictionary or not _has_exact_keys(value, SETTINGS_KEYS):
		return null
	var settings := {}
	for key in ["master", "music", "sfx", "ambience"]:
		var volume: Variant = value[key]
		if not _is_finite_number(volume):
			return null
		if float(volume) < 0.0 or float(volume) > 1.0:
			return null
		settings[key] = float(volume)
	if typeof(value["vibration"]) != TYPE_BOOL or typeof(value["reduce_motion"]) != TYPE_BOOL:
		return null
	if typeof(value["quality"]) != TYPE_STRING or not ["high", "low"].has(value["quality"]):
		return null
	if not _is_integer_number(value["fps"]) or not [30, 60].has(int(value["fps"])):
		return null
	settings["vibration"] = value["vibration"]
	settings["quality"] = value["quality"]
	settings["fps"] = int(value["fps"])
	settings["reduce_motion"] = value["reduce_motion"]
	return settings

func _normalize_profile(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	if value.is_empty():
		return {}
	if not _has_exact_keys(value, PROFILE_KEYS):
		return null
	if typeof(value["profile_id"]) != TYPE_STRING or value["profile_id"].strip_edges().is_empty():
		return null
	for key in ["money_cents", "shards", "research_points"]:
		if not _is_nonnegative_integer(value[key]):
			return null
	var inventory: Variant = value["inventory"]
	if not inventory is Dictionary or not _has_exact_keys(inventory, ["iron_ore"]):
		return null
	if not _is_nonnegative_integer(inventory["iron_ore"]):
		return null
	if typeof(value["active_site"]) != TYPE_STRING or not SITE_IDS.has(value["active_site"]):
		return null
	var sites: Variant = value["sites"]
	if not sites is Dictionary or not _has_exact_keys(sites, SITE_IDS):
		return null
	for site_id in SITE_IDS:
		var site_state: Variant = sites[site_id]
		if not site_state is Dictionary or not _has_exact_keys(site_state, ["unlocked"]):
			return null
		if typeof(site_state["unlocked"]) != TYPE_BOOL:
			return null
	if not sites["site_earth_fe_17"]["unlocked"] or not sites[value["active_site"]]["unlocked"]:
		return null
	var local_state: Variant = value["local"]
	if not local_state is Dictionary or not _has_exact_keys(local_state, ["lifetime_peak"] + LOCAL_MAP_KEYS):
		return null
	if not _is_nonnegative_integer(local_state["lifetime_peak"]):
		return null
	for key in LOCAL_MAP_KEYS:
		if not local_state[key] is Dictionary or not local_state[key].is_empty():
			return null
	if typeof(value["route"]) != TYPE_STRING or not ["intro", "checkpoint"].has(value["route"]):
		return null
	var story: Variant = value["story"]
	if not story is Dictionary or not _has_exact_keys(story, ["current_id", "line", "intro_seen"]):
		return null
	if typeof(story["current_id"]) != TYPE_STRING or story["current_id"] != "A01":
		return null
	if not _is_nonnegative_integer(story["line"]) or int(story["line"]) > 4 or typeof(story["intro_seen"]) != TYPE_BOOL:
		return null
	var normalized_profile: Dictionary = value.duplicate(true)
	for key in ["money_cents", "shards", "research_points"]:
		normalized_profile[key] = int(value[key])
	normalized_profile["inventory"]["iron_ore"] = int(inventory["iron_ore"])
	normalized_profile["local"]["lifetime_peak"] = int(local_state["lifetime_peak"])
	normalized_profile["story"]["line"] = int(story["line"])
	return normalized_profile

func _is_nonnegative_integer(value: Variant) -> bool:
	return _is_integer_number(value) and float(value) >= 0.0

func _is_integer_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and floor(number) == number

func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))

func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true

func _failure(error_code: Error, message: String) -> Dictionary:
	return {"ok": false, "error": error_code, "message": message}

func _backup_path() -> String:
	return GameStateScript.SAVE_PATH + BACKUP_SUFFIX

func _path_exists(path: String) -> bool:
	var absolute_path := ProjectSettings.globalize_path(path)
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(absolute_path)

func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _game_state() -> Variant:
	return get_node_or_null("/root/GameState")
