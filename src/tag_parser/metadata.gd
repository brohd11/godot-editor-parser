extends RefCounted
## Legacy handlers receive merged modifiers/arguments; raw occurrence queries stay lossless.

const Registry = preload("res://addons/_lib/editor_parser/src/tag_parser/registry.gd")


static func build(entries:Array, handlers:Dictionary) -> Dictionary:
	var grouped:Dictionary = {}
	for entry:Dictionary in entries:
		if entry.attach != Registry.ATTACH_MEMBER or entry.target_name.is_empty() or not handlers.has(entry.tag):
			continue
		var member_path:String = entry.identity.trim_prefix(entry.file).trim_prefix(".").trim_prefix(Registry.MEMBER_DELIM)
		# Class declarations belong to the class itself in the existing editor metadata API.
		if entry.target_kind == "class":
			member_path += Registry.MEMBER_DELIM + entry.target_name
		var tags:Dictionary = grouped.get_or_add(member_path, {})
		if tags.has(entry.tag):
			tags[entry.tag].args += " " + entry.args
			tags[entry.tag].mods += " " + entry.mods
		else:
			tags[entry.tag] = {"args": entry.args, "mods": entry.mods}
	var metadata:Dictionary = {}
	for member_path:String in grouped:
		var tags:Dictionary = {}
		for tag:String in grouped[member_path]:
			tags[tag] = handlers[tag].parse_tag(grouped[member_path][tag])
		metadata[member_path] = tags
	return metadata
