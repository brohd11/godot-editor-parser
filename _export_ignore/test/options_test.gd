extends RefCounted
const Scanner = preload("res://addons/_lib/editor_parser/src/tag/scanner.gd")

static func run_tests() -> Dictionary:
	var failures:Array = []
	for text:String in ["substitute mode=direct", "substitute, mode=direct", "substitute mode = 'direct'"]:
		var result := Scanner.Options.parse(text)
		if not result.errors.is_empty() or result.options != {"substitute": true, "mode": "direct"}:
			failures.append("option parsing failed: " + text)
	for text:String in ["substitute substitute", "mode=one mode=two", "=value", "mode=", "mode='unfinished", 'mode="a"tail']:
		var result := Scanner.Options.parse(text)
		if result.errors.is_empty() or not result.options.is_empty():
			failures.append("invalid options accepted: " + text)
	var quoted := Scanner.Options.parse('label="a, b; c" empty=""')
	if not quoted.errors.is_empty() or quoted.options != {"label": "a, b; c", "empty": ""}:
		failures.append("quoted values changed")
	var entries := Scanner.scan_lines(PackedStringArray(["#! inline; substitute", "static func sample():", "\tpass"]), "res://test.gd")
	if entries.size() != 1 or entries[0].args != "substitute" or entries[0].mods != "" or entries[0].attach != Scanner.ATTACH_MEMBER:
		failures.append("option tag lost attachment/raw compatibility")
	return {"result": failures.size(), "output": ["tag options: %d failures" % failures.size()] + failures}
