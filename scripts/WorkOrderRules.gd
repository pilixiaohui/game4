extends RefCounted
class_name WorkOrderRules

const BALANCED := "balanced"
const FOOD_CREW := "food_crew"
const SOIL_CREW := "soil_crew"
const TUNNEL_CREW := "tunnel_crew"

const ORDER_IDS: Array[String] = [
	BALANCED,
	FOOD_CREW,
	SOIL_CREW,
	TUNNEL_CREW,
]

static func is_valid(order_id: String) -> bool:
	return ORDER_IDS.has(order_id)

static func label(order_id: String) -> String:
	match order_id:
		FOOD_CREW:
			return "Feed fungus first"
		SOIL_CREW:
			return "Dig soil first"
		TUNNEL_CREW:
			return "Clear tunnel loads"
	return "Balanced crews"

static func transport_bonus(order_id: String) -> int:
	return 1 if order_id == TUNNEL_CREW else 0

static func production_multiplier(order_id: String, output_rates: Dictionary) -> float:
	match order_id:
		FOOD_CREW:
			if output_rates.has("food"):
				return 1.2
			if output_rates.has("soil"):
				return 0.9
		SOIL_CREW:
			if output_rates.has("soil"):
				return 1.2
			if output_rates.has("food"):
				return 0.9
		TUNNEL_CREW:
			if not output_rates.is_empty():
				return 0.95
	return 1.0
