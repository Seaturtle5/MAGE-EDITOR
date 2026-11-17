# MAGE:EDITOR

MAGE:EDITOR is an offline desktop tool for making MAGE content packs without learning the content format. You work on one pack and can load other packs to use their content. The editor writes ordinary pack files and checks them with the game engine itself.

The editor is in development. Stories, conversations, events and every content type can be built visually; what is still missing is listed under "Not finished". Content the editor cannot show yet is kept exactly as it is.

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
| Library (left) | Everything in your pack by kind, and the other loaded packs folded away. Choose an entry to open it, or drag it into a story, onto the map or onto a matching picker. Opening a pack also loads the packs in the folder beside it that belong with it (see below). **Pack → Add another pack** takes one more pack or a whole folder of packs. |
| Home | Guided tasks, what you worked on with hints about what it still needs, and problems. |
| Stories | The board. The story you opened is drawn as a flow from left to right: what starts it, its text and actions, each check with a way out for every answer, the player's responses, fights and where it ends. The stories around it are cards; click one to open it. See "The board" below. |
| Map | The map as the game draws it: one part of the world at a time, north up, a dot for each place and a path for each way. Click a place to see what happens there. See "The map" below. |
| Details | Everything about the selected content. Conditions read in words and open the condition builder; lists of words are chips; numbers, spans, chances, switches and choices have their own controls; settings with several parts (what an item is worn as, a body part, a creature's trophies, the warnings at each level of hunger) are sheets and rows. A hook's moment is chosen from a list, including a share of the enemy's health and a moment one of your stories raises. An event's condition is built with the condition builder, and an item's reactions are chosen in "What should happen?", as in a story. The small buttons beside the name show where the content is used, rename it everywhere, duplicate it and delete it. |
| Side editor (right) | The selected story as blocks, with a preview underneath. |
| Status line | What just happened, with **Undo**, and where you are. |

**‹ ›** beside Home go back and forward through what you looked at (Alt+← / Alt+→). The **☰** button opens the lists of saved values and problems: choose a value to see every story that changes it and every story that reads it.

## The board

Opening a story (from the library, from Home, from another story's card) draws it on the board:

| Node | What it shows |
|---|---|
| ⚡ The story's own card | What starts it: an event's trigger, condition and how often it happens; "When the player talks to Wren" for a story inside other content; the stories that lead to it; or a warning that nothing leads there yet. **Details** opens its settings. |
| 💬 Text, ⚙ Actions | A run of text and actions in order: the first lines, and how many more there are. |
| ◇ Check | An "Only if": one way out for each condition, and one for when none holds. |
| ☰ The player chooses | The responses, each with its own way out. A ◈ marks a response that is only offered under a condition. |
| ⚔ Fight | The creature, and a way out for each result that has its own part. |
| ⏹ Ends here, ↩ Goes back | Where the story stops. From **Then go on with…** it can be sent on to another story. |

Click a node to find its blocks in the side editor, where they are changed. Orange dots are ways you can lead elsewhere: drag one to another story's card (a response, the ending, a played story); right-click a line to remove the link. Blue lines follow from the blocks themselves. A very long story draws its first sixty parts and says how many blocks are further in. **Show all stories** shows every story as a card, without a flow; **Tidy up** arranges the board again.

## The map

The map is drawn with the game's own layout, so a place is where the player will see it: north is up, places joined by compass ways stand beside each other, ways up, down, inside and outside step off to the side. A ◆ is a fast-travel point, a small door on a path is a door, an arrow is a way that only leads one way, and a short dashed stub is a way that leaves this part of the map. Your own places are bright; places of other packs are outlined.

| To | Do |
|---|---|
| See another part of the world | Choose it in the list beside **MAP**: the game shows one region at a time, or the places of an area that belong to no region. |
| See what happens at a place | Click it: its events, people and items, its ways out, its area and region are listed on the right. Double-click opens its details. |
| Connect two places | Drag from one to the other. The direction offered is the one the second place lies in; choose a door if the way goes through one. Hold Shift for a way that only leads one way. |
| Remove a way | Right-click its path, or use the ✕ beside it in the place's list of ways out. |
| Put a place somewhere of your own choosing | Hold Ctrl and drag it. The game then keeps it there, and the places joined to it by compass ways follow. **Let the game place it** on the right gives the position back. |
| Move around | Drag the background, turn the mouse wheel, or use **−**, **+** and **Fit**. The arrow keys go from place to place. |

## Working beside other packs

A pack rarely stands alone: it uses the base pack's items, another author's places. When you open a pack, the editor looks in the folder it sits in and loads the packs that belong with it: the packs it needs, the packs that need it, and the other packs that need the same base pack. With a whole game this can be sixty packs.

- Your own pack opens at once. The others are read behind the scenes, on every processor at once, and the check mark in the top bar says **Loading packs…** until they are in. You can already write.
- The other packs cannot be changed here. Using something of theirs adds the pack to the ones yours needs.
- After every change the editor checks the changed file at once (is every line something the game understands?), and then checks your whole pack against the others behind the scenes (does that item exist?); problems appear on their blocks when it is done, usually within a second or two.
- **Check** in the top bar checks every loaded pack's stories again. With a whole game loaded this takes a quarter of a minute; you can keep working meanwhile.

Without the packs it uses, a pack shows a problem for everything it takes from them. If your packs are not kept side by side, add them with **Pack → Add another pack**.

## A pack of pictures

A pack can hold pictures for other packs' content. On the pack's own page, **Art** says how they count: **Replaces** puts them in place of the content's own pictures, **Fallback** only fills gaps. Import the pictures (**Pack → Import a picture**), open the other pack's character, place, creature or item from the library, and choose the small **🖼** beside its name: your pack then adds the picture to that content, and the other pack's files stay as they are.

## Guided tasks

On Home, choose a task: talk to a character, something happens at a place, make an item, start a quest, add a place, open a shop, write an ending. With the Flexible Survival base pack loaded there are eight more. A task asks a few questions page by page and shows what it will make. A place or an area that does not exist yet can be made on the spot from only a name. **Create** makes everything, connected, as one step you can undo.

## Stories as blocks

Each block is a sentence. The highlighted parts are chips: choose one to change it, or drop a library entry on it.

| To | Do |
|---|---|
| Add | **+ Text**, **+ Action** or **+ More** at the place you want it. Action opens "What should happen?": search with everyday words (heal, trust, teleport), fill in the sentence, **Add** or **Add & next**. You can also type a line you know. |
| Write | Double-click a text block, or choose **+ Text**: a large writing window opens. Its toolbar has undo, **B**old and *I*talic, **Insert** (a name, he or she, a counter's number, a text kept for reuse), **Body** (words about the player's body), **Vary** (several versions, and how the game goes through them), **Only if…** and **Style** (a roll, a warning). Select words first to change those words. Beside the text it shows the words as a sample player reads them, and under it what the game cannot read yet. Ctrl+Enter keeps the text, Esc leaves it. Long text fields on the Details page open the same window from **⤢ Write in a large window**. |
| Make it conditional | **⋯ → Only if…** puts the block (or all selected blocks) inside a condition. Conditions are built from sentences in groups: all of, any of, none of. Add **Otherwise, if…** and **Otherwise** from the condition's own menu. |
| Move | Drag the handle; hold Ctrl to copy. Or use **⋯ → Move up / Move down**, Alt+↑ / Alt+↓, or cut and paste. Shift-click and Ctrl-click select several blocks. |
| Copy between stories | Copy and paste work as lines of the content format, also to and from a text editor. |
| Work something out | Where a block takes an amount, choose **a calculation** and put it together from chips: **+ number**, **+ counter…**, the signs, brackets, **random**, the smaller or larger of two numbers, a square root, a list's size or one of its entries. Choose a chip to change or remove it. |
| Understand | **⋯ → Explain** says what a block does. **Show the line** shows the content format's line under every block. |
| Preview | The strip under the blocks shows the text as a sample player reads it. Conditions are marked taken or skipped for that sample. Actions are not applied; the preview stops at responses, pauses, links and fights. |

Some actions only work in certain stories (a fight action, "keep the item"). They are hidden elsewhere; **Show all** lists them greyed out with the reason.

Lists of responses that belong to other content open the same way: what the player can do at a place, a character's own actions, a creature's attacks. Each response is a block with what happens when it is chosen inside it; **+ Response** adds one.

## Try it in the game

**▶ Play** in the top bar starts the real game on your pack as it is now, unsaved changes included, in its own window: from a starting point of the game, at the selected place, or straight into the story you are working on (**▶ Try it** above the blocks does the same). The story plays for the sample player chosen in the preview. The game uses its own saves and settings for this; your own saves and the other packs are not touched. A pack with problems is not started; the first problem is shown instead.

The game is taken from the engine checkout the editor was started with (`--engine`).

## Finding and changing across the pack

| To | Use |
|---|---|
| Jump anywhere | **Find anything** (Ctrl+K): content by name, your own stories by their text, values and commands. |
| Change a word in the story text | **Pack → Find and replace in story text** (Ctrl+H). Only the words players read are searched; every line is listed before anything changes. |
| See what moves a quest | Open the quest and choose **What moves it?**: each stage with the stories that set it, and a button to set it from another story. |
| See how packs depend on each other | **Pack → How the packs depend on each other**. |
| Go back in time | **Pack → History of changes** lists every change; choose one to go back to just after it. |

## Safety

- Every change is one step in Undo, named after what it did. Save is separate and explicit.
- Unsaved changes are copied to a recovery draft every 30 seconds and offered after a crash.
- **Rename** lists every line that will change before anything changes. Prose is not touched; a rename that would break something is taken back.
- **Delete** shows what uses the content and can remove the actions and links that use it.
- Saving stops if a file changed on disk since it was opened. Other packs are never changed.

## Not finished

- Every field has its own control (a picker, number boxes, a switch, chips, a condition in words, rows, sheets, a text box for words the player reads), but a few number fields of the rules types take a calculation as a short typed formula, and the roles and change texts of saved values cannot be changed.
- In the writing window, variations and conditional words are written as marked text, not as panels; there is no spell check.
- The map does not set a region's travel order or map grid; a door that leads into an area is set in the door's details. Exits that stories make in play are placed by the game's layout but not drawn as paths.
- The board draws the flow of one story at a time; a part of the flow is changed in the side editor, not on the board.
- Playing in the game does not lead back to the block that was played, and the sample player's body form is not passed on.
- With very many packs loaded (several thousand pieces of content), the preview under the blocks updates when you ask. A check of your own pack does not look again at the other packs' stories: a problem your change causes in another pack's story shows after **Check**.
- A board of every story of a large game is not drawn: beyond 150 cards the board shows the first ones and says how many are left out. Choose a story to see it with its neighbours.
