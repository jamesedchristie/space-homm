class_name PortraitHead
extends RefCounted
## The smooth head of a leader bust: a displaced sphere (jaw taper, chin, cheekbones,
## brow ridge, cranial crest) with vertex colours for blush and shading. The returned
## `front` points let features (eyes, nose, mouth) sit on the real surface.

const W := 0.088  # half width
const H := 0.11  # half height
const D := 0.102  # half depth
const LAT := 44
const LON := 64


## n: unit direction (+z faces forward, +y up). p: shape parameters (jaw, brow, cheek, crest, chin).
static func point(n: Vector3, p: Dictionary) -> Vector3:
	var jaw: float = p.get("jaw", 0.4)
	var brow: float = p.get("brow", 0.2)
	var cheek: float = p.get("cheek", 0.3)
	var crest: float = p.get("crest", 0.0)
	var chin: float = p.get("chin", 0.5)
	var pt := Vector3(n.x * W, n.y * H, n.z * D)
	if n.z < 0.0:
		pt.z *= 1.07
	var fz := maxf(n.z, 0.0)
	# The lower face tapers towards the chin; a strong jaw keeps it wide and square.
	var low := smoothstep(0.2, -0.8, n.y)
	pt.x *= 1.0 - lerpf(0.36, 0.14, jaw) * low
	pt.z += 0.012 * lerpf(0.4, 1.3, chin) * low * fz
	var jaw_corner := exp(-(pow((absf(n.x) - 0.7) / 0.3, 2.0) + pow((n.y + 0.55) / 0.28, 2.0))) * (1.0 - fz * 0.4)
	pt.x += signf(n.x) * jaw * 0.016 * jaw_corner
	# Cheekbones.
	var g := exp(-(pow((absf(n.x) - 0.62) / 0.3, 2.0) + pow((n.y + 0.1) / 0.26, 2.0) + pow((n.z - 0.65) / 0.4, 2.0)))
	pt.x += signf(n.x) * cheek * 0.009 * g
	pt.z += cheek * 0.004 * g
	# Brow ridge, with a soft dip for the eye sockets below it.
	var gb := exp(-pow((n.y - 0.2) / 0.1, 2.0)) * smoothstep(0.3, 0.8, n.z) * (1.0 - pow(absf(n.x), 3.0))
	pt.z += brow * 0.03 * gb
	var socket := exp(-(pow((absf(n.x) - 0.38) / 0.18, 2.0) + pow((n.y - 0.02) / 0.15, 2.0))) * smoothstep(0.5, 0.9, n.z)
	pt.z -= 0.004 * socket * (0.4 + brow)
	# Rounded forehead.
	pt.z *= 1.0 + 0.04 * smoothstep(0.2, 0.7, n.y) * fz
	# Cranial crest: the skull sweeps up and back.
	if crest > 0.0:
		var dir := Vector3(0, 0.78, -0.62).normalized()
		var c := exp(-(1.0 - n.dot(dir)) * 4.2) * (1.0 - 0.35 * pow(absf(n.x), 1.5))
		pt.y += crest * 0.07 * c
		pt.z -= crest * 0.085 * c
		pt.x *= 1.0 - crest * 0.1 * c
	return pt


## {"mesh": ArrayMesh, "front": PackedVector3Array (surface points with z > 0)}.
static func build(p: Dictionary, blush: Color, shade: Color) -> Dictionary:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var front := PackedVector3Array()
	var rows := LAT + 1
	for i in rows:
		var th := PI * float(i) / LAT
		for j in LON:
			var ph := TAU * float(j) / LON
			var n := Vector3(sin(th) * sin(ph), cos(th), sin(th) * cos(ph))
			var pt := point(n, p)
			verts.append(pt)
			cols.append(_color(n, p, blush, shade))
			if n.z > 0.0:
				front.append(pt)
	var idx := PackedInt32Array()
	for i in LAT:
		for j in LON:
			var a := i * LON + j
			var b := i * LON + (j + 1) % LON
			var c := (i + 1) * LON + j
			var d := (i + 1) * LON + (j + 1) % LON
			idx.append_array([a, c, b, b, c, d])
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for k in range(0, idx.size(), 3):
		var fn := (verts[idx[k + 1]] - verts[idx[k]]).cross(verts[idx[k + 2]] - verts[idx[k]])
		for m in 3:
			normals[idx[k + m]] += fn
	for k in normals.size():
		normals[k] = normals[k].normalized() if normals[k].length() > 0.0 else Vector3.UP
	# Godot wants clockwise front faces; the normals above came from the counter-clockwise order.
	for k in range(0, idx.size(), 3):
		var swap := idx[k + 1]
		idx[k + 1] = idx[k + 2]
		idx[k + 2] = swap
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": mesh, "front": front}


static func _color(n: Vector3, p: Dictionary, blush: Color, shade: Color) -> Color:
	var c := Color.WHITE
	var fz := maxf(n.z, 0.0)
	# Blush on cheeks and nose, shadow around the eyes and under the chin.
	var cheeks := exp(-(pow((absf(n.x) - 0.55) / 0.3, 2.0) + pow((n.y + 0.2) / 0.25, 2.0))) * fz
	c = c.lerp(blush, 0.5 * cheeks)
	var sockets := exp(-(pow((absf(n.x) - 0.36) / 0.2, 2.0) + pow((n.y - 0.05) / 0.17, 2.0))) * fz
	c = c.lerp(shade, 0.5 * sockets)
	var chin := smoothstep(-0.75, -1.0, n.y)
	c = c.lerp(shade, 0.4 * chin)
	var brow_shadow := exp(-pow((n.y - 0.3) / 0.07, 2.0)) * smoothstep(0.4, 0.8, n.z) * float(p.get("brow", 0.2))
	c = c.lerp(shade, 0.35 * brow_shadow)
	if float(p.get("crest", 0.0)) > 0.0:
		var band := 0.5 + 0.5 * sin(n.x * 26.0)
		var up := smoothstep(0.25, 0.9, n.y)
		c = c.lerp(shade, 0.22 * band * up)
	return c


## Height of the head surface at (x, y) in head space: z of the nearest front vertices.
static func surface_z(front: PackedVector3Array, x: float, y: float) -> float:
	var best := 1e9
	var z := 0.05
	var best2 := 1e9
	var z2 := 0.05
	for v in front:
		var d := (v.x - x) * (v.x - x) + (v.y - y) * (v.y - y)
		if d < best:
			best2 = best
			z2 = z
			best = d
			z = v.z
		elif d < best2:
			best2 = d
			z2 = v.z
	var w1 := 1.0 / (best + 1e-7)
	var w2 := 1.0 / (best2 + 1e-7)
	return (z * w1 + z2 * w2) / (w1 + w2)
