class_name FlowBubbles
extends Control
## Shows which way the board's connections lead: small bubbles float along
## every line from where it starts to where it goes. With `still` set (the
## Reduce motion switch) the lines carry arrowheads instead, which do not move.
## It lies over the board, takes no input and draws only lines that are in view.

## Pixels between two bubbles on a line, and how far they float in a second.
const SPACING := 58.0
const SPEED := 34.0
## Bubbles are drawn this many times a second: enough to float, light on the processor.
const RATE := 30.0

var graph: GraphEdit
var still := false
## The lines as drawn last: [{points, lengths, total, colour}], kept while the board does not move.
var lines: Array[Dictionary] = []
## Where the nodes stand: a line runs behind them, and so do its bubbles.
var _nodes: Array[Rect2] = []
var _mark := ""
var _time := 0.0
var _since := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	if graph == null or not is_visible_in_tree(): return
	_time += delta
	_since += delta
	if _since < 1.0 / RATE: return
	_since = 0.0
	var mark := _board_mark()
	if mark != _mark:
		_mark = mark
		_measure()
		queue_redraw()
	elif not still and not lines.is_empty(): queue_redraw()

## What the lines depend on, as text: they are measured again only when it changes.
func _board_mark() -> String:
	var links := graph.get_connection_list()
	var sum := Vector2.ZERO
	var count := 0
	for child: Node in graph.get_children():
		if child is GraphNode:
			sum += (child as GraphNode).position + (child as GraphNode).size
			count += 1
	return "%s|%s|%s|%d|%d|%s|%s" % [graph.scroll_offset, graph.zoom, sum, count, links.size(), links.hash(), size]

## Where a line runs on the board, from the dot it leaves to the dot it enters.
func _measure() -> void:
	lines.clear()
	_nodes.clear()
	for child: Node in graph.get_children():
		if child is GraphNode: _nodes.append(Rect2((child as GraphNode).position, (child as GraphNode).size * graph.zoom).grow(-5.0))
	var view := Rect2(Vector2.ZERO, size).grow(40.0)
	for link: Dictionary in graph.get_connection_list():
		var from := graph.get_node_or_null(NodePath(link.from_node)) as GraphNode
		var to := graph.get_node_or_null(NodePath(link.to_node)) as GraphNode
		if from == null or to == null or int(link.from_port) >= from.get_output_port_count() or int(link.to_port) >= to.get_input_port_count(): continue
		var start := from.position + from.get_output_port_position(link.from_port) * graph.zoom
		var end := to.position + to.get_input_port_position(link.to_port) * graph.zoom
		if not view.intersects(Rect2(start, Vector2.ZERO).expand(end)): continue
		var points := graph.get_connection_line(start, end)
		if points.size() < 2: continue
		var lengths := PackedFloat32Array([0.0])
		for index in range(1, points.size()): lengths.append(lengths[index - 1] + points[index - 1].distance_to(points[index]))
		lines.append({"points": points, "lengths": lengths, "total": lengths[-1], "colour": from.get_output_port_color(link.from_port)})

## The point a distance along a line, and the direction the line runs in there.
static func along(line: Dictionary, distance: float) -> Array:
	var points: PackedVector2Array = line.points
	var lengths: PackedFloat32Array = line.lengths
	var low := 0
	var high := lengths.size() - 1
	while high - low > 1:
		var middle := (low + high) / 2
		if lengths[middle] <= distance: low = middle
		else: high = middle
	var span := lengths[high] - lengths[low]
	var part := clampf((distance - lengths[low]) / span, 0.0, 1.0) if span > 0.0 else 0.0
	return [points[low].lerp(points[high], part), (points[high] - points[low]).normalized()]

func _covered(point: Vector2) -> bool:
	for rect: Rect2 in _nodes:
		if rect.has_point(point): return true
	return false

func _draw() -> void:
	var zoom := graph.zoom if graph != null else 1.0
	var radius := clampf(4.8 * zoom, 3.6, 5.2)
	var ring := Color(EditorTheme.color("bg"), 0.85)
	var spacing := SPACING * clampf(zoom, 0.7, 1.0)
	for line: Dictionary in lines:
		var total: float = line.total
		if total < 26.0: continue
		var colour: Color = (line.colour as Color).lightened(0.62)
		if still:
			# Arrowheads that stay where they are: one in the middle of a short line, more on a long one.
			var heads := maxi(1, int(total / (spacing * 2.2)))
			for index in heads:
				var spot := along(line, total * (index + 0.5) / heads)
				if _covered(spot[0]): continue
				var tip: Vector2 = spot[0] + spot[1] * radius * 1.5
				var side: Vector2 = (spot[1] as Vector2).orthogonal() * radius * 1.35
				var back: Vector2 = tip - spot[1] * radius * 3.0
				draw_colored_polygon(PackedVector2Array([tip + spot[1] * 2.0, back - spot[1] * 1.5 + side * 1.25, back - spot[1] * 1.5 - side * 1.25]), ring)
				draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), colour)
			continue
		var distance := fposmod(_time * SPEED, spacing)
		while distance < total:
			# A bubble grows out of the dot it leaves and shrinks into the one it enters.
			var edge := minf(distance, total - distance)
			var size_now := radius * clampf(edge / 14.0, 0.0, 1.0)
			if size_now > 0.8:
				var spot := along(line, distance)
				if not _covered(spot[0]):
					draw_circle(spot[0], size_now + 1.5, ring)
					draw_circle(spot[0], size_now, colour)
			distance += spacing
