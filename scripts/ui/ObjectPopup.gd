extends PanelContainer
class_name ObjectPopup

signal external_stage_selected(stage_id: String)

var title_label: Label
var detail_label: Label
var run_label: Label
var stage_box: VBoxContainer

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(360, 240)
	var root = VBoxContainer.new()
	add_child(root)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 18)
	root.add_child(title_label)
	detail_label = Label.new()
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(detail_label)
	run_label = Label.new()
	run_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(run_label)
	stage_box = VBoxContainer.new()
	root.add_child(stage_box)

func show_module(state: Dictionary, data, stages: Dictionary = {}, active_run: Dictionary = {}, stage_previews: Dictionary = {}, city_status: Dictionary = {}) -> void:
	visible = true
	title_label.text = data.display_name
	var efficiency = int(round(float(state.get("efficiency", 1.0)) * 100.0))
	var pending := _format_resource_dict(state.get("pending_output", {}))
	var delivered := _format_resource_dict(state.get("delivered_this_tick", {}))
	var blocker := _blocker_text(String(state.get("last_blocker", "none")))
	detail_label.text = "Status: %s\n%s\nWorkers: %d\nEfficiency: %d%%\nPending: %s\nDelivered now: %s\n%s" % [
		state.get("status", "idle"),
		blocker,
		data.worker_need,
		efficiency,
		pending,
		delivered,
		data.description_short,
	]
	run_label.text = ""
	for child in stage_box.get_children():
		child.queue_free()
	if data.external_interface:
		if active_run.has("id"):
			var impact: Dictionary = city_status.get("production_impact", {})
			run_label.text = "Exploring: %s\nRemaining: %ds\nCity impact: %d workers outside; worker satisfaction %d%%\nProduction: %d%% avg, %d/%d constrained (%s)\nChance locked: %d%%  Risk: %d%%" % [
				active_run.get("display_name", "Outside"),
				ceili(float(active_run.get("remaining", 0.0))),
				int(impact.get("workers_exploring", active_run.get("worker_required", 0))),
				int(round(float(impact.get("worker_satisfaction", 1.0)) * 100.0)),
				int(round(float(impact.get("average_efficiency", 1.0)) * 100.0)),
				int(impact.get("constrained_count", 0)),
				int(impact.get("production_count", 0)),
				_blocker_text(String(impact.get("worst_blocker", "none"))).replace("Blocker: ", ""),
				int(round(float(active_run.get("success_chance", 0.0)) * 100.0)),
				int(round(float(active_run.get("risk", 0.0)) * 100.0)),
			]
		else:
			run_label.text = "Entrance ready"
			for stage_id in stages.keys():
				var stage = stages[stage_id]
				var preview: Dictionary = stage_previews.get(stage_id, {})
				var entry = VBoxContainer.new()
				entry.add_theme_constant_override("separation", 4)
				var summary = Label.new()
				summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				summary.text = "%s\n%d sec, %d workers, %d food\nChance %d%%, risk %d%%\nMods: %s\nRewards: %s" % [
					stage.display_name,
					int(stage.duration),
					stage.worker_required,
					stage.food_cost,
					int(round(float(preview.get("success_chance", 0.0)) * 100.0)),
					int(round(float(stage.risk) * 100.0)),
					_format_modifiers(Dictionary(preview.get("modifiers", {}))),
					_format_reward_tendency(stage),
				]
				entry.add_child(summary)
				var button = Button.new()
				button.text = "Explore"
				button.custom_minimum_size = Vector2(0, 34)
				button.pressed.connect(func() -> void: external_stage_selected.emit(stage.id))
				entry.add_child(button)
				stage_box.add_child(entry)

func hide_popup() -> void:
	visible = false

func _format_resource_dict(value) -> String:
	if typeof(value) != TYPE_DICTIONARY or value.is_empty():
		return "-"
	var parts: Array[String] = []
	for key in value.keys():
		var amount := int(value[key])
		if amount > 0:
			parts.append("%d %s" % [amount, String(key)])
	if parts.is_empty():
		return "-"
	return ", ".join(parts)

func _blocker_text(blocker: String) -> String:
	match blocker:
		"no_workers":
			return "Blocker: workers stretched thin"
		"bottleneck":
			return "Blocker: tunnel bottleneck"
		"storage_full":
			return "Blocker: storage full, output wasted"
		"disconnected":
			return "Blocker: no connected route"
		"none":
			return "Blocker: none"
	return "Blocker: %s" % blocker

func _format_modifiers(modifiers: Dictionary) -> String:
	if modifiers.is_empty():
		return "none"
	var parts: Array[String] = []
	for key in modifiers.keys():
		var value := float(modifiers[key])
		if absf(value) < 0.005:
			continue
		var sign := "+" if value >= 0.0 else ""
		parts.append("%s%s%d%%" % [String(key).replace("_", " "), sign, int(round(value * 100.0))])
	if parts.is_empty():
		return "none"
	return "; ".join(parts)

func _format_reward_tendency(stage) -> String:
	var tags: Array[String] = []
	for tag in stage.tags:
		tags.append(String(tag))
	for key in stage.reward_weights.keys():
		if not tags.has(String(key)):
			tags.append(String(key))
	return ", ".join(tags)
