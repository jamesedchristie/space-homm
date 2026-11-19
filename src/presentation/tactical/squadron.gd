class_name Squadron
extends RefCounted
## Squadrons: a battle unit of small warships is drawn as several craft in
## formation inside its hex (unit visual "squadron": n, each craft scaled by
## "craft_size"). The number of craft shown follows the unit's hull, like a
## Heroes stack: ceil(n * hull / max_hull), at least one while it lives.
## Capital ships and stations are a single, bigger model (squadron 1).

## Formation slots per squadron size, in model space (+x forward, +z to the
## side, y a little stagger) and how far (seconds) each craft trails the lead.
const FORMATIONS := {
	1: [[0.0, 0.0, 0.0]],
	2: [[0.2, 0.05, -0.26], [-0.2, -0.05, 0.3]],
	3: [[0.32, 0.0, 0.0], [-0.2, 0.07, -0.42], [-0.22, -0.06, 0.42]],
	4: [[0.36, 0.0, 0.0], [0.0, 0.06, -0.34], [0.0, -0.05, 0.34], [-0.36, 0.02, 0.0]],
	5: [[0.42, 0.0, 0.0], [0.12, 0.06, -0.3], [0.1, -0.05, 0.3], [-0.2, 0.1, -0.58], [-0.22, -0.08, 0.58]],
}
const LAGS := {
	1: [0.0],
	2: [0.0, 0.1],
	3: [0.0, 0.09, 0.11],
	4: [0.0, 0.07, 0.08, 0.14],
	5: [0.0, 0.07, 0.08, 0.14, 0.15],
}


## Craft in a full-strength squadron of this unit definition (1 for singles).
static func size_of(def: Dictionary) -> int:
	return maxi(1, int(def.get("visual", {}).get("squadron", 1)))


## Craft still flying: ceil(n * hull / max_hull); 0 once the hull is gone.
static func craft_count(n: int, hull: int, max_hull: int) -> int:
	if hull <= 0 or n <= 0:
		return 0
	return clampi(ceili(float(n) * float(hull) / float(maxi(1, max_hull))), 1, n)


static func slots(n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if FORMATIONS.has(n):
		for p: Array in FORMATIONS[n]:
			out.append(Vector3(p[0], p[1], p[2]))
		return out
	# Bigger wings: a V of pairs behind the lead.
	out.append(Vector3(0.45, 0, 0))
	for i in range(1, n):
		var rank := (i + 1) / 2
		var side := -1.0 if i % 2 == 1 else 1.0
		out.append(Vector3(0.45 - rank * 0.28, 0.05 * side, side * rank * 0.28))
	return out


static func lags(n: int) -> Array[float]:
	var out: Array[float] = []
	if LAGS.has(n):
		for v: float in LAGS[n]:
			out.append(v)
		return out
	for i in n:
		out.append(0.07 * ((i + 1) / 2))
	return out
