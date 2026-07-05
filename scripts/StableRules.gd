extends RefCounted
class_name StableRules

const PRESSURE_ORDER: Array[String] = [
	"throughput_pressure",
	"worker_pressure",
	"capacity_pressure",
	"food_pressure",
	"soil_pressure",
	"expansion_pressure",
]

static func stable_roll(seed_text: String) -> float:
	var hash_value := 2166136261
	for i in range(seed_text.length()):
		hash_value = int((hash_value ^ seed_text.unicode_at(i)) * 16777619) & 0x7fffffff
	return float(hash_value % 1000) / 999.0

static func highest_pressure_key(city_pressure: Dictionary) -> String:
	var best_key := PRESSURE_ORDER[0]
	var best_value := -1.0
	for key in PRESSURE_ORDER:
		var value := float(city_pressure.get(key, 0.0))
		if value > best_value:
			best_value = value
			best_key = key
	return best_key

static func tag_matches_pressure(tag: String, pressure_key: String) -> bool:
	return (
		(tag == "food" and pressure_key == "food_pressure")
		or (tag == "soil" and pressure_key == "soil_pressure")
		or (tag == "workers" and pressure_key == "worker_pressure")
		or (tag == "storage" and pressure_key == "capacity_pressure")
		or (tag == "throughput" and pressure_key == "throughput_pressure")
		or (tag == "expansion" and pressure_key == "expansion_pressure")
	)

static func pressure_reason(pressure_key: String) -> String:
	match pressure_key:
		"food_pressure":
			return "Relieves food pressure"
		"soil_pressure":
			return "Relieves soil pressure"
		"worker_pressure":
			return "Relieves worker pressure"
		"capacity_pressure":
			return "Relieves storage pressure"
		"throughput_pressure":
			return "Relieves tunnel bottlenecks"
		"expansion_pressure":
			return "Opens more build space"
	return "Relieves current nest pressure"

static func support_priority_for_pressure(pressure_key: String) -> Array[String]:
	match pressure_key:
		"capacity_pressure":
			return ["storage_chamber", "overflow_silo", "sorter", "nursery"]
		"worker_pressure":
			return ["nursery", "shift_roost", "storage_chamber", "sorter"]
		"throughput_pressure":
			return ["sorter", "relay_junction", "storage_chamber", "overflow_silo", "nursery"]
		"soil_pressure":
			return ["digging_room", "relay_junction", "storage_chamber", "sorter"]
		"food_pressure":
			return ["fungus_farm", "overflow_silo", "storage_chamber", "nursery"]
	return ["storage_chamber", "overflow_silo", "nursery", "shift_roost", "sorter", "relay_junction"]
