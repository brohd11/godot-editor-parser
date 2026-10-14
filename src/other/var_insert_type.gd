#! namespace EditorParser.Other class VarInsertType
#! strip-cast GDScriptParser

const TagParser = preload("uid://mjs2johce5hs") #! resolve EditorParser.TagParser
const EditorGDScriptParser = preload("uid://t2dewmuth0sy") #! resolve EditorParser.EditorGDScriptParser

const MemberParse = preload("uid://ccgs5uvjcchb1") #! resolve GDScriptParser.MemberParse
const Keywords = MemberParse.Keywords

const UString = preload("uid://dce8d0wuh35gs") #! resolve UtilR.Strings.UString
const USignal = preload("uid://d4jphy4ihsgmc") #! resolve UtilR.Signals.USignal

static var type_hint_regex:RegEx

static func tets_scrip() -> void:
	var parser:GDScriptParser = EditorGDScriptParser.get_parser()
	format_script(parser, ScriptEditorRef.get_current_code_edit())


static func infer_single_line(parser:GDScriptParser, script_editor:CodeEdit, idx:int):
	var code_edit_parser:GDScriptParser.CodeEditParser = parser.get_code_edit_parser()
	var untyped_line_data:Dictionary = {}
	var line_type_data:Dictionary = check_type_in_line(code_edit_parser, idx)
	if not line_type_data:
		return 
	untyped_line_data[idx] = line_type_data
	
	insert_types(parser, script_editor, untyped_line_data)


static func format_script(parser:GDScriptParser, script_editor:CodeEdit):
	var code_edit_parser = parser.get_code_edit_parser()
	var untyped_lines = {}
	var i = 0
	for _i in range(script_editor.get_line_count()):
		if i >= script_editor.get_line_count():
			break
		
		var text = script_editor.get_line(i)
		var stripped_text = text.strip_edges()
		if MemberParse.get_line_declaration(stripped_text).is_empty() and not stripped_text.begins_with("for "):
			i += 1
			continue
		var line_data = check_type_in_line(code_edit_parser, i)
		if line_data.is_empty():
			i += 1
			continue
		untyped_lines[i] = line_data
		var end_i = line_data.get("context").get(GDScriptParser.Keys.CONTEXT_END)
		i = end_i + 1
	
	#print(untyped_lines)
	insert_types(parser, script_editor, untyped_lines)


static func check_type_in_line(code_edit_parser:GDScriptParser.CodeEditParser, line_i:int) -> Dictionary:
	var context_data:Dictionary = code_edit_parser.get_line_context(line_i)
	var stripped_l:String = context_data.get(GDScriptParser.Keys.CONTEXT_TEXT).strip_edges()
	var dec:StringName = MemberParse.get_line_declaration(stripped_l)
	var member_info = null
	
	if dec == &"":
		if not stripped_l.begins_with("for "):
			return {}
		else:
			dec = Keywords.FOR
	if dec == Keywords.VAR or dec == Keywords.STATIC_VAR:
		var type_info:Array = MemberParse.get_var_or_const_info(stripped_l, false)
		if type_info[1] != "":
			return {}
		member_info = type_info
	elif dec == Keywords.FUNC or dec == Keywords.STATIC_FUNC:
		if UString.string_safe_count(stripped_l, "->") != 0:
			return {}
		member_info = MemberParse.get_func_info(stripped_l)
	elif dec == Keywords.FOR:
		
		var type_info:Array = MemberParse.get_for_loop_info(stripped_l)
		if type_info[1] != "":
			return {}
		member_info = type_info
	
	if member_info != null:
		return {
			"context": context_data,
			"declaration": dec,
			"member_info": member_info
		}
	return {}


static func insert_types(parser:GDScriptParser, script_editor:CodeEdit, untyped_line_data:Dictionary):
	var sig_list = USignal.disconnect_signals_of_name(script_editor, "text_changed")
	_insert_types(parser, script_editor, untyped_line_data)
	USignal.connect_signals_from_list(script_editor, sig_list)

static func _insert_types(parser:GDScriptParser, script_editor:CodeEdit, untyped_line_data:Dictionary):
	var action_started:bool = false
	
	var line_idxes:Array = untyped_line_data.keys()
	for i:int in line_idxes:
		var data:Dictionary = untyped_line_data[i]
		var context_data:Dictionary = data.get("context")
		var dec:String = data.get("declaration")
		var member_info:Variant = data.get("member_info")
		
		var start_idx:int = context_data.get(GDScriptParser.Keys.CONTEXT_START)
		var end_idx:int = context_data.get(GDScriptParser.Keys.CONTEXT_END)
		var multiline:bool = start_idx != end_idx
		
		var target_line_idx:int = -1
		var target_line_new_text:String = ""
		
		if dec == Keywords.VAR or dec == Keywords.STATIC_VAR or dec == Keywords.FOR:
			var nm:String = member_info[0]
			var type_access_path:String = get_type_access_path(parser, nm, i + 1)
			if type_access_path == "":
				continue
			
			var line_text:String = script_editor.get_line(i)
			var insert_idx:int = line_text.find(nm) + nm.length()
			var insert_text:String = ":" + type_access_path
			var left_side_text:String = line_text.substr(0, insert_idx)
			
			var right_side_delim:String = "="
			if dec == Keywords.FOR:
				right_side_delim = "in"
			
			var delim_idx:int = line_text.find(right_side_delim, insert_idx)
			if delim_idx == -1:
				print("Could not complete insertion::", line_text)
				continue
			
			var right_side_text:String = line_text.substr(delim_idx)
			target_line_new_text = left_side_text + insert_text + " " + right_side_text
			target_line_idx = i
			
		elif dec == Keywords.FUNC or dec == Keywords.STATIC_FUNC:
			var class_obj:GDScriptParser.ParserClass = parser.get_class_object(parser.get_class_at_line(start_idx)) as GDScriptParser.ParserClass
			if not is_instance_valid(class_obj):
				continue
			
			var func_nm:String = member_info.get(MemberParse.Keys.FUNC_NAME)
			var type_access_path:String = get_type_access_path(parser, func_nm + "()", class_obj.declaration_line)
			if type_access_path == "":
				continue
			
			var target_line:int = start_idx
			if multiline:
				for ni:int in range(end_idx, start_idx - 1, -1): # work backwards
					var line_text:String = script_editor.get_line(ni)
					var colon_idx:int = UString.string_safe_rfind(line_text, ":")
					if colon_idx > -1:
						line_text = line_text.substr(0, colon_idx).strip_edges()
						if line_text.ends_with(")"):
							target_line = ni
							break
			
			var target_line_text:String = script_editor.get_line(target_line)
			
			var col_idx:int = UString.string_safe_rfind(target_line_text, ":")
			var end_text:String = target_line_text.substr(col_idx)
			target_line_text = target_line_text.left(col_idx).strip_edges(false)
			target_line_text = target_line_text + " -> " + type_access_path + end_text
			
			target_line_idx = target_line
			target_line_new_text = target_line_text
		
		
		if target_line_idx == -1 or target_line_new_text == "":
			continue
		
		if not action_started:
			#push_warning("START ACTION")
			action_started = true
			script_editor.start_action(TextEdit.ACTION_TYPING)
		
		script_editor.set_line(target_line_idx, target_line_new_text)
	
	if action_started:
		#push_warning("END ACTION")
		script_editor.end_action()
	
	script_editor.update_code_completion_options.call_deferred(false)


static func get_type_access_path(parser:GDScriptParser, expression:String, line:int) -> String: # preserve comments
	var type_rich:Dictionary = parser.resolve_expression_to_type_rich(expression, line)
	var inferred_type:String = type_rich.type
	#print("HERE::",expression, "->", inferred_type)
	
	# these ones operate on the member line dec itself, not the next up
	var type_data:Dictionary = parser.get_code_edit_parser().get_type_from_line(line - 1)
	#print(type_data)
	if type_data and type_data.get(GDScriptParser.Keys.TYPE) == "var":
		var type_array:Array = type_data.get("result")
		var assignment:String = type_array[2]
		var tag_parser = TagParser.get_tag_parser("keys")
		if tag_parser:
			var adjusted_string:String = tag_parser.resolve_tagged_expression(assignment, line - 1)
			if adjusted_string:
				inferred_type = parser.resolve_expression_to_type(adjusted_string, line - 1)
				#print("ADJ STRING::TYPE", "::", adjusted_string, " -> ", inferred_type)
	
	#print("HERE::",inferred_type)
	if inferred_type == "":
		return ""
	
	inferred_type = inferred_type.trim_suffix(GDScriptParser.Keys.INS_DELIM)
	if not MemberParse.is_absolute_path(inferred_type):
		if inferred_type.ends_with(GDScriptParser.Keys.ENUM_PATH_SUFFIX): # these are handled
			return inferred_type.trim_suffix(GDScriptParser.Keys.ENUM_PATH_SUFFIX)
		
		var member_name:String = GDScriptParser.Utils.type_path_get_member(inferred_type)
		if member_name == "":
			return inferred_type
		var non_member:String = GDScriptParser.Utils.type_path_get_non_member(inferred_type)
		if non_member != "":
			var current_script = ScriptEditorRef.get_current_script()
			if ClassDB.is_parent_class(non_member, current_script.get_instance_base_type()):
				non_member = ""
		return UString.dot_join(non_member, member_name)
	else:
		var current_class:String = parser.get_class_at_line(line)
		var class_obj:GDScriptParser.ParserClass = parser.get_class_object(current_class) as GDScriptParser.ParserClass
		var preload_check:Variant = class_obj.has_preload(inferred_type)
		var access_string:String = ""
		if preload_check != null:
			access_string = preload_check
		else:
			var access_object:GDScriptParser.TypeLookup.AccessObject = parser.resolve_to_access_object(expression, line)
			var access_options:GDScriptParser.Access.AccessOptions = parser.get_access().find_path_to_type_simple(class_obj, access_object, inferred_type)
			
			#print(access_options.standard)
			#print(access_options.script_alias)
			#print(access_options.global)
			
			if access_options.standard != "":
				var access_check:String = parser.resolve_expression_to_type(access_options.standard, line)
				if access_check == inferred_type:
					access_string = access_options.standard
			
			if access_string != "":
				pass
			elif access_options.script_alias != "":
				access_string = access_options.script_alias
			elif access_options.global != "":
				access_string = access_options.global
			else:
				return ""
			
			
			
		return access_string
	
	
	return ""
