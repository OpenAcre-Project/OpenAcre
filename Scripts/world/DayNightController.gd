class_name DayNightController
extends Node3D

@export var sun_light: DirectionalLight3D
@export var environment: WorldEnvironment
@export var sun_color_gradient: Gradient
@export var sun_intensity_curve: Curve

var target_day_progress: float = 0.5
var current_day_progress: float = 0.5
# Day progress goes from 0.0 to 1.0 (midnight to midnight)

func _ready() -> void:
	if not sun_color_gradient:
		sun_color_gradient = Gradient.new()
		sun_color_gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
		sun_color_gradient.set_color(0, Color("0b0e14")) # Replace default point 1
		sun_color_gradient.set_offset(0, 0.0)
		sun_color_gradient.set_color(1, Color("0b0e14")) # Replace default point 2
		sun_color_gradient.set_offset(1, 1.0)
		sun_color_gradient.add_point(0.20, Color("1e2c45"))
		sun_color_gradient.add_point(0.25, Color("ff7b00"))
		sun_color_gradient.add_point(0.30, Color("ffe4b5"))
		sun_color_gradient.add_point(0.50, Color("ffffff"))
		sun_color_gradient.add_point(0.70, Color("ffe4b5"))
		sun_color_gradient.add_point(0.75, Color("ff4500"))
		sun_color_gradient.add_point(0.80, Color("1e2c45"))

	if not sun_intensity_curve:
		sun_intensity_curve = Curve.new()
		sun_intensity_curve.add_point(Vector2(0.0, 0.05))
		sun_intensity_curve.add_point(Vector2(0.2, 0.1))
		sun_intensity_curve.add_point(Vector2(0.25, 0.8))
		sun_intensity_curve.add_point(Vector2(0.3, 1.2))
		sun_intensity_curve.add_point(Vector2(0.5, 1.5))
		sun_intensity_curve.add_point(Vector2(0.7, 1.2))
		sun_intensity_curve.add_point(Vector2(0.75, 0.8))
		sun_intensity_curve.add_point(Vector2(0.8, 0.1))
		sun_intensity_curve.add_point(Vector2(1.0, 0.05))

	# Connect to TimeManager signals
	if GameManager.session.time.has_signal("time_changed"):
		GameManager.session.time.time_changed.connect(_on_time_changed)
	if GameManager.session.time.has_signal("minute_passed"):
		GameManager.session.time.minute_passed.connect(_update_target_progress)
	
	# Initial fetch
	_update_target_progress()
	# Set current immediately so we don't lerp on startup
	current_day_progress = target_day_progress
	_apply_time_visuals(current_day_progress)

func _process(delta: float) -> void:
	# Smoothly lerp towards target progress.
	var smoothing := 2.0
	
	# Handle wrap-around gracefully (e.g., crossing midnight from 0.99 to 0.0)
	var diff: float = target_day_progress - current_day_progress
	if diff > 0.5:
		current_day_progress += 1.0
	elif diff < -0.5:
		current_day_progress -= 1.0
		
	current_day_progress = lerp(current_day_progress, target_day_progress, minf(1.0, delta * smoothing))
	
	# Wrap back to 0-1 range for sampling and visualization
	var sample_progress := wrapf(current_day_progress, 0.0, 1.0)
	
	_apply_time_visuals(sample_progress)

func _update_target_progress() -> void:
	target_day_progress = (GameManager.session.time.current_hour * 60.0 + GameManager.session.time.current_minute) / 1440.0

func _on_time_changed(_prev_total: int, _curr_total: int, _discrete: bool) -> void:
	_update_target_progress()

func _apply_time_visuals(progress: float) -> void:
	if sun_light:
		# Map progress to rotation
		# 0.0 (midnight) -> 90 deg X (straight up)
		# 0.5 (noon)     -> -90 deg X (straight down)
		# 1.0 (midnight) -> -270 deg X (straight up again)
		var angle_deg: float = lerp(90.0, -270.0, progress)
		sun_light.rotation_degrees.x = angle_deg
		
		# Optional: Add a slight offset on Y so it isn't an exact east-to-west over the equator
		# sun_light.rotation_degrees.y = 45.0
		
		if sun_intensity_curve:
			sun_light.light_energy = sun_intensity_curve.sample(progress)
			
		if sun_color_gradient:
			sun_light.light_color = sun_color_gradient.sample(progress)
