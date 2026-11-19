class_name HeroFaces
extends RefCounted
## Portrait definitions for heroes: each hero gets a stable face from their
## species (the owner's) and id: skin, hair, eyes and age vary within the
## species' look, the uniform takes the empire's colour, and the backdrop is
## the species' leader's. Uses the same LeaderPortrait as the diplomacy screen.

const SKIN := {
	"human": ["#f1c7a8", "#d29a7c", "#b27a5a", "#8a5a3f", "#5e3b28"],
	"veltari": ["#e6e2f0", "#dcd6ec", "#efe9f6", "#d4dbea"],
	"kesh": ["#a56f43", "#8e5a35", "#b97f4e", "#7f5b3a"],
	"sorn": ["#8c97a3", "#7d8996", "#9aa3ad", "#6f7b88"],
}
const HAIR := {
	"human": ["#2b1c14", "#4a2f22", "#6b4a2b", "#b88a4a", "#1a1a1a", "#8c8c8c"],
	"veltari": ["#f0f2ff", "#e2e6ff", "#d9f1ff"],
	"kesh": ["#3a261a", "#1f1510", "#5a2a1c"],
	"sorn": [""],
}
const STYLES := {
	"human": ["short", "short", "bun", "long"],
	"veltari": ["long", "short"],
	"kesh": ["braids", "short", "mohawk"],
	"sorn": ["none"],
}
const EYES := {
	"human": ["#4f7f9c", "#5a3d2a", "#3f6b4a", "#6b6b6b"],
	"veltari": ["#9ee7ff", "#c9a8ff"],
	"kesh": ["#e8a331", "#d1652a"],
	"sorn": ["#1c1a24", "#2a2018"],
}


static func definition(data: DataRegistry, species: String, hero_id: String, team_color: Color) -> Dictionary:
	var look := species if SKIN.has(species) else "human"
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash(hero_id)) + 101
	var p: Dictionary = data.leaders.get(look, {}).get("portrait", {}).duplicate(true)
	p["look"] = look
	p["skin"] = _pick(SKIN[look], rng)
	p["hair"] = _pick(HAIR[look], rng)
	p["hair_style"] = _pick(STYLES[look], rng)
	p["eyes"] = _pick(EYES[look], rng)
	p["age"] = rng.randf_range(0.2, 0.7)
	p["jaw"] = rng.randf_range(0.2, 0.6)
	p["primary"] = team_color.darkened(0.55).to_html(false)
	p["glow"] = team_color.to_html(false)
	return {"name": "", "portrait": p}


static func _pick(options: Array, rng: RandomNumberGenerator) -> String:
	return str(options[rng.randi() % options.size()])
