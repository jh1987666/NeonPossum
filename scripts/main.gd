extends Node2D

signal score_changed(score: int)
signal gems_changed(gems: int)
signal game_over

enum State { MENU, PLAYING, DEAD }

var config: Dictionary
var state: State = State.MENU
var score: int = 0
var gem_count: int = 0
var distance: float = 0.0
var elapsed: float = 0.0
var current_speed: float = 0.0
var speed_timer: float = 0.0
var speed_peak_timer: float = 0.0   # counts up while at max speed; triggers decay after hold
var speed_decaying: bool = false
var hit_relief_timer: float = 0.0  # seconds of enforced speed drop after a non-fatal hit
var slow_timer: float = 0.0         # SLOW gate: world speed dampened while > 0
var slow_target_speed: float = 0.0  # fixed target speed captured at gate activation
var gem_multiplier: int = 1
var bonus_score: int = 0   # punch/combo points (score is otherwise recomputed each frame)

@onready var player: Node2D = $Player
@onready var obstacle_spawner: Node2D = $ObstacleSpawner
@onready var gem_spawner: Node2D = $GemSpawner
@onready var gate_spawner: Node2D = $GateSpawner
@onready var bg_scroller: Node2D = $BackgroundScroller
@onready var hud: CanvasLayer = $HUD
@onready var menu_layer: CanvasLayer = $MenuLayer
@onready var death_layer: CanvasLayer = $DeathLayer

var State_PLAYING = 1  # expose for child scripts

# Screen shake: offsets this Node2D (the game world) briefly. CanvasLayers
# (HUD/menus) ignore the Node2D transform, so they stay rock-steady.
var shake_amt: float = 0.0
var shake_decay: float = 6.0

# Punch combo: consecutive minion bowl-overs within COMBO_WINDOW stack a score
# multiplier. Lapse the window and the combo resets.
var combo: int = 0
var combo_timer: float = 0.0
var run_max_combo: int = 0
const COMBO_WINDOW: float = 2.2

# Leap combo (Zombie Tsunami style): jump over obstacles in sequence to build a
# multiplier. Lapses if you go too long without a hop.
var leap_combo: int = 0
var leap_timer: float = 0.0
const LEAP_WINDOW: float = 3.2

var revives_used: int = 0   # this run; revive cost escalates per use
var run_finalized: bool = true   # true = nothing pending; first start_game is a no-op
var current_zone: int = 1
var selected_char: String = "zee"

var _char_select: Node = null
var _shop: Node = null
var _near_lbl: Label = null
var run_near_misses: int = 0
var boss: Node = null
var boss_cleared: Array = []   # zones whose boss has been beaten this run

# Fetch the SaveData autoload by tree path so this script parses even if the
# editor hasn't registered the global name yet (autoload added mid-session).
@onready var save_data: Node = get_node("/root/SaveData")
@onready var missions: Node = get_node("/root/Missions")

func _ready() -> void:
	# Keep processing while the tree is paused so the pause toggle/ESC still work.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# ...but the gameplay nodes must STOP when paused. They're children of this
	# ALWAYS node, so without this they'd inherit ALWAYS and ignore the pause.
	for n in [$Player, $ObstacleSpawner, $GemSpawner, $GateSpawner,
			$BackgroundScroller, $PerspectiveFloor]:
		n.process_mode = Node.PROCESS_MODE_PAUSABLE
	config = _load_config()
	current_speed = config.world.start_speed
	# Character select layer (built in code, no scene file needed)
	_char_select = load("res://scripts/char_select_layer.gd").new()
	_char_select.name = "CharSelectLayer"
	add_child(_char_select)
	_char_select.play_pressed.connect(_on_char_select_play)
	_char_select.back_pressed.connect(_show_menu)

	# Boss encounter controller (built in code; drawn in world space at track top)
	boss = load("res://scripts/boss.gd").new()
	boss.name = "Boss"
	boss.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(boss)
	boss.setup(self)
	boss.boss_defeated.connect(_on_boss_defeated)

	# Dev: jump straight into the boss fight from the menu.
	var boss_btn := Button.new()
	boss_btn.text = "BOSS FIGHT"
	boss_btn.add_theme_font_size_override("font_size", 34)
	boss_btn.anchor_left = 0.5
	boss_btn.anchor_right = 0.5
	boss_btn.offset_left = -410
	boss_btn.offset_right = -20
	boss_btn.offset_top = 1200
	boss_btn.offset_bottom = 1270
	boss_btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.4))
	boss_btn.pressed.connect(start_boss_run)
	menu_layer.add_child(boss_btn)

	# Upgrade shop (built in code; spend gems on powerup upgrades)
	_shop = load("res://scripts/shop_layer.gd").new()
	_shop.name = "ShopLayer"
	add_child(_shop)
	_shop.back_pressed.connect(_show_menu)
	var shop_btn := Button.new()
	shop_btn.text = "◈ SHOP"
	shop_btn.add_theme_font_size_override("font_size", 34)
	shop_btn.anchor_left = 0.5
	shop_btn.anchor_right = 0.5
	shop_btn.offset_left = 20
	shop_btn.offset_right = 410
	shop_btn.offset_top = 1200
	shop_btn.offset_bottom = 1270
	shop_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.8))
	shop_btn.pressed.connect(_show_shop)
	menu_layer.add_child(shop_btn)

	_build_postfx()

	# Near-miss "close call" feedback label (own label so it never fights the
	# combo/zone text).
	_near_lbl = Label.new()
	_near_lbl.add_theme_font_size_override("font_size", 42)
	_near_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_near_lbl.anchor_left = 0.5
	_near_lbl.anchor_right = 0.5
	_near_lbl.offset_left = -320
	_near_lbl.offset_right = 320
	_near_lbl.offset_top = 1280
	_near_lbl.offset_bottom = 1345
	_near_lbl.modulate = Color(1, 1, 1, 0)
	$HUD.add_child(_near_lbl)

	# Mission mini-bar: 3 tiny progress labels at the very bottom of the screen
	for i in range(3):
		var ml := Label.new()
		ml.name = "MissionMini%d" % i
		ml.add_theme_font_size_override("font_size", 18)
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ml.anchor_left = 0.0; ml.anchor_right = 1.0
		ml.offset_top  = 1820 + i * 28
		ml.offset_bottom = 1820 + i * 28 + 26
		ml.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 0.65))
		$HUD.add_child(ml)

	# Wire buttons
	$MenuLayer/StartButton.pressed.connect(_show_char_select)
	$DeathLayer/RetryButton.pressed.connect(start_game)
	$DeathLayer/ReviveButton.pressed.connect(revive)
	# Return to the main menu after dying (was: had to close the game).
	var death_menu := Button.new()
	death_menu.text = "MENU"
	death_menu.add_theme_font_size_override("font_size", 36)
	death_menu.anchor_left = 0.5
	death_menu.anchor_right = 0.5
	death_menu.anchor_top = 1.0
	death_menu.anchor_bottom = 1.0
	death_menu.offset_left = -200
	death_menu.offset_right = 200
	death_menu.offset_top = -160
	death_menu.offset_bottom = -80
	death_menu.pressed.connect(_death_to_menu)
	$DeathLayer.add_child(death_menu)
	# Pause controls
	$HUD/PauseButton.pressed.connect(func(): set_paused(true))
	$PauseLayer/ResumeButton.pressed.connect(func(): set_paused(false))
	$PauseLayer/RestartButton.pressed.connect(func(): set_paused(false); start_game())
	$PauseLayer/MenuButton.pressed.connect(_pause_to_menu)
	# Sound toggle (persisted)
	Sfx.set_muted(not save_data.sound_on)
	$MenuLayer/SoundButton.pressed.connect(_toggle_sound)
	_refresh_sound_button()
	# Wire player death
	$Player.died.connect(on_player_died)
	# Wire shield on/off to the HUD powerup label
	$Player.shield_changed.connect(_on_shield_changed)
	# Wire HUD score updates
	score_changed.connect(func(s): $HUD/ScoreLabel.text = str(s))
	gems_changed.connect(_on_gems_changed)
	# Mission completion feedback
	missions.mission_completed.connect(_on_mission_completed)
	# Full-screen black intro: play the neon-sign animation once, then the menu.
	$IntroLayer/IntroVideo.finished.connect(_end_intro)
	_start_intro()
	# Dev capture hook: NP_AUTO=run|boss boots straight into gameplay so the
	# renderer can be screenshotted. No effect in normal play.
	if OS.has_environment("NP_AUTO"):
		call_deferred("_debug_autostart", OS.get_environment("NP_AUTO"))

func _debug_autostart(mode: String) -> void:
	_end_intro()
	if mode == "boss":
		start_boss_run()
	elif mode == "select":
		_show_char_select()
	elif mode == "shop":
		_show_shop()
	else:
		selected_char = "zee"
		start_game()

func _on_mission_completed(text: String, reward: int) -> void:
	save_data.add_gems(reward)
	# Flash on the combo line (free real estate mid-screen).
	var label: Label = $HUD/ComboLabel
	label.text = "MISSION! +%d ◈" % reward
	label.modulate = Color(0.4, 1.0, 0.5, 1)
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(func():
		if combo < 2:
			label.text = "")

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and state == State.PLAYING:
			set_paused(not get_tree().paused)
			return
		if $IntroLayer.visible:
			_end_intro()
		elif state == State.MENU and event.keycode in [KEY_ENTER, KEY_SPACE]:
			_show_char_select()
		elif state == State.DEAD and event.keycode in [KEY_ENTER, KEY_SPACE, KEY_R]:
			start_game()

# --- Pause ----------------------------------------------------------------

func set_paused(p: bool) -> void:
	if state != State.PLAYING:
		return
	get_tree().paused = p
	$PauseLayer.visible = p

func _pause_to_menu() -> void:
	get_tree().paused = false
	$PauseLayer.visible = false
	_finalize_run()   # abandoned run still banks its gems/stats
	obstacle_spawner.stop()
	gem_spawner.stop()
	gate_spawner.stop()
	if boss:
		boss.stop()
	player.is_alive = false
	Sfx.stop_music()
	_clear_spawned()
	_show_menu()

# Free leftover obstacles/gems/gates when bailing to the menu.
func _clear_spawned() -> void:
	for n in obstacle_spawner.get_children():
		n.queue_free()
	for n in gem_spawner.get_children():
		n.queue_free()
	for n in gate_spawner.get_children():
		n.queue_free()

func spawn_roof_gems(roof_y: float, obs: Node) -> void:
	# Spread 5 teal gems in the player's lane above the roof, staggered ahead.
	# They move at world speed so they stay planted on the vehicle top.
	var gem_scene: PackedScene = load("res://scenes/gem.tscn")
	if gem_scene == null:
		return
	var lane: int = player.lane
	var gem_cfg: Dictionary = config.gems.teal
	for i in range(5):
		var gem: Node2D = gem_scene.instantiate()
		gem_spawner.add_child(gem)
		gem.setup(gem_cfg, lane, get_speed(), roof_y - 120.0 - i * 90.0)
		gem.collected.connect(func(v: int): on_gem_collected(v))

func _unhandled_input(event: InputEvent) -> void:
	# Tap/click anywhere skips the intro splash.
	if not $IntroLayer.visible:
		return
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed)
	if pressed:
		_end_intro()

func _load_config() -> Dictionary:
	var f := FileAccess.open("res://game_config.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text())

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_update_shake(delta)
	if state != State.PLAYING:
		return

	_update_combo(delta)
	_update_leap(delta)
	_update_zone()
	_update_mission_minibars()
	elapsed += delta
	var old_score := score
	distance += current_speed * delta * config.scoring.distance_per_second / 1000.0
	var jinx_mult: float = 1.0 + float(player.get_meta("score_bonus_pct", 0.0))
	score = int(float(int(distance) + gem_count * gem_multiplier + bonus_score) * jinx_mult)
	if score != old_score:
		emit_signal("score_changed", score)

	# SLOW gate: ease to fixed target speed, then ramp back when expired.
	if slow_timer > 0.0:
		slow_timer -= delta
		current_speed = move_toward(current_speed, slow_target_speed, 500.0 * delta)
		speed_peak_timer = 0.0
		if slow_timer <= 0.0:
			# Expired — ramp back up from wherever we are; reset decay state so
			# normal increment logic takes over immediately.
			speed_decaying = false
			speed_peak_timer = 0.0

	# Hit relief: non-fatal shield hits drop speed to 70% of current for a few seconds.
	if hit_relief_timer > 0.0:
		hit_relief_timer -= delta
		var relief_target: float = config.world.start_speed + (current_speed - config.world.start_speed) * 0.55
		current_speed = move_toward(current_speed, relief_target, 180.0 * delta)
		speed_peak_timer = 0.0   # don't count toward peak hold during relief

	speed_timer += delta
	if speed_timer >= config.world.speed_increment_interval:
		speed_timer = 0.0
		if hit_relief_timer > 0.0 or slow_timer > 0.0:
			pass   # suppress ramp during relief / slow windows
		elif not speed_decaying and current_speed < config.world.max_speed:
			current_speed = minf(
				current_speed + config.world.speed_increment,
				config.world.max_speed
			)
			_flash_speed_up()
	# Once at peak, hold for speed_peak_hold seconds then decay back to start_speed.
	var peak_hold: float = config.world.get("speed_peak_hold", 45.0)
	var decay_rate: float = config.world.get("speed_decay", 6.0)
	if not speed_decaying and current_speed >= config.world.max_speed:
		speed_peak_timer += delta
		if speed_peak_timer >= peak_hold:
			speed_decaying = true
	if speed_decaying:
		current_speed = maxf(
			config.world.start_speed,
			current_speed - decay_rate * delta
		)
		if current_speed <= config.world.start_speed:
			# Bottom out: ramp back up again (wave pattern for long runs)
			speed_decaying = false
			speed_peak_timer = 0.0

func _flash_speed_up() -> void:
	var label: Label = $HUD/ComboLabel
	if combo >= 2:
		return  # don't stomp an active combo display
	label.text = "SPEED UP!"
	label.modulate = Color(1, 0.86, 0.24, 1)
	var tw := create_tween()
	tw.tween_interval(0.7)
	tw.tween_callback(func():
		if combo < 2:
			label.text = "")

# --- Zone progression ---------------------------------------------------

func _update_mission_minibars() -> void:
	var sums: Array = missions.summaries()
	for i in range(3):
		var lbl: Label = $HUD.get_node_or_null("MissionMini%d" % i)
		if lbl == null:
			return
		if i < sums.size():
			lbl.text = sums[i]
		else:
			lbl.text = ""

func _update_zone() -> void:
	if not config.has("zones"):
		return
	if boss and boss.is_active():
		return   # hold zone progression hostage until the boss is down
	var thresholds: Array = config.zones.thresholds
	var new_zone: int = 1
	for i in range(thresholds.size()):
		if distance >= float(thresholds[i]):
			new_zone = i + 1
	if new_zone != current_zone:
		_enter_zone(new_zone)

func _enter_zone(z: int) -> void:
	current_zone = z
	obstacle_spawner.set_zone(z)
	$PerspectiveFloor.set_zone(z)
	add_shake(10.0)
	Sfx.play("powerup")
	_flash_zone_name(z)
	# Each zone's boss guards the gateway into the NEXT zone: fight the boss of
	# the zone you just finished the first time you cross its threshold.
	var prev_zone: int = z - 1
	if prev_zone >= 1 and not boss_cleared.has(prev_zone):
		_begin_boss(prev_zone)

# Full-screen radial vignette so the bright neon center pops and the edges
# fall into shadow — cheap cinematic depth, no shader needed.
func _build_postfx() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, 0.5))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.width = 270
	gtex.height = 480
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.52)
	gtex.fill_to = Vector2(1.0, 1.0)
	var layer := CanvasLayer.new()
	layer.layer = 0   # same plane as the world; tree order puts it above, HUD(1) above it
	var vig := TextureRect.new()
	vig.texture = gtex
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.z_index = 0
	layer.add_child(vig)
	add_child(layer)

func _on_gems_changed(g: int) -> void:
	var lbl: Label = $HUD/GemsLabel
	lbl.text = "GEMS: %d" % g
	lbl.pivot_offset = lbl.size * 0.5
	lbl.scale = Vector2(1.18, 1.18)
	var tw := create_tween()
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.16)

func _show_controls_hint() -> void:
	var cl: Label = $HUD/ComboLabel
	cl.text = "SWIPE  ←  →  to move\n↑ jump          ↓ slide"
	cl.modulate = Color(1, 1, 1, 0.9)
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_callback(func(): if combo < 2: cl.text = "")

func _flash_now_playing() -> void:
	if not _char_select:
		return
	var nm: String = _char_select.display_name(selected_char)
	var col: Color = _char_select.color_for(selected_char)
	var perk: String = _char_select.perk_for(selected_char)

	var label: Label = $HUD/PowerupLabel
	label.text = "▶ %s" % nm
	label.modulate = col

	# Perk banner — second label below the name, fades after 2.5s
	if not $HUD.has_node("PerkBanner"):
		var pb := Label.new()
		pb.name = "PerkBanner"
		pb.add_theme_font_size_override("font_size", 28)
		pb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pb.anchor_left = 0.5
		pb.anchor_right = 0.5
		pb.offset_left = -400
		pb.offset_right = 400
		pb.offset_top = 420
		pb.offset_bottom = 470
		pb.modulate = Color(1, 1, 1, 0)
		$HUD.add_child(pb)
	var pb: Label = $HUD.get_node("PerkBanner")
	pb.text = "✦ %s" % perk.to_upper()
	pb.add_theme_color_override("font_color", col.lightened(0.3))
	pb.modulate = Color(1, 1, 1, 1)
	var tw2 := create_tween()
	tw2.tween_interval(2.0)
	tw2.tween_property(pb, "modulate:a", 0.0, 0.6)

	var tw := create_tween()
	tw.tween_interval(1.3)
	tw.tween_callback(func(): label.text = "")

func _begin_boss(z: int) -> void:
	if boss and not boss.is_active():
		boss.start(z)

func start_boss_run() -> void:
	# Dev entry: start a fresh run and drop straight into zone 1's boss.
	if _char_select:
		_char_select.hide_screen()
	start_game()
	_begin_boss(1)

func _on_boss_defeated(reward: int) -> void:
	boss_cleared.append(boss.zone)
	gem_count += reward
	save_data.total_gems += reward
	emit_signal("gems_changed", gem_count)
	# Hand the track back to the normal spawners.
	if state == State.PLAYING:
		obstacle_spawner.start(config)
		obstacle_spawner.set_zone(current_zone)
		gem_spawner.start(config)
		gate_spawner.start(config)

func _flash_zone_name(z: int) -> void:
	if not config.has("zones"):
		return
	var names: Array = config.zones.names
	if z < 1 or z > names.size():
		return
	var zone_name: String = str(names[z - 1])
	var label: Label = $HUD/ComboLabel
	label.text = "ZONE %d\n%s" % [z, zone_name.to_upper()]
	label.modulate = Color(0.0, 1.0, 0.8, 1.0)
	label.scale = Vector2(1.3, 1.3)
	var tw := create_tween()
	tw.tween_property(label, "scale", Vector2.ONE, 0.35)
	tw.tween_interval(2.0)
	tw.tween_callback(func():
		if combo < 2:
			label.text = "")

func start_game() -> void:
	_finalize_run()   # close out the previous (dead) run exactly once
	get_tree().paused = false
	Engine.time_scale = 1.0   # clear any leftover hit-stop slow-mo
	$PauseLayer.visible = false
	run_finalized = false
	state = State.PLAYING
	score = 0
	gem_count = 0
	bonus_score = 0
	distance = 0.0
	elapsed = 0.0
	speed_timer = 0.0
	speed_peak_timer = 0.0
	speed_decaying = false
	hit_relief_timer = 0.0
	slow_timer = 0.0
	slow_target_speed = 0.0
	current_speed = config.world.start_speed
	gem_multiplier = 1
	menu_layer.hide()
	death_layer.hide()
	$HUD/PowerupLabel.text = ""
	$HUD/ComboLabel.text = ""
	combo = 0
	combo_timer = 0.0
	run_max_combo = 0
	leap_combo = 0
	leap_timer = 0.0
	run_near_misses = 0
	revives_used = 0
	current_zone = 1
	boss_cleared = []
	if boss:
		boss.stop()
	obstacle_spawner.set_zone(1)
	($PerspectiveFloor as Node2D).call("reset_zone")
	hud.show()
	_flash_now_playing()
	if save_data.runs == 0:
		_show_controls_hint()
	Sfx.start_music()
	player.config = config
	player.start()
	if player.has_meta("score_bonus_pct"): player.remove_meta("score_bonus_pct")
	if player.has_meta("combo_hold_bonus"): player.remove_meta("combo_hold_bonus")
	_apply_char_perk(selected_char)
	obstacle_spawner.start(config)
	gem_spawner.start(config)
	gate_spawner.start(config)
	bg_scroller.start(config)

func on_player_died() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	obstacle_spawner.stop()
	gem_spawner.stop()
	gate_spawner.stop()
	if boss:
		boss.stop()
	Sfx.play("hit")
	Sfx.stop_music()
	add_shake(34.0)
	_hitstop(0.11)
	_show_death_screen()
	emit_signal("game_over")

# Brief slow-mo freeze at the moment of impact — cheap, high-value "juice".
func _hitstop(real_secs: float) -> void:
	Engine.time_scale = 0.12
	var tmr: SceneTreeTimer = get_tree().create_timer(real_secs, true, false, true)
	tmr.timeout.connect(func(): Engine.time_scale = 1.0)

func _on_shield_changed(active: bool) -> void:
	var label: Label = $HUD/PowerupLabel
	if active:
		label.text = "🛡 SHIELD"
		label.modulate = Color(0.0, 0.9, 1.0, 1.0)
	else:
		# Brief "SHIELD DOWN!" flash, then clear
		label.text = "SHIELD DOWN!"
		label.modulate = Color(1.0, 0.3, 0.3, 1.0)
		var tw := create_tween()
		tw.tween_interval(0.8)
		tw.tween_callback(func(): label.text = "")
		# Give the player a 4-second speed relief after absorbing a hit
		hit_relief_timer = 4.0

func on_gem_collected(value: int) -> void:
	# gem_count is the raw gem tally; the score formula applies the multiplier
	# (don't multiply here too, or gems would be counted twice over).
	gem_count += value
	save_data.total_gems += value   # bank live so it's spendable (e.g. revive)
	emit_signal("gems_changed", gem_count)
	Sfx.play("gem")
	missions.report("gems", 1)

func on_minion_punched(value: int) -> void:
	# NPC bowled over — pure score bonus, no death (like Minion Rush "Punch Minion").
	# Consecutive punches stack a combo multiplier.
	combo += 1
	combo_timer = COMBO_WINDOW
	run_max_combo = maxi(run_max_combo, combo)
	bonus_score += value * combo   # persists; score formula in _process adds it
	missions.report("punch", 1)
	emit_signal("score_changed", score)
	Sfx.play("gem")
	add_shake(10.0 + 2.0 * float(combo))  # bigger thump as the combo climbs
	var cl: Label = $HUD/ComboLabel
	if combo >= 2:
		cl.text = "COMBO x%d  +%d" % [combo, value * combo]
		cl.modulate = Color(1, 0.4, 0.8, 1)
		cl.scale = Vector2(1.3, 1.3)
		var tw := create_tween()
		tw.tween_property(cl, "scale", Vector2.ONE, 0.18)
	else:
		cl.text = "+%d" % (value * combo)
		cl.modulate = Color(1.0, 0.6, 0.9, 1)
		cl.scale = Vector2(1.15, 1.15)
		var tw2 := create_tween()
		tw2.tween_property(cl, "scale", Vector2.ONE, 0.16)
		tw2.tween_interval(0.5)
		tw2.tween_callback(func(): if combo < 2: cl.text = "")

func on_near_miss() -> void:
	if state != State.PLAYING:
		return
	run_near_misses += 1
	var base_near_bonus: int = 5
	if selected_char == "zee":
		base_near_bonus *= run_near_misses   # ×1 first, ×2 second, ×3 third … cap feel good
		base_near_bonus = mini(base_near_bonus, 50)
	bonus_score += base_near_bonus
	missions.report("near_miss", 1)
	emit_signal("score_changed", score)
	if _near_lbl:
		_near_lbl.text = "CLOSE!  +%d" % base_near_bonus if selected_char == "zee" else "CLOSE!  +5"
		_near_lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 1.0))
		_near_lbl.modulate = Color(1, 1, 1, 1)
		var tw := create_tween()
		tw.tween_property(_near_lbl, "modulate:a", 0.0, 0.55)

func on_obstacle_cleared(kind: String) -> void:
	if kind == "spring":
		missions.report("spring", 1)
	if kind != "jump" and kind != "spring":
		return
	leap_combo += 1
	var cira_bonus: float = float(player.get_meta("combo_hold_bonus", 0.0))
	leap_timer = LEAP_WINDOW + cira_bonus
	# Escalating reward; every clear is worth more as the chain grows.
	bonus_score += 2 * leap_combo
	emit_signal("score_changed", score)
	# Flashy milestone every 5 leaps.
	if leap_combo >= 3 and leap_combo % 5 == 0:
		bonus_score += leap_combo * 10
		Sfx.play("gem")
		add_shake(8.0)
		var cl: Label = $HUD/ComboLabel
		if combo < 2:   # don't stomp an active punch combo
			cl.text = "LEAP ×%d!" % leap_combo
			cl.modulate = Color(0.4, 1.0, 0.9, 1)
			cl.scale = Vector2(1.4, 1.4)
			var tw := create_tween()
			tw.tween_property(cl, "scale", Vector2.ONE, 0.22)
			tw.tween_interval(0.8)
			tw.tween_callback(func():
				if combo < 2 and leap_combo == 0:
					cl.text = "")
	elif leap_combo >= 2 and combo < 2:
		var cl2: Label = $HUD/ComboLabel
		cl2.text = "LEAP ×%d" % leap_combo
		# Color tier: cyan→yellow→orange→red as the chain climbs
		var leap_col: Color
		if leap_combo < 5:
			leap_col = Color(0.4, 1.0, 0.9, 0.9)    # cyan
		elif leap_combo < 10:
			leap_col = Color(1.0, 0.95, 0.2, 0.95)   # yellow
		elif leap_combo < 20:
			leap_col = Color(1.0, 0.55, 0.1, 1.0)    # orange
		else:
			leap_col = Color(1.0, 0.2, 0.3, 1.0)     # red — you're insane
		cl2.modulate = leap_col
		cl2.scale = Vector2(1.0 + minf(float(leap_combo) * 0.015, 0.35), 1.0 + minf(float(leap_combo) * 0.015, 0.35))
		var tw3 := create_tween()
		tw3.tween_property(cl2, "scale", Vector2.ONE, 0.14)

func _update_leap(delta: float) -> void:
	if leap_timer <= 0.0:
		return
	leap_timer -= delta
	if leap_timer <= 0.0:
		leap_combo = 0
		if combo < 2:
			$HUD/ComboLabel.text = ""

func _update_combo(delta: float) -> void:
	if combo_timer <= 0.0:
		return
	combo_timer -= delta
	if combo_timer <= 0.0:
		combo = 0
		$HUD/ComboLabel.text = ""

func on_gate_activated(gate_type: String) -> void:
	# SLOW is handled entirely in main — no player state change needed.
	if gate_type == "slow":
		for g in config.gates.types:
			if g.id == "slow":
				slow_timer = float(g.duration)
				# Capture fixed target NOW — don't recalculate per-frame
				slow_target_speed = maxf(
					config.world.start_speed,
					current_speed * float(g.get("multiplier", 0.55))
				)
				break
		Sfx.play("powerup")
		missions.report("powerups", 1)
		var label: Label = $HUD/PowerupLabel
		label.text = "⏳ TIME WARP"
		label.modulate = Color(0.8, 0.3, 1.0, 1.0)
		return
	player.activate_powerup(gate_type, config.gates)
	Sfx.play("powerup")
	missions.report("powerups", 1)
	if gate_type == "hoverbike":
		missions.report("hoverbike", 1)
	# Flash a HUD tag for the timed powerups (shield handles its own indicator).
	var tags := {"ball": "● GOBLIN BALL", "speed": "» SPEED", "magnet": "🧲 MAGNET", "jetpack": "🚀 JETPACK", "hoverbike": "🏍 HOVERBIKE"}
	if tags.has(gate_type):
		var label: Label = $HUD/PowerupLabel
		label.text = tags[gate_type]
		label.modulate = Color(1, 0.93, 0.27, 1) if gate_type == "magnet" else Color(0, 0.8, 1, 1)

func _toggle_sound() -> void:
	save_data.sound_on = not save_data.sound_on
	save_data.save_game()
	Sfx.set_muted(not save_data.sound_on)
	if save_data.sound_on and state == State.PLAYING:
		Sfx.start_music()
	_refresh_sound_button()

func _refresh_sound_button() -> void:
	$MenuLayer/SoundButton.text = "SOUND: ON" if save_data.sound_on else "SOUND: OFF"

func set_gem_multiplier(mult: int) -> void:
	gem_multiplier = mult

func get_speed() -> float:
	# Factor in the player's active speed power-up so world matches the runner
	return current_speed * player.speed_mult

func add_shake(amount: float) -> void:
	shake_amt = maxf(shake_amt, amount)

func _update_shake(delta: float) -> void:
	if shake_amt <= 0.01:
		if position != Vector2.ZERO:
			position = Vector2.ZERO
		shake_amt = 0.0
		return
	position = Vector2(randf_range(-shake_amt, shake_amt), randf_range(-shake_amt, shake_amt))
	shake_amt = lerpf(shake_amt, 0.0, shake_decay * delta)

# --- Intro splash ---------------------------------------------------------

func _start_intro() -> void:
	state = State.MENU
	$IntroLayer.show()
	menu_layer.hide()
	death_layer.hide()
	hud.hide()
	$IntroLayer/IntroVideo.play()

func _end_intro() -> void:
	if not $IntroLayer.visible:
		return
	$IntroLayer/IntroVideo.stop()
	$IntroLayer.hide()
	_show_menu()

func _show_char_select() -> void:
	menu_layer.hide()
	if _char_select:
		_char_select.show_screen()

func _show_shop() -> void:
	menu_layer.hide()
	if _shop:
		_shop.show_screen()

func _death_to_menu() -> void:
	_finalize_run()       # bank stats/gems for the run we're abandoning
	_clear_spawned()
	Engine.time_scale = 1.0
	death_layer.hide()
	_show_menu()

func _apply_char_perk(char_id: String) -> void:
	# Mechanical hookups for per-character perks. Player-side perks (shield, jump,
	# lane speed, magnet, duration mult) are set in player.apply_perk().
	player.apply_perk(char_id)
	match char_id:
		"rix":
			pass   # handled via revive_cap() — RIX gets 4 revives instead of 3
		"echo":
			gem_multiplier = 2  # +100% gem value (generous for alpha; tune to 1.1x later)
		"jinx":
			# Bonus score multiplier — applied in score calc each frame.
			# Stored on player so score formula can read it.
			player.set_meta("score_bonus_pct", 0.15)
		"sable":
			# Head-start sprint: bump world speed up 20% for the first 8 seconds
			current_speed = minf(current_speed * 1.25, config.world.max_speed * 0.6)
		"cira":
			# Combos hold longer — handled by bumping combo_timer on next cleared obstacle.
			player.set_meta("combo_hold_bonus", 1.5)

func _on_char_select_play(char_id: String) -> void:
	selected_char = char_id
	if _char_select:
		_char_select.hide_screen()
	start_game()

func _show_menu() -> void:
	if _char_select:
		_char_select.hide_screen()
	if _shop:
		_shop.hide_screen()
	state = State.MENU
	menu_layer.show()
	death_layer.hide()
	hud.hide()
	menu_layer.get_node("BestLabel").text = "BEST %d   COMBO x%d   GEMS %d" % [
		save_data.high_score, save_data.best_combo, save_data.total_gems]
	menu_layer.get_node("MissionsLabel").text = "\n".join(missions.summaries())
	# Daily login reward (pays out once per calendar day, escalates with streak).
	var daily: Dictionary = save_data.try_daily_reward()
	var dl: Label = menu_layer.get_node("DailyLabel")
	if daily.claimed:
		dl.text = "DAILY REWARD  +%d ◈   (streak %d)" % [daily.reward, daily.streak]
	else:
		dl.text = ""

func _show_death_screen() -> void:
	# Peek whether this beats the record (actual persistence happens in
	# _finalize_run, once, so a revive doesn't double-count stats).
	var is_best: bool = score > save_data.high_score
	death_layer.show()
	var go_label: Label = death_layer.get_node("GameOverLabel")
	if is_best:
		go_label.text = "NEW BEST!"
		go_label.add_theme_color_override("font_color", Color(1, 0.86, 0.24, 1))
	elif player._in_dumpster:
		go_label.text = "BONK. 🗑️"
		go_label.add_theme_color_override("font_color", Color(1, 0.55, 0.0, 1))
	else:
		go_label.text = "GAME OVER"
		go_label.add_theme_color_override("font_color", Color(1, 0.13, 0.33, 1))
	death_layer.get_node("ScoreLabel").text = "SCORE: %d" % score
	death_layer.get_node("GemsLabel").text = "GEMS: %d" % gem_count
	death_layer.get_node("BestLabel").text = "BEST: %d" % maxi(score, save_data.high_score)
	# Run stat line — gives players context on how the run went
	var stat_parts: Array = []
	if run_near_misses > 0:
		stat_parts.append("%d close call%s" % [run_near_misses, "s" if run_near_misses > 1 else ""])
	if run_max_combo > 1:
		stat_parts.append("×%d combo" % run_max_combo)
	if leap_combo > 0 or (leap_timer <= 0 and leap_combo == 0 and bonus_score > 0):
		pass  # leap already captured in score
	if stat_parts.size() > 0:
		var sl: Label = death_layer.get_node_or_null("StatLabel")
		if sl == null:
			sl = Label.new()
			sl.name = "StatLabel"
			sl.add_theme_font_size_override("font_size", 26)
			sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 0.85))
			sl.anchor_left = 0.0; sl.anchor_right = 1.0
			sl.offset_top = 620; sl.offset_bottom = 660
			death_layer.add_child(sl)
		sl.text = " · ".join(stat_parts)
	else:
		var sl: Label = death_layer.get_node_or_null("StatLabel")
		if sl: sl.text = ""
	# Offer a paid revive while affordable and under the per-run cap.
	var rbtn: Button = death_layer.get_node("ReviveButton")
	var cost: int = revive_cost()
	var revive_cap: int = 4 if selected_char == "rix" else 3
	if revives_used < revive_cap and save_data.total_gems >= cost:
		rbtn.visible = true
		rbtn.text = "REVIVE  ◈%d" % cost
	else:
		rbtn.visible = false

# Record stats + mission progress exactly once when a run truly ends (player
# declines revive and leaves the death screen, or abandons via pause→menu).
func _finalize_run() -> void:
	if run_finalized:
		return
	run_finalized = true
	save_data.record_run(score, int(distance), gem_count, run_max_combo)
	missions.report("distance", int(distance))
	missions.report("runs", 1)
	missions.report_max("combo", run_max_combo)

func revive_cost() -> int:
	return 40 + revives_used * 40   # 40, 80, 120

func revive() -> void:
	var cost: int = revive_cost()
	if save_data.total_gems < cost:
		return
	save_data.total_gems -= cost
	save_data.save_game()
	revives_used += 1
	death_layer.hide()
	state = State.PLAYING
	_clear_spawned()                 # wipe hazards so you don't instantly re-die
	player.revive()
	obstacle_spawner.start(config)
	gem_spawner.start(config)
	gate_spawner.start(config)
	Sfx.start_music()
