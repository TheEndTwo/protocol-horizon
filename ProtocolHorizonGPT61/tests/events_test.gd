extends SceneTree

var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

func _run() -> void:
	var meta = load("res://gameplay/MetaModel.gd")
	var p: Dictionary = root.get_node("GameState").make_new_profile()
	GameMath.game(p)["progression"] = {"geology":{"reports":[{"id":"GEO-TEST-1","tags":[]},{"id":"GEO-TEST-2","tags":[]}]}}
	meta.ensure(p)
	check(not meta.act(p,"event_action",{"id":"EV01"}).ok,"Pocket accepted before mining")
	GameMath.stat(p,"taps",20)
	meta.refresh(p)
	var before := int(p["inventory"]["iron_ore"])
	check(meta.act(p,"event_action",{"id":"EV01","choice":"auto_sort"}).ok,"Real pocket choice failed")
	check(p["inventory"]["iron_ore"] == before,"Selecting event gave unclaimed rewards")
	check(meta.act(p,"claim_event",{"event_id":"EV01"}).ok,"Pocket reward not claimable")
	check(GameMath.reserved(p,"iron_ore") == 50,"Auto-sort did not reserve actual reward")
	check(not meta.act(p,"claim_event",{"event_id":"EV01"}).ok,"Pocket reward duplicated")
	check(not meta.act(p,"event_action",{"id":"EV08","first_id":"GEO-TEST-1","second_id":"GEO-TEST-1"}).ok,"Same document accepted twice")
	check(meta.act(p,"event_action",{"id":"EV08","first_id":"GEO-TEST-1","second_id":"GEO-TEST-2"}).ok,"Document comparison failed")
	check(meta.act(p,"claim_event",{"event_id":"EV08"}).ok,"Evidence event cannot be claimed")
	p["sites"]["site_earth_pd_7"]["unlocked"] = true
	meta.refresh(p)
	check(not meta.act(p,"event_action",{"id":"EV05"}).ok,"Catalyst delivery accepted without production")
	p["inventory"]["pd_catalyst"] = 1
	GameMath.stat(p,"produced:pd_catalyst")
	meta.refresh(p)
	check(meta.act(p,"event_action",{"id":"EV05"}).ok,"Produced catalyst shipment failed")
	check(p["inventory"]["pd_catalyst"] == 0,"Shipment did not consume real component")
	check(meta.act(p,"claim_event",{"event_id":"EV05"}).ok,"Catalyst event reward missing")
	check(not meta.act(p,"event_action",{"id":"EV05"}).ok,"Catalyst shipment repeated")
	if failures.is_empty():
		print("EVENTS PASS: real pocket choices/reserve, physical catalyst shipment, document comparison, one-time rewards")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: "+failure)
		quit(1)
