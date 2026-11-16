# MAGE:EDITOR

MAGE:EDITOR is an offline desktop tool for making MAGE content packs without learning the content format. You work on one pack and can load other packs to use their content. The editor writes ordinary pack files and checks them with the game engine itself.

The editor is in development. Stories, conversations, events and the common content types can be built visually; many settings of the rarer types are still typed. Content the editor cannot show yet is kept exactly as it is.

## Start

Install Godot 4.7 and Python 3, then run:

```sh
./run.sh --engine /path/to/MAGE
```

`--engine` points to a MAGE checkout containing `engine/`. You can instead set `MAGE_ENGINE`; the launcher also checks a sibling engine folder. To use another Godot executable, set `GODOT` or pass `--godot /path/to/godot`.

The editor uses the engine's own reader and checker from that checkout, without changing it. If the example adventure is available, the first launch opens a working copy of it.

## The window

| Where | What |
|---|---|
| Top bar | **Pack** (new, open, add another pack, import a picture), **Undo / Redo**, **Find anything** (Ctrl+K), **Create**, **Play**, the check result, and **Save**. The gear holds appearance, interface size and the technical views. |
| Library (left) | Everything in your pack by kind, and the other loaded packs folded away. Choose an entry to open it, or drag it into a story, onto the map or onto a matching picker. |
| Home | Guided tasks, what you worked on with hints about what it still needs, and problems. |
| Stories | The board: one card per story, with lines showing how they lead to each other. Select a card to see its blocks in the side editor. **Tidy up** arranges the cards. |
| Map | Places and the paths between them; what happens at each place. |
| Details | Everything about the selected content. The small buttons beside its name show where it is used, rename it everywhere, duplicate it and delete it. |
| Side editor (right) | The selected story as blocks, with a preview underneath. |
| Status line | What just happened, with **Undo**, and where you are. |

## Guided tasks

On Home, choose a task: talk to a character, something happens at a place, make an item, start a quest, add a place, open a shop, write an ending. With the Flexible Survival base pack loaded there are eight more. A task asks a few questions page by page and shows what it will make. A place or an area that does not exist yet can be made on the spot from only a name. **Create** makes everything, connected, as one step you can undo.

## Stories as blocks

Each block is a sentence. The highlighted parts are chips: choose one to change it, or drop a library entry on it.

| To | Do |
|---|---|
| Add | **+ Text**, **+ Action** or **+ More** at the place you want it. Action opens "What should happen?": search with everyday words (heal, trust, teleport), fill in the sentence, **Add** or **Add & next**. You can also type a line you know. |
| Write | Double-click a text block. **Insert** adds a name, he or she, or a counter's number; **Vary** and **Only if…** wrap the selected words. Ctrl+Enter keeps the text, Esc cancels. |
| Make it conditional | **⋯ → Only if…** puts the block (or all selected blocks) inside a condition. Conditions are built from sentences in groups: all of, any of, none of. Add **Otherwise, if…** and **Otherwise** from the condition's own menu. |
| Move | Drag the handle; hold Ctrl to copy. Or use **⋯ → Move up / Move down**, Alt+↑ / Alt+↓, or cut and paste. Shift-click and Ctrl-click select several blocks. |
| Copy between stories | Copy and paste work as lines of the content format, also to and from a text editor. |
| Understand | **⋯ → Explain** says what a block does. **Show the line** shows the content format's line under every block. |
| Preview | The strip under the blocks shows the text as a sample player reads it. Conditions are marked taken or skipped for that sample. Actions are not applied; the preview stops at responses, pauses, links and fights. |

Some actions only work in certain stories (a fight action, "keep the item"). They are hidden elsewhere; **Show all** lists them greyed out with the reason.

## Try it in the game

**▶ Play** in the top bar starts the real game on your pack as it is now, unsaved changes included, in its own window: from a starting point of the game, at the selected place, or straight into the story you are working on (**▶ Try it** above the blocks does the same). The story plays for the sample player chosen in the preview. The game uses its own saves and settings for this; your own saves and the other packs are not touched. A pack with problems is not started; the first problem is shown instead.

The game is taken from the engine checkout the editor was started with (`--engine`).

## Safety

- Every change is one step in Undo, named after what it did. Save is separate and explicit.
- Unsaved changes are copied to a recovery draft every 30 seconds and offered after a crash.
- **Rename** lists every line that will change before anything changes. Prose is not touched; a rename that would break something is taken back.
- **Delete** shows what uses the content and can remove the actions and links that use it.
- Saving stops if a file changed on disk since it was opened. Other packs are never changed.

## Not finished

- Settings of the rarer content types (most rules, nested settings such as equipment or body parts) are typed in the format's words in a text box.
- A calculation is typed as a short formula inside its block; lists of entries are typed with commas.
- The map does not edit doors, regions or map positions.
- Playing in the game does not lead back to the block that was played, and the sample player's body form is not passed on.
- There is no find and replace, and no view of how packs depend on each other.
- The Details forms still use an older design than the side editor.
