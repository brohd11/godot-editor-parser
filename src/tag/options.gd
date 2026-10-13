extends RefCounted
## Opt-in parsing keeps legacy tag consumers and raw argument text unchanged.

static func parse(text:String) -> Dictionary:
	var options:Dictionary = {}
	var errors:Array = []
	var token := RegEx.create_from_string(r'''\s*([A-Za-z_][A-Za-z_0-9-]*)(?:\s*=\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s,=\"\']+))?''')
	var offset := 0
	while offset < text.length():
		if text[offset] in [" ", "\t", "\r", "\n", ","]:
			offset += 1
			continue
		var found := token.search(text, offset)
		if found == null or found.get_start() != offset:
			errors.append("Malformed tag option near: " + text.substr(offset))
			break
		var name := found.get_string(1)
		var raw := found.get_string(2)
		var value:Variant = true
		if raw != "":
			value = raw.substr(1, raw.length() - 2).c_unescape() if raw[0] in ['"', "'"] else raw
		if options.has(name):
			errors.append("Duplicate tag option: " + name)
		else:
			options[name] = value
		offset = found.get_end()
		if offset < text.length() and text[offset] not in [" ", "\t", "\r", "\n", ","]:
			errors.append("Expected a separator after tag option: " + name)
			break
	return {"options": options if errors.is_empty() else {}, "errors": errors}
