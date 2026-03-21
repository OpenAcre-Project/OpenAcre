extends ConsumableItem3D

func _ready() -> void:
	if initial_item_id == &"":
		initial_item_id = &"item.apple"
	if nutrition_value == 0:
		nutrition_value = 150.0 # Standard apple nutrition
	super._ready()
