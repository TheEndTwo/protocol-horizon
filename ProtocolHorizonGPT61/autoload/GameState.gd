extends Node

const SCHEMA_VERSION := 1
const SAVE_PATH := "user://protocol_horizon_gpt61_save_v1.json"
const SEASON_LEVEL_CAP := 60

var current_route: StringName = &"start"
var settings: Dictionary = default_settings()
var profile: Dictionary = {}

static func default_settings() -> Dictionary:
	return {
		"master": 0.8,
		"music": 0.6,
		"sfx": 0.8,
		"ambience": 0.5,
		"vibration": true,
		"quality": "high",
		"fps": 60,
		"reduce_motion": false,
	}

static func make_new_profile() -> Dictionary:
	var profile_id := Crypto.new().generate_random_bytes(16).hex_encode()
	if profile_id.is_empty():
		profile_id = "%d-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec(), randi()]
	return {
		"profile_id": profile_id,
		"money_cents": 0,
		"shards": 0,
		"research_points": 0,
		"inventory": {"iron_ore": 0},
		"active_site": "site_earth_fe_17",
		"sites": {
			"site_earth_fe_17": {"unlocked": true},
			"site_earth_pd_7": {"unlocked": false},
			"site_earth_ir_9": {"unlocked": false},
		},
		"local": {
			"lifetime_peak": 0,
			"upgrades": {},
			"machines": {},
			"workers": {},
			"equipment": {},
		},
		"route": "intro",
		"story": {"current_id": "A01", "line": 0, "intro_seen": false},
	}

func is_content_ready() -> bool:
	return ContentRegistry.is_loaded
