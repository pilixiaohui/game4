extends Resource
class_name ModuleData

const TOP := "top"
const RIGHT := "right"
const BOTTOM := "bottom"
const LEFT := "left"
const DIRECTIONS := [TOP, RIGHT, BOTTOM, LEFT]
const OPPOSITE := {
	TOP: BOTTOM,
	RIGHT: LEFT,
	BOTTOM: TOP,
	LEFT: RIGHT,
}
const DELTAS := {
	TOP: Vector2i(0, -1),
	RIGHT: Vector2i(1, 0),
	BOTTOM: Vector2i(0, 1),
	LEFT: Vector2i(-1, 0),
}

@export var id: String = ""
@export var display_name: String = ""
@export var category: String = ""
@export var size: Vector2i = Vector2i.ONE
@export var build_cost_food: int = 0
@export var build_cost_soil: int = 0
@export var worker_need: int = 0
@export var throughput: int = 1
@export var required_throughput: int = 1
@export var base_cycle_time: float = 10.0
@export var rarity: String = "common"
@export var description_short: String = ""
@export var external_interface: bool = false
@export var transport_output: int = 0
@export var excavation_power: float = 0.0
@export var excavation_interval: float = 1.0
var connectors: Dictionary = _blank_connectors()
var tags: Array[String] = []
var reward_tags: Array[String] = []
var input_rates: Dictionary = {}
var output_rates: Dictionary = {}
var storage: Dictionary = {}
var adjacency_rules: Dictionary = {}
var solves_pressure: Dictionary = {}
var creates_pressure: Dictionary = {}

static func _blank_connectors() -> Dictionary:
	return {TOP: false, RIGHT: false, BOTTOM: false, LEFT: false}

static func make(
	p_id: String,
	p_name: String,
	p_category: String,
	p_size: Vector2i,
	p_connectors: Dictionary,
	p_cost_food: int,
	p_cost_soil: int,
	p_worker_need: int,
	p_output_rates: Dictionary = {},
	p_storage: Dictionary = {},
	p_throughput: int = 1,
	p_cycle_time: float = 10.0,
	p_external_interface: bool = false,
	p_tags: Array = [],
	p_rarity: String = "common",
	p_description: String = "",
	p_reward_tags: Array = [],
	p_solves_pressure: Dictionary = {},
	p_creates_pressure: Dictionary = {},
	p_transport_output: int = -1,
	p_excavation_power: float = 0.0,
	p_excavation_interval: float = 1.0
):
	var data = load("res://scripts/data/ModuleData.gd").new()
	data.id = p_id
	data.display_name = p_name
	data.category = p_category
	data.size = p_size
	data.connectors = _blank_connectors()
	for direction in p_connectors.keys():
		data.connectors[direction] = bool(p_connectors[direction])
	data.build_cost_food = p_cost_food
	data.build_cost_soil = p_cost_soil
	data.worker_need = p_worker_need
	data.output_rates = p_output_rates.duplicate(true)
	data.storage = p_storage.duplicate(true)
	data.throughput = p_throughput
	data.required_throughput = max(1, _rate_total(p_output_rates))
	data.base_cycle_time = p_cycle_time
	data.external_interface = p_external_interface
	data.tags.clear()
	for tag in p_tags:
		data.tags.append(String(tag))
	data.reward_tags.clear()
	for tag in p_reward_tags:
		data.reward_tags.append(String(tag))
	data.rarity = p_rarity
	data.description_short = p_description
	data.solves_pressure = p_solves_pressure.duplicate(true)
	data.creates_pressure = p_creates_pressure.duplicate(true)
	data.transport_output = _rate_total(p_output_rates) if p_transport_output < 0 else p_transport_output
	data.excavation_power = p_excavation_power
	data.excavation_interval = max(0.1, p_excavation_interval)
	return data

static func _rate_total(rates: Dictionary) -> int:
	var total = 0
	for value in rates.values():
		total += int(value)
	return total

func rotated_size(rotation_steps: int) -> Vector2i:
	var steps = posmod(rotation_steps, 4)
	if steps % 2 == 1:
		return Vector2i(size.y, size.x)
	return size

func rotated_connectors(rotation_steps: int) -> Dictionary:
	var rotated = connectors.duplicate(true)
	for i in range(posmod(rotation_steps, 4)):
		rotated = {
			TOP: rotated[LEFT],
			RIGHT: rotated[TOP],
			BOTTOM: rotated[RIGHT],
			LEFT: rotated[BOTTOM],
		}
	return rotated
