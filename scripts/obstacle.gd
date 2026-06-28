extends Node2D

const Perspective = preload("res://scripts/perspective.gd")

signal hit_player(cause: String)
signal punched(score: int)
signal cleared(kind: String)   # safely jumped/slid past — drives the leap combo
signal near_miss()             # squeaked past a hazard in the next lane — "close call"

const LANE_X := [270.0, 540.0, 810.0]
const DESPAWN_Y := 2100.0

# Zone accent colors — matches perspective_floor ZONE_PALETTES grid color (index 3).
const ZONE_ACCENTS := [
	Color(0.0,  0.92, 1.0,  1),  # 1 Neon City  — cyan
	Color(1.0,  0.75, 0.0,  1),  # 2 Transit     — gold
	Color(0.2,  1.0,  0.1,  1),  # 3 Sewer       — acid green
	Color(0.3,  0.7,  1.0,  1),  # 4 Corporate   — ice blue
	Color(0.8,  0.5,  1.0,  1),  # 5 Rooftop     — purple
]

func _zone_accent() -> Color:
	return ZONE_ACCENTS[clampi(zone - 1, 0, ZONE_ACCENTS.size() - 1)]

var speed: float = 600.0
var obstacle_type: Dictionary
var lanes: Array = [0]          # one or more lane indices this obstacle covers
var style: String = "barrier"   # barrier | beam | slick | npc
var action: String = "jump"     # jump | slide | punch
var checked_hit: bool = false
var near_checked: bool = false
var t_anim: float = 0.0          # local clock for neon animation
var knocked: float = 0.0        # >0 = NPC has been punched (flying away)
var salvo_projectile: bool = false  # true = boss salvo missile; draws as orb not goblin
var self_speed: float = 0.0     # extra closing speed for oncoming vehicles (0 = parked)
var safe_lane: int = 0          # wall_gap only: which lane index (0/1/2) has the opening
var zone: int = 1               # current zone — drives pit/hole appearance

# Half-width of this obstacle in flat world-X (drives collision + drawing).
var half_w: float = 45.0
var height: float = 180.0
var npc_tex: Texture2D = null
var sprite_tex: Texture2D = null

# Shared pool of little-one cutouts, loaded once across all obstacle instances.
static var _npc_textures: Array = []
# Cache of solid-obstacle sprites by id (car/bus/cart/barrier/cone).
static var _sprite_cache: Dictionary = {}

static func _sprite_for(id: String) -> Texture2D:
	if not _sprite_cache.has(id):
		_sprite_cache[id] = load("res://assets/sprites/obstacles/%s.png" % id) as Texture2D
	return _sprite_cache[id]

static func _npc_pool() -> Array:
	if _npc_textures.is_empty():
		for i in range(1, 8):
			var t := load("res://assets/sprites/npc/npc_0%d.png" % i) as Texture2D
			if t:
				_npc_textures.append(t)
	return _npc_textures

@onready var visual: Node2D = $Visual
@onready var body: ColorRect = $Visual/Body
@onready var hint_label: Label = $Visual/HintLabel

func setup(t: Dictionary, lane_list: Array, spd: float) -> void:
	obstacle_type = t
	lanes = lane_list.duplicate()
	speed = spd
	style = t.get("style", "barrier")
	action = t.get("action", "jump")
	height = float(t.height)

	# Center X across the covered lanes; half-width spans them (+ a little).
	var lx_min: float = LANE_X[lanes.min()]
	var lx_max: float = LANE_X[lanes.max()]
	var center_x: float = (lx_min + lx_max) * 0.5
	half_w = (lx_max - lx_min) * 0.5 + (110.0 if style == "beam" else 55.0)
	position = Vector2(center_x, float(t.get("y_offset", 0)) - 100.0)

	# The ColorRect Body is only used for the solid "barrier" style; every other
	# style is drawn procedurally in _draw(). Hide the rect for those.
	if style == "barrier":
		body.visible = true
		body.size = Vector2(half_w * 2.0, height)
		body.position = Vector2(-half_w, -height)
		body.color = Color.from_string("#" + str(t.color), Color.RED)
	else:
		body.visible = false

	if style == "npc":
		var pool := _npc_pool()
		if not pool.is_empty():
			npc_tex = pool[randi() % pool.size()]
	elif style == "sprite":
		# Allow a "sprite" override key so e.g. car_oncoming reuses the car texture
		var sprite_id: String = t.get("sprite", str(t.id))
		sprite_tex = _sprite_for(sprite_id)

	self_speed = float(t.get("self_speed", 0.0))
	if style == "wall_gap":
		safe_lane = randi() % 3

	_set_hint()

func _set_hint() -> void:
	match action:
		"slide":
			# Wide beams span all lanes — both jump and slide are valid
			if int(obstacle_type.get("lanes", 1)) >= 3:
				hint_label.text = "▲ JUMP  or  ▼ SLIDE"
			else:
				hint_label.text = "▼ SLIDE"
			hint_label.add_theme_color_override("font_color", Color(1, 0.6, 0.0, 1))
		"punch":
			hint_label.text = "✦ PUNCH"
			hint_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.8, 1))
		"evade":
			var arrows := ["← LEFT", "↑ CENTER", "→ RIGHT"]
			hint_label.text = "HOLE! " + arrows[safe_lane]
			hint_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4, 1))
		"spring":
			hint_label.text = "🌀 SPRING"
			hint_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.55, 1))
		_:
			hint_label.text = "▲ JUMP"
			hint_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
	hint_label.position = Vector2(-60.0, -height - 60.0)

func _process(delta: float) -> void:
	t_anim += delta
	# Move at the CURRENT world speed (so speed power-ups + ramp keep everything
	# in lockstep with the floor and gems), falling back to the spawn speed.
	var main: Node = get_parent().get_parent()
	var spd: float = (main.get_speed() if main and main.has_method("get_speed") else speed) + self_speed
	position.y += spd * delta
	if knocked > 0.0:
		knocked += delta
	_apply_perspective()
	if obstacle_type.get("rideable", false) and action == "jump":
		_check_ride()
	else:
		_check_collision()
	_check_near_miss()
	if position.y > DESPAWN_Y:
		_release_rider()
		queue_free()

func _check_collision() -> void:
	if checked_hit:
		return
	var main: Node = get_parent().get_parent()
	if main.state != 1:  # only while PLAYING
		return
	var player: Node = main.player

	# X overlap test (flat world coords).
	var x_overlap: bool = position.x + half_w > player.position.x - 45.0 \
		and position.x - half_w < player.position.x + 45.0
	if not x_overlap:
		return

	# Only resolve when the obstacle reaches the player plane.
	if position.y < 1320.0 or position.y > 1640.0:
		return

	match action:
		"slide":
			# Slide-action obstacles: duck under (slide/ball) or fly over (jump/jet).
			# Head-height beams: jumping CLEARS them — you're above the beam.
			# Floor slicks: jumping also clears (hop the puddle).
			# Both cases: being airborne is always safe.
			var safe: bool = player.state == player.State.SLIDE \
				or player.state == player.State.BALL \
				or player.state == player.State.JETPACK \
				or player.state == player.State.HOVERBIKE \
				or player.state == player.State.JUMP
			checked_hit = true
			if not safe:
				emit_signal("hit_player", "wipeout")
		"jump":
			# Solid: safe only if airborne. A real JUMP earns leap-combo credit;
			# ball/jetpack pass safely but don't (they're auto-clears, not skill).
			checked_hit = true
			if player.state == player.State.JUMP:
				emit_signal("cleared", "jump")
			elif player.state == player.State.BALL \
					or player.state == player.State.JETPACK \
					or player.state == player.State.HOVERBIKE:
				pass
			else:
				emit_signal("hit_player", "frontal")
		"punch":
			checked_hit = true
			if player.state != player.State.JUMP:
				knocked = 0.0001
				emit_signal("punched", int(obstacle_type.get("score", 50)))
		"spring":
			# Springboard: always safe, always launches. No action required from player.
			checked_hit = true
			player.spring_launch()
			emit_signal("cleared", "spring")
		"evade":
			# A hole across the lanes with one solid path. The safe lane has a
			# springboard that auto-launches the player over the gap.
			var airborne: bool = player.state == player.State.JUMP \
				or player.state == player.State.BALL \
				or player.state == player.State.JETPACK \
				or player.state == player.State.HOVERBIKE
			var safe: bool = player.lane == safe_lane or airborne
			checked_hit = true
			if not safe:
				emit_signal("hit_player", "fall")
			elif player.lane == safe_lane and not airborne:
				# Springboard in the safe lane auto-launches.
				player.spring_launch()
				emit_signal("cleared", "jump")

# The roof line in the player's vertical space. Clamped so it's always reachable
# at the peak of a normal jump (you can't land on something above your apex).
func _roof_y(player: Node) -> float:
	var apex_reach: float = player.GROUND_Y - player.cfg_jump_height + 70.0
	return maxf(player.GROUND_Y - height, apex_reach)

# Rideable tall vehicle: land on the roof when descending onto it, ride until it
# scrolls out from under you, crash if you run into it grounded.
func _check_ride() -> void:
	var main: Node = get_parent().get_parent()
	if not main or main.state != 1:
		return
	var player: Node = main.player
	var x_overlap: bool = position.x + half_w > player.position.x - 45.0 \
		and position.x - half_w < player.position.x + 45.0
	var in_window: bool = position.y > 1340.0 and position.y < 1700.0
	var roof_y: float = _roof_y(player)

	# Already riding THIS vehicle: keep her pinned to the roof; release when it
	# slides past or she's no longer above it.
	if player.ride_obstacle == self:
		if not x_overlap or position.y >= 1690.0:
			player.dismount(self)
		elif player.state == player.State.RUN:
			player.position.y = roof_y
		return

	if not (x_overlap and in_window):
		return

	# Flying over the top (ball / jetpack): always safe, no mount.
	if player.state == player.State.BALL or player.state == player.State.JETPACK:
		return

	# Airborne and dropping onto the roof -> mount.
	if player.state == player.State.JUMP and player.jump_velocity >= -60.0 \
			and player.position.y >= roof_y - 8.0:
		player.mount_roof(roof_y, self)
		return

	# Grounded smack into the side -> crash (once).
	# Dumpsters earn a special comedic fall-in cause instead of a plain frontal.
	if player.state != player.State.JUMP and not checked_hit:
		checked_hit = true
		var cause: String = "dumpster" if obstacle_type.get("id", "") == "dumpster" else "frontal"
		emit_signal("hit_player", cause)

func _release_rider() -> void:
	var main: Node = get_parent().get_parent()
	if main and is_instance_valid(main.player):
		if main.player.ride_obstacle == self:
			main.player.dismount(self)

# "Close call": a dangerous hazard slides past in the NEXT lane (no collision,
# but within a hair of one). Fires once per obstacle.
func _check_near_miss() -> void:
	if near_checked or not (action in ["jump", "slide", "evade"]):
		return
	var main: Node = get_parent().get_parent()
	if not main or main.state != 1:
		return
	var player: Node = main.player
	if not player.is_alive:
		return
	if position.y < 1420.0 or position.y > 1560.0:
		return
	var dx: float = absf(position.x - player.position.x)
	var collide_dist: float = half_w + 45.0
	if dx > collide_dist and dx < collide_dist + 190.0:
		near_checked = true
		emit_signal("near_miss")

func _apply_perspective() -> void:
	var p: float = Perspective.progress(position.y)
	visual.global_position = Vector2(Perspective.converge_x(position.x, p), Perspective.screen_y(p))
	var s: float = Perspective.depth_scale(p)
	visual.scale = Vector2(s, s)
	queue_redraw()

func _draw() -> void:
	if not visual:
		return
	var s: float = visual.scale.x
	var base: Vector2 = visual.position
	var hw: float = half_w * s          # on-screen half width
	var hh: float = height * s           # on-screen height

	# Ground-contact shadow — now drawn for EVERY hazard (incl. floating beams)
	# so you can read exactly where on the track it sits and time your move.
	draw_set_transform(base, 0.0, Vector2(hw * 1.7, hw * 0.42))
	draw_circle(Vector2.ZERO, 1.0, Color(0.0, 0.0, 0.0, 0.5))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	match style:
		"beam":        _draw_beam(base, hw, hh, s)
		"slick":       _draw_slick(base, hw, s)
		"npc":         _draw_npc(base, hw, hh, s)
		"sprite":
			_draw_sprite_obj(base, hh, s)
			if obstacle_type.get("id", "") == "cart":
				_draw_cart_pusher(base, hh, s)
		"wall_gap":    _draw_wall_gap(base, hw, hh, s)
		"springboard": _draw_springboard(base, hw, hh, s)
		_:             _draw_barrier_glow(base, hw, hh)

# Crackling horizontal electric bar spanning the obstacle's width.
func _draw_beam(base: Vector2, hw: float, hh: float, s: float) -> void:
	var col := Color.from_string("#" + str(obstacle_type.color), Color(1, 0.16, 0.29))
	col = col.lerp(_zone_accent(), 0.35)   # tint toward zone palette
	# Slide-beams hang at head height (duck under); jump-beams sit low (hop over).
	var bar_y: float = base.y - (hh * 1.1 if action == "slide" else hh * 0.28)
	var pulse: float = 0.55 + 0.45 * sin(t_anim * 9.0)
	# Outer glow
	draw_line(Vector2(base.x - hw, bar_y), Vector2(base.x + hw, bar_y),
		Color(col.r, col.g, col.b, 0.22), 26.0 * s)
	draw_line(Vector2(base.x - hw, bar_y), Vector2(base.x + hw, bar_y),
		Color(col.r, col.g, col.b, 0.4 * pulse), 14.0 * s)
	# Jagged electric core
	var pts := PackedVector2Array()
	var segs := 14
	for i in range(segs + 1):
		var fx: float = float(i) / float(segs)
		var x: float = base.x - hw + fx * hw * 2.0
		var jitter: float = sin(t_anim * 22.0 + fx * 18.0) * 7.0 * s
		pts.append(Vector2(x, bar_y + jitter))
	draw_polyline(pts, Color(1, 1, 1, 0.9), 3.0 * s)
	draw_polyline(pts, Color(col.r, col.g, col.b, 1.0), 6.0 * s)
	# End emitter nodes
	for ex in [base.x - hw, base.x + hw]:
		draw_circle(Vector2(ex, bar_y), 14.0 * s, Color(col.r, col.g, col.b, 0.9))
		draw_circle(Vector2(ex, bar_y), 7.0 * s, Color(1, 1, 1, 0.9))
	# Depth cue: drop posts from the bar to the track + a bright ground stripe,
	# so a head-height SLIDE beam is clearly planted and easy to time.
	if action == "slide":
		for ex in [base.x - hw, base.x + hw]:
			draw_line(Vector2(ex, bar_y), Vector2(ex, base.y),
				Color(col.r, col.g, col.b, 0.35 * pulse), 3.0 * s)
		draw_line(Vector2(base.x - hw, base.y), Vector2(base.x + hw, base.y),
			Color(col.r, col.g, col.b, 0.7 * pulse), 4.0 * s)

# Glowing acid/oil puddle on the floor — slide to skim over it.
func _draw_slick(base: Vector2, hw: float, s: float) -> void:
	var col := Color.from_string("#" + str(obstacle_type.color), Color(0.22, 1, 0.08))
	col = col.lerp(_zone_accent(), 0.4)
	var pulse: float = 0.6 + 0.4 * sin(t_anim * 4.0)
	draw_set_transform(base, 0.0, Vector2(hw * 1.2, hw * 0.5))
	draw_circle(Vector2.ZERO, 1.0, Color(col.r, col.g, col.b, 0.25 * pulse))
	draw_circle(Vector2.ZERO, 0.7, Color(col.r, col.g, col.b, 0.45 * pulse))
	draw_circle(Vector2.ZERO, 0.4, Color(0.8, 1.0, 0.8, 0.6))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Crisp elliptical rim so the puddle's edge (and approach) is readable at speed.
	var rim := PackedVector2Array()
	for i in range(25):
		var a: float = TAU * float(i) / 24.0
		rim.append(base + Vector2(cos(a) * hw * 1.2, sin(a) * hw * 0.5))
	draw_polyline(rim, Color(0.6, 1.0, 0.6, 0.9 * pulse), 3.0 * s)
	# Leading-edge bar — the line you must be sliding by the time you reach it.
	draw_line(base + Vector2(-hw * 1.1, hw * 0.5), base + Vector2(hw * 1.1, hw * 0.5),
		Color(0.8, 1.0, 0.8, 0.85 * pulse), 3.0 * s)

# Little-one NPC: real goblin-kid cutout standing in the lane. Tips back and
# fades once punched. Falls back to a neon capsule if no texture loaded.
func _draw_npc(base: Vector2, hw: float, hh: float, s: float) -> void:
	var lean: float = 0.0
	var fade: float = 1.0
	if knocked > 0.0:
		lean = clampf(knocked * 6.0, 0.0, 1.4)        # rotate away from camera
		fade = clampf(1.0 - knocked * 1.5, 0.0, 1.0)

	# Boss salvo missiles draw as energy orbs, not goblins.
	if salvo_projectile:
		var orb_r: float = hw * 0.7
		var pulse: float = 0.55 + 0.45 * sin(t_anim * 12.0)
		draw_circle(Vector2(0, -hh * 0.5), orb_r * 1.4, Color(1.0, 0.85, 0.1, 0.22 * pulse))
		draw_circle(Vector2(0, -hh * 0.5), orb_r,       Color(1.0, 0.85, 0.1, 0.85))
		draw_circle(Vector2(0, -hh * 0.5), orb_r * 0.5, Color(1.0, 1.0,  1.0, 0.95))
		# Spin lines
		for i in range(4):
			var a: float = t_anim * 6.0 + TAU * float(i) / 4.0
			var tip: Vector2 = Vector2(0, -hh * 0.5) + Vector2(cos(a), sin(a)) * orb_r * 1.1
			draw_line(Vector2(0, -hh * 0.5), tip, Color(1.0, 0.9, 0.2, 0.7 * pulse), 2.5)
		return

	if npc_tex:
		var tw: float = float(npc_tex.get_width())
		var th: float = float(npc_tex.get_height())
		if th <= 0.0:
			return
		var scale: float = (hh / th)                  # fit to target on-screen height
		# Transform pivots at the feet (base) so she leans back from the ground.
		draw_set_transform(base, lean, Vector2(scale, scale))
		var dst := Rect2(-tw * 0.5, -th, tw, th)       # centered X, bottom at origin
		draw_texture_rect(npc_tex, dst, false, Color(1, 1, 1, fade))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return

	# Fallback capsule — variant styling by npc type
	var npc_id: String = str(obstacle_type.get("id", "npc"))
	var col := Color.from_string("#" + str(obstacle_type.color), Color(1, 0.4, 0.8))
	var w: float = hw * 0.55
	draw_set_transform(base, lean, Vector2.ONE)
	match npc_id:
		"npc_small":
			# Small fast runner — thin, bright blue, visor flash
			draw_circle(Vector2(0, -hh * 0.5), w * 0.65, Color(col.r, col.g, col.b, 0.9 * fade))
			draw_circle(Vector2(0, -hh * 0.82), w * 0.55, Color(col.r, col.g, col.b, 0.9 * fade))
			# Speed lines
			for i in range(3):
				var ly: float = -hh * (0.25 + i * 0.18)
				draw_line(Vector2(-w * 1.8, ly), Vector2(-w * 0.9, ly), Color(1, 1, 1, 0.35 * fade), 2.0)
		"npc_big":
			# Big bruiser — wide, orange, thick neck
			draw_circle(Vector2(0, -hh * 0.42), w * 1.2, Color(col.r, col.g, col.b, 0.9 * fade))
			draw_circle(Vector2(0, -hh * 0.78), w * 0.9, Color(col.r, col.g, col.b, 0.9 * fade))
			# Fists
			draw_circle(Vector2(-w * 1.3, -hh * 0.55), w * 0.5, Color(col.r * 0.8, col.g * 0.6, 0.3, 0.9 * fade))
			draw_circle(Vector2( w * 1.3, -hh * 0.55), w * 0.5, Color(col.r * 0.8, col.g * 0.6, 0.3, 0.9 * fade))
		"npc_gold":
			# Gold rare goblin — glowing, sparkles, crown
			var gpulse: float = 0.7 + 0.3 * sin(t_anim * 8.0)
			draw_circle(Vector2(0, -hh * 0.5),  w * 1.1, Color(1.0, 0.9, 0.0, 0.3 * gpulse * fade))
			draw_circle(Vector2(0, -hh * 0.5),  w * 0.8, Color(1.0, 0.85, 0.1, 0.95 * fade))
			draw_circle(Vector2(0, -hh * 0.82), w * 0.65, Color(1.0, 0.92, 0.3, 0.95 * fade))
			# Crown points
			for i in range(3):
				var cx2: float = (i - 1) * w * 0.65
				draw_circle(Vector2(cx2, -hh * 0.96), w * 0.22, Color(1.0, 0.8, 0.0, fade))
		_:
			# Standard goblin capsule
			draw_circle(Vector2(0, -hh * 0.5), w, Color(col.r, col.g, col.b, 0.85 * fade))
			draw_circle(Vector2(0, -hh * 0.78), w * 0.85, Color(col.r, col.g, col.b, 0.85 * fade))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# Real obstacle cutout (car/bus/cart/barrier/cone), feet/base anchored to the
# track at its depth, scaled to the type's target height.
func _draw_sprite_obj(base: Vector2, hh: float, s: float) -> void:
	if not sprite_tex:
		_draw_barrier_glow(base, half_w * s, hh)
		return
	var tw: float = float(sprite_tex.get_width())
	var th: float = float(sprite_tex.get_height())
	if th <= 0.0:
		return
	var scale: float = hh / th
	var sprite_w: float = tw * scale

	# --- Depth for tall vehicles: a dark extruded body behind the flat cutout,
	# plus a contact shadow, so it reads as a 3D volume you can land on. ---
	if obstacle_type.get("rideable", false):
		var ext: float = hh * 0.16        # how far the body extrudes "back/up"
		var bw: float = sprite_w * 0.46
		# extruded box (top + back face) skewed upward to fake perspective
		var top := PackedVector2Array([
			Vector2(base.x - bw, base.y - hh),
			Vector2(base.x + bw, base.y - hh),
			Vector2(base.x + bw * 0.82, base.y - hh - ext),
			Vector2(base.x - bw * 0.82, base.y - hh - ext),
		])
		draw_colored_polygon(top, Color(0.06, 0.06, 0.10, 0.9))
		draw_polyline(top, Color(0.0, 0.9, 1.0, 0.35), 2.0 * s)
		# side sliver for body thickness
		draw_colored_polygon(PackedVector2Array([
			Vector2(base.x + bw, base.y - hh), Vector2(base.x + bw, base.y - hh * 0.18),
			Vector2(base.x + bw * 0.9, base.y - hh * 0.12), Vector2(base.x + bw * 0.82, base.y - hh - ext),
		]), Color(0.04, 0.04, 0.08, 0.85))

	draw_set_transform(base, 0.0, Vector2(scale, scale))
	draw_texture_rect(sprite_tex, Rect2(-tw * 0.5, -th, tw, th), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# Homeless person hunched behind the cart, arms forward on the handle.
func _draw_cart_pusher(base: Vector2, hh: float, s: float) -> void:
	var bob: float = sin(t_anim * 9.0) * 2.5 * s   # walking stride bob
	# Position behind the cart (farther up the screen = "behind" in pseudo-3D)
	var px: float = base.x - 18.0 * s
	var py: float = base.y + bob
	var body_h: float = hh * 0.62
	var skin := Color(0.85, 0.65, 0.45)
	var coat := Color(0.28, 0.22, 0.16)   # dirty coat
	var pant := Color(0.22, 0.22, 0.30)

	# Legs (two rects, alternating stride)
	var stride: float = sin(t_anim * 9.0) * 7.0 * s
	draw_rect(Rect2(px - 8.0 * s, py - body_h * 0.38, 10.0 * s, body_h * 0.38), pant)
	draw_rect(Rect2(px + 2.0 * s, py - body_h * 0.38 + stride, 10.0 * s, body_h * 0.38), pant)

	# Torso (hunched — tilted forward)
	draw_colored_polygon(PackedVector2Array([
		Vector2(px - 12.0 * s, py - body_h * 0.38),
		Vector2(px + 12.0 * s, py - body_h * 0.38),
		Vector2(px + 6.0 * s,  py - body_h * 0.82),
		Vector2(px - 6.0 * s,  py - body_h * 0.82),
	]), coat)

	# Arms outstretched forward to cart handle
	var handle_x: float = base.x + 4.0 * s
	var handle_y: float = py - body_h * 0.68
	draw_line(Vector2(px - 4.0 * s, py - body_h * 0.72), Vector2(handle_x, handle_y),
		coat, 7.0 * s)
	draw_line(Vector2(px + 4.0 * s, py - body_h * 0.72), Vector2(handle_x, handle_y),
		coat, 7.0 * s)

	# Head (small, hunched down)
	draw_circle(Vector2(px - 4.0 * s, py - body_h * 0.88), 11.0 * s, skin)
	# Beanie
	draw_colored_polygon(PackedVector2Array([
		Vector2(px - 15.0 * s, py - body_h * 0.88),
		Vector2(px + 7.0 * s,  py - body_h * 0.88),
		Vector2(px + 4.0 * s,  py - body_h * 1.04),
		Vector2(px - 12.0 * s, py - body_h * 1.04),
	]), Color(0.6, 0.15, 0.1))   # red beanie

# Neon spring coil + launch platform. Draws from ground (base.y) upward.
func _draw_springboard(base: Vector2, hw: float, hh: float, s: float) -> void:
	var col := Color(0.0, 1.0, 0.55)
	var pulse: float = 0.6 + 0.4 * sin(t_anim * 9.0)
	var coil_h: float = hh * 0.65
	var base_h: float = 10.0 * s
	var pad_h:  float = 12.0 * s
	# Base plate
	draw_rect(Rect2(base.x - hw * 0.8, base.y - base_h, hw * 1.6, base_h),
		Color(col.r, col.g, col.b, 0.75))
	# Spring coils — zigzag from base plate up to the launch pad
	var pts := PackedVector2Array()
	var steps := 7
	for i in range(steps + 1):
		var frac: float = float(i) / float(steps)
		var cy: float = base.y - base_h - coil_h * frac
		var cx: float = base.x + (hw * 0.55 if i % 2 == 0 else -hw * 0.55)
		pts.append(Vector2(cx, cy))
	draw_polyline(pts, Color(col.r, col.g, col.b, 0.85 * pulse), 4.0 * s)
	draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.35 * pulse), 2.0 * s)
	# Launch pad on top
	var pad_y: float = base.y - base_h - coil_h - pad_h
	draw_rect(Rect2(base.x - hw * 0.9, pad_y, hw * 1.8, pad_h),
		Color(col.r, col.g, col.b, 0.9))
	draw_rect(Rect2(base.x - hw * 0.9, pad_y, hw * 1.8, pad_h),
		Color(1.0, 1.0, 1.0, 0.5 * pulse), false, 2.0 * s)
	# Arrow chevrons above the pad pulsing upward
	for ai in range(3):
		var ay: float = pad_y - (16.0 + float(ai) * 14.0) * s
		var aw: float = hw * (0.55 - float(ai) * 0.12)
		var alpha: float = (0.9 - float(ai) * 0.25) * pulse
		draw_line(Vector2(base.x - aw, ay + 10.0 * s), Vector2(base.x, ay),
			Color(col.r, col.g, col.b, alpha), 3.0 * s)
		draw_line(Vector2(base.x + aw, ay + 10.0 * s), Vector2(base.x, ay),
			Color(col.r, col.g, col.b, alpha), 3.0 * s)

# Soft neon outline around the solid barrier rect.
func _draw_barrier_glow(base: Vector2, hw: float, hh: float) -> void:
	var col := Color.from_string("#" + str(obstacle_type.color), Color(1, 0.13, 0.33))
	col = col.lerp(_zone_accent(), 0.3)
	var r := Rect2(base.x - hw, base.y - hh, hw * 2.0, hh)
	draw_rect(r, Color(col.r, col.g, col.b, 0.85), false, 4.0)

# Zone-keyed murk (deep color at the bottom of the hole) and rim glow.
const PIT_MURK := [
	Color(0.02, 0.03, 0.05),  # 1 city — black void / open manhole
	Color(0.05, 0.03, 0.0),   # 2 transit — dark track gap
	Color(0.02, 0.10, 0.03),  # 3 sewer — green murk below
	Color(0.02, 0.05, 0.12),  # 4 corporate — maintenance shaft
	Color(0.04, 0.02, 0.08),  # 5 rooftop — open void, city far below
]
const PIT_RIM := [
	Color(0.0, 0.92, 1.0),    # 1 cyan
	Color(1.0, 0.7, 0.1),     # 2 amber
	Color(0.3, 1.0, 0.3),     # 3 green
	Color(0.4, 0.7, 1.0),     # 4 blue
	Color(0.85, 0.5, 1.0),    # 5 purple
]

# A hole punched across the lanes — fall in unless you're on the solid path
# (safe lane), or you jump/jet over it. The opening recedes UPWARD (away toward
# the far edge), with a bright near lip and a dark shaft suggesting real depth.
func _draw_wall_gap(base: Vector2, hw: float, hh: float, s: float) -> void:
	var zi: int = clampi(zone - 1, 0, PIT_MURK.size() - 1)
	var murk: Color = PIT_MURK[zi]
	var rim: Color = PIT_RIM[zi]
	var pulse: float = 0.6 + 0.4 * sin(t_anim * 6.0)
	var lx: float = base.x - hw
	var rx: float = base.x + hw
	# The hole opening sits on the ground: near lip at base.y, far lip up the screen.
	var depth: float = hh * 0.85
	var far_y: float = base.y - depth
	var lane_w: float = hw * 2.0 / 3.0
	var lane_offsets := [-lane_w, 0.0, lane_w]
	var path_cx: float = base.x + lane_offsets[safe_lane]
	var path_lx: float = path_cx - lane_w * 0.5
	var path_rx: float = path_cx + lane_w * 0.5

	# --- HOLE SECTIONS (everything except the safe path) ---
	for seg in [[lx, path_lx], [path_rx, rx]]:
		var sx: float = seg[0]; var ex: float = seg[1]
		if ex - sx < 2.0:
			continue
		# Cavity: dark fill, slightly inset at the far edge to fake perspective depth.
		var inset: float = (ex - sx) * 0.10
		var cavity := PackedVector2Array([
			Vector2(sx, base.y), Vector2(ex, base.y),
			Vector2(ex - inset, far_y), Vector2(sx + inset, far_y),
		])
		draw_colored_polygon(cavity, Color(murk.r, murk.g, murk.b, 1.0))
		# Depth gradient — a darker band deeper in.
		var deep := PackedVector2Array([
			Vector2(sx + inset, far_y), Vector2(ex - inset, far_y),
			Vector2(ex - inset*1.6, far_y + depth*0.30), Vector2(sx + inset*1.6, far_y + depth*0.30),
		])
		draw_colored_polygon(deep, Color(0, 0, 0, 0.55))
		# Zone murk glow rising from the bottom (e.g. green sewer light).
		draw_line(Vector2(sx + inset, far_y), Vector2(ex - inset, far_y),
				Color(rim.r, rim.g, rim.b, 0.30 * pulse), 4.0 * s)
		# Bright near lip — the edge you'd trip over.
		draw_line(Vector2(sx, base.y), Vector2(ex, base.y),
				Color(rim.r, rim.g, rim.b, 0.95 * pulse), maxf(3.0, 5.0 * s))
		# Hazard chevrons on the lip warning DO-NOT-ENTER.
		var stripes := int((ex - sx) / (26.0 * s)) + 1
		for k in range(stripes):
			var hx: float = sx + (ex - sx) * float(k) / float(stripes)
			draw_line(Vector2(hx, base.y), Vector2(hx + 10.0*s, base.y - 12.0*s),
					Color(rim.r, rim.g, rim.b, 0.5 * pulse), 2.0 * s)

	# --- SAFE PATH: springboard that auto-launches the player over the gap ---
	var path_col := Color(0.0, 1.0, 0.55)
	var spring_hw: float = lane_w * 0.42
	var spring_base := Vector2(path_cx, base.y)
	var coil_h: float = depth * 0.5
	# Base plate of the spring
	draw_rect(Rect2(path_cx - spring_hw * 0.85, base.y - 10.0 * s, spring_hw * 1.7, 10.0 * s),
		Color(path_col.r, path_col.g, path_col.b, 0.8))
	# Coil zigzag
	var coil_pts := PackedVector2Array()
	var csteps := 6
	for ci in range(csteps + 1):
		var frac: float = float(ci) / float(csteps)
		var cy: float = base.y - 10.0 * s - coil_h * frac
		var cx: float = path_cx + (spring_hw * 0.6 if ci % 2 == 0 else -spring_hw * 0.6)
		coil_pts.append(Vector2(cx, cy))
	draw_polyline(coil_pts, Color(path_col.r, path_col.g, path_col.b, 0.9 * pulse), 4.0 * s)
	# Launch pad
	var lpad_y: float = base.y - 10.0 * s - coil_h - 12.0 * s
	draw_rect(Rect2(path_cx - spring_hw, lpad_y, spring_hw * 2.0, 12.0 * s),
		Color(path_col.r, path_col.g, path_col.b, 0.95))
	draw_rect(Rect2(path_cx - spring_hw, lpad_y, spring_hw * 2.0, 12.0 * s),
		Color(1.0, 1.0, 1.0, 0.5 * pulse), false, 2.0 * s)
	# Upward chevrons above pad
	for ai in range(3):
		var ay: float = lpad_y - (14.0 + float(ai) * 12.0) * s
		var aw: float = spring_hw * (0.7 - float(ai) * 0.18)
		var alpha: float = (0.9 - float(ai) * 0.25) * pulse
		draw_line(Vector2(path_cx - aw, ay + 9.0 * s), Vector2(path_cx, ay),
			Color(path_col.r, path_col.g, path_col.b, alpha), 3.0 * s)
		draw_line(Vector2(path_cx + aw, ay + 9.0 * s), Vector2(path_cx, ay),
			Color(path_col.r, path_col.g, path_col.b, alpha), 3.0 * s)
