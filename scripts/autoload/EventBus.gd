extends Node

# All world events flow through here. Any system can listen without knowing
# about the others — this keeps factions, villages, and creatures decoupled.

signal world_event(text: String, severity: int)  # severity: 0=info, 1=warning, 2=danger

signal raid_started(faction_name: String, target_village: String)
signal raid_ended(faction_name: String, target_village: String, loot: Dictionary)
signal dragon_attack_started(dragon_name: String, target_village: String)
signal dragon_fed(dragon_name: String, target_village: String, livestock_lost: int)
signal village_crisis(village_name: String, crisis_type: String)
signal faction_grew(faction_name: String, new_population: int)
signal livestock_attacked(village_name: String, count_lost: int)
signal player_interacted(entity_name: String, info: String)

func log_info(text: String) -> void:
	world_event.emit(text, 0)

func log_warning(text: String) -> void:
	world_event.emit(text, 1)

func log_danger(text: String) -> void:
	world_event.emit(text, 2)
