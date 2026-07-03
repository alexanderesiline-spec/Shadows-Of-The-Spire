extends Control

# Touch movement feeds the SAME InputMap actions keyboard/gamepad already use
# (Input.action_press("ui_right", strength) etc.), so Player.gd's
# Input.get_axis("ui_left", "ui_right") picks it up transparently through the
# identical codepath — no branching for touch anywhere in Player.gd.

const BASE_RADIUS := 60.0
const KNOB_RADIUS := 28.0

var _touch_index: int = -1
var _knob_offset: Vector2 = Vector2.ZERO
var _base_center: Vector2 = Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = Vector2(BASE_RADIUS, BASE_RADIUS) * 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_base_center = event.position
			_update_knob(event.position)
		elif not event.pressed and event.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update_knob(event.position)

func _update_knob(pos: Vector2) -> void:
	var offset := pos - _base_center
	if offset.length() > BASE_RADIUS:
		offset = offset.normalized() * BASE_RADIUS
	_knob_offset = offset
	queue_redraw()

	var normalized := offset / BASE_RADIUS   # -1..1 per axis
	Input.action_press("ui_right", maxf(normalized.x, 0.0))
	Input.action_press("ui_left", maxf(-normalized.x, 0.0))
	Input.action_press("ui_down", maxf(normalized.y, 0.0))
	Input.action_press("ui_up", maxf(-normalized.y, 0.0))

func _release() -> void:
	_touch_index = -1
	_knob_offset = Vector2.ZERO
	queue_redraw()
	Input.action_release("ui_right")
	Input.action_release("ui_left")
	Input.action_release("ui_down")
	Input.action_release("ui_up")

func _draw() -> void:
	var center := size / 2.0
	draw_circle(center, BASE_RADIUS, Color(1, 1, 1, 0.15))
	draw_circle(center + _knob_offset, KNOB_RADIUS, Color(1, 1, 1, 0.35))
