class_name HeroBuilder
extends RefCounted
## Turns a Hero into a tactical unit definition, so heroes fight in missions
## through the same engine as everything else:
##   stats     = class base + growth per level + gear modifiers + trait modifiers
##   abilities = gear abilities (weapon first) + class skills unlocked by level
## The result is passed to BattleEngine as a scenario entry's "unit_def".


static func unit_def(hero: Hero, data: DataRegistry) -> Dictionary:
	var cls: Dictionary = data.hero_classes[hero.class_id]
	var stats: Dictionary = {}
	for stat: String in cls.get("stats", {}):
		stats[stat] = float(cls["stats"][stat])
	for stat: String in cls.get("growth", {}):
		stats[stat] = float(stats.get(stat, 0.0)) + float(cls["growth"][stat]) * (hero.level - 1)

	var abilities: Array[String] = []
	for slot in ["weapon", "gadget", "armor"]:
		var item: Dictionary = data.items.get(hero.gear.get(slot, ""), {})
		_apply_modifiers(stats, item.get("modifiers", {}))
		for ability_id: String in item.get("abilities", []):
			if ability_id not in abilities:
				abilities.append(ability_id)
	for ability_id in skills_at(cls, hero.level):
		if ability_id not in abilities:
			abilities.append(ability_id)
	for trait_id in hero.traits:
		_apply_modifiers(stats, data.traits.get(trait_id, {}).get("modifiers", {}))

	return {
		"id": "hero_" + hero.id,
		"name": hero.name,
		"description": "%s, level %d" % [cls.get("name", hero.class_id), hero.level],
		"tags": ["infantry", "hero"],
		"stats": stats,
		"abilities": abilities,
		"visual": {"placeholder": "hero", "sprite": "", "size": 1.0, "model": "hero"},
		"stat_names": {"hull": "Health", "shields": "Shields"},
	}


## Class skills unlocked at or below `level`, in unlock order.
static func skills_at(cls: Dictionary, level: int) -> Array[String]:
	var out: Array[String] = []
	var levels: Array = cls.get("skills", {}).keys()
	levels.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for lvl: String in levels:
		if int(lvl) <= level:
			for ability_id: String in cls["skills"][lvl]:
				out.append(ability_id)
	return out


## The status a hero's fleet gets in battle while the hero commands it.
static func command_status(hero: Hero, data: DataRegistry) -> String:
	return data.hero_classes.get(hero.class_id, {}).get("command_status", "")


static func _apply_modifiers(stats: Dictionary, modifiers: Dictionary) -> void:
	for stat: String in modifiers:
		var m: Dictionary = modifiers[stat]
		var base: float = stats.get(stat, BattleUnit.DEFAULT_STATS.get(stat, 0.0))
		stats[stat] = (base + float(m.get("add", 0.0))) * float(m.get("mul", 1.0))
