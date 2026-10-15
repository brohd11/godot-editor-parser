@tool
extends RefCounted
## Warmup fixture (copy of gdscript_parser's gp_service.gd, no class_name). Mirrors the UProfile.TimeFunction.TimeScale pattern (deeply nested enum) with several
## const aliases (T / TS / Scale) and functions that take the same enum via each spelling. Used to
## test that the access finder matches the alias the user actually typed. Also hosts a couple of
## in-script caret sites (aliases resolved from *within* the defining script).

@warning_ignore_start("unused_parameter", "unused_variable", "standalone_expression")

class Ticker:
	enum Scale { MSEC, USEC }

const T = Ticker
const TS = Ticker.Scale
const Scale = Ticker.Scale  # NuNu-style: a const alias whose name repeats the enum's own name

func tf_full(s: Ticker.Scale) -> void:
	pass

func tf_t(s: T.Scale) -> void:
	pass

func tf_ts(s: TS) -> void:
	pass

static func make() -> Scale:
	return Scale.MSEC

# In-script caret sites: the caller (this script) has T / TS / Scale in scope.
func _s_local_full() -> void:
	tf_full(Ticker.Scale.MSEC)                 # anchor: "\ttf_full(" (after)

func _s_local_ts() -> void:
	tf_ts(TS.MSEC)                            # anchor: "\ttf_ts(" (after)

func _s_local_scale_alias() -> void:
	var sc := make()
	if sc == Scale.MSEC: pass                 # anchor: "\tif sc == " (after)
