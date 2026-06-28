extends Node2D

# Boss duel, Minion Rush style: the boss broadcasts from a jumbotron at the end
# of the track and fires CHEST-CANNON LASERS down telegraphed lanes — dodge by
# switching lanes. Between volleys it exposes a STRIKE TARGET in a lane; run into
# it to fire back and chip the boss's health. You can't win by only surviving —
# you have to land hits. Get lasered (in the wrong lane) and it's a wipeout.

signal boss_defeated(reward: int)

const Perspective = preload("res://scripts/perspective.gd")
const LANE_WX := [270.0, 540.0, 810.0]   # world-X of the three lanes
const PLAYER_P := 0.82                    # progress of the player plane

# One entry per zone. `tex` is the broadcast portrait shown on the jumbotron.
const BOSSES := [
	{"name": "SENTINEL PRIME", "tex": "res://assets/sprites/Enemies/1759451820042.png", "hp": 6,  "rim": Color(1.0, 0.16, 0.67)},
	{"name": "TRANSIT WARDEN",  "tex": "res://assets/sprites/Enemies/1759459781440.png", "hp": 8,  "rim": Color(1.0, 0.75, 0.1)},
	{"name": "THE RAT QUEEN",   "tex": "res://assets/sprites/Enemies/1759464122346.png", "hp": 8,  "rim": Color(0.3, 1.0, 0.3)},
	{"name": "SYNAPSIS",        "tex": "res://assets/sprites/Enemies/1759468156743.png", "hp": 10, "rim": Color(0.4, 0.7, 1.0)},
	{"name": "APEX",            "tex": "res://assets/sprites/Enemies/1759468823536.png", "hp": 10, "rim": Color(0.85, 0.5, 1.0)},
]

enum Phase { IDLE, INTRO, TELEGRAPH, FIRE, STRIKE, SALVO, COOLDOWN }

var main: Node = null
var spawner: Node = null
var active: bool = false
var hp: int = 4
var max_hp: int = 4
var zone: int = 1
var rim: Color = Color(1.0, 0.16, 0.67)
var t: float = 0.0
var flash: float = 0.0
var boss_sprite: Sprite2D = null
var base_scale: Vector2 = Vector2.ONE

var phase: int = Phase.IDLE
var phase_t: float = 0.0
var target_lanes: Array = []      # lanes the chest cannons are aiming at
var fired_hit: bool = false       # laser already resolved against the player
var strike_obs: Node = null       # the current strike target (if any)
var salvo_targets: Array = []     # multiple punch targets during a missile salvo
var phase_count: int = 0          # fire cycles completed — drives strike vs salvo cadence
var counter_t: float = 0.0        # counter-shot bolt animation clock

# Jumbotron geometry (world space, top-center of the 1080-wide play area).
const SCREEN_CX: float = 540.0
const SCREEN_TOP: float = 110.0
const SCREEN_W: float = 620.0
const SCREEN_H: float = 460.0

func setup(main_ref: Node) -> void:
	main = main_ref
	spawner = main.obstacle_spawner
	z_index = 40
	boss_sprite = Sprite2D.new()
	boss_sprite.centered = true
	add_child(boss_sprite)
	visible = false

func is_active() -> bool:
	return active

func start(z: int) -> void:
	zone = z
	var def: Dictionary = BOSSES[clampi(z - 1, 0, BOSSES.size() - 1)]
	max_hp = int(def.hp)
	hp = max_hp
	rim = def.rim
	var tex: Texture2D = load(def.tex)
	boss_sprite.texture = tex
	if tex:
		var sc: float = minf(SCREEN_W / float(tex.get_width()), SCREEN_H / float(tex.get_height()))
		base_scale = Vector2(sc, sc)
		boss_sprite.scale = base_scale
		boss_sprite.position = Vector2(SCREEN_CX, SCREEN_TOP + SCREEN_H * 0.5)
	# Freeze normal spawners — the boss owns the track now.
	spawner.stop()
	main.gem_spawner.stop()
	main.gate_spawner.stop()
	main._clear_spawned()
	active = true
	t = 0.0
	flash = 0.0
	counter_t = 0.0
	phase_count = 0
	target_lanes = []
	salvo_targets.clear()
	_set_phase(Phase.INTRO)
	visible = true
	_boss_intro_card(z, def.name, def.rim)
	_announce(def.name)
	queue_redraw()

func stop() -> void:
	active = false
	visible = false
	if is_instance_valid(strike_obs):
		strike_obs.queue_free()
	strike_obs = null
	for o in salvo_targets:
		if is_instance_valid(o):
			o.queue_free()
	salvo_targets.clear()

func _set_phase(p: int) -> void:
	phase = p
	phase_t = 0.0

func _process(delta: float) -> void:
	if not active:
		return
	t += delta
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 3.0)
	if counter_t > 0.0:
		counter_t = maxf(0.0, counter_t - delta * 2.4)
	_animate_boss()
	phase_t += delta

	match phase:
		Phase.INTRO:
			if phase_t > 1.7:
				_begin_telegraph()
		Phase.TELEGRAPH:
			# Rage: telegraph is 30% shorter below half HP — less time to react
			var tele_dur: float = 0.6 if hp <= max_hp / 2 else 0.9
			if phase_t > tele_dur:
				_begin_fire()
		Phase.FIRE:
			_resolve_laser()
			if phase_t > 0.5:
				# Odd cycles: single strike target. Even cycles (or wounded): missile salvo.
				if phase_count % 2 == 0 or hp <= max_hp / 2:
					_begin_salvo()
				else:
					_begin_strike()
		Phase.STRIKE:
			# Window to catch the strike target. Ends when it's hit (freed) or times out.
			if not is_instance_valid(strike_obs):
				strike_obs = null
				_set_phase(Phase.COOLDOWN)
			elif phase_t > 2.6:
				if is_instance_valid(strike_obs):
					strike_obs.queue_free()
				strike_obs = null
				_set_phase(Phase.COOLDOWN)
		Phase.SALVO:
			# Scrub any targets that scrolled off or were already freed.
			salvo_targets = salvo_targets.filter(func(o): return is_instance_valid(o))
			if salvo_targets.is_empty():
				_set_phase(Phase.COOLDOWN)
			elif phase_t > 3.5:
				for o in salvo_targets:
					if is_instance_valid(o):
						o.queue_free()
				salvo_targets.clear()
				_set_phase(Phase.COOLDOWN)
		Phase.COOLDOWN:
			if phase_t > 0.6:
				_begin_telegraph()
	queue_redraw()

# --- Phase entries ---------------------------------------------------------

func _begin_telegraph() -> void:
	# Aim at 1 lane early, 2 lanes once the boss is wounded (harder).
	var n: int = 1 if hp > max_hp / 2 else 2
	target_lanes = _pick_lanes(n)
	fired_hit = false
	_set_phase(Phase.TELEGRAPH)

func _begin_fire() -> void:
	fired_hit = false
	flash = 0.5
	phase_count += 1
	var shake_amt: float = 14.0 if hp <= max_hp / 2 else 7.0
	main.add_shake(shake_amt)
	Sfx.play("hit")
	_set_phase(Phase.FIRE)

func _resolve_laser() -> void:
	if fired_hit or not is_instance_valid(main.player):
		return
	var pl: Node = main.player
	if not pl.is_alive:
		return
	# Lasers sweep whole lanes; only a lane change (or flying) saves you.
	if pl.lane in target_lanes \
			and pl.state != pl.State.BALL and pl.state != pl.State.JETPACK:
		fired_hit = true
		pl.take_hit("frontal")

func _begin_strike() -> void:
	target_lanes = []
	# Expose a strike target: an npc-style "punch" you run into to fire back.
	var def: Dictionary = _type_def("npc")
	if def.is_empty():
		_set_phase(Phase.COOLDOWN)
		return
	var obs: Node = preload("res://scenes/obstacle.tscn").instantiate()
	spawner.add_child(obs)
	obs.zone = zone
	obs.setup(def, [randi() % 3], main.get_speed())
	obs.punched.connect(_on_strike_hit)
	strike_obs = obs
	_set_phase(Phase.STRIKE)

func _begin_salvo() -> void:
	target_lanes = []
	salvo_targets.clear()
	# 2 missiles at full health, 3 when wounded (below half HP).
	var n: int = 3 if hp <= max_hp / 2 else 2
	var lanes: Array = [0, 1, 2]
	lanes.shuffle()
	var used: Array = lanes.slice(0, n)
	var def: Dictionary = _type_def("npc")
	if def.is_empty():
		_set_phase(Phase.COOLDOWN)
		return
	for li in used:
		var obs: Node = preload("res://scenes/obstacle.tscn").instantiate()
		spawner.add_child(obs)
		obs.zone = zone
		obs.setup(def, [li], main.get_speed())
		obs.salvo_projectile = true
		obs.punched.connect(func(_sc: int): _on_salvo_hit(obs))
		salvo_targets.append(obs)
	_set_phase(Phase.SALVO)
	# Brief HUD prompt so the player knows to punch back.
	var label: Label = main.get_node("HUD/ComboLabel")
	label.text = "PUNCH BACK!"
	label.modulate = Color(1.0, 0.9, 0.1, 1.0)
	label.scale = Vector2(1.2, 1.2)
	var tw := create_tween()
	tw.tween_property(label, "scale", Vector2.ONE, 0.2)
	tw.tween_interval(1.2)
	tw.tween_callback(func(): if active and phase == Phase.SALVO: label.text = "")

func _on_salvo_hit(obs: Node) -> void:
	salvo_targets.erase(obs)
	counter_t = 1.0
	_take_damage()

func _on_strike_hit(_score: int) -> void:
	# Player landed a hit — fire a counter-bolt up at the boss and damage it.
	counter_t = 1.0
	strike_obs = null
	_take_damage()

func _take_damage() -> void:
	hp -= 1
	flash = 1.0
	Sfx.play("powerup")
	main.add_shake(16.0)
	get_node("/root/Missions").report("boss_hit", 1)
	if hp <= 0:
		_defeat()

func _defeat() -> void:
	active = false
	if is_instance_valid(strike_obs):
		strike_obs.queue_free()
	strike_obs = null
	var reward: int = 50 + zone * 50
	Sfx.play("powerup")
	main.add_shake(40.0)
	var label: Label = main.get_node("HUD/ComboLabel")
	label.text = "BOSS DOWN!\n+%d ◈" % reward
	label.modulate = Color(0.4, 1.0, 0.5, 1.0)
	label.scale = Vector2(1.4, 1.4)
	var tw := create_tween()
	tw.tween_property(label, "scale", Vector2.ONE, 0.4)
	tw.tween_interval(1.4)
	tw.tween_callback(func(): label.text = "")
	var ft := create_tween()
	ft.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.8)
	ft.tween_callback(func():
		visible = false
		modulate = Color.WHITE)
	emit_signal("boss_defeated", reward)

# --- Helpers ---------------------------------------------------------------

func _pick_lanes(n: int) -> Array:
	# Each boss has a signature pattern that makes it feel distinct.
	match zone:
		1:  # SENTINEL PRIME — sweeping single shot, alternates sides
			var side: int = phase_count % 2   # left then right then left
			return [side * 2]                 # 0 or 2 (never center)
		2:  # TRANSIT WARDEN — pincer: both outer lanes simultaneously
			if n >= 2:
				return [0, 2]
			return [[0, 2][randi() % 2]]
		3:  # RAT QUEEN — random but always hits center on odd cycles
			if phase_count % 2 == 1:
				return [1]
			var sides := [0, 2]; sides.shuffle()
			return sides.slice(0, clampi(n, 1, 2))
		4:  # SYNAPSIS — rapid triple salvo, uses all 3 lanes in a rotating order
			var order := [[0,1],[1,2],[0,2],[0,1,2]]
			return order[phase_count % order.size()].slice(0, clampi(n, 1, 3))
		5:  # APEX — pure random but enraged Apex can hit all 3
			var all := [0, 1, 2]; all.shuffle()
			var cap: int = 3 if (hp <= max_hp / 2 and n >= 2) else clampi(n, 1, 2)
			return all.slice(0, cap)
		_:
			var all2 := [0, 1, 2]; all2.shuffle()
			return all2.slice(0, clampi(n, 1, 2))

func _type_def(id: String) -> Dictionary:
	for ty in main.config.obstacles.types:
		if str(ty.id) == id:
			return ty
	return {}

# Full-screen 2-second title card: zone name top, boss name large center, rimlight color.
# Engine.time_scale briefly freezes gameplay to let the card land before lasers start.
func _boss_intro_card(zone_num: int, boss_name: String, rim: Color) -> void:
	var zone_names: Array = main.config.zones.names if main.config.has("zones") else []
	var zone_label: String = zone_names[clampi(zone_num - 1, 0, zone_names.size() - 1)] if zone_names.size() > 0 else ("ZONE %d" % zone_num)

	var card := CanvasLayer.new()
	card.layer = 30
	main.add_child(card)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.06, 0.88)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(bg)

	var zone_lbl := Label.new()
	zone_lbl.text = "— ZONE %d —\n%s" % [zone_num, zone_label.to_upper()]
	zone_lbl.add_theme_font_size_override("font_size", 34)
	zone_lbl.add_theme_color_override("font_color", Color(rim.r, rim.g, rim.b, 0.75))
	zone_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone_lbl.anchor_left = 0.0; zone_lbl.anchor_right = 1.0
	zone_lbl.offset_top = 660; zone_lbl.offset_bottom = 760
	card.add_child(zone_lbl)

	var boss_lbl := Label.new()
	boss_lbl.text = boss_name
	boss_lbl.add_theme_font_size_override("font_size", 76)
	boss_lbl.add_theme_color_override("font_color", Color(rim.r, rim.g, rim.b, 1.0))
	boss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_lbl.anchor_left = 0.0; boss_lbl.anchor_right = 1.0
	boss_lbl.offset_top = 800; boss_lbl.offset_bottom = 920
	card.add_child(boss_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "INCOMING"
	sub_lbl.add_theme_font_size_override("font_size", 30)
	sub_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.85, 0.65))
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.anchor_left = 0.0; sub_lbl.anchor_right = 1.0
	sub_lbl.offset_top = 920; sub_lbl.offset_bottom = 970
	card.add_child(sub_lbl)

	# Hold 1.2s, then fade out and remove
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(bg, "color", Color(0.02, 0.01, 0.06, 0.0), 0.4)
	tw.parallel().tween_property(boss_lbl, "modulate", Color(1, 1, 1, 0), 0.4)
	tw.parallel().tween_property(zone_lbl, "modulate", Color(1, 1, 1, 0), 0.4)
	tw.parallel().tween_property(sub_lbl, "modulate", Color(1, 1, 1, 0), 0.4)
	tw.tween_callback(func(): card.queue_free())

func _announce(boss_name: String) -> void:
	var label: Label = main.get_node("HUD/ComboLabel")
	label.text = "⚠ BOSS ⚠\n%s" % boss_name
	label.modulate = Color(1.0, 0.2, 0.3, 1.0)
	label.scale = Vector2(1.4, 1.4)
	var tw := create_tween()
	tw.tween_property(label, "scale", Vector2.ONE, 0.4)
	tw.tween_interval(1.5)
	tw.tween_callback(func(): if active: label.text = "")

# --- Drawing ---------------------------------------------------------------

func _lane_target(lane: int) -> Vector2:
	return Vector2(Perspective.converge_x(LANE_WX[lane], PLAYER_P), Perspective.screen_y(PLAYER_P))

# Keeps the boss feeling alive even on a single still: a slow ken-burns zoom +
# sway, a charge-up swell while the cores spin up, and a forward LUNGE on fire.
func _animate_boss() -> void:
	if not boss_sprite:
		return
	var breathe: float = 1.0 + 0.02 * sin(t * 1.1)
	var sway_x: float = sin(t * 0.9) * 8.0
	var bob_y: float = sin(t * 1.6) * 10.0
	var punch: float = 0.0
	match phase:
		Phase.TELEGRAPH:
			breathe += 0.06 * clampf(phase_t / 0.9, 0.0, 1.0)
		Phase.FIRE:
			punch = 1.0 - clampf(phase_t / 0.5, 0.0, 1.0)   # snap forward, then ease back
	boss_sprite.scale = base_scale * (breathe + 0.10 * punch)
	boss_sprite.position = Vector2(
		SCREEN_CX + sway_x,
		SCREEN_TOP + SCREEN_H * 0.5 + bob_y + 26.0 * punch)

# The two glowing chest cores — where the lasers fire from. Tracked to her actual
# (swaying/lunging) position so the beams stay locked to her chest.
func _chest_origin(side: float) -> Vector2:
	var cx: float = boss_sprite.position.x if boss_sprite else SCREEN_CX
	var cy: float = (boss_sprite.position.y if boss_sprite else SCREEN_TOP + SCREEN_H * 0.5) - SCREEN_H * 0.10
	return Vector2(cx + side * 46.0, cy)

func _draw() -> void:
	if not active and modulate.a <= 0.01:
		return
	var top := SCREEN_TOP - 16.0
	var frame := Rect2(SCREEN_CX - SCREEN_W * 0.5 - 16.0, top, SCREEN_W + 32.0, SCREEN_H + 64.0)
	var enraged: bool = hp <= max_hp / 2
	var pulse_speed: float = 9.0 if enraged else 4.0
	var pulse: float = 0.6 + 0.4 * sin(t * pulse_speed)
	var glow: float = clampf(flash, 0.0, 1.0)
	# Rage: rim bleeds red when wounded
	var draw_rim: Color = rim.lerp(Color(1.0, 0.1, 0.15), 0.55 * float(enraged))
	# Jumbotron backing + neon frame + scanlines.
	draw_rect(frame, Color(0.02, 0.02, 0.05, 0.92))
	draw_rect(frame, Color(draw_rim.r, draw_rim.g, draw_rim.b, 0.85 * pulse + 0.15 * glow), false, 5.0)
	draw_rect(frame.grow(8.0), Color(draw_rim.r, draw_rim.g, draw_rim.b, 0.18 * pulse), false, 2.0)
	# Rage vignette: red inner glow when enraged
	if enraged:
		draw_rect(frame.grow(-4.0), Color(1.0, 0.05, 0.05, 0.06 * pulse), true)
	var y: float = top
	while y < top + SCREEN_H + 64.0:
		draw_line(Vector2(frame.position.x, y), Vector2(frame.position.x + frame.size.x, y),
			Color(0, 0, 0, 0.12), 1.0)
		y += 6.0
	# Hologram sweep — a brighter scanline travels down the broadcast.
	var sweep_y: float = top + fmod(t * 140.0, SCREEN_H + 64.0)
	draw_line(Vector2(frame.position.x, sweep_y), Vector2(frame.position.x + frame.size.x, sweep_y),
		Color(rim.r, rim.g, rim.b, 0.22), 2.0)
	# Occasional glitch slice — brief signal-tear on the feed.
	if fmod(t, 1.7) < 0.06:
		var gy: float = top + fmod(t * 533.0, SCREEN_H)
		draw_rect(Rect2(frame.position.x, gy, frame.size.x, 10.0), Color(rim.r, rim.g, rim.b, 0.30))
		draw_rect(Rect2(frame.position.x + 6, gy + 3, frame.size.x, 4.0), Color(0.0, 0.9, 1.0, 0.2))
	if glow > 0.0:
		draw_rect(frame, Color(1.0, 0.2, 0.2, 0.22 * glow))

	# --- Telegraph: chest cores spin up + warning rails down the targeted lanes ---
	if phase == Phase.TELEGRAPH:
		var warn: float = 0.4 + 0.6 * abs(sin(t * 14.0))
		var chg: float = clampf(phase_t / 0.9, 0.0, 1.0)   # cores brighten as they charge
		for s in [-1.0, 1.0]:
			var core: Vector2 = _chest_origin(s)
			draw_circle(core, 10.0 + 16.0 * chg, Color(1.0, 0.2, 0.5, 0.25 + 0.4 * chg * warn))
			draw_circle(core, 6.0 + 6.0 * chg, Color(1.0, 0.5, 0.7, 0.9))
		for lane in target_lanes:
			var tp: Vector2 = _lane_target(lane)
			var o: Vector2 = _chest_origin(0.0)
			draw_line(o, tp, Color(1.0, 0.2, 0.2, 0.5 * warn), 4.0)
			draw_circle(tp, 26.0, Color(1.0, 0.2, 0.2, 0.25 * warn))

	# --- Fire: chest-cannon laser beams into the targeted lanes ---
	if phase == Phase.FIRE:
		for i in range(target_lanes.size()):
			var lane: int = target_lanes[i]
			var tp: Vector2 = _lane_target(lane)
			var o: Vector2 = _chest_origin(-1.0 if i == 0 else 1.0)
			# muzzle flare
			draw_circle(o, 18.0, Color(1, 1, 1, 0.9))
			draw_circle(o, 30.0, Color(rim.r, rim.g, rim.b, 0.5))
			# beam (outer glow + hot core)
			draw_line(o, tp, Color(rim.r, rim.g, rim.b, 0.35), 30.0)
			draw_line(o, tp, Color(1.0, 0.3, 0.4, 0.8), 12.0)
			draw_line(o, tp, Color(1, 1, 1, 0.95), 4.0)
			draw_circle(tp, 30.0, Color(1.0, 0.4, 0.4, 0.6))

	# --- Salvo: small spinning missile orbs orbiting the chest cores ---
	if phase == Phase.SALVO:
		var n_orbs: int = salvo_targets.size()
		for i in range(n_orbs):
			var angle: float = t * 4.0 + TAU * float(i) / float(max(n_orbs, 1))
			for s in [-1.0, 1.0]:
				var core: Vector2 = _chest_origin(s)
				var orb: Vector2 = core + Vector2(cos(angle) * 28.0, sin(angle) * 18.0)
				draw_circle(orb, 9.0, Color(1.0, 0.9, 0.2, 0.9))
				draw_circle(orb, 5.0, Color(1.0, 1.0, 1.0, 1.0))

	# --- Counter-bolt: player's return fire streaking up to the boss ---
	if counter_t > 0.0:
		var prog: float = 1.0 - counter_t
		var from := Vector2(SCREEN_CX, 1480.0)
		var to := _chest_origin(0.0)
		var head: Vector2 = from.lerp(to, clampf(prog * 1.2, 0.0, 1.0))
		draw_line(from, head, Color(0.3, 1.0, 0.6, 0.5), 8.0)
		draw_circle(head, 14.0, Color(0.6, 1.0, 0.8, 0.95))

	# --- Health bar across the bottom of the jumbotron ---
	var bar_w: float = SCREEN_W
	var bx: float = SCREEN_CX - bar_w * 0.5
	var by: float = top + SCREEN_H + 30.0
	draw_rect(Rect2(bx, by, bar_w, 22.0), Color(0.1, 0.05, 0.08, 1.0))
	var frac: float = clampf(float(hp) / float(max_hp), 0.0, 1.0)
	var hb_col := Color(1.0, 0.2, 0.3) if frac < 0.34 else (Color(1.0, 0.7, 0.1) if frac < 0.67 else Color(0.3, 1.0, 0.4))
	draw_rect(Rect2(bx, by, bar_w * frac, 22.0), hb_col)
	draw_rect(Rect2(bx, by, bar_w, 22.0), Color(rim.r, rim.g, rim.b, 0.9), false, 2.0)
	for i in range(1, max_hp):
		var px: float = bx + bar_w * float(i) / float(max_hp)
		draw_line(Vector2(px, by), Vector2(px, by + 22.0), Color(0, 0, 0, 0.6), 2.0)
