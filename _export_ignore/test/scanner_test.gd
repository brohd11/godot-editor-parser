extends RefCounted

const Scanner = preload("res://addons/_lib/editor_parser/src/tag/scanner.gd")
const Registry = preload("res://addons/_lib/editor_parser/src/tag/registry.gd")
const P = "res://sample.gd"

static var _failures:Array = []
static var _passed:int


static func run_tests() -> Dictionary:
	_failures = []
	_passed = 0
	_test_locations()
	_test_scopes()
	_test_multiline()
	_test_registry_updates()
	var output:Array = ["tag scanner: %d passed, %d failed" % [_passed, _failures.size()]]
	output.append_array(_failures)
	return {"result": _failures.size(), "output": output}


static func _test_locations() -> void:
	var lines := PackedStringArray([
		'var text = "é😀" #! keys α  \r',
		"func f():",
		"\t#! inline",
		"\twork()",
		"\t#! future some-data",
	])
	var tags := Scanner.scan_lines(lines, P)
	_check("all occurrences survive", tags.size(), 3)
	var first:Dictionary = tags[0]
	_check("raw trailing spaces retained", first.raw, "#! keys α  ")
	_check("character columns, CR excluded", [first.line, first.column, first.end_line, first.end_column],
		[0, lines[0].find("#!"), 0, lines[0].length() - 1])
	_check("standalone targets next statement", [tags[1].attach, tags[1].target], [Scanner.ATTACH_LINE, 3])
	_check("EOF has no invented target", [tags[2].attach, tags[2].identity, tags[2].target], [Scanner.ATTACH_UNATTACHED, "", -1])
	_check("EOF retains its function", tags[2].owner_function, P + "::f")
	var only := Scanner.scan_lines(PackedStringArray(["#! future"]), P)
	_check("tag-only source survives", only[0].attach, Scanner.ATTACH_UNATTACHED)
	var ordered := Scanner.scan_lines(PackedStringArray(["#! before", "var value #! trailing"]), P)
	_check("pending and trailing tags retain source order", ordered.map(func(e): return e.tag), ["before", "trailing"])
	var masked := Scanner.scan_lines(PackedStringArray([
		'var a = "escaped \\" #! hidden"',
		'var b = """', "#! hidden", '""" #! visible', "# prose #! hidden", "##! hidden",
	]), P)
	_check("only real tag comment parsed", masked.map(func(e): return e.tag), ["visible"])


static func _test_scopes() -> void:
	var owners:Array = []
	var tags := Scanner.scan_lines(PackedStringArray([
		"class Outer:",
		"\t#! keys member",
		"\tvar value",
		"\t#! inline",
		"\tstatic func run():",
		"\t\t#! keys local",
		"\t\tvar value",
		"\t\tif true:",
		"\t\t\t#! leftover",
		"\t\tprint(value)",
		"\t\t#! lost_function",
		"\t#! keys next",
		"\tfunc next():",
		"\t\tpass",
		"#! root",
		"var root",
	]), P, owners)
	_check("member identity", tags[0].identity, P + ".Outer::value")
	_check("function declaration target", [tags[1].attach, tags[1].target_kind], [Scanner.ATTACH_MEMBER, "func"])
	_check("local excluded from member identities", [tags[2].attach, tags[2].identity], [Scanner.ATTACH_LOCAL, ""])
	_check("local owner function", tags[2].owner_function, P + ".Outer::run")
	_check("cannot cross block boundary", tags[3].attach, Scanner.ATTACH_UNATTACHED)
	_check("cannot cross function boundary", tags[4].attach, Scanner.ATTACH_UNATTACHED)
	_check("outdented tag has correct scope", [tags[5].owner_class, tags[5].owner_function], [P + ".Outer", ""])
	_check("root owner after class", tags[6].owner_class, P)
	_check("one owner for every source line", owners.size(), 16)
	_check("owner inside function", owners[6], P + ".Outer")
	var sibling := Scanner.scan_lines(PackedStringArray([
		"func f():", "\tif true:", "\t\t#! branch", "\telse:", "\t\tvar x",
	]), P)
	_check("tag cannot jump to sibling branch", sibling[0].attach, Scanner.ATTACH_UNATTACHED)


static func _test_multiline() -> void:
	var tags := Scanner.scan_lines(PackedStringArray([
		"extends RefCounted",
		"#! keys a", "@export_enum(", '\t"A",', '\t"B"', ")", "var choice",
		"#! inline", "static func f(", "\targ:int, #! argument", "):",
		"\t#! local", "\tvar x = arg",
		"\tif (", "\t\targ > 0", "\t):", "\t\t#! branch", "\tprint(x)",
	]), P)
	_check("annotation continuation preserves pending tag", [tags[0].attach, tags[0].target], [Scanner.ATTACH_MEMBER, 6])
	_check("multiline function target starts at func", tags[1].target, 8)
	_check("parameter trailing tag stays line-scoped", [tags[2].attach, tags[2].target], [Scanner.ATTACH_LINE, 9])
	_check("body of multiline function is local", tags[3].attach, Scanner.ATTACH_LOCAL)
	_check("multiline block boundary respected", tags[4].attach, Scanner.ATTACH_UNATTACHED)
	var local_lambda := Scanner.scan_lines(PackedStringArray([
		"var callback = func():", "\t#! keys", "\tvar value", "\treturn value",
	]), P)
	_check("lambda locals are not class members", local_lambda[0].attach, Scanner.ATTACH_LOCAL)
	var anonymous_enum := Scanner.scan_lines(PackedStringArray(["#! keys", "enum { X, Y }"]), P)
	_check("anonymous enum retains its enclosing identity", anonymous_enum[0].identity, P)


static func _test_registry_updates() -> void:
	var registry = Registry.new()
	registry.replace_source(P, PackedStringArray(["#! keys one", "#! keys two", "var value"]))
	registry.replace_source("res://other.gd", PackedStringArray(["#! keys other", "var value"]))
	_check("duplicates retained", registry.get_entries("keys").size(), 3)
	_check("first entry compatibility", registry.get_tag_data(P + "::value", "keys").args, "one")
	registry.replace_source(P, PackedStringArray(["#! renamed", "func run():", "\t#! keys local", "\tvar value"]))
	_check("old identity removed", registry.has_tag(P + "::value", "keys"), false)
	_check("new identity indexed", registry.has_tag(P + "::run", "renamed"), true)
	_check("old occurrences removed, other file retained", registry.get_entries("keys").size(), 2)
	_check("local does not pollute member index", registry.has_tag(P + "::value", "keys"), false)
	registry.invalidate(P)
	_check("invalidation clears new identity", registry.has_tag(P + "::run", "renamed"), false)
	_check("invalidation retains other file", registry.get_entries("keys").size(), 1)
	registry.clear()
	_check("clear removes every index", [registry.get_entries("keys"), registry.has_tag("res://other.gd::value", "keys")], [[], false])


static func _check(label:String, actual:Variant, expected:Variant) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failures.append("FAIL %s: expected %s, got %s" % [label, expected, actual])
