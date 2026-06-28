extends Node2D

# Distance-based spawning: obstacle spacing is measured in PIXELS traveled,
# not seconds. This keeps gaps fair no matter how fast the world is moving.

var config: Dictionary
var active: bool = false
var obstacle_scene: PackedScene
var current_zone: int = 1

var total_dist: float = 0.0      # total pixels traveled this run
var dist_since_spawn: float = 0.0
var next_gap: float = 1320.0     # pixels until next spawn

# Pixel gaps derived from config (using start_speed as the reference)
var gap_start_px: float = 1320.0
var gap_min_px: float = 420.0
var gap_decay: float = 0.04

# Arrival-time spacing: obstacles travel from SPAWN_Y down to the player plane.
# Faster (oncoming) obstacles cover that distance quicker, so a fixed pixel gap
# lets them overtake a slower obstacle and arrive at the SAME instant —
# undodgeable. We instead guarantee a minimum gap between successive ARRIVAL
# times at the player, computed from each obstacle's true closing speed.
const SPAWN_Y: float = -100.0
const PLAYER_PLANE_Y: float = 1480.0
const MIN_ARRIVAL_GAP: float = 0.95   # seconds between obstacles reaching the player
# Extra cushion: the world keeps accelerating, so a leading obstacle arrives a
# touch sooner than predicted. Padding the gap absorbs that compression.
const ARRIVAL_PAD: float = 0.15
# Tall multi-lane vehicles (bus/train) visually hide anything spawned behind
# them. Give the NEXT obstacle extra lead time so the occluder has scrolled
# down/past before the next hazard appears — no more "slide hidden by the bus".
const OCCLUDER_EXTRA: float = 1.3     # seconds of extra gap after a tall wide vehicle
var game_t: float = 0.0               # run clock
var last_arrival_t: float = -10.0     # when the most recent obstacle hits the plane
var occluder_clear_t: float = -10.0   # game_t when the last occluder clears the player view
var occluder_lanes: Array = []        # lanes the last occluder occupied
# Seeded combo: after certain setups we queue a follow-up obstacle to create intentional chains
var pending_combo: Dictionary = {}    # {type_id, lane, spawn_at_game_t}
var combo_cooldown: float = 0.0      # don't combo again for this many seconds

func _ready() -> void:
	obstacle_scene = preload("res://scenes/obstacle.tscn")

func start(cfg: Dictionary) -> void:
	config = cfg
	var ref_speed: float = cfg.world.start_speed
	gap_start_px = ref_speed * cfg.obstacles.spawn_interval_start
	gap_min_px = ref_speed * cfg.obstacles.spawn_interval_min
	gap_decay = cfg.obstacles.spawn_interval_decay
	total_dist = 0.0
	dist_since_spawn = 0.0
	next_gap = gap_start_px * 0.5  # first obstacle comes a bit sooner
	game_t = 0.0
	last_arrival_t = -10.0
	occluder_clear_t = -10.0
	occluder_lanes.clear()
	pending_combo.clear()
	combo_cooldown = 0.0
	active = true
	for child in get_children():
		child.queue_free()

func stop() -> void:
	active = false

func set_zone(z: int) -> void:
	current_zone = z

func _process(delta: float) -> void:
	if not active:
		return
	var v: float = _get_main().get_speed()
	var step: float = v * delta
	total_dist += step
	dist_since_spawn += step
	game_t += delta

	if combo_cooldown > 0.0:
		combo_cooldown -= delta
	# Check if a pending combo obstacle is ready to fire
	if not pending_combo.is_empty() and game_t >= float(pending_combo.get("spawn_at_game_t", 0.0)):
		_spawn_combo()

	if dist_since_spawn >= next_gap:
		_try_spawn(v)

func _current_gap() -> float:
	# Gap shrinks with distance traveled, clamped to the minimum
	return maxf(gap_min_px, gap_start_px - total_dist * gap_decay)

# Predict when an obstacle spawned NOW would reach the player plane, given its
# total closing speed (world speed + any self_speed for oncoming traffic).
func _arrival_time(t: Dictionary, world_speed: float) -> float:
	var closing: float = world_speed + float(t.get("self_speed", 0.0))
	if closing <= 1.0:
		closing = 1.0
	return game_t + (PLAYER_PLANE_Y - SPAWN_Y) / closing

func _try_spawn(world_speed: float) -> void:
	var t: Dictionary = _pick_type()
	var arr: float = _arrival_time(t, world_speed)
	# Arrival-time gap: prevents fast + slow obstacles stacking undodgeably.
	if arr - last_arrival_t < MIN_ARRIVAL_GAP + ARRIVAL_PAD:
		return
	# Occlusion guard: skip hazards that would arrive while a tall vehicle still
	# visually covers the same or adjacent lanes — player can't see them coming.
	if game_t < occluder_clear_t and not _is_occluder(t) and not occluder_lanes.is_empty():
		var candidate_lanes: int = int(t.get("lanes", 1))
		var start_lane: int = randi() % (3 - candidate_lanes + 1)
		for i in range(candidate_lanes):
			if (start_lane + i) in occluder_lanes:
				return   # would hide behind occluder — skip this tick
	dist_since_spawn = 0.0
	next_gap = _current_gap() * randf_range(0.85, 1.15)
	last_arrival_t = arr
	if _is_occluder(t):
		last_arrival_t += OCCLUDER_EXTRA
		occluder_clear_t = game_t + OCCLUDER_EXTRA + MIN_ARRIVAL_GAP
		# Record which lanes this occluder blocks
		var blk: int = int(t.get("lanes", 1))
		var sl: int = randi() % (3 - blk + 1)
		occluder_lanes.clear()
		for i in range(blk):
			occluder_lanes.append(sl + i)
	_spawn_obstacle(t)

# Tall, wide vehicles that block the view of whatever is behind them.
func _is_occluder(t: Dictionary) -> bool:
	return int(t.get("lanes", 1)) >= 2 \
		and t.get("style", "") == "sprite" \
		and float(t.get("height", 0.0)) >= 400.0

func _spawn_obstacle(t: Dictionary) -> void:
	# Pick random lane(s); multi-lane obstacles pick a valid contiguous block.
	var lanes_used: Array[int] = []
	var blocked_lanes: int = int(t.lanes)
	var start_lane: int = randi() % (3 - blocked_lanes + 1)
	for i in range(blocked_lanes):
		lanes_used.append(start_lane + i)

	# Multi-lane beams and wall_gap span as ONE wide visual — don't stack instances.
	if t.get("style", "") in ["beam", "wall_gap"] and blocked_lanes > 1:
		var obs: Node2D = obstacle_scene.instantiate()
		add_child(obs)
		obs.zone = current_zone
		obs.setup(t, lanes_used, _get_main().get_speed())
		_wire(obs)
		_maybe_seed_combo(str(t.get("id", "")), 1)
		return

	for lane in lanes_used:
		var obs: Node2D = obstacle_scene.instantiate()
		add_child(obs)
		obs.zone = current_zone
		obs.setup(t, [lane], _get_main().get_speed())
		_wire(obs)
	# Possibly queue a satisfying follow-up obstacle off the springboard
	if not lanes_used.is_empty():
		_maybe_seed_combo(str(t.get("id", "")), lanes_used[0])

# After spawning a springboard, queue a juicy follow-up for the player to chain.
# 12% chance when no combo is on cooldown and distance is far enough in.
func _maybe_seed_combo(spawned_id: String, lane: int) -> void:
	if combo_cooldown > 0.0 or total_dist < 2000.0:
		return
	if spawned_id != "springboard":
		return
	if randf() > 0.12:
		return
	# Pick a follow-up: high beam overhead (always jumpable from spring height) or wall_gap
	var follow_ids: Array = ["elec_high", "wall_gap"]
	var fid: String = follow_ids[randi() % follow_ids.size()]
	# Queue it to appear ~0.9 seconds after the spring's arrival
	var v: float = _get_main().get_speed()
	var spring_arr: float = _arrival_time(_find_type("springboard"), v)
	pending_combo = {"type_id": fid, "lane": lane, "spawn_at_game_t": spring_arr - 0.9}
	combo_cooldown = 18.0   # don't chain again for 18 seconds

func _spawn_combo() -> void:
	var fid: String = str(pending_combo.get("type_id", ""))
	var lane: int = int(pending_combo.get("lane", 1))
	pending_combo.clear()
	var t: Dictionary = _find_type(fid)
	if t.is_empty():
		return
	# wall_gap is always 3-lane; elec_high is 1-lane
	var lanes_used: Array[int] = []
	if fid == "wall_gap":
		lanes_used = [0, 1, 2]
	else:
		lanes_used = [clampi(lane, 0, 2)]
	var obs: Node2D = obstacle_scene.instantiate()
	add_child(obs)
	obs.zone = current_zone
	obs.setup(t, lanes_used, _get_main().get_speed())
	_wire(obs)

func _find_type(id: String) -> Dictionary:
	for t in config.obstacles.types:
		if str(t.get("id", "")) == id:
			return t
	return {}

func _wire(obs: Node2D) -> void:
	obs.hit_player.connect(_on_obstacle_hit_player)
	obs.punched.connect(_on_obstacle_punched)
	obs.cleared.connect(_on_obstacle_cleared)
	obs.near_miss.connect(_on_obstacle_near_miss)

# Weighted random pick. Filters to current zone; beams ramp up over distance.
func _pick_type() -> Dictionary:
	# Only include obstacle types available in the current zone
	var types: Array = config.obstacles.types.filter(
		func(t): return t.get("min_zone", 1) <= current_zone
	)
	var total: float = 0.0
	var weights: Array = []
	for t in types:
		var w: float = float(t.get("weight", 1))
		if t.get("style", "") == "beam":
			w += clampf(total_dist / 6000.0, 0.0, 3.0)
		weights.append(w)
		total += w
	var r: float = randf() * total
	for i in range(types.size()):
		r -= weights[i]
		if r <= 0.0:
			return types[i]
	return types[0]

func _on_obstacle_hit_player(cause: String) -> void:
	_get_main().player.take_hit(cause)

func _on_obstacle_punched(score: int) -> void:
	_get_main().on_minion_punched(score)

func _on_obstacle_cleared(kind: String) -> void:
	_get_main().on_obstacle_cleared(kind)

func _on_obstacle_near_miss() -> void:
	_get_main().on_near_miss()

func _get_main() -> Node:
	return get_parent()
