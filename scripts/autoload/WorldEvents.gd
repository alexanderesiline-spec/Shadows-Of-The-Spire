extends Node

# Generalizes conditionality up from individual NPCs (already handled by each
# NPC's own utility AI) to the world/faction level. Holds small event-
# definition objects, each polled once a day; an event only ever fires when
# its own condition_met() reads true against real world state — nothing here
# is hard-scripted to a calendar date or a bare probability alone.

var _events: Array = []

func _ready() -> void:
	GameClock.day_passed.connect(_on_day_passed)
	_events.append(ImperialMusterEvent.new())

func _on_day_passed(_day: int, _season: String) -> void:
	for event in _events:
		event.tick_day()
