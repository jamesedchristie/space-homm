class_name LeaderRules
extends RefCounted
## Faction leaders for diplomacy screens (data/strategic/leaders.json). One leader per
## species, plus the raider warlord (role "barbarian") and the traders' factor (role "minor").
## Pure data helpers: the presentation picks portraits and typewriter text from these.

## Every leader has this many lines per situation (2 or 3 variants each), see validate().
const LINE_KEYS := ["first_contact", "greeting", "hail_war", "war_on_you", "you_declare_war",
		"peace_accepted", "peace_refused", "peace_offer", "offer_declined", "gift", "farewell"]
const PLACEHOLDERS := ["{player}", "{empire}", "{leader}"]
const WARLORD := "raider_warlord"
const FACTOR := "trader_factor"
## Barbarians never negotiate: their screen is a contact screen with taunts only.
const NEGOTIATORS := ["major", "minor"]


## Id of the leader for a faction (state faction dict or campaign faction def).
static func leader_id(faction: Dictionary) -> String:
	match faction.get("role", "major"):
		"barbarian":
			return WARLORD
		"minor":
			return FACTOR
	return faction.get("species", "")


static func negotiates(faction: Dictionary) -> bool:
	return faction.get("role", "major") in NEGOTIATORS and not faction.get("always_hostile", false)


static func leader(data: DataRegistry, faction: Dictionary) -> Dictionary:
	return data.leaders.get(leader_id(faction), {})


## One variant of a line with {player} (the addressed faction's name), {empire} (the
## leader's faction) and {leader} filled in. `salt` picks the variant deterministically.
static func line(data: DataRegistry, faction: Dictionary, key: String, player_name: String, salt: int = 0) -> String:
	var def := leader(data, faction)
	var options: Array = def.get("lines", {}).get(key, [])
	if options.is_empty():
		return ""
	var text: String = options[absi(salt) % options.size()]
	return text.replace("{player}", player_name).replace("{empire}", faction.get("name", "")) \
			.replace("{leader}", def.get("name", ""))


## Problems with the leaders data, as messages (empty when fine).
static func validate(data: DataRegistry) -> PackedStringArray:
	var errors := PackedStringArray()
	var needed: Array[String] = [WARLORD, FACTOR]
	for id: String in data.species:
		needed.append(id)
	for id in needed:
		if not data.leaders.has(id):
			errors.append("no leader for '%s'" % id)
	for id: String in data.leaders:
		var def: Dictionary = data.leaders[id]
		for key: String in ["name", "title", "personality"]:
			if str(def.get(key, "")).is_empty():
				errors.append("leader '%s': missing %s" % [id, key])
		var portrait: Dictionary = def.get("portrait", {})
		if portrait.is_empty():
			errors.append("leader '%s': missing portrait" % id)
		elif portrait.get("look", "") not in ["human", "veltari", "kesh", "sorn"]:
			errors.append("leader '%s': unknown portrait look '%s'" % [id, portrait.get("look", "")])
		for key: String in ["primary", "accent", "skin"]:
			if portrait.has(key) and not Color.html_is_valid(portrait[key]):
				errors.append("leader '%s': portrait.%s is not a colour" % [id, key])
		var lines: Dictionary = def.get("lines", {})
		for key in LINE_KEYS:
			var variants: Variant = lines.get(key, [])
			if not variants is Array or variants.size() < 2 or variants.size() > 3:
				errors.append("leader '%s': line '%s' needs 2-3 variants" % [id, key])
				continue
			for text: Variant in variants:
				if not text is String or text.is_empty():
					errors.append("leader '%s': line '%s' has an empty variant" % [id, key])
				else:
					var stripped: String = text
					for p in PLACEHOLDERS:
						stripped = stripped.replace(p, "")
					if stripped.contains("{") or stripped.contains("}"):
						errors.append("leader '%s': line '%s' has an unknown placeholder" % [id, key])
	return errors
