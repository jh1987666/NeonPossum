extends Node2D

enum State { IDLE, RUN, JUMP, SLIDE, BALL, JETPACK, HOVERBIKE, DEAD }

const LANE_X := [270.0, 540.0, 810.0]
const GROUND_Y := 1500.0
const JETPACK_Y    := GROUND_Y - 380.0
const HOVERBIKE_Y  := GROUND_Y - 200.0

var state: State = State.IDLE
var lane: int = 1
var target_x: float = LANE_X[1]
var jump_velocity: float = 0.0
var jump_timer: float = 0.0
var slide_timer: float = 0.0
var slide_held: bool = false
var _slide_queued: bool = false   # slide pressed mid-air → dive + slide on landing
var ball_timer: float = 0.0
var jetpack_timer: float = 0.0
var hoverbike_timer: float = 0.0

# Character perk state (reset each run via apply_perk)
var perk_duration_mult: float = 1.0   # LUMEN: power-up duration bonus
var perk_passive_magnet: bool = false  # ZOE: always-on small magnet
var perk_passive_magnet_range: float = 280.0
# Roof-riding: when she lands on top of a tall vehicle, her "ground" is raised to
# that vehicle's roof until it scrolls out from under her, then she drops off.
var ground_override: float = GROUND_Y
var ride_obstacle: Node = null
var shield_active: bool = false
var speed_mult: float = 1.0
var speed_timer: float = 0.0
var magnet_timer: float = 0.0
var magnet_range: float = 620.0
var jump_buffer_timer: float = 0.0
const JUMP_BUFFER: float = 0.13
var cfg_ball_jump_height: float = 300.0
var cfg_ball_jump_duration: float = 0.35
var is_alive: bool = false

var config: Dictionary
var cfg_lane_duration: float = 0.12
var cfg_jump_height: float = 480.0
var cfg_jump_duration: float = 0.5
var cfg_slide_duration: float = 1.5

var touch_start: Vector2 = Vector2.ZERO
var swipe_threshold: float = 120.0

# Run cycle
var run_dist: float = 0.0
var run_frame_idx: int = 0
const RUN_FRAME_DIST: float = 90.0  # pixels traveled per frame step

@onready var player_sprite: Sprite2D = $PlayerSprite
@onready var collision: Area2D = $Hitbox
@onready var anim: AnimationPlayer = $AnimationPlayer

var tex_run: Array[Texture2D] = []
var tex_jump: Texture2D
var tex_slide: Texture2D
var tex_ball: Texture2D
var tex_death_face: Texture2D
var tex_death_butt: Texture2D

var shield_pulse: float = 0.0
var puffs: Array = []   # {t, s} expanding dust rings at the feet
var anim_t: float = 0.0  # continuous time for visual animations
var _in_dumpster: bool = false
var _dumpster_t: float = 0.0

signal died
signal shield_changed(active: bool)

func _ready() -> void:
	position = Vector2(LANE_X[1], GROUND_Y)
	z_index = 50
	_load_textures()
	hide()

func _load_textures() -> void:
	var base := "res://assets/sprites/final/"
	for i in range(1, 5):
		var t := load(base + "run_0%d.png" % i) as Texture2D
		if t:
			tex_run.append(t)
	tex_jump       = load(base + "jump.png")
	tex_slide      = load(base + "slide.png")
	tex_ball       = load(base + "ball.png")
	tex_death_face = load(base + "death_face.png")
	tex_death_butt = load(base + "death_butt.png")
	if tex_run.size() > 0:
		player_sprite.texture = tex_run[0]

func start() -> void:
	# Pull tunable values from game_config.json (was hardcoded before)
	if config and config.has("player"):
		cfg_jump_height = config.player.jump_height
		cfg_jump_duration = config.player.jump_duration
		cfg_ball_jump_height = config.player.get("ball_jump_height", 300.0)
		cfg_ball_jump_duration = config.player.get("ball_jump_duration", 0.35)
		cfg_slide_duration = config.player.slide_duration
		cfg_lane_duration = config.lanes.switch_duration
	show()
	is_alive = true
	lane = 1
	position = Vector2(LANE_X[1], GROUND_Y)
	target_x = LANE_X[1]
	state = State.RUN
	shield_active = false
	speed_mult = 1.0
	_lean = 0.0
	player_sprite.rotation = 0.0
	player_sprite.position.y = 0.0
	player_sprite.visible = true
	ground_override = GROUND_Y
	ride_obstacle = null
	_slide_queued = false
	_in_dumpster = false
	_dumpster_t = 0.0

func apply_perk(char_id: String) -> void:
	match char_id:
		"zoe":
			perk_passive_magnet = true
		"lumen":
			perk_duration_mult = 1.25
		"nova", "kane":
			shield_active = true
			emit_signal("shield_changed", true)
		"vibe":
			cfg_lane_duration = maxf(0.06, cfg_lane_duration * 0.7)
		"pixel":
			cfg_jump_height *= 1.25

func _process(delta: float) -> void:
	anim_t += delta
	if _in_dumpster and state == State.DEAD:
		_dumpster_t = minf(_dumpster_t + delta * 2.5, 1.0)
		queue_redraw()
	if not is_alive:
		return
	_handle_lane_slide(delta)
	_handle_jump(delta)
	_handle_slide_timer(delta)
	_handle_ball_timer(delta)
	_handle_jetpack_timer(delta)
	_handle_hoverbike_timer(delta)
	_handle_speed_timer(delta)
	var spd: float = get_parent().get_speed() if has_node("..") else 600.0
	_advance_run_anim(spd * delta)
	_update_hitbox()
	_apply_run_feel(delta)
	_age_puffs(delta)
	shield_pulse += delta  # general anim clock for shield + magnet auras
	queue_redraw()  # keep ground shadow (and powerup auras) rendering

func _input(event: InputEvent) -> void:
	if not is_alive:
		return

	# Keyboard controls (desktop testing)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_A:  _move_left()
			KEY_RIGHT, KEY_D: _move_right()
			KEY_UP, KEY_W, KEY_SPACE: _jump()
			KEY_DOWN, KEY_S:  _slide()

	# Touch swipe
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_start = event.position
		else:
			_evaluate_swipe(event.position - touch_start)

	# Mouse drag (desktop fallback)
	if event is InputEventMouseButton and event.pressed:
		touch_start = event.position
	elif event is InputEventMouseButton and not event.pressed:
		_evaluate_swipe(event.position - touch_start)

func _evaluate_swipe(delta: Vector2) -> void:
	if delta.length() < swipe_threshold:
		return
	if abs(delta.x) > abs(delta.y):
		if delta.x < 0:
			_move_left()
		else:
			_move_right()
	else:
		if delta.y < 0:
			_jump()
		else:
			_slide()

func _move_left() -> void:
	if lane > 0:
		lane -= 1
		target_x = LANE_X[lane]

func _move_right() -> void:
	if lane < 2:
		lane += 1
		target_x = LANE_X[lane]

func _jump() -> void:
	if state == State.JUMP:
		jump_buffer_timer = JUMP_BUFFER
		return
	if state == State.JETPACK or state == State.HOVERBIKE or state == State.DEAD:
		return
	if state == State.SLIDE:
		slide_timer = 0.0
		slide_held = false
	if state == State.BALL:
		# Ball can only bounce from the ground (not mid-air re-launch)
		if position.y >= ground_override:
			jump_velocity = -(2.0 * cfg_ball_jump_height) / cfg_ball_jump_duration
			Sfx.play("jump")
		return
	state = State.JUMP
	jump_velocity = -(2.0 * cfg_jump_height) / cfg_jump_duration
	_spawn_puff(0.7)
	Sfx.play("jump")

func _slide() -> void:
	if state == State.JETPACK or state == State.HOVERBIKE or state == State.BALL:
		return
	if state == State.JUMP:
		# Air-slide: kill upward momentum, dive hard, and slide the instant we
		# land — so a low obstacle right after a jump is survivable.
		if jump_velocity < 0.0:
			jump_velocity = 0.0
		jump_velocity += 950.0
		_slide_queued = true
		return
	state = State.SLIDE
	slide_held = false
	slide_timer = cfg_slide_duration  # fixed-duration slide (tap/swipe, auto-stands)
	Sfx.play("slide")

func _handle_lane_slide(delta: float) -> void:
	var speed := LANE_X[1] / cfg_lane_duration  # pixels per second for lane switch
	position.x = move_toward(position.x, target_x, speed * delta)

func _handle_jump(delta: float) -> void:
	if state != State.JUMP and state != State.BALL:
		return
	var gravity: float
	if state == State.BALL:
		gravity = (2.0 * cfg_ball_jump_height) / (cfg_ball_jump_duration * cfg_ball_jump_duration)
	else:
		gravity = (2.0 * cfg_jump_height) / (cfg_jump_duration * cfg_jump_duration)
	jump_velocity += gravity * delta
	position.y += jump_velocity * delta
	if position.y >= ground_override:
		position.y = ground_override
		jump_velocity = 0.0
		if state == State.JUMP:
			if jump_buffer_timer > 0.0:
				jump_buffer_timer = 0.0
				jump_velocity = -(2.0 * cfg_jump_height) / cfg_jump_duration
				Sfx.play("jump")
			else:
				state = State.RUN
				_spawn_puff(1.0)
				if _slide_queued:
					_slide_queued = false
					_slide()

func _handle_slide_timer(delta: float) -> void:
	if state != State.SLIDE:
		return
	slide_timer -= delta
	if slide_timer <= 0:
		state = State.RUN

func _handle_ball_timer(delta: float) -> void:
	if state != State.BALL:
		return
	ball_timer -= delta
	if ball_timer <= 0:
		state = State.RUN if position.y >= ground_override else State.JUMP

func _handle_jetpack_timer(delta: float) -> void:
	if state != State.JETPACK:
		return
	jetpack_timer -= delta
	var target_y: float = JETPACK_Y if jetpack_timer > 0.4 else GROUND_Y
	position.y = move_toward(position.y, target_y, 1100.0 * delta)
	if jetpack_timer <= 0.0 and position.y >= GROUND_Y - 2.0:
		state = State.RUN
		position.y = GROUND_Y

func _handle_hoverbike_timer(delta: float) -> void:
	if state != State.HOVERBIKE:
		return
	hoverbike_timer -= delta
	var target_y: float = HOVERBIKE_Y if hoverbike_timer > 0.5 else GROUND_Y
	position.y = move_toward(position.y, target_y, 900.0 * delta)
	if hoverbike_timer <= 0.0 and position.y >= GROUND_Y - 2.0:
		state = State.RUN
		position.y = GROUND_Y

func _handle_speed_timer(delta: float) -> void:
	if jump_buffer_timer > 0.0:
		jump_buffer_timer -= delta
	if magnet_timer > 0.0:
		magnet_timer -= delta
	if speed_mult == 1.0:
		return
	speed_timer -= delta
	if speed_timer <= 0:
		speed_mult = 1.0

func _update_hitbox() -> void:
	_update_sprite()

# Target on-screen heights (px) per state. Feet always anchored at position.y.
const VIS_H_STAND: float = 280.0
const VIS_H_SLIDE: float = 150.0
const VIS_H_BALL: float  = 140.0

func _update_sprite() -> void:
	var tex: Texture2D
	var target_h: float = VIS_H_STAND
	match state:
		State.RUN, State.IDLE:
			if tex_run.size() > 0:
				tex = tex_run[run_frame_idx % tex_run.size()]
			target_h = VIS_H_STAND
		State.JUMP:
			tex = tex_jump
			target_h = VIS_H_STAND
		State.SLIDE:
			tex = tex_slide
			target_h = VIS_H_SLIDE
		State.BALL:
			tex = tex_ball
			target_h = VIS_H_BALL
		State.JETPACK, State.HOVERBIKE:
			if tex_run.size() > 0:
				tex = tex_run[run_frame_idx % tex_run.size()]
			target_h = VIS_H_STAND
		State.DEAD:
			tex = player_sprite.texture  # keep whatever was set in _die()
			target_h = VIS_H_STAND
	if tex:
		player_sprite.texture = tex
		_anchor_feet(tex, target_h)

# Scale any texture to a fixed on-screen height and pin its BOTTOM edge to
# the node origin (position.y) — so feet sit on the ground for every pose,
# regardless of the cutout's native pixel dimensions.
func _anchor_feet(tex: Texture2D, target_h: float) -> void:
	var tex_h: float = float(tex.get_height())
	if tex_h <= 0.0:
		return
	var s: float = target_h / tex_h
	player_sprite.scale  = Vector2(s, s)
	player_sprite.offset = Vector2(0.0, -tex_h * 0.5)

# Pulsing cyan shield bubble — drawn behind the sprite (node _draw renders
# under child nodes), so it reads as an aura around her.
func _draw() -> void:
	# ground-contact shadow at the feet (origin) so she sits on the track
	draw_set_transform(Vector2(0.0, -4.0), 0.0, Vector2(95.0, 24.0))
	draw_circle(Vector2.ZERO, 1.0, Color(0.0, 0.0, 0.0, 0.5))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# ZOE passive magnet: soft purple ring shows the always-on pull radius
	if perk_passive_magnet and state != State.DEAD:
		var mpulse: float = 0.35 + 0.15 * sin(anim_t * 3.0)
		draw_arc(Vector2(0.0, -80.0), perk_passive_magnet_range * 0.38, 0.0, TAU,
				 40, Color(0.7, 0.4, 1.0, mpulse), 2.5, true)

	# Dust puffs: expanding, fading neon-tinted rings kicked up at the feet.
	for p in puffs:
		var rad: float = lerpf(12.0, 78.0 * p.s, p.t)
		var a: float = (1.0 - p.t) * 0.45 * p.s
		draw_set_transform(Vector2(0.0, -6.0), 0.0, Vector2(1.0, 0.4))
		draw_arc(Vector2.ZERO, rad, 0.0, TAU, 20, Color(0.7, 0.85, 1.0, a), 3.0, true)
		draw_arc(Vector2.ZERO, rad * 0.6, 0.0, TAU, 16, Color(1.0, 1.0, 1.0, a * 0.7), 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Hoverbike — Oppressor MkII style: sleek body, two thruster pods, neon glow
	if state == State.HOVERBIKE:
		var flicker: float = 0.7 + 0.3 * sin(shield_pulse * 22.0)
		var bike_col := Color(1.0, 0.42, 0.0)
		# Main body (elongated hull under the player)
		draw_rect(Rect2(-52.0, -8.0, 104.0, 22.0), Color(0.12, 0.12, 0.14, 0.95))
		draw_rect(Rect2(-52.0, -8.0, 104.0, 22.0), Color(bike_col.r, bike_col.g, bike_col.b, 0.8), false, 2.5)
		# Nose cone
		draw_colored_polygon(PackedVector2Array([
			Vector2(52.0, -2.0), Vector2(52.0, 16.0), Vector2(72.0, 7.0)
		]), Color(0.18, 0.12, 0.08, 0.95))
		# Wing stubs left/right
		for sx in [-1.0, 1.0]:
			draw_rect(Rect2(sx * 18.0 - 10.0, 10.0, 20.0, 10.0),
				Color(bike_col.r, bike_col.g, bike_col.b, 0.6))
		# Thruster pods (two neon ovals underneath)
		for tx in [-34.0, 34.0]:
			draw_set_transform(Vector2(tx, 18.0), 0.0, Vector2(1.0, 0.45))
			draw_circle(Vector2.ZERO, 14.0, Color(bike_col.r, bike_col.g, bike_col.b, 0.9))
			draw_circle(Vector2.ZERO, 8.0,  Color(1.0, 0.85, 0.5, 1.0))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			# Downward thrust flame
			var flen: float = 28.0 + 20.0 * flicker
			draw_line(Vector2(tx, 22.0), Vector2(tx + randf_range(-3.0, 3.0), 22.0 + flen),
				Color(1.0, 0.55, 0.0, 0.5 * flicker), 10.0)
			draw_line(Vector2(tx, 22.0), Vector2(tx, 22.0 + flen * 0.5),
				Color(1.0, 1.0, 0.8, 0.85), 3.0)

	# Jetpack thrust flames downward from feet while hovering
	if state == State.JETPACK:
		var flicker: float = 0.6 + 0.4 * sin(shield_pulse * 18.0)
		for side: float in [-1.0, 1.0]:
			var jx: float = side * 28.0
			var jlen: float = 110.0 + 60.0 * flicker
			draw_line(Vector2(jx - 5.0, 0.0), Vector2(jx + randf_range(-4.0, 4.0), jlen),
				Color(0.0, 0.6, 1.0, 0.55 * flicker), 14.0)
			draw_line(Vector2(jx, 0.0), Vector2(jx, jlen * 0.55),
				Color(1.0, 1.0, 1.0, 0.85), 4.0)
		draw_arc(Vector2.ZERO, 52.0, 0.0, TAU, 24,
			Color(0.0, 0.85, 1.0, 0.4 + 0.3 * flicker), 5.0, true)

	# Magnet aura: spinning dashed yellow ring at the feet while active.
	if magnet_timer > 0.0:
		var mp: float = 0.5 + 0.5 * sin(shield_pulse * 5.0)
		var seg := 16
		for i in range(seg):
			if i % 2 == 1:
				continue
			var a0: float = shield_pulse * 2.0 + TAU * float(i) / float(seg)
			var a1: float = a0 + TAU / float(seg)
			draw_arc(Vector2(0.0, -10.0), 120.0, a0, a1, 4,
				Color(1.0, 0.93, 0.27, 0.5 + 0.4 * mp), 6.0, true)

	if _in_dumpster:
		_draw_dumpster_legs()

	if not shield_active:
		return
	var pulse: float = 0.5 + 0.5 * sin(shield_pulse * 7.0)
	var center := Vector2(0.0, -130.0)
	# squash X so the circle becomes a tall body-shaped oval
	draw_set_transform(center, 0.0, Vector2(0.62, 1.0))
	draw_circle(Vector2.ZERO, 165.0, Color(0.2, 0.9, 1.0, 0.10 + 0.08 * pulse))
	draw_arc(Vector2.ZERO, 165.0, 0.0, TAU, 56, Color(0.4, 1.0, 1.0, 0.55 + 0.45 * pulse), 5.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# Kick up a ring of dust at the feet (takeoff = small, landing = full).
func _spawn_puff(strength: float) -> void:
	puffs.append({"t": 0.0, "s": strength})

func _age_puffs(delta: float) -> void:
	if puffs.is_empty():
		return
	for p in puffs:
		p.t += delta * 2.6
	puffs = puffs.filter(func(p): return p.t < 1.0)

# Brings the sprite to life: a vertical stride bob synced to footfalls, a lean
# into lane-changes (pivoting at the feet), and a quick squash/stretch off jumps.
# All applied to the child Sprite2D so the ground shadow + auras stay anchored.
const RUN_BOB_AMP: float = 12.0
var _lean: float = 0.0
func _apply_run_feel(delta: float) -> void:
	# Lean toward the lane we're sliding into; spring back to upright when settled.
	var dx: float = target_x - position.x
	var target_lean: float = clampf(dx * 0.0011, -0.18, 0.18)
	_lean = lerpf(_lean, target_lean, clampf(delta * 14.0, 0.0, 1.0))
	player_sprite.rotation = _lean

	var bob_y: float = 0.0
	var sx: float = 1.0
	var sy: float = 1.0
	match state:
		State.RUN:
			# Two footfalls per stride: bob up on each. run_dist drives the phase
			# so the bounce stays locked to the leg animation at any speed.
			var phase: float = run_dist / RUN_FRAME_DIST * PI
			bob_y = -absf(sin(phase)) * RUN_BOB_AMP
		State.JUMP:
			# Stretch on the way up, squash near the apex/landing.
			var vy: float = jump_velocity
			sy = clampf(1.0 + vy * 0.00018, 0.86, 1.12)
			sx = 2.0 - sy
		State.BALL:
			# Gentle spin wobble handled by sprite swap; keep it round.
			pass
	player_sprite.position.y = bob_y
	# Fold the squash/stretch into the anchored scale set by _anchor_feet.
	player_sprite.scale.x = absf(player_sprite.scale.x) * sx
	player_sprite.scale.y = absf(player_sprite.scale.y) * sy

func _advance_run_anim(dist_step: float) -> void:
	if state != State.RUN or tex_run.is_empty():
		return
	run_dist += dist_step
	var new_frame := int(run_dist / RUN_FRAME_DIST) % tex_run.size()
	if new_frame != run_frame_idx:
		run_frame_idx = new_frame

# Shop upgrade multiplier for a powerup's duration (1.0 if SaveData unavailable).
func _up_mult(id: String) -> float:
	var sd: Node = get_node_or_null("/root/SaveData")
	return sd.upgrade_mult(id) if sd else 1.0

func activate_powerup(gate_type: String, gate_cfg: Dictionary) -> void:
	for g in gate_cfg.types:
		if g.id == gate_type:
			var mult: float = _up_mult(gate_type) * perk_duration_mult
			match gate_type:
				"ball":
					state = State.BALL
					ball_timer = g.duration * mult
					if position.y >= GROUND_Y:
						jump_velocity = -(2.0 * cfg_ball_jump_height) / cfg_ball_jump_duration
				"speed":
					speed_mult = g.multiplier
					speed_timer = g.duration * mult
				"shield":
					shield_active = true
					shield_pulse = 0.0
					emit_signal("shield_changed", true)
				"magnet":
					magnet_timer = g.duration * mult
					# Range scales with the upgrade too, so a leveled magnet reaches
					# clear across all three lanes.
					magnet_range = float(g.get("range", 720)) * mult
				"jetpack":
					state = State.JETPACK
					jetpack_timer = g.duration * mult
				"hoverbike":
					state = State.HOVERBIKE
					hoverbike_timer = g.duration * mult
					position.y = minf(position.y, HOVERBIKE_Y + 10.0)
			return

func is_magnet_active() -> bool:
	return magnet_timer > 0.0 or perk_passive_magnet

func effective_magnet_range() -> float:
	if magnet_timer > 0.0:
		return magnet_range
	return perk_passive_magnet_range

# Called by a rideable obstacle when she descends onto its roof: snap her feet to
# the roof line and let her run along the top until it scrolls out from under her.
func mount_roof(roof_y: float, obs: Node) -> void:
	if state == State.DEAD or state == State.JETPACK:
		return
	ground_override = roof_y
	ride_obstacle = obs
	if position.y > roof_y:
		position.y = roof_y
	jump_velocity = 0.0
	if state == State.JUMP or state == State.BALL:
		state = State.RUN
	Sfx.play("jump")
	# Spawn a gem trail on the roof for the player to collect
	var main: Node = get_parent()
	if main and main.has_method("spawn_roof_gems"):
		main.spawn_roof_gems(roof_y, obs)

# The vehicle has passed (or she jumped clear): restore real ground and let her
# fall back down to the track.
func dismount(obs: Node) -> void:
	if ride_obstacle != obs:
		return
	ride_obstacle = null
	ground_override = GROUND_Y
	if position.y < GROUND_Y and state == State.RUN:
		state = State.JUMP   # walk off the edge -> fall

func is_riding() -> bool:
	return ride_obstacle != null

func take_hit(cause: String = "") -> void:
	if shield_active:
		shield_active = false
		emit_signal("shield_changed", false)
		queue_redraw()  # clear the aura immediately
		return
	if state == State.BALL:
		return
	_die(cause)

func _die(cause: String = "") -> void:
	is_alive = false
	state = State.DEAD
	ground_override = GROUND_Y
	ride_obstacle = null
	_in_dumpster = cause == "dumpster"
	_dumpster_t = 0.0
	if _in_dumpster:
		# Hide sprite — legs are drawn procedurally in _draw().
		player_sprite.visible = false
	else:
		# A botched duck/slide = butt-first wipeout; a frontal smack = face-plant.
		# Anything else (unspecified) flips a coin.
		var use_butt: bool
		match cause:
			"wipeout": use_butt = true
			"fall":    use_butt = true   # dropped into the hole — lands on the rump
			"frontal": use_butt = false
			_:         use_butt = randi() % 2 == 0
		var dtex: Texture2D = tex_death_butt if use_butt else tex_death_face
		if dtex:
			player_sprite.texture = dtex
			_anchor_feet(dtex, VIS_H_STAND)
	# Drop any run lean/bob so the death pose sits flat on the ground.
	player_sprite.rotation = 0.0
	player_sprite.position.y = 0.0
	_lean = 0.0
	emit_signal("died")

func spring_launch() -> void:
	if state == State.DEAD or state == State.JETPACK:
		return
	if state == State.SLIDE:
		slide_timer = 0.0
		slide_held = false
	if state == State.JUMP:
		# Already airborne — boost upward if not already going high enough.
		jump_velocity = minf(jump_velocity, -(2.0 * cfg_jump_height * 1.4) / cfg_jump_duration)
		return
	state = State.JUMP
	jump_velocity = -(2.0 * cfg_jump_height * 1.4) / cfg_jump_duration   # 40% taller than normal
	_spawn_puff(1.3)
	Sfx.play("jump")

func is_ball_active() -> bool:
	return state == State.BALL

# Brought back after a paid revive: alive, centered, running, with a grace shield.
func revive() -> void:
	is_alive = true
	lane = 1
	position = Vector2(LANE_X[1], GROUND_Y)
	target_x = LANE_X[1]
	state = State.RUN
	jump_velocity = 0.0
	magnet_timer = 0.0
	speed_mult = 1.0
	shield_active = true
	shield_pulse = 0.0
	ground_override = GROUND_Y
	ride_obstacle = null
	_in_dumpster = false
	_dumpster_t = 0.0
	hoverbike_timer = 0.0
	perk_duration_mult = 1.0
	perk_passive_magnet = false
	player_sprite.visible = true
	emit_signal("shield_changed", true)
	show()
	queue_redraw()

# Two legs kicking up from the dumpster opening — classic cartoon "fell in" gag.
# Drawn in player-local space (origin = feet on ground; up = negative Y).
func _draw_dumpster_legs() -> void:
	var sink: float = minf(_dumpster_t * 3.0, 1.0)      # 0→1 in first ~0.33 s
	var leg_h: float = 130.0 * sink                      # legs emerge upward
	var wobble: float = maxf(0.0, _dumpster_t - 0.25)
	var sway: float = sin(wobble * 13.0) * 20.0 * maxf(0.0, 1.0 - wobble * 1.2)
	var lw: float = 18.0
	var gap: float = 10.0
	for si in range(2):
		var side: float = -1.0 if si == 0 else 1.0
		var cx: float = side * (lw * 0.5 + gap * 0.5) + sway
		# trouser fill
		draw_rect(Rect2(cx - lw * 0.5, -leg_h, lw, leg_h), Color(0.15, 0.15, 0.65, 0.95))
		draw_rect(Rect2(cx - lw * 0.5, -leg_h, lw, leg_h), Color(0.3, 0.3, 1.0, 0.7), false, 2.0)
		# shoe at the top
		if leg_h > 40.0:
			draw_circle(Vector2(cx + side * 4.0, -leg_h), 11.0, Color(0.05, 0.05, 0.05, 1.0))
	# impact stars while sinking
	if sink < 0.9:
		var a: float = (1.0 - sink) * 0.85
		var r: float = (1.0 - sink) * 28.0
		draw_circle(Vector2(52.0, -leg_h - 18.0), r * 0.5, Color(1.0, 0.9, 0.1, a))
		draw_circle(Vector2(-52.0, -leg_h - 22.0), r * 0.4, Color(1.0, 0.3, 0.2, a))
		draw_circle(Vector2(10.0, -leg_h - 35.0), r * 0.35, Color(1.0, 1.0, 1.0, a * 0.6))

# Hitbox is kept a bit SMALLER than the visible sprite so near-misses feel fair.
# Heights track the on-screen sprite heights (VIS_H_*) the player actually sees.
func get_hitbox_rect() -> Rect2:
	var w: float
	var h: float
	match state:
		State.SLIDE:
			w = 130.0
			h = 120.0   # low crouch — must clear the head-height beam
		State.BALL:
			w = 90.0
			h = 115.0
		_:
			w = 90.0
			h = 215.0   # standing/run/jump full body (~77% of 280px visual)
	return Rect2(position.x - w * 0.5, position.y - h, w, h)
