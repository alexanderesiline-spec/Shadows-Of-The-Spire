extends RefCounted
class_name PlayerStats

# Two-layer stat model, locked by design: base_stats (5 in each + race mods +
# the 10-point creation allocation) are frozen the moment character creation
# completes and can NEVER be raised again except through equipment_bonus
# (always zero today — no item system exists yet, but the shape already
# supports gear slotting in later without restructuring anything here).

const STAT_NAMES := ["strength", "agility", "intelligence", "magic_affinity",
	"vitality", "endurance", "stealth", "luck"]

const BASE_VALUE := 5
const CREATION_POINTS := 10

var base_stats: Dictionary = {}
var equipment_bonus: Dictionary = {}
var _locked: bool = false

func _init() -> void:
	for s in STAT_NAMES:
		base_stats[s] = BASE_VALUE
		equipment_bonus[s] = 0

# Applies a race's flat modifiers on top of the base 5s. Must happen before
# lock_in() — this is still "character creation," not post-game growth.
func apply_race_mods(mods: Dictionary) -> void:
	if _locked:
		return
	for stat in mods:
		if base_stats.has(stat):
			base_stats[stat] += mods[stat]

# Spends from the 10-point creation pool. Any race can allocate into any stat,
# including Luck — no exclusivity gate; Fox-kin's bonus is purely additive on
# top of whatever the player also chooses to allocate.
func allocate(stat: String, amount: int) -> bool:
	if _locked or not base_stats.has(stat):
		return false
	base_stats[stat] += amount
	return true

func lock_in() -> void:
	_locked = true

func total(stat: String) -> int:
	return base_stats.get(stat, BASE_VALUE) + equipment_bonus.get(stat, 0)

# ── Derived gameplay hooks ───────────────────────────────────────────────────

func speed_multiplier() -> float:
	return 1.0 + (total("agility") - BASE_VALUE) * 0.04

# Scales NPC._player_threat()'s wariness radius/intensity — higher Stealth
# means NPCs notice the player less readily.
func detection_multiplier() -> float:
	return clampf(1.0 - (total("stealth") - BASE_VALUE) * 0.06, 0.2, 2.0)

func mana_multiplier() -> float:
	return 1.0 + (total("magic_affinity") - BASE_VALUE) * 0.05
