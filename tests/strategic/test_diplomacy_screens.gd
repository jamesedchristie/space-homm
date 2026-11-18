extends TestCase
## What the diplomacy screens rely on: leaders data, first contact, AI war declarations
## and AI peace offers (the engine side). The screens themselves are presentation only.


func _as(e: GalaxyEngine, faction_id: String) -> void:
	for i in e.state.factions.size():
		if e.state.factions[i]["id"] == faction_id:
			e.state.current_faction_index = i
	e.state.pending_event = {}


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(ev: Dictionary) -> String: return ev["type"])


## a (player) with three ships against b (one ship), at war, long enough for talks.
func _war(extra: Dictionary = {}) -> GalaxyEngine:
	var base := {
		"factions": [{"id": "a", "controller": "player"}, {"id": "b", "controller": "ai"}],
		"resources": {"a": {"credits": 200}},
	}
	base.merge(extra, true)
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["a", "test_dummy", 1, 3], ["a", "test_dummy", 0, 4],
			["b", "test_dummy", 8, 2]], base)
	e.state.turn_number = 6
	return e


# --- Leaders data -------------------------------------------------------------

func test_leaders_data_is_valid() -> void:
	var data := DataRegistry.get_default()
	assert_eq(LeaderRules.validate(data).size(), 0, "\n".join(LeaderRules.validate(data)))
	for id: String in data.species:
		assert_true(data.leaders.has(id), "a leader for species '%s'" % id)
	assert_true(data.leaders.has(LeaderRules.WARLORD))
	assert_true(data.leaders.has(LeaderRules.FACTOR))
	assert_eq(data.errors.size(), 0, "\n".join(data.errors))


func test_every_shipped_campaign_faction_has_a_leader_with_every_line() -> void:
	var data := DataRegistry.get_default()
	for campaign_id: String in data.campaigns:
		for f: Dictionary in data.campaigns[campaign_id]["factions"]:
			if f.get("controller", "") == "player":
				continue
			var def := LeaderRules.leader(data, f)
			assert_false(def.is_empty(), "%s: faction %s has a leader" % [campaign_id, f["id"]])
			for key in LeaderRules.LINE_KEYS:
				var text := LeaderRules.line(data, f, key, "Terran Alliance", 3)
				assert_false(text.is_empty(), "%s/%s: line %s" % [campaign_id, f["id"], key])
				assert_false(text.contains("{"), "%s/%s: placeholders filled in %s" % [campaign_id, f["id"], key])


func test_leader_roles() -> void:
	assert_eq(LeaderRules.leader_id({"role": "barbarian", "species": "kesh"}), LeaderRules.WARLORD)
	assert_eq(LeaderRules.leader_id({"role": "minor", "species": "sorn"}), LeaderRules.FACTOR)
	assert_eq(LeaderRules.leader_id({"species": "veltari"}), "veltari")
	assert_false(LeaderRules.negotiates({"role": "barbarian"}), "raiders never negotiate")
	assert_true(LeaderRules.negotiates({"role": "minor"}))


func test_leader_lines_pick_variants() -> void:
	var data := DataRegistry.get_default()
	var faction := {"role": "major", "species": "kesh", "name": "Kesh Dominion"}
	var seen := {}
	for salt in 6:
		seen[LeaderRules.line(data, faction, "first_contact", "Terran Alliance", salt)] = true
	assert_true(seen.size() >= 2, "several variants")
	var war := LeaderRules.line(data, faction, "war_on_you", "Terran Alliance", 0)
	assert_false(war.is_empty() or war.contains("{"))


# --- First contact ------------------------------------------------------------

func test_first_contact_fires_once_per_pair_and_is_saved() -> void:
	var e := Fixtures.galaxy([["a", "test_fast_dummy", 1, 2], ["b", "test_dummy", 6, 2]])
	assert_false(e.state.has_met("a", "b"), "out of sight at the start")
	var move := e.submit(MoveFleetCommand.new("a", e.state.fleets_of("a")[0].id, e.state.grid.cell_from_layout(Vector2i(3, 2))))
	assert_true(move.ok, move.error)
	var contacts := move.events.filter(func(ev: Dictionary) -> bool: return ev["type"] == GalaxyEvents.FIRST_CONTACT)
	assert_eq(contacts.size(), 1)
	assert_eq(contacts[0]["factions"], ["a", "b"])
	assert_true(e.state.has_met("b", "a"), "contact is mutual")
	# Moving about in view again does not repeat it.
	var back := e.submit(MoveFleetCommand.new("a", e.state.fleets_of("a")[0].id, e.state.grid.cell_from_layout(Vector2i(2, 2))))
	assert_eq(_types(back.events).count(GalaxyEvents.FIRST_CONTACT), 0)
	# And it survives a save.
	var save := GalaxySave.to_dict(e, "test_campaign")
	assert_true(save["state"]["met"].has("a|b"))


func test_met_round_trips_through_a_save() -> void:
	var data := DataRegistry.get_default()
	var e := GalaxyEngine.from_campaign(data, "random_sector", 4)
	e.start()
	e.state.met["patrol|veltari"] = 3
	e.state.peace_offers["veltari>patrol"] = {"from": "veltari", "to": "patrol", "turn": 3, "status": "pending"}
	var save := GalaxySave.to_dict(e, "random_sector")
	var out := GalaxySave.from_dict(data, save)
	assert_true(out.has("engine"), str(out.get("error", "")))
	var e2: GalaxyEngine = out["engine"]
	assert_eq(e2.state.met, e.state.met)
	assert_eq(e2.state.peace_offers, e.state.peace_offers)
	# Older saves without the record treat everyone as already met.
	save["state"].erase("met")
	var old: GalaxyEngine = GalaxySave.from_dict(data, save)["engine"]
	assert_true(old.state.has_met("patrol", "traders"))
	assert_true(old.state.has_met("kesh", "veltari"))


# --- AI declares war ----------------------------------------------------------

func test_ai_war_declaration_emits_the_event_the_screen_listens_to() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 8, 2], ["b", "test_dummy", 8, 3]], {
		"factions": [{"id": "a", "controller": "player"}, {"id": "b", "controller": "ai"}],
		"relations": [{"factions": ["a", "b"], "status": "peace", "opinion": -60}],
	})
	var cmd := GalaxyAI.new()._diplomacy(e, "b")
	assert_true(cmd is DiplomacyCommand, "the hated, weaker neighbour gets a war declaration")
	assert_eq((cmd as DiplomacyCommand).action, "declare_war")
	_as(e, "b")
	var result := e.submit(cmd)
	assert_true(result.ok, result.error)
	var declared := result.events.filter(func(ev: Dictionary) -> bool: return ev["type"] == GalaxyEvents.WAR_DECLARED)
	assert_eq(declared.size(), 1)
	assert_eq(declared[0]["faction"], "b")
	assert_eq(declared[0]["target"], "a")
	assert_true(e.state.at_war("a", "b"))


# --- Peace offers -------------------------------------------------------------

func test_ai_offers_peace_to_the_player_and_it_can_be_accepted() -> void:
	var e := _war()
	assert_true(DiplomacyRules.wants_to_offer_peace(e, "b", "a"), "the weaker side at war a while wants peace")
	var cmd := GalaxyAI.new()._diplomacy(e, "b")
	assert_true(cmd is DiplomacyCommand)
	assert_eq((cmd as DiplomacyCommand).action, "offer_peace")
	_as(e, "b")
	var offered := e.submit(cmd)
	assert_true(offered.ok, offered.error)
	assert_true(GalaxyEvents.PEACE_OFFERED in _types(offered.events))
	assert_false(DiplomacyRules.pending_offer(e.state, "b", "a").is_empty())
	assert_false(e.submit(cmd).ok, "no second offer while one waits")
	# The player answers on their own turn.
	assert_false(e.submit(DiplomacyCommand.new("a", "b", "accept_peace")).ok, "not a's turn yet")
	_as(e, "a")
	var accepted := e.submit(DiplomacyCommand.new("a", "b", "accept_peace"))
	assert_true(accepted.ok, accepted.error)
	assert_true(GalaxyEvents.PEACE_SIGNED in _types(accepted.events))
	assert_false(e.state.at_war("a", "b"))
	assert_true(DiplomacyRules.pending_offer(e.state, "b", "a").is_empty())


func test_refusing_a_peace_offer_keeps_the_war_and_blocks_new_offers_for_a_while() -> void:
	var e := _war()
	_as(e, "b")
	assert_true(e.submit(DiplomacyCommand.new("b", "a", "offer_peace")).ok)
	_as(e, "a")
	var refused := e.submit(DiplomacyCommand.new("a", "b", "refuse_peace"))
	assert_true(refused.ok, refused.error)
	assert_true(GalaxyEvents.PEACE_OFFER_REFUSED in _types(refused.events))
	assert_true(e.state.at_war("a", "b"))
	assert_true(DiplomacyRules.pending_offer(e.state, "b", "a").is_empty())
	assert_false(DiplomacyRules.wants_to_offer_peace(e, "b", "a"), "cooldown after a refusal")
	assert_false(e.submit(DiplomacyCommand.new("a", "b", "accept_peace")).ok, "nothing left to accept")
	e.state.turn_number += DiplomacyRules.OFFER_COOLDOWN
	assert_true(DiplomacyRules.wants_to_offer_peace(e, "b", "a"), "wants peace again later")


func test_offers_lapse_and_winners_do_not_offer() -> void:
	var e := _war()
	_as(e, "b")
	e.submit(DiplomacyCommand.new("b", "a", "offer_peace"))
	e.state.turn_number += DiplomacyRules.OFFER_TTL + 1
	_as(e, "a")
	assert_false(e.submit(DiplomacyCommand.new("a", "b", "accept_peace")).ok, "the offer lapsed")
	# The stronger side does not ask for peace.
	var strong := _war()
	assert_false(DiplomacyRules.wants_to_offer_peace(strong, "a", "b"))
	# Nor does anyone who never negotiates.
	var hostile := _war({"factions": [{"id": "a", "controller": "player"}, {"id": "b", "controller": "ai", "always_hostile": true}]})
	assert_false(DiplomacyRules.wants_to_offer_peace(hostile, "b", "a"))
	assert_false(hostile.submit(DiplomacyCommand.new("a", "b", "accept_peace")).ok)


func test_an_autoplayed_player_takes_a_fair_offer() -> void:
	var e := _war()
	_as(e, "b")
	e.submit(DiplomacyCommand.new("b", "a", "offer_peace"))
	_as(e, "a")
	var crushing := GalaxyAI.new()._diplomacy(e, "a")
	assert_eq((crushing as DiplomacyCommand).action, "refuse_peace", "a faction crushing its enemy turns the offer down")
	for fleet in e.state.fleets_of("a").slice(1):
		e.state.fleets.erase(fleet.id)
	var cmd := GalaxyAI.new()._diplomacy(e, "a")
	assert_true(cmd is DiplomacyCommand)
	assert_eq((cmd as DiplomacyCommand).action, "accept_peace")
	assert_true(e.submit(cmd).ok)
	assert_false(e.state.at_war("a", "b"))
