extends Node

const SCHEMA_VERSION := 1
const SAVE_PATH := "user://protocol_horizon_gpt61_save_v1.json"
const SEASON_LEVEL_CAP := 60

var current_route: StringName = &"start"

func is_content_ready() -> bool:
	return ContentRegistry.is_loaded
