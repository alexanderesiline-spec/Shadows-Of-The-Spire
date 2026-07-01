extends Node2D

# A location in the world an NPC can travel to and "use" to satisfy a need.
# Places are dumb: they hold a type, a look, and an effect. All decision-making
# lives in the NPC. Effects are applied per-hour while an NPC works/rests here.

enum PlaceType { HOME, FIELD, TAVERN, MARKET, GUARD_POST, CAMP }

@export var place_name: String = "Place"
@export var place_type: PlaceType = PlaceType.HOME

const TYPE_COLORS := {
	PlaceType.HOME:      Color(0.55, 0.45, 0.32),
	PlaceType.FIELD:     Color(0.42, 0.55, 0.20),
	PlaceType.TAVERN:    Color(0.62, 0.38, 0.55),
	PlaceType.MARKET:    Color(0.78, 0.66, 0.28),
	PlaceType.GUARD_POST:Color(0.35, 0.42, 0.62),
	PlaceType.CAMP:      Color(0.50, 0.28, 0.18),
}

const TYPE_LABELS := {
	PlaceType.HOME: "Home",
	PlaceType.FIELD: "Field",
	PlaceType.TAVERN: "Tavern",
	PlaceType.MARKET: "Market",
	PlaceType.GUARD_POST: "Guard Post",
	PlaceType.CAMP: "Camp",
}

func _ready() -> void:
	WorldSimulation.register_place(self)
	_build_visual()

func _exit_tree() -> void:
	WorldSimulation.unregister_place(self)

func _build_visual() -> void:
	var color: Color = TYPE_COLORS.get(place_type, Color.GRAY)

	# Base footprint
	var pad := Polygon2D.new()
	pad.polygon = PackedVector2Array([
		Vector2(-26, 16), Vector2(26, 16), Vector2(26, -16), Vector2(-26, -16)
	])
	pad.color = color.darkened(0.35)
	add_child(pad)

	# Type-specific marker on top
	match place_type:
		PlaceType.HOME, PlaceType.TAVERN, PlaceType.MARKET, PlaceType.GUARD_POST:
			var roof := Polygon2D.new()
			roof.polygon = PackedVector2Array([
				Vector2(-28, -16), Vector2(0, -36), Vector2(28, -16)
			])
			roof.color = color
			add_child(roof)
		PlaceType.FIELD:
			# rows of crops
			for i in range(-2, 3):
				var row := Polygon2D.new()
				row.polygon = PackedVector2Array([
					Vector2(i * 9 - 2, 14), Vector2(i * 9 + 2, 14),
					Vector2(i * 9 + 2, -12), Vector2(i * 9 - 2, -12)
				])
				row.color = color.lightened(0.1 if i % 2 == 0 else -0.1)
				add_child(row)
		PlaceType.CAMP:
			var tent := Polygon2D.new()
			tent.polygon = PackedVector2Array([
				Vector2(-22, 14), Vector2(0, -26), Vector2(22, 14)
			])
			tent.color = color
			add_child(tent)

	var label := Label.new()
	label.text = "%s" % place_name
	label.position = Vector2(-44, 18)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", color.lightened(0.4))
	add_child(label)

func type_label() -> String:
	return TYPE_LABELS.get(place_type, "Place")
