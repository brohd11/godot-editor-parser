extends RefCounted

const Service = preload("res://addons/_lib/editor_parser/src/tag/tag_parser.gd")
const P = "res://unsaved_tag_test.gd"
const TAG = &"tag_parser_service_test"
const FIXTURE = "res://addons/_lib/editor_parser/_export_ignore/test/fixtures/metadata.gd"

class Handler:
	extends RefCounted
	var calls := 0
	func parse_tag(raw:Dictionary) -> Dictionary:
		calls += 1
		return raw.duplicate()

class BufferService:
	extends "res://addons/_lib/editor_parser/src/tag/tag_parser.gd"
	var buffer := ""
	func _read_source(_path:String) -> String:
		return buffer
	func _current_script_path() -> String:
		return "res://unsaved_tag_test.gd"

static var _failures:Array = []
static var _passed:int


static func run_tests() -> Dictionary:
	_failures = []
	_passed = 0
	_test_buffers()
	_test_singleton()
	_check("all service checks completed", _passed + _failures.size(), 22)
	var output:Array = ["tag editor service: %d passed, %d failed" % [_passed, _failures.size()]]
	output.append_array(_failures)
	return {"result": _failures.size(), "output": output}


static func _test_buffers() -> void:
	var service := BufferService.new()
	var handler := Handler.new()
	service.parsers["keys"] = handler
	service.buffer = "#! keys before\nvar member"
	_check("unsaved metadata", service.get_script_metadata(P).member.keys.args, "before")
	service.get_script_metadata(P)
	_check("unchanged content reuses metadata", handler.calls, 1)
	service.buffer = "#! keys after\nvar member\n#! unknown"
	_check("unsaved edits invalidate metadata", service.get_script_metadata(P).member.keys.args, "after")
	_check("unknown EOF tag available without handler", service._get_entries(P).size(), 2)
	service.buffer = "var different"
	_check("removed tag clears metadata", service.get_script_metadata(P), {})
	_check("removed tag clears index", service._registry.get_entries("keys"), [])
	service.buffer = "#! keys restored\nvar member"
	service.get_script_metadata(P)
	service._on_filesystem_changed()
	_check("filesystem invalidates sources and indexes", [service._sources, service._registry.get_entries("keys")], [{}, []])
	_check("empty path is safe", [service.get_script_metadata(""), service._get_entries("")], [{}, []])
	service.free()


static func _test_singleton() -> void:
	var existed:bool = Service.instance_valid()
	var service = Service.get_instance()
	var handler := Handler.new()
	service._cache["sentinel"] = true
	Service.register_tag_parser(TAG, handler)
	_check("registration visible through new API", Service.get_tag_parser(TAG), handler)
	_check("registration clears metadata cache", service._cache, {})
	_check("legacy member lookup", Service.get_metadata_for_type(FIXTURE + "::member", TAG)[TAG].args, "value")
	_check("legacy class lookup", Service.get_metadata_for_type(FIXTURE + ".Inner::Inner", TAG)[TAG].args, "class")
	_check("legacy function lookup", Service.get_metadata_for_type(FIXTURE + ".Inner::method", TAG)[TAG].args, "argument")
	_check("occurrence query filters by tag", Service.get_tag_entries(FIXTURE, TAG).size(), 3)
	_check("unknown occurrence filter", Service.get_tag_entries(FIXTURE, "absent"), [])
	var parser = GDScriptParser.new()
	parser.set_script_path(FIXTURE)
	parser.set_source_code("#! tag_parser_service_test buffer\nvar member")
	_check("legacy parser-buffer API reads unsaved text", service.parse_script_metadata(parser).member[TAG].args, "buffer")
	parser.code_edit.free()
	service._cache["sentinel"] = true
	Service.unregister_tag_parser(TAG)
	_check("unregistration visible", Service.get_tag_parser(TAG, false), null)
	_check("unregistration clears metadata cache", service._cache, {})
	var active = service._current_script_path()
	if active.is_empty():
		_check("no active script occurrence query", Service.get_tag_entries(), [])
	else: # a script open in the editor answers the pathless query
		_check("occurrence query defaults to the active script", Service.get_tag_entries(), Service.get_tag_entries(active))
	_check("no active script metadata query", Service.get_tag_metadata(TAG), null)
	_check("missing file metadata query", service.get_script_metadata("res://absent_tag_test.gd"), {})
	Service.clear_cache()
	_check("legacy cache reset clears all layers", [service._cache, service._sources], [{}, {}])
	if not existed:
		service.free()


static func _check(label:String, actual:Variant, expected:Variant) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failures.append("FAIL %s: expected %s, got %s" % [label, expected, actual])
