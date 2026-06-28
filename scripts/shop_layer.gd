extends CanvasLayer

signal back_pressed

# Gem sink: spend collected gems to upgrade powerup durations. Each level adds
# +20% duration (handled by SaveData.upgrade_mult, read in player.activate_powerup).
const ITEMS := [
	{"id": "magnet",  "name": "MAGNET",      "desc": "Longer + reaches all lanes", "color": Color(1.0, 0.93, 0.27)},
	{"id": "ball",    "name": "GOBLIN BALL", "desc": "Roll through longer",   "color": Color(0.0, 0.8, 1.0)},
	{"id": "speed",   "name": "SPEED BURST", "desc": "Boost lasts longer",    "color": Color(1.0, 0.66, 0.0)},
	{"id": "jetpack",   "name": "JETPACK",   "desc": "Stay airborne longer",   "color": Color(0.0, 0.87, 1.0)},
	{"id": "hoverbike", "name": "HOVER BIKE", "desc": "Ride longer before landing",  "color": Color(1.0, 0.42, 0.0)},
	{"id": "slow",      "name": "TIME WARP",  "desc": "World slows for longer",       "color": Color(0.8, 0.3,  1.0)},
]

var _save: Node = null
var _rows: Array = []
var _gem_lbl: Label = null
var _msg_lbl: Label = null

func _ready() -> void:
	layer = 15
	visible = false
	_save = get_node_or_null("/root/SaveData")
	_build_ui()

func show_screen() -> void:
	visible = true
	_refresh()

func hide_screen() -> void:
	visible = false

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.06, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "UPGRADE SHOP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.8))
	title.position = Vector2(0, 60)
	title.size = Vector2(1080, 90)
	add_child(title)

	_gem_lbl = Label.new()
	_gem_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gem_lbl.add_theme_font_size_override("font_size", 44)
	_gem_lbl.add_theme_color_override("font_color", Color(0.0, 1.0, 0.8))
	_gem_lbl.position = Vector2(0, 165)
	_gem_lbl.size = Vector2(1080, 60)
	add_child(_gem_lbl)

	var y0: float = 300.0
	var rh: float = 250.0
	for i in range(ITEMS.size()):
		_rows.append(_make_row(ITEMS[i], 70.0, y0 + i * rh, 940.0))

	_msg_lbl = Label.new()
	_msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_lbl.add_theme_font_size_override("font_size", 34)
	_msg_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	_msg_lbl.position = Vector2(0, 300.0 + ITEMS.size() * rh + 10.0)
	_msg_lbl.size = Vector2(1080, 50)
	add_child(_msg_lbl)

	var back := Button.new()
	back.text = "← BACK"
	back.add_theme_font_size_override("font_size", 40)
	back.anchor_top = 1.0
	back.anchor_bottom = 1.0
	back.anchor_left = 0.5
	back.anchor_right = 0.5
	back.offset_left = -220
	back.offset_right = 220
	back.offset_top = -150
	back.offset_bottom = -56
	back.pressed.connect(func(): hide_screen(); emit_signal("back_pressed"))
	add_child(back)

func _make_row(item: Dictionary, x: float, y: float, w: float) -> Dictionary:
	var panel := Panel.new()
	panel.position = Vector2(x, y)
	panel.size = Vector2(w, 220)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.11, 1.0)
	style.set_border_width_all(3)
	style.border_color = Color(item.color.r, item.color.g, item.color.b, 0.6)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var name_lbl := Label.new()
	name_lbl.text = item.name
	name_lbl.add_theme_font_size_override("font_size", 40)
	name_lbl.add_theme_color_override("font_color", item.color)
	name_lbl.position = Vector2(30, 18)
	name_lbl.size = Vector2(w - 60, 50)
	panel.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = item.desc
	desc_lbl.add_theme_font_size_override("font_size", 26)
	desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 1.0, 0.85))
	desc_lbl.position = Vector2(30, 72)
	desc_lbl.size = Vector2(w - 60, 36)
	panel.add_child(desc_lbl)

	var lvl_lbl := Label.new()
	lvl_lbl.add_theme_font_size_override("font_size", 30)
	lvl_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	lvl_lbl.position = Vector2(30, 130)
	lvl_lbl.size = Vector2(420, 50)
	panel.add_child(lvl_lbl)

	var buy := Button.new()
	buy.add_theme_font_size_override("font_size", 34)
	buy.position = Vector2(w - 360, 120)
	buy.size = Vector2(330, 80)
	buy.pressed.connect(func(): _buy(item.id))
	panel.add_child(buy)

	return {"id": item.id, "lvl": lvl_lbl, "buy": buy, "color": item.color}

func _buy(id: String) -> void:
	if not _save:
		return
	if _save.try_buy_upgrade(id):
		Sfx.play("powerup")
		_flash("UPGRADED!", Color(0.4, 1.0, 0.5))
	else:
		if _save.get_upgrade(id) >= _save.MAX_UP_LEVEL:
			_flash("MAXED OUT", Color(1.0, 0.8, 0.2))
		else:
			_flash("NOT ENOUGH GEMS", Color(1.0, 0.4, 0.4))
	_refresh()

func _flash(text: String, col: Color) -> void:
	if not _msg_lbl:
		return
	_msg_lbl.text = text
	_msg_lbl.add_theme_color_override("font_color", col)
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(func(): _msg_lbl.text = "")

func _refresh() -> void:
	if not _save:
		return
	_gem_lbl.text = "◈ %d GEMS" % _save.total_gems
	for r in _rows:
		var lvl: int = _save.get_upgrade(r.id)
		r.lvl.text = "LV %d / %d" % [lvl, _save.MAX_UP_LEVEL]
		if lvl >= _save.MAX_UP_LEVEL:
			r.buy.text = "MAXED"
			r.buy.disabled = true
		else:
			var cost: int = _save.upgrade_cost(r.id)
			r.buy.text = "BUY  ◈%d" % cost
			r.buy.disabled = _save.total_gems < cost
