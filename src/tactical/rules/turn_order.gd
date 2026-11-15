class_name TurnOrder
extends RefCounted
## Initiative: each round every living unit acts once, highest initiative
## first. Ties are broken by the battle's seeded RNG so results are replayable.


static func build_queue(state: BattleState) -> Array[String]:
	var entries: Array = []
	for u in state.living_units():
		entries.append({"id": u.id, "init": u.get_stat("initiative"), "tiebreak": state.rng.randf()})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["init"] != b["init"]:
			return a["init"] > b["init"]
		return a["tiebreak"] > b["tiebreak"])
	var queue: Array[String] = []
	for e: Dictionary in entries:
		queue.append(e["id"])
	return queue
