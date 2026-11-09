extends Node

signal changed
signal message(text: String)

const MODELS := {
	"economy":"res://gameplay/EconomyModel.gd", "progression":"res://gameplay/ProgressionModel.gd",
	"meta":"res://gameplay/MetaModel.gd", "sites":"res://gameplay/SiteModel.gd",
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
	GameMath.game(next)
	for domain in MODELS:
		model(domain).ensure(next)
	_refresh(next)
	var g := GameMath.game(next)
	var now := int(Time.get_unix_time_from_system())
	var last := int(g.get("last_saved_ts", now))
	var seconds := mini(maxi(0, now - last), 14400 + 1440 * int(g.get("offline_level", 0)))
	if seconds > 2:
		var before := next["inventory"].duplicate(true)
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
	model("progression").refresh(p)
	model("meta").refresh(p)

func perform(domain: String, action: String, args: Dictionary = {}) -> Dictionary:
	if _busy or not MODELS.has(domain) or not prepare():
		return GameMath.fail("Игровое состояние недоступно")
	_busy = true
	var candidate := GameState.profile.duplicate(true)
	_refresh(candidate)
	var result: Dictionary = model(domain).act(candidate, action, args)
	if result.get("ok", false):
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
	candidate["active_site"] = GameMath.SITE_IDS[site] if GameMath.unlocked(candidate, site) else GameMath.SITE_IDS["fe"]
	candidate["route"] = "earth"
	return SaveService.commit_profile(candidate)

func dismiss_offline() -> void:
	if not prepare():
		return
	var candidate := GameState.profile.duplicate(true)
	GameMath.game(candidate).erase("offline_report")
	SaveService.commit_profile(candidate)

func simulate(p: Dictionary, seconds: float) -> void:
	var remaining := maxf(0, seconds)
	while remaining > 0.000001:
		var step := minf(1.0, remaining)
		for domain in ["economy", "sites", "progression", "meta"]:
			model(domain).advance(p, step)
		remaining -= step
	_refresh(p)

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
