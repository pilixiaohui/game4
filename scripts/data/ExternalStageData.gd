extends Resource
class_name ExternalStageData

@export var id: String = ""
@export var display_name: String = ""
@export var duration: float = 20.0
@export var worker_required: int = 2
@export var food_cost: int = 4
@export_range(0.0, 1.0) var danger: float = 0.15
@export_range(0.0, 1.0) var success_base: float = 0.65
@export_range(0.0, 1.0) var risk: float = 0.15
@export_range(0.0, 1.0) var partial_resource_ratio: float = 0.55
@export_range(0.0, 1.0) var failure_resource_ratio: float = 0.3
@export var base_food_reward: Vector2i = Vector2i(8, 16)
@export var base_soil_reward: Vector2i = Vector2i.ZERO
var card_reward_pool: Array[String] = []
var connectors: Dictionary = {}
var tags: Array[String] = []
var reward_weights: Dictionary = {}
var pressure_weight_bonus: Dictionary = {}

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
	p_tags: Array = [],
	p_success_base: float = -1.0,
	p_risk: float = -1.0,
	p_reward_weights: Dictionary = {},
	p_pressure_weight_bonus: Dictionary = {},
	p_partial_resource_ratio: float = 0.55,
	p_failure_resource_ratio: float = 0.3
):
	var data = load("res://scripts/data/ExternalStageData.gd").new()
	data.id = p_id
	data.display_name = p_name
	data.duration = p_duration
	data.worker_required = p_workers
	data.food_cost = p_food_cost
	data.danger = p_danger
	data.success_base = p_danger if p_success_base < 0.0 else p_success_base
	data.risk = p_danger if p_risk < 0.0 else p_risk
	data.base_food_reward = p_food_reward
	data.base_soil_reward = p_soil_reward
	data.card_reward_pool.clear()
	for card_id in p_cards:
		data.card_reward_pool.append(String(card_id))
	data.tags.clear()
	for tag in p_tags:
		data.tags.append(String(tag))
	data.reward_weights = p_reward_weights.duplicate(true)
	data.pressure_weight_bonus = p_pressure_weight_bonus.duplicate(true)
	data.partial_resource_ratio = clampf(p_partial_resource_ratio, 0.0, 1.0)
	data.failure_resource_ratio = clampf(p_failure_resource_ratio, 0.0, 1.0)
	return data
