extends PanelContainer

@onready var tool_label: Label = %ToolLabel

func _ready() -> void:
	if EventBus != null:
		EventBus.player_tool_equipped.connect(_on_player_tool_equipped)

func _on_player_tool_equipped(tool_name: String) -> void:
	if tool_name.is_empty():
		tool_label.text = "Equipped: None"
	else:
		tool_label.text = "Equipped: " + tool_name
