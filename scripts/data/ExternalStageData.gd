extends Resource
class_name ExternalStageData

@export var id: String = ""
@export var display_name: String = ""
@export var duration: float = 20.0
@export var worker_required: int = 2
@export var food_cost: int = 4
@export_range(0.0, 1.0) var danger: float = 0.15
@export var base_food_reward: Vector2i = Vector2i(8, 16)
@export var base_soil_reward: Vector2i = Vector2i.ZERO
var card_reward_pool: Array[String] = []
var connectors: Dictionary = {}
var tags: Array[String] = []

static func make(
	p_id: String,
	p_name: String,
	p_duration: float,
	p_workers: int,
	p_food_cost: int,
	p_danger: float,
	p_food_reward: Vector2i,
	p_soil_reward: Vector2i,
	p_cards: Array,
	p_tags: Array = []
):
	var data = load("res://scripts/data/ExternalStageData.gd").new()
	data.id = p_id
	data.display_name = p_name
	data.duration = p_duration
	data.worker_required = p_workers
	data.food_cost = p_food_cost
	data.danger = p_danger
	data.base_food_reward = p_food_reward
	data.base_soil_reward = p_soil_reward
	data.card_reward_pool.clear()
	for card_id in p_cards:
		data.card_reward_pool.append(String(card_id))
	data.tags.clear()
	for tag in p_tags:
		data.tags.append(String(tag))
	return data
