# MAGE:EDITOR

Standalone Godot 4.7 desktop authoring tool for MAGE packs. `src/workspace.gd` manages one writable pack and read-only references; `src/document.gd` preserves source text and writes files; `src/story_graph.gd` applies source-aware story operations; `src/story_canvas.gd` and `src/visual_details.gd` implement the author-facing visual interface. `launch.py` stages the editor with the selected MAGE checkout's content library in a temporary project. Do not fork the engine parser, schema or validator into this repository.

`src/editor_theme.gd` supplies MAGE Dark and Cream Light palettes. `src/event_triggers.gd` supplies named place/zone trigger controls shared by creation and event details. The world-map inspector shows event scope and eligibility; its counts describe associations, not a running game's eligible events. `PackWorkspace.preview_content()` uses the engine's loader operations on unsaved buffers for current merged definitions.

`src/authoring_layout.gd` supplies the shared section navigation, focused page and persistent summary used by Details, creation and action choosers. Keep incomplete structured entries on their page until applied; new interaction drafts create source only when applied. Response-linked story creation must preserve the originating script field and refuse a stale source snapshot.

`src/saved_value_row.gd` supplies guided saved-value declarations, using the selected engine loader to read existing kinds and numeric limits. Preserve unedited declaration spelling and protect nested metadata. Structured entry drafts have inline errors, stale-source checks and an explicit discard action.

`src/authoring_catalog.gd` adds author-facing labels, categories and help over the shared schema and effect compiler. Properties must include existing fields and script interactions. Item use controls distinguish food infection from scripted mutation and prevent mixing a use story with a built-in activity. Selecting food mutation alone creates an empty use program so the item is usable.

The authoring goal is visual creation of all supported pack content, without requiring authors to learn the underlying scripting format. Use speech bubbles, response connectors and clear action/condition controls. Keep technical views optional while visual coverage is incomplete.

Preserve comments, attribution, unfamiliar fields, conditions, actions, links and other source text. Never modify reference packs. Refuse an operation if it cannot be applied without losing existing behavior. Treat IDs as save and cross-pack references. Validate unsaved buffers with the shared engine and report errors with their original paths.

Run `./run.sh --engine /path/to/MAGE`. The project is early development; do not represent its visual coverage or game preview as feature-complete.
