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
| `workspace.gd`, `document.gd`, `edit_history.gd`, `autosave.gd` | One writable pack plus read-only references; source-preserving documents; workspace-wide undo; recovery drafts. `preview_content()` loads unsaved buffers with the engine's loader; `validate()` runs the engine's validator on a snapshot. `uses_index()` lists where each ID is meant (not prose) in the working pack. |
| `block_catalog.gd` | Every engine action and condition as a sentence with typed slots. A line is read only when the engine's first matching rule is the entry's rule and rendering the slots gives the same line. Add an entry for each new engine rule; keep entries in the engine's rule order where patterns overlap. |
| `slot_control.gd`, `picker_button.gd`, `sentence_view.gd` | One control per slot kind (content, value, amount, calculation, choice, switch, text); a searchable picker that takes library drops; a sentence drawn as words and chips. |
| `block_chooser.gd`, `condition_builder.gd`, `condition_dialog.gd` | "What should happen?" and "When?": everyday-word search, context filtering, fill-in, quick add; conditions as All / Any / None groups. |
| `story_editor.gd`, `story_blocks.gd`, `story_graph.gd`, `preview.gd` | The side editor of blocks; block-level source operations; older story operations and `structure()`; the engine-rendered text preview with sample players (it skips actions and is not a playtest). |
| `story_canvas.gd`, `world_canvas.gd`, `visual_details.gd`, `event_triggers.gd`, `saved_value_row.gd`, `attribute_bonus_row.gd`, `authoring_catalog.gd`, `authoring_layout.gd` | The story board (summary cards), the map, and the Details forms with their helpers. The Details forms and the pickers in `story_canvas.gd` predate the block catalog and should move onto it. |
| `templates.gd`, `templates/`, `task_wizard.gd`, `pack_home.gd` | Guided tasks as data: `.fsc` with `{{placeholders}}` and a header of pages and questions. Game templates show only with the `core-mechanics` pack loaded and hold no story text. |
| `content_tools.gd`, `content_actions.gd` | Rename everywhere (prose untouched, taken back if it would break references), duplicate, delete with its consequences, where-used, the quest view. `ContentTools.map_code` decides which parts of a line hold IDs; rename and the uses index share it. |
| `main.gd`, `command_palette.gd`, `drop_menu.gd`, `drag_payload.gd`, `editor_theme.gd`, `editor_prefs.gd`, `wording.gd` | The window (top bar, library, Home / Stories / Map / Details, side editor, status line), Find anything, drops, themes and category colours, remembered settings, the wording table. |

The product documentation must say plainly what is not finished. Run `./run.sh --engine /path/to/MAGE`.
