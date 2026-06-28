extends Node2D

# Short-lived neon sparkle burst spawned at a gem's screen position on pickup.
# Draws an expanding ring plus a handful of flung sparks, then frees itself.

var color: Color = Color(1, 0.4, 0.8)
var life: float = 0.0
const LIFE_MAX: float = 0.42
var sparks: Array = []   # each: {pos, vel}
var scale_base: float = 1.0

func configure(col: Color, depth_scale: float) -> void:
	color = col
	scale_base = clampf(depth_scale, 0.3, 1.5)

func _ready() -> void:
	z_index = 60
	var n := 9
	for i in range(n):
		var ang: float = TAU * float(i) / float(n) + randf_range(-0.2, 0.2)
		var spd: float = randf_range(180.0, 420.0) * scale_base
		sparks.append({
			"pos": Vector2.ZERO,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
		})

func _process(delta: float) -> void:
	life += delta
	for s in sparks:
		s.pos += s.vel * delta
		s.vel *= 0.88   # drag
	if life >= LIFE_MAX:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var t: float = clampf(life / LIFE_MAX, 0.0, 1.0)
	var fade: float = 1.0 - t
	# expanding ring
	var ring_r: float = (10.0 + 90.0 * t) * scale_base
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 32,
		Color(color.r, color.g, color.b, 0.6 * fade), 4.0 * scale_base, true)
	# bright core flash early on
	draw_circle(Vector2.ZERO, 16.0 * scale_base * fade, Color(1, 1, 1, 0.8 * fade))
	# sparks
	for s in sparks:
		var p: Vector2 = s.pos
		draw_line(p, p - s.vel.normalized() * 14.0 * scale_base,
			Color(color.r, color.g, color.b, fade), 3.0 * scale_base)
		draw_circle(p, 4.0 * scale_base * fade, Color(1, 1, 1, fade))
