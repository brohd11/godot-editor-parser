#! namespace EditorParser class EditorGDScriptParser
extends Singletons.RefCount

#! strip-cast GDScriptParser

const ParserWarmup = preload("res://addons/_lib/editor_parser/src/gdscript/warmup.gd")

# Use 'PE_STRIP_CAST_SCRIPT' to auto strip type casts with plugin exporter, if the class is not a global name
const PE_STRIP_CAST_SCRIPT = preload("res://addons/_lib/editor_parser/src/gdscript/editor_gdscript_parser.gd")

static func get_singleton_name() -> String:
	return "EditorGDScriptParser"

static func get_instance() -> PE_STRIP_CAST_SCRIPT:
	return _get_instance(PE_STRIP_CAST_SCRIPT)

static func instance_valid() -> bool:
	return _instance_valid(PE_STRIP_CAST_SCRIPT)

static func register_node(node:Node):
	return _register_node(PE_STRIP_CAST_SCRIPT, node)

static func unregister_node(node:Node):
	_unregister_node(PE_STRIP_CAST_SCRIPT, node)

static func call_on_ready(callable, print_err:bool=true):
	_call_on_ready(PE_STRIP_CAST_SCRIPT, callable, print_err)


const SCRIPT_CACHE_SIZE = 40

signal editor_script_changed(script)
signal parse_completed

var gdscript_parser:GDScriptParser

var _parse_queued:bool = false
var _parse_force_queued:bool = false
var _parser_cache:Dictionary = {}

var _script_change_debounce:=false
var _current_script

var valid_script:= true

var _warmup:ParserWarmup


func _init(node):
	gdscript_parser = GDScriptParser.new()
	gdscript_parser.set_autoload_cache()
	_set_parser_cache()


func _set_parser_cache():
	gdscript_parser.set_parser_cache(_parser_cache)
	gdscript_parser.set_parser_cache_size(SCRIPT_CACHE_SIZE)

func _ready() -> void:
	await get_tree().create_timer(1).timeout
	ProjectSettings.settings_changed.connect(_on_project_settings_changed)
	ScriptEditorRef.subscribe(ScriptEditorRef.Event.VALIDATE_SCRIPT, _on_script_validate)
	ScriptEditorRef.subscribe(ScriptEditorRef.Event.EDITOR_SCRIPT_CHANGED, _on_editor_script_changed)
	ScriptEditorRef.subscribe(ScriptEditorRef.Event.TEXT_CHANGED, _on_text_changed)
	_on_editor_script_changed(ScriptEditorRef.get_current_script())

func _on_project_settings_changed():
	if is_instance_valid(gdscript_parser):
		gdscript_parser.set_autoload_cache()

func _on_text_changed():
	gdscript_parser.reset_caret_context()
	# keep line ranges tracking the buffer; the debounced VALIDATE_SCRIPT parse still owns members
	gdscript_parser.sync_line_ranges()


func _on_script_validate():
	_parse()
	gdscript_parser.clean_parser_cache.call_deferred()

func _on_editor_script_changed(script):
	_current_script = script
	#print("CURRENT SCRIPT::", _current_script)
	
	if _script_change_debounce:
		return
	_parse_queued = false # fallback, if the queue is stuck this will get things moving
	_script_change_debounce = true
	await get_tree().process_frame
	_set_editor_script_code_edit()
	_script_change_debounce = false

func _set_editor_script_code_edit():
	gdscript_parser.active_parser = gdscript_parser
	
	valid_script = is_instance_valid(_current_script)
	var code_edit = ScriptEditorRef.get_current_code_edit()
	#print("ACTUAL SCRIPT::", _current_script, "::CODE::", code_edit)

	if not is_instance_valid(code_edit) or not valid_script: # if not emit null. Mostly for clearing the outline when nothing left
		editor_script_changed.emit(null)
	else:
		_merge_current_with_cache(true) # merge resolved members to data, this is useful if the current script doesn't get polled much
		gdscript_parser.set_current_script(_current_script) # this clears the current class objects
		gdscript_parser.set_code_edit(code_edit)
		
		_merge_current_with_cache(false) # merge cached resolve. Before parse, so they can be updated if needed
		
		editor_script_changed.emit(_current_script)
		#print("SCRIPT CHANGE PARSE", _current_script)
		_parse() #true)
	

func _get_or_add_cached_data(script_path:String):
	var cached_data = gdscript_parser.get_cached_parser_data(script_path)
	if not gdscript_parser.cached_data_valid(script_path, cached_data):
		#print("NOT VALID")
		var _parser = gdscript_parser.get_parser_for_path(script_path, true) # this forces instancing and parse once
		cached_data = gdscript_parser.get_cached_parser_data(script_path)
	return cached_data

func _merge_current_with_cache(to_cache:bool): # all this merges is the resolve cache, seems to be fine
	var path = gdscript_parser.get_script_path()
	if not is_instance_valid(gdscript_parser) or not FileAccess.file_exists(path):
		return
	var cached_data = _get_or_add_cached_data(path)
	var classes = cached_data[GDScriptParser.Keys.CACHE_CLASSES]
	gdscript_parser.clean_resolve_cache(classes) # cleans the cache from anything not actually in the class
	if to_cache:
		#print("MERGING::TO CACHE")
		merge_class_data(gdscript_parser._class_access, classes)
	else:
		#print("MERGING::FROM CACHE")
		merge_class_data(classes, gdscript_parser._class_access)

func merge_class_data(from_classes:Dictionary, to_classes:Dictionary):
	for access_name in from_classes.keys():
		var to_obj = to_classes.get(access_name) as GDScriptParser.ParserClass
		if not is_instance_valid(to_obj):
			continue
		var from_obj = from_classes[access_name] as GDScriptParser.ParserClass
		#print("MERGING::", from_obj._resolve_cache.keys(), "::->::", to_obj._resolve_cache.keys())
		to_obj._resolve_cache.merge(from_obj._resolve_cache.duplicate(), true) #^ should this overwrite?



static func queue_parse(force:=false):
	#print("FS PARSE")
	get_instance()._parse(force)

func _parse(force:=false):
	if not valid_script:
		#print("Not a valid script for editor GDScriptParser")
		return
	if force:
		_parse_force_queued = true
	if _parse_queued: # if gdscriptparser hits an error in parse, this can get stuck as true
		return
	_parse_queued = true
	gdscript_parser.parse(_parse_force_queued)
	_parse_force_queued = false
	parse_completed.emit()
	await get_tree().process_frame
	_parse_queued = false


## Warm the project into the disk parse cache (shallow: members/constants/return types).
## Console: script call <this> warmup_project
static func warmup_project() -> void:
	get_instance()._start_warmup(false)

## Full warmup: shallow surface plus mapped function locals + argument types. Heavier.
## Console: script call <this> warmup_project_full
static func warmup_project_full():
	get_instance()._start_warmup(true)

func _start_warmup(full:bool):
	if is_instance_valid(_warmup) and _warmup.running:
		print("ParserWarmup: already running")
		return
	_warmup = ParserWarmup.new()
	_warmup.run(gdscript_parser._parse_cache_dir, get_tree(), full)

static func clear_persistent_cache():
	if not DirAccess.dir_exists_absolute(GDScriptParser.PARSE_CACHE_DIR):
		return
	var files = DirAccess.get_files_at(GDScriptParser.PARSE_CACHE_DIR)
	for f in files:
		var path = GDScriptParser.PARSE_CACHE_DIR.path_join(f)
		DirAccess.remove_absolute(path)

static func get_parser(script_path:String="") -> GDScriptParser:
	var ins = _get_instance(PE_STRIP_CAST_SCRIPT, false)
	if not is_instance_valid(ins) or not ins.valid_script:
		return null
	if script_path == "" or script_path == ins.gdscript_parser.get_script_path():
		return ins.gdscript_parser
	else:
		return ins.gdscript_parser.get_parser_for_path(script_path)

func get_caret_context() -> GDScriptParser.CaretContext:
	return gdscript_parser.get_caret_context()

static func clear_cache() -> void:
	var ins = get_instance()
	ins._parser_cache.clear()
	ins._set_parser_cache()

static func cache_size():
	return get_instance()._parser_cache.size()

static func reset_debounce(): # possibly make a timer? check if the queue has been in for too long
	get_instance()._parse_queued = false

#^ --- Singleton Methods

func _all_unregistered_callback():
	pass

func _get_ready_bool() -> bool:
	return is_node_ready()

static func parse_expression(expression:String, line:int=-1):
	var parser = get_parser()
	return parser.resolve_expression_to_type(expression)


static func test_memory():
	var ins = get_instance()
	var cache = ins._parser_cache
	print("ORPHAN NODES::", ins.get_orphan_node_ids().size())
	print("CACHE SIZE::", cache.get(GDScriptParser.Keys.CACHE_ACTIVE_PARSERS, {}).size(), "::INACTIVE::", cache.get(GDScriptParser.Keys.CACHE_INACTIVE_PARSERS, {}).size())
	print("MEM BEFORE::", String.humanize_size(OS.get_static_memory_usage()))
	cache.clear()
	await ins.get_tree().process_frame
	print("MEM AFTER::", String.humanize_size(OS.get_static_memory_usage()))
	print("ORPHAN NODES AFTER::", ins.get_orphan_node_ids().size())

static func test_mem_current_scripts():
	var ins = get_instance()
	var cache = ins._parser_cache
	print("MEM BEFORE::", String.humanize_size(OS.get_static_memory_usage()))
	for script in EditorInterface.get_script_editor().get_open_scripts():
		
		var g = ins.get_parser(script.resource_path)
		for c in g._class_access.values():
			for m in c.get_members():
				c.get_member_type(m)
	
		#print("NEW PARSER::", String.humanize_size(OS.get_static_memory_usage()))
		pass
	#print("MEM AFTER::", String.humanize_size(OS.get_static_memory_usage()))
	cache.clear()
	await ins.get_tree().process_frame
	print("MEM AFTER CLEAR::", String.humanize_size(OS.get_static_memory_usage()))
