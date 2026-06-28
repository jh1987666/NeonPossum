extends Node2D

# Distance-based gate spawning — a fixed PIXEL spacing so power-up gates stay
# evenly paced instead of becoming 3x rarer as the world speeds up.

var config: Dictionary
var active: bool = false
var gate_scene: PackedScene

var dist_since_spawn: float = 0.0
var gate_gap_px: float = 7200.0

func _ready() -> void:
	gate_scene = preload("res://scenes/gate.tscn")

func start(cfg: Dictionary) -> void:
	config = cfg
	# Convert the old 12s interval into a constant pixel spacing at start speed
	gate_gap_px = cfg.world.start_speed * cfg.gates.spawn_interval
	dist_since_spawn = 0.0
	active = true
	for child in get_children():
		child.queue_free()

func stop() -> void:
	active = false

func _process(delta: float) -> void:
	if not active:
		return
	dist_since_spawn += _get_main().get_speed() * delta
	if dist_since_spawn >= gate_gap_px:
		dist_since_spawn = 0.0
		_spawn_gate()

func _spawn_gate() -> void:
	var types: Array = config.gates.types
	var t: Dictionary = types[randi() % types.size()]
	var lane: int = randi() % 3
	var gate: Node2D = gate_scene.instantiate()
	add_child(gate)
	gate.setup(t, lane, _get_main().get_speed(), config.gates)
	gate.activated.connect(_on_gate_activated)

func _on_gate_activated(gate_type: String) -> void:
	_get_main().on_gate_activated(gate_type)

func _get_main() -> Node:
	return get_parent()
