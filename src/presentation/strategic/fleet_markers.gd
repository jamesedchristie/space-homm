class_name FleetMarkers
extends RefCounted
## Shared 2D marks for fleets on the galaxy map (2D board and the 3D board's overlay).


## A small bouncing arrow over one of your fleets that can still move this turn.
static func draw_ready_chevron(canvas: CanvasItem, at: Vector2) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var p := at + Vector2(0, sin(t * 4.0) * 2.5)
	var pts := PackedVector2Array([p + Vector2(-6, -5), p + Vector2(6, -5), p + Vector2(0, 2)])
	canvas.draw_colored_polygon(PackedVector2Array([pts[0] + Vector2(-1.5, -1.5), pts[1] + Vector2(1.5, -1.5),
			pts[2] + Vector2(0, 2)]), Color(0, 0, 0, 0.8))
	canvas.draw_colored_polygon(pts, Palette.ACTIVE)
