extends Node

# Transient holding pen between the debug race picker and Main.tscn's Player.
# RacePicker fills this in, then scene-swaps to Main.tscn; Player._ready()
# reads it once and applies it.

const PlayerStatsScript = preload("res://scripts/entities/PlayerStats.gd")
const RaceData = preload("res://scripts/entities/RaceData.gd")

var chosen_race: String = "Human"
var stats: RefCounted = null   # a PlayerStats instance

func finalize(race_name: String, allocations: Dictionary) -> void:
	chosen_race = race_name
	stats = PlayerStatsScript.new()
	stats.apply_race_mods(RaceData.stat_mods(race_name))
	for stat_name in allocations:
		stats.allocate(stat_name, allocations[stat_name])
	stats.lock_in()

func get_stats() -> RefCounted:
	if stats == null:
		# Fallback for skipping the picker entirely (e.g. quick iteration) —
		# a plain Human with no allocation, still fully functional.
		finalize("Human", {})
	return stats
