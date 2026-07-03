extends BaseWorldEvent
class_name ImperialMusterEvent

# Replaces the old hidden "25% chance of a patrol surge" dice roll with a real
# conditional definition: the empire musters more guards specifically because
# bandits have been active recently — not on a bare timer. This closes an
# emergent feedback loop already implicit in the systems: raids -> muster ->
# higher patrol_level -> bandits favor "lying low" -> raids taper off ->
# WorldSimulation.recent_raid_count decays -> muster stops firing.

func _init() -> void:
	cooldown_days = 4

func condition_met() -> bool:
	return WorldSimulation.recent_raid_count > 0

func fire() -> void:
	WorldSimulation.patrol_level += 0.8 + randf() * 0.6
	WorldSimulation.recent_raid_count = 0
	EventBus.log_warning("Word of recent raids reaches the garrison — the town crawls with extra guards.")
