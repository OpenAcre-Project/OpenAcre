extends Node

# These signals act as alarms. Other scripts will "listen" for them.
signal minute_passed
signal hour_passed
signal day_passed
signal time_changed(previous_total_minutes: int, current_total_minutes: int, used_discrete_steps: bool)

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

func get_total_minutes() -> int:
	return ((current_day - 1) * 24 * 60) + (current_hour * 60) + current_minute

func set_time(day: int, hour: int, minute: int, emit_boundary_signals: bool = false) -> void:
	var normalized_day := maxi(1, day)
	var normalized_hour := clampi(hour, 0, 23)
	var normalized_minute := clampi(minute, 0, 59)
	var target_total := ((normalized_day - 1) * 24 * 60) + (normalized_hour * 60) + normalized_minute
	set_total_minutes(target_total, emit_boundary_signals)

func set_total_minutes(total_minutes: int, emit_boundary_signals: bool = false) -> void:
	var clamped_total := maxi(0, total_minutes)
	var previous_total := get_total_minutes()

	if clamped_total == previous_total:
		return

	var new_day := int(floor(float(clamped_total) / 1440.0)) + 1
	var minute_of_day := clamped_total % 1440
	var new_hour := int(floor(float(minute_of_day) / 60.0))
	var new_minute := minute_of_day % 60

	current_day = new_day
	current_hour = new_hour
	current_minute = new_minute
	_internal_timer = 0.0

	if emit_boundary_signals:
		var previous_day := int(floor(float(previous_total) / 1440.0)) + 1
		var previous_hour_of_day := int(floor(float(previous_total % 1440) / 60.0))
		if current_day != previous_day:
			emit_signal("day_passed")
		if current_hour != previous_hour_of_day:
			emit_signal("hour_passed")

	emit_signal("time_changed", previous_total, clamped_total, false)

func fast_forward_minutes(minutes: int, emit_minute_signals: bool = false) -> Dictionary:
	if minutes <= 0:
		return {
			"advanced_minutes": 0,
			"previous_total_minutes": get_total_minutes(),
			"current_total_minutes": get_total_minutes(),
			"used_discrete_steps": emit_minute_signals
		}

	var previous_total := get_total_minutes()
	if emit_minute_signals:
		for _i in range(minutes):
			_advance_minute()
		emit_signal("time_changed", previous_total, get_total_minutes(), true)
	else:
		set_total_minutes(previous_total + minutes, false)

	return {
		"advanced_minutes": minutes,
		"previous_total_minutes": previous_total,
		"current_total_minutes": get_total_minutes(),
		"used_discrete_steps": emit_minute_signals
	}

func fast_forward_seconds(seconds: int, emit_minute_signals: bool = false) -> Dictionary:
	if seconds <= 0:
		return {
			"advanced_minutes": 0,
			"previous_total_minutes": get_total_minutes(),
			"current_total_minutes": get_total_minutes(),
			"used_discrete_steps": emit_minute_signals
		}

	var minutes := int(floor(float(seconds) / 60.0))
	return fast_forward_minutes(minutes, emit_minute_signals)
