# MAGE:EDITOR

Standalone Godot 4.7 desktop authoring tool for MAGE packs. Authors build all pack content visually; the content format stays the only source and the engine stays the only grammar. `launch.py` stages the editor with the selected MAGE checkout's content library in a temporary project. Do not fork the engine parser, schema or validator into this repository.

## Rules

- Write `.fsc` text and check it with the engine: `Effect.compile`, `Condition.compile`, `FscParser`, the validator. Never accept a line the engine rejects.
- Never lose source. Preserve comments, attribution, unfamiliar fields, line endings and everything outside the exact range an operation changes. What cannot be shown as a control stays as a protected "kept" block.
- Never modify reference packs. Using another pack's content adds the dependency.
- Every change is one labelled undo step: wrap it in `workspace.transaction(label, callable)` and return an error text to roll back.
- Operations take the text snapshot the author was looking at and refuse to act when the document changed since.
- Every drag has a keyboard or menu alternative. Every colour has an icon.
- Plain words first: an author never needs to know the content format. Names for things come from `wording.gd`; the optional "Show the line" reveals the format.
- Statically typed GDScript; an inferred Variant is an error.

## Structure (`src/`)

| File | Job |
|---|---|
| `workspace.gd`, `document.gd`, `edit_history.gd`, `autosave.gd`, `perf.gd` | One writable pack plus read-only references, loaded and checked on other threads; source-preserving documents parsed in part after a change; workspace-wide undo; recovery drafts; step timings. `preview_content()` loads unsaved buffers with the engine's loader; `validate()` runs the engine's validator. `uses()` lists where an ID is meant (not prose) in the working pack. See Speed below. |
| `block_catalog.gd` | Every engine action and condition as a sentence with typed slots. A line is read only when the engine's first matching rule is the entry's rule and rendering the slots gives the same line. Add an entry for each new engine rule; keep entries in the engine's rule order where patterns overlap. |
| `slot_control.gd`, `picker_button.gd`, `sentence_view.gd` | One control per slot kind (content, value, amount, calculation, choice, switch, text); a searchable picker that takes library drops; a sentence drawn as words and chips. |
| `block_chooser.gd`, `condition_builder.gd`, `condition_dialog.gd` | "What should happen?" and "When?": everyday-word search, context filtering, fill-in, quick add; conditions as All / Any / None groups. |
| `story_editor.gd`, `story_blocks.gd`, `story_graph.gd`, `preview.gd` | The side editor of blocks; block-level source operations; older story operations and `structure()`; the engine-rendered text preview with sample players (it skips actions and is not a playtest). |
| `story_canvas.gd`, `world_canvas.gd`, `visual_details.gd`, `event_triggers.gd`, `saved_value_row.gd`, `attribute_bonus_row.gd`, `authoring_catalog.gd`, `authoring_layout.gd` | The story board (summary cards), the map, and the Details forms with their helpers. The Details forms and the pickers in `story_canvas.gd` predate the block catalog and should move onto it. |
| `templates.gd`, `templates/`, `task_wizard.gd`, `pack_home.gd` | Guided tasks as data: `.fsc` with `{{placeholders}}` and a header of pages and questions. Game templates show only with the `core-mechanics` pack loaded and hold no story text. |
| `playtest.gd` | Starts the real game (the engine checkout in `MAGE_ENGINE_PATH`, set by `launch.py`) with `--only-packs --packs … --data …` on the working pack, or on a copy that holds the unsaved buffers, and the reference packs in place. Never point the game at the player's saves, and never write into a pack to try it. |
| `content_tools.gd`, `content_actions.gd` | Rename everywhere (prose untouched, taken back if it would break references), duplicate, delete with its consequences, where-used, the quest view. `ContentTools.map_code` decides which parts of a line hold IDs; rename and the uses index share it. |
| `main.gd`, `content_library.gd`, `command_palette.gd`, `drop_menu.gd`, `drag_payload.gd`, `editor_theme.gd`, `editor_prefs.gd`, `wording.gd` | The window (top bar, library, Home / Stories / Map / Details, side editor, status line), the library tree (an entry opens when the pointer is let go in place, so it can be dragged), Find anything, drops, themes and category colours, remembered settings, the wording table. |

## Speed

An edit must be back on screen at once, in a file of a megabyte with sixty packs loaded. Measure before and after (`MAGE_PERF=1` prints the steps' times, see `perf.gd`), on a real large pack, and keep every refresh proportional to what changed:

- **Documents** (`document.gd`): `text` raises `version` on every change; lines, line starts, definition ranges and the unsaved state are worked out once per version. After a change only the definitions around the changed lines are parsed again (`_reparse`): the ones above are kept and the ones below are moved to their new line numbers in place. Never walk a file's text in a script loop, and never keep a line number across a change.
- **Rows** (`workspace.gd`): rows of unchanged files stay the same objects; only a changed file's rows are made again, and the list is patched in place when no definition came or went. Rows are shared: put `script_field` on a copy, never on a row. `find_row`, `rows_with_id`, `rows_under`, `links_touching`, `uses`, `is_used`, `problems_at` answer from indexes; do not loop over `rows` or `diagnostics` in a refresh.
- **Per-block caches**: what is read from a definition's text (the IDs it mentions, its story links, the quick check's findings) is kept per block text, so one edit reads one block again.
- **Loaded content** (`base_content()`, `preview_content()`): the other packs are loaded into one `ContentDB` once; every preview and check loads only the working pack onto a layer of it (the engine's `ContentDB.layer()`). The engine copies a definition before an extension changes it (`protect_definitions`), so parsed definitions stay as written.
- **Checks**: `check_working()` (parser and story compiler, changed files only) runs at once; `request_check()` runs the engine's validator on another thread (the working pack's scripts, or with `true` every pack's) and emits `checked`; the window calls `poll()` every frame to take results. Tests use the same code without threads: `validate()`, `add_references()`, and `settle()` to wait. The check thread parses the working pack for itself: the window's own parse moves with every edit.
- **Other packs** load on another thread (`load_packs()`, `read_packs()` parses on all processors), found by `packs_beside()`.
- **The window**: pages not in view are not drawn (`VisualDetails.stale`, the technical views); the library is filled again only when its list changes; the board draws again only the cards whose content changed and at most `MAX_CARDS`; the side editor draws the blocks in view at once and the rest over the next frames (`StoryEditor.waiting`, `complete()` before looking a panel up).
- Wrapped text must have a width before it gets its text (`AuthoringLayout.label` sets one): without it a long paragraph is first laid out one letter per line. Text with a symbol the interface font lacks is slow to build unless the theme names a fallback (`EditorTheme.symbol_fonts()`), and fallbacks raise line heights unless trimmed (`EditorTheme.font()`).

The product documentation must say plainly what is not finished. Run `./run.sh --engine /path/to/MAGE`.
