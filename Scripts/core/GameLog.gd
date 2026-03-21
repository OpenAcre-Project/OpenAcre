class_name GameLog
extends RefCounted

## Centralized game logging. All game scripts should use GameLog.info() / warn() / error()
## instead of print() / push_warning() / push_error(). The DeveloperConsole subscribes to the
## log_message signal to display entries in-game. If no console exists (production), the signal
## simply has no listeners — zero overhead.

enum Level { INFO, WARN, ERROR }

static func info(text: String) -> void:
	print(text)
	EventBus.log_message.emit(text, Level.INFO)

static func warn(text: String) -> void:
	push_warning(text)
	EventBus.log_message.emit(text, Level.WARN)

static func error(text: String) -> void:
	push_error(text)
	EventBus.log_message.emit(text, Level.ERROR)

## Convenience: format + log in one call
static func infof(fmt: String, args: Array) -> void:
	info(fmt % args)

static func warnf(fmt: String, args: Array) -> void:
	warn(fmt % args)

static func errorf(fmt: String, args: Array) -> void:
	error(fmt % args)
