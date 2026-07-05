extends PanelContainer
class_name ObjectPopup

signal external_stage_selected(stage_id: String)

var title_label: Label
var detail_label: Label
var run_label: Label
var stage_scroll: ScrollContainer
var stage_box: VBoxContainer

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(404, 420)
	var root = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	stage_scroll = ScrollContainer.new()
	stage_scroll.name = "StageScroll"
	stage_scroll.custom_minimum_size = Vector2(0, 190)
	stage_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(stage_scroll)
	stage_box = VBoxContainer.new()
	stage_box.name = "StageBox"
	stage_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_scroll.add_child(stage_box)

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
			run_label.text = "%s\nReturn in %ds\n%s\n%s\nOutlook locked: %s  Risk: %s" % [
				active_run.get("display_name", "Outside"),
				ceili(float(active_run.get("remaining", 0.0))),
				_worker_draw_text(impact, int(active_run.get("worker_required", 0))),
				_production_drag_text(impact),
				_outlook_text(float(active_run.get("success_chance", 0.0))),
				_risk_text(float(active_run.get("risk", 0.0))),
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
				summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				summary.text = "%s\n%s, %d workers, %d food\nOutlook: %s   Risk: %s\nWhat helps: %s\nLikely finds: %s" % [
					stage.display_name,
					_duration_text(float(stage.duration)),
					stage.worker_required,
					stage.food_cost,
					_outlook_text(float(preview.get("success_chance", 0.0))),
					_risk_text(float(stage.risk)),
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
		if value > 0.0:
			parts.append(_modifier_label(String(key), true))
		else:
			parts.append(_modifier_label(String(key), false))
	if parts.is_empty():
		return "none"
	return "; ".join(parts)

func _format_reward_tendency(stage) -> String:
	var tags: Array[String] = []
	for tag in stage.tags:
		tags.append(_tag_label(String(tag)))
	for key in stage.reward_weights.keys():
		var label := _tag_label(String(key))
		if not tags.has(label):
			tags.append(label)
	return ", ".join(tags)

func _outlook_text(chance: float) -> String:
	if chance >= 0.72:
		return "promising"
	if chance >= 0.55:
		return "uncertain"
	if chance >= 0.35:
		return "dangerous"
	return "desperate"

func _risk_text(risk: float) -> String:
	if risk < 0.16:
		return "low"
	if risk < 0.28:
		return "medium"
	return "high"

func _duration_text(seconds: float) -> String:
	var minutes := int(floor(seconds / 60.0))
	var remain := int(seconds) % 60
	if minutes <= 0:
		return "%ds" % int(seconds)
	return "%dm %02ds" % [minutes, remain]

func _modifier_label(key: String, positive: bool) -> String:
	match key:
		"free_workers":
			return "spare workers help" if positive else "thin worker crew hurts"
		"capacity_room":
			return "empty stores help" if positive else "full stores hurt"
		"connected_entrance":
			return "connected entrance helps" if positive else "entrance trouble hurts"
		"city_pressure":
			return "stable city helps" if positive else "city pressure hurts"
	return String(key).replace("_", " ")

func _tag_label(tag: String) -> String:
	match tag:
		"food":
			return "food"
		"soil":
			return "soil"
		"workers":
			return "worker help"
		"throughput":
			return "tunnel relief"
		"storage":
			return "storage"
		"expansion":
			return "dig space"
		"risk":
			return "rare salvage"
	return tag.replace("_", " ")

func _worker_draw_text(impact: Dictionary, fallback_workers: int) -> String:
	var workers_out := int(impact.get("workers_exploring", fallback_workers))
	var satisfaction := int(round(float(impact.get("worker_satisfaction", 1.0)) * 100.0))
	return "%d workers are outside; city labor is at %d%%." % [workers_out, satisfaction]

func _production_drag_text(impact: Dictionary) -> String:
	var average := int(round(float(impact.get("average_efficiency", 1.0)) * 100.0))
	var constrained := int(impact.get("constrained_count", 0))
	var production := int(impact.get("production_count", 0))
	var blocker := _blocker_text(String(impact.get("worst_blocker", "none"))).replace("Blocker: ", "")
	return "Rooms run at %d%%; %d/%d constrained by %s." % [average, constrained, production, blocker]
