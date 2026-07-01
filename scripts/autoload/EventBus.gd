extends Node

# All world events flow through here. Any system can listen without knowing
# about the others — this keeps NPCs, places, and UI decoupled.

signal world_event(text: String, severity: int)  # severity: 0=info, 1=warning, 2=danger

# Emitted when an individual NPC does something worth surfacing in the log
# (woke early to farm, slept in hungover, went raiding, laid low, went hungry).
signal npc_notable(npc_name: String, text: String, severity: int)

# Emitted when the player inspects someone/something.
signal player_interacted(entity_name: String, info: String)

func log_info(text: String) -> void:
	world_event.emit(text, 0)

func log_warning(text: String) -> void:
	world_event.emit(text, 1)

func log_danger(text: String) -> void:
	world_event.emit(text, 2)

# Convenience: log an NPC moment to both the notable channel and the world log.
func notable(npc_name: String, text: String, severity: int = 0) -> void:
	npc_notable.emit(npc_name, text, severity)
	world_event.emit(text, severity)
