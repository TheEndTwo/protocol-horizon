extends SceneTree

const StateModel = preload("res://autoload/GameState.gd")
const EconomyModel = preload("res://gameplay/EconomyModel.gd")
const ProgressionModel = preload("res://gameplay/ProgressionModel.gd")
const SiteModel = preload("res://gameplay/SiteModel.gd")
const ResearchModel = preload("res://gameplay/ResearchRuntime.gd")

const QA_CASH_CENTS := 2_000_000
const QA_RAW_IRON := 1_000

var profile: Dictionary = {}
var failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var registry: Node = root.get_node_or_null("ContentRegistry")
	if registry == null or not registry.is_loaded:
		_finish("canonical content unavailable")
		return

	profile = StateModel.make_new_profile()
	profile["story"]["intro_seen"] = true
	profile["money_cents"] = QA_CASH_CENTS
	profile["inventory"]["iron_ore"] = QA_RAW_IRON
	EconomyModel.ensure(profile)
	ProgressionModel.ensure(profile)
	SiteModel.ensure(profile)
	ProgressionModel.refresh(profile)
	ResearchModel.refresh(profile)

	var workers: Array = EconomyModel.definitions("fe", "worker")
	if not _action(EconomyModel.act(profile, "buy", {"site":"fe", "kind":"worker", "id":str(workers[0]["id"]), "count":1}), "hire first worker"):
		_finish("worker action failed")
		return
	if not _build("safe_repair", 11.0) or not _chapter("A02"):
		_finish("A02 path failed")
		return
	if not _geology("fe_survey") or not _chapter("A03"):
		_finish("A03 path failed")
		return
	var accepted := ProgressionModel.act(profile, "contract_accept", {"id":"ore_delivery"})
	if not _action(accepted, "accept ore contract"):
		_finish("contract accept failed")
		return
	var order_id := str(accepted.get("order_id", ""))
	if not _action(ProgressionModel.act(profile, "contract_ship", {"order_id":order_id}), "ship ore contract") or not _action(ProgressionModel.act(profile, "contract_claim", {"order_id":order_id}), "claim ore contract") or not _chapter("A04"):
		_finish("A04 path failed")
		return
	if not _geology("fe_survey") or not _chapter("A05"):
		_finish("A05 path failed")
		return
	if not _action(EconomyModel.act(profile, "sell", {"resource":"iron_ore", "amount":1}), "sell free iron"):
		_finish("sale evidence failed")
		return
	if not _build("hq", 16.0) or not _build("factory", 61.0):
		_finish("factory setup failed")
		return
	if not _craft("R_INGOT", 4, 121.0) or not _craft("R_STEEL", 1, 61.0):
		_finish("first steel production failed")
		return
	for definition in EconomyModel.definitions("fe", "upgrade"):
		if not _action(EconomyModel.act(profile, "buy", {"site":"fe", "kind":"upgrade", "id":str(definition["id"]), "count":35}), "raise Fe average to 350"):
			_finish("Fe progression purchase failed")
			return
	var fe_peak := int(GameMath.site(profile, "fe").get("peak", 0))
	if not _check(fe_peak == 350 and not _done("A07"), "Fe must reach exactly 350 without completing A07; peak=%d" % fe_peak):
		_finish("Fe gate setup failed")
		return
	if not _chapter("A06"):
		_finish("A06 path failed")
		return
	ProgressionModel.refresh(profile)
	if not _check(GameMath.unlocked(profile, "pd"), "Pd must unlock from A06 + Fe 350 + produced steel + first survey, without A07") or not _chapter("A08"):
		_finish("Pd unlock/A08 failed")
		return
	if not _check(int(GameMath.site(profile, "fe").get("expansions", 0)) == 0, "QA route unexpectedly used Fe expansion"):
		_finish("unexpected expansion")
		return

	var pd_cycles := 0
	while int(profile["inventory"].get("pd_concentrate", 0)) < 16 and pd_cycles < 5:
		if not _action(SiteModel.act(profile, "take_sample", {"site":"pd"}), "take real Pd sample"):
			_finish("Pd sample action failed")
			return
		_tick(45.0)
		if not _check(str(SiteModel.view(profile, "pd").get("status", "")) == "ready", "Pd sampling did not finish"):
			_finish("Pd sampling stalled")
			return
		if not _action(SiteModel.act(profile, "start_cycle", {"site":"pd"}), "start Pd concentration"):
			_finish("Pd cycle action failed")
			return
		_tick(180.0)
		pd_cycles += 1
	if not _check(int(profile["inventory"].get("pd_concentrate", 0)) >= 16, "Real Pd cycles did not produce enough concentrate"):
		_finish("Pd production insufficient")
		return
	if not _craft("R_PD_REFINED", 4, 361.0) or not _craft("R_PD_CAT", 2, 241.0) or not _chapter("A09") or not _chapter("A10"):
		_finish("Pd refining/catalyst progression failed")
		return
	if not _geology("fe_survey") or not _chapter("A11"):
		_finish("A11 railway log path failed")
		return
	if not _chapter("A12") or not _action(ProgressionModel.act(profile, "propose_alternative_contract"), "propose alternative contract") or not _chapter("A12"):
		_finish("A12 negotiation path failed")
		return
	if not _geology("fe_survey") or not _chapter("A13"):
		_finish("A13 archive path failed")
		return
	if not _action(ProgressionModel.act(profile, "research", {"id":"D01"}), "purchase research evidence"):
		_finish("research evidence failed")
		return
	if not _build("power", 46.0):
		_finish("power construction failed")
		return
	if not _craft("R_INGOT", 84, 2_641.0) or not _craft("R_STEEL", 19, 1_141.0):
		_finish("additional Fe steel production failed")
		return
	if not _build("deep_station", 301.0):
		_finish("deep station construction failed")
		return
	ProgressionModel.refresh(profile)
	if not _check(GameMath.unlocked(profile, "ir"), "Ir must unlock after A13, real Pd catalyst, two reports and the deep station") or not _chapter("A14"):
		_finish("Ir unlock/A14 failed")
		return
	if not _action(ProgressionModel.act(profile, "geology_start", {"id":"ir_probe"}), "start Ir spectrum survey"):
		_finish("Ir probe failed")
		return
	_tick(91.0)
	if not _chapter("A15") or not _chapter("A16") or not _action(ProgressionModel.act(profile, "compare_worker_registry"), "compare worker registry") or not _chapter("A16"):
		_finish("A15/A16 evidence path failed")
		return
	var campaigns := 0
	while int(profile["inventory"].get("ir_core", 0)) < 5 and campaigns < 4:
		if not _action(SiteModel.act(profile, "start_campaign", {"site":"ir", "strategy_id":"reliable"}), "start real Ir campaign"):
			_finish("Ir campaign action failed")
			return
		_tick(500.0)
		campaigns += 1
	if not _check(int(profile["inventory"].get("ir_core", 0)) >= 5, "Real Ir campaigns did not produce cores for refining and the safe project"):
		_finish("Ir core production insufficient")
		return
	if not _geology("deep_signal") or not _chapter("A17") or not _chapter("A18") or not _action(ProgressionModel.act(profile, "story_transmit"), "attempt evidence transmission") or not _chapter("A18") or not _chapter("A19"):
		_finish("A17-A19 evidence path failed")
		return
	if not _craft("R_INGOT", 8, 241.0) or not _craft("R_HI_ALLOY", 4, 481.0) or not _craft("R_IR_REFINED", 1, 121.0) or not _craft("R_IR_CONTACT", 1, 181.0):
		_finish("real alloy/refining/thermal-contact production failed")
		return
	if not _build("safe_cavity_project", 301.0) or not _action(ProgressionModel.act(profile, "story_reserve_contact"), "reserve thermal contact") or not _chapter("A20"):
		_finish("A20 preparation failed")
		return
	if not _action(ProgressionModel.act(profile, "enter_cavity"), "enter cavity safely"):
		_finish("safe cavity entry failed")
		return
	var before_samples := int(profile["inventory"].get("KEY_HORIZONITE_SAMPLE", 0))
	if not _check(before_samples == 0, "QA fixture already contains the story sample") or not _action(ProgressionModel.act(profile, "story_complete", {"id":"A20"}), "complete A20"):
		_finish("A20 completion failed")
		return
	var duplicate := ProgressionModel.act(profile, "story_complete", {"id":"A20"})
	if not _check(not bool(duplicate.get("ok", false)) and int(profile["inventory"].get("KEY_HORIZONITE_SAMPLE", 0)) == 1, "A20 must award one non-repeatable sample"):
		_finish("duplicate A20 reward")
		return
	_check(bool(profile["game"]["progression"]["story"]["flags"].get("phase2_discovered", false)), "A20 must discover phase 2")
	_check(float(profile["game"]["stats"].get("iap_spend_cents", 0)) == 0.0, "Integrated QA route must not use IAP")
	_check(int(GameMath.site(profile, "fe").get("peak", 0)) == 350 and not _done("A07"), "A08 reachability must not use Fe 600/A07")
	_check(int(GameMath.site(profile, "fe").get("expansions", 0)) == 0, "Integrated route must not require expansion")
	_finish("A01-A20 genuine actions; real production, campaigns, evidence, and one A20 sample")


func _chapter(id: String) -> bool:
	if not _action(ProgressionModel.act(profile, "story_open", {"id":id}), "open " + id):
		return false
	return _action(ProgressionModel.act(profile, "story_complete", {"id":id}), "complete " + id)


func _build(id: String, seconds: float) -> bool:
	if not _action(ProgressionModel.act(profile, "build", {"id":id}), "start building " + id):
		return false
	_tick(seconds)
	return _check(str(profile["game"]["progression"]["buildings"].get(id, {}).get("status", "")) == "complete", id + " did not complete")


func _geology(id: String) -> bool:
	if not _action(ProgressionModel.act(profile, "geology_start", {"id":id}), "start geology " + id):
		return false
	_tick(121.0)
	return true


func _craft(id: String, count: int, seconds: float) -> bool:
	if not _action(EconomyModel.act(profile, "queue", {"recipe":id, "line":0, "count":count}), "queue " + id):
		return false
	_tick(seconds)
	return true


func _tick(seconds: float) -> void:
	EconomyModel.advance(profile, seconds)
	SiteModel.advance(profile, seconds)
	ProgressionModel.advance(profile, seconds)


func _done(id: String) -> bool:
	return bool(profile.get("game", {}).get("progression", {}).get("story_done", {}).get(id, false))


func _action(result: Dictionary, label: String) -> bool:
	return _check(bool(result.get("ok", false)), "%s rejected: %s" % [label, str(result.get("message", "no response"))])


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures.append(message)
	return condition


func _finish(label: String) -> void:
	if failures.is_empty():
		print("EARTH STORY PASS: " + label)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
