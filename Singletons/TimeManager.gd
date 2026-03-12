extends Node

# These signals act as alarms. Other scripts will "listen" for them.
signal minute_passed
signal hour_passed
signal day_passed

# Time Settings
@export var time_multiplier: float = 60.0 # 1 real second = 60 in-game seconds
var current_minute: int = 0
var current_hour: int = 6 # Game starts at 6:00 AM
var current_day: int = 1

var _internal_timer: float = 0.0

func _process(delta: float) -> void:
	# Delta is the fraction of a second since the last frame.
	_internal_timer += delta * time_multiplier
	
	# Once our internal timer hits 60 (1 in-game minute)
	if _internal_timer >= 60.0:
		_internal_timer -= 60.0
		_advance_minute()

func _advance_minute() -> void:
	current_minute += 1
	emit_signal("minute_passed")
	
	if current_minute >= 60:
		current_minute = 0
		_advance_hour()

func _advance_hour() -> void:
	current_hour += 1
	emit_signal("hour_passed")
	
	if current_hour >= 24:
		current_hour = 0
		_advance_day()

func _advance_day() -> void:
	current_day += 1
	emit_signal("day_passed")
