extends Node

# System Signals
@warning_ignore("unused_signal")
signal log_message(text: String, level: int)

# UI Signals
@warning_ignore("unused_signal")
signal show_notification(msg: String)
@warning_ignore("unused_signal")
signal update_crosshair_prompt(text: String)
@warning_ignore("unused_signal")
signal update_vehicle_hints(show: bool, hints: Array[String])

# Entity Streaming Signals
@warning_ignore("unused_signal")
signal entity_view_released(entity_id: StringName)

# Game Flow Signals
@warning_ignore("unused_signal")
signal save_game_requested
@warning_ignore("unused_signal")
signal pre_save_flush
@warning_ignore("unused_signal")
signal load_game_requested
@warning_ignore("unused_signal")
signal game_loaded_successfully

# Player Signals
@warning_ignore("unused_signal")
signal player_tool_equipped(tool_name: String)
@warning_ignore("unused_signal")
signal player_stats_changed(health: float, stamina: float)
