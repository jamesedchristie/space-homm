class_name DiplomacyRules
extends RefCounted
## War and peace between factions, and how AI-run factions answer proposals.
## Opinion (-100..100) is how one faction feels about another; it drops when
## attacked or robbed of planets and rises with gifts and time at peace.
##
## Rules while at peace: fleets can't attack each other or pass through each
## other, and planets can't be captured from each other.

const GIFT_CREDITS := 50
const GIFT_OPINION := 10
const ATTACKED_OPINION := -15
const PLANET_TAKEN_OPINION := -20
const WAR_DECLARED_OPINION := -30
const PEACE_DRIFT := 1
const MIN_WAR_TURNS := 3
## AI accepts peace at this opinion or better...
const PEACE_OPINION := 10
## ...or when it is clearly losing (its strength below this fraction of yours)...
const LOSING_RATIO := 0.7
## ...or when it has been at war this long and is this far ahead of you on score.
const CONTENT_WAR_TURNS := 12
const CONTENT_SCORE_RATIO := 1.4


static func change_opinion(state: GalaxyState, of_faction: String, about: String, delta: int) -> void:
	if of_faction.is_empty() or about.is_empty() or of_faction == about:
		return
	var row: Dictionary = state.opinions.get_or_add(of_faction, {})
	row[about] = clampi(int(row.get(about, 0)) + delta, -100, 100)


## Total effective hit points of the faction's fleets.
static func military_strength(engine: GalaxyEngine, faction_id: String) -> float:
	var total := 0.0
	for f in engine.state.fleets_of(faction_id):
		total += f.strength(engine.data)
	return total


## Why `target` (AI-run) refuses peace with `proposer`, or "" if it accepts.
static func peace_refusal(engine: GalaxyEngine, target: String, proposer: String) -> String:
	var s := engine.state
	var t := s.faction(target)
	if t.get("always_hostile", false):
		return "%s don't negotiate." % t["name"]
	if s.turn_number - int(s.relation(target, proposer)["since"]) < MIN_WAR_TURNS:
		return "%s won't talk peace so soon after the war began." % t["name"]
	var losing := military_strength(engine, target) < military_strength(engine, proposer) * LOSING_RATIO
	# A power well ahead on score is content once a war has dragged on: it takes the peace.
	var content := s.turn_number - int(s.relation(target, proposer)["since"]) >= CONTENT_WAR_TURNS \
			and float(EmpireRules.score(engine, target)) > float(EmpireRules.score(engine, proposer)) * CONTENT_SCORE_RATIO
	if s.opinion(target, proposer) >= PEACE_OPINION or losing or content:
		return ""
	return "%s refuse: they don't trust you enough (opinion %d, need %d). Gifts help." % [
			t["name"], s.opinion(target, proposer), PEACE_OPINION]
