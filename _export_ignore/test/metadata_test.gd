extends RefCounted

const Scanner = preload("res://addons/_lib/editor_parser/src/tag/scanner.gd")
const Metadata = preload("res://addons/_lib/editor_parser/src/tag/metadata.gd")

class Handler:
	extends RefCounted
	func parse_tag(raw:Dictionary) -> Dictionary:
		return raw.duplicate()


static func run_tests() -> Dictionary:
	var source := PackedStringArray([
		"extends RefCounted", "#! keys first; one", "#! keys second; two", "var member",
		"#! keys class-data", "class Outer:", "\t#! keys inner", "\tclass Inner:",
		"\t\t#! keys func-data", "\t\tfunc run():", "\t\t\t#! keys local", "\t\t\tvar member",
		"\t\t\tprint(member) #! keys trailing", "#! unregistered", "var unknown", "#! keys eof",
	])
	var entries := Scanner.scan_lines(source, "res://metadata.gd")
	var handler := Handler.new()
	var metadata := Metadata.build(entries, {"keys": handler})
	var expected := {
		"member": {"keys": {"mods": "first second", "args": "one two"}},
		"Outer::Outer": {"keys": {"mods": "", "args": "class-data"}},
		"Outer.Inner::Inner": {"keys": {"mods": "", "args": "inner"}},
		"Outer.Inner::run": {"keys": {"mods": "", "args": "func-data"}},
	}
	var failures := 0
	var output:Array = []
	if metadata != expected:
		failures += 1
		output.append("FAIL metadata compatibility: %s" % [metadata])
	if entries.size() != 9 or entries[0].args != "one" or entries[1].args != "two":
		failures += 1
		output.append("FAIL metadata aggregation changed or discarded raw occurrences")
	if not Metadata.build(entries, {}).is_empty():
		failures += 1
		output.append("FAIL unregistered handlers produced metadata")
	output.push_front("tag metadata: %d passed, %d failed" % [3 - failures, failures])
	return {"result": failures, "output": output}
