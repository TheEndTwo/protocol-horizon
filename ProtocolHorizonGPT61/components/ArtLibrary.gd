class_name ArtLibrary
extends RefCounted

const OVERRIDES := "res://data/art_overrides.json"
static var _overrides: Dictionary = {}
static var _loaded := false
static var _textures: Dictionary = {}

static func texture_for(fallback: String) -> Texture2D:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(OVERRIDES):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(OVERRIDES))
			if parsed is Dictionary:
				_overrides = parsed
	var key := fallback.get_file().get_basename()
	var path := str(_overrides.get(key, fallback))
	if not path.begins_with("res://") or not ResourceLoader.exists(path):
		path = fallback
	if not _textures.has(path):
		var resource = load(path)
		_textures[path] = resource if resource is Texture2D else load(fallback)
	return _textures[path]
