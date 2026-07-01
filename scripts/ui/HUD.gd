extends CanvasLayer

const MAX_LOG_ENTRIES: int = 12
const COLOR_INFO    := Color(0.85, 0.85, 0.85)
const COLOR_WARNING := Color(1.0, 0.75, 0.2)
const COLOR_DANGER  := Color(1.0, 0.35, 0.35)

var _time_label: Label
var _player_stats: Label
var _log_container: VBoxContainer
var _scroll: ScrollContainer
var _status_panel: PanelContainer
var _status_content: VBoxContainer
var _status_visible: bool = false

func _ready() -> void:
	_build_ui()
	EventBus.world_event.connect(_on_world_event)
	EventBus.village_crisis.connect(func(v, c): _add_log("[!] %s crisis in %s" % [c, v], COLOR_DANGER))
	EventBus.faction_grew.connect(func(f, p): _add_log("[+] %s now %d strong" % [f, p], COLOR_WARNING))
	EventBus.livestock_attacked.connect(func(v, n): _add_log("[~] %s lost %d livestock" % [v, n], COLOR_WARNING))

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ── Time bar (top center) ──────────────────────────────────────────────
	var time_bg := PanelContainer.new()
	time_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	time_bg.offset_bottom = 32
	root.add_child(time_bg)

	_time_label = Label.new()
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", 14)
	time_bg.add_child(_time_label)

	# ── Player stats (top-right) ───────────────────────────────────────────
	var player_bg := PanelContainer.new()
	player_bg.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	player_bg.offset_left = -310
	player_bg.offset_bottom = 68
	root.add_child(player_bg)

	var pvbox := VBoxContainer.new()
	player_bg.add_child(pvbox)

	var player_title := Label.new()
	player_title.text = "— Player —"
	player_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_title.add_theme_font_size_override("font_size", 12)
	pvbox.add_child(player_title)

	_player_stats = Label.new()
	_player_stats.add_theme_font_size_override("font_size", 11)
	pvbox.add_child(_player_stats)

	# ── Event log (bottom-left) ────────────────────────────────────────────
	var log_bg := PanelContainer.new()
	log_bg.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_bg.offset_top = -230
	log_bg.offset_right = 560
	log_bg.offset_bottom = 0
	root.add_child(log_bg)

	var log_vbox := VBoxContainer.new()
	log_bg.add_child(log_vbox)

	var log_title := Label.new()
	log_title.text = "— World Events —"
	log_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	log_title.add_theme_font_size_override("font_size", 12)
	log_vbox.add_child(log_title)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(530, 175)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_vbox.add_child(_scroll)

	_log_container = VBoxContainer.new()
	_log_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_log_container)

	# ── Controls hint (bottom-right) ──────────────────────────────────────
	var hint_bg := PanelContainer.new()
	hint_bg.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint_bg.offset_left = -220
	hint_bg.offset_top = -95
	root.add_child(hint_bg)

	var hint := Label.new()
	hint.text = "WASD / Arrows — Move\nE — Inspect nearby\nTab — World status"
	hint.add_theme_font_size_override("font_size", 11)
	hint_bg.add_child(hint)

	# ── World Status panel (Tab toggle, center) ────────────────────────────
	_status_panel = PanelContainer.new()
	_status_panel.set_anchors_preset(Control.PRESET_CENTER)
	_status_panel.offset_left = -320
	_status_panel.offset_top = -260
	_status_panel.offset_right = 320
	_status_panel.offset_bottom = 260
	_status_panel.visible = false
	root.add_child(_status_panel)

	var status_vbox := VBoxContainer.new()
	_status_panel.add_child(status_vbox)

	var status_title := Label.new()
	status_title.text = "═══ WORLD STATUS ═══"
	status_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_title.add_theme_font_size_override("font_size", 14)
	status_vbox.add_child(status_title)

	_status_content = VBoxContainer.new()
	status_vbox.add_child(_status_content)

	var close_hint := Label.new()
	close_hint.text = "[Tab] to close"
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_hint.add_theme_font_size_override("font_size", 11)
	close_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	status_vbox.add_child(close_hint)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("status_panel"):
		_status_visible = not _status_visible
		_status_panel.visible = _status_visible
		if _status_visible:
			_refresh_status_panel()

func _process(_delta: float) -> void:
	_time_label.text = GameClock.get_time_string()
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_player_stats.text = player.get_status()

func _refresh_status_panel() -> void:
	for child in _status_content.get_children():
		child.queue_free()

	_add_status_section("VILLAGES")
	for v in WorldSimulation.villages:
		if is_instance_valid(v):
			_add_status_line(v.get_status_short(), Color(0.5, 1.0, 0.5))

	_add_status_section("FACTIONS")
	for f in WorldSimulation.factions:
		if is_instance_valid(f):
			_add_status_line(f.get_status_short(), Color(1.0, 0.55, 0.3))

	_add_status_section("DRAGONS")
	for d in WorldSimulation.dragons:
		if is_instance_valid(d):
			_add_status_line(d.get_status_short(), Color(0.8, 0.5, 1.0))

func _add_status_section(title: String) -> void:
	var l := Label.new()
	l.text = "  %s:" % title
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_status_content.add_child(l)

func _add_status_line(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = "    " + text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_content.add_child(l)

func _on_world_event(text: String, severity: int) -> void:
	var color: Color
	match severity:
		1: color = COLOR_WARNING
		2: color = COLOR_DANGER
		_: color = COLOR_INFO
	_add_log(text, color)

func _add_log(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	_log_container.add_child(label)

	while _log_container.get_child_count() > MAX_LOG_ENTRIES:
		_log_container.get_child(0).queue_free()

	_scroll.call_deferred("set_v_scroll", 999999)
