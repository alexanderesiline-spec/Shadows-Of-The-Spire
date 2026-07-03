extends Node

# The 9 locked races as a static data table rather than 9 hand-authored .tres
# Resource files — a Resource with nested Dictionary export values is fragile
# to write correctly by hand outside a live editor; this is equally
# data-driven and just as easy to convert to real .tres files later if wanted.
#
# stat_mods use PlayerStats.STAT_NAMES keys. trust_mod is the race's general
# "how trustworthy does this race read to others" modifier (distinct from
# SpeciesLore's specific pairwise relations — both apply, see
# NPC.seed_trust_for_player). Luck is allocatable by any race at creation
# (no exclusivity gate) — Fox-kin's +3 is on top of that, per the locked
# clarification superseding an earlier "+2 Luck +1 INT" draft.

const ChunkGeneratorScript = preload("res://scripts/world/chunk/ChunkGenerator.gd")

# Demon's isolated starting island — far from the default town chunk (~31,31)
# so the two never overlap. A small forced-land chunk ringed by forced ocean,
# guaranteeing the "isolated island" regardless of what the biome map/noise
# naturally generates there.
const DEMON_ISLAND_CHUNK := Vector2i(10, 10)

const RACES := {
	"Human": {
		"stat_mods": {}, "trust_mod": 0.0,
	},
	"Bear-kin": {
		"stat_mods": {"strength": 3, "endurance": 2}, "trust_mod": -1.0,
	},
	"Wolf-kin": {
		"stat_mods": {"agility": 2, "stealth": 2}, "trust_mod": -1.0,
	},
	"Cat-kin": {
		"stat_mods": {"stealth": 3, "agility": 1}, "trust_mod": -1.0,
	},
	"Fox-kin": {
		"stat_mods": {"luck": 3, "intelligence": 1}, "trust_mod": 1.0,
	},
	"Bird-kin": {
		"stat_mods": {"agility": 3, "stealth": 1}, "trust_mod": -1.0,
	},
	"Lizard-kin": {
		"stat_mods": {
			"strength": 1, "agility": 1, "intelligence": 1, "magic_affinity": 1,
			"vitality": 1, "endurance": 1, "stealth": 1, "luck": 1,
		},
		"trust_mod": 1.0,
	},
	"Elf": {
		"stat_mods": {"magic_affinity": 3, "intelligence": 2}, "trust_mod": -2.0,
	},
	"Demon": {
		"stat_mods": {"strength": 5, "magic_affinity": 5, "intelligence": 3, "vitality": -4},
		"trust_mod": -5.0,
		"spawn_chunk": DEMON_ISLAND_CHUNK,
	},
}

const RACE_ORDER := ["Human", "Bear-kin", "Wolf-kin", "Cat-kin", "Fox-kin",
	"Bird-kin", "Lizard-kin", "Elf", "Demon"]

static func get_race(race_name: String) -> Dictionary:
	return RACES.get(race_name, RACES["Human"])

static func stat_mods(race_name: String) -> Dictionary:
	return get_race(race_name).get("stat_mods", {})

static func trust_mod(race_name: String) -> float:
	return get_race(race_name).get("trust_mod", 0.0)

# Species string used for SpeciesLore/relationship seeding — lowercase,
# matches the convention NPC.gd already uses ("wolf-kin", "fox-kin", ...).
static func species_string(race_name: String) -> String:
	return race_name.to_lower()

static func has_spawn_override(race_name: String) -> bool:
	return get_race(race_name).has("spawn_chunk")

# Tile-unit spawn position for races with a fixed starting location (only
# Demon today). Also guarantees the terrain there regardless of biome/noise.
static func spawn_tile_pos(race_name: String) -> Vector2:
	var race := get_race(race_name)
	if not race.has("spawn_chunk"):
		return Vector2.ZERO
	var chunk: Vector2i = race["spawn_chunk"]
	var chunk_size := 32   # matches TileConfig.CHUNK_SIZE_TILES; avoids a load-order dependency
	_force_isolated_island(chunk)
	return Vector2(chunk.x * chunk_size + chunk_size / 2.0, chunk.y * chunk_size + chunk_size / 2.0)

static func _force_isolated_island(center: Vector2i) -> void:
	# Center + immediate ring forced to land, next ring out forced to ocean —
	# small guaranteed island no matter what the biome map says there.
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			ChunkGeneratorScript.force_clear(Vector2i(center.x + dx, center.y + dy), "sand")
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			if maxi(absi(dx), absi(dy)) <= 1:
				continue
			ChunkGeneratorScript.force_clear(Vector2i(center.x + dx, center.y + dy), "deep_water")
