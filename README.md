# Editor Parser

Editor-side GDScript parsing services, under the `EditorParser` namespace:

- `EditorParser.EditorGDScriptParser` (`src/gdscript/editor_gdscript_parser.gd`): singleton that keeps a
  `GDScriptParser` synced with the active script editor buffer.
- `EditorParser.TagParser` (`src/tag/tag_parser.gd`): `#!` tag metadata service.

Both are lazily instanced singletons, so using one never instantiates the other.

## EditorGDScriptParser

Register from an EditorPlugin (`register_node(self)` / `unregister_node(self)`), then use
`EditorGDScriptParser.get_parser(path = "")` for the active (or a cached) parser. It reparses on
script validation and emits `editor_script_changed` / `parse_completed`. `warmup_project()` /
`warmup_project_full()` fill the persistent parse cache (`src/gdscript/warmup.gd`).

# Tag Parser

Shared GDScript `#!` tag discovery and indexing, plus an optional editor service.
The scanner and registry never preload the editor service, and have no editor
dependencies, so export-time tools (gdscript_optimizer, plugin_exporter) use them directly.

## Core API

```gdscript
const Registry = preload("res://addons/_lib/editor_parser/src/tag/registry.gd")

var registry = Registry.new()
registry.scan_files(["res://example.gd"])
var tags = registry.get_entries("inline")
registry.replace_source("res://example.gd", edited_text.split("\n"))
registry.invalidate("res://example.gd")
```

`scan_file` and `get_file_entries` read each file once per registry snapshot.
`replace_source` replaces a file's occurrences and indexes using supplied source
lines. `invalidate(path)` removes one snapshot; `clear()` removes all snapshots.
`get_entries(tag)` returns occurrences across scanned files. `has_tag(identity,
tag)` and `get_tag_data(identity, tag)` query file/member attachments; the latter
returns the first occurrence. Local, line, and unattached tags do not populate
the declaration index. Treat returned entries as read-only.

`Scanner.scan_lines(lines, path, owners = [])` scans without retaining a registry.
The optional `owners` array receives the enclosing class path of each source line,
preserving the optimizer's existing interface. `scan_code(line, state)` retains
the comment/string/continuation scanning interface used by struct rewriting.

## Grammar and locations

The grammar remains `#! tag mods; args`. Without a semicolon, a single value is
arguments, not modifiers. Bare tags and hyphenated names are accepted. The tag
must begin the actual comment; strings, triple-quoted text, and prose comments
mentioning a tag are excluded.

Every occurrence has `tag`, `mods`, `args`, `raw`, `file`, `line`, `column`,
`end_line`, `end_column`, `attach`, `identity`, `target`, `target_kind`,
`target_name`, `owner_class`, and `owner_function`. Lines and character columns
are zero-based; the end column is exclusive. Raw text retains trailing spaces
but excludes the line ending. UTF-8 byte offsets are not used.

- `file`: header tags separated from the first declaration by a blank line, or
  preceding `class_name`/`extends`. Identity is the script path.
- `member`: tags above class/member declarations, through comments and
  annotations. Class identities are `res://a.gd.Outer.Inner`; member identities
  are `res://a.gd.Outer::member`.
- `local`: tags above local declarations. They carry scope and target information
  but no class-member identity.
- `line`: trailing tags and tags within continued statements target their own
  line. Standalone tags before ordinary code target that statement's first line.
- `unattached`: no valid target in the same indentation/scope, including EOF.
  `target` is `-1` and `identity` is empty.

Tags retain source order and duplicates. No pending tag crosses a block or
function boundary. Enclosing named classes/functions are recorded where they can
be identified lexically; this is not a full GDScript syntax or expression parser.
Exact expression selection and inlining belong to consumers.

## Editor service and compatibility

The optional service is `src/tag/tag_parser.gd` (`EditorParser.TagParser`). It
keeps the `EditorTagParser` singleton name and uses util_r's CacheHelper, GDScriptParser
interfaces, and script-editor utilities. It follows the Singletons lifecycle and needs no
EditorPlugin registration. The optimizer's `tag_registry.gd` remains a compatibility entry point.

Existing handler registration and member-metadata APIs are preserved. Handlers
still receive `{mods, args}`, with duplicate arguments/modifiers joined by spaces.
Class metadata preserves the editor convention `Outer.Inner::Inner`; functions
and fields retain their existing member keys. Local and line tags are not passed
off as class-member metadata.

`get_tag_entries(path = "", tag = "")` exposes occurrences independently of
handler registration. An empty path selects the current editor script; no active
script returns an empty result. Active buffers are read directly, including
unsaved edits. Source changes and handler registration changes invalidate parsed
metadata; filesystem changes and `clear_cache()` invalidate all cached layers.

## Validation

From the development project:

```sh
godot --headless --path . --script res://tests/editor_parser/run_headless.gd
python3 tests/editor_parser/core_smoke.py --godot /path/to/Godot
```

The smoke test installs only the core and metadata adapter in a disposable
project, confirming they work without editor services or other addon libraries.
This repository is currently local; configure an actual remote before adding a
remote installation entry to the addon manifest.

## Structured options

Consumers can opt into `Scanner.Options.parse(entry.args)` (also available through
Registry). It returns `{options, errors}` without changing raw scanner metadata.
Options are flags or `key=value` strings separated by whitespace/commas; quoted values
may contain separators. Duplicate names and malformed input return errors and no
usable options. Each consumer validates its own supported names and value types.
For example, `#! inline; substitute` produces `{substitute: true}`.
