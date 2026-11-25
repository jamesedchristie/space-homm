class_name TradeRules
extends RefCounted
## Trade between powers (Phase 6):
## - **Trade agreements** between two major powers at peace: each earns PACT_CREDITS a turn plus a
##   little per colony of the partner (PACT_PER_COLONY, at most PACT_MAX). Proposed through
##   DiplomacyCommand "propose_trade" (an AI accepts when it likes you enough), ended by
##   "cancel_trade" or by war. Stored in GalaxyState.trade_pacts.
## - **The market**: a minor power with "market": true in its faction definition (the Free Traders)
##   buys and sells strategic resources for credits to anyone it has met and is at peace with
##   (MarketCommand). Prices are in economy.json "market" (credits per unit; buying costs
##   BUY_MARKUP times the price). Each deal warms the traders to you a little.

const PACT_CREDITS := 3
const PACT_PER_COLONY := 0.5
const PACT_MAX := 8
## An AI signs an agreement with a power it thinks at least this well of.
const PACT_OPINION := 5
const BUY_MARKUP := 2.0
const DEAL_OPINION := 1


static func has_pact(s: GalaxyState, a: String, b: String) -> bool:
	return s.trade_pacts.has(GalaxyState.relation_key(a, b))


static func partners(s: GalaxyState, faction_id: String) -> Array[String]:
	var out: Array[String] = []
	for f in s.factions:
		if f["id"] != faction_id and has_pact(s, faction_id, f["id"]):
			out.append(f["id"])
	return out


## Credits a turn this faction earns from its agreement with `partner`.
static func pact_income(engine: GalaxyEngine, faction_id: String, partner: String) -> int:
	var s := engine.state
	if not has_pact(s, faction_id, partner) or s.at_war(faction_id, partner) or s.is_eliminated(partner):
		return 0
	var colonies := 0
	for p in s.planets_of(partner):
		colonies += p.colonies().size()
	return mini(PACT_CREDITS + int(colonies * PACT_PER_COLONY), PACT_MAX)


static func pacts_income(engine: GalaxyEngine, faction_id: String) -> int:
	var total := 0
	for partner in partners(engine.state, faction_id):
		total += pact_income(engine, faction_id, partner)
	return total


## Why `target` won't sign an agreement with `proposer` now ("" if it would).
static func pact_refusal(engine: GalaxyEngine, target: String, proposer: String) -> String:
	var s := engine.state
	var f := s.faction(target)
	if f.get("role", "major") != "major" or s.faction(proposer).get("role", "major") != "major":
		return "Only the great powers sign trade agreements"
	if s.at_war(target, proposer):
		return "Not while we are at war"
	if has_pact(s, target, proposer):
		return "We already trade"
	if f.get("controller", "") != "player" and s.opinion(target, proposer) < PACT_OPINION:
		return "They don't trust you enough yet (opinion %d, they want %d)" % [s.opinion(target, proposer), PACT_OPINION]
	return ""


# --- The market ---------------------------------------------------------------

## The faction running the market that `faction_id` can use now, or "".
static func market_for(engine: GalaxyEngine, faction_id: String) -> String:
	var s := engine.state
	for f in s.factions:
		if f.get("market", false) and not s.is_eliminated(f["id"]) and not s.at_war(faction_id, f["id"]) \
				and (s.has_met(faction_id, f["id"]) or f["id"] == faction_id):
			return f["id"]
	return ""


## Price in credits of one unit when selling it to the market (0 if it isn't traded).
static func price(engine: GalaxyEngine, resource: String) -> int:
	return int(engine.data.economy.get("market", {}).get(resource, 0))


## Credits for a deal: positive amount buys (costs credits), negative sells (earns them).
static func deal_credits(engine: GalaxyEngine, resource: String, amount: int) -> int:
	if amount > 0:
		return -int(ceil(price(engine, resource) * BUY_MARKUP * amount))
	return price(engine, resource) * -amount


## Why a market deal can't be made ("" if it can).
static func deal_error(engine: GalaxyEngine, faction_id: String, resource: String, amount: int) -> String:
	if market_for(engine, faction_id).is_empty():
		return "No market: meet the Free Traders and stay at peace with them"
	if price(engine, resource) <= 0:
		return "The market doesn't trade that"
	if amount == 0:
		return "Nothing to trade"
	var stock: Dictionary = engine.state.resources.get(faction_id, {})
	if amount < 0 and int(stock.get(resource, 0)) < -amount:
		return "Not enough to sell"
	if amount > 0 and int(stock.get("credits", 0)) < -deal_credits(engine, resource, amount):
		return "Not enough credits"
	return ""
