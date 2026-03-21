extends Node

## The single Autoload that holds the active GameSession

var session: GameSession = null

func _enter_tree() -> void:
    # Ensure there is always a session available immediately when the game boots
    if session == null:
        start_new_game()

func _process(delta: float) -> void:
    if session != null:
        session.process_tick(delta)

func start_new_game() -> void:
    session = GameSession.new()

func end_game() -> void:
    session = null
