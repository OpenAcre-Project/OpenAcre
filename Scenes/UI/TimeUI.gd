extends PanelContainer

@onready var time_label: Label = %TimeLabel

func _ready() -> void:
	if GameManager.session != null and GameManager.session.time != null:
		var tm: TimeManager = GameManager.session.time
		if tm.has_signal("minute_passed"):
			tm.minute_passed.connect(_update_time)
		if tm.has_signal("time_changed"):
			tm.time_changed.connect(_on_time_changed_args)
		_update_time()

func _on_time_changed_args(_a: int, _b: int, _c: bool) -> void:
	_update_time()

func _update_time() -> void:
	if GameManager.session != null and GameManager.session.time != null:
		var tm: TimeManager = GameManager.session.time
		time_label.text = "Day %d - %02d:%02d" % [tm.current_day, tm.current_hour, tm.current_minute]
