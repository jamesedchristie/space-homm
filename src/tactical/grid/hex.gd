class_name Hex
extends RefCounted
## Pure hex math on axial coordinates (q, r), stored in Vector2i (x = q, y = r).
## Pointy-top orientation. Reference: https://www.redblobgames.com/grids/hexagons/
##
## Content files use "offset" (column, row) coordinates because they are easier
## to author; HexGrid converts them with oddr_to_axial().

const SQRT3 := 1.7320508075688772

const DIRECTIONS := [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


static func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in DIRECTIONS:
		out.append(c + d)
	return out


@warning_ignore("integer_division")
static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2


## Rounds fractional axial coordinates to the nearest hex.
static func round_axial(qf: float, rf: float) -> Vector2i:
	var sf := -qf - rf
	var q := roundf(qf)
	var r := roundf(rf)
	var s := roundf(sf)
	var dq := absf(q - qf)
	var dr := absf(r - rf)
	var ds := absf(s - sf)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(int(q), int(r))


## Hexes on the straight line from a to b, inclusive of both ends.
static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := distance(a, b)
	if n == 0:
		out.append(a)
		return out
	# Nudge so lines that run exactly along hex edges resolve consistently.
	var aq := a.x + 1e-6
	var ar := a.y + 2e-6
	var bq := b.x + 1e-6
	var br := b.y + 2e-6
	for i in range(n + 1):
		var t := float(i) / float(n)
		out.append(round_axial(lerpf(aq, bq, t), lerpf(ar, br, t)))
	return out


## Every hex within `radius` steps of center (including center).
static func within(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dq in range(-radius, radius + 1):
		for dr in range(maxi(-radius, -dq - radius), mini(radius, -dq + radius) + 1):
			out.append(center + Vector2i(dq, dr))
	return out


static func to_pixel(c: Vector2i, size: float) -> Vector2:
	return Vector2(size * SQRT3 * (c.x + c.y / 2.0), size * 1.5 * c.y)


static func from_pixel(p: Vector2, size: float) -> Vector2i:
	var q := (SQRT3 / 3.0 * p.x - p.y / 3.0) / size
	var r := (2.0 / 3.0 * p.y) / size
	return round_axial(q, r)


static func corners(center: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * i - 30.0)
		pts.append(center + Vector2(cos(angle), sin(angle)) * size)
	return pts


## Offset "odd-r" (column, row) -> axial. Odd rows are shoved right.
@warning_ignore("integer_division")
static func oddr_to_axial(col_row: Vector2i) -> Vector2i:
	var row := col_row.y
	return Vector2i(col_row.x - (row - (row & 1)) / 2, row)


@warning_ignore("integer_division")
static func axial_to_oddr(c: Vector2i) -> Vector2i:
	return Vector2i(c.x + (c.y - (c.y & 1)) / 2, c.y)
