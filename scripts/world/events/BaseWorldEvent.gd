extends RefCounted
class_name BaseWorldEvent

# A world/faction-level conditional event. WorldEvents polls every registered
# event daily: if condition_met() is true and the event isn't on cooldown,
# fire() runs and cooldown_days resets. Concrete events never get invoked on
# a timer or a bare dice roll alone — condition_met() must read real world
# state (WorldSimulation aggregates, faction stats, ...), so "this fires
# because of what's happening in the world" stays true by construction.

var cooldown_days: int = 1
var cooldown_remaining: int = 0

func condition_met() -> bool:
	return false

func fire() -> void:
	pass

func tick_day() -> void:
	if cooldown_remaining > 0:
		cooldown_remaining -= 1
		return
	if condition_met():
		fire()
		cooldown_remaining = cooldown_days
