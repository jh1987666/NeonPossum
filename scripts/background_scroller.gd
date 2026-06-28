extends Node2D

# Parallax background — 3 layers at different scroll speeds.
# Layer0/Layer0B tile the main background. Layer1/Layer2 for parallax art later.

var speeds: Array = [1.0, 0.6, 0.35]
var active: bool = false

# Two tiles for seamless BG loop
@onready var bg_a = $Layer0
@onready var bg_b = $Layer0B
@onready var mid_layer = $Layer1
@onready var fg_layer = $Layer2

func start(cfg: Dictionary) -> void:
	speeds = cfg.world.scroll_layer_speeds
	active = true

func _process(delta: float) -> void:
	if not active:
		return
	var spd: float = get_parent().get_speed()

	# Seamless tile scroll for main background
	for bg in [bg_a, bg_b]:
		bg.position.y += spd * speeds[0] * delta
		if bg.position.y >= 1920.0:
			bg.position.y -= 3840.0

	# Mid and foreground parallax layers (empty until art added)
	if mid_layer.get_child_count() > 0:
		mid_layer.position.y += spd * speeds[1] * delta
		if mid_layer.position.y >= 1920.0:
			mid_layer.position.y = fmod(mid_layer.position.y, 1920.0)

	if fg_layer.get_child_count() > 0:
		fg_layer.position.y += spd * speeds[2] * delta
		if fg_layer.position.y >= 1920.0:
			fg_layer.position.y = fmod(fg_layer.position.y, 1920.0)
