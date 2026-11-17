class_name MapSurface
extends Control
## The map as the game draws it: a dot for each place where the game's own
## layout puts it (north up), paths for the ways between them, names beside
## the dots. On top of that it can be changed: drag from one place to another
## to connect them, Ctrl-drag a place to give it a position of its own.

signal place_chosen(id: String)
signal place_opened(id: String)
signal connect_requested(from: String, to: String, one_way: bool)
signal way_chosen(a: String, b: String)
signal place_moved(id: String, cell: Vector2i)
signal content_dropped(data: Dictionary, position: Vector2)

## Pixels between two neighbouring places at zoom 1.
const STEP := 120.0
const ZOOM_MIN := 0.2
const ZOOM_MAX := 1.6
## Where a name is tried, in order, as directions from its place.
const LABEL_SLOTS := [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0), Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]

var workspace: PackWorkspace
## {id, name, cell: Vector2i, own: bool, fast: bool, note: String}
var places: Array[Dictionary] = []
## {a, b, both: bool, door: bool, played: bool}: a way from a to b, and back when `both`.
var ways: Array[Dictionary] = []
## {from, step: Vector2, name}: a way that leaves this part of the map.
var stubs: Array[Dictionary] = []
var background: Texture2D
var selected := ""
var zoom := 1.0
var pan := Vector2.ZERO
var hovered := ""

var _by_id: Dictionary = {}
var _labels: Dictionary = {}
var _labels_zoom := -1.0
var _press := ""
var _press_at := Vector2.ZERO
var _dragging := false
var _moving := false
var _panning := false
var _pointer := Vector2.ZERO
## Until the author moves the view, it follows the size of the window.
var _fitted := true

func _init() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_ARROW

## Shows a part of the map. The view is kept when it is the same part as before.
func show_map(new_places: Array[Dictionary], new_ways: Array[Dictionary], new_stubs: Array[Dictionary], picture: Texture2D, keep_view: bool) -> void:
	places = new_places
	ways = new_ways
	stubs = new_stubs
	background = picture
	_by_id.clear()
	for place: Dictionary in places: _by_id[place.id] = place
	_labels_zoom = -1.0
	if not keep_view:
		_fitted = true
		fit.call_deferred()
	queue_redraw()

func has_place(id: String) -> bool:
	return _by_id.has(id)

func point_of(id: String) -> Vector2:
	return at_cell(Vector2(_by_id[id].cell))

func at_cell(cell: Vector2) -> Vector2:
	return pan + cell * STEP * zoom

## The cell nearest a point of the surface.
func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(((point - pan) / (STEP * zoom)).round())

func radius() -> float:
	return clampf(11.0 * zoom, 5.0, 13.0)

## The place under a point, or "".
func place_at(point: Vector2) -> String:
	var best := ""
	var nearest := radius() + 7.0
	for place: Dictionary in places:
		var distance := point.distance_to(at_cell(Vector2(place.cell)))
		if distance < nearest:
			nearest = distance
			best = place.id
	return best

## The way under a point, or {}.
func way_at(point: Vector2) -> Dictionary:
	for way: Dictionary in ways:
		var a := point_of(way.a)
		var b := point_of(way.b)
		if Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point) <= 6.0: return way
	return {}

## Shows every place, as large as fits.
func fit() -> void:
	if places.is_empty() or size.x < 10: return
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for place: Dictionary in places:
		low = low.min(Vector2(place.cell))
		high = high.max(Vector2(place.cell))
	var span := (high - low).max(Vector2(1, 1)) * STEP
	# Room is left at the sides for the names beside the outermost places.
	var room := (size - Vector2(280, 120)).max(Vector2(80, 80))
	zoom = clampf(minf(room.x / span.x, room.y / span.y), ZOOM_MIN, 1.3)
	pan = size / 2.0 - (low + high) / 2.0 * STEP * zoom
	_fitted = true
	queue_redraw()

## Brings a place into view.
func reveal(id: String) -> void:
	if not _by_id.has(id): return
	var point := point_of(id)
	if size.x > 200 and not Rect2(Vector2(60, 40), size - Vector2(120, 80)).has_point(point):
		pan += size / 2.0 - point
		_fitted = false
		queue_redraw()

func zoom_by(factor: float, around: Vector2) -> void:
	var next := clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(next, zoom): return
	pan = around - (around - pan) * (next / zoom)
	zoom = next
	_fitted = false
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _fitted: fit()
	elif what == NOTIFICATION_MOUSE_EXIT and not hovered.is_empty():
		hovered = ""
		queue_redraw()

# ------------------------------------------------------------------ drawing

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), EditorTheme.color("bg"))
	_draw_background()
	if places.is_empty():
		var words := "No places here yet. Choose + Place to add the first one."
		draw_string(get_theme_default_font(), size / 2.0 - Vector2(180, 0), words, HORIZONTAL_ALIGNMENT_CENTER, 360, 15, EditorTheme.color("muted"))
		return
	if not is_equal_approx(_labels_zoom, zoom): _place_labels()
	var font := get_theme_default_font()
	var r := radius()
	var path := Color(EditorTheme.color("muted"), 0.75)
	var view := Rect2(Vector2(-80, -80), size + Vector2(160, 160))
	for stub: Dictionary in stubs:
		var from := point_of(stub.from)
		if not view.has_point(from): continue
		var to: Vector2 = from + (stub.step as Vector2).normalized() * STEP * zoom * 0.42
		draw_dashed_line(from, to, Color(path, 0.6), 2.0, 5.0)
		draw_arc(to, 3.5, 0, TAU, 12, Color(path, 0.8), 1.5, true)
	for way: Dictionary in ways:
		var a := point_of(way.a)
		var b := point_of(way.b)
		if not view.has_point(a) and not view.has_point(b): continue
		if way.get("played", false): draw_dashed_line(a, b, Color(EditorTheme.color("info"), 0.8), 2.0, 7.0)
		else: draw_line(a, b, path, maxf(1.5, 3.0 * minf(zoom, 1.0)), true)
		var along := (b - a).normalized()
		if not way.both:
			var tip := b - along * (r + 5.0)
			var side := along.orthogonal() * 5.0
			draw_colored_polygon(PackedVector2Array([tip, tip - along * 10.0 + side, tip - along * 10.0 - side]), EditorTheme.color("text"))
		if way.door:
			var middle := (a + b) / 2.0
			var leaf := Rect2(middle - Vector2(5, 7), Vector2(10, 14))
			draw_rect(leaf, EditorTheme.color("bg"))
			draw_rect(leaf, EditorTheme.color("accent"), false, 2.0)
			draw_circle(middle + Vector2(2, 1), 1.2, EditorTheme.color("accent"))
	if _dragging and _by_id.has(_press) and not _moving:
		draw_line(point_of(_press), _pointer, EditorTheme.color("accent"), 2.5, true)
	for place: Dictionary in places:
		var centre := at_cell(Vector2(place.cell))
		if not view.has_point(centre): continue
		var chosen: bool = place.id == selected
		var fill := EditorTheme.color("accent") if chosen else (Color(EditorTheme.color("text"), 0.9) if place.own else EditorTheme.color("hover"))
		if _moving and _dragging and place.id == _press: fill = Color(fill, 0.35)
		if place.fast:
			var d := r * 1.35
			draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -d), centre + Vector2(d, 0), centre + Vector2(0, d), centre + Vector2(-d, 0)]), fill)
			if not place.own and not chosen: draw_polyline(PackedVector2Array([centre + Vector2(0, -d), centre + Vector2(d, 0), centre + Vector2(0, d), centre + Vector2(-d, 0), centre + Vector2(0, -d)]), EditorTheme.color("muted"), 1.5, true)
		else:
			draw_circle(centre, r, fill)
			if not place.own and not chosen: draw_arc(centre, r, 0, TAU, 24, EditorTheme.color("muted"), 1.5, true)
		if chosen: draw_arc(centre, r + 5.0, 0, TAU, 32, EditorTheme.color("accent"), 2.0, true)
		elif place.id == hovered or (_dragging and not _moving and place.id == place_at(_pointer) and place.id != _press): draw_arc(centre, r + 4.0, 0, TAU, 32, EditorTheme.color("text"), 1.5, true)
	var size_f := 15 if zoom >= 0.75 else 12
	for place: Dictionary in places:
		var centre := at_cell(Vector2(place.cell))
		if not view.has_point(centre): continue
		var named: bool = _labels.has(place.id)
		if not named and place.id != selected and place.id != hovered: continue
		var text_size := font.get_string_size(str(place.name), HORIZONTAL_ALIGNMENT_LEFT, -1, size_f)
		var offset: Vector2 = _labels.get(place.id, Vector2(0, r + 9.0 + text_size.y / 2.0))
		# The chosen place wears a ring: its name stands clear of it.
		if place.id == selected: offset += offset.normalized() * 5.0
		var box := Rect2(centre + offset - text_size / 2.0, text_size)
		draw_rect(box.grow(2), Color(EditorTheme.color("bg"), 0.9 if not named else 0.72), true)
		var colour := EditorTheme.color("text") if place.own or place.id == selected else EditorTheme.color("muted")
		draw_string(font, Vector2(box.position.x, box.position.y + font.get_ascent(size_f)), str(place.name), HORIZONTAL_ALIGNMENT_LEFT, -1, size_f, colour)
	if _moving and _dragging and _by_id.has(_press):
		var target := at_cell(Vector2(cell_at(_pointer)))
		draw_arc(target, r + 3.0, 0, TAU, 32, EditorTheme.color("accent"), 2.0, true)
		draw_circle(target, r, Color(EditorTheme.color("accent"), 0.5))

func _draw_background() -> void:
	if background != null:
		var picture := background.get_size()
		var cover := maxf(size.x / picture.x, size.y / picture.y)
		draw_texture_rect(background, Rect2((size - picture * cover) / 2.0, picture * cover), false, Color(1, 1, 1, 0.32))
		return
	# A faint dot at every place the layout could put something.
	var step := STEP * zoom
	while step < 36.0: step *= 2.0
	var dot := Color(EditorTheme.color("border"), 0.8)
	var y := fposmod(pan.y, step)
	while y < size.y:
		var x := fposmod(pan.x, step)
		while x < size.x:
			draw_circle(Vector2(x, y), 1.2, dot)
			x += step
		y += step

## Finds a spot for every name where it crosses the fewest paths, places and
## other names; a name that would still cover something is left out and shown
## when the pointer is on its place. Only what is near a place is looked at.
func _place_labels() -> void:
	_labels.clear()
	_labels_zoom = zoom
	var font := get_theme_default_font()
	var size_f := 15 if zoom >= 0.75 else 12
	var r := radius()
	var by_cell: Dictionary = {}
	for place: Dictionary in places: by_cell[place.cell] = place.id
	var touching: Dictionary = {}
	for way: Dictionary in ways:
		for id: String in [way.a, way.b]:
			if not touching.has(id): touching[id] = []
			touching[id].append(way)
	var reach := Vector2i(clampi(int(ceil(260.0 / (STEP * zoom))), 1, 6), clampi(int(ceil(60.0 / (STEP * zoom))), 1, 4))
	var placed: Dictionary = {}
	var order: Array[Dictionary] = places.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.own and not b.own)
	for place: Dictionary in order:
		var centre := Vector2(place.cell) * STEP * zoom
		var text_size := font.get_string_size(str(place.name), HORIZONTAL_ALIGNMENT_LEFT, -1, size_f)
		var near: Array[String] = []
		for y in range(place.cell.y - reach.y, place.cell.y + reach.y + 1):
			for x in range(place.cell.x - reach.x, place.cell.x + reach.x + 1):
				var other: String = by_cell.get(Vector2i(x, y), "")
				if not other.is_empty() and other != place.id: near.append(other)
		var segments: Array = []
		for id: String in [place.id] + near:
			for way: Dictionary in touching.get(id, []):
				segments.append([Vector2(_by_id[way.a].cell) * STEP * zoom, Vector2(_by_id[way.b].cell) * STEP * zoom])
		var best := Rect2()
		var best_score := INF
		for index in LABEL_SLOTS.size():
			var direction: Vector2 = LABEL_SLOTS[index]
			var offset := Vector2(direction.x * (r + 5.0 + text_size.x / 2.0), direction.y * (r + 5.0 + text_size.y / 2.0))
			var rect := Rect2(centre + offset - text_size / 2.0, text_size)
			var score := index * 0.1
			for segment: Array in segments:
				if _rect_hits_segment(rect.grow(2), segment[0], segment[1]): score += 10.0
			for id: String in near:
				var dot := Vector2(_by_id[id].cell) * STEP * zoom
				if dot.clamp(rect.position, rect.end).distance_to(dot) < r + 4.0: score += 15.0
				if placed.has(id) and rect.grow(3).intersects(placed[id]): score += 20.0
			if score < best_score:
				best_score = score
				best = rect
		# A name that would still lie on another name or place is left out.
		if best_score >= 15.0: continue
		placed[place.id] = best
		_labels[place.id] = best.get_center() - centre

static func _rect_hits_segment(rect: Rect2, a: Vector2, b: Vector2) -> bool:
	if rect.has_point(a) or rect.has_point(b): return true
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for index in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[index], corners[(index + 1) % 4]) != null: return true
	return false

# -------------------------------------------------------------------- input

func _get_tooltip(at_position: Vector2) -> String:
	var id := place_at(at_position)
	if id.is_empty():
		var way := way_at(at_position)
		if way.is_empty(): return ""
		return "%s %s %s%s. Right-click to remove a way." % [str(_by_id[way.a].name), "↔" if way.both else "→", str(_by_id[way.b].name), ", through a door" if way.door else ""]
	var place: Dictionary = _by_id[id]
	return str(place.name) + ("\n" + str(place.note) if not str(place.note).is_empty() else "")

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		_pointer = click.position
		if click.pressed and click.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_by(1.12 if click.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12, click.position)
			accept_event()
		elif click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
			grab_focus()
			_press = place_at(click.position)
			_press_at = click.position
			_dragging = false
			_moving = click.ctrl_pressed or click.meta_pressed
			_panning = _press.is_empty()
			if not _press.is_empty() and click.double_click:
				place_opened.emit(_press)
				_press = ""
		elif click.button_index == MOUSE_BUTTON_LEFT:
			var pressed := _press
			var was_dragging := _dragging
			var was_moving := _moving
			_press = ""
			_dragging = false
			_moving = false
			_panning = false
			queue_redraw()
			if pressed.is_empty(): return
			if not was_dragging: place_chosen.emit(pressed)
			elif was_moving: place_moved.emit(pressed, cell_at(click.position))
			else:
				var target := place_at(click.position)
				if not target.is_empty() and target != pressed: connect_requested.emit(pressed, target, click.shift_pressed)
		elif click.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = click.pressed
		elif click.button_index == MOUSE_BUTTON_RIGHT and click.pressed:
			var way := way_at(click.position)
			if not way.is_empty(): way_chosen.emit(str(way.a), str(way.b))
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_pointer = motion.position
		if _panning:
			pan += motion.relative
			_fitted = false
			queue_redraw()
		elif not _press.is_empty():
			if _dragging or motion.position.distance_to(_press_at) > 6.0:
				_dragging = true
				queue_redraw()
		else:
			var over := place_at(motion.position)
			if over != hovered:
				hovered = over
				queue_redraw()
	elif event is InputEventKey and event.pressed:
		var key := event as InputEventKey
		var step: Vector2 = {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}.get(key.keycode, Vector2.ZERO)
		if step != Vector2.ZERO:
			var next := neighbour(selected, step)
			if not next.is_empty(): place_chosen.emit(next)
			accept_event()
		elif key.keycode in [KEY_ENTER, KEY_KP_ENTER] and not selected.is_empty():
			place_opened.emit(selected)
			accept_event()
		elif key.keycode in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]:
			zoom_by(1.2 if key.keycode in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD] else 1.0 / 1.2, size / 2.0)
			accept_event()

## The nearest place in a direction from a place (for the arrow keys); the
## first place when none is chosen.
func neighbour(from: String, direction: Vector2) -> String:
	if not _by_id.has(from): return str(places[0].id) if not places.is_empty() else ""
	var origin := Vector2(_by_id[from].cell)
	var best := ""
	var best_score := INF
	for place: Dictionary in places:
		var delta := Vector2(place.cell) - origin
		if place.id == from or delta.normalized().dot(direction) < 0.5: continue
		var score := delta.length() * (2.0 - delta.normalized().dot(direction))
		if score < best_score:
			best_score = score
			best = place.id
	return best

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return workspace != null and not DragPayload.resolve(workspace, data).is_empty()

func _drop_data(position: Vector2, data: Variant) -> void:
	if _can_drop_data(position, data): content_dropped.emit(data, position)
