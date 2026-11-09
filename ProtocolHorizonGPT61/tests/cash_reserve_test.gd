extends SceneTree

var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

func _run() -> void:
	var p: Dictionary = root.get_node("GameState").make_new_profile()
	p["money_cents"] = 1000
	GameMath.game(p)["research_runtime"] = {"cash_reserves":{"P09":200,"P14":100,"PD24":400}}
	check(GameMath.available_money(p) == 300,"Unrelated purchases can spend reserved cash")
	check(GameMath.available_money(p,"payroll") == 600,"Payroll cannot use its own reserve")
	check(GameMath.available_money(p,"pd_chemical") == 700,"Chemical queue cannot use its own reserve")
	check(not GameMath.pay(p,301),"Unrelated purchase consumed a protected cent")
	check(p["money_cents"] == 1000,"Failed payment changed ledger")
	check(GameMath.pay(p,450,"payroll"),"Payroll payment failed despite a real reserve")
	check(p["money_cents"] == 550,"Payroll debited wrong cash amount")
	check(p["game"]["research_runtime"]["cash_reserves"]["P09"] == 50,"Payroll did not consume only needed P09 reserve")
	check(p["game"]["research_runtime"]["cash_reserves"]["PD24"] == 400,"Payroll stole chemical money")
	check(not GameMath.pay(p,1),"No free cash should remain")
	check(GameMath.pay(p,300,"pd_chemical"),"Real chemical reserve was inaccessible")
	check(p["money_cents"] == 250 and p["game"]["research_runtime"]["cash_reserves"]["PD24"] == 100,"Chemical reserve accounting changed total cash incorrectly")
	check(GameMath.available_money(p) == 0 and GameMath.available_money(p,"payroll") == 150,"Reserve remainder is wrong")
	check(GameMath.pay(p,150,"payroll"),"Remaining paid shift cannot consume its reserve")
	check(GameMath.available_money(p,"payroll") == 0 and p["money_cents"] == 100,"Payroll spent another purpose's reserve")
	check(not GameMath.pay(p,-1),"Negative payment created money")
	if failures.is_empty():
		print("CASH RESERVE PASS: purpose isolation, no money creation, exact reserve consumption, failed-payment rollback")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: "+failure)
		quit(1)
