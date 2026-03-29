extends SceneTree

func _init() -> void:
	print("--- Starting Item System Verification (UESS) ---")
	
	# NOTE: This test requires Autoloads (GameManager, EntityRegistry, ItemRegistry)
	# to be active. Run within the Godot editor, not standalone.
	
	# 1. Setup Definitions
	var wheat := CommodityDefinition.new()
	wheat.id = &"commodity.wheat"
	wheat.density = 0.77
	
	# 2. Test Tank
	print("\nTesting BulkTankData...")
	var tank: BulkTankData = load("res://Scripts/simulation/BulkTankData.gd").new()
	tank.max_volume = 100.0
	tank.allowed_commodities = [&"commodity.wheat"]
	
	var added: float = tank.try_add_fluid(&"commodity.wheat", 50.0)
	print("Added 50L wheat: ", added == 50.0)
	
	# 3. Test UESS Inventory
	# NOTE: Full inventory tests require GameManager.session to be initialized.
	# The InventoryData now resolves EntityData from EntityManager by runtime_id.
	# For standalone testing, use the in-game developer console:
	#   spawn item.apple 5
	#   Then interact with the apple to test pickup
	
	print("\nNote: InventoryData tests require a running GameSession.")
	print("Use the developer console in-game for integration testing.")
	print("  - 'spawn item.apple' to create test entities")
	print("  - Walk up and interact to test UESS pickup/drop")
	
	print("\n--- Verification Complete ---")
	quit()
