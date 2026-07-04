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

func show_module(state: Dictionary, data, stages: Dictionary = {}, active_run: Dictionary = {}) -> void:
	visible = true
	title_label.text = data.display_name
	var efficiency = int(round(float(state.get("efficiency", 1.0)) * 100.0))
	detail_label.text = "Status: %s\nWorkers: %d\nEfficiency: %d%%\n%s" % [
		state.get("status", "idle"),
		data.worker_need,
		efficiency,
		data.description_short,
	]
	run_label.text = ""
	for child in stage_box.get_children():
		child.queue_free()
	if data.external_interface:
		if active_run.has("id"):
			run_label.text = "Exploring: %s\nRemaining: %ds" % [
				active_run.get("display_name", "Outside"),
				ceili(float(active_run.get("remaining", 0.0))),
			]
		else:
			run_label.text = "Entrance ready"
			for stage_id in stages.keys():
				var stage = stages[stage_id]
				var button = Button.new()
				button.text = "%s  %ds  %d workers" % [stage.display_name, int(stage.duration), stage.worker_required]
				button.pressed.connect(func() -> void: external_stage_selected.emit(stage.id))
				stage_box.add_child(button)

func hide_popup() -> void:
	visible = false
