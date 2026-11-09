class_name EarthMeta
extends RefCounted

const CONFIG_PATH := "res://data/proposals/meta.json"
const SITE_KEYS := ["fe", "pd", "ir"]
const SITE_IDS := {"fe":"site_earth_fe_17", "pd":"site_earth_pd_7", "ir":"site_earth_ir_9"}
const SITE_NAMES := {"Fe":"fe", "Pd":"pd", "Ir":"ir", "Global":"global"}
const EFFECT_KEYS := ["output", "tap", "crit", "weak", "wage", "storage", "speed"]

static func ensure(p: Dictionary) -> void:
	var g := GameMath.game(p)
	if not (g.get("meta", {}) is Dictionary):
		g["meta"] = {}
	var meta: Dictionary = g["meta"]
	var cfg := _config()
	var new_meta := meta.is_empty()
	if not (meta.get("gear", {}) is Dictionary):
		meta["gear"] = {"items":[], "equipped":{}, "fragments":{}}
	var gear: Dictionary = meta["gear"]
	_ensure_fields(gear, {"items":[], "equipped":{}, "fragments":{}})
	if not (meta.get("specialists", {}) is Dictionary):
		meta["specialists"] = {"owned":{}, "assignments":{}, "fragments":{}}
	var specialists: Dictionary = meta["specialists"]
	_ensure_fields(specialists, {"owned":{}, "assignments":{}, "fragments":{}})
	if new_meta or specialists["owned"].is_empty():
		var starter_id := str(cfg.get("specialists", {}).get("starter_id", "SP01"))
		if not specialists["owned"].has(starter_id):
			specialists["owned"][starter_id] = {"level":1, "stars":0}
	if not (meta.get("cases", {}) is Dictionary):
		meta["cases"] = {"opened":{}, "pity":{}}
	_ensure_fields(meta["cases"], {"opened":{}, "pity":{}})
	if not (meta.get("season", {}) is Dictionary):
		meta["season"] = {"id":str(cfg.get("season", {}).get("id", "mountain_depths_proposal_01")), "xp":0, "tasks":{}}
	_ensure_fields(meta["season"], {"id":str(cfg.get("season", {}).get("id", "mountain_depths_proposal_01")), "xp":0, "tasks":{}})
	for key in ["events", "claims", "milestones", "evidence"]:
		if not (meta.get(key, {}) is Dictionary):
			meta[key] = {}
	if not (meta.get("boosts", []) is Array):
		meta["boosts"] = []
	if not (meta.get("tracking", {}) is Dictionary):
		meta["tracking"] = {"last_stats":GameMath.game(p)["stats"].duplicate(true), "long_projects_seen":0}
	_ensure_fields(meta["tracking"], {"last_stats":GameMath.game(p)["stats"].duplicate(true), "long_projects_seen":0})
	_ensure_starter_gear(p, meta, cfg)
	_ensure_task_rows(p, meta)
	_rebuild_bonuses(p)

static func act(p: Dictionary, action: String, args: Dictionary) -> Dictionary:
	ensure(p)
	var result: Dictionary
	match action:
		"gear_equip": result = _gear_equip(p, args)
		"gear_unequip": result = _gear_unequip(p, args)
		"gear_upgrade": result = _gear_upgrade(p, args)
		"gear_star": result = _gear_star(p, args)
		"specialist_assign": result = _specialist_assign(p, args)
		"specialist_unassign": result = _specialist_unassign(p, args)
		"specialist_level": result = _specialist_level(p, args)
		"specialist_star": result = _specialist_star(p, args)
		"case_open": result = _case_open(p, args)
		"claim_case_milestone": result = _claim_case_milestone(p, args)
		"claim_season_task": result = _claim_season_task(p, args)
		"claim_season_reward": result = _claim_season_reward(p, args)
		"claim_event": result = _claim_event(p, args)
		"shop_purchase", "vip_purchase": result = GameMath.fail("Покупки пока недоступны")
		_: return GameMath.fail("Неизвестное действие мета-системы")
	if result.get("ok", false):
		refresh(p)
	return result

static func advance(p: Dictionary, seconds: float) -> void:
	ensure(p)
	var elapsed := maxf(0.0, seconds)
	if elapsed > 0.0:
		var boosts: Array = GameMath.game(p)["meta"]["boosts"]
		var remaining: Array = []
		for boost in boosts:
			boost["remaining_s"] = maxf(0.0, float(boost.get("remaining_s", 0.0)) - elapsed)
			if float(boost["remaining_s"]) > 0.0:
				remaining.append(boost)
		GameMath.game(p)["meta"]["boosts"] = remaining
	refresh(p)

static func refresh(p: Dictionary) -> void:
	ensure(p)
	_sync_progress(p)
	_rebuild_bonuses(p)

static func view(p: Dictionary) -> Dictionary:
	var snapshot := p.duplicate(true)
	ensure(snapshot)
	refresh(snapshot)
	var meta: Dictionary = GameMath.game(snapshot)["meta"]
	var cfg := _config()
	var owned: Dictionary = meta["specialists"]["owned"]
	var specialist_view: Array = []
	for row in GameMath.records("specialists"):
		var item: Dictionary = row.duplicate(true)
		var specialist_id := str(row.get("id", ""))
		var site := _site_key_for_name(str(row.get("site", "")))
		item["owned"] = owned.has(specialist_id)
		item["eligible_case_pool"] = _rank_allowed(row, _vip_rank(snapshot)) and (site == "global" or _site_is_open(snapshot, site))
		if owned.has(specialist_id):
			item["progress"] = owned[specialist_id].duplicate(true)
		specialist_view.append(item)
	var case_view: Array = []
	var case_pools: Dictionary = {}
	for row in GameMath.records("cases"):
		var item: Dictionary = row.duplicate(true)
		var case_id := str(row.get("id", ""))
		item["available"] = _case_available(snapshot, case_id)
		item["rarity_probability_total"] = _weight_total(row.get("rarity_prob_pct", {}))
		item["category_probability_total"] = _weight_total(row.get("category_prob_pct", {}))
		item["eligible_specialist_ids"] = _eligible_specialist_ids(snapshot, "")
		case_view.append(item)
		case_pools[case_id] = _eligible_specialist_ids(snapshot, "")
	var season_cfg: Dictionary = cfg.get("season", {})
	var level_cap := int(season_cfg.get("level_cap", 60))
	var xp_per_level := maxi(1, int(season_cfg.get("xp_per_level", 100)))
	var season: Dictionary = meta["season"]
	var season_level := mini(level_cap, int(floor(float(season.get("xp", 0)) / xp_per_level)))
	var task_view: Array = []
	for row in GameMath.records("season_tasks"):
		var task_id := str(row.get("template_id", ""))
		var task_state: Dictionary = season["tasks"].get(task_id, {})
		var item: Dictionary = row.duplicate(true)
		item["progress"] = int(task_state.get("progress", 0))
		item["complete"] = int(task_state.get("progress", 0)) >= int(row.get("target_count", 0))
		item["claimed"] = bool(task_state.get("claimed", false))
		item["period_id"] = str(task_state.get("period_id", ""))
		item["claim_id"] = _task_claim_id(task_id, item["period_id"])
		task_view.append(item)
	var season_levels: Array = []
	for level_row in season_cfg.get("levels", []):
		var item: Dictionary = level_row.duplicate(true)
		item["unlocked"] = int(item.get("level", 0)) <= season_level
		item["free_claimed"] = meta["claims"].has(_season_claim_id(int(item.get("level", 0)), "free"))
		item["premium_claimed"] = meta["claims"].has(_season_claim_id(int(item.get("level", 0)), "premium"))
		season_levels.append(item)
	var event_view: Array = []
	for row in GameMath.records("events"):
		var item: Dictionary = row.duplicate(true)
		var event_id := str(row.get("id", ""))
		var state: Dictionary = meta["events"].get(event_id, {})
		item["available"] = _event_site_open(snapshot, str(row.get("site", "")))
		item["progress"] = int(state.get("progress", 0))
		item["complete"] = int(state.get("progress", 0)) >= _event_target(event_id)
		item["claimed"] = bool(state.get("claimed", false))
		item["reward_status"] = "provisional"
		event_view.append(item)
	var shop_view: Array = []
	for product in GameMath.records("shop"):
		var item: Dictionary = product.duplicate(true)
		item["purchase_available"] = false
		item["price_is_unofficial_preview"] = true
		item["message"] = str(cfg.get("vip_shop", {}).get("disabled_message", "Покупки пока недоступны"))
		shop_view.append(item)
	var case_counts: Dictionary = {}
	for case_id in cfg.get("cases", {}).get("case_inventory_ids", []):
		case_counts[case_id] = int(snapshot.get("inventory", {}).get(case_id, 0))
	var vip_rows := GameMath.records("vip")
	var bonuses: Dictionary = GameMath.game(snapshot)["bonuses"].get("meta", {}).duplicate(true)
	return {
		"gear":meta["gear"].duplicate(true),
		"specialists":{"catalog":specialist_view, "owned":owned.duplicate(true), "assignments":meta["specialists"]["assignments"].duplicate(true), "team_slots":_team_slots(snapshot)},
		"cases":{"catalog":case_view, "inventory":case_counts, "history":meta["cases"]["opened"].duplicate(true), "pity":meta["cases"]["pity"].duplicate(true), "pools":case_pools, "table_version":str(cfg.get("cases", {}).get("table_version", "cases_v8"))},
		"season":{"id":str(season.get("id", "")), "xp":int(season.get("xp", 0)), "level":season_level, "level_cap":level_cap, "xp_per_level":xp_per_level, "tasks":task_view, "levels":season_levels, "premium_enabled":false, "reward_status":"provisional_not_canon"},
		"events":event_view,
		"vip":{"rank":_vip_rank(snapshot), "catalog":vip_rows, "purchase_available":false, "message":str(cfg.get("vip_shop", {}).get("disabled_message", "Покупки пока недоступны"))},
		"shop":{"products":shop_view, "purchase_available":false, "message":str(cfg.get("vip_shop", {}).get("disabled_message", "Покупки пока недоступны"))},
		"bonuses":bonuses
	}

static func _config() -> Dictionary:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

static func _ensure_fields(target: Dictionary, defaults: Dictionary) -> void:
	for key in defaults:
		if not target.has(key):
			target[key] = defaults[key].duplicate(true) if defaults[key] is Dictionary or defaults[key] is Array else defaults[key]

static func _ensure_starter_gear(p: Dictionary, meta: Dictionary, cfg: Dictionary) -> void:
	var gear: Dictionary = meta["gear"]
	var items: Array = gear["items"]
	var site_slots: Dictionary = cfg.get("equipment", {}).get("site_slots", {})
	var token := str(p.get("profile_id", "local")).sha256_text().substr(0, 12)
	for site in SITE_KEYS:
		var equipped: Dictionary = gear["equipped"].get(site, {})
		for slot in site_slots.get(site, []):
			var starter_template := "starter_%s_%s" % [site, str(slot)]
			var starter: Dictionary = {}
			for item in items:
				if str(item.get("template_id", "")) == starter_template and str(item.get("site", "")) == site:
					starter = item
					break
			if starter.is_empty():
				starter = {"id":"gear_%s_%s_%s" % [token, site, str(slot)], "site":site, "slot":str(slot), "template_id":starter_template, "rarity":str(cfg.get("equipment", {}).get("starter_rarity", "Обычный")), "level":1, "stars":0, "source":"starter"}
				items.append(starter)
			if not equipped.has(slot) or _gear_item_by_id(items, str(equipped.get(slot, ""))).is_empty():
				equipped[str(slot)] = starter["id"]
		gear["equipped"][site] = equipped

static func _ensure_task_rows(p: Dictionary, meta: Dictionary) -> void:
	var tasks: Dictionary = meta["season"]["tasks"]
	for row in GameMath.records("season_tasks"):
		var task_id := str(row.get("template_id", ""))
		if tasks.has(task_id):
			continue
		var kind := str(row.get("kind", "season_once"))
		tasks[task_id] = {"period_id":_period_for(kind), "progress":0, "claimed":false}

static func _period_for(kind: String) -> String:
	if kind == "daily":
		var date := Time.get_date_dict_from_system(true)
		return "day:%04d-%02d-%02d" % [int(date.get("year", 0)), int(date.get("month", 0)), int(date.get("day", 0))]
	if kind == "weekly":
		return "week:%d" % floori(Time.get_unix_time_from_system() / 604800.0)
	return "season:" + str(_config().get("season", {}).get("id", "mountain_depths_proposal_01"))

static func _sync_progress(p: Dictionary) -> void:
	var g := GameMath.game(p)
	var meta: Dictionary = g["meta"]
	var tracking: Dictionary = meta["tracking"]
	var stats: Dictionary = g["stats"]
	var previous: Dictionary = tracking.get("last_stats", {})
	var deltas: Dictionary = {}
	for key in stats:
		var current := maxf(0.0, float(stats.get(key, 0.0)))
		var old := maxf(0.0, float(previous.get(key, current)))
		deltas[str(key)] = maxi(0, floori(current - old))
	tracking["last_stats"] = stats.duplicate(true)
	var season: Dictionary = meta["season"]
	for row in GameMath.records("season_tasks"):
		var task_id := str(row.get("template_id", ""))
		var kind := str(row.get("kind", "season_once"))
		var task: Dictionary = season["tasks"].get(task_id, {})
		var period := _period_for(kind)
		if str(task.get("period_id", "")) != period:
			task = {"period_id":period, "progress":0, "claimed":false}
			season["tasks"][task_id] = task
		if task_id.begins_with("LONG"):
			continue
		var event_key := str(row.get("progress_event", ""))
		var amount := int(deltas.get(event_key, 0))
		if amount > 0 and not bool(task.get("claimed", false)):
			task["progress"] = mini(int(row.get("target_count", 1)), int(task.get("progress", 0)) + amount)
	var long_delta := int(deltas.get("season_project_completed", 0))
	var seen := int(tracking.get("long_projects_seen", 0))
	for i in range(long_delta):
		var long_index := seen + i + 1
		if long_index > 10:
			break
		var task_id := "LONG%02d" % long_index
		var task: Dictionary = season["tasks"].get(task_id, {})
		if not task.is_empty() and not bool(task.get("claimed", false)):
			task["progress"] = 1
	tracking["long_projects_seen"] = mini(10, seen + long_delta)
	var event_cfg: Dictionary = _config().get("events", {})
	for row in GameMath.records("events"):
		var event_id := str(row.get("id", ""))
		var state: Dictionary = meta["events"].get(event_id, {"progress":0, "claimed":false})
		if not _event_site_open(p, str(row.get("site", ""))) or bool(state.get("claimed", false)):
			meta["events"][event_id] = state
			continue
		var hook: Dictionary = event_cfg.get("hooks", {}).get(event_id, {})
		var amount := int(deltas.get(str(hook.get("stat", "")), 0))
		if amount > 0:
			state["progress"] = mini(_event_target(event_id), int(state.get("progress", 0)) + amount)
		meta["events"][event_id] = state

static func _rebuild_bonuses(p: Dictionary) -> void:
	var g := GameMath.game(p)
	var meta: Dictionary = g["meta"]
	var result: Dictionary = {}
	for site in SITE_KEYS:
		if not _site_is_open(p, site):
			continue
		var gear: Dictionary = meta["gear"]
		var equipped: Dictionary = gear["equipped"].get(site, {})
		for slot in equipped:
			var item := _gear_item_by_id(gear["items"], str(equipped[slot]))
			if not item.is_empty():
				_add_gear_bonus(result, site, item)
		var assignments: Dictionary = meta["specialists"]["assignments"].get(site, {})
		for specialist_id in assignments.values():
			var progress: Dictionary = meta["specialists"]["owned"].get(str(specialist_id), {})
			var row := GameMath.record("specialists", str(specialist_id))
			if not row.is_empty() and not progress.is_empty():
				_add_specialist_bonus(result, site, row, progress)
	for boost in meta["boosts"]:
		var site := str(boost.get("site", "fe"))
		var stat := str(boost.get("stat", "output"))
		if EFFECT_KEYS.has(stat) and float(boost.get("remaining_s", 0.0)) > 0.0:
			_add_bonus(result, site, stat, float(boost.get("amount", 0.0)))
	g["bonuses"]["meta"] = result

static func _add_gear_bonus(result: Dictionary, site: String, item: Dictionary) -> void:
	var cfg := _config().get("equipment", {})
	var effects: Dictionary = cfg.get("slot_effects", {}).get(site, {}).get(str(item.get("slot", "")), {})
	var rarity_multiplier := float(cfg.get("rarity_multipliers", {}).get(str(item.get("rarity", "Обычный")), 1.0))
	var level := clampi(int(item.get("level", 1)), 1, int(cfg.get("level_cap", 100)))
	var stars := clampi(int(item.get("stars", 0)), 0, int(cfg.get("star_cap", 5)))
	var multiplier := (1.0 + float(cfg.get("effect_per_level", 0.0)) * float(level - 1)) * (1.0 + float(cfg.get("effect_per_star", 0.0)) * stars) * rarity_multiplier
	for stat in effects:
		_add_bonus(result, site, str(stat), float(effects[stat]) * multiplier)

static func _add_specialist_bonus(result: Dictionary, team_site: String, row: Dictionary, progress: Dictionary) -> void:
	var level_cap := maxi(1, int(row.get("level_cap", 100)))
	var level := clampi(int(progress.get("level", 1)), 1, level_cap)
	var stars := clampi(int(progress.get("stars", 0)), 0, int(row.get("star_cap", 5)))
	var ratio := float(level - 1) / float(maxi(1, level_cap - 1))
	var value := float(row.get("base", 0.0)) + (float(row.get("max", 0.0)) - float(row.get("base", 0.0))) * ratio
	value *= 1.0 + float(_config().get("specialists", {}).get("effect_per_star", 0.0)) * stars
	var stat := _specialist_effect_key(row)
	if str(row.get("unit", "percent")) == "percent":
		value /= 100.0
	elif stat == "storage":
		value *= float(_config().get("specialists", {}).get("storage_capacity_per_slot", 1000))
	if stat == "storage" and str(row.get("unit", "")) == "percent":
		value *= float(_config().get("specialists", {}).get("storage_base_capacity", 10000))
	var target_site := team_site
	if team_site == "vip":
		target_site = "global"
	_add_bonus(result, target_site, stat, value)

static func _specialist_effect_key(row: Dictionary) -> String:
	var stat := str(row.get("stat", ""))
	var target := str(row.get("target", ""))
	if stat == "tap_bonus":
		return "weak" if target.contains("weak_point") else "tap"
	if stat in ["operating_cost_saving", "salary_saving", "material_input_saving"]:
		return "wage"
	if stat in ["storage_capacity", "storage_reserved_slots", "queue_capacity"]:
		return "storage"
	if stat in ["survey_speed", "campaign_speed", "resonance_duration"]:
		return "speed"
	if stat in ["survey_precision", "geology_normal_samples"] or target.contains("weak_point") or target.contains("deep_scan") or target.contains("quality"):
		return "weak"
	return "output"

static func _add_bonus(result: Dictionary, site: String, stat: String, amount: float) -> void:
	if not EFFECT_KEYS.has(stat):
		return
	var key := stat if site == "global" else site + ":" + stat
	result[key] = float(result.get(key, 0.0)) + amount

static func _site_is_open(p: Dictionary, site: String) -> bool:
	return site == "global" or (SITE_IDS.has(site) and GameMath.unlocked(p, site))

static func _site_key_for_name(name: String) -> String:
	return str(SITE_NAMES.get(name, "global"))

static func _event_site_open(p: Dictionary, site: String) -> bool:
	if site in ["any", "geology", "fe"]:
		return _site_is_open(p, "fe")
	if site == "pd":
		return _site_is_open(p, "pd")
	if site == "ir":
		return _site_is_open(p, "ir")
	return false

static func _event_target(event_id: String) -> int:
	return int(_config().get("events", {}).get("hooks", {}).get(event_id, {}).get("target", 1))

static func _rank_allowed(row: Dictionary, rank: int) -> bool:
	var required := str(row.get("rank_required", "")).strip_edges()
	return required.is_empty() or rank >= int(required)

static func _vip_rank(_p: Dictionary) -> int:
	return 0

static func _team_slots(p: Dictionary) -> Dictionary:
	var base: Dictionary = _config().get("specialists", {}).get("team_slots", {"fe":5, "pd":3, "ir":3})
	return {"fe":int(base.get("fe", 5)), "pd":int(base.get("pd", 3)), "ir":int(base.get("ir", 3)), "vip":int(_config().get("specialists", {}).get("vip8_global_extra_slots", 1)) if _vip_rank(p) >= 8 else 0}

static func _gear_item_by_id(items: Array, item_id: String) -> Dictionary:
	for item in items:
		if str(item.get("id", "")) == item_id:
			return item
	return {}

static func _specialist_row(specialist_id: String) -> Dictionary:
	return GameMath.record("specialists", specialist_id)

static func _specialist_available_for_case(p: Dictionary, row: Dictionary) -> bool:
	var site := _site_key_for_name(str(row.get("site", "")))
	return _rank_allowed(row, _vip_rank(p)) and (site == "global" or _site_is_open(p, site))

static func _eligible_specialist_ids(p: Dictionary, rarity: String) -> Array:
	var result: Array = []
	for row in GameMath.records("specialists"):
		if not _specialist_available_for_case(p, row):
			continue
		if not rarity.is_empty() and str(row.get("rarity", "")) != rarity:
			continue
		result.append(str(row.get("id", "")))
	result.sort()
	return result

static func _case_available(p: Dictionary, case_id: String) -> bool:
	for row in GameMath.records("cases"):
		if str(row.get("id", "")) != case_id:
			continue
		var unlock := str(row.get("unlock", ""))
		if unlock == "VIP4":
			return _vip_rank(p) >= 4
		return unlock == "Fe" and _site_is_open(p, "fe")
	return false

static func _weight_total(weights: Variant) -> int:
	if not weights is Dictionary:
		return 0
	var total := 0
	for value in weights.values():
		total += int(value)
	return total

static func _task_claim_id(task_id: String, period_id: String) -> String:
	return "season_task:%s:%s" % [period_id, task_id]

static func _season_claim_id(level: int, lane: String) -> String:
	return "season_level:%s:%d:%s" % [str(_config().get("season", {}).get("id", "")), level, lane]
