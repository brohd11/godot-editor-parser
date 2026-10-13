extends RefCounted
## ParserWarmup - project-wide disk-cache warmup sweep.
##
## Enumerates every project .gd, builds a fresh LIVE parse of each, resolves its public surface, then
## write_cache()s it. Two depths:
##   shallow (default) - members, constants, function return types (what other scripts consume).
##   full              - shallow + mapped function locals + argument types.
## Never-opened utility / third-party scripts don't need their locals warmed (irrelevant unless you
## edit inside them; files you actually open get locals populated naturally via outline / completion),
## so shallow is the default - smaller caches, skips the expensive map_variables() body scan.
##
## Fresh parse (not the disk-cached parser) guarantees completeness: a partially-cached parser can
## have only one member resolved and its funcs flagged already-mapped, so reusing it would leave gaps.
## Runs on parsers isolated from the editor's live cache; the shared artifact is the on-disk dir.
## Non-blocking: drains WARMUP_PER_FRAME scripts per frame, awaiting a process_frame between batches.

const GetFiles = preload("uid://b3p6nfmpcltt0") #! resolve ALibRuntime.Utils.UFile.GetFiles
const WARMUP_PER_FRAME := 3 # scripts resolved per frame before yielding (parse is heavy; keep small)

var running := false


## Sweep the whole project. `cache_dir` = the parse-cache dir to write into; `tree` paces the drain;
## `full` also warms function locals + args (default shallow = public surface only).
func run(cache_dir:String, tree:SceneTree, full:bool = false) -> void:
	if running:
		return
	running = true

	var cache:Dictionary = {} # shared across the sweep so dependency sub-parsers are reused
	var paths:Array = GetFiles.scan("res://", ["gd"])
	print("ParserWarmup: sweeping %d scripts (%s) -> %s" % [paths.size(), "full" if full else "shallow", cache_dir])

	var warmed := 0
	var count := 0
	for path in paths:
		if _warmup_one(cache, cache_dir, path, full):
			warmed += 1
		count += 1
		if count % WARMUP_PER_FRAME == 0:
			await tree.process_frame

	print("ParserWarmup: done - %d scripts warmed" % warmed)
	running = false


## Fresh-parse one script, resolve it to the requested depth, persist. Returns false if unresolvable.
func _warmup_one(cache:Dictionary, cache_dir:String, path:String, full:bool) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var script:GDScript = load(path)
	if not is_instance_valid(script):
		return false

	var p:GDScriptParser = GDScriptParser.new()
	p.set_autoload_cache()
	p.set_parser_cache(cache)
	p.set_parser_cache_size(40)
	p.set_parse_cache_dir(cache_dir)
	p.active_parser = p
	p.set_current_script(script)
	p.set_source_code(script.source_code)
	p.parse()

	_resolve_all(p, full)
	p.write_cache()
	return true


## Resolve the public/cross-script surface (members, constants, function return types AND argument
## types - all of which other scripts consume for completion & signature help) always. Function
## *locals* are internal - only relevant when editing the file - so they're warmed only in `full`.
## In shallow mode, drop each func's structural local-var data before persisting (tree-sitter parse
## populates local_vars even without map_variables); files you actually open re-map via their own
## live parser, so this saves inference time and disk. Runs on a fresh LIVE parser so map_variables()
## can scan the bodies in full mode.
func _resolve_all(p:GDScriptParser, full:bool) -> void:
	for access_path in p.get_classes():
		var class_obj:GDScriptParser.ParserClass = p.get_class_object(access_path)
		if not is_instance_valid(class_obj):
			continue
		for member_name in class_obj.members.keys():
			class_obj.get_member_type_rich(member_name)
		for const_name in class_obj.constants.keys():
			class_obj.get_member_type_rich(const_name)
		for func_name in class_obj.functions.keys():
			var func_obj:GDScriptParser.ParserFunc = class_obj.functions[func_name]
			if not is_instance_valid(func_obj):
				continue
			func_obj.get_return_type_rich()
			for arg_name in func_obj.arguments.keys(): # public signature -> always warmed
				func_obj.get_local_var_type_rich(arg_name)
			if full:
				func_obj.map_variables() # legacy local-var mapping (body scan)
				for lv_name in func_obj.local_vars.keys():
					func_obj.get_local_var_type_rich(lv_name)
			else:
				func_obj.local_vars.clear() # internal locals: not needed cross-script, drop to stay lean
