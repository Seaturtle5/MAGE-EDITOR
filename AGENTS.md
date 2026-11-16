# MAGE:EDITOR

Standalone Godot 4.7 desktop authoring tool for MAGE packs. `src/workspace.gd` manages one writable pack and read-only references; `src/document.gd` preserves source text and writes files; `src/story_graph.gd` applies source-aware story operations; `src/story_canvas.gd` and `src/visual_details.gd` implement the author-facing visual interface. `launch.py` stages the editor with the selected MAGE checkout's content library in a temporary project. Do not fork the engine parser, schema or validator into this repository.

`src/edit_history.gd` journals workspace text snapshots. Use `workspace.transaction(label, callable)` for operations spanning multiple files or adding dependencies; return an error string to roll back. Ordinary document changes are captured at reindex. `src/autosave.gd` keeps applied edits separately from explicit saves; never overwrite an unresolved recovery draft or bypass external-file checks.

`src/pack_home.gd`, `src/task_wizard.gd` and `src/templates.gd` share data-driven creation. Templates live in `src/templates/`; game templates are gated by the loaded `core-mechanics` pack. Keep placeholder stories generic. `src/drag_payload.gd` carries stable typed references; `src/drop_menu.gd` proposes an operation before changing source. Drop targets must keep their picker/button alternatives.

`src/story_editor.gd` is the board's source-aware side editor. `StoryGraph.structure()` provides ranges for nested blocks; require the original text snapshot for structural operations. Unsupported blocks and comments must remain protected. `src/block_catalog.gd` supplies sentence entries checked by the engine compiler; incomplete catalog coverage must stay visible in the product documentation. `src/condition_builder.gd` composes guided groups. `src/preview.gd` uses engine text/condition evaluation on disposable sample state and skips actions; it is not a playtest.

`src/editor_theme.gd` supplies MAGE Dark and Cream Light palettes. `src/event_triggers.gd` supplies named place/zone trigger controls shared by creation and event details. The world-map inspector shows event scope and eligibility; its counts describe associations, not a running game's eligible events. `PackWorkspace.preview_content()` uses the engine's loader operations on unsaved buffers for current merged definitions.

`src/authoring_layout.gd` supplies the shared section navigation, focused page and persistent summary used by Details, creation and action choosers. Keep incomplete structured entries on their page until applied; new interaction drafts create source only when applied. Response-linked story creation must preserve the originating script field and refuse a stale source snapshot.

`src/attribute_bonus_row.gd` uses the shared effect compiler for reversible condition bonuses. Only the six player attributes support relative temporary changes; preserve other effects and explain repeated healing separately. Story image controls use existing `show` steps and runtime pack/extension precedence. New story-wide effects go before the first direct response group; nested branches and existing actions retain their positions.

`src/saved_value_row.gd` supplies guided saved-value declarations, using the selected engine loader to read existing kinds and numeric limits. Preserve unedited declaration spelling and protect nested metadata. Structured entry drafts have inline errors, stale-source checks and an explicit discard action.

`src/authoring_catalog.gd` adds author-facing labels, categories and help over the shared schema and effect compiler. Properties must include existing fields and script interactions. Item use controls distinguish food infection from scripted mutation and prevent mixing a use story with a built-in activity. Selecting food mutation alone creates an empty use program so the item is usable.

The authoring goal is visual creation of all supported pack content, without requiring authors to learn the underlying scripting format. Use speech bubbles, response connectors and clear action/condition controls. Keep technical views optional while visual coverage is incomplete.

Preserve comments, attribution, unfamiliar fields, conditions, actions, links and other source text. Never modify reference packs. Refuse an operation if it cannot be applied without losing existing behavior. Treat IDs as save and cross-pack references. Validate unsaved buffers with the shared engine and report errors with their original paths.

Run `./run.sh --engine /path/to/MAGE`. The project is early development; do not represent its visual coverage or game preview as feature-complete.
