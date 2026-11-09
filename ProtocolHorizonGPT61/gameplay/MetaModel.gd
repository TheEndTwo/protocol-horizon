class_name EarthMeta
extends RefCounted

const CONFIG_PATH := "res://data/proposals/meta.json"
const SITE_KEYS := ["fe", "pd", "ir"]
const SITE_IDS := {"fe":"site_earth_fe_17", "pd":"site_earth_pd_7", "ir":"site_earth_ir_9"}
const SITE_NAMES := {"Fe":"fe", "Pd":"pd", "Ir":"ir", "Global":"global"}
const EFFECT_KEYS := ["output", "tap", "crit", "weak", "wage", "storage", "speed"]

static func ensure(p: Dictionary) -> void:
	var g := GameMath.game(p)
	if not g.has("meta") or not (g["meta"] is Dictionary):
		g["meta"] = {}
	var meta: Dictionary = g["meta"]
	var cfg := _config()
	var new_meta := meta.is_empty()
	if not meta.has("gear") or not (meta["gear"] is Dictionary):
		meta["gear"] = {"items":[], "equipped":{}, "fragments":{}}
	var gear: Dictionary = meta["gear"]
	_ensure_fields(gear, {"items":[], "equipped":{}, "fragments":{}})
	if not meta.has("specialists") or not (meta["specialists"] is Dictionary):
		meta["specialists"] = {"owned":{}, "assignments":{}, "fragments":{}}
	var specialists: Dictionary = meta["specialists"]
	_ensure_fields(specialists, {"owned":{}, "assignments":{}, "fragments":{}})
	if new_meta or specialists["owned"].is_empty():
		var starter_id := str(cfg.get("specialists", {}).get("starter_id", "SP01"))
		if not specialists["owned"].has(starter_id):
			specialists["owned"][starter_id] = {"level":1, "stars":0}
	if not meta.has("cases") or not (meta["cases"] is Dictionary):
		meta["cases"] = {"opened":{}, "pity":{}}
	_ensure_fields(meta["cases"], {"opened":{}, "pity":{}})
	if not meta.has("season") or not (meta["season"] is Dictionary):
		meta["season"] = {"id":str(cfg.get("season", {}).get("id", "mountain_depths_proposal_01")), "xp":0, "tasks":{}}
	_ensure_fields(meta["season"], {"id":str(cfg.get("season", {}).get("id", "mountain_depths_proposal_01")), "xp":0, "tasks":{}})
	for key in ["events", "claims", "milestones", "evidence"]:
		if not meta.has(key) or not (meta[key] is Dictionary):
			meta[key] = {}
	if not meta.has("boosts") or not (meta["boosts"] is Array):
		meta["boosts"] = []
	if not meta.has("tracking") or not (meta["tracking"] is Dictionary):
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
		var specialist_ids := _case_specialist_ids(snapshot, item)
		item["eligible_specialist_ids"] = specialist_ids
		case_view.append(item)
		case_pools[case_id] = specialist_ids
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
		"specialists":{"catalog":specialist_view, "owned":owned.duplicate(true), "assignments":meta["specialists"]["assignments"].duplicate(true), "fragments":meta["specialists"]["fragments"].duplicate(true), "team_slots":_team_slots(snapshot)},
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
		var old := maxf(0.0, float(previous.get(key, 0.0)))
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
	if _vip_rank(p) >= 8:
		var vip_assignments: Dictionary = meta["specialists"]["assignments"].get("vip", {})
		for specialist_id in vip_assignments.values():
			var progress: Dictionary = meta["specialists"]["owned"].get(str(specialist_id), {})
			var row := GameMath.record("specialists", str(specialist_id))
			if not row.is_empty() and not progress.is_empty():
				_add_specialist_bonus(result, "vip", row, progress)
	for boost in meta["boosts"]:
		var site := str(boost.get("site", "fe"))
		var stat := str(boost.get("stat", "output"))
		if EFFECT_KEYS.has(stat) and float(boost.get("remaining_s", 0.0)) > 0.0:
			_add_bonus(result, site, stat, float(boost.get("amount", 0.0)))
	g["bonuses"]["meta"] = result

static func _add_gear_bonus(result: Dictionary, site: String, item: Dictionary) -> void:
	var cfg: Dictionary = _config().get("equipment", {})
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
	var key := stat if site == "global" or stat == "storage" else site + ":" + stat
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

static func _case_specialist_ids(p: Dictionary, case_row: Dictionary) -> Array:
	if not bool(case_row.get("available", false)):
		return []
	var categories: Dictionary = case_row.get("category_prob_pct", {})
	if int(categories.get("specialist_card_or_fragments", 0)) <= 0:
		return []
	var result: Dictionary = {}
	var rarity_weights: Dictionary = case_row.get("rarity_prob_pct", {})
	for rarity in rarity_weights:
		if int(rarity_weights[rarity]) <= 0:
			continue
		for specialist_id in _eligible_specialist_ids(p, str(rarity)):
			result[specialist_id] = true
	var ids: Array = result.keys()
	ids.sort()
	return ids

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

static func _gear_equip(p: Dictionary, args: Dictionary) -> Dictionary:
	var site := str(args.get("site", "fe"))
	var slot := str(args.get("slot", ""))
	var item_id := str(args.get("item_id", ""))
	if not SITE_KEYS.has(site) or not _site_is_open(p, site):
		return GameMath.fail("Этот участок пока закрыт")
	var slots: Array = _config().get("equipment", {}).get("site_slots", {}).get(site, [])
	if not slots.has(slot):
		return GameMath.fail("Неизвестный слот снаряжения")
	var gear: Dictionary = GameMath.game(p)["meta"]["gear"]
	var item := _gear_item_by_id(gear["items"], item_id)
	if item.is_empty() or str(item.get("site", "")) != site or str(item.get("slot", "")) != slot:
		return GameMath.fail("Предмет не подходит этому слоту")
	var equipped: Dictionary = gear["equipped"].get(site, {})
	equipped[slot] = item_id
	gear["equipped"][site] = equipped
	return _success("Снаряжение установлено", {"item_id":item_id})

static func _gear_unequip(p: Dictionary, args: Dictionary) -> Dictionary:
	var site := str(args.get("site", "fe"))
	var slot := str(args.get("slot", ""))
	if not SITE_KEYS.has(site) or not _site_is_open(p, site):
		return GameMath.fail("Этот участок пока закрыт")
	var equipped: Dictionary = GameMath.game(p)["meta"]["gear"]["equipped"].get(site, {})
	if not equipped.has(slot):
		return GameMath.fail("Слот уже пуст")
	equipped.erase(slot)
	GameMath.game(p)["meta"]["gear"]["equipped"][site] = equipped
	return _success("Предмет снят")

static func _gear_upgrade(p: Dictionary, args: Dictionary) -> Dictionary:
	var meta: Dictionary = GameMath.game(p)["meta"]
	var gear: Dictionary = meta["gear"]
	var item := _gear_item_by_id(gear["items"], str(args.get("item_id", "")))
	if item.is_empty():
		return GameMath.fail("Предмет не найден")
	var cfg: Dictionary = _config().get("equipment", {})
	var level := int(item.get("level", 1))
	var cap := int(cfg.get("level_cap", 100))
	if level >= cap:
		return GameMath.fail("Достигнут максимальный уровень")
	var cost := int(cfg.get("upgrade_base_cost_cents", 0)) + level * int(cfg.get("upgrade_cost_per_level_cents", 0))
	if not p.has("money_cents") or not GameMath.pay(p, cost):
		return GameMath.fail("Недостаточно гелионов")
	item["level"] = level + 1
	return _success("Уровень снаряжения повышен", {"level":item["level"], "cost_cents":cost})

static func _gear_star(p: Dictionary, args: Dictionary) -> Dictionary:
	var meta: Dictionary = GameMath.game(p)["meta"]
	var gear: Dictionary = meta["gear"]
	var item := _gear_item_by_id(gear["items"], str(args.get("item_id", "")))
	if item.is_empty():
		return GameMath.fail("Предмет не найден")
	var stars := int(item.get("stars", 0))
	var cap := int(_config().get("equipment", {}).get("star_cap", 5))
	var costs: Array = _config().get("equipment", {}).get("star_fragment_costs", [])
	if stars >= cap or stars >= costs.size():
		return GameMath.fail("Достигнут предел звёзд")
	var template := str(item.get("template_id", ""))
	var fragments: Dictionary = gear["fragments"]
	var needed := int(costs[stars])
	if int(fragments.get(template, 0)) < needed:
		return GameMath.fail("Недостаточно фрагментов этого предмета")
	fragments[template] = int(fragments[template]) - needed
	item["stars"] = stars + 1
	return _success("Звезда снаряжения улучшена", {"stars":item["stars"], "fragments_spent":needed})

static func _specialist_assign(p: Dictionary, args: Dictionary) -> Dictionary:
	var specialist_id := str(args.get("specialist_id", ""))
	var site := str(args.get("site", "fe"))
	var slot := int(args.get("slot", -1))
	var meta: Dictionary = GameMath.game(p)["meta"]
	var team_slots := _team_slots(p)
	if not team_slots.has(site) or slot < 0 or slot >= int(team_slots[site]):
		return GameMath.fail("Нет свободного слота специалиста")
	if site != "vip" and (not SITE_KEYS.has(site) or not _site_is_open(p, site)):
		return GameMath.fail("Этот участок пока закрыт")
	var owned: Dictionary = meta["specialists"]["owned"]
	if not owned.has(specialist_id):
		return GameMath.fail("Специалист ещё не получен")
	var row := _specialist_row(specialist_id)
	if row.is_empty() or not _rank_allowed(row, _vip_rank(p)):
		return GameMath.fail("Специалист недоступен без подтверждённого VIP")
	var row_site := _site_key_for_name(str(row.get("site", "")))
	if site == "vip":
		if row_site != "global" or _vip_rank(p) < 8:
			return GameMath.fail("VIP-слот пока недоступен")
	elif row_site != "global" and row_site != site:
		return GameMath.fail("Специалист предназначен для другого участка")
	var assignments: Dictionary = meta["specialists"]["assignments"]
	for assigned_site in assignments:
		for assigned_id in assignments[assigned_site].values():
			if str(assigned_id) == specialist_id:
				return GameMath.fail("Специалист уже назначен")
	var team: Dictionary = assignments.get(site, {})
	var slot_key := str(slot)
	if team.has(slot_key):
		return GameMath.fail("Слот уже занят")
	team[slot_key] = specialist_id
	assignments[site] = team
	return _success("Специалист назначен", {"specialist_id":specialist_id, "site":site, "slot":slot})

static func _specialist_unassign(p: Dictionary, args: Dictionary) -> Dictionary:
	var site := str(args.get("site", "fe"))
	var slot_key := str(int(args.get("slot", -1)))
	var assignments: Dictionary = GameMath.game(p)["meta"]["specialists"]["assignments"]
	var team: Dictionary = assignments.get(site, {})
	if not team.has(slot_key):
		return GameMath.fail("Слот уже пуст")
	var specialist_id := str(team[slot_key])
	team.erase(slot_key)
	assignments[site] = team
	return _success("Специалист снят", {"specialist_id":specialist_id})

static func _specialist_level(p: Dictionary, args: Dictionary) -> Dictionary:
	var specialist_id := str(args.get("specialist_id", ""))
	var meta: Dictionary = GameMath.game(p)["meta"]
	var owned: Dictionary = meta["specialists"]["owned"]
	if not owned.has(specialist_id):
		return GameMath.fail("Специалист ещё не получен")
	var row := _specialist_row(specialist_id)
	if row.is_empty():
		return GameMath.fail("Канонический специалист не найден")
	var state: Dictionary = owned[specialist_id]
	var level := int(state.get("level", 1))
	var cap := int(row.get("level_cap", 100))
	if level >= cap:
		return GameMath.fail("Достигнут максимальный уровень")
	var cfg: Dictionary = _config().get("specialists", {})
	var cost := int(cfg.get("level_base_cost_cents", 0)) + level * int(cfg.get("level_cost_per_level_cents", 0))
	if not p.has("money_cents") or not GameMath.pay(p, cost):
		return GameMath.fail("Недостаточно гелионов")
	state["level"] = level + 1
	return _success("Уровень специалиста повышен", {"specialist_id":specialist_id, "level":state["level"], "cost_cents":cost})

static func _specialist_star(p: Dictionary, args: Dictionary) -> Dictionary:
	var specialist_id := str(args.get("specialist_id", ""))
	var meta: Dictionary = GameMath.game(p)["meta"]
	var specialists: Dictionary = meta["specialists"]
	var owned: Dictionary = specialists["owned"]
	if not owned.has(specialist_id):
		return GameMath.fail("Специалист ещё не получен")
	var row := _specialist_row(specialist_id)
	if row.is_empty():
		return GameMath.fail("Канонический специалист не найден")
	var state: Dictionary = owned[specialist_id]
	var stars := int(state.get("stars", 0))
	var costs: Array = _config().get("specialists", {}).get("star_fragment_costs", [])
	var cap := int(row.get("star_cap", 5))
	if stars >= cap or stars >= costs.size():
		return GameMath.fail("Достигнут предел звёзд")
	var fragments: Dictionary = specialists["fragments"]
	var needed := int(costs[stars])
	if int(fragments.get(specialist_id, 0)) < needed:
		return GameMath.fail("Недостаточно фрагментов этого специалиста")
	fragments[specialist_id] = int(fragments[specialist_id]) - needed
	state["stars"] = stars + 1
	return _success("Звезда специалиста улучшена", {"specialist_id":specialist_id, "stars":state["stars"], "fragments_spent":needed})

static func _claim_case_milestone(p: Dictionary, args: Dictionary) -> Dictionary:
	var milestone_id := str(args.get("milestone_id", ""))
	var meta: Dictionary = GameMath.game(p)["meta"]
	var milestones: Array = _config().get("cases", {}).get("free_case_milestones", [])
	for milestone in milestones:
		if str(milestone.get("id", "")) != milestone_id:
			continue
		if bool(meta["milestones"].get(milestone_id, false)):
			return GameMath.fail("Награда уже получена")
		var actual := float(GameMath.game(p)["stats"].get(str(milestone.get("stat", "")), 0.0))
		if actual < float(milestone.get("target", 0)):
			return GameMath.fail("Этап ещё не выполнен")
		var reward: Dictionary = milestone.get("reward", {})
		_grant_proposal_reward(p, reward)
		meta["milestones"][milestone_id] = true
		return _success("Бесплатный кейс получен", {"milestone_id":milestone_id, "reward":reward.duplicate(true)})
	return GameMath.fail("Неизвестный этап")

static func _claim_season_task(p: Dictionary, args: Dictionary) -> Dictionary:
	refresh(p)
	var task_id := str(args.get("task_id", ""))
	var meta: Dictionary = GameMath.game(p)["meta"]
	var row: Dictionary = {}
	for candidate in GameMath.records("season_tasks"):
		if str(candidate.get("template_id", "")) == task_id:
			row = candidate
			break
	if row.is_empty():
		return GameMath.fail("Задание не найдено")
	var state: Dictionary = meta["season"]["tasks"].get(task_id, {})
	var target := int(row.get("target_count", 0))
	if int(state.get("progress", 0)) < target:
		return GameMath.fail("Задание ещё не выполнено")
	var claim_id := _task_claim_id(task_id, str(state.get("period_id", "")))
	if meta["claims"].has(claim_id):
		return GameMath.fail("Награда уже получена")
	meta["claims"][claim_id] = true
	state["claimed"] = true
	meta["season"]["xp"] = int(meta["season"].get("xp", 0)) + int(row.get("xp_reward", 0))
	return _success("Опыт сезона получен", {"claim_id":claim_id, "xp":int(row.get("xp_reward", 0))})

static func _claim_season_reward(p: Dictionary, args: Dictionary) -> Dictionary:
	var level := int(args.get("level", 0))
	var lane := str(args.get("lane", "free"))
	if lane != "free":
		return GameMath.fail("Премиальная дорожка недоступна без подтверждённой покупки")
	var cfg: Dictionary = _config().get("season", {})
	var xp_per_level := maxi(1, int(cfg.get("xp_per_level", 100)))
	var current_level := mini(int(cfg.get("level_cap", 60)), int(floor(float(GameMath.game(p)["meta"]["season"].get("xp", 0)) / xp_per_level)))
	if level < 1 or level > current_level:
		return GameMath.fail("Уровень сезона ещё не открыт")
	var claim_id := _season_claim_id(level, lane)
	var meta: Dictionary = GameMath.game(p)["meta"]
	if meta["claims"].has(claim_id):
		return GameMath.fail("Награда уже получена")
	var reward: Dictionary = {}
	for row in cfg.get("levels", []):
		if int(row.get("level", 0)) == level:
			reward = row.get(lane, {})
			break
	if reward.is_empty():
		return GameMath.fail("Награда для уровня не настроена")
	_grant_proposal_reward(p, reward)
	meta["claims"][claim_id] = true
	return _success("Предложенная награда сезона получена", {"claim_id":claim_id, "reward":reward.duplicate(true), "reward_status":"provisional_not_canon"})

static func _claim_event(p: Dictionary, args: Dictionary) -> Dictionary:
	refresh(p)
	var event_id := str(args.get("event_id", ""))
	var row: Dictionary = {}
	for candidate in GameMath.records("events"):
		if str(candidate.get("id", "")) == event_id:
			row = candidate
			break
	if row.is_empty() or not _event_site_open(p, str(row.get("site", ""))):
		return GameMath.fail("Событие пока недоступно")
	var meta: Dictionary = GameMath.game(p)["meta"]
	var state: Dictionary = meta["events"].get(event_id, {})
	if int(state.get("progress", 0)) < _event_target(event_id):
		return GameMath.fail("Событие ещё не выполнено")
	var claim_id := "event:" + event_id
	if meta["claims"].has(claim_id):
		return GameMath.fail("Награда уже получена")
	var reward: Dictionary = _config().get("events", {}).get("rewards", {}).get(event_id, {})
	if reward.is_empty():
		return GameMath.fail("Награда события не настроена")
	_grant_event_reward(p, event_id, reward)
	meta["claims"][claim_id] = true
	state["claimed"] = true
	meta["events"][event_id] = state
	return _success("Награда события получена", {"claim_id":claim_id, "reward":reward.duplicate(true), "reward_status":"provisional"})

static func _grant_event_reward(p: Dictionary, event_id: String, reward: Dictionary) -> void:
	var kind := str(reward.get("kind", ""))
	if kind == "material":
		_grant_material(p, str(reward.get("resource_id", "")), int(reward.get("amount", 0)))
	elif kind == "money_cents":
		p["money_cents"] = int(p.get("money_cents", 0)) + int(reward.get("amount", 0))
	elif kind == "evidence":
		GameMath.game(p)["meta"]["evidence"][event_id] = true
	GameMath.game(p)["meta"]["season"]["xp"] = int(GameMath.game(p)["meta"]["season"].get("xp", 0)) + int(reward.get("season_xp", 0))

static func _case_open(p: Dictionary, args: Dictionary) -> Dictionary:
	var case_id := str(args.get("case_id", ""))
	var open_id := str(args.get("open_id", "")).strip_edges()
	if open_id.is_empty():
		return GameMath.fail("Нужен уникальный идентификатор открытия")
	var meta: Dictionary = GameMath.game(p)["meta"]
	var opened: Dictionary = meta["cases"]["opened"]
	if opened.has(open_id):
		var prior: Dictionary = opened[open_id]
		if str(prior.get("case_id", "")) != case_id:
			return GameMath.fail("Этот идентификатор открытия уже использован")
		return _success("Результат уже зафиксирован", {"open_id":open_id, "case_open_id":open_id, "seed":int(prior.get("seed", 0)), "table_version":str(prior.get("table_version", "")), "result":prior.get("result", {}).duplicate(true), "replayed":true})
	if not _case_available(p, case_id):
		return GameMath.fail("Этот кейс недоступен")
	var row: Dictionary = {}
	for candidate in GameMath.records("cases"):
		if str(candidate.get("id", "")) == case_id:
			row = candidate
			break
	if row.is_empty():
		return GameMath.fail("Кейс не найден")
	if _weight_total(row.get("rarity_prob_pct", {})) != 100 or _weight_total(row.get("category_prob_pct", {})) != 100:
		return GameMath.fail("Таблица вероятностей кейса некорректна")
	var inventory: Dictionary = p.get("inventory", {})
	var amount := int(inventory.get(case_id, 0))
	if amount <= 0:
		return GameMath.fail("Нет бесплатного кейса этого типа")
	var table_version := str(_config().get("cases", {}).get("table_version", "cases_v8"))
	var seed := _stable_seed("%s|%s|%s|%s" % [str(p.get("profile_id", "local")), case_id, open_id, table_version])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rarity := _roll_rarity(p, case_id, row, rng)
	var category := _weighted_pick(rng, row.get("category_prob_pct", {}))
	var reward := _grant_case_category(p, open_id, rarity, category, rng)
	var result := {"rarity":rarity, "category":category, "reward":reward}
	var record := {"case_open_id":open_id, "case_id":case_id, "seed":seed, "table_version":table_version, "result":result.duplicate(true)}
	inventory[case_id] = amount - 1
	p["inventory"] = inventory
	opened[open_id] = record
	return _success("Кейс открыт", {"open_id":open_id, "case_open_id":open_id, "seed":seed, "table_version":table_version, "result":result.duplicate(true), "replayed":false})

static func _roll_rarity(p: Dictionary, case_id: String, row: Dictionary, rng: RandomNumberGenerator) -> String:
	var chosen := _weighted_pick(rng, row.get("rarity_prob_pct", {}))
	var pity_all: Dictionary = GameMath.game(p)["meta"]["cases"]["pity"]
	var pity: Dictionary = pity_all.get(case_id, {"since_epic":0, "since_legendary":0, "since_mythic":0})
	var thresholds: Dictionary = row.get("pity", {})
	if int(pity.get("since_mythic", 0)) >= maxi(0, int(thresholds.get("mythic", 120)) - 1):
		chosen = "Мифический"
	elif int(pity.get("since_legendary", 0)) >= maxi(0, int(thresholds.get("legendary_or_higher", 40)) - 1):
		chosen = "Легендарный" if _rarity_rank(chosen) < _rarity_rank("Легендарный") else chosen
	elif int(pity.get("since_epic", 0)) >= maxi(0, int(thresholds.get("epic_or_higher", 10)) - 1):
		chosen = "Эпический" if _rarity_rank(chosen) < _rarity_rank("Эпический") else chosen
	if _rarity_rank(chosen) >= _rarity_rank("Эпический"):
		pity["since_epic"] = 0
	else:
		pity["since_epic"] = int(pity.get("since_epic", 0)) + 1
	if _rarity_rank(chosen) >= _rarity_rank("Легендарный"):
		pity["since_legendary"] = 0
	else:
		pity["since_legendary"] = int(pity.get("since_legendary", 0)) + 1
	if chosen == "Мифический":
		pity["since_mythic"] = 0
	else:
		pity["since_mythic"] = int(pity.get("since_mythic", 0)) + 1
	pity_all[case_id] = pity
	return chosen

static func _rarity_rank(rarity: String) -> int:
	var rank := ["Обычный", "Редкий", "Эпический", "Легендарный", "Мифический"].find(rarity)
	return maxi(0, rank)

static func _weighted_pick(rng: RandomNumberGenerator, weights: Variant) -> String:
	if not weights is Dictionary:
		return ""
	var keys: Array = weights.keys()
	keys.sort()
	var total := 0
	for key in keys:
		total += maxi(0, int(weights[key]))
	if total <= 0:
		return ""
	var roll := rng.randi_range(1, total)
	var cursor := 0
	for key in keys:
		cursor += maxi(0, int(weights[key]))
		if roll <= cursor:
			return str(key)
	return str(keys.back())

static func _grant_case_category(p: Dictionary, open_id: String, rarity: String, category: String, rng: RandomNumberGenerator) -> Dictionary:
	var meta: Dictionary = GameMath.game(p)["meta"]
	var case_cfg: Dictionary = _config().get("cases", {})
	match category:
		"specialist_card_or_fragments":
			var candidates := _eligible_specialist_ids(p, rarity)
			if candidates.is_empty():
				candidates = _eligible_specialist_ids(p, "")
			if candidates.is_empty():
				_add_shards(p, int(case_cfg.get("currency_rewards", {}).get("shards", 20)))
				return {"kind":"shards", "amount":int(case_cfg.get("currency_rewards", {}).get("shards", 20)), "fallback":"no_eligible_specialist"}
			var specialist_id: String = candidates[rng.randi_range(0, candidates.size() - 1)]
			var owned: Dictionary = meta["specialists"]["owned"]
			if owned.has(specialist_id):
				var fragments: Dictionary = meta["specialists"]["fragments"]
				var count := int(case_cfg.get("specialist_card_duplicate_fragments", 5))
				fragments[specialist_id] = int(fragments.get(specialist_id, 0)) + count
				return {"kind":"specialist_fragments", "specialist_id":specialist_id, "amount":count}
			owned[specialist_id] = {"level":1, "stars":0}
			return {"kind":"specialist", "specialist_id":specialist_id}
		"equipment_card_or_fragments":
			var sites: Array = []
			for site in SITE_KEYS:
				if _site_is_open(p, site):
					sites.append(site)
			if sites.is_empty():
				_add_shards(p, 20)
				return {"kind":"shards", "amount":20, "fallback":"no_open_site"}
			var site: String = sites[rng.randi_range(0, sites.size() - 1)]
			var slots: Array = _config().get("equipment", {}).get("site_slots", {}).get(site, [])
			var slot: String = str(slots[rng.randi_range(0, slots.size() - 1)])
			var template_id := "case_%s_%s" % [site, slot]
			var gear: Dictionary = meta["gear"]
			for owned_item in gear["items"]:
				if str(owned_item.get("template_id", "")) == template_id and str(owned_item.get("rarity", "")) == rarity:
					var fragments: Dictionary = gear["fragments"]
					var count := int(case_cfg.get("equipment_duplicate_fragments", 5))
					fragments[template_id] = int(fragments.get(template_id, 0)) + count
					return {"kind":"equipment_fragments", "template_id":template_id, "amount":count}
			var item_id := "gear_case_" + str(p.get("profile_id", "local")).sha256_text().substr(0, 8) + "_" + _stable_hex(open_id)
			var item := {"id":item_id, "site":site, "slot":slot, "template_id":template_id, "rarity":rarity, "level":1, "stars":0, "source":"case"}
			gear["items"].append(item)
			return {"kind":"equipment", "item":item.duplicate(true)}
		"industrial_materials":
			var resources: Array = []
			for site in SITE_KEYS:
				if _site_is_open(p, site):
					resources.append({"fe":"iron_ore", "pd":"pd_concentrate", "ir":"ir_core"}[site])
			var resource_id: String = str(resources[rng.randi_range(0, resources.size() - 1)])
			var count := int(case_cfg.get("industrial_material_amount", 1))
			var accepted := GameMath.add(p, resource_id, count)
			if accepted > 0:
				return {"kind":"material", "resource_id":resource_id, "amount":accepted}
			var fallback := int(case_cfg.get("currency_rewards", {}).get("shards", 20))
			_add_shards(p, fallback)
			return {"kind":"shards", "amount":fallback, "fallback":"warehouse_full"}
		"shards":
			var shards := int(case_cfg.get("currency_rewards", {}).get("shards", 20))
			_add_shards(p, shards)
			return {"kind":"shards", "amount":shards}
		"helios":
			var cash := int(case_cfg.get("currency_rewards", {}).get("money_cents", 100))
			p["money_cents"] = int(p.get("money_cents", 0)) + cash
			return {"kind":"money_cents", "amount":cash}
		"boosts":
			var boost_cfg: Dictionary = case_cfg.get("currency_rewards", {})
			var boost := {"id":"boost_" + _stable_hex(open_id), "site":"fe", "stat":"output", "amount":float(boost_cfg.get("boost_output", 0.1)), "remaining_s":float(boost_cfg.get("boost_seconds", 600))}
			meta["boosts"].append(boost)
			return {"kind":"boost", "boost":boost.duplicate(true)}
		_:
			var fallback := int(case_cfg.get("currency_rewards", {}).get("shards", 20))
			_add_shards(p, fallback)
			return {"kind":"shards", "amount":fallback, "fallback":"unknown_category"}


static func _grant_proposal_reward(p: Dictionary, reward: Dictionary) -> void:
	var meta: Dictionary = GameMath.game(p)["meta"]
	var amount := int(reward.get("amount", 0))
	match str(reward.get("kind", "")):
		"money_cents":
			p["money_cents"] = int(p.get("money_cents", 0)) + amount
		"shards":
			_add_shards(p, amount)
		"case":
			var case_id := str(reward.get("case_id", ""))
			if not case_id.is_empty():
				p["inventory"][case_id] = int(p["inventory"].get(case_id, 0)) + amount
		"specialist_fragments":
			var specialist_id := str(reward.get("specialist_id", ""))
			var fragments: Dictionary = meta["specialists"]["fragments"]
			fragments[specialist_id] = int(fragments.get(specialist_id, 0)) + amount
		"equipment_fragments":
			var template_id := str(reward.get("template_id", ""))
			var fragments: Dictionary = meta["gear"]["fragments"]
			fragments[template_id] = int(fragments.get(template_id, 0)) + amount
		"material":
			_grant_material(p, str(reward.get("resource_id", "")), amount)
		"boost":
			meta["boosts"].append({"id":"boost_" + _stable_hex(str(Time.get_ticks_usec())), "site":str(reward.get("site", "fe")), "stat":str(reward.get("stat", "output")), "amount":float(reward.get("effect", 0.1)), "remaining_s":float(reward.get("duration_s", 600))})
		_:
			_add_shards(p, maxi(amount, 1))

static func _grant_material(p: Dictionary, resource_id: String, amount: int) -> void:
	if resource_id.is_empty() or amount <= 0:
		_add_shards(p, 1)
		return
	var accepted := GameMath.add(p, resource_id, amount)
	if accepted < amount:
		_add_shards(p, maxi(1, amount - accepted))

static func _add_shards(p: Dictionary, amount: int) -> void:
	p["shards"] = int(p.get("shards", 0)) + maxi(0, amount)

static func _stable_seed(value: String) -> int:
	var result := 0
	for byte in value.to_utf8_buffer():
		result = int((result * 131 + int(byte)) % 2147483647)
	return maxi(result, 1)

static func _stable_hex(value: String) -> String:
	return value.sha256_text().substr(0, 16)

static func _success(message: String, extra: Dictionary = {}) -> Dictionary:
	var result := GameMath.ok(message)
	for key in extra:
		result[key] = extra[key]
	return result
