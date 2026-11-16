class_name Planet
extends RefCounted
## A planet on the galaxy map: gives vision, repairs friendly fleets, produces
## resources (type yields + buildings), builds things and can be captured.

var id: String
var name: String
var type: String
var cell: Vector2i
## Faction id, or "" if unclaimed.
var owner := ""
var sensor := 2
var description := ""
## Building ids (see data/empire/buildings.json). Limited by the type's slots.
var buildings: Array[String] = []
## Random or scripted planet traits (data/strategic/planet_traits.json).
var traits: Array[String] = []
## Current build: {} when idle, else {"kind": "building"|"unit", "item": id, "progress": int, "turns": int}
var queue: Dictionary = {}
