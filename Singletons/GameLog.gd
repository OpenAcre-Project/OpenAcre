extends Node

## Centralized game logging. All game scripts should use GameLog.info() / warn() / error()
## instead of print() / push_warning() / push_error(). The DeveloperConsole subscribes to the
## log_message signal to display entries in-game. If no console exists (production), the signal
## simply has no listeners — zero overhead.

enum Level { INFO, WARN, ERROR }

signal log_message(text: String, level: int)

func info(text: String) -> void:
	print(text)
	log_message.emit(text, Level.INFO)

func warn(text: String) -> void:
	push_warning(text)
	log_message.emit(text, Level.WARN)

func error(text: String) -> void:
	push_error(text)
	log_message.emit(text, Level.ERROR)

## Convenience: format + log in one call
func infof(fmt: String, args: Array) -> void:
	info(fmt % args)

func warnf(fmt: String, args: Array) -> void:
	warn(fmt % args)

func errorf(fmt: String, args: Array) -> void:
	error(fmt % args)
