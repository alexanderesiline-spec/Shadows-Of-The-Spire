extends CanvasModulate

# Tints the whole world (not the HUD — it lives on its own CanvasLayer) to sell
# the passage of time. Samples an ordered gradient of colour stops keyed to the
# fractional time of day from GameClock and lerps smoothly between them.

# (time_fraction, colour) stops, ascending. Midnight is duplicated at 0.0 and 1.0
# so the wrap from night back to night is seamless.
const STOPS := [
	[0.00, Color(0.22, 0.26, 0.45)],  # midnight — deep blue
	[0.22, Color(0.28, 0.30, 0.48)],  # pre-dawn
	[0.27, Color(0.95, 0.72, 0.60)],  # dawn — warm
	[0.38, Color(1.00, 1.00, 1.00)],  # full morning light
	[0.62, Color(1.00, 1.00, 1.00)],  # afternoon
	[0.72, Color(0.98, 0.66, 0.45)],  # dusk — orange
	[0.83, Color(0.55, 0.42, 0.50)],  # twilight
	[0.90, Color(0.40, 0.34, 0.46)],  # nightfall
	[1.00, Color(0.22, 0.26, 0.45)],  # midnight again
]

func _process(_delta: float) -> void:
	color = _sample(GameClock.time_fraction())

func _sample(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	for i in range(STOPS.size() - 1):
		var a: Array = STOPS[i]
		var b: Array = STOPS[i + 1]
		if t >= a[0] and t <= b[0]:
			var span: float = b[0] - a[0]
			var local: float = 0.0 if span <= 0.0 else (t - a[0]) / span
			return (a[1] as Color).lerp(b[1] as Color, local)
	return STOPS[STOPS.size() - 1][1]
