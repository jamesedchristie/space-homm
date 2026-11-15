class_name HeroProgression
extends RefCounted
## XP and levels, driven by data/heroes/progression.json.


static func max_level(data: DataRegistry) -> int:
	return data.progression.get("xp_thresholds", [0]).size()


## Total XP needed to reach `level`, or -1 past the cap.
static func xp_for_level(data: DataRegistry, level: int) -> int:
	var thresholds: Array = data.progression.get("xp_thresholds", [0])
	if level < 1 or level > thresholds.size():
		return -1
	return int(thresholds[level - 1])


## Adds XP and levels up as needed. Returns the levels gained, in order.
static func add_xp(hero: Hero, amount: int, data: DataRegistry) -> Array[int]:
	var gained: Array[int] = []
	hero.xp += maxi(amount, 0)
	while hero.level < max_level(data) and hero.xp >= xp_for_level(data, hero.level + 1):
		hero.level += 1
		gained.append(hero.level)
	return gained


## Class skills newly unlocked at exactly `level`.
static func skills_unlocked_at(hero: Hero, level: int, data: DataRegistry) -> Array:
	return data.hero_classes[hero.class_id].get("skills", {}).get(str(level), [])
