class_name StoryFlow
extends RefCounted
## One story as a flow, read from left to right: what starts it, runs of text
## and actions, every check with a way out for each answer, the player's
## responses, fights, and where it ends or goes on. The board draws this for
## the story in focus; nothing here changes a file.

## More nodes than this and the parts further in are folded into one node each.
const MAX_NODES := 60
## Lines of text and actions listed in one node before "more".
const MAX_LINES := 5
const COLUMN := 330.0
const WIDTH := 280.0
const GAP := 26.0
const RUN := ["text", "effect", "show", "page_break", "play"]
## Letters of a line that are laid out; the rest is in its tooltip and in the side editor.
const SHOWN := 90
## What starts the stories that are part of other content: %s is that content's name.
const STARTS := {
	"talk": "When the player talks to %s", "use": "When the player uses %s", "encounter": "When the player meets %s in a fight",
	"victory": "When %s wins the fight", "defeated": "When %s is defeated", "enter": "When the player enters %s",
	"description": "When the player looks at %s", "scent": "When the player smells %s", "sex": "When the player has sex with %s",
	"presence": "While %s is at the player's place", "summon": "When %s is called to the party", "dismiss": "When %s is sent away",
	"gift": "When %s is given something", "attack": "When %s attacks", "each turn": "Every turn, while %s lasts", "ends": "When %s ends",
	"each round": "Every round of a fight with %s", "fight starts": "When a fight with %s starts", "intro": "When %s opens",
	"locked text": "When the player tries %s while it is locked", "going text": "When the player goes through %s",
}

## {name, kind, icon, title, line, keys, rows, column, y, height}; `keys` are the blocks
## the node stands for (as StoryGraph.structure() names them); a row is {text, muted, tip, port}
## where port is absent or says what its way out is: {kind: "next" | "response" | "continuation" | "play", ...}.
var nodes: Array[Dictionary] = []
## {from, port, to} between nodes and {from, port, story} to another story; from "start" is the story's own card.
var links: Array[Dictionary] = []
var bottom := 0.0
var columns := 1
var folded := 0

var _row: Dictionary
var _workspace: PackWorkspace
var _children: Dictionary = {}
var _is_menu := false
var _by_name: Dictionary = {}

static func build(row: Dictionary, workspace: PackWorkspace) -> StoryFlow:
	var flow := StoryFlow.new()
	flow._row = row
	flow._workspace = workspace
	flow._is_menu = (row.def.type == "menu" and not row.has("script_field")) or (row.has("script_field") and ContentDB.SCHEMA.get(row.def.type, {}).get(row.script_field, "") == "menu")
	for entry: Dictionary in StoryGraph.structure(row):
		if not flow._children.has(entry.parent): flow._children[entry.parent] = []
		flow._children[entry.parent].append(entry)
	var result := flow._sequence("", 1, 0.0, [["start", 0]], 0, {})
	flow.columns = int(result.column)
	flow.bottom = float(result.bottom)
	var tails: Array = result.tails
	if not tails.is_empty():
		# Whatever runs to the end of the story meets here. From here the story
		# can be sent on to another one.
		var end := flow._node("end", "⏹", "Ends here", 0, flow.columns, 0.0)
		end.rows.append({"text": "Back to the list of responses" if flow._is_menu else "The story is over.", "muted": true, "tip": ""})
		end.rows.append({"text": "➜ Then go on with…", "muted": true, "tip": "Drag this dot to another story to go on with it when this one is over.", "port": {"kind": "continuation"}})
		flow._size(end)
		for tail: Array in tails: flow.links.append({"from": tail[0], "port": tail[1], "to": end.name})
		flow.columns += 1
		flow.bottom = maxf(flow.bottom, end.height)
	return flow

func node(name: String) -> Dictionary:
	return _by_name.get(name, {})

## What a way out of a node is: {} when it has none there.
func port(name: String, index: int) -> Dictionary:
	var at := 0
	for row: Dictionary in node(name).get("rows", []):
		if not row.has("port"): continue
		if at == index: return row.port
		at += 1
	return {}

## The node that stands for a block, or "" (a block further in than the board draws has none).
func node_of(key: String) -> String:
	for entry: Dictionary in nodes:
		if key in entry.keys: return entry.name
	return ""

## The stories this one leads to, by ID.
func targets() -> Array:
	var out: Array = []
	for link: Dictionary in links:
		if link.has("story") and link.story not in out: out.append(link.story)
	return out

func _node(kind: String, icon: String, title: String, line: int, column: int, y: float) -> Dictionary:
	var entry := {"name": "flow_%d" % nodes.size(), "kind": kind, "icon": icon, "title": title, "line": line, "keys": [], "rows": [], "column": column, "y": y, "height": 0.0}
	nodes.append(entry)
	_by_name[entry.name] = entry
	return entry

## How tall a node is drawn: a line of text takes two rows of words, the rest one.
func _size(entry: Dictionary) -> void:
	var height := 46.0
	for line: Dictionary in entry.rows: height += 46.0 if line.get("prose", false) else 27.0
	entry.height = maxf(height, 73.0)

## The output port a row of a node is.
func _port_index(entry: Dictionary, row_index: int) -> int:
	var at := 0
	for index in row_index:
		if entry.rows[index].has("port"): at += 1
	return at

## Lays out the blocks inside `parent` from `column` on, at height `y`, reached
## from `tails` ([node, port] pairs). Returns the column after them, how far
## down they reach and the ways out that run on to whatever follows.
func _sequence(parent: String, column: int, y: float, tails: Array, depth: int, option: Dictionary) -> Dictionary:
	var kids: Array = _children.get(parent, [])
	var reach := y
	var index := 0
	while index < kids.size():
		var entry: Dictionary = kids[index]
		var kind: String = entry.node.kind
		if nodes.size() >= MAX_NODES:
			# Too much to draw: the rest of this part is one node that opens in the side editor.
			var rest := kids.size() - index
			var more := _node("more", "⋯", "%d more block%s" % [rest, "" if rest == 1 else "s"], int(entry.line), column, y)
			for at in range(index, kids.size()): more.keys.append(kids[at].key)
			more.rows.append({"text": "Shown in the blocks on the right", "muted": true, "tip": "This story is long: the board draws its first parts. Click to find these blocks in the side editor.", "port": {"kind": "next"}})
			_size(more)
			folded += rest
			for tail: Array in tails: links.append({"from": tail[0], "port": tail[1], "to": more.name})
			return {"column": column + 1, "bottom": maxf(reach, y + float(more.height)), "tails": [[more.name, 0]]}
		if kind in RUN:
			var run: Array = []
			while index < kids.size() and str(kids[index].node.kind) in RUN:
				run.append(kids[index])
				index += 1
			var made := _run(run, column, y)
			for tail: Array in tails: links.append({"from": tail[0], "port": tail[1], "to": made.name})
			tails = [[made.name, 0]]
			column += 1
			reach = maxf(reach, y + float(made.height))
			continue
		index += 1
		if kind == "goto":
			var target: String = entry.node.target
			var last := index == kids.size()
			for tail: Array in tails:
				# A way that ends in "go to" can be sent elsewhere by dragging its dot.
				var way := port(tail[0], tail[1])
				if way.get("kind", "") == "next" and last:
					if depth == 0: way.kind = "continuation"
					elif not option.is_empty() and depth == 1 and bool(StoryGraph.transition(option).editable):
						way.kind = "response"
						way.line = int(option.line)
				if target not in ["end", "back"]: links.append({"from": tail[0], "port": tail[1], "story": target})
			if target in ["end", "back"] and not tails.is_empty():
				var stop := _node("stop", "⏹" if target == "end" else "↩", "Ends here" if target == "end" else "Goes back", int(entry.line), column, y)
				stop.keys.append(entry.key)
				stop.rows.append({"text": "The story is over." if target == "end" else "Back to the conversation it came from.", "muted": true, "tip": ""})
				_size(stop)
				for tail: Array in tails: links.append({"from": tail[0], "port": tail[1], "to": stop.name})
				column += 1
				reach = maxf(reach, y + float(stop.height))
			tails = []
			continue
		if kind not in ["if", "fight", "choices"]: continue
		var parts: Array = _children.get(entry.key, [])
		var made: Dictionary
		match kind:
			"if":
				made = _node("if", "◇", "Check", int(entry.line), column, y)
				made.rows.append({"text": "Which of these holds?", "muted": true, "tip": "The first line that holds is followed."})
				for part: Dictionary in parts:
					var condition: String = part.node.condition
					var words := BlockCatalog.condition_sentence(condition, _workspace) if not condition.is_empty() else ""
					made.rows.append({"text": ("If " + _lower(words)).left(SHOWN) if not condition.is_empty() else "Otherwise", "tip": ("Only if " + _lower(words) + ".") if not condition.is_empty() else "When none of the lines above holds.", "port": {"kind": "next"}, "part": part.key})
				if not (entry.node["else"] is Array):
					made.rows.append({"text": "Otherwise: carries on", "muted": true, "tip": "When none of the lines above holds, the story goes on with what follows.", "port": {"kind": "next"}, "through": true})
			"fight":
				made = _node("fight", "⚔", "Fight", int(entry.line), column, y)
				made.rows.append({"text": "Against " + BlockCatalog.content_label("creature", str(entry.node.creature), _workspace), "tip": "The story waits here until the fight is over."})
				for part: Dictionary in parts:
					made.rows.append({"text": StoryEditor.OUTCOMES.get(str(part.node.label), str(part.node.label).capitalize()), "tip": "What happens after this result.", "port": {"kind": "next"}, "part": part.key})
				if parts.size() < 3:
					made.rows.append({"text": "Any other result: carries on", "muted": true, "tip": "After a result without its own part, the story goes on with what follows.", "port": {"kind": "next"}, "through": true})
			"choices":
				made = _node("choices", "☰", "The player chooses", int(entry.line), column, y)
				for part: Dictionary in parts:
					var condition: String = part.node.get("condition", "")
					var editable: bool = StoryGraph.transition(part.node).editable
					made.rows.append({"text": "› " + str(part.node.label) + ("  ◈" if not condition.is_empty() else ""), "tip": "A response the player can choose." + (" Offered only if " + _lower(BlockCatalog.condition_sentence(condition, _workspace)) + "." if not condition.is_empty() else "") + (" Drag its dot to a story to go there." if editable else ""), "port": {"kind": "response", "line": int(part.node.line)} if editable else {"kind": "next"}, "part": part.key})
				if parts.is_empty(): made.rows.append({"text": "No responses yet", "muted": true, "tip": ""})
		# The responses are the blocks of a list of responses; a check or a fight is one block.
		if kind == "choices" and not parts.is_empty():
			for part: Dictionary in parts: made.keys.append(part.key)
		else: made.keys.append(entry.key)
		_size(made)
		for tail: Array in tails: links.append({"from": tail[0], "port": tail[1], "to": made.name})
		var outs: Array = []
		var far := column + 1
		var at := y
		for row_index in (made.rows as Array).size():
			var line: Dictionary = made.rows[row_index]
			if not line.has("port"): continue
			var from := [made.name, _port_index(made, row_index)]
			if line.get("through", false):
				outs.append(from)
				continue
			var part_entry: Dictionary = {}
			for part: Dictionary in parts:
				if part.key == line.part: part_entry = part
			var inner := _sequence(str(line.part), column + 1, at, [from], depth + 1, part_entry.node if kind == "choices" else {})
			# After a response of a conversation the list shows again: nothing runs on.
			if not (kind == "choices" and _is_menu and depth == 0): outs.append_array(inner.tails)
			far = maxi(far, int(inner.column))
			if float(inner.bottom) > at: at = float(inner.bottom) + GAP
		tails = outs
		column = far
		reach = maxf(reach, maxf(at - GAP, y + float(made.height)))
	return {"column": column, "bottom": reach, "tails": tails}

## A run of text and actions as one node: its first lines, and how much more there is.
func _run(run: Array, column: int, y: float) -> Dictionary:
	var texts := 0
	for entry: Dictionary in run:
		if entry.node.kind == "text": texts += 1
	var made := _node("run", "💬" if texts > 0 else "⚙", "Text" if texts > 0 else "Actions", int(run[0].line), column, y)
	var shown := 0
	for entry: Dictionary in run:
		made.keys.append(entry.key)
		var item: Dictionary = entry.node
		var line := {"text": "", "tip": "", "line": int(entry.line)}
		match str(item.kind):
			"text":
				# Two lines are shown: only the start is put in words (a long passage is slow to lay out).
				var source := str(item.text)
				var words := Wording.words(source.left(SHOWN * 2) if source.length() > SHOWN * 2 else source, _workspace)
				line.text = "“" + (words.left(SHOWN) + "…" if words.length() > SHOWN else words + "”")
				line.tip = words.left(400)
				line.prose = true
			"effect":
				var read := BlockCatalog.read_line(str(item.text))
				line.text = (str(read.entry.icon) if not read.is_empty() else "🔒") + " " + BlockCatalog.sentence(str(item.text), _workspace)
				line.tip = line.text
				if str(line.text).length() > SHOWN: line.text = str(line.text).left(SHOWN) + "…"
			"show": line.text = "🖼 Shows " + (BlockCatalog.content_label("image", str(item.image), _workspace) if not str(item.image).is_empty() else "no picture")
			"page_break": line.text = "⏸ Waits for the player"
			"play":
				var target := StoryGraph.play_target(item)
				line.text = "▶ Plays " + (BlockCatalog.content_label("scene", target, _workspace) if not target.is_empty() else str(item.target))
				line.tip = "Plays another story, then comes back here. Drag its dot to play a different story."
				if not target.is_empty(): line.port = {"kind": "play", "node": item}
		# The first row carries the way on; a played story keeps a row of its own.
		if shown >= MAX_LINES and not line.has("port"): continue
		if (made.rows as Array).is_empty() and line.has("port"): made.rows.append({"text": "In order:", "muted": true, "tip": "", "port": {"kind": "next"}})
		if (made.rows as Array).is_empty(): line.port = {"kind": "next"}
		made.rows.append(line)
		shown += 1
	if run.size() > shown: made.rows.append({"text": "+ %d more" % (run.size() - shown), "muted": true, "tip": "The rest is in the blocks on the right."})
	_size(made)
	for row_index in (made.rows as Array).size():
		var line: Dictionary = made.rows[row_index]
		if line.get("port", {}).get("kind", "") == "play": links.append({"from": made.name, "port": _port_index(made, row_index), "story": StoryGraph.play_target(line.port.node)})
	return made

static func _lower(text: String) -> String:
	return text.left(1).to_lower() + text.substr(1) if text.length() > 1 and text.substr(1, 1) == text.substr(1, 1).to_lower() else text

## What starts a story, in sentences: an event's trigger, what the story is a
## part of, or the stories that lead to it.
static func starts(row: Dictionary, workspace: PackWorkspace) -> Array[String]:
	var out: Array[String] = []
	var d: FscParser.Definition = row.def
	var key := StoryBlocks.script_key(row)
	var owner := Wording.title(row)
	if d.type == "event" and key == "play":
		var found: String = d.fields["found by"].value if d.fields.has("found by") else ""
		for sentence: String in (EventTriggers.describe(workspace, found) if not found.is_empty() else "Started by another story").split("\nOR "): out.append(sentence)
		var needs: String = d.fields["requires"].value if d.fields.has("requires") else ""
		if not needs.is_empty(): out.append("Only if " + _lower(EventTriggers.describe_condition(workspace, needs)))
		var repeat: String = d.fields["repeat"].value if d.fields.has("repeat") else ""
		out.append({"": "Happens once", "once": "Happens once", "always": "Every time", "until resolved": "Until a story finishes it"}.get(repeat, "Repeats: " + repeat))
		if d.fields.has("active") and d.fields["active"].value == "no": out.append("Off until a story turns it on")
		return out
	if d.type == "hook":
		var moment: String = d.fields["on"].value if d.fields.has("on") else ""
		out.append(VisualDetails.MOMENT_WORDS.get(moment, "At the moment: " + moment) if not moment.is_empty() else "No moment chosen yet")
		return out
	if d.type in ["scene", "menu", "text"] and not row.has("script_field"):
		var seen: Dictionary = {}
		for link: Dictionary in workspace.links_touching(d.id):
			if link.target != d.id or link.from.def.id == d.id: continue
			var from := Wording.title(link.from) + (" · " + StoryEditor.story_name(link.from) if link.from.has("script_field") else "")
			if seen.has(from): continue
			seen[from] = true
			if seen.size() <= 3: out.append("After " + from)
		if seen.size() > 3: out.append("and %d more stories" % (seen.size() - 3))
		if out.is_empty(): out.append("⚠ Nothing leads here yet" if not workspace.is_used(d.id) else "Used by other content")
		return out
	if STARTS.has(key): out.append(str(STARTS[key]) % owner)
	else: out.append("%s of %s" % [StoryEditor.story_name(row), owner])
	return out
