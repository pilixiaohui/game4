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
var connectors: Dictionary = _blank_connectors()
var tags: Array[String] = []
var input_rates: Dictionary = {}
var output_rates: Dictionary = {}
var storage: Dictionary = {}
var adjacency_rules: Dictionary = {}

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
	p_tags: Array[String] = [],
	p_rarity: String = "common",
	p_description: String = ""
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
	data.tags = p_tags.duplicate()
	data.rarity = p_rarity
	data.description_short = p_description
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
