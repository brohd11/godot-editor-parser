extends SceneTree
## Tests for ParserWarmup depth control. Shallow warms the public surface (members/constants/return
## types) and skips function locals; full also maps + resolves locals. A fresh parse per file also
## completes any partial cache. _warmup_one / _resolve_all are tree-independent, so drive them
## directly over a fixture (skipping run()'s FileSystemSingleton enumeration + frame pacing).
##
##     Godot --headless --path . --script res://addons/_lib/editor_parser/_export_ignore/test/warmup_test.gd

const ParserWarmup = preload("res://addons/_lib/editor_parser/src/gdscript/warmup.gd")

const DIR := "res://addons/_lib/editor_parser/_export_ignore/test/"
# own dir: the suites share one process under the aggregator, so don't reuse another suite's cache dir
const TEST_CACHE_DIR := "res://.godot/addons/gdscript_parser/parse_cache_warmup_test"
# warmup_fixture: top-level const aliases (T/TS/Scale) + a function with a typed local (`sc := make()`).
const FIXTURE := DIR + "fixtures/warmup_fixture.gd"
const LOCAL_FUNC := "_s_local_scale_alias"
const LOCAL_VAR := "sc"


# Headless entry point (`--script warmup_test.gd`). quit() lives ONLY here so the static path below is
# safe to call from the editor console / aggregator without killing the editor.
# _initialize(), not _init(): the main loop is null during _init(), so the native backend cannot attach.
func _initialize() -> void:
	_run_headless.call_deferred()


func _run_headless() -> void:
	var res := run_tests()
	print("\n".join(res.output))
	quit(1 if res.result > 0 else 0)


## Runs the suite; returns {result: fail count (0 == all good), output: report lines}.
static func run_tests() -> Dictionary:
	var out: Array = []
	return {"result": _run(out), "output": out}


static func _run(out: Array) -> int:
	_ensure_global_class_registry()

	var fails := 0
	fails += _check(out, "shallow warms surface, skips locals", _test_shallow())
	fails += _check(out, "full warms locals", _test_full())
	fails += _check(out, "fresh parse completes a partial cache", _test_partial_completion())

	out.append("")
	out.append("WARMUP: %s" % ("ALL PASS" if fails == 0 else "%d FAILURE(S)" % fails))
	_clear_dir()
	return fails


static func _check(out: Array, name:String, err:String) -> int:
	if err == "":
		out.append("  PASS  %s" % name)
		return 0
	out.append("  FAIL  %s -> %s" % [name, err])
	return 1


# Shallow: constants resolved, a .bin written, but the typed local is NOT mapped.
static func _test_shallow() -> String:
	_clear_dir()
	ParserWarmup.new()._warmup_one({}, TEST_CACHE_DIR, FIXTURE, false)

	if not FileAccess.file_exists(GDScriptParser.ScriptCache.cache_file_path(TEST_CACHE_DIR, FIXTURE)):
		return "no .bin written"
	var re := GDScriptParser.ScriptCache.read_standalone(FIXTURE, TEST_CACHE_DIR)
	if re == null or re.state != GDScriptParser.STATE_CACHED_RESOLVED:
		return "did not rehydrate as CACHED_RESOLVED"
	if re.get_class_object("")._resolve_cache.is_empty():
		return "public surface not resolved (empty resolve cache)"
	if _local_count(re, "", LOCAL_FUNC) != 0:
		return "shallow mapped function locals (should skip)"
	return ""


# Full: same fixture, the typed local is mapped and resolves.
static func _test_full() -> String:
	_clear_dir()
	ParserWarmup.new()._warmup_one({}, TEST_CACHE_DIR, FIXTURE, true)

	var re := GDScriptParser.ScriptCache.read_standalone(FIXTURE, TEST_CACHE_DIR)
	if re == null:
		return "read_standalone returned null"
	if _local_count(re, "", LOCAL_FUNC) == 0:
		return "full did not map function locals"
	# local_vars are keyed by unique name ("sc-<line>-<col>"); find the entry for LOCAL_VAR.
	var func_obj = re.get_class_object("").functions[LOCAL_FUNC]
	var key := ""
	for k in func_obj.local_vars.keys():
		if str(k).begins_with(LOCAL_VAR + "-"):
			key = k
			break
	if key == "":
		return "full did not map local '%s'" % LOCAL_VAR
	var tr = func_obj.get_local_var_type_rich(key)
	if not (tr is Dictionary) or tr.get("type", "") == "":
		return "full did not resolve local '%s'" % LOCAL_VAR
	return ""


# Fresh parse overwrites a partial cache (one member resolved) with the complete surface.
static func _test_partial_completion() -> String:
	_clear_dir()

	# partial: parse, resolve exactly ONE constant, write.
	var live := _parse_only(FIXTURE)
	var cobj = live.get_class_object("")
	var const_names = cobj.constants.keys()
	if const_names.is_empty():
		return "fixture has no constants to partially resolve"
	cobj.get_member_type_rich(const_names[0])
	live.write_cache()

	var before := GDScriptParser.ScriptCache.read_standalone(FIXTURE, TEST_CACHE_DIR)
	var before_count:int = before.get_class_object("")._resolve_cache.size()

	# warmup (shallow) rebuilds fresh and resolves the whole surface.
	ParserWarmup.new()._warmup_one({}, TEST_CACHE_DIR, FIXTURE, false)

	var after := GDScriptParser.ScriptCache.read_standalone(FIXTURE, TEST_CACHE_DIR)
	var after_count:int = after.get_class_object("")._resolve_cache.size()
	if after_count <= before_count:
		return "partial cache not completed (%d -> %d resolved)" % [before_count, after_count]
	if after_count < const_names.size():
		return "not all constants resolved after warmup (%d < %d)" % [after_count, const_names.size()]
	return ""


# ---- helpers ----

static func _local_count(parser:GDScriptParser, access:String, func_name:String) -> int:
	var cobj = parser.get_class_object(access)
	if not is_instance_valid(cobj) or not cobj.functions.has(func_name):
		return -1
	return cobj.functions[func_name].local_vars.size()

# Parse structure only (no resolve), matching warmup's per-file dispatcher setup.
static func _parse_only(path:String) -> GDScriptParser:
	var p := GDScriptParser.new()
	p.set_autoload_cache()
	p.set_parser_cache({})
	p.set_parser_cache_size(40)
	p.set_parse_cache_dir(TEST_CACHE_DIR)
	p.active_parser = p
	p.set_current_script(load(path))
	p.set_source_code(load(path).source_code)
	p.parse()
	return p

static func _ensure_global_class_registry() -> void:
	var ucd = GDScriptParser.UClassDetail
	if ucd.global_class_registry.is_empty():
		ucd.global_class_registry = ucd.get_all_global_class_paths()

static func _clear_dir() -> void:
	if not DirAccess.dir_exists_absolute(TEST_CACHE_DIR):
		return
	var dir := DirAccess.open(TEST_CACHE_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
