extends Control

# Minimal, functional (not final) character creation: pick one of the 9
# races, spend the 10-point pool across the 8 stats (any stat, no exclusivity
# gate — Fox-kin's own bonus stacks on top of whatever's allocated), confirm
# to hand off to CharacterSetup and scene-swap into Main.tscn.

const RaceData = preload("res://scripts/entities/RaceData.gd")
const PlayerStatsScript = preload("res://scripts/entities/PlayerStats.gd")

var _selected_race: String = "Human"
var _allocations: Dictionary = {}
var _points_remaining: int = PlayerStatsScript.CREATION_POINTS

var _race_buttons: Dictionary = {}
var _stat_value_labels: Dictionary = {}
var _points_label: Label
var _preview_label: Label

func _ready() -> void:
	for s in PlayerStatsScript.STAT_NAMES:
		_allocations[s] = 0
	_build_ui()
	_refresh()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 14)
	margin.add_child(root_vbox)

	var title := Label.new()
	title.text = "Choose your kind"
	title.add_theme_font_size_override("font_size", 22)
	root_vbox.add_child(title)

	# Race selection row.
	var race_row := HFlowContainer.new()
	race_row.add_theme_constant_override("h_separation", 8)
	root_vbox.add_child(race_row)
	for race_name in RaceData.RACE_ORDER:
		var btn := Button.new()
		btn.text = race_name
		btn.toggle_mode = true
		btn.button_pressed = (race_name == _selected_race)
		btn.pressed.connect(_on_race_selected.bind(race_name))
		race_row.add_child(btn)
		_race_buttons[race_name] = btn

	_preview_label = Label.new()
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_vbox.add_child(_preview_label)

	root_vbox.add_child(HSeparator.new())

	# Stat allocation rows.
	var stats_label := Label.new()
	stats_label.text = "Allocate 10 points (any stat, no cap):"
	root_vbox.add_child(stats_label)

	for stat_name in PlayerStatsScript.STAT_NAMES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		root_vbox.add_child(row)

		var name_label := Label.new()
		name_label.text = stat_name.capitalize()
		name_label.custom_minimum_size = Vector2(140, 0)
		row.add_child(name_label)

		var minus := Button.new()
		minus.text = "-"
		minus.pressed.connect(_on_stat_delta.bind(stat_name, -1))
		row.add_child(minus)

		var value_label := Label.new()
		value_label.custom_minimum_size = Vector2(30, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(value_label)
		_stat_value_labels[stat_name] = value_label

		var plus := Button.new()
		plus.text = "+"
		plus.pressed.connect(_on_stat_delta.bind(stat_name, 1))
		row.add_child(plus)

	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 14)
	root_vbox.add_child(_points_label)

	var confirm := Button.new()
	confirm.text = "Begin"
	confirm.pressed.connect(_on_confirm)
	root_vbox.add_child(confirm)

func _on_race_selected(race_name: String) -> void:
	_selected_race = race_name
	for name_key in _race_buttons:
		_race_buttons[name_key].button_pressed = (name_key == race_name)
	_refresh()

func _on_stat_delta(stat_name: String, delta: int) -> void:
	var current: int = _allocations[stat_name]
	if delta > 0 and _points_remaining <= 0:
		return
	if delta < 0 and current <= 0:
		return
	_allocations[stat_name] = current + delta
	_points_remaining -= delta
	_refresh()

func _refresh() -> void:
	var mods := RaceData.stat_mods(_selected_race)
	var mod_strs: Array = []
	for stat_name in mods:
		mod_strs.append("+%d %s" % [mods[stat_name], stat_name.capitalize()])
	var trust := RaceData.trust_mod(_selected_race)
	_preview_label.text = "%s — %s (Trust %+.0f)" % [
		_selected_race,
		(", ".join(mod_strs) if not mod_strs.is_empty() else "no innate stat bonuses"),
		trust,
	]

	for stat_name in PlayerStatsScript.STAT_NAMES:
		var base := PlayerStatsScript.BASE_VALUE + mods.get(stat_name, 0) + _allocations[stat_name]
		_stat_value_labels[stat_name].text = str(base)

	_points_label.text = "Points remaining: %d" % _points_remaining

func _on_confirm() -> void:
	CharacterSetup.finalize(_selected_race, _allocations)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
