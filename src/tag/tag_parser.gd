#! namespace EditorParser class TagParser
extends Singletons.Base

const CacheHelper = preload("uid://c70cjcnys60ud") #! resolve UtilR.Files.CacheHelper

# Core components, exposed so consumers can reach them as EditorParser.TagParser.X.
const Scanner = preload("res://addons/_lib/editor_parser/src/tag/scanner.gd")
const Options = preload("res://addons/_lib/editor_parser/src/tag/options.gd")
const Registry = preload("res://addons/_lib/editor_parser/src/tag/registry.gd")
const Metadata = preload("res://addons/_lib/editor_parser/src/tag/metadata.gd")

# Use 'PE_STRIP_CAST_SCRIPT' to auto strip type casts with plugin exporter, if the class is not a global name
const PE_STRIP_CAST_SCRIPT = preload("res://addons/_lib/editor_parser/src/tag/tag_parser.gd")
static func get_singleton_name() -> String:
	return "EditorTagParser"

static func get_instance() -> PE_STRIP_CAST_SCRIPT:
	return _get_instance(PE_STRIP_CAST_SCRIPT)

static func instance_valid() -> bool:
	return _instance_valid(PE_STRIP_CAST_SCRIPT)

static func call_on_ready(callable:Callable, print_err:bool=true):
	_call_on_ready(PE_STRIP_CAST_SCRIPT, callable, print_err)

func _get_ready_bool() -> bool:
	return is_node_ready()

static func register_tag_parser(tag:StringName, parser:Object):
	var ins = get_instance()
	if ins.parsers.has(tag):
		printerr("Parser tag already registered::", tag)
	elif not parser.has_method("parse_tag"):
		printerr("Parser does not have 'parse_tag' method::", parser, "::Tag - ", tag)
	else:
		ins.parsers[tag] = parser
		ins._cache.clear()

static func unregister_tag_parser(tag:StringName):
	var ins = get_instance()
	if not ins.parsers.has(tag):
		printerr("Tag was not registered::", tag)
	else:
		ins.parsers.erase(tag)
		ins._cache.clear()



var parsers:Dictionary[StringName, Object] = {}
var _cache:Dictionary = {}
var _sources:Dictionary = {}
var _registry = Registry.new()


func _init(_node:Node = null) -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)


func _on_filesystem_changed() -> void:
	_invalidate()


func _invalidate() -> void:
	_cache.clear()
	_sources.clear()
	_registry.clear()


static func get_tag_parser(tag:StringName, print_err:=true):
	var ins = get_instance()
	var parser = ins.parsers.get(tag)
	if parser == null and print_err:
		print("Parser not registered: ", tag)
	return parser

static func get_metadata_for_type(type_path:String, tag:StringName=&""):
	if not GDScriptParser.Utils.is_absolute_path(type_path):
		return
	
	var script_data = GDScriptParser.Utils.type_path_get_script_data(type_path)
	var script_path = script_data[0]
	var class_access = script_data[1]
	var member = GDScriptParser.Utils.type_path_get_member(type_path)
	if member == "":
		return
	
	var member_path:String
	if class_access != "":
		member_path = GDScriptParser.Utils.type_path_add_member(class_access, member)
	else:
		member_path = member
	
	var ins = get_instance()
	var script_meta = ins.get_script_metadata(script_path)
	if not script_meta:
		return
	var data_for_class = script_meta.get(member_path)
	if not data_for_class:
		return
	
	var data = {}
	var valid_tags = data_for_class.keys() if tag.is_empty() else [tag]
	for t in valid_tags:
		var tag_data = data_for_class.get(t)
		if not tag_data:
			continue
		data[t] = tag_data
	return data

static func get_tag_metadata(tag:StringName, path:String = ""):
	var ins = get_instance()
	if path == "":
		path = ins._current_script_path()
	return ins.get_script_metadata(path).get(tag)


static func get_tag_entries(path:String = "", tag:String = "") -> Array:
	var ins = get_instance()
	if path == "":
		path = ins._current_script_path()
	var entries:Array = ins._get_entries(path)
	if tag.is_empty():
		return entries
	return entries.filter(func(entry:Dictionary) -> bool: return entry.tag == tag)


func get_script_metadata(path:String) -> Dictionary:
	var entries := _get_entries(path)
	if path.is_empty():
		return {}
	var cached = CacheHelper.get_cached_data(path, _cache)
	if cached != null:
		return cached
	var metadata := Metadata.build(entries, parsers)
	CacheHelper.store_data(path, metadata, _cache, [path] if FileAccess.file_exists(path) else [])
	return metadata


func parse_script_metadata(gdscript_parser:GDScriptParser) -> Dictionary:
	if not is_instance_valid(gdscript_parser):
		return {}
	gdscript_parser.get_code_edit_parser() # Rehydrate cached parsers before reading their source.
	var buffer:CodeEdit = gdscript_parser.code_edit
	if not is_instance_valid(buffer):
		return {}
	var lines := buffer.text.split("\n")
	return Metadata.build(Registry.scan_lines(lines, gdscript_parser.get_script_path()), parsers)


func _get_entries(path:String) -> Array:
	if path.is_empty():
		return []
	var source := _read_source(path)
	if not _sources.has(path) or _sources[path] != source:
		_sources[path] = source
		_registry.replace_source(path, source.split("\n"))
		_cache.erase(path)
	return _registry.get_file_entries(path)


func _current_script_path() -> String:
	if not Engine.is_editor_hint():
		return ""
	var current = ScriptEditorRef.get_current_script()
	return current.resource_path if is_instance_valid(current) else ""


func _read_source(path:String) -> String:
	if path == _current_script_path():
		var code_edit = ScriptEditorRef.get_current_code_edit()
		if is_instance_valid(code_edit):
			return code_edit.text
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


static func clear_cache() -> void:
	get_instance()._invalidate()
