class_name GameSession
extends RefCounted

## Context object that holds the state and simulation instances for a single active game.

var time: TimeManager
var farm: FarmData
var entities: EntityManager

var is_new_game: bool = true

func _init() -> void:
    time = TimeManager.new()
    farm = FarmData.new()
    entities = EntityManager.new()

    # Wire up intra-session dependencies
    time.minute_passed.connect(entities._on_minute_passed)
    time.minute_passed.connect(farm._on_minute_passed)
    farm._last_processed_minute = time.get_total_minutes()

func process_tick(delta: float) -> void:
    # Tick down exactly what needs to update in the session
    time.tick(delta) # Or define a custom tick method
    entities.tick(delta)
    farm.tick(delta)
