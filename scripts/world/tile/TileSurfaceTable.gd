extends Node

# Surface name -> atlas placement. Generation code (ChunkGenerator, BiomeMap
# tile-picking) only ever refers to a surface by NAME — never a raw atlas
# coordinate — so swapping in the real 1280x1280 atlas later only means
# editing BASE_SURFACES/VARIANT_SURFACES here, nothing downstream.
#
# The real atlas is a 4x4 grid = 16 physical cells, but the requested surface
# list has more than 16 distinct names. Resolved as the plan flags: 16 base
# surfaces get their own atlas cell, and the rest are TINTED VARIANTS that
# reuse a base cell's source art via a distinct alternative-tile id + a
# modulate color (e.g. "dark grass" = the grass cell, tinted darker). This is
# a real constraint on the final atlas — surfaces sharing a base cell will
# only ever differ by tint, not by unique art, until dedicated tiles exist.
#
# (Implemented as a plain script with const tables rather than a hand-authored
# .tres — a Resource .tres with nested Vector2i/Color dictionaries is fragile
# to write by hand outside the editor; this is equally data-driven.)

# name -> {atlas_coord: Vector2i, fallback_color: Color}
# fallback_color is what placeholder (no-real-atlas) mode paints directly.
const BASE_SURFACES := {
	"grass":      {"atlas_coord": Vector2i(0, 0), "fallback_color": Color("4a7c3f")},
	"dirt":       {"atlas_coord": Vector2i(1, 0), "fallback_color": Color("6b4a2f")},
	"sand":       {"atlas_coord": Vector2i(2, 0), "fallback_color": Color("d9c17a")},
	"water":      {"atlas_coord": Vector2i(3, 0), "fallback_color": Color("2f6b8f")},
	"stone":      {"atlas_coord": Vector2i(0, 1), "fallback_color": Color("7d7d7d")},
	"wood":       {"atlas_coord": Vector2i(1, 1), "fallback_color": Color("5c3a21")},
	"rocky":      {"atlas_coord": Vector2i(2, 1), "fallback_color": Color("8a8378")},
	"lava":       {"atlas_coord": Vector2i(3, 1), "fallback_color": Color("c23b22")},
	"ice":        {"atlas_coord": Vector2i(0, 2), "fallback_color": Color("cfeaf5")},
	"flowers":    {"atlas_coord": Vector2i(1, 2), "fallback_color": Color("8fc45a")},
	"deep_water": {"atlas_coord": Vector2i(2, 2), "fallback_color": Color("1d3f57")},
	"snow":       {"atlas_coord": Vector2i(3, 2), "fallback_color": Color("f2f8fb")},
	"swamp":      {"atlas_coord": Vector2i(0, 3), "fallback_color": Color("4a5c3f")},
	"ash":        {"atlas_coord": Vector2i(1, 3), "fallback_color": Color("4a4440")},
	"clay":       {"atlas_coord": Vector2i(2, 3), "fallback_color": Color("a9714f")},
	"mossy_rock": {"atlas_coord": Vector2i(3, 3), "fallback_color": Color("55684a")},
}

# name -> {base: String, alt_id: int, tint: Color}
# Reuses a BASE_SURFACES cell's art, recolored. alt_id must be unique per base.
const VARIANT_SURFACES := {
	"dark grass": {"base": "grass", "alt_id": 1, "tint": Color(0.62, 0.72, 0.60)},
	"dry dirt":   {"base": "dirt",  "alt_id": 1, "tint": Color(1.12, 1.02, 0.82)},
	"moss":       {"base": "grass", "alt_id": 2, "tint": Color(0.55, 0.78, 0.58)},
	"wetland":    {"base": "swamp", "alt_id": 1, "tint": Color(0.85, 0.92, 0.80)},
}

static func is_variant(name: String) -> bool:
	return VARIANT_SURFACES.has(name)

static func base_name_for(name: String) -> String:
	if VARIANT_SURFACES.has(name):
		return VARIANT_SURFACES[name]["base"]
	return name

static func atlas_coord_for(name: String) -> Vector2i:
	var base := base_name_for(name)
	return BASE_SURFACES.get(base, BASE_SURFACES["grass"])["atlas_coord"]

static func alt_id_for(name: String) -> int:
	if VARIANT_SURFACES.has(name):
		return VARIANT_SURFACES[name]["alt_id"]
	return 0

static func tint_for(name: String) -> Color:
	if VARIANT_SURFACES.has(name):
		return VARIANT_SURFACES[name]["tint"]
	return Color.WHITE

static func fallback_color_for(name: String) -> Color:
	var base := base_name_for(name)
	var c: Color = BASE_SURFACES.get(base, BASE_SURFACES["grass"])["fallback_color"]
	if VARIANT_SURFACES.has(name):
		return c * VARIANT_SURFACES[name]["tint"]
	return c

static func all_names() -> Array:
	var names: Array = BASE_SURFACES.keys()
	names.append_array(VARIANT_SURFACES.keys())
	return names
