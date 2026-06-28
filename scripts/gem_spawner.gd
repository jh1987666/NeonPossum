extends Node2D

# Distance-based gem spawning — same pixel-spacing logic as obstacles so
# gem density stays consistent regardless of world speed.

var config: Dictionary
var active: bool = false
var gem_scene: PackedScene

var dist_since_spawn: float = 0.0
var next_gap: float = 700.0

# Pixel gap range derived from the old 0.8–2.0s timing at start speed
var gap_min_px: float = 480.0
var gap_max_px: float = 1200.0

func _ready() -> void:
	gem_scene = preload("res://scenes/gem.tscn")

func start(cfg: Dictionary) -> void:
	config = cfg
	var ref_speed: float = cfg.world.start_speed
	gap_min_px = ref_speed * 0.8
	gap_max_px = ref_speed * 2.0
	dist_since_spawn = 0.0
	next_gap = ref_speed * 1.2  # first cluster
	active = true
	for child in get_children():
		child.queue_free()

func stop() -> void:
	active = false

func _process(delta: float) -> void:
	if not active:
		return
	dist_since_spawn += _get_main().get_speed() * delta
	if dist_since_spawn >= next_gap:
		dist_since_spawn = 0.0
		next_gap = randf_range(gap_min_px, gap_max_px)
		if randf() < config.gems.spawn_chance:
			_spawn_gems()

func _spawn_gems() -> void:
	var lane: int = randi() % 3
	var gem_cfg: Dictionary = _pick_gem_type()

	if randf() < config.gems.line_chance:
		# Spawn a line of 5 gems
		for i in range(5):
			_spawn_gem(lane, gem_cfg, -200.0 - i * 120.0)
	else:
		_spawn_gem(lane, gem_cfg, -100.0)

func _spawn_gem(lane: int, gem_cfg: Dictionary, y_off: float) -> void:
	var gem: Node2D = gem_scene.instantiate()
	add_child(gem)
	gem.setup(gem_cfg, lane, _get_main().get_speed(), y_off)
	gem.collected.connect(_on_gem_collected)

func _pick_gem_type() -> Dictionary:
	var r := randf()
	if r < 0.05:
		return config.gems.gold
	elif r < 0.25:
		return config.gems.teal
	else:
		return config.gems.pink

func _on_gem_collected(value: int) -> void:
	_get_main().on_gem_collected(value)

func _get_main() -> Node:
	return get_parent()
