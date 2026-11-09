class_name GameMath
extends RefCounted

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
	return SITE_IDS.has(id) and bool(p.get("sites", {}).get(SITE_IDS[id], {}).get("unlocked", false))

static func registry() -> Node:
	return Engine.get_main_loop().root.get_node("ContentRegistry")

static func records(catalog: String) -> Array:
	return registry().get_records(StringName(catalog))

static func record(catalog: String, id: String) -> Dictionary:
	return registry().get_record(StringName(catalog), id)

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
