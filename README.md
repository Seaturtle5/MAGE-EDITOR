# MAGE:EDITOR

MAGE:EDITOR is an offline desktop tool for creating MAGE content packs. It is designed for authors to build stories and game content visually. Work on one pack and load other packs as read-only references.

The editor is in early development. The story board and details forms cover common authoring tasks; visual coverage is not complete yet. Existing content that cannot be edited safely is preserved.

## Start

Install Godot 4.7 and Python 3, then run:

```sh
./run.sh --engine /path/to/MAGE
```

`--engine` points to a MAGE checkout containing `engine/`. You can instead set `MAGE_ENGINE`; the launcher also checks a sibling engine folder. To use another Godot executable, set `GODOT` or pass `--godot /path/to/godot`.

The editor stages a copy of the selected engine's content library in a temporary directory. It uses that checkout's parser, schema and validator without modifying the engine. If the example adventure is available, the first launch creates a separate working copy in the editor's user data folder.

## Work on a pack

| Action | How |
|---|---|
| Choose appearance | Use **MAGE Dark / Cream Light** in the top bar. The choice is remembered on this computer. The editor uses MAGE's Barlow interface and Literata story fonts when available in the selected engine checkout; their licences are included with those fonts. |
| Start or open | Open the **Pack** menu to create or open a pack. The example adventure opens in an editor-owned working copy on first launch. |
| Create content | Choose **+ Create** and follow **Starting point → Name & opening → Review**. Write an optional opening passage before creating a story, conversation or event. The summary stays visible and Back keeps your draft. An ID is suggested automatically; **More types and ID options** exposes technical choices. |
| Find content | Choose a content tab and select an entry from your working pack. **Details** has section navigation, Back/Next controls and a persistent **At a glance** summary. Events have separate trigger and condition sections. **Stories** lists searchable interactions; **Add property** opens one property at a time. Story entries open on the board. Find other packs in the library. |
| Write a conversation | Write in speech bubbles and response cards. Add or remove responses, add conditions or actions, and create single-line variations and conditional text. |
| Start an interaction | In **Details → Stories**, choose an interaction. A missing plain story opens the writing space directly; applying it creates the passage. Cancelling leaves the source unchanged. |
| Write longer passages | Choose **Open writing space** below a plain speech or narration bubble. Write and apply several paragraphs in the larger window; cancelling an edited draft asks before discarding it. |
| Connect stories | Use **Choose next story** on a response to connect an existing passage or create a new story that is linked automatically. You can also drag a response connector to a destination. Drag an automatic continuation or play-and-return connector to change it; right-click a connection to disconnect it. Node positions are saved locally. |
| Explore places | Open **World map** or choose **Places**. Select a place or its event count to see a side panel of events, people and items. Event cards explain the trigger, requirements and repeat rule; zone events are labelled separately. Drag between places to add a directional exit; right-click a connection to choose an exit to remove. A return exit is created separately. |
| Add an event to a place | Choose **+ Add event here** on a place card. The place is selected for you. Choose walking, arrival, fast travel, leaving, exploring, scavenging or a story-started event. Zone triggers apply throughout the selected zone. The creation flow starts at **Name & opening** with the place selected. After creation, use the event’s **When & where**, **Conditions** and **Stories** sections. |
| Adjust an event | Open the event's **Details**. **Change when & where** offers named places and zones; add another trigger for an alternative way to start it. **Add condition** offers time, items, flags and quest stages. Additional conditions must all pass. **Stories → Event story** opens the story board. Leaving events interrupt the exit; use the **Continue the move** story action when the player should leave. Cross-pack destinations and conditions add their pack dependency. |
| Find a property | In **Details → Properties**, search by name or purpose and filter by category. Existing and available properties appear together, with explanations and controls. Browsing changes nothing. |
| Make food heal or mutate | Open the item's **Use & reactions**, then **+ Add reaction → Restore health** and choose an amount. Hunger, thirst, damage and attribute changes use the same chooser. **Food mutation → Choose mutation form** selects a loaded form and respects food-infection protections. Scripted gradual mutation and full transformation are separate choices under **Body changes**. |
| Review item behavior | **Use & reactions** shows story text, reactions and their conditions in order. Click a reaction to replace it or choose **Remove**. **Consumption & combat settings** controls whether one item is used up and whether it can be used in a fight. Food is used up by default; no extra take-item action is needed. |
| Add story steps | Use the buttons on a node to add speech, a response, an action, a pause, or a story to play and return from. Action and condition choosers have categories, search and a preview of their scope. Item and number changes have an amount control. Number conditions offer at least, at most and equal thresholds; time controls record a moment and check turns passed, and lists can be checked for entries. Unrecorded times count as long ago. Nothing is added until confirmed. |
| Use another pack | **Pack → Add reference pack** loads its definitions read-only. **Show library** opens a searchable panel with pack filters, values and problems. Reference selectors and story actions can use other packs and add the dependency to your working pack. |
| Create saved values | In **Details → Settings**, edit a values section with Flag, Number, Text, Time, States and List controls. Each explains its starting behavior; numbers have optional normal and fight limits. Apply entries before leaving, or choose **Discard entry edits**. Errors stay beside your draft. |
| Add art | **Import image** copies an image into the working pack and adds an artist credit. |
| Check and save | **Check pack** checks the loaded packs, including unsaved changes, using the engine and opens the problems panel. **Save all** writes changed files in the working pack. |

Imported images are copied immediately; content changes stay in memory until saved. Saving stops if a content file changed on disk since it was opened. Save operations across several files are not one transaction.

## Current limits

The board can edit plain text passages, create and edit common single-line variations, manage common response conditions and actions, and change existing direct and play-and-return links. The larger writing space currently edits plain passages; complex dynamic passages still need further visual controls. The world map shows direct exits and dangerous doors, but does not yet edit doors or game map coordinates. Event controls cover the engine's common place and zone triggers; unfamiliar clauses and complex source layouts are preserved. Hooks and events started only by stories are not included in place event counts. Conditional and fight branches, engine actions, and nested properties are not all visually editable yet. Unsupported content is preserved. Node positions on either board are stored on this computer and do not change the game's map coordinates. A game playtest and coordinated ID renaming are not available yet. The optional **Advanced** switch exposes technical views during development; they are not the intended authoring workflow.
