@tool
extends EditorScript

## Tests for the shared TagRegistry - `#!` tags resolved to the member, file or line they
## are attached to, keyed by parser type path.
##
##     load("res://addons/_lib/editor_parser/_export_ignore/test/registry_test.gd").run_tests()

const TagRegistry = preload("res://addons/_lib/editor_parser/src/tag/registry.gd")
const P = "res://t.gd"
const DIR = "user://tag_parser_registry_tests/"

static var _failures:Array[String] = []
static var _passed:int = 0


static func run_tests() -> Dictionary:
	_failures = []
	_passed = 0

	_test_member_attach()
	_test_file_attach()
	_test_line_attach()
	_test_masking()
	_test_pending_reset()
	_test_tag_grammar()
	_test_continuation()
	_test_registry()

	var output:Array[String] = []
	output.append("tag_registry: %d passed, %d failed" % [_passed, _failures.size()])
	for failure in _failures:
		output.append("  FAIL  " + failure)
	return {"result": _failures.size(), "output": output}


func _run() -> void: # EditorScript entry, for running this from the editor
	print("\n".join(run_tests().output))


static func _test_member_attach() -> void:
	var e = _scan([
		"extends RefCounted",
		"#! struct",
		"class S:",
		"\tvar a",
		"class Outer:",
		"\tclass Inner:",
		"\t\t#! keys",
		"\t\tvar field",
		"\t#! keys",
		"\tstatic func f():",
		"\t\tpass",
		"#! keys",
		"@export_range(0, 10)",
		"var top",
		"#! keys",
		"var after_class",
	])
	_check("member: class identity is the class path", _ids(e, "struct"), ["res://t.gd.S"])
	_check("member: attach", e[0].attach, TagRegistry.ATTACH_MEMBER)
	_check("member: nested class member, annotations skipped, class body popped", _ids(e, "keys"),
		["res://t.gd.Outer.Inner::field", "res://t.gd.Outer::f", "res://t.gd::top", "res://t.gd::after_class"])


## A blank line after a header tag makes it the file's; a tag right above a declaration is that
## declaration's, even in the header.
static func _test_file_attach() -> void:
	var remote = _scan(["#! remote", "", "const A = 1"])
	_check("file: blank-separated header tag", [remote[0].attach, remote[0].identity], [TagRegistry.ATTACH_FILE, P])
	var ns = _scan(["#! namespace A.B class C", "extends RefCounted"])
	_check("file: above extends", [ns[0].attach, ns[0].identity], [TagRegistry.ATTACH_FILE, P])
	var cn = _scan(["@tool", "#! struct", "class_name S extends RefCounted"])
	_check("file: above class_name, past @tool", [cn[0].attach, cn[0].identity], [TagRegistry.ATTACH_FILE, P])
	var adjacent = _scan(["#! remote", "const A = 1"])
	_check("file: adjacent header tag attaches to the declaration", adjacent[0].identity, P + "::A")


static func _test_line_attach() -> void:
	var e = _scan([
		'const A = preload("x.gd") #! dependency current',
		"class Inner:",
		'\tvar p = "res://a" #! ignore-remote',
	])
	_check("line: attach", e[0].attach, TagRegistry.ATTACH_LINE)
	_check("line: top-level owner", e[0].identity, P)
	_check("line: value is args", e[0].args, "current")
	_check("line: hyphenated tag inside a class", [e[1].tag, e[1].identity], ["ignore-remote", P + ".Inner"])


static func _test_masking() -> void:
	var e = _scan([
		'var s = "#! struct"',
		"var t = '# not #! struct'",
		"## tag it `#! struct` to convert",
		'var doc = """',
		"#! struct",
		'"""',
		"var after",
	])
	_check("masking: strings, prose and triple-quoted bodies never fire", e.size(), 0)


static func _test_pending_reset() -> void:
	var e = _scan([
		"extends RefCounted",
		"func f():",
		"\t#! struct",
		"\tprint(1)",
		"\tvar x = 2",
	])
	_check("reset: tag above plain code attaches to that line", [e.size(), e[0].attach, e[0].target], [1, TagRegistry.ATTACH_LINE, 3])


static func _test_tag_grammar() -> void:
	var e = _scan([
		"#! arg_location line:Keys; context:SubSpace",
		"#! keys a b",
		"#!keys_tight",
		"#! struct",
		"var m",
	])
	_check("grammar: mods; args", [e[0].mods, e[0].args], ["line:Keys", "context:SubSpace"])
	_check("grammar: lone value is args", [e[1].mods, e[1].args], ["", "a b"])
	_check("grammar: no space after #!", e[2].tag, "keys_tight")
	_check("grammar: bare tag", [e[3].mods, e[3].args], ["", ""])
	_check("grammar: stacked tags share the declaration", _ids(e, "struct"), [P + "::m"])
	_check("grammar: line numbers", [e[0].line, e[3].line], [0, 3])
	_check("grammar: target is the declaration line", [e[0].target, e[3].target], [4, 4])


static func _test_continuation() -> void:
	var e = _scan([
		"var d = {",
		'\t"a": 1, #! keys',
		"}",
		"var long = 1 + \\",
		"\t2",
		"#! struct",
		"class S:",
		"\tvar a",
	])
	_check("continuation: tag inside a bracket is a line tag", [e[0].tag, e[0].attach], ["keys", TagRegistry.ATTACH_LINE])
	_check("continuation: closing bracket and backslash do not break class tracking", _ids(e, "struct"), [P + ".S"])


static func _test_registry() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path = DIR + "reg.gd"
	var f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(["extends RefCounted", "#! struct", "class S:", "\tvar a", "\t#! struct", "\tvar b"]))
	f.close()

	var reg = TagRegistry.new()
	reg.scan_files([path, DIR + "missing.gd", DIR + "data.json"])
	_check("registry: entries by tag", reg.get_entries("struct").size(), 2)
	_check("registry: unknown tag", reg.get_entries("nope"), [])
	_check("registry: has_tag", [reg.has_tag(path + ".S", "struct"), reg.has_tag(path + ".S", "keys")], [true, false])
	_check("registry: tag data", reg.get_tag_data(path + ".S::b", "struct").get("line"), 4)
	_check("registry: missing and non-gd files are empty", reg.get_file_entries(DIR + "missing.gd"), [])

	DirAccess.remove_absolute(path)
	_check("registry: cached after the file is gone", reg.get_file_entries(path).size(), 2)
	DirAccess.remove_absolute(DIR)


# --- harness -----------------------------------------------------------------------------

static func _scan(lines:Array) -> Array:
	return TagRegistry.scan_lines(PackedStringArray(lines), P)


static func _ids(entries:Array, tag:String) -> Array:
	var out = []
	for e in entries:
		if e.tag == tag:
			out.append(e.identity)
	return out


static func _check(label:String, actual, expected) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failures.append("%s\n          expected: %s\n          actual:   %s" % [label, expected, actual])
