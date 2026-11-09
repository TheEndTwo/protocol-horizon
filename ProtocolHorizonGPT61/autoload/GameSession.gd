extends Node

signal changed
signal message(text: String)

const MODELS := {
	"economy":"res://gameplay/EconomyModel.gd", "progression":"res://gameplay/ProgressionModel.gd",
	"meta":"res://gameplay/MetaModel.gd", "sites":"res://gameplay/SiteModel.gd",
	"research":"res://gameplay/ResearchRuntime.gd",
}
var _models: Dictionary = {}
var _profile_id := ""
var _clock := 0.0
var _save_clock := 0.0
var fault := ""
var _busy := false

func model(domain: String) -> Script:
	if not _models.has(domain):
		_models[domain] = load(MODELS[domain])
	return _models[domain]

func prepare() -> bool:
	if not SaveService.has_profile():
		return false
	var id := str(GameState.profile["profile_id"])
	if _profile_id == id:
		return fault.is_empty()
	var next := GameState.profile.duplicate(true)
	if next.has("game") and not GameMath.valid_game(next["game"]):
		fault = "Игровые данные повреждены; запись остановлена."
		return false
	GameMath.game(next)
	for domain in MODELS:
		var script := model(domain)
		if script == null or not script.can_instantiate():
			fault = "Не удалось загрузить игровую систему: " + domain
			return false
		if script.has_method("ensure"):
			script.ensure(next)
		elif script.has_method("refresh"):
			script.refresh(next)
	_refresh(next)
	var g := GameMath.game(next)
	var now := int(Time.get_unix_time_from_system())
	var last := int(g.get("last_saved_ts", now))
	var seconds := mini(maxi(0, now - last), 14400 + 1440 * int(g.get("offline_level", 0)))
	if seconds > 2:
		var before: Dictionary = next["inventory"].duplicate(true)
		var money := int(next["money_cents"])
		simulate(next, seconds)
		g["offline_report"] = {"seconds":seconds, "money_cents":int(next["money_cents"]) - money, "materials":{}, "id":"%s:%d:%d" % [id, last, now]}
		for resource in next["inventory"]:
			var delta := int(next["inventory"][resource]) - int(before.get(resource, 0))
			if delta != 0:
				g["offline_report"]["materials"][resource] = delta
		g["offline_claim_id"] = g["offline_report"]["id"]
	g["last_saved_ts"] = now
	if SaveService.commit_profile(next) != OK:
		fault = "Не удалось сохранить игровое состояние. Освободи место и повтори запуск."
		message.emit(fault)
		return false
	_profile_id = id
	fault = ""
	_clock = 0.0
	_save_clock = 0.0
	changed.emit()
	return true

func _refresh(p: Dictionary) -> void:
	GameMath.sync_events(p)
	model("progression").refresh(p)
	model("research").refresh(p)
	model("meta").refresh(p)

func perform(domain: String, action: String, args: Dictionary = {}) -> Dictionary:
	if _busy or not MODELS.has(domain) or not prepare():
		return GameMath.fail("Игровое состояние недоступно")
	if (domain == "economy" and action == "queue") or (domain == "research" and action == "queue_recipe_chain"):
		if not building_complete("factory"):
			var denied := GameMath.fail("Сначала построй завод в разделе строительства")
			message.emit(denied["message"])
			return denied
	_busy = true
	var candidate := GameState.profile.duplicate(true)
	_refresh(candidate)
	var result: Dictionary = model(domain).act(candidate, action, args)
	if result.get("ok", false):
		if domain == "progression" and action in ["expand", "expansion"]:
			var expanded_site := str(args.get("site", "fe"))
			GameMath.site(candidate, expanded_site)["horizon"] = 0
			GameMath.site(candidate, expanded_site)["tap_fraction"] = 0.0
			if expanded_site in ["pd", "ir"]:
				model("sites").act(candidate, expanded_site + "_cancel", {})
		_refresh(candidate)
		GameMath.game(candidate)["last_saved_ts"] = int(Time.get_unix_time_from_system())
		if SaveService.commit_profile(candidate) != OK:
			result = GameMath.fail("Ошибка записи: действие не применено")
		else:
			changed.emit()
	_busy = false
	message.emit(str(result.get("message", "")))
	return result

func navigate(tab: String, site: String) -> Error:
	if not prepare() or not GameMath.SITES.has(site):
		return ERR_UNAVAILABLE
	var candidate := GameState.profile.duplicate(true)
	GameMath.game(candidate)["ui"] = {"tab":tab, "site":site}
	GameMath.game(candidate)["last_saved_ts"] = int(Time.get_unix_time_from_system())
	candidate["active_site"] = GameMath.SITE_IDS[site] if GameMath.unlocked(candidate, site) else GameMath.SITE_IDS["fe"]
	candidate["route"] = "earth"
	return SaveService.commit_profile(candidate)

func dismiss_offline() -> void:
	if not prepare():
		return
	var candidate := GameState.profile.duplicate(true)
	GameMath.game(candidate).erase("offline_report")
	GameMath.game(candidate)["last_saved_ts"] = int(Time.get_unix_time_from_system())
	SaveService.commit_profile(candidate)

func simulate(p: Dictionary, seconds: float) -> void:
	var remaining := maxf(0, seconds)
	while remaining > 0.000001:
		var step := _next_step(p, remaining)
		model("economy").advance(p, step)
		model("sites").advance(p, step)
		model("progression").advance(p, step)
		GameMath.sync_events(p)
		model("meta").advance(p, step)
		remaining -= step

func _next_step(p: Dictionary, remaining: float) -> float:
	var step := minf(60.0, remaining)
	var g := GameMath.game(p)
	var payroll := 0.0
	var iron_rate := 0.0
	for site_id in GameMath.SITES:
		if GameMath.unlocked(p,site_id):
			var metrics: Dictionary = model("economy").metrics(p,site_id)
			payroll += float(metrics.get("worker_wage_cents_per_minute",0))
			if site_id == "fe":
				iron_rate = float(metrics.get("rate_per_second",0))
	var room := GameMath.capacity(p)-GameMath.stored(p)
	if room > 0 and iron_rate > 0:
		step = minf(step,float(room)/iron_rate)
	var cycle_budget := 0.0
	var extraction: Dictionary = g.get("extraction",{})
	for site_id in ["pd","ir"]:
		if not GameMath.unlocked(p,site_id):
			continue
		var info: Dictionary = model("sites").view(p,site_id)
		if site_id == "pd":
			var lens: Dictionary = info.get("lens",{})
			if bool(info.get("automatic",false)) or str(info.get("status","idle")) not in ["idle","cancelled","completed"]:
				cycle_budget += 2.0 * (float(lens.get("sample_cost_cents",0))+float(lens.get("operating_cost_cents",0)))
		else:
			var campaign: Dictionary = info.get("campaign",{})
			if str(info.get("status","idle")) in ["running","waiting_funds"]:
				cycle_budget += float(campaign.get("projected_operation_cost_cents",0))
		var next_event := float(info.get("remaining_seconds",info.get("phase_remaining_seconds",0)))
		if next_event > 0.000001:
			step = minf(step,next_event)
	# Low budgets need fine interleaving of income, wages, and phase payments.
	if (payroll > 0 or cycle_budget > 0) and float(p["money_cents"]) < payroll + cycle_budget + 2:
		step = minf(step,1.0)
	for line in g.get("factory",[]):
		var next_event := float(line.get("active",{}).get("seconds_left",0))
		if next_event > 0.000001:
			step = minf(step,next_event)
	var progression: Dictionary = g.get("progression",{})
	for building in progression.get("buildings",{}).values():
		if str(building.get("status","")) == "building":
			var next_event := float(building.get("remaining_seconds",0))
			if next_event > 0.000001:
				step = minf(step,next_event)
	var expedition: Dictionary = progression.get("geology",{}).get("active",{})
	if float(expedition.get("remaining_seconds",0)) > 0.000001:
		step = minf(step,float(expedition["remaining_seconds"]))
	for boost in g.get("meta",{}).get("boosts",[]):
		if float(boost.get("remaining_s",0)) > 0.000001:
			step = minf(step,float(boost["remaining_s"]))
	return maxf(0.000001,step)

func _process(delta: float) -> void:
	if _profile_id.is_empty() or not fault.is_empty() or _busy or GameState.profile.get("profile_id", "") != _profile_id:
		return
	_clock += delta
	_save_clock += delta
	if _clock >= 1.0:
		var seconds := floorf(_clock)
		_clock -= seconds
		var candidate := GameState.profile.duplicate(true)
		simulate(candidate, seconds)
		GameState.profile = candidate
		changed.emit()
	if _save_clock >= 10.0:
		_save_clock = 0.0
		flush()

func flush() -> Error:
	if _profile_id.is_empty() or GameState.profile.get("profile_id", "") != _profile_id:
		return OK
	var candidate := GameState.profile.duplicate(true)
	GameMath.game(candidate)["last_saved_ts"] = int(Time.get_unix_time_from_system())
	var result := SaveService.commit_profile(candidate)
	if result != OK:
		message.emit("Не удалось записать автосохранение")
	return result

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush()

func building_complete(id: String) -> bool:
	return str(GameMath.game(GameState.profile).get("progression",{}).get("buildings",{}).get(id,{}).get("status","")) == "complete"
