class_name Planet
extends RefCounted
## A planet on the galaxy map. For now planets give vision, repair friendly
## fleets and can be captured; resources and colonies arrive in step 4.

var id: String
var name: String
var type: String
var cell: Vector2i
## Faction id, or "" if unclaimed.
var owner := ""
var sensor := 2
var description := ""
