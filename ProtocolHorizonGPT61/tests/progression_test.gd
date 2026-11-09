extends SceneTree

const Progression = preload("res://gameplay/ProgressionModel.gd")
const Sites = preload("res://gameplay/SiteModel.gd")

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
	_test_safe_repair_story_gate()
	_test_geology_large_advance()
	_test_offline_claim_ack_only()
	_test_expansion_preserves_global_state()
	_test_offline_prices()
	_test_validation_and_view_schema()
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
	check(bool(GameMath.game(p)["progression"]["effects"]["flags"].get("D02:bonus_pocket", false)), "D02 must expose its named feature flag without inventing an effect size")
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

func _test_safe_repair_story_gate() -> void:
	var p := profile()
	p["money_cents"] = 1000
	p["inventory"]["iron_ore"] = 5
	Progression.ensure(p)
	check(bool(Progression.act(p, "build", {"id":"safe_repair"}).get("ok", false)), "The concrete safe_repair project should be startable")
	Progression.advance(p, 10.0)
	GameMath.stat(p, "purchases:worker")
	GameMath.sync_events(p)
	check(int(GameMath.game(p)["stats"].get("safe_repairs", 0)) == 1, "Completed safe_repair should expose the A02 repair counter")
	check(bool(Progression.act(p, "story_open", {"id":"A02"}).get("ok", false)), "A02 should open after A01")
	check(bool(Progression.act(p, "story_complete", {"id":"A02"}).get("ok", false)), "A02 should become reachable after worker and real safe repair")
	check(bool(GameMath.game(p)["progression"]["story_done"].get("A02", false)), "A02 completion should persist")

func _test_geology_large_advance() -> void:
	var p := profile()
	p["money_cents"] = 1000
	Progression.ensure(p)
	check(bool(Progression.act(p, "geology_start", {"id":"fe_survey"}).get("ok", false)), "Paid Fe survey should start")
	check(int(p["money_cents"]) == 800, "Geology price should be paid when expedition starts")
	Progression.advance(p, 86400.0)
	var geology: Dictionary = GameMath.game(p)["progression"]["geology"]
	check(geology["reports"].size() == 1 and bool(geology["guaranteed_geobinding"]), "First survey should guarantee its report and Pd geobinding")
	check(int(p["research_points"]) == 1 and int(p["shards"]) == 2, "Proposal reward sources should be visible and deterministic")
	Progression.advance(p, 86400.0)
	check(geology["reports"].size() == 1 and int(p["research_points"]) == 1, "Idle large advances must not duplicate geology rewards")

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
	check(fe.get("active_batch", {}) == {"remaining":4} and int(fe["geodata"]) == 10, "Expansion should preserve pending local batch output and award mined geodata")
	check(pd["upgrades"].get("pd_upgrade") == 12, "Expansion must preserve other site")
	check(p["local"] == before_local, "Expansion must preserve equipment/specialists namespace")
	check(int(p["money_cents"]) == 4242 and int(p["inventory"]["iron_ore"]) == 31 and int(p["research_points"]) == 9, "Expansion must preserve global wallet, stock, and research")
	check(not bool(Progression.expansion_preview(p, "fe").get("eligible", false)), "No repeat expansion without new actual mining")
	var extraction: Dictionary = EarthSites.ensure(p)
	p["sites"]["site_earth_pd_7"]["unlocked"] = true
	var pd_extract: Dictionary = extraction["pd"]
	pd_extract["status"] = "sampling"
	pd_extract["sample"] = {"seed":7}
	pd_extract["automatic"] = true
	pd_extract["pending_output"] = 7
	var pd_expansion := GameMath.site(p, "pd")
	pd_expansion["upgrades"] = {"u1":60, "u2":60, "u3":60, "u4":60, "u5":60, "u6":60, "u7":60, "u8":60, "u9":60, "u10":60}
	pd_expansion["mined"] = 100.0
	g["progression"]["expansions"]["pd"] = {"mined_start":0}
	check(bool(Progression.act(p, "expand", {"site":"pd"}).get("ok", false)), "Pd expansion should complete without owning extraction cancellation")
	check(str(pd_extract["status"]) == "sampling" and not pd_extract["sample"].is_empty() and bool(pd_extract["automatic"]), "Progression expand must not duplicate the parent SiteModel cancellation")
	check(int(pd_extract["pending_output"]) == 7, "Progression expansion must preserve produced Pd output")
	p["inventory"] = {"iron_ore":10000}
	Sites.ensure(p)
	check(str(pd_extract["status"]) == "cancelled" and pd_extract["sample"].is_empty() and not bool(pd_extract["automatic"]) and int(pd_extract["pending_output"]) == 7, "Post-expansion SiteModel sync must cancel Pd while preserving output when storage is full")
	p["sites"]["site_earth_ir_9"]["unlocked"] = true
	var ir_extract: Dictionary = extraction["ir"]
	ir_extract["status"] = "running"
	ir_extract["campaign"] = {"status":"running", "phase_elapsed_s":5.0, "committed_cost_cents":100}
	ir_extract["pending_output"] = 3
	var ir_expansion := GameMath.site(p, "ir")
	ir_expansion["upgrades"] = {"u1":60, "u2":60, "u3":60, "u4":60, "u5":60, "u6":60, "u7":60, "u8":60, "u9":60, "u10":60}
	ir_expansion["mined"] = 100.0
	g["progression"]["expansions"]["ir"] = {"mined_start":0}
	check(bool(Progression.act(p, "expand", {"site":"ir"}).get("ok", false)), "Ir expansion should complete without owning extraction cancellation")
	check(str(ir_extract["status"]) == "running" and str(ir_extract["campaign"]["status"]) == "running", "Progression expand must not cancel Ir twice")
	Sites.ensure(p)
	check(str(ir_extract["status"]) == "cancelled" and str(ir_extract["campaign"]["status"]) == "cancelled" and int(ir_extract["pending_output"]) == 3, "Post-expansion SiteModel sync must cancel Ir without discarding pending output")
	check(int(p["money_cents"]) == 4242 and int(p["research_points"]) == 9, "Pd/Ir extraction cancellation must preserve global wallet and research")

func _test_offline_claim_ack_only() -> void:
	var p := profile()
	p["money_cents"] = 1000
	Progression.ensure(p)
	check(bool(Progression.act(p, "geology_start", {"id":"fe_survey"}).get("ok", false)), "Offline ack fixture expedition should start")
	var game := GameMath.game(p)
	var report := {"id":"profile-1:100:200", "seconds":100, "money_cents":25, "materials":{"iron_ore":2}}
	game["offline_report"] = report.duplicate(true)
	game["offline_report_acknowledged_id"] = ""
	var before_money := int(p["money_cents"])
	var before_points := int(p.get("research_points", 0))
	var before_shards := int(p.get("shards", 0))
	var before_remaining := float(game["progression"]["geology"]["active"]["remaining_seconds"])
	check(not bool(Progression.act(p, "offline_claim", {"claim_id":"invented", "elapsed_seconds":86400.0}).get("ok", false)), "Unknown offline report IDs must be rejected")
	check(float(game["progression"]["geology"]["active"]["remaining_seconds"]) == before_remaining, "Rejected offline claims must not advance time")
	var ack := Progression.act(p, "offline_claim", {"claim_id":report["id"]})
	check(bool(ack.get("ok", false)), "The existing GameSession report ID should be acknowledgeable")
	check(str(game.get("offline_report_acknowledged_id", "")) == report["id"], "Acknowledgment should persist only the report ID")
	check(int(p["money_cents"]) == before_money and int(p.get("research_points", 0)) == before_points and int(p.get("shards", 0)) == before_shards, "Acknowledging offline report must not grant rewards")
	check(float(game["progression"]["geology"]["active"]["remaining_seconds"]) == before_remaining, "Acknowledging offline report must not advance progression")
	check(not bool(Progression.act(p, "offline_claim", {"claim_id":"stale-report"}).get("ok", false)), "A stale offline report ID must be rejected")
	check(Progression.view(p)["offline_report_acknowledged"], "Progression view should expose the report acknowledgment state")

func _test_offline_prices() -> void:
	var p := profile()
	p["shards"] = 2950
	Progression.ensure(p)
	for _step in range(50):
		check(bool(Progression.act(p, "offline_upgrade").get("ok", false)), "Offline upgrade step should be affordable")
	check(int(p["shards"]) == 0, "Fifty offline steps must cost exactly 2950 shards")
	check(int(GameMath.game(p)["offline_level"]) == 50, "Offline level should stop at 50 steps")
	check(not bool(Progression.act(p, "offline_upgrade").get("ok", false)), "Offline steps must stop at the 24-hour cap")

func _test_validation_and_view_schema() -> void:
	var p := profile()
	Progression.ensure(p)
	check(Progression.validate(p), "A normalized progression state should validate")
	var view := Progression.view(p)
	check(view.has("action_schemas") and view.has("offered_actions") and view.has("coverage"), "View must expose action IDs/schemas and explicit feature coverage")
	check(view["offered_actions"].has("safe_repair") == false, "Safe repair is a building ID, not a top-level action verb")
	check(view["action_schemas"]["build"]["ids"].has("safe_repair"), "Build action schema must expose the safe_repair ID")
	GameMath.game(p)["progression"]["research"] = "tampered"
	check(not Progression.validate(p), "Semantic validation should reject a malformed research map before ensure repairs it")

func _finish() -> void:
	if failures.is_empty():
		print("PROGRESSION PASS: research DAG/costs, unlock gates, story, contracts, buildings, expansion, offline")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
