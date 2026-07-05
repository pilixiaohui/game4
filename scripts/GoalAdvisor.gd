extends RefCounted
class_name GoalAdvisor

const StableRulesScript := preload("res://scripts/StableRules.gd")

static func summary(snapshot: Dictionary) -> Dictionary:
	var milestone := _first_session_milestone(snapshot)
	if not milestone.is_empty():
		return milestone
	var city_pressure: Dictionary = snapshot.get("city_pressure", {})
	var key := StableRulesScript.highest_pressure_key(city_pressure)
	var value := float(city_pressure.get(key, 0.0))
	var label := "Keep the nest flowing"
	var action := "Add production, storage, workers, tunnels, or explore when ready."
	var modules: Array = snapshot.get("modules", [])
	match key:
		"food_pressure":
			label = "Food stores are thin"
			action = "Grow food or scout debris before starting a costly build."
		"soil_pressure":
			label = "Soil limits expansion"
			action = "Run digging rooms or scout loose soil for the next chamber."
		"worker_pressure":
			label = "Workers are stretched"
			action = "Choose Nursery or delay exploration until production recovers."
		"capacity_pressure":
			label = "Stores are near full"
			action = "Build Storage before producers waste output."
		"throughput_pressure":
			label = "Tunnels are jammed"
			action = "Add Sorter or corridors near busy production routes."
			if _has_module_id(modules, "sorter"):
				label = "Bottleneck eased, still busy"
				action = "Sorter cut the worst load; add another path or storage for the remaining jam."
		"expansion_pressure":
			label = "The nest needs room"
			action = "Let digging rooms open frontier cells before placing large modules."
	if value <= 0.05:
		label = "Nest is stable"
		action = "Prepare an entrance run or shape the next production wing."
	return _result(key, value, label, action, float(snapshot.get("elapsed_seconds", 0.0)))

static func _first_session_milestone(snapshot: Dictionary) -> Dictionary:
	var modules: Array = snapshot.get("modules", [])
	var hand: Array = snapshot.get("hand", [])
	var module_defs: Dictionary = snapshot.get("module_defs", {})
	var reward_choices: Array = snapshot.get("reward_choices", [])
	var active_external_run: Dictionary = snapshot.get("active_external_run", {})
	var last_external_result: Dictionary = snapshot.get("last_external_result", {})
	var resources: Dictionary = snapshot.get("resources", {})
	var elapsed := float(snapshot.get("elapsed_seconds", 0.0))
	if reward_choices.size() > 0:
		return _result("reward_pending", 1.0, "Pick the next nest organ", "Choose the card that answers the strongest pressure, then keep playing to feel the tradeoff.", elapsed)
	if active_external_run.has("id"):
		return _result("exploration_running", 1.0, "Foragers are outside", "Watch production slow while workers are away; recover when they return.", elapsed)
	if not _has_module_id(modules, "digging_room"):
		return _result("build_soil", 0.8, "Start a soil line", "Connect a Digging Room to open cells and begin soil production.", elapsed)
	if not _has_module_id(modules, "fungus_farm"):
		return _result("build_food", 0.8, "Start a food line", "Connect a Fungus Farm so the entrance has a food budget.", elapsed)
	if not _has_module_id(modules, "surface_entrance"):
		var entrance = module_defs.get("surface_entrance", null)
		if entrance != null:
			var food_gap: int = max(0, int(entrance.build_cost_food) - int(resources.get("food", 0)))
			var soil_gap: int = max(0, int(entrance.build_cost_soil) - int(resources.get("soil", 0)))
			var pressure_key := StableRulesScript.highest_pressure_key(snapshot.get("city_pressure", {}))
			var action := "Need %d food and %d soil. Watch three levers: fungus food, digging soil, and tunnel flow." % [food_gap, soil_gap]
			if food_gap == 0 and soil_gap > 0:
				action = "Food is ready; soil is the next gate. Keep digging rooms connected."
			elif soil_gap == 0 and food_gap > 0:
				action = "Soil is ready; food is the next gate. Keep fungus moving through clear tunnels."
			elif pressure_key == "throughput_pressure":
				action = "Resources are coming, but tunnels are busy. Let pending loads clear or add a turn path if useful."
			elif pressure_key == "food_pressure":
				action = "Food is the slow lever. Keep the Fungus Farm flowing before opening the gate."
			elif pressure_key == "soil_pressure":
				action = "Soil is the slow lever. Keep the Digging Room flowing before opening the gate."
			return _result("stockpile_entrance", 0.75, "Stockpile for the surface gate", action, elapsed)
	if last_external_result.is_empty():
		return _result("start_exploration", 0.65, "Choose the first scouting route", "Compare outlook, risk, worker draw, and likely finds before sending workers out.", elapsed)
	for support_id in ["storage_chamber", "nursery", "sorter"]:
		if hand.has(support_id) and not _has_module_id(modules, support_id):
			var data = module_defs[support_id]
			return _result("install_reward", 0.7, "Install %s" % data.display_name, "%s Watch the pressure meter for the next 3-5 minutes after it connects." % data.description_short, elapsed)
	return {}

static func _result(key: String, value: float, label: String, action: String, elapsed: float) -> Dictionary:
	return {
		"key": key,
		"value": value,
		"label": label,
		"action": action,
		"time": elapsed,
	}

static func _has_module_id(modules: Array, module_id: String) -> bool:
	for module in modules:
		if String(module.get("module_id", "")) == module_id:
			return true
	return false
