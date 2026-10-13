extends "res://addons/_lib/editor_parser/src/tag/scanner.gd"
## File reads are snapshots. Replace buffers or invalidate paths explicitly after edits.

var _files:Dictionary = {}
var _by_tag:Dictionary = {}
var _by_identity:Dictionary = {}


func scan_file(path:String) -> Array:
	if not _files.has(path):
		var lines := PackedStringArray()
		if path.get_extension() == "gd" and FileAccess.file_exists(path):
			lines = FileAccess.get_file_as_string(path).split("\n")
		replace_source(path, lines)
	return _files[path]


func scan_files(paths:Array) -> void:
	for path:String in paths:
		scan_file(path)


func replace_source(path:String, lines:PackedStringArray) -> Array:
	invalidate(path)
	var entries := scan_lines(lines, path)
	_files[path] = entries
	for entry:Dictionary in entries:
		_by_tag.get_or_add(entry.tag, []).append(entry)
		if entry.attach not in [ATTACH_FILE, ATTACH_MEMBER]:
			continue
		var tags:Dictionary = _by_identity.get_or_add(entry.identity, {})
		if not tags.has(entry.tag):
			tags[entry.tag] = entry
	return entries


func invalidate(path:String) -> void:
	for entry:Dictionary in _files.get(path, []):
		var tagged:Array = _by_tag[entry.tag]
		tagged.erase(entry)
		if tagged.is_empty():
			_by_tag.erase(entry.tag)
		_by_identity.erase(entry.identity)
	_files.erase(path)


func clear() -> void:
	_files.clear()
	_by_tag.clear()
	_by_identity.clear()


func get_entries(tag:String) -> Array:
	return _by_tag.get(tag, [])


func get_file_entries(path:String) -> Array:
	return scan_file(path)


func has_tag(identity:String, tag:String) -> bool:
	return _by_identity.get(identity, {}).has(tag)


func get_tag_data(identity:String, tag:String) -> Dictionary:
	return _by_identity.get(identity, {}).get(tag, {})
