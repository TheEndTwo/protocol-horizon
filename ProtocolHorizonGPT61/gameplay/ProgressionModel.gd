class_name EarthProgression
extends RefCounted

const PROPOSAL_PATH := "res://data/proposals/progression.json"
const STORY_IDS := ["A02", "A03", "A04", "A05", "A06", "A07", "A08", "A09", "A10", "A11", "A12", "A13", "A14", "A15", "A16", "A17", "A18", "A19", "A20"]
const FE_MASTERY_MILESTONES := [20, 50, 80, 120, 160, 200, 250, 350]
const BUILDING_ALIASES := {"research_center":"research", "hq":"hq", "deep_station":"deep_station"}
const SITE_MODEL := preload("res://gameplay/SiteModel.gd")

static var _content_cache_loaded := false
static var _catalog_rows: Dictionary = {}
static var _catalog_index: Dictionary = {}
static var _research_dependencies: Dictionary = {}
static var _proposal_cache: Dictionary = {}
static var _research_audit_cache: Dictionary = {}

static func ensure(p: Dictionary) -> void:
	var g := GameMath.game(p)
	if not g.has("progression") or not g["progression"] is Dictionary:
		g["progression"] = {}
	var progression: Dictionary = g["progression"]
	_ensure_fields(progression, {"research":{}, "mastery":{}, "story_done":{}, "story_read":{}, "story_archive":[], "buildings":{}, "expansions":{}})
	if not progression.has("story") or not progression["story"] is Dictionary:
		progression["story"] = {}
	_ensure_fields(progression["story"], {"current_id":"", "flags":{}})
	_ensure_fields(progression["expansions"], {"claims":{}})
	if not progression.has("geology") or not progression["geology"] is Dictionary:
		progression["geology"] = {}
	_ensure_fields(progression["geology"], {"active":{}, "reports":[], "discoveries":{}, "guaranteed_geobinding":false, "cycle":0, "expedition_counts":{}})
	if not progression.has("contracts") or not progression["contracts"] is Dictionary:
		progression["contracts"] = {}
	_ensure_fields(progression["contracts"], {"active":{}, "completed":{}, "sequence":0})
	if not progression.has("effects") or not progression["effects"] is Dictionary:
		progression["effects"] = {}
	_ensure_fields(progression["effects"], {"flags":{}, "mastery":{}, "research_levels":{}})
	if not progression.has("mastery_points"):
		progression["mastery_points"] = 0
	if not progression.has("mastery_points_earned"):
		progression["mastery_points_earned"] = 0
	if not g.has("offline_level"):
		g["offline_level"] = 0
	if not p.has("sites"):
		p["sites"] = {}
	for site_id in GameMath.SITE_IDS.values():
		if not p["sites"].has(site_id):
			p["sites"][site_id] = {"unlocked":site_id == GameMath.SITE_IDS["fe"]}
	if bool(p.get("story", {}).get("intro_seen", false)):
		progression["story_done"]["A01"] = true

static func act(p: Dictionary, action: String, args: Dictionary = {}) -> Dictionary:
	ensure(p)
	var result: Dictionary
	match action:
		"research", "research_buy":
			result = _research(p, str(args.get("id", "")))
		"mastery", "mastery_buy":
			result = _mastery(p, str(args.get("id", "")))
		"story_open":
			result = _story_open(p, str(args.get("id", "")))
		"story_complete":
			result = _story_complete(p, str(args.get("id", "")))
		"story_reserve_contact":
			result = _reserve_story_contact(p)
		"story_transmit":
			result = _story_transmit(p)
		"compare_worker_registry":
			result = _compare_worker_registry(p)
		"propose_alternative_contract":
			result = _propose_alternative_contract(p)
		"enter_cavity":
			result = _enter_cavity(p)
		"geology_start":
			result = _geology_start(p, str(args.get("id", "")))
		"build", "building_start":
			result = _building_start(p, str(args.get("id", "")))
		"contract_accept":
			result = _contract_accept(p, str(args.get("id", "")))
		"contract_ship":
			result = _contract_ship(p, str(args.get("order_id", "")))
		"contract_claim":
			result = _contract_claim(p, str(args.get("order_id", "")))
		"expand", "expansion":
			result = _expand(p, str(args.get("site", "")))
		"offline_upgrade":
			result = _offline_upgrade(p)
		_:
			result = GameMath.fail("Неизвестное действие прогрессии: " + action)
	if bool(result.get("ok", false)):
		refresh(p)
	return result

static func advance(p: Dictionary, seconds: float) -> void:
	ensure(p)
	if not is_finite(seconds) or seconds <= 0.0:
		return
	var delta := seconds
	var progression: Dictionary = GameMath.game(p)["progression"]
	var buildings: Dictionary = progression["buildings"]
	for id in buildings.keys():
		var building: Dictionary = buildings[id]
		if str(building.get("status", "")) != "building":
			continue
		building["remaining_seconds"] = maxf(0.0, float(building.get("remaining_seconds", 0.0)) - delta)
		if float(building["remaining_seconds"]) <= 0.0:
			_complete_building(p, str(id))
	var geology: Dictionary = progression["geology"]
	var expedition: Dictionary = geology["active"]
	if not expedition.is_empty():
		expedition["remaining_seconds"] = maxf(0.0, float(expedition.get("remaining_seconds", 0.0)) - delta)
		if float(expedition["remaining_seconds"]) <= 0.0:
			_complete_expedition(p)
	refresh(p)

static func refresh(p: Dictionary) -> void:
	ensure(p)
	var g := GameMath.game(p)
	var progression: Dictionary = g["progression"]
	var done: Dictionary = progression["story_done"]
	var stats: Dictionary = g["stats"]
	var fe_peak := int(GameMath.site(p, "fe").get("peak", 0))
	var geo: Dictionary = progression["geology"]
	var pd_ready := bool(done.get("A06", false)) and fe_peak >= 350 and float(stats.get("produced:steel", 0.0)) >= 1.0 and bool(geo.get("guaranteed_geobinding", false))
	var ir_ready: bool = bool(done.get("A13", false)) and float(stats.get("produced:pd_catalyst", 0.0)) >= 1.0 and geo["reports"].size() >= 2 and _building_complete(p, "deep_station")
	for site in ["fe", "pd", "ir"]:
		var unlocked: bool = site == "fe" or (site == "pd" and pd_ready) or (site == "ir" and ir_ready)
		var public_id: String = GameMath.SITE_IDS[site]
		if not p["sites"].has(public_id):
			p["sites"][public_id] = {"unlocked":false}
		p["sites"][public_id]["unlocked"] = unlocked
	_refresh_research_bonuses(p)
	_refresh_mastery_points(p)

static func validate(p: Dictionary) -> bool:
	if p.has("game") and not p["game"] is Dictionary:
		return false
	var game: Dictionary = p.get("game", {})
	if not game.has("progression"):
		return true
	if not game["progression"] is Dictionary:
		return false
	var progression: Dictionary = game["progression"]
	for key in ["research", "mastery", "story_done", "story_read", "buildings", "expansions", "geology", "contracts", "story", "effects"]:
		if progression.has(key) and not progression[key] is Dictionary:
			return false
	if progression.has("story_archive") and not progression["story_archive"] is Array:
		return false
	for key in ["research", "mastery"]:
		for rank in progression.get(key, {}).values():
			if not _bounded_integer(rank, 0, 1000):
				return false
	for key in ["mastery_points", "mastery_points_earned"]:
		if progression.has(key) and not _bounded_integer(progression[key], 0, 100000):
			return false
	var geology: Dictionary = progression.get("geology", {})
	if geology.has("active") and not geology["active"] is Dictionary:
		return false
	if geology.has("reports") and not geology["reports"] is Array:
		return false
	var active: Dictionary = geology.get("active", {})
	if not active.is_empty() and (not active.has("id") or not _finite_nonnegative(active.get("remaining_seconds", null))):
		return false
	var contracts: Dictionary = progression.get("contracts", {})
	for key in ["active", "completed"]:
		if contracts.has(key) and not contracts[key] is Dictionary:
			return false
	for building in progression.get("buildings", {}).values():
		if not building is Dictionary or not ["building", "complete", "blocked"].has(str(building.get("status", ""))):
			return false
		if building.has("remaining_seconds") and not _finite_nonnegative(building["remaining_seconds"]):
			return false
	return true

static func available_story(p: Dictionary) -> Array:
	ensure(p)
	var available: Array = []
	var progression: Dictionary = GameMath.game(p)["progression"]
	var done: Dictionary = progression["story_done"]
	for row in _story_rows():
		var id := str(row.get("id", ""))
		if not STORY_IDS.has(id) or bool(done.get(id, false)):
			continue
		var prerequisite := str(row.get("prerequisite_story", ""))
		if not prerequisite.is_empty() and not _story_done(p, prerequisite):
			continue
		var status := _story_status(p, row)
		available.append(status)
	return available

static func research_status(p: Dictionary, id: String) -> Dictionary:
	ensure(p)
	var record := _cached_record("research", id)
	if record.is_empty():
		return {"id":id, "known":false, "can_research":false, "reason":"Нет узла с таким ID в каноне."}
	var progression: Dictionary = GameMath.game(p)["progression"]
	var current := int(progression["research"].get(id, 0))
	var maximum := int(record.get("max_levels", 1))
	var cost := _research_level_cost(record, current + 1)
	var dependencies: Array = _research_dependencies.get(id, []).duplicate()
	var dependency_blockers: Array[String] = []
	for dependency in dependencies:
		var dep_record := _cached_record("research", dependency)
		if dep_record.is_empty() or int(progression["research"].get(dependency, 0)) < int(dep_record.get("max_levels", 1)):
			dependency_blockers.append(dependency)
	var unlock_ok := _research_unlock_met(p, record)
	var points := int(p.get("research_points", 0))
	var can_research := current < maximum and dependency_blockers.is_empty() and unlock_ok and points >= cost
	var proposal: Dictionary = _proposals().get("research_effects", {}).get(id, {})
	var reason := ""
	if current >= maximum:
		reason = "Узел изучен полностью."
	elif not dependency_blockers.is_empty():
		reason = "Сначала завершить зависимости: " + ", ".join(dependency_blockers)
	elif not unlock_ok:
		reason = _research_unlock_reason(p, record)
	elif points < cost:
		reason = "Нужно %d ОИ; доступно %d." % [cost, points]
	return {
		"id":id, "known":true, "record":record, "level":current, "max_levels":maximum,
		"next_cost":cost, "dependencies":dependencies, "dependency_blockers":dependency_blockers,
		"unlocked":unlock_ok and dependency_blockers.is_empty(), "can_research":can_research,
		"reason":reason, "canonical_effect":str(record.get("effect", "")),
		"effect_mode":"proposal" if not proposal.is_empty() else "catalog_only",
		"effect_proposal":proposal, "points":points
	}

static func expansion_preview(p: Dictionary, site: String) -> Dictionary:
	ensure(p)
	if not GameMath.SITES.has(site):
		return {"ok":false, "site":site, "message":"Неизвестный участок."}
	var local := GameMath.site(p, site)
	var levels: Dictionary = local.get("upgrades", {})
	var count := 10 if site == "fe" else 10
	var total := 0
	for value in levels.values():
		total += int(value)
	var average := floori(float(total) / float(count))
	var expansion_count := int(local.get("expansions", 0))
	var required := (600 if expansion_count == 0 else 400) if site == "fe" else (60 if expansion_count == 0 else 40)
	var cycle_start := int(GameMath.game(p)["progression"]["expansions"].get(site, {}).get("mined_start", 0))
	var cycle_mined := maxi(0, int(float(local.get("mined", 0.0)) - cycle_start))
	var geodata := floori(float(cycle_mined) / float(_proposals().get("expansion_geodata_per_mined", 100)))
	var unlocked := site == "fe" or GameMath.unlocked(p, site)
	var eligible := unlocked and average >= required and cycle_mined > 0
	return {
		"ok":true, "site":site, "unlocked":unlocked, "average_level":average,
		"required_average":required, "expansions":expansion_count, "eligible":eligible,
		"mined_since_expansion":cycle_mined, "geodata_award":geodata,
		"reset_fields":["upgrades", "machines", "workers", "fraction", "wage_fraction", "active_batch"],
		"preserved_fields":["money_cents", "inventory", "sites", "stories", "research", "mastery", "equipment", "specialists", "other_sites"],
		"message":"" if eligible else _expansion_blocker(site, unlocked, average, required, cycle_mined)
	}

static func mastery_status(p: Dictionary, id: String) -> Dictionary:
	ensure(p)
	var record := _cached_record("mastery", id)
	if record.is_empty():
		return {"id":id, "known":false, "can_unlock":false, "reason":"Нет навыка с таким ID в каноне."}
	var progression: Dictionary = GameMath.game(p)["progression"]
	var rank := int(progression["mastery"].get(id, 0))
	var reached := _mastery_milestone(p, str(record.get("milestone", "")))
	var cost := int(record.get("cost_mastery_points", 1))
	return {
		"id":id, "known":true, "record":record, "rank":rank,
		"max_rank":int(record.get("max_rank", 1)), "milestone":str(record.get("milestone", "")),
		"milestone_reached":reached, "cost":cost,
		"can_unlock":reached and rank < int(record.get("max_rank", 1)) and int(progression["mastery_points"]) >= cost,
		"reason":"" if reached else "Не достигнут рубеж: " + str(record.get("milestone", "")),
		"canonical_effect":str(record.get("effect", "")), "requires_prestige":str(record.get("requires_prestige", "no")) == "yes"
	}

static func view(p: Dictionary) -> Dictionary:
	ensure(p)
	refresh(p)
	var progression: Dictionary = GameMath.game(p)["progression"]
	var audit := research_catalog_audit()
	var action_schemas: Dictionary = _proposals().get("action_schemas", {})
	var offered_actions: Array[String] = []
	for action in action_schemas:
		offered_actions.append(str(action))
	offered_actions.sort()
	var feature_hooks: Array[String] = []
	for flag in progression["effects"].get("flags", {}):
		feature_hooks.append(str(flag))
	feature_hooks.sort()
	return {
		"sites":p["sites"].duplicate(true), "available_story":available_story(p),
		"buildings":progression["buildings"].duplicate(true), "geology":progression["geology"].duplicate(true),
		"contracts":progression["contracts"].duplicate(true), "research":progression["research"].duplicate(true),
		"mastery":progression["mastery"].duplicate(true), "mastery_catalog":_cached_rows("mastery"), "mastery_points":int(progression["mastery_points"]),
		"effects":progression["effects"].duplicate(true),
		"action_schemas":action_schemas.duplicate(true), "offered_actions":offered_actions,
		"feature_hooks":feature_hooks, "coverage":_proposals().get("coverage", {}).duplicate(true),
		"building_catalog":_proposals().get("buildings", {}).duplicate(true),
		"offline_level":int(GameMath.game(p)["offline_level"]),
		"offline_cap_seconds":14400 + int(GameMath.game(p)["offline_level"]) * 1440,
		"research_catalog":audit, "season_level_cap":60,
		"season_rewards_unassigned":true
	}

static func research_catalog_audit() -> Dictionary:
	_ensure_content_cache()
	if not _research_audit_cache.is_empty():
		return _research_audit_cache.duplicate(true)
	var rows: Array = _catalog_rows["research"]
	var issues: Array[String] = []
	var records: Dictionary = {}
	var total_cost := 0
	for row in rows:
		var id := str(row.get("id", ""))
		if records.has(id):
			issues.append("Повторный ID " + id)
		records[id] = row
		total_cost += int(row.get("total_cost_oi", 0))
	for id in records:
		for dependency in _csv_list(str(records[id].get("dependencies", ""))):
			if not records.has(dependency):
				issues.append("Неизвестная зависимость %s → %s" % [id, dependency])
	var marks: Dictionary = {}
	for id in records:
		if not _visit_research(str(id), records, marks):
			issues.append("Цикл зависимостей вокруг " + str(id))
	_research_audit_cache = {"count":rows.size(), "total_cost_oi":total_cost, "valid_dag":issues.is_empty(), "issues":issues}
	return _research_audit_cache.duplicate(true)

static func _research(p: Dictionary, id: String) -> Dictionary:
	var status := research_status(p, id)
	if not bool(status.get("known", false)):
		return GameMath.fail("Узел исследования не найден в каноне.")
	if not bool(status.get("can_research", false)):
		return GameMath.fail(str(status.get("reason", "Исследование сейчас недоступно.")))
	var progression: Dictionary = GameMath.game(p)["progression"]
	var record: Dictionary = status["record"]
	var cost := int(status["next_cost"])
	p["research_points"] = int(p.get("research_points", 0)) - cost
	progression["research"][id] = int(status["level"]) + 1
	return GameMath.ok("Исследование %s: уровень %d/%d." % [id, progression["research"][id], int(record["max_levels"])])

static func _mastery(p: Dictionary, id: String) -> Dictionary:
	var record := _cached_record("mastery", id)
	if record.is_empty():
		return GameMath.fail("Навык мастерства не найден в каноне.")
	var progression: Dictionary = GameMath.game(p)["progression"]
	var current := int(progression["mastery"].get(id, 0))
	var maximum := int(record.get("max_rank", 1))
	if current >= maximum:
		return GameMath.fail("Навык уже изучен полностью.")
	var milestone := _mastery_milestone(p, str(record.get("milestone", "")))
	if not milestone:
		return GameMath.fail("Не достигнут рубеж: " + str(record.get("milestone", "")))
	var cost := int(record.get("cost_mastery_points", 1))
	if int(progression["mastery_points"]) < cost:
		return GameMath.fail("Недостаточно очков мастерства.")
	progression["mastery_points"] = int(progression["mastery_points"]) - cost
	progression["mastery"][id] = current + 1
	progression["effects"]["mastery"][id] = {"enabled":true, "effect":str(record.get("effect", ""))}
	return GameMath.ok("Навык %s активирован." % id)

static func _story_open(p: Dictionary, id: String) -> Dictionary:
	if not STORY_IDS.has(id):
		return GameMath.fail("После вступления модель принимает только главы A02–A20.")
	var row := _cached_record("story", id)
	if row.is_empty():
		return GameMath.fail("Глава отсутствует в каноническом каталоге.")
	var progression: Dictionary = GameMath.game(p)["progression"]
	if bool(progression["story_done"].get(id, false)):
		return GameMath.fail("Глава уже завершена.")
	var prerequisite := str(row.get("prerequisite_story", ""))
	if not prerequisite.is_empty() and not _story_done(p, prerequisite):
		return GameMath.fail("Сначала завершить " + prerequisite + ".")
	progression["story_read"][id] = true
	progression["story"]["current_id"] = id
	return GameMath.ok("Диалог открыт; открытие не выдаёт награду.")

static func _story_complete(p: Dictionary, id: String) -> Dictionary:
	if not STORY_IDS.has(id):
		return GameMath.fail("Главу A01 завершает вступление, остальные главы — только A02–A20.")
	var progression: Dictionary = GameMath.game(p)["progression"]
	var row := _cached_record("story", id)
	if row.is_empty() or not bool(progression["story_read"].get(id, false)):
		return GameMath.fail("Сначала откройте доступный диалог.")
	if bool(progression["story_done"].get(id, false)):
		return GameMath.fail("Глава уже завершена.")
	var prerequisite := str(row.get("prerequisite_story", ""))
	if not prerequisite.is_empty() and not _story_done(p, prerequisite):
		return GameMath.fail("Сначала завершить " + prerequisite + ".")
	var blockers := _story_requirements(p, id)
	if not blockers.is_empty():
		return GameMath.fail("Не выполнены условия главы: " + "; ".join(blockers))
	if id == "A20" and GameMath.add(p, "KEY_HORIZONITE_SAMPLE", 1) != 1:
		return GameMath.fail("На складе нет места для неотчуждаемого сюжетного образца.")
	progression["story_done"][id] = true
	progression["story_archive"].append(id)
	progression["story"]["current_id"] = ""
	if id == "A20":
		progression["story"]["flags"]["phase2_discovered"] = true
	return GameMath.ok("Глава %s подтверждена по игровым условиям." % id)

static func _story_status(p: Dictionary, row: Dictionary) -> Dictionary:
	var id := str(row.get("id", ""))
	var progression: Dictionary = GameMath.game(p)["progression"]
	var blockers := _story_requirements(p, id)
	return {
		"id":id, "title":str(row.get("title", id)), "trigger":str(row.get("trigger", "")),
		"description":str(row.get("description", "")), "reward_unlock":str(row.get("reward_unlock", "")),
		"prerequisite_story":str(row.get("prerequisite_story", "")),
		"read":bool(progression["story_read"].get(id, false)), "completed":bool(progression["story_done"].get(id, false)),
		"requirements_met":blockers.is_empty(), "blockers":blockers,
		"dialogue":_cached_record("dialogue", id).get("lines", []).duplicate(true)
	}

static func _story_requirements(p: Dictionary, id: String) -> Array[String]:
	var g := GameMath.game(p)
	var progression: Dictionary = g["progression"]
	var stats: Dictionary = g["stats"]
	var blockers: Array[String] = []
	var reports: Array = progression["geology"]["reports"]
	match id:
		"A02":
			if float(stats.get("workers_hired", 0)) < 1: blockers.append("нанять первого работника")
			if float(stats.get("safe_repairs", 0)) < 1: blockers.append("завершить безопасный ремонт")
		"A03":
			if reports.is_empty(): blockers.append("получить первый геологический отчёт")
		"A04":
			if not _has_completed_contract_type(p, "trade"): blockers.append("отгрузить и получить первый торговый контракт")
		"A05":
			if not bool(progression["geology"]["discoveries"].get("registry_anomaly", false)): blockers.append("получить отчёт о REGISTRY_ANOMALY")
		"A06":
			if float(stats.get("produced:steel", 0.0)) < 1.0: blockers.append("произвести первую сталь")
			if _sold_count(stats) < 1.0: blockers.append("продать свободный товар")
		"A07":
			if int(GameMath.site(p, "fe").get("peak", 0)) < 600: blockers.append("достичь исторического среднего уровня Fe 600 (сюжет необязателен)")
		"A08":
			if not _pd_unlock_conditions(p): blockers.append("выполнить условия доступа к П-7")
		"A09":
			if float(stats.get("produced:pd_catalyst", 0.0)) < 1.0: blockers.append("произвести Pd-катализатор")
		"A10":
			if not _building_complete(p, "factory"): blockers.append("завершить строительство завода")
			if float(stats.get("produced:pd_refined", 0.0)) < 1.0: blockers.append("произвести очищенный Pd")
		"A11":
			if not bool(progression["geology"]["discoveries"].get("railway_log", false)): blockers.append("получить геологический отчёт TRAIN_LOG")
		"A12":
			if not bool(stats.get("alternative_contract_proposed", false)): blockers.append("подать альтернативное предложение по контракту")
		"A13":
			if not bool(progression["geology"]["discoveries"].get("old_project_record", false)): blockers.append("найти запись старого проекта")
		"A14":
			if not _ir_unlock_conditions(p): blockers.append("выполнить условия доступа к И-9")
		"A15":
			if not bool(progression["geology"]["discoveries"].get("ir_spectrum", false)): blockers.append("проанализировать спектр И-9")
		"A16":
			if not bool(stats.get("worker_registry_compared", false)): blockers.append("сопоставить реестр работников")
		"A17":
			if not bool(progression["geology"]["discoveries"].get("deep_geology_signal", false)): blockers.append("подтвердить сигнал глубинной геологии")
		"A18":
			if not bool(stats.get("evidence_transmission_attempted", false)): blockers.append("предпринять передачу свидетельств")
		"A19":
			if not _a19_evidence(p): blockers.append("собрать свидетельства: финансы + техника + наука")
		"A20":
			if not bool(progression["story"]["flags"].get("safe_cavity_entered", false)): blockers.append("безопасно войти в искусственную полость")
			if int(GameMath.game(p)["reservations"].get("progression:story:A20:thermal_contact", {}).get("ir_thermal_contact", 0)) < 1 or int(p.get("inventory", {}).get("ir_thermal_contact", 0)) < 1: blockers.append("зарезервировать термоконтакт И-9")
			if not bool(progression["geology"]["discoveries"].get("deep_geology_signal", false)): blockers.append("подтвердить сигнал глубинной геологии")
			if not _building_complete(p, "safe_cavity_project"): blockers.append("завершить проект безопасной полости")
	return blockers

static func _research_unlock_met(p: Dictionary, record: Dictionary) -> bool:
	var unlock := str(record.get("unlock", "earth_start"))
	if unlock.begins_with("story:"):
		return _story_done(p, unlock.trim_prefix("story:"))
	var site := str(record.get("site", "common"))
	if site == "common" or site == "fe":
		return true
	return GameMath.unlocked(p, site)

static func _research_unlock_reason(p: Dictionary, record: Dictionary) -> String:
	var unlock := str(record.get("unlock", "earth_start"))
	if unlock.begins_with("story:"):
		return "Требуется завершить " + unlock.trim_prefix("story:") + "."
	return "Требуется открыть участок " + str(record.get("site", "")) + "."

static func _research_level_cost(record: Dictionary, level: int) -> int:
	var maximum := int(record.get("max_levels", 1))
	if level < 1 or level > maximum:
		return 0
	var total := int(record.get("total_cost_oi", 0))
	return floori(float(total * level) / float(maximum)) - floori(float(total * (level - 1)) / float(maximum))

static func _refresh_research_bonuses(p: Dictionary) -> void:
	var g := GameMath.game(p)
	var progression: Dictionary = g["progression"]
	var effects: Dictionary = progression["effects"]
	if progression["research"] == effects.get("research_levels", {}):
		return
	var flags: Dictionary = {}
	var bonuses: Dictionary = {}
	var proposals: Dictionary = _proposals().get("research_effects", {})
	for id in progression["research"]:
		var level := int(progression["research"][id])
		var row: Dictionary = proposals.get(str(id), {})
		if level <= 0 or row.is_empty():
			continue
		for flag in row.get("feature_flags", []):
			flags[str(id) + ":" + str(flag)] = true
		var scope := str(row.get("site", ""))
		for key in row.get("bonuses", {}):
			var bonus_key := str(key) if scope.is_empty() else scope + ":" + str(key)
			bonuses[bonus_key] = float(bonuses.get(bonus_key, 0.0)) + float(row["bonuses"][key]) * level
	effects["flags"] = flags
	effects["research_levels"] = progression["research"].duplicate(true)
	g["bonuses"]["progression"] = bonuses

static func _refresh_mastery_points(p: Dictionary) -> void:
	var progression: Dictionary = GameMath.game(p)["progression"]
	var peaks: Array[int] = []
	for site in GameMath.SITES:
		peaks.append(int(GameMath.site(p, site).get("peak", 0)))
	var signature := "%d:%d:%d" % [peaks[0], peaks[1], peaks[2]]
	if signature == str(progression.get("mastery_peak_signature", "")):
		return
	_ensure_content_cache()
	var earned := 0
	for row in _catalog_rows["mastery"]:
		if _mastery_milestone(p, str(row.get("milestone", ""))):
			earned += 1
	var previous := int(progression["mastery_points_earned"])
	if earned > previous:
		progression["mastery_points"] = int(progression["mastery_points"]) + earned - previous
		progression["mastery_points_earned"] = earned
	progression["mastery_peak_signature"] = signature

static func _mastery_milestone(p: Dictionary, milestone: String) -> bool:
	var parts := milestone.split("_lifetime_peak_")
	if parts.size() != 2 or not GameMath.SITES.has(parts[0]):
		return false
	return int(GameMath.site(p, parts[0]).get("peak", 0)) >= int(parts[1])

static func _geology_start(p: Dictionary, id: String) -> Dictionary:
	var definitions: Dictionary = _proposals().get("geology_expeditions", {})
	if not definitions.has(id):
		return GameMath.fail("Неизвестный тип геологической экспедиции.")
	var progression: Dictionary = GameMath.game(p)["progression"]
	var geology: Dictionary = progression["geology"]
	if not geology["active"].is_empty():
		return GameMath.fail("Сначала завершите текущую экспедицию.")
	var spec: Dictionary = definitions[id]
	var site := str(spec.get("site", "fe"))
	if site != "fe" and not GameMath.unlocked(p, site):
		return GameMath.fail("Участок для этой экспедиции ещё не открыт.")
	if id == "deep_signal" and not _building_complete(p, "deep_station"):
		return GameMath.fail("Для глубокого сканирования нужна Глубинная станция.")
	var cost := int(spec.get("cost_cents", 0))
	if not GameMath.pay(p, cost):
		return GameMath.fail("Недостаточно гелионов для экспедиции.")
	geology["cycle"] = int(geology["cycle"]) + 1
	var expedition_counts: Dictionary = geology["expedition_counts"]
	expedition_counts[id] = int(expedition_counts.get(id, 0)) + 1
	geology["active"] = {
		"id":id, "site":site, "sequence":int(expedition_counts[id]),
		"remaining_seconds":float(spec.get("duration_seconds", 0.0)),
		"reward_research_points":int(spec.get("reward_research_points", 0)),
		"reward_shards":int(spec.get("reward_shards", 0))
	}
	if float(geology["active"]["remaining_seconds"]) <= 0.0:
		_complete_expedition(p)
	return GameMath.ok("Экспедиция оплачена и начата.")

static func _complete_expedition(p: Dictionary) -> void:
	var progression: Dictionary = GameMath.game(p)["progression"]
	var geology: Dictionary = progression["geology"]
	var expedition: Dictionary = geology["active"]
	if expedition.is_empty():
		return
	var id := str(expedition["id"])
	var sequence := int(expedition["sequence"])
	var tags: Array = _expedition_tags(id, sequence)
	var report_id := "GEO-%04d" % (geology["reports"].size() + 1)
	var report := {"id":report_id, "site":str(expedition["site"]), "expedition":id, "tags":tags}
	geology["reports"].append(report)
	for tag in tags:
		geology["discoveries"][str(tag)] = true
	if id == "fe_survey":
		geology["guaranteed_geobinding"] = true
	p["research_points"] = int(p.get("research_points", 0)) + int(expedition.get("reward_research_points", 0))
	p["shards"] = int(p.get("shards", 0)) + int(expedition.get("reward_shards", 0))
	GameMath.stat(p, "geology_reports")
	geology["active"] = {}

static func _expedition_tags(id: String, sequence: int) -> Array:
	if id == "fe_survey":
		match sequence:
			1: return ["STRUCTURE_01", "guaranteed_geobinding"]
			2: return ["registry_anomaly"]
			3: return ["railway_log"]
			4: return ["old_project_record"]
			_: return ["geology_report"]
	if id == "ir_probe":
		return ["ir_spectrum"]
	if id == "deep_signal":
		return ["deep_geology_signal"]
	return ["geology_report"]

static func _building_start(p: Dictionary, requested_id: String) -> Dictionary:
	var id := str(BUILDING_ALIASES.get(requested_id, requested_id))
	var definitions: Dictionary = _proposals().get("buildings", {})
	if not definitions.has(id):
		return GameMath.fail("Неизвестный проект строительства.")
	var progression: Dictionary = GameMath.game(p)["progression"]
	var building_state: Dictionary = progression["buildings"]
	if building_state.has(id) and str(building_state[id].get("status", "")) in ["building", "complete"]:
		return GameMath.fail("Проект уже начат или завершён.")
	var blocker := _building_blocker(p, id)
	if not blocker.is_empty():
		return GameMath.fail(blocker)
	var spec: Dictionary = definitions[id]
	var cost_cents := int(spec.get("cost_cents", 0))
	var items: Dictionary = spec.get("items", {})
	for item in items:
		if GameMath.free_amount(p, str(item)) < int(items[item]):
			return GameMath.fail("Недостаточно свободного ресурса: " + str(item))
	if int(p.get("money_cents", 0)) < cost_cents:
		return GameMath.fail("Недостаточно гелионов на строительство.")
	var reserve_id := "progression:building:" + id
	if not items.is_empty():
		GameMath.game(p)["reservations"][reserve_id] = items.duplicate(true)
	if not GameMath.pay(p, cost_cents):
		GameMath.game(p)["reservations"].erase(reserve_id)
		return GameMath.fail("Не удалось оплатить строительство.")
	building_state[id] = {
		"status":"building", "remaining_seconds":float(spec.get("duration_seconds", 0.0)),
		"reservation_id":reserve_id, "cost_cents":cost_cents
	}
	if float(building_state[id]["remaining_seconds"]) <= 0.0:
		_complete_building(p, id)
	return GameMath.ok("Строительство начато; материалы зарезервированы.")

static func _complete_building(p: Dictionary, id: String) -> void:
	var progression: Dictionary = GameMath.game(p)["progression"]
	var building_state: Dictionary = progression["buildings"]
	if not building_state.has(id) or str(building_state[id].get("status", "")) != "building":
		return
	var building: Dictionary = building_state[id]
	var reservation_id := str(building.get("reservation_id", ""))
	var reservations: Dictionary = GameMath.game(p)["reservations"]
	var reserved_items: Dictionary = reservations.get(reservation_id, {})
	for item in reserved_items:
		if int(p.get("inventory", {}).get(item, 0)) < int(reserved_items[item]):
			building["status"] = "blocked"
			building["error"] = "Зарезервированные материалы отсутствуют."
			return
	reservations.erase(reservation_id)
	for item in reserved_items:
		GameMath.take(p, str(item), int(reserved_items[item]))
	building["status"] = "complete"
	building["remaining_seconds"] = 0.0
	building.erase("reservation_id")
	GameMath.stat(p, "buildings_completed")
	if id == "safe_repair":
		GameMath.game(p)["stats"]["safe_repairs"] = maxi(1, int(GameMath.game(p)["stats"].get("safe_repairs", 0)))

static func _building_blocker(p: Dictionary, id: String) -> String:
	match id:
		"hq": return ""
		"research", "factory", "warehouse", "trade", "power":
			return "Сначала завершите штаб." if not _building_complete(p, "hq") else ""
		"deep_station":
			if not _story_done(p, "A13"): return "Требуется завершить A13."
			if not GameMath.unlocked(p, "pd"): return "Сначала откройте П-7."
			if not _building_complete(p, "factory"): return "Сначала завершите завод."
			if float(GameMath.game(p)["stats"].get("produced:pd_catalyst", 0.0)) < 1.0: return "Требуется собственный Pd-катализатор."
			return ""
		"safe_cavity_project":
			if not _story_done(p, "A19"): return "Требуется завершить A19."
			if not _building_complete(p, "deep_station") or not _building_complete(p, "power"): return "Нужны Глубинная станция и энергоблок."
			return ""
		"safe_repair": return ""
	return "Проект строительства недоступен."

static func _building_complete(p: Dictionary, id: String) -> bool:
	var progression: Dictionary = GameMath.game(p).get("progression", {})
	return str(progression.get("buildings", {}).get(id, {}).get("status", "")) == "complete"

static func _contract_accept(p: Dictionary, id: String) -> Dictionary:
	var definitions: Dictionary = _proposals().get("contracts", {})
	if not definitions.has(id):
		return GameMath.fail("Контракт отсутствует в каталоге предложений.")
	var progression: Dictionary = GameMath.game(p)["progression"]
	var contracts: Dictionary = progression["contracts"]
	var spec: Dictionary = definitions[id]
	if not bool(spec.get("repeatable", false)) and contracts["completed"].has(id):
		return GameMath.fail("Этот контракт уже получен.")
	for order in contracts["active"].values():
		if str(order.get("contract_id", "")) == id:
			return GameMath.fail("Этот контракт уже принят.")
	var blocker := _contract_blocker(p, spec)
	if not blocker.is_empty():
		return GameMath.fail(blocker)
	var requirements: Dictionary = spec.get("items", {})
	for item in requirements:
		if GameMath.free_amount(p, str(item)) < int(requirements[item]):
			return GameMath.fail("Недостаточно свободного ресурса: " + str(item))
	contracts["sequence"] = int(contracts["sequence"]) + 1
	var order_id := id + "#%04d" % int(contracts["sequence"])
	var reserve_id := "progression:contract:" + order_id
	if not requirements.is_empty():
		GameMath.game(p)["reservations"][reserve_id] = requirements.duplicate(true)
	contracts["active"][order_id] = {
		"order_id":order_id, "contract_id":id, "status":"accepted",
		"reservation_id":reserve_id, "items":requirements.duplicate(true),
		"reward":spec.get("reward", {}).duplicate(true)
	}
	return {"ok":true, "message":"Контракт принят; товар зарезервирован.", "order_id":order_id}

static func _contract_ship(p: Dictionary, order_id: String) -> Dictionary:
	var contracts: Dictionary = GameMath.game(p)["progression"]["contracts"]
	if not contracts["active"].has(order_id):
		return GameMath.fail("Активный контракт не найден.")
	var order: Dictionary = contracts["active"][order_id]
	if str(order.get("status", "")) != "accepted":
		return GameMath.fail("Контракт уже отгружен или закрыт.")
	var reserve_id := str(order.get("reservation_id", ""))
	var reservations: Dictionary = GameMath.game(p)["reservations"]
	var reserved_items: Dictionary = reservations.get(reserve_id, {})
	for item in order.get("items", {}):
		if int(reserved_items.get(item, 0)) < int(order["items"][item]) or int(p.get("inventory", {}).get(item, 0)) < int(order["items"][item]):
			return GameMath.fail("Резерв контракта повреждён; отгрузка отклонена.")
	reservations.erase(reserve_id)
	for item in order.get("items", {}):
		if not GameMath.take(p, str(item), int(order["items"][item])):
			return GameMath.fail("Не удалось списать зарезервированный товар.")
	order["status"] = "shipped"
	return GameMath.ok("Партия отгружена; награду можно получить один раз.")

static func _contract_claim(p: Dictionary, order_id: String) -> Dictionary:
	var contracts: Dictionary = GameMath.game(p)["progression"]["contracts"]
	if not contracts["active"].has(order_id):
		return GameMath.fail("Активный контракт не найден или уже закрыт.")
	var order: Dictionary = contracts["active"][order_id]
	if str(order.get("status", "")) != "shipped" or contracts["completed"].has(order_id):
		return GameMath.fail("Награда доступна только после отгрузки и выдаётся один раз.")
	var reward: Dictionary = order.get("reward", {})
	p["money_cents"] = int(p.get("money_cents", 0)) + int(reward.get("money_cents", 0))
	p["research_points"] = int(p.get("research_points", 0)) + int(reward.get("research_points", 0))
	p["shards"] = int(p.get("shards", 0)) + int(reward.get("shards", 0))
	var contract_id := str(order.get("contract_id", ""))
	var spec: Dictionary = _proposals().get("contracts", {}).get(contract_id, {})
	if not bool(spec.get("repeatable", false)):
		contracts["completed"][contract_id] = true
	contracts["completed"][order_id] = true
	order["status"] = "claimed"
	contracts["active"].erase(order_id)
	GameMath.stat(p, "contracts_claimed")
	if str(spec.get("type", "")) == "trade":
		GameMath.stat(p, "trade_contracts_completed")
	return GameMath.ok("Контракт закрыт; награда начислена однократно.")

static func _contract_blocker(p: Dictionary, spec: Dictionary) -> String:
	var requirement := str(spec.get("requires", ""))
	if requirement == "pd_unlocked" and not GameMath.unlocked(p, "pd"):
		return "Требуется открыть П-7."
	if requirement == "ir_unlocked" and not GameMath.unlocked(p, "ir"):
		return "Требуется открыть И-9."
	if requirement.begins_with("story:") and not _story_done(p, requirement.trim_prefix("story:")):
		return "Требуется завершить " + requirement.trim_prefix("story:") + "."
	return ""

static func _has_completed_contract_type(p: Dictionary, contract_type: String) -> bool:
	var completed: Dictionary = GameMath.game(p)["progression"]["contracts"]["completed"]
	if not completed.has("trade_contracts_completed"):
		for order_id in completed:
			var order: Dictionary = GameMath.game(p)["progression"]["contracts"].get("active", {}).get(order_id, {})
			if str(order.get("type", "")) == contract_type:
				return true
	return int(GameMath.game(p)["stats"].get("trade_contracts_completed", 0)) > 0

static func _expand(p: Dictionary, site: String) -> Dictionary:
	var preview := expansion_preview(p, site)
	if not bool(preview.get("eligible", false)):
		return GameMath.fail(str(preview.get("message", "Экспансия сейчас недоступна.")))
	var progression: Dictionary = GameMath.game(p)["progression"]
	var local := GameMath.site(p, site)
	var cycle := int(local.get("expansions", 0))
	var claim_id := "%s:%d" % [site, cycle]
	if progression["expansions"].get("claims", {}).has(claim_id):
		return GameMath.fail("Награда этой Экспансии уже выдана.")
	var mined_start := int(progression["expansions"].get(site, {}).get("mined_start", 0))
	var mined := maxi(0, int(float(local.get("mined", 0.0)) - mined_start))
	var geodata := floori(float(mined) / float(_proposals().get("expansion_geodata_per_mined", 100)))
	var cancel_result := _cancel_site_operation(p, site)
	if not bool(cancel_result.get("ok", false)):
		return GameMath.fail(str(cancel_result.get("message", "Не удалось безопасно остановить активную добычу.")))
	progression["expansions"]["claims"][claim_id] = {"mined":mined, "geodata":geodata}
	local["upgrades"] = {}
	local["machines"] = {}
	local["workers"] = {}
	local["fraction"] = 0.0
	local["wage_fraction"] = 0.0
	local.erase("active_batch")
	local["expansions"] = cycle + 1
	local["geodata"] = int(local.get("geodata", 0)) + geodata
	progression["expansions"][site] = {"mined_start":int(float(local.get("mined", 0.0)))}
	GameMath.stat(p, "expansions_completed")
	return GameMath.ok("Локальная Экспансия выполнена; глобальные данные сохранены.")

static func _cancel_site_operation(p: Dictionary, site: String) -> Dictionary:
	if not ["pd", "ir"].has(site):
		return GameMath.ok()
	var extraction: Dictionary = GameMath.game(p).get("extraction", {})
	if not extraction.has(site) or not extraction[site] is Dictionary:
		return GameMath.ok()
	var state: Dictionary = extraction[site]
	var status := str(state.get("status", "idle"))
	if site == "pd" and status in ["idle", "cancelled"]:
		if not state.get("sample", {}).is_empty():
			return GameMath.fail("Не удалось отменить повреждённую активную пробу.")
		state["automatic"] = false
		return GameMath.ok()
	if site == "ir" and status in ["idle", "cancelled"]:
		return GameMath.ok()
	return SITE_MODEL.act(p, "cancel", {"site":site})

static func _expansion_blocker(site: String, unlocked: bool, average: int, required: int, mined: int) -> String:
	if not unlocked:
		return "Участок ещё не открыт."
	if average < required:
		return "Нужен средний уровень %d; сейчас %d." % [required, average]
	if mined <= 0:
		return "После предыдущей Экспансии нужна фактическая добыча."
	return "Экспансия недоступна на участке " + site + "."

static func _offline_upgrade(p: Dictionary) -> Dictionary:
	var g := GameMath.game(p)
	var level := int(g["offline_level"])
	if level >= 50:
		return GameMath.fail("Офлайн-лимит уже увеличен до 24 часов.")
	var next_level := level + 1
	var cost := 75 if next_level <= 20 else (48 if next_level <= 40 else 49)
	if int(p.get("shards", 0)) < cost:
		return GameMath.fail("Для следующего шага нужно %d осколков." % cost)
	p["shards"] = int(p["shards"]) - cost
	g["offline_level"] = next_level
	return GameMath.ok("Офлайн-лимит теперь %d минут." % (240 + next_level * 24))

static func _reserve_story_contact(p: Dictionary) -> Dictionary:
	var progression: Dictionary = GameMath.game(p)["progression"]
	if not _story_done(p, "A19"):
		return GameMath.fail("Для подготовки финала нужно завершить A19.")
	var reserve_id := "progression:story:A20:thermal_contact"
	if GameMath.game(p)["reservations"].has(reserve_id):
		return GameMath.fail("Термоконтакт уже зарезервирован для финала.")
	if GameMath.free_amount(p, "ir_thermal_contact") < 1:
		return GameMath.fail("Нужен один свободный термоконтакт И-9.")
	GameMath.game(p)["reservations"][reserve_id] = {"ir_thermal_contact":1}
	progression["story"]["flags"]["thermal_contact_reserved"] = true
	return GameMath.ok("Один термоконтакт зарезервирован для A20.")

static func _story_transmit(p: Dictionary) -> Dictionary:
	if not bool(GameMath.game(p)["progression"]["story_read"].get("A18", false)):
		return GameMath.fail("Сначала откройте A18.")
	GameMath.stat(p, "evidence_transmission_attempted")
	GameMath.game(p)["stats"]["evidence_transmission_attempted"] = true
	return GameMath.ok("Попытка передачи свидетельств записана.")

static func _compare_worker_registry(p: Dictionary) -> Dictionary:
	var progression: Dictionary = GameMath.game(p)["progression"]
	if not bool(progression["story_read"].get("A16", false)):
		return GameMath.fail("Сначала откройте A16.")
	if float(GameMath.game(p)["stats"].get("workers_hired", 0)) < 1.0:
		return GameMath.fail("Для сопоставления нужен хотя бы один работник.")
	GameMath.game(p)["stats"]["worker_registry_compared"] = true
	return GameMath.ok("Сопоставление реестров записано.")

static func _propose_alternative_contract(p: Dictionary) -> Dictionary:
	var progression: Dictionary = GameMath.game(p)["progression"]
	if not bool(progression["story_read"].get("A12", false)):
		return GameMath.fail("Сначала откройте A12.")
	if not _story_done(p, "A11"):
		return GameMath.fail("Для переговоров требуется завершить A11.")
	GameMath.game(p)["stats"]["alternative_contract_proposed"] = true
	return GameMath.ok("Альтернативное предложение записано; предметы не выданы.")

static func _enter_cavity(p: Dictionary) -> Dictionary:
	var progression: Dictionary = GameMath.game(p)["progression"]
	if not _story_done(p, "A19") or not _building_complete(p, "safe_cavity_project"):
		return GameMath.fail("Для безопасного входа нужны A19 и завершённый проект полости.")
	if not bool(progression["geology"]["discoveries"].get("deep_geology_signal", false)):
		return GameMath.fail("Сначала подтвердите глубинный геологический сигнал.")
	progression["story"]["flags"]["safe_cavity_entered"] = true
	return GameMath.ok("Полость исследована безопасно.")

static func _pd_unlock_conditions(p: Dictionary) -> bool:
	var stats: Dictionary = GameMath.game(p)["stats"]
	return _story_done(p, "A06") and int(GameMath.site(p, "fe").get("peak", 0)) >= 350 and float(stats.get("produced:steel", 0.0)) >= 1.0 and bool(GameMath.game(p)["progression"]["geology"].get("guaranteed_geobinding", false))

static func _ir_unlock_conditions(p: Dictionary) -> bool:
	var stats: Dictionary = GameMath.game(p)["stats"]
	return _story_done(p, "A13") and float(stats.get("produced:pd_catalyst", 0.0)) >= 1.0 and GameMath.game(p)["progression"]["geology"]["reports"].size() >= 2 and _building_complete(p, "deep_station")

static func _a19_evidence(p: Dictionary) -> bool:
	var stats: Dictionary = GameMath.game(p)["stats"]
	var finance := _sold_count(stats) >= 1.0 and int(stats.get("trade_contracts_completed", 0)) >= 1
	var engineering := _building_complete(p, "deep_station") and _building_complete(p, "power")
	var science: bool = not GameMath.game(p)["progression"]["research"].is_empty() and GameMath.game(p)["progression"]["geology"]["reports"].size() >= 2
	return finance and engineering and science

static func _sold_count(stats: Dictionary) -> float:
	var sold := float(stats.get("sold", 0.0))
	for key in stats:
		if str(key).begins_with("sold:"):
			sold += float(stats[key])
	return sold

static func _story_done(p: Dictionary, id: String) -> bool:
	if id == "A01" and bool(p.get("story", {}).get("intro_seen", false)):
		return true
	return bool(GameMath.game(p).get("progression", {}).get("story_done", {}).get(id, false))

static func _story_rows() -> Array:
	return _cached_rows("story")

static func _csv_list(value: String) -> Array[String]:
	var items: Array[String] = []
	for item in value.split(",", false):
		var trimmed := item.strip_edges()
		if not trimmed.is_empty():
			items.append(trimmed)
	return items

static func _visit_research(id: String, records: Dictionary, marks: Dictionary) -> bool:
	var mark := int(marks.get(id, 0))
	if mark == 1:
		return false
	if mark == 2:
		return true
	marks[id] = 1
	for dependency in _csv_list(str(records[id].get("dependencies", ""))):
		if records.has(dependency) and not _visit_research(dependency, records, marks):
			return false
	marks[id] = 2
	return true

static func _proposals() -> Dictionary:
	_ensure_content_cache()
	return _proposal_cache

static func _ensure_content_cache() -> void:
	if _content_cache_loaded:
		return
	for catalog in ["research", "mastery", "story", "dialogue"]:
		var rows := GameMath.records(catalog)
		var index: Dictionary = {}
		for row in rows:
			var id := str(row.get("id", ""))
			index[id] = row
			if catalog == "research":
				_research_dependencies[id] = _csv_list(str(row.get("dependencies", "")))
		_catalog_rows[catalog] = rows
		_catalog_index[catalog] = index
	var file := FileAccess.open(PROPOSAL_PATH, FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			_proposal_cache = parsed
	_content_cache_loaded = true

static func _cached_rows(catalog: String) -> Array:
	_ensure_content_cache()
	return _catalog_rows.get(catalog, []).duplicate(true)

static func _cached_record(catalog: String, id: String) -> Dictionary:
	_ensure_content_cache()
	var row: Dictionary = _catalog_index.get(catalog, {}).get(id, {})
	return row.duplicate(true)

static func _bounded_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum and floorf(float(value)) == float(value)

static func _finite_nonnegative(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0

static func _ensure_fields(target: Dictionary, defaults: Dictionary) -> void:
	for key in defaults:
		var default: Variant = defaults[key]
		if not target.has(key) or typeof(target[key]) != typeof(default):
			target[key] = default.duplicate(true) if default is Dictionary or default is Array else default
