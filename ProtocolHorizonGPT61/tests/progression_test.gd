extends SceneTree

const Progression = preload("res://gameplay/ProgressionModel.gd")

var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func profile() -> Dictionary:
	return {
		"money_cents":0, "shards":0, "research_points":0,
		"inventory":{"iron_ore":0}, "sites":{
			"site_earth_fe_17":{"unlocked":true}, "site_earth_pd_7":{"unlocked":false}, "site_earth_ir_9":{"unlocked":false}
		}, "story":{"current_id":"A01", "line":0, "intro_seen":true}, "local":{"equipment":{"pickaxe":"starter"}}
	}

func _run() -> void:
	var registry: Node = root.get_node("ContentRegistry")
	check(registry.is_loaded, "Canonical catalogues failed to load: " + str(registry.errors))
	if not registry.is_loaded:
		_finish()
		return
	_test_research()
	_test_site_unlocks()
	_test_story_open_is_not_reward()
	_test_contract_claim_once()
	_test_building_reservation()
	_test_geology_and_offline_claim()
	_test_expansion_preserves_global_state()
	_test_offline_prices()
	_finish()

func _test_research() -> void:
	var p := profile()
	Progression.ensure(p)
	var audit: Dictionary = Progression.research_catalog_audit()
	check(int(audit.get("count", 0)) == 140, "Expected all 140 canonical research nodes")
	check(int(audit.get("total_cost_oi", 0)) == 992, "Canonical research budget must total 992 OI")
	check(bool(audit.get("valid_dag", false)), "Research dependencies must be a DAG: " + str(audit.get("issues", [])))
	check(not bool(Progression.act(p, "research", {"id":"D02"}).get("ok", false)), "Dependency-blocked node D02 was purchasable")
	check(not bool(Progression.act(p, "research", {"id":"D01"}).get("ok", false)), "Research without OI was purchasable")
	p["research_points"] = 2
	check(bool(Progression.act(p, "research", {"id":"D01"}).get("ok", false)), "D01 should cost its canonical two OI")
	check(not bool(Progression.act(p, "research", {"id":"D02"}).get("ok", false)), "D02 should still require its full D01 prerequisite")
	check(int(Progression.research_status(p, "D02").get("next_cost", 0)) == 2, "Level cost split must sum to the canonical D02 total")
	p["research_points"] = 2
	check(bool(Progression.act(p, "research", {"id":"D02"}).get("ok", false)), "D02 first level should be purchasable after D01")
	check(is_equal_approx(GameMath.bonus(p, "tap", "fe"), 0.05), "D02 proposal must feed the real GameMath bonus hook")
	check(GameMath.records("mastery").size() == 24, "All 24 canonical mastery skills must be retained")
	var g := GameMath.game(p)
	for site in ["fe", "pd", "ir"]:
		GameMath.site(p, site)["peak"] = 1000
	Progression.refresh(p)
	check(int(g["progression"]["mastery_points_earned"]) == 24, "Mastery points should derive from persistent peak milestones")
	check(bool(Progression.mastery_status(p, "FE_SK01").get("can_unlock", false)), "Reached mastery milestone should be actionable")

func _test_site_unlocks() -> void:
	var p := profile()
	Progression.ensure(p)
	var fe := GameMath.site(p, "fe")
	fe["peak"] = 350
	GameMath.game(p)["stats"]["produced:steel"] = 1.0
	GameMath.game(p)["progression"]["story_done"]["A06"] = true
	Progression.refresh(p)
	check(not GameMath.unlocked(p, "pd"), "Pd must remain locked without a guaranteed geology binding")
	GameMath.game(p)["progression"]["geology"]["guaranteed_geobinding"] = true
	Progression.refresh(p)
	check(GameMath.unlocked(p, "pd"), "Pd must unlock at Fe peak 350 without A07/A08 or expansion")
	check(not bool(GameMath.game(p)["progression"]["story_done"].get("A08", false)), "Pd unlock must not fabricate completion of A08")
	GameMath.game(p)["progression"]["story_done"]["A13"] = true
	GameMath.game(p)["stats"]["produced:pd_catalyst"] = 1.0
	GameMath.game(p)["progression"]["geology"]["reports"] = [{"id":"one"}, {"id":"two"}]
	Progression.refresh(p)
	check(not GameMath.unlocked(p, "ir"), "Ir must remain locked without a completed deep station")
	GameMath.game(p)["progression"]["buildings"]["deep_station"] = {"status":"complete"}
	Progression.refresh(p)
	check(GameMath.unlocked(p, "ir"), "Ir must unlock with A13, own Pd catalyst, two reports, and deep station")

func _test_story_open_is_not_reward() -> void:
	var p := profile()
	Progression.ensure(p)
	p["inventory"]["iron_ore"] = 7
	var before: Dictionary = p["inventory"].duplicate(true)
	check(bool(Progression.act(p, "story_open", {"id":"A02"}).get("ok", false)), "A02 should open after parent-managed A01 intro")
	check(p["inventory"] == before, "Opening a story must not grant or consume resources")
	check(not bool(GameMath.game(p)["progression"]["story_done"].get("A02", false)), "Opening a story must not mark it complete")
	check(not bool(Progression.act(p, "story_complete", {"id":"A02"}).get("ok", false)), "A02 must require real worker and repair counters")

func _test_contract_claim_once() -> void:
	var p := profile()
	p["inventory"]["iron_ore"] = 5
	Progression.ensure(p)
	var accepted: Dictionary = Progression.act(p, "contract_accept", {"id":"science_supply"})
	check(bool(accepted.get("ok", false)), "F2P science contract should be accept-able")
	var order_id := str(accepted.get("order_id", ""))
	check(GameMath.free_amount(p, "iron_ore") == 0, "Accepted contract should reserve its input")
	check(bool(Progression.act(p, "contract_ship", {"order_id":order_id}).get("ok", false)), "Reserved science input should ship")
	check(bool(Progression.act(p, "contract_claim", {"order_id":order_id}).get("ok", false)), "Shipped science order should award research points")
	check(int(p["research_points"]) == 1, "Science contract must award one research point without payment")
	check(not bool(Progression.act(p, "contract_claim", {"order_id":order_id}).get("ok", false)), "Contract reward must not be claimed twice")
	check(int(p["research_points"]) == 1, "Duplicate claim must not duplicate research points")

func _test_building_reservation() -> void:
	var p := profile()
	p["money_cents"] = 1000
	p["inventory"]["iron_ore"] = 25
	Progression.ensure(p)
	var started: Dictionary = Progression.act(p, "build", {"id":"hq"})
	check(bool(started.get("ok", false)), "HQ should start when proposal cost is available")
	check(GameMath.free_amount(p, "iron_ore") == 0, "Construction material should be reserved")
	check(not Progression._building_complete(p, "hq"), "A started building must not be instantly complete")
	Progression.advance(p, 15.0)
	check(Progression._building_complete(p, "hq"), "HQ should complete after its real timer")
	check(int(p["inventory"]["iron_ore"]) == 0, "Reserved construction material should be consumed once at completion")

func _test_geology_and_offline_claim() -> void:
	var p := profile()
	p["money_cents"] = 1000
	Progression.ensure(p)
	check(bool(Progression.act(p, "geology_start", {"id":"fe_survey"}).get("ok", false)), "Paid Fe survey should start")
	check(int(p["money_cents"]) == 800, "Geology price should be paid when expedition starts")
	var claim := Progression.act(p, "offline_claim", {"claim_id":"test-offline-1", "elapsed_seconds":30.0})
	check(bool(claim.get("ok", false)), "Timed expedition should advance in a one-time offline claim")
	var geology: Dictionary = GameMath.game(p)["progression"]["geology"]
	check(geology["reports"].size() == 1 and bool(geology["guaranteed_geobinding"]), "First survey should guarantee its report and Pd geobinding")
	check(int(p["research_points"]) == 1 and int(p["shards"]) == 2, "Proposal reward sources should be visible and deterministic")
	check(not bool(Progression.act(p, "offline_claim", {"claim_id":"test-offline-1", "elapsed_seconds":30.0}).get("ok", false)), "Offline claim ID must not be reusable")
	check(geology["reports"].size() == 1, "Repeated offline report claim must not duplicate geology rewards")

func _test_expansion_preserves_global_state() -> void:
	var p := profile()
	p["money_cents"] = 4242
	p["inventory"]["iron_ore"] = 31
	p["research_points"] = 9
	Progression.ensure(p)
	var g := GameMath.game(p)
	var fe := GameMath.site(p, "fe")
	var pd := GameMath.site(p, "pd")
	fe["upgrades"] = {"u1":600, "u2":600, "u3":600, "u4":600, "u5":600, "u6":600, "u7":600, "u8":600, "u9":600, "u10":600}
	fe["machines"] = {"drill":2}
	fe["workers"] = {"miners":4}
	fe["mined"] = 1000.0
	fe["active_batch"] = {"remaining":4}
	pd["upgrades"] = {"pd_upgrade":12}
	g["progression"]["expansions"]["fe"] = {"mined_start":0}
	var before_local: Dictionary = p["local"].duplicate(true)
	var preview: Dictionary = Progression.expansion_preview(p, "fe")
	check(bool(preview.get("eligible", false)) and int(preview.get("geodata_award", 0)) == 10, "Fe600 preview should award geodata only from 1000 mined units")
	check(bool(Progression.act(p, "expand", {"site":"fe"}).get("ok", false)), "Eligible Fe expansion should complete")
	check(fe["upgrades"].is_empty() and fe["machines"].is_empty() and fe["workers"].is_empty(), "Expansion should reset only local levels, machines, workers")
	check(not fe.has("active_batch") and int(fe["geodata"]) == 10, "Expansion should safely cancel local batch and award mined geodata")
	check(pd["upgrades"].get("pd_upgrade") == 12, "Expansion must preserve other site")
	check(p["local"] == before_local, "Expansion must preserve equipment/specialists namespace")
	check(int(p["money_cents"]) == 4242 and int(p["inventory"]["iron_ore"]) == 31 and int(p["research_points"]) == 9, "Expansion must preserve global wallet, stock, and research")
	check(not bool(Progression.expansion_preview(p, "fe").get("eligible", false)), "No repeat expansion without new actual mining")

func _test_offline_prices() -> void:
	var p := profile()
	p["shards"] = 2950
	Progression.ensure(p)
	for _step in range(50):
		check(bool(Progression.act(p, "offline_upgrade").get("ok", false)), "Offline upgrade step should be affordable")
	check(int(p["shards"]) == 0, "Fifty offline steps must cost exactly 2950 shards")
	check(int(GameMath.game(p)["offline_level"]) == 50, "Offline level should stop at 50 steps")
	check(not bool(Progression.act(p, "offline_upgrade").get("ok", false)), "Offline steps must stop at the 24-hour cap")

func _finish() -> void:
	if failures.is_empty():
		print("PROGRESSION PASS: research DAG/costs, unlock gates, story, contracts, buildings, expansion, offline")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
