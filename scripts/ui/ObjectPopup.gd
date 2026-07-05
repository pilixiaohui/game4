extends PanelContainer
class_name ObjectPopup

signal external_stage_selected(stage_id: String)

var title_label: Label
var detail_label: Label
var run_label: Label
var stage_box: VBoxContainer

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(260, 180)
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

func show_module(state: Dictionary, data, stages: Dictionary = {}, active_run: Dictionary = {}, stage_previews: Dictionary = {}) -> void:
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
			run_label.text = "Exploring: %s\nRemaining: %ds\nCity impact: %d workers outside, production load %d%%\nChance locked: %d%%  Risk: %d%%" % [
				active_run.get("display_name", "Outside"),
				ceili(float(active_run.get("remaining", 0.0))),
				int(active_run.get("worker_required", 0)),
				int(round((1.0 - float(state.get("worker_effect", 1.0))) * 100.0)),
				int(round(float(active_run.get("success_chance", 0.0)) * 100.0)),
				int(round(float(active_run.get("risk", 0.0)) * 100.0)),
			]
		else:
			run_label.text = "Entrance ready"
			for stage_id in stages.keys():
				var stage = stages[stage_id]
				var button = Button.new()
				var preview: Dictionary = stage_previews.get(stage_id, {})
				button.text = "%s  %ds  %d workers  %d%% chance  %d%% risk" % [
					stage.display_name,
					int(stage.duration),
					stage.worker_required,
					int(round(float(preview.get("success_chance", 0.0)) * 100.0)),
					int(round(float(stage.risk) * 100.0)),
				]
				button.pressed.connect(func() -> void: external_stage_selected.emit(stage.id))
				stage_box.add_child(button)

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
