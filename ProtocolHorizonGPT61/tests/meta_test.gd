extends SceneTree

const Meta = preload("res://gameplay/MetaModel.gd")
var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _profile() -> Dictionary:
	var p := {
		"profile_id":"earth-meta-test",
		"money_cents":100000,
		"shards":0,
		"inventory":{"iron_ore":0, "pd_concentrate":0, "ir_core":0, "case_basic":2, "case_rare":0, "case_elite":0, "case_specialist":0, "case_vip_daily":0},
		"sites":{
			"site_earth_fe_17":{"unlocked":true},
			"site_earth_pd_7":{"unlocked":false},
			"site_earth_ir_9":{"unlocked":false}
		}
	}
	GameMath.game(p)
	return p

func _run() -> void:
	var registry := root.get_node_or_null("ContentRegistry")
	check(registry != null and registry.is_loaded, "Canonical catalog registry not loaded")
	if registry == null or not registry.is_loaded:
		_finish()
		return
	var p := _profile()
	Meta.ensure(p)
	var view := Meta.view(p)
	check(view["specialists"]["catalog"].size() == 80, "Expected all 80 canonical specialists")
	check(view["gear"]["items"].size() == 20, "Expected free starter gear for Fe, Pd, Ir")
	var ids: Dictionary = {}
	for item in view["gear"]["items"]:
		ids[str(item["id"])] = true
	check(ids.size() == 20, "Starter gear IDs must be unique")
	check(view["gear"]["equipped"]["fe"].size() == 8, "Fe starter kit must equip all eight slots")
	check(view["gear"]["equipped"]["pd"].size() == 6 and view["gear"]["equipped"]["ir"].size() == 6, "Pd and Ir starter kits must have six slots")
	for case_row in view["cases"]["catalog"]:
		check(int(case_row["rarity_probability_total"]) == 100, "Canonical rarity odds must total 100 for " + str(case_row["id"]))
		check(int(case_row["category_probability_total"]) == 100, "Canonical category odds must total 100 for " + str(case_row["id"]))
	var vip_ids := ["VIP_FE_5", "VIP_PD_6", "VIP_IR_7", "VIP_GLOBAL_10"]
	for row in view["specialists"]["catalog"]:
		if vip_ids.has(str(row["id"])):
			check(not bool(row["eligible_case_pool"]), "VIP exclusive entered ordinary case pool: " + str(row["id"]))
			check(not bool(row["owned"]), "VIP exclusive was granted without verified purchase")
	check(not bool(view["cases"]["catalog"].back()["available"]), "VIP case must remain unavailable without receipt verification")
	var before_bonus := GameMath.bonus(p, "tap", "fe")
	var pickaxe: Dictionary = view["gear"]["items"].filter(func(item): return item["template_id"] == "starter_fe_pickaxe")[0]
	var upgraded := Meta.act(p, "gear_upgrade", {"item_id":pickaxe["id"]})
	check(bool(upgraded["ok"]), "Gear upgrade should spend real in-game currency")
	check(GameMath.bonus(p, "tap", "fe") > before_bonus, "Equipped gear upgrade must alter gameplay bonus")
	p["game"]["meta"]["gear"]["fragments"]["starter_fe_pickaxe"] = 5
	var starred := Meta.act(p, "gear_star", {"item_id":pickaxe["id"]})
	check(bool(starred["ok"]), "Gear star should consume actual fragments")
	var gear_snapshot: Array = p["game"]["meta"]["gear"]["items"].duplicate(true)
	GameMath.site(p, "fe")["expansions"] = 1
	Meta.refresh(p)
	check(p["game"]["meta"]["gear"]["items"] == gear_snapshot, "Site progression must not erase equipment")
	p["sites"]["site_earth_pd_7"]["unlocked"] = true
	p["game"]["meta"]["specialists"]["owned"]["SP04"] = {"level":1, "stars":0}
	var assigned := Meta.act(p, "specialist_assign", {"specialist_id":"SP04", "site":"fe", "slot":0})
	check(bool(assigned["ok"]), "Eligible specialist assignment failed")
	var duplicate_assignment := Meta.act(p, "specialist_assign", {"specialist_id":"SP04", "site":"pd", "slot":0})
	check(not bool(duplicate_assignment["ok"]), "One specialist was assigned to multiple sites")
	check(GameMath.bonus(p, "output", "fe") > 0.0, "Assigned canonical specialist must provide a real bonus")
	var before_tasks: Dictionary = p["game"]["meta"]["season"]["tasks"].duplicate(true)
	GameMath.stat(p, "contract_fulfilled", 1)
	var task_view: Dictionary = Meta.view(p)
	check(p["game"]["meta"]["season"]["tasks"] == before_tasks, "Viewing meta must not progress saved season tasks")
	var day_task: Dictionary = task_view["season"]["tasks"].filter(func(task): return task["template_id"] == "DAY01")[0]
	check(int(day_task["progress"]) == 1, "Task view should reflect the real contract counter")
	var task_claim := Meta.act(p, "claim_season_task", {"task_id":"DAY01"})
	check(bool(task_claim["ok"]) and int(p["game"]["meta"]["season"]["xp"]) == 25, "Canonical season task should grant XP once")
	check(not bool(Meta.act(p, "claim_season_task", {"task_id":"DAY01"})["ok"]), "Season task reward was claimed twice")
	GameMath.stat(p, "taps", 100)
	check(bool(Meta.act(p, "claim_case_milestone", {"milestone_id":"MINE_100_TAPS"})["ok"]), "F2P stat milestone should grant a case")
	check(not bool(Meta.act(p, "claim_case_milestone", {"milestone_id":"MINE_100_TAPS"})["ok"]), "Case milestone was claimed twice")
	var first_open := Meta.act(p, "case_open", {"case_id":"case_basic", "open_id":"test-open-001"})
	check(bool(first_open.get("ok", false)), "Free case should open: " + str(first_open))
	var quantity_after_open := int(p["inventory"]["case_basic"])
	var replay_open := Meta.act(p, "case_open", {"case_id":"case_basic", "open_id":"test-open-001"})
	check(bool(replay_open.get("ok", false)) and bool(replay_open.get("replayed", false)), "Repeated open ID should return its committed result: " + str(replay_open))
	check(int(p["inventory"]["case_basic"]) == quantity_after_open, "Repeated open ID must not consume or award twice")
	check(first_open.get("seed", -1) == replay_open.get("seed", -2) and first_open.get("result", {}) == replay_open.get("result", {}), "Case open ID must preserve deterministic result")
	GameMath.stat(p, "iron_pocket_choice", 1)
	Meta.refresh(p)
	var event_view: Dictionary = Meta.view(p)["events"].filter(func(event): return event["id"] == "EV01")[0]
	check(int(event_view["progress"]) == 1, "Event must progress from its gameplay stat, not viewing")
	check(bool(Meta.act(p, "claim_event", {"event_id":"EV01"})["ok"]), "Completed F2P event should grant its one-time reward")
	check(not bool(Meta.act(p, "claim_event", {"event_id":"EV01"})["ok"]), "Event reward was claimed twice")
	p["game"]["meta"]["season"]["xp"] = 100
	check(bool(Meta.act(p, "claim_season_reward", {"level":1, "lane":"free"})["ok"]), "Proposed free reward should be claimable after level unlock")
	check(not bool(Meta.act(p, "claim_season_reward", {"level":1, "lane":"free"})["ok"]), "Season level reward was claimed twice")
	check(not bool(Meta.act(p, "claim_season_reward", {"level":1, "lane":"premium"})["ok"]), "Premium reward must require verified purchase")
	check(int(Meta.view(p)["vip"]["rank"]) == 0, "VIP rank must remain zero without verified StoreKit receipts")
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("META PASS: gear, specialists, deterministic cases, milestones, season, events, VIP, and view isolation")
		quit(0)
		return
	for failure in failures:
		printerr("FAIL: " + failure)
	quit(1)
