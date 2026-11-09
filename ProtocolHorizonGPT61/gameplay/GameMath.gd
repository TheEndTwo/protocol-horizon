class_name GameMath
extends RefCounted

static var _catalog_cache: Dictionary = {}
static var _record_cache: Dictionary = {}
static var _building_spec_cache: Dictionary = {}

const SITES := ["fe", "pd", "ir"]
const SITE_IDS := {"fe":"site_earth_fe_17", "pd":"site_earth_pd_7", "ir":"site_earth_ir_9"}
const OUTPUTS := {"fe":"iron_ore", "pd":"pd_concentrate", "ir":"ir_core"}

static func game(p: Dictionary) -> Dictionary:
	if not p.has("game"):
		p["game"] = {}
	var g: Dictionary = p["game"]
	for key in ["sites", "stats", "reservations", "bonuses", "claims"]:
		if not g.has(key):
			g[key] = {}
	return g

static func site(p: Dictionary, id: String) -> Dictionary:
	var sites: Dictionary = game(p)["sites"]
	if not sites.has(id):
		sites[id] = {"upgrades":{}, "machines":{}, "workers":{}, "peak":0, "horizon":0, "expansions":0, "geodata":0, "mined":0.0, "fraction":0.0, "wage_fraction":0.0}
	return sites[id]

static func unlocked(p: Dictionary, id: String) -> bool:
	var canonical := str(SITE_IDS.get(id, id))
	return canonical in SITE_IDS.values() and bool(p.get("sites", {}).get(canonical, {}).get("unlocked", false))

static func registry() -> Node:
	return Engine.get_main_loop().root.get_node("ContentRegistry")

# Internal canonical data is read-only; public registry access still returns copies.
static func records(catalog: String) -> Array:
	if not _catalog_cache.has(catalog):
		_catalog_cache[catalog] = registry().get_records(StringName(catalog))
	return _catalog_cache[catalog]

static func record(catalog: String, id: String) -> Dictionary:
	var key := catalog + ":" + id
	if not _record_cache.has(key):
		_record_cache[key] = registry().get_record(StringName(catalog), id)
	return _record_cache[key]

static func stat(p: Dictionary, key: String, amount: float = 1.0) -> void:
	var stats: Dictionary = game(p)["stats"]
	stats[key] = float(stats.get(key, 0.0)) + amount

static func bonus(p: Dictionary, key: String, id: String = "fe") -> float:
	var value := 0.0
	for domain in game(p)["bonuses"].values():
		value += float(domain.get(key, 0.0)) + float(domain.get(id + ":" + key, 0.0))
	return value

static func capacity(p: Dictionary) -> int:
	return 10000 + int(bonus(p, "storage"))

static func stored(p: Dictionary) -> int:
	var total := 0
	for value in p["inventory"].values():
		total += int(value)
	return total

static func reserved(p: Dictionary, id: String) -> int:
	var total := 0
	for reservation in game(p)["reservations"].values():
		total += int(reservation.get(id, 0))
	return total

static func free_amount(p: Dictionary, id: String) -> int:
	return maxi(0, int(p["inventory"].get(id, 0)) - reserved(p, id))

static func take(p: Dictionary, id: String, amount: int) -> bool:
	if amount < 0 or free_amount(p, id) < amount:
		return false
	p["inventory"][id] = int(p["inventory"].get(id, 0)) - amount
	return true

static func add(p: Dictionary, id: String, amount: int) -> int:
	var accepted := mini(maxi(amount, 0), maxi(0, capacity(p) - stored(p)))
	p["inventory"][id] = int(p["inventory"].get(id, 0)) + accepted
	return accepted

static func pay(p: Dictionary, cents: int) -> bool:
	if cents < 0 or int(p["money_cents"]) < cents:
		return false
	p["money_cents"] = int(p["money_cents"]) - cents
	return true

static func ok(message: String = "Готово") -> Dictionary:
	return {"ok":true, "message":message}

static func fail(message: String) -> Dictionary:
	return {"ok":false, "message":message}

static func valid_game(value: Dictionary) -> bool:
	for field in ["sites", "stats", "reservations", "bonuses", "claims", "progression", "meta", "extraction", "ui"]:
		if value.has(field) and not value[field] is Dictionary:
			return false
	for counter in value.get("stats", {}).values():
		if typeof(counter) == TYPE_BOOL:
			continue
		if not _unsigned_number(counter):
			return false
	for id in value.get("sites", {}):
		if not SITES.has(id) or not value["sites"][id] is Dictionary:
			return false
		var state: Dictionary = value["sites"][id]
		for field in ["upgrades", "machines", "workers"]:
			if state.has(field) and not state[field] is Dictionary:
				return false
			for level in state.get(field, {}).values():
				if not _unsigned_number(level) or float(level) != floorf(float(level)) or float(level) > 1000:
					return false
		for field in ["peak", "horizon", "expansions", "geodata", "mined", "fraction", "wage_fraction"]:
			if state.has(field) and not _unsigned_number(state[field]):
				return false
	for field in ["offline_level", "last_saved_ts"]:
		if value.has(field) and not _unsigned_number(value[field]):
			return false
	if int(value.get("offline_level", 0)) > 50:
		return false
	var shapes := {
		"progression":{"research":TYPE_DICTIONARY,"mastery":TYPE_DICTIONARY,"story_done":TYPE_DICTIONARY,"story_read":TYPE_DICTIONARY,"story_archive":TYPE_ARRAY,"buildings":TYPE_DICTIONARY,"geology":TYPE_DICTIONARY,"contracts":TYPE_DICTIONARY,"effects":TYPE_DICTIONARY},
		"meta":{"gear":TYPE_DICTIONARY,"specialists":TYPE_DICTIONARY,"cases":TYPE_DICTIONARY,"season":TYPE_DICTIONARY,"events":TYPE_DICTIONARY,"claims":TYPE_DICTIONARY,"tracking":TYPE_DICTIONARY,"boosts":TYPE_ARRAY},
		"extraction":{"pd":TYPE_DICTIONARY,"ir":TYPE_DICTIONARY}}
	for domain in shapes:
		var entries: Dictionary = value.get(domain,{})
		for field in shapes[domain]:
			if entries.has(field) and typeof(entries[field]) != shapes[domain][field]:
				return false
	if value.has("factory"):
		if not value["factory"] is Array or value["factory"].size() != 5:
			return false
		for line in value["factory"]:
			if not line is Dictionary or not line.get("queue",[]) is Array or not line.get("active",{}) is Dictionary or not line.get("pending",{}) is Dictionary:
				return false
	for domain in value.get("bonuses", {}).values():
		if not domain is Dictionary:
			return false
		for amount in domain.values():
			if not (typeof(amount) in [TYPE_INT, TYPE_FLOAT]) or not is_finite(float(amount)):
				return false
	for reservation in value.get("reservations", {}).values():
		if not reservation is Dictionary:
			return false
		for amount in reservation.values():
			if not _unsigned_number(amount) or float(amount) != floorf(float(amount)):
				return false
	return true

static func _unsigned_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0

static func sync_events(p: Dictionary) -> void:
	var g := game(p)
	var stats: Dictionary = g["stats"]
	var sold := 0.0
	var batches := 0.0
	for key in stats.keys():
		if str(key).begins_with("sold:"):
			sold += float(stats[key])
		if str(key).begins_with("produced:") and str(key) != "produced:iron_ore":
			batches += float(stats[key])
	var aliases := {"sold":sold, "production_batch_completed":batches,
		"workers_hired":stats.get("purchases:worker",0), "upgrade_purchased":stats.get("purchases:upgrade",0),
		"geology_completed":stats.get("geology_reports",0), "contract_fulfilled":stats.get("contracts_claimed",0)}
	var progression: Dictionary = g.get("progression", {})
	var ranks := 0.0
	for rank in progression.get("research", {}).values():
		ranks += float(rank)
	aliases["research_purchased"] = ranks
	aliases["pd_optional_scan_completed"] = stats.get("pd_samples_analyzed",0)
	var campaign: Dictionary = g.get("extraction",{}).get("ir",{}).get("campaign",{})
	if str(campaign.get("strategy_id","")) == "reliable" and float(stats.get("ir_campaigns_started",0)) > 0:
		aliases["ir_route_selected"] = 1
	var buildings: Dictionary = progression.get("buildings", {})
	var completed := 0.0
	for id in buildings:
		if str(buildings[id].get("status", "")) == "complete":
			completed += 1.0
			if str(id) in ["safe_repair", "safe_repairs", "repair"]:
				aliases["safe_repairs"] = 1
	aliases["season_project_completed"] = completed
	if _building_spec_cache.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/proposals/progression.json"))
		if parsed is Dictionary:
			_building_spec_cache = parsed.get("buildings",{})
	var building_bonuses: Dictionary = {}
	for id in buildings:
		if str(buildings[id].get("status","")) != "complete":
			continue
		for key in _building_spec_cache.get(id,{}).get("bonuses",{}):
			building_bonuses[key] = float(building_bonuses.get(key,0)) + float(_building_spec_cache[id]["bonuses"][key])
	g["bonuses"]["buildings"] = building_bonuses
	var deliveries := float(stats.get("contracts_claimed", 0))
	for order in progression.get("contracts", {}).get("active", {}).values():
		if str(order.get("status", "")) == "shipped":
			deliveries += 1.0
	aliases["material_delivered"] = deliveries
	for key in aliases:
		stats[key] = maxf(float(stats.get(key,0)), float(aliases[key]))
