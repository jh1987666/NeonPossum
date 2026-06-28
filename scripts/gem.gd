extends Node2D

const Perspective = preload("res://scripts/perspective.gd")
const BurstScene = preload("res://scripts/gem_burst.gd")

signal collected(value: int)

const LANE_X := [270.0, 540.0, 810.0]
const DESPAWN_Y := 2100.0
const COLLECT_RADIUS := 80.0

var gem_value: int = 1
var speed: float = 600.0
var done: bool = false
var gem_color: Color = Color(1, 0.4, 0.8)
var gem_size: float = 40.0
var spin: float = 0.0
var screen_pos: Vector2 = Vector2.ZERO
var cur_scale: float = 1.0

@onready var visual: Node2D = $Visual
@onready var body: ColorRect = $Visual/Body

func setup(gem_cfg: Dictionary, lane: int, spd: float, y_offset: float = 0.0) -> void:
	gem_value = gem_cfg.value
	speed = spd
	gem_size = float(gem_cfg.size)
	gem_color = Color.from_string("#" + gem_cfg.color, Color(1, 0.4, 0.8))
	position = Vector2(LANE_X[lane], y_offset)
	body.visible = false   # drawn procedurally now
	spin = randf() * TAU

func _process(delta: float) -> void:
	if done:
		return
	spin += delta * 2.4
	# Move at current world speed so gems stay locked to the floor/obstacles.
	var main: Node = get_parent().get_parent()
	var spd: float = main.get_speed() if main and main.has_method("get_speed") else speed
	position.y += spd * delta
	var pp: float = Perspective.progress(position.y)
	screen_pos = Vector2(Perspective.converge_x(position.x, pp), Perspective.screen_y(pp))
	cur_scale = Perspective.depth_scale(pp)
	visual.global_position = screen_pos
	visual.scale = Vector2(cur_scale, cur_scale)
	queue_redraw()

	if main.state == 1:
		var player_pos: Vector2 = main.player.position
		# Gem magnet: drag nearby gems toward the player.
		if main.player.has_method("is_magnet_active") and main.player.is_magnet_active():
			var pull_range: float = main.player.effective_magnet_range() if main.player.has_method("effective_magnet_range") else main.player.magnet_range
			if position.distance_to(player_pos) < pull_range:
				position = position.move_toward(player_pos, 1500.0 * delta)
		if position.distance_to(player_pos) < COLLECT_RADIUS:
			done = true
			_spawn_burst()
			emit_signal("collected", gem_value)
			queue_free()
			return

	if position.y > DESPAWN_Y:
		queue_free()

func _spawn_burst() -> void:
	var burst := Node2D.new()
	burst.set_script(BurstScene)
	get_parent().add_child(burst)
	burst.global_position = screen_pos
	burst.configure(gem_color, cur_scale)

# Glowing neon faceted gem, drawn in screen space at the perspective position.
func _draw() -> void:
	var s: float = cur_scale
	var c: Vector2 = visual.position
	var r: float = gem_size * 0.7 * s
	var pulse: float = 0.6 + 0.4 * sin(spin * 1.7)

	# soft outer glow
	draw_circle(c, r * 2.0, Color(gem_color.r, gem_color.g, gem_color.b, 0.10 * pulse))
	draw_circle(c, r * 1.35, Color(gem_color.r, gem_color.g, gem_color.b, 0.18 * pulse))

	# faceted diamond (4 points, slowly spinning)
	var pts := PackedVector2Array()
	var n := 6
	for i in range(n):
		var a: float = spin + TAU * float(i) / float(n)
		var rad: float = r if i % 2 == 0 else r * 0.62
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	draw_colored_polygon(pts, Color(gem_color.r, gem_color.g, gem_color.b, 0.9))
	# bright neon rim
	var rim := pts
	rim.append(pts[0])
	draw_polyline(rim, Color(1, 1, 1, 0.85), 2.5 * s)
	# inner highlight
	draw_circle(c, r * 0.28, Color(1, 1, 1, 0.85 * pulse))
