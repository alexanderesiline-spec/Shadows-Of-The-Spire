extends Node

# 1 real second = 1 in-game hour. Adjustable at runtime (HUD +/- keys).
var SECONDS_PER_HOUR: float = 1.0
const HOURS_PER_DAY: int = 24
const DAYS_PER_SEASON: int = 7
const SEASONS: Array[String] = ["Spring", "Summer", "Autumn", "Winter"]

var hour: int = 6
var day: int = 1
var season_index: int = 0
var year: int = 1

signal hour_passed(hour: int)
signal day_passed(day: int, season: String)
signal season_changed(season: String)

var _elapsed: float = 0.0

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= SECONDS_PER_HOUR:
		_elapsed -= SECONDS_PER_HOUR
		_advance_hour()

func _advance_hour() -> void:
	hour += 1
	if hour >= HOURS_PER_DAY:
		hour = 0
		_advance_day()
	hour_passed.emit(hour)

func _advance_day() -> void:
	day += 1
	if day > DAYS_PER_SEASON:
		day = 1
		_advance_season()
	day_passed.emit(day, get_season())

func _advance_season() -> void:
	season_index = (season_index + 1) % SEASONS.size()
	if season_index == 0:
		year += 1
	season_changed.emit(get_season())

func get_season() -> String:
	return SEASONS[season_index]

func is_night() -> bool:
	return hour < 6 or hour >= 20

# Coarse phase used by NPC schedules — readable buckets instead of raw hours.
func get_day_phase() -> String:
	if hour >= 5 and hour < 8:
		return "Dawn"
	elif hour >= 8 and hour < 12:
		return "Morning"
	elif hour >= 12 and hour < 17:
		return "Day"
	elif hour >= 17 and hour < 20:
		return "Dusk"
	else:
		return "Night"

func get_time_string() -> String:
	var period = "Night" if is_night() else ("Dawn" if hour < 9 else ("Dusk" if hour >= 17 else "Day"))
	return "Day %d  |  %02d:00  |  %s  |  %s  |  Year %d" % [
		day, hour, get_season(), period, year
	]
