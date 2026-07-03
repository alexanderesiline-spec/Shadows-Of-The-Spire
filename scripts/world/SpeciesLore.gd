extends Node

# Shared species/faction lore math — used by both NPC-to-NPC relationships
# (NPC._seed_affinity) and NPC-to-player trust (NPC.seed_trust_for_player),
# instead of two parallel copies of the same table. Pure functions only; no
# state.

# Inter-species relationship seeds, straight from the world's lore — grievance
# pairs start cooler, alliance pairs start warmer. Keyed by species pair sorted
# alphabetically and joined with "|" so lookup doesn't care about call order.
const SPECIES_RELATIONS := {
	"bear-kin|bird-kin": 15.0,   # alliance — shared highland territories
	"bird-kin|cat-kin": -15.0,   # grievance — old predator/prey tension
	"bear-kin|wolf-kin": -15.0,  # grievance — territorial competition
	"cat-kin|wolf-kin": 5.0,     # civil tolerance
	"demon|elf": -30.0,          # full historical warfare
}
const SAME_FACTION_TRUST_BONUS := 10.0
const FOX_KIN_UNIVERSAL_BONUS := 10.0    # considered lucky by every species
const LIZARD_KIN_MEDIATOR_BONUS := 5.0   # neutral, trusted by every species
const DEMON_UNIVERSAL_PENALTY := -15.0   # unliked by every non-demon species

static func species_pair_key(a: String, b: String) -> String:
	return (a + "|" + b) if a <= b else (b + "|" + a)

# Just the species-vs-species component (grievance/alliance/universal terms),
# with no faction consideration — the player has no faction of their own yet,
# so this is what NPC.seed_trust_for_player uses.
static func species_delta(species_a: String, species_b: String) -> float:
	var delta := 0.0
	if species_a != species_b:
		var key := species_pair_key(species_a, species_b)
		if SPECIES_RELATIONS.has(key):
			delta += SPECIES_RELATIONS[key]
	if species_a == "fox-kin" or species_b == "fox-kin":
		delta += FOX_KIN_UNIVERSAL_BONUS
	if species_a == "lizard-kin" or species_b == "lizard-kin":
		delta += LIZARD_KIN_MEDIATOR_BONUS
	if (species_a == "demon") != (species_b == "demon"):
		delta += DEMON_UNIVERSAL_PENALTY
	return delta

# Full NPC-to-NPC starting affinity: neutral 50 + faction match bonus +
# species_delta.
static func seed_affinity(species_a: String, faction_a: int, species_b: String, faction_b: int) -> float:
	var base := 50.0
	if faction_a == faction_b:
		base += SAME_FACTION_TRUST_BONUS
	base += species_delta(species_a, species_b)
	return clampf(base, 0.0, 100.0)
