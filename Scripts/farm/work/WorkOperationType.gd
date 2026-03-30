extends RefCounted
class_name WorkOperationType

enum Value {
	TILLAGE = 0,
	SOWING = 1,
	APPLICATION = 2,
	HARVESTING = 3,
	CLEARING = 4
}

static func as_string(operation: int) -> String:
	match operation:
		Value.TILLAGE:
			return "TILLAGE"
		Value.SOWING:
			return "SOWING"
		Value.APPLICATION:
			return "APPLICATION"
		Value.HARVESTING:
			return "HARVESTING"
		Value.CLEARING:
			return "CLEARING"
		_:
			return "UNKNOWN"
