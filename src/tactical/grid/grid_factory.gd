class_name GridFactory
extends RefCounted
## Builds the right TacticalGrid for a map definition. Add new grid shapes
## (e.g. "square" for ground missions) here.


static func from_map(map_def: Dictionary, terrain_defs: Dictionary) -> TacticalGrid:
	var kind: String = map_def.get("grid", "hex")
	match kind:
		"hex":
			return HexGrid.from_map(map_def, terrain_defs)
	push_error("GridFactory: unknown grid type '%s'" % kind)
	return null
