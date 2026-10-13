extends RefCounted
## Keeps every tag occurrence; attachment is separate from discovering its source location.
## Ranges use zero-based character columns with an exclusive end, matching CodeEdit.

const Options = preload("res://addons/_lib/editor_parser/src/tag_parser/options.gd")

const MEMBER_DELIM = ":" + ":"
const ATTACH_MEMBER = &"member"
const ATTACH_FILE = &"file"
const ATTACH_LINE = &"line"
const ATTACH_LOCAL = &"local"
const ATTACH_UNATTACHED = &"unattached"

static var _tag_regex:RegEx
static var _decl_regex:RegEx
static var _header_regex:RegEx


static func scan_lines(lines:PackedStringArray, path:String, owners:Array = []) -> Array:
	_ensure_regex()
	var entries:Array = []
	var state = {"quote": "", "depth": 0, "cont": false}
	var scopes:Array = []
	var pending:Array = []
	var blank_after_pending := false
	var seen_code := false
	var statement_indent := 0
	var statement_line := 0
	var statement_scoped := false
	for i in lines.size():
		var line:String = lines[i].trim_suffix("\r")
		var continued:bool = state.cont
		var comment_idx := scan_code(line, state)
		var code := (line.substr(0, comment_idx) if comment_idx > -1 else line).strip_edges()
		var indent := line.length() - line.strip_edges(true, false).length()
		var tag:Dictionary = {}
		if comment_idx > -1:
			tag = _parse_tag(line.substr(comment_idx), path, i, comment_idx)
		if not continued and (not code.is_empty() or not tag.is_empty()):
			while not scopes.is_empty() and scopes.back().indent >= indent:
				scopes.pop_back()
			var scope_line:int = -1 if scopes.is_empty() else scopes.back().line
			for p in pending.duplicate():
				if p._indent != indent or p._scope != scope_line:
					pending.erase(p)
		var owner := _class_path(path, scopes)
		var function := _function_path(scopes)
		owners.append(owner)
		if not tag.is_empty():
			tag.owner_class = owner
			tag.owner_function = function
			tag._indent = indent
			tag._scope = -1 if scopes.is_empty() else scopes.back().line
			entries.append(tag)
		if continued:
			if not tag.is_empty():
				_attach(tag, ATTACH_LINE, owner, i)
			if not state.cont and code.ends_with(":") and not statement_scoped:
				scopes.append(_scope("block", "", statement_indent, statement_line))
			continue
		if code.is_empty():
			if not tag.is_empty():
				pending.append(tag)
				blank_after_pending = false
			elif comment_idx == -1 and not pending.is_empty():
				blank_after_pending = true
			continue
		statement_indent = indent
		statement_line = i
		statement_scoped = false
		if not tag.is_empty():
			_attach(tag, ATTACH_LINE, owner, i)
		var decl = _decl_regex.search(code)
		if code.begins_with("@") and decl == null:
			continue
		if decl:
			var kind:String = decl.get_string("kind")
			var member_name:String = decl.get_string("name")
			var local:bool = not scopes.is_empty() and scopes.back().kind != "class"
			var identity := owner + "." + member_name if kind == "class" else owner + MEMBER_DELIM + member_name
			if member_name.is_empty():
				identity = owner
			var header_block := not seen_code and blank_after_pending
			for p in pending:
				if header_block:
					_attach(p, ATTACH_FILE, path, i, kind, member_name)
				else:
					_attach(p, ATTACH_LOCAL if local else ATTACH_MEMBER, "" if local else identity, i, kind, member_name)
			if kind in ["class", "func"] and (state.cont or code.ends_with(":")):
				scopes.append(_scope(kind, identity, indent, i))
				statement_scoped = true
		elif (scopes.is_empty() and _header_regex.search(code) != null) or not seen_code:
			for p in pending:
				_attach(p, ATTACH_FILE, path, i)
		else:
			for p in pending:
				_attach(p, ATTACH_LINE, owner, i)
		if code.ends_with(":") and not statement_scoped:
			scopes.append(_scope("block", "", indent, i))
			statement_scoped = true
		seen_code = true
		pending.clear()
		blank_after_pending = false
	for entry:Dictionary in entries:
		entry.erase("_indent")
		entry.erase("_scope")
	return entries


static func _scope(kind:String, identity:String, indent:int, line:int) -> Dictionary:
	return {"kind": kind, "identity": identity, "indent": indent, "line": line}


static func _class_path(path:String, scopes:Array) -> String:
	for i in range(scopes.size() - 1, -1, -1):
		if scopes[i].kind == "class":
			return scopes[i].identity
	return path


static func _function_path(scopes:Array) -> String:
	for i in range(scopes.size() - 1, -1, -1):
		if scopes[i].kind == "func":
			return scopes[i].identity
	return ""


static func _attach(entry:Dictionary, attach:StringName, identity:String, target:int,
		kind:String = "", member_name:String = "") -> void:
	entry.attach = attach
	entry.identity = identity
	entry.target = target
	entry.target_kind = kind
	entry.target_name = member_name


static func _parse_tag(comment:String, path:String, line:int, column:int) -> Dictionary:
	var match_tag = _tag_regex.search(comment.strip_edges(false, true))
	if match_tag == null:
		return {}
	var mods:String = match_tag.get_string("mod").strip_edges()
	var args:String = match_tag.get_string("args").strip_edges()
	if args.is_empty() and not comment.contains(";"):
		args = mods
		mods = ""
	return {"tag": match_tag.get_string("tag"), "mods": mods, "args": args, "raw": comment,
		"file": path, "line": line, "column": column, "end_line": line,
		"end_column": column + comment.length(), "attach": ATTACH_UNATTACHED,
		"identity": "", "target": -1, "target_kind": "", "target_name": ""}


static func _ensure_regex() -> void:
	if _tag_regex != null:
		return
	_tag_regex = RegEx.new()
	_tag_regex.compile("^#!\\s*(?<tag>[\\w-]+)(?:\\s+(?<mod>[^;]+?))?(?:\\s*;\\s*(?<args>.*))?\\s*$")
	const ANNOTATIONS = "(?:@\\w+(?:\\([^)]*\\))?\\s+)*"
	_decl_regex = RegEx.new()
	_decl_regex.compile("^" + ANNOTATIONS + "(?:static\\s+)?(?<kind>func|var|const|signal|class|enum)\\b\\s*(?<name>\\w*)")
	_header_regex = RegEx.new()
	_header_regex.compile("^" + ANNOTATIONS + "(?:class_name|extends)\\b")


## Index the comment starts at, or -1. `state` carries open triple-quoted strings and bracket depth
## across lines; `state.cont` is set when the statement continues onto the next line.
static func scan_code(line:String, state:Dictionary) -> int:
	var quote:String = state.quote
	var comment_idx = -1
	var i = 0
	var n = line.length()
	while i < n:
		var c = line[i]
		if quote != "":
			if c == "\\":
				i += 2
			elif line.substr(i, quote.length()) == quote:
				i += quote.length()
				quote = ""
			else:
				i += 1
			continue
		if c == "#":
			comment_idx = i
			break
		if c == '"' or c == "'":
			var triple = c + c + c
			quote = triple if line.substr(i, 3) == triple else c
			i += quote.length()
			continue
		if c in "([{":
			state.depth += 1
		elif c in ")]}":
			state.depth = maxi(state.depth - 1, 0)
		i += 1

	if quote.length() == 1: # only a triple quote spans lines
		quote = ""
	state.quote = quote
	var code = line.substr(0, comment_idx) if comment_idx > -1 else line
	state.cont = state.depth > 0 or quote != "" or code.strip_edges(false, true).ends_with("\\")
	return comment_idx
