class_name Perf
extends RefCounted
## How long the editor's own steps take, printed when the environment
## variable MAGE_PERF is set. Costs nothing otherwise.

static var on := OS.has_environment("MAGE_PERF")

static func start() -> int:
	return Time.get_ticks_usec() if on else 0

static func stop(label: String, from: int) -> void:
	if on: print("perf %8.1f ms  %s" % [(Time.get_ticks_usec() - from) / 1000.0, label])
