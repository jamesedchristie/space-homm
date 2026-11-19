class_name LabelLayout
extends RefCounted
## Keeps 2D labels projected from 3D from overlapping: each box is pushed up
## until it clears the boxes already placed. Boxes nearer the bottom of the
## screen (nearer the camera) keep their spot; the ones behind move.


## boxes: Array of Rect2 (screen space, in draw order). Returns the vertical
## offset (<= 0) to apply to each.
static func resolve(boxes: Array[Rect2], gap: float = 2.0, max_shift: float = 90.0) -> Array[float]:
	var order: Array[int] = []
	for i in boxes.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return boxes[a].position.y > boxes[b].position.y)
	var placed: Array[Rect2] = []
	var offsets: Array[float] = []
	offsets.resize(boxes.size())
	offsets.fill(0.0)
	for i in order:
		var r := boxes[i]
		var shift := 0.0
		var moved := true
		var tries := placed.size() + 1  # each placed box can push this one at most once (and huge, far off-screen coordinates can't loop)
		while moved and -shift < max_shift and tries > 0:
			tries -= 1
			moved = false
			var test := Rect2(r.position + Vector2(0, shift), r.size)
			for p in placed:
				if test.grow(gap * 0.5).intersects(p.grow(gap * 0.5)):
					shift = p.position.y - r.size.y - gap - r.position.y
					moved = true
					break
		offsets[i] = shift
		placed.append(Rect2(r.position + Vector2(0, shift), r.size))
	return offsets
