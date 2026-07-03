extends Node

# Global, runtime-toggleable dev switches. dev_mode gates BuildMode's free
# placement/terrain editing/manual save — everything else in the project
# should treat this as read-only and check it, never set it directly except
# through toggle_dev_mode() so the change gets logged.

var dev_mode: bool = false

func toggle_dev_mode() -> void:
	dev_mode = not dev_mode
	EventBus.log_warning("Dev mode %s." % ("enabled" if dev_mode else "disabled"))
