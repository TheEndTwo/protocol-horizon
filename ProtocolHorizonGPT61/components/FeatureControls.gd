class_name FeatureControls
extends RefCounted

static func render(screen: Control, parent: VBoxContainer, catalog: String) -> void:
	var p: Dictionary = screen.call("profile")
	var owned: Dictionary = GameMath.game(p).get("progression",{}).get(catalog,{})
	var model = GameSession.model("features")
	for raw_id in owned:
		var id := str(raw_id)
		if int(owned[id]) <= 0:
			continue
		for operation in model.operations(p,id):
			var card: VBoxContainer = screen.call("card",parent,str(operation.get("title",id)),str(operation.get("description","")))
			var inputs: Dictionary = {}
			for field in operation.get("fields",[]):
				var key := str(field.get("key",""))
				HorizonUI.label(card,str(field.get("label",key)),13)
				match str(field.get("type","number")):
					"number":
						var input := SpinBox.new()
						input.min_value = float(field.get("min",0))
						input.max_value = float(field.get("max",100))
						input.step = float(field.get("step",1))
						input.value = float(field.get("value",input.min_value))
						input.custom_minimum_size.y = 44
						card.add_child(input)
						inputs[key] = input
					"select":
						var input := OptionButton.new()
						input.name = "FeatureInput" + id + key
						input.custom_minimum_size.y = 44
						for choice in field.get("choices",[]):
							var value: Variant = choice.get("value",choice.get("id"))
							input.add_item(str(choice.get("label",value)))
							input.set_item_metadata(input.item_count-1,value)
							if field.has("value") and field["value"] == value:
								input.select(input.item_count-1)
						card.add_child(input)
						inputs[key] = input
					"toggle":
						var input := CheckButton.new()
						input.name = "FeatureInput" + id + key
						input.custom_minimum_size.y = 44
						input.button_pressed = bool(field.get("value",false))
						card.add_child(input)
						inputs[key] = input
			var command := str(operation.get("action",""))
			var base: Dictionary = operation.get("args",{}).duplicate(true)
			base["id"] = id
			var button := HorizonUI.button(card,str(operation.get("button","Применить")),"Feature"+id+command,func():
				var args := base.duplicate(true)
				for key in inputs:
					var input: Control = inputs[key]
					if input is SpinBox:
						args[key] = int(input.value)
					elif input is OptionButton and input.selected >= 0:
						args[key] = input.get_item_metadata(input.selected)
					elif input is CheckButton:
						args[key] = input.button_pressed
				screen.call("action","features",command,args))
			var reason := str(operation.get("reason",""))
			button.disabled = not reason.is_empty()
			if not reason.is_empty():
				HorizonUI.notice(card,reason)
