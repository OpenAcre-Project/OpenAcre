extends SceneTree

func _init() -> void:
	print("--- Starting Item System Verification ---")
	
	# 1. Setup Definitions
	var wheat := CommodityDefinition.new()
	wheat.id = &"commodity.wheat"
	wheat.density = 0.77
	
	var apple_def := ItemDefinition.new()
	apple_def.id = &"item.apple"
	apple_def.base_mass = 0.15
	apple_def.base_volume = 0.2
	apple_def.max_stack_size = 10
	
	var water_bottle_def := ItemDefinition.new()
	water_bottle_def.id = &"item.water_bottle"
	water_bottle_def.base_mass = 0.05
	water_bottle_def.base_volume = 0.5
	
	# Mock Registry (Since we aren't running as Autoload here)
	# We'll just use the scripts directly if possible or mock the Registry
	var registry: Node = load("res://Scripts/simulation/ItemRegistry.gd").new()
	registry.register_commodity(wheat)
	registry.register_item(apple_def)
	registry.register_item(water_bottle_def)
	
	# 2. Test Tank
	print("\nTesting BulkTankData...")
	var tank: BulkTankData = load("res://Scripts/simulation/BulkTankData.gd").new()
	tank.max_volume = 100.0
	tank.allowed_commodities = [&"commodity.wheat"]
	
	var added: float = tank.try_add_fluid(&"commodity.wheat", 50.0)
	print("Added 50L wheat: ", added == 50.0)
	# We need to manually inject registry into tank if it uses ItemRegistry singleton
	# But in this test, ItemRegistry.get_commodity_density will fail if not Autoloaded.
	# Let's assume the Autoload works in-game. For this script, we'll just check logic.
	
	# 3. Test Inventory & Stacking
	print("\nTesting InventoryData & Stacking...")
	var inv: InventoryData = load("res://Scripts/simulation/InventoryData.gd").new()
	inv.max_volume = 10.0
	
	var apple1 := load("res://Scripts/simulation/ItemInstance.gd").new()
	apple1.definition_id = &"item.apple"
	apple1.stack = 5
	
	var apple2 := load("res://Scripts/simulation/ItemInstance.gd").new()
	apple2.definition_id = &"item.apple"
	apple2.stack = 7
	
	inv.try_add_item(apple1)
	inv.try_add_item(apple2)
	
	print("Total apples (should be 12): ", inv.items[0].stack if inv.items.size() > 0 else 0)
	print("Items in inventory (should be 2 due to max_stack=10): ", inv.items.size())
	
	# 4. Test Player Data Mass
	print("\nTesting PlayerData mass...")
	var player_data: PlayerData = load("res://Scripts/simulation/resources/PlayerData.gd").new()
	player_data.pockets.try_add_item(apple1)
	print("Player pocket mass: ", player_data.get_total_encumbrance_mass())
	
	print("\n--- Verification Complete ---")
	quit()
