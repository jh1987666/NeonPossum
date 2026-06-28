extends Node2D

const Perspective = preload("res://scripts/perspective.gd")

signal activated(gate_type: String)

const LANE_X := [270.0, 540.0, 810.0]
const DESPAWN_Y := 2100.0
const COLLECT_RADIUS := 100.0

var gate_type: String = "ball"
var speed: float = 600.0
var triggered: bool = false
var gate_w: float = 180.0
var gate_h: float = 400.0
var gate_color: Color = Color.WHITE
var t_anim: float = 0.0

@onready var visual: Node2D = $Visual
@onready var body: ColorRect = $Visual/Body
@onready var label: Label = $Visual/Label

func setup(t: Dictionary, lane: int, spd: float, gate_cfg: Dictionary) -> void:
	gate_type = t.id
	speed = spd
	position = Vector2(LANE_X[lane], -100.0)
	gate_w = float(gate_cfg.width)
	gate_h = float(gate_cfg.height)
	gate_color = Color.from_string("#" + t.color, Color.WHITE)
	body.visible = false   # drawn procedurally as a neon portal now
	label.text = t.id.to_upper()
	label.position = Vector2(-gate_w * 0.5, -gate_h - 50.0)
	label.size = Vector2(gate_w, 40)
	label.add_theme_color_override("font_color", gate_color)

func _process(delta: float) -> void:
	if triggered:
		return
	t_anim += delta
	var main: Node = get_parent().get_parent()
	var spd: float = main.get_speed() if main and main.has_method("get_speed") else speed
	position.y += spd * delta
	var pp: float = Perspective.progress(position.y)
	visual.global_position = Vector2(Perspective.converge_x(position.x, pp), Perspective.screen_y(pp))
	var gsc: float = Perspective.depth_scale(pp)
	visual.scale = Vector2(gsc, gsc)
	queue_redraw()

	if main.state == 1:
		var player_pos: Vector2 = main.player.position
		if position.distance_to(player_pos) < COLLECT_RADIUS:
			triggered = true
			emit_signal("activated", gate_type)
			_play_flash()
			return

	if position.y > DESPAWN_Y:
		queue_free()

func _draw() -> void:
	if not visual:
		return
	var s: float = visual.scale.x
	var base: Vector2 = visual.position           # ground-center at this depth
	var w: float = gate_w * s
	var h: float = gate_h * s
	var col := gate_color
	var pulse: float = 0.6 + 0.4 * sin(t_anim * 6.0)

	# ground-contact shadow
	draw_set_transform(base, 0.0, Vector2(w * 0.6, w * 0.18))
	draw_circle(Vector2.ZERO, 1.0, Color(0.0, 0.0, 0.0, 0.45))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var lft: float = base.x - w * 0.5
	var rgt: float = base.x + w * 0.5
	var top: float = base.y - h
	# translucent energy field with vertical scan lines
	draw_rect(Rect2(lft, top, w, h), Color(col.r, col.g, col.b, 0.12 * pulse))
	var rungs := 7
	for i in range(rungs):
		var fy: float = fmod(t_anim * 0.4 + float(i) / float(rungs), 1.0)
		var y: float = top + fy * h
		draw_line(Vector2(lft, y), Vector2(rgt, y), Color(col.r, col.g, col.b, 0.18 * pulse), 2.0 * s)
	# neon frame: glow then bright core on posts + top bar
	var glow := Color(col.r, col.g, col.b, 0.35 * pulse)
	var core := Color(col.r, col.g, col.b, 0.95)
	for pass_w in [16.0 * s, 6.0 * s]:
		var c: Color = glow if pass_w > 9.0 * s else core
		draw_line(Vector2(lft, base.y), Vector2(lft, top), c, pass_w)   # left post
		draw_line(Vector2(rgt, base.y), Vector2(rgt, top), c, pass_w)   # right post
		draw_line(Vector2(lft, top), Vector2(rgt, top), c, pass_w)      # top bar
	# emitter caps
	for cx in [lft, rgt]:
		draw_circle(Vector2(cx, top), 9.0 * s, core)
		draw_circle(Vector2(cx, top), 4.0 * s, Color(1, 1, 1, 0.9))

func _play_flash() -> void:
	var tween := create_tween()
	tween.tween_property(body, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)
