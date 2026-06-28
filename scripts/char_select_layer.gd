extends CanvasLayer

signal play_pressed(char_id: String)
signal back_pressed

# The wife-approved roster. `tex` is the selection-card portrait. Perks are shown
# as flavor for now; the mechanical hookups land per-character later. Names for
# the unnamed folders are placeholders — easy to rename here.
var CHARS := [
	{"id": "zee",  "name": "ZEE",   "tex": "res://assets/sprites/final/run_03.png",                       "perk": "Close calls score x2 each", "color": Color(0.0, 0.92, 1.0)},
	{"id": "zoe",  "name": "ZOE",   "tex": "res://assets/sprites/Character 8/download (85).jpeg",          "perk": "Passive gem magnet",        "color": Color(0.7, 0.4, 1.0)},
	{"id": "lumen","name": "LUMEN", "tex": "res://assets/sprites/Character 15/1782277317139.png",          "perk": "Power-ups last longer",     "color": Color(0.85, 0.5, 1.0)},
	{"id": "nova", "name": "NOVA",  "tex": "res://assets/sprites/Character 3/download (92).jpeg",           "perk": "Starts with a shield",      "color": Color(1.0, 0.4, 0.8)},
	{"id": "rix",  "name": "RIX",   "tex": "res://assets/sprites/Character 7/download (88).jpeg",           "perk": "+1 revive per run",         "color": Color(1.0, 0.55, 0.0)},
	{"id": "kane", "name": "KANE",  "tex": "res://assets/sprites/Character 10/download (87).jpeg",          "perk": "Shrugs off the first hit",  "color": Color(0.2, 1.0, 0.5)},
	{"id": "echo", "name": "ECHO",  "tex": "res://assets/sprites/Character 17/download (27).jpeg",          "perk": "+10% coins",                "color": Color(0.0, 1.0, 0.8)},
	{"id": "vibe", "name": "VIBE",  "tex": "res://assets/sprites/Character 18/download (84).jpeg",          "perk": "Snappier lane changes",     "color": Color(1.0, 0.75, 0.2)},
	{"id": "pixel","name": "PIXEL", "tex": "res://assets/sprites/Character 19/download (100).jpeg",         "perk": "Higher jump",               "color": Color(0.3, 0.7, 1.0)},
	{"id": "jinx", "name": "JINX",  "tex": "res://assets/sprites/Character 21/download (33).jpeg",          "perk": "Bonus score multiplier",    "color": Color(1.0, 0.16, 0.67)},
	{"id": "sable","name": "SABLE", "tex": "res://assets/sprites/Character 22/download (99).jpeg",          "perk": "Head-start sprint",         "color": Color(0.5, 0.8, 1.0)},
	{"id": "cira", "name": "CIRA",  "tex": "res://assets/sprites/Character 23/download.jpeg",               "perk": "Combos hold longer",        "color": Color(0.4, 1.0, 0.3)},
]

const COLS: int = 3
const CARD_W: float = 312.0
const CARD_H: float = 348.0
const GAP_X: float = 18.0
const GAP_Y: float = 16.0
const GRID_TOP: float = 150.0

var selected: int = 0
var _card_panels: Array = []

func _ready() -> void:
	layer = 15
	visible = false
	_build_ui()

func show_screen() -> void:
	visible = true
	_refresh_selection()

func hide_screen() -> void:
	visible = false

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.06, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "CHOOSE YOUR RUNNER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.0, 0.92, 1.0))
	title.position = Vector2(0, 48)
	title.size = Vector2(1080, 80)
	add_child(title)

	# Scrollable grid so all 12 fit comfortably on a tall phone screen.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, GRID_TOP)
	scroll.size = Vector2(1080, 1480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var grid_w: float = CARD_W * COLS + GAP_X * (COLS - 1)
	var left: float = (1080.0 - grid_w) * 0.5
	var holder := Control.new()
	var rows: int = int(ceil(float(CHARS.size()) / float(COLS)))
	holder.custom_minimum_size = Vector2(1080, rows * (CARD_H + GAP_Y) + 40)
	scroll.add_child(holder)

	for i in range(CHARS.size()):
		var r: int = i / COLS
		var c: int = i % COLS
		var x: float = left + c * (CARD_W + GAP_X)
		var y: float = r * (CARD_H + GAP_Y)
		var card := _make_card(CHARS[i], x, y, i)
		holder.add_child(card)
		_card_panels.append(card)

	# PLAY button pinned to the bottom.
	var play_btn := Button.new()
	play_btn.text = "▶  RUN"
	play_btn.add_theme_font_size_override("font_size", 52)
	play_btn.anchor_top = 1.0
	play_btn.anchor_bottom = 1.0
	play_btn.anchor_left = 0.5
	play_btn.anchor_right = 0.5
	play_btn.offset_left = -230
	play_btn.offset_right = 230
	play_btn.offset_top = -150
	play_btn.offset_bottom = -56
	play_btn.pressed.connect(_on_play)
	add_child(play_btn)

	var back_btn := Button.new()
	back_btn.text = "← BACK"
	back_btn.add_theme_font_size_override("font_size", 30)
	back_btn.anchor_top = 1.0
	back_btn.anchor_bottom = 1.0
	back_btn.offset_left = 36
	back_btn.offset_right = 220
	back_btn.offset_top = -140
	back_btn.offset_bottom = -66
	back_btn.pressed.connect(func(): hide_screen(); emit_signal("back_pressed"))
	add_child(back_btn)

func _make_card(ch: Dictionary, x: float, y: float, idx: int) -> Panel:
	var panel := Panel.new()
	panel.position = Vector2(x, y)
	panel.size = Vector2(CARD_W, CARD_H)
	panel.clip_contents = true

	# Portrait fills the card, cover-cropped.
	var tex: Texture2D = load(ch.tex)
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.position = Vector2.ZERO
	pic.size = Vector2(CARD_W, CARD_H)
	panel.add_child(pic)

	# Bottom gradient so the name reads on any art.
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.62)
	shade.position = Vector2(0, CARD_H - 96)
	shade.size = Vector2(CARD_W, 96)
	panel.add_child(shade)

	var name_lbl := Label.new()
	name_lbl.text = ch.name
	name_lbl.add_theme_font_size_override("font_size", 38)
	name_lbl.add_theme_color_override("font_color", ch.color)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(0, CARD_H - 92)
	name_lbl.size = Vector2(CARD_W, 44)
	panel.add_child(name_lbl)

	var perk_lbl := Label.new()
	perk_lbl.text = ch.perk
	perk_lbl.add_theme_font_size_override("font_size", 21)
	perk_lbl.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0, 0.95))
	perk_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	perk_lbl.position = Vector2(4, CARD_H - 48)
	perk_lbl.size = Vector2(CARD_W - 8, 40)
	panel.add_child(perk_lbl)

	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.pressed.connect(func(): _select(idx))
	panel.add_child(btn)
	return panel

func _select(idx: int) -> void:
	selected = idx
	_refresh_selection()

func _refresh_selection() -> void:
	for i in range(_card_panels.size()):
		if not is_instance_valid(_card_panels[i]):
			continue
		var col: Color = CHARS[i].color
		var is_sel: bool = (i == selected)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.04, 0.03, 0.10, 1.0)
		style.set_border_width_all(6 if is_sel else 2)
		style.border_color = Color(col.r, col.g, col.b, 1.0 if is_sel else 0.4)
		style.set_corner_radius_all(10)
		if is_sel:
			style.shadow_color = Color(col.r, col.g, col.b, 0.6)
			style.shadow_size = 16
		_card_panels[i].add_theme_stylebox_override("panel", style)

func _on_play() -> void:
	emit_signal("play_pressed", CHARS[selected].id)

func display_name(id: String) -> String:
	for c in CHARS:
		if c.id == id:
			return c.name
	return "ZEE"

func color_for(id: String) -> Color:
	for c in CHARS:
		if c.id == id:
			return c.color
	return Color(0.0, 0.92, 1.0)

func perk_for(id: String) -> String:
	for c in CHARS:
		if c.id == id:
			return c.perk
	return ""
