class_name Palette
extends RefCounted
## Placeholder visual identity. Replace with a Godot Theme once asset packs
## arrive; until then every color lives here.

const TEAM_COLORS := [Color("3fb8d8"), Color("e8643c"), Color("9ad04a"), Color("c75bd6")]
## Matching sprite color variants in the Kenney ship set, per team.
const TEAM_SPRITE_COLORS := ["blue", "orange", "green", "red"]

const CELL_FILL := Color(0.06, 0.10, 0.18, 0.28)
const CELL_LINE := Color(0.40, 0.65, 0.85, 0.22)
const REACHABLE := Color(0.25, 0.70, 1.00, 0.22)
const PATH := Color(0.45, 0.85, 1.00, 0.85)
const TARGET := Color(1.00, 0.35, 0.25, 0.20)
const AREA := Color(1.00, 0.60, 0.20, 0.45)
const HOVER := Color(1.00, 1.00, 1.00, 0.85)
const ACTIVE := Color(1.00, 0.88, 0.30)
const FOG_UNEXPLORED := Color(0.015, 0.02, 0.035, 1.0)
const FOG_DIM := Color(0.0, 0.0, 0.02, 0.5)
const NEUTRAL := Color(0.62, 0.64, 0.70)

const HULL := Color("5fd068")
const SHIELDS := Color("4aa8ff")
const TEXT := Color(0.86, 0.91, 1.0)
const TEXT_DIM := Color(0.55, 0.62, 0.75)
const BAD := Color("ff5a4a")
const GOOD := Color("7be08a")

const PANEL_BG := Color(0.035, 0.05, 0.09, 0.88)
const PANEL_BORDER := Color(0.25, 0.55, 0.75, 0.55)

const DAMAGE_COLORS := {
	"kinetic": Color("b6f07a"),
	"energy": Color("6fd6ff"),
	"explosive": Color("ff7a3c"),
}
## Laser sprite color per damage type (Kenney laser set).
const DAMAGE_LASERS := {"kinetic": "Green", "energy": "Blue", "explosive": "Red"}


static func team_color(team: int) -> Color:
	return TEAM_COLORS[team % TEAM_COLORS.size()]


## Resolves a visual.sprite path, replacing "{team}" with the team's color variant.
static func team_sprite(path: String, team: int) -> String:
	return path.replace("{team}", TEAM_SPRITE_COLORS[team % TEAM_SPRITE_COLORS.size()])


static func damage_color(damage_type: String) -> Color:
	return DAMAGE_COLORS.get(damage_type, Color.WHITE)


static func hex(c: Color) -> String:
	return c.to_html(false)
