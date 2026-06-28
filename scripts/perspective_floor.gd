extends Node2D

const Perspective = preload("res://scripts/perspective.gd")
const LOGO = preload("res://assets/sprites/ui/menu_logo_t.png")

# Synthwave 3D track: gradient sky + sun, a receding road with scrolling grid +
# lane dashes, and PARALLAX SIDE BUILDINGS carrying neon signs (some the Neon
# Possum logo). Purely visual — sells depth, speed and place.

const RUNG_COUNT: int = 22
const SCROLL_K: float = 0.00020

# Building system: discrete neon storefronts that scroll up the sides of the
# track from the horizon, recycling once they pass the camera.
const BUILDS_PER_SIDE: int = 9
const BUILD_SPAN: float = 1600.0     # world-Y distance over which they recycle

var phase: float = 0.0
var builds: Array = []               # {wy, side, w, h, base, sign, hue}
var _rng := RandomNumberGenerator.new()

# Wet-asphalt reflective flecks scattered on the road, scrolling toward the
# camera to give the ground real texture and speed (instead of a flat color).
var flecks: Array = []               # {xf (-1..1 across track), poff, sz}
var far_phase: float = 0.0           # slow parallax for the distant skyline

# Zone palette — each entry: [sky_top, sky_bot, road, grid, curb]
const ZONE_PALETTES := [
	[Color(0.04,0.024,0.09,1), Color(0.31,0.07,0.44,1), Color(0.09,0.075,0.16,1), Color(0.0,0.92,1.0,1),  Color(1.0,0.16,0.67,1)],  # 1 Neon City
	[Color(0.03,0.02,0.03,1),  Color(0.12,0.08,0.02,1), Color(0.07,0.06,0.05,1),  Color(1.0,0.75,0.0,1),  Color(1.0,0.55,0.0,1)],  # 2 Transit
	[Color(0.02,0.04,0.02,1),  Color(0.03,0.14,0.03,1), Color(0.04,0.08,0.04,1),  Color(0.2,1.0,0.1,1),   Color(0.4,1.0,0.2,1)],   # 3 Sewer
	[Color(0.03,0.04,0.12,1),  Color(0.04,0.12,0.40,1), Color(0.07,0.08,0.18,1),  Color(0.3,0.7,1.0,1),   Color(0.5,0.8,1.0,1)],   # 4 Corporate
	[Color(0.07,0.08,0.20,1),  Color(0.28,0.18,0.52,1), Color(0.12,0.10,0.20,1),  Color(0.8,0.5,1.0,1),   Color(1.0,0.4,0.8,1)],   # 5 Rooftop
]

var _pal_from: Array = []
var _pal_to:   Array = []
var _pal_t:    float = 1.0      # 1.0 = fully arrived, 0.0 = transition start
const PAL_SPEED: float = 0.5    # palette fully blends in 2 seconds
var _current_zone: int = 1

func set_zone(z: int) -> void:
	var idx: int = clampi(z - 1, 0, ZONE_PALETTES.size() - 1)
	_pal_from = _current_pal()
	_pal_to = ZONE_PALETTES[idx]
	_pal_t = 0.0
	_current_zone = z

func reset_zone() -> void:
	_pal_from = ZONE_PALETTES[0]
	_pal_to   = ZONE_PALETTES[0]
	_pal_t    = 1.0
	_current_zone = 1

func _current_pal() -> Array:
	if _pal_from.is_empty() or _pal_to.is_empty():
		return ZONE_PALETTES[0]
	var result: Array = []
	for i in range(5):
		result.append(_pal_from[i].lerp(_pal_to[i], _pal_t))
	return result

func _pal_color(idx: int) -> Color:
	if _pal_from.is_empty() or _pal_to.is_empty():
		return ZONE_PALETTES[0][idx]
	return _pal_from[idx].lerp(_pal_to[idx], _pal_t)

# Palette of neon facade hues.
const NEON := [
	Color(1.0, 0.16, 0.67),   # magenta
	Color(0.0, 0.92, 1.0),    # cyan
	Color(0.6, 0.2, 1.0),     # purple
	Color(1.0, 0.55, 0.0),    # amber
	Color(0.2, 1.0, 0.5),     # green
]

func _ready() -> void:
	z_index = 0
	_rng.seed = 1337
	_pal_from = ZONE_PALETTES[0]
	_pal_to   = ZONE_PALETTES[0]
	_pal_t    = 1.0
	_init_builds()
	_init_flecks()

func _init_flecks() -> void:
	flecks.clear()
	for i in range(72):
		flecks.append({
			"xf": _rng.randf_range(-0.96, 0.96),
			"poff": _rng.randf(),
			"sz": _rng.randf_range(0.7, 2.2),
		})

func _init_builds() -> void:
	builds.clear()
	for side in [-1, 1]:
		for i in range(BUILDS_PER_SIDE):
			var wy: float = Perspective.SPAWN_WY + BUILD_SPAN * float(i) / float(BUILDS_PER_SIDE)
			builds.append(_make_build(side, wy))

const ZONE_NEON := [
	[],  # unused (index 0)
	[],  # zone 1: use base NEON array
	[Color(1.0,0.55,0.0), Color(1.0,0.75,0.2), Color(0.9,0.40,0.0)],   # 2 amber
	[Color(0.2,1.0,0.1),  Color(0.1,0.9,0.3),  Color(0.4,1.0,0.2)],    # 3 green
	[Color(0.3,0.7,1.0),  Color(0.5,0.8,1.0),  Color(0.1,0.5,1.0)],    # 4 blue
	[Color(0.8,0.5,1.0),  Color(1.0,0.4,0.8),  Color(0.6,0.3,1.0)],    # 5 purple
]

func _make_build(side: int, wy: float) -> Dictionary:
	var pool: Array = ZONE_NEON[_current_zone] if _current_zone >= 2 else NEON
	var hue: Color = pool[_rng.randi() % pool.size()]
	return {
		"wy": wy,
		"side": side,
		"w": _rng.randf_range(360.0, 560.0),
		"h": _rng.randf_range(520.0, 980.0),
		"hue": hue,
		"sign": _rng.randi() % 5,
	}

func _process(delta: float) -> void:
	if _pal_t < 1.0:
		_pal_t = minf(_pal_t + PAL_SPEED * delta, 1.0)
	var spd: float = 600.0
	var main: Node = get_parent()
	if main and main.has_method("get_speed"):
		spd = main.get_speed()
	phase = fmod(phase + spd * delta * SCROLL_K, 1.0)
	far_phase = fmod(far_phase + spd * delta * SCROLL_K * 0.18, 1.0)
	# Scroll buildings toward the camera; recycle past the player plane.
	for b in builds:
		b.wy += spd * delta
		if b.wy > Perspective.PLAYER_WY + 250.0:
			var fresh := _make_build(b.side, b.wy - BUILD_SPAN)
			b.wy = fresh.wy
			b.w = fresh.w
			b.h = fresh.h
			b.hue = fresh.hue
			b.sign = fresh.sign
	queue_redraw()

func _draw() -> void:
	var hz: float = Perspective.HORIZON_Y
	var vx: float = Perspective.VANISH_X
	var vanish := Vector2(vx, hz)

	# --- sky gradient (top dark -> horizon color, zone-aware) ---
	var sky_top: Color = _pal_color(0)
	var sky_bot: Color = _pal_color(1)
	var bands := 32
	for i in range(bands):
		var t := float(i) / float(bands)
		var y0 := hz * t
		var y1 := hz * (t + 1.0 / bands)
		var c := sky_top.lerp(sky_bot, t * t)
		draw_rect(Rect2(0.0, y0, 1080.0, y1 - y0 + 1.0), c)

	# --- sun glow ---
	draw_circle(Vector2(vx, hz - 80.0), 150.0, Color(1.0, 0.35, 0.63, 0.28))
	draw_circle(Vector2(vx, hz - 80.0), 95.0, Color(1.0, 0.47, 0.71, 0.5))

	# --- distant parallax skyline (two layers, scrolling slowly, zone-tinted) ---
	var sky_tint: Color = _pal_color(1)
	var rim_tint: Color = _pal_color(3)
	# Far layer: dark silhouettes, barely moving.
	var off_far: int = int(far_phase * 108.0)
	var bx := -108
	while bx < 1080:
		var seed: int = absi(bx + off_far)
		var bh := 26 + (seed * 37) % 70
		var bw := 40 + (seed * 13) % 34
		draw_rect(Rect2(bx - off_far, hz - bh, bw, bh),
			Color(sky_tint.r * 0.35, sky_tint.g * 0.35, sky_tint.b * 0.45, 0.9))
		bx += 58
	# Mid layer: taller towers with a few lit windows + rim-lit tops.
	var off_mid: int = int(far_phase * 220.0)
	bx = -90
	while bx < 1080:
		var seed2: int = absi(bx * 3 + off_mid)
		var bh2 := 60 + (seed2 * 29) % 150
		var bw2 := 54 + (seed2 * 17) % 40
		var rx: float = float(bx) - float(off_mid % 64)
		draw_rect(Rect2(rx, hz - bh2, bw2, bh2), Color(0.05, 0.05, 0.11, 1.0))
		# rim-lit roofline
		draw_line(Vector2(rx, hz - bh2), Vector2(rx + bw2, hz - bh2),
			Color(rim_tint.r, rim_tint.g, rim_tint.b, 0.5), 2.0)
		# scattered lit windows
		for wi in range(3):
			if (seed2 + wi * 7) % 3 == 0:
				var wx: float = rx + 8 + wi * (bw2 / 3.0)
				draw_rect(Rect2(wx, hz - bh2 + 12 + (wi * 13) % (bh2 - 16), 6, 8),
					Color(rim_tint.r, rim_tint.g, rim_tint.b, 0.6))
		bx += 78

	# --- ground plane (zone-aware color) ---
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, 1920.0), Vector2(1080.0, 1920.0), vanish
	]), _pal_color(2))

	# --- side buildings (far -> near so nearer ones overlap) ---
	var ordered := builds.duplicate()
	ordered.sort_custom(func(a, b): return a.wy < b.wy)
	for b in ordered:
		_draw_building(b)

	# --- asphalt strip just inside the curbs (a touch lighter than ground) ---
	_draw_road_fill(vanish)

	# --- scrolling wet-asphalt texture (flecks + sheen) for ground depth ---
	_draw_road_texture()

	# --- wet-road neon reflections (subtle smears below the buildings) ---
	_draw_wet_reflections(ordered)

	# --- lane channel tints so WHICH lane is obvious ---
	var chans := [
		[Perspective.TRACK_LEFT, Perspective.DIV_LEFT],
		[Perspective.DIV_LEFT, Perspective.DIV_RIGHT],
		[Perspective.DIV_RIGHT, Perspective.TRACK_RIGHT],
	]
	for ci in range(chans.size()):
		var tint := Color(0.20, 0.10, 0.32, 0.20) if ci == 1 else Color(0.10, 0.20, 0.32, 0.13)
		draw_colored_polygon(PackedVector2Array([
			Vector2(chans[ci][0], 1920.0), Vector2(chans[ci][1], 1920.0), vanish
		]), tint)

	# --- grid rungs (scrolling transverse lines, zone-aware color) ---
	var grid_col: Color = _pal_color(3)
	for i in range(RUNG_COUNT):
		var p: float = fmod(phase + float(i) / float(RUNG_COUNT), 1.0)
		if p <= 0.015:
			continue
		var y: float = Perspective.screen_y(p)
		var lx: float = Perspective.converge_x(Perspective.TRACK_LEFT, p)
		var rx: float = Perspective.converge_x(Perspective.TRACK_RIGHT, p)
		var a: float = clampf(0.16 + 0.55 * p, 0.0, 0.8)
		draw_line(Vector2(lx, y), Vector2(rx, y), Color(grid_col.r, grid_col.g, grid_col.b, a), 1.0 + 6.0 * p)

	# --- bright curbs at the outer track edges (zone-aware color) ---
	var curb_col: Color = _pal_color(4)
	for ex in [Perspective.TRACK_LEFT, Perspective.TRACK_RIGHT]:
		draw_line(vanish, Vector2(ex, 1920.0), Color(curb_col.r, curb_col.g, curb_col.b, 0.85), 4.0)
	# --- dashed lane dividers (scrolling) ---
	for ex in [Perspective.DIV_LEFT, Perspective.DIV_RIGHT]:
		_draw_lane_dashes(ex)

	# --- "jump-ready" timing line near the player ---
	var jp := 0.82
	var jy: float = Perspective.screen_y(jp)
	var jl: float = Perspective.converge_x(Perspective.TRACK_LEFT, jp)
	var jr: float = Perspective.converge_x(Perspective.TRACK_RIGHT, jp)
	draw_line(Vector2(jl, jy), Vector2(jr, jy), Color(1.0, 0.86, 0.24, 0.55), 4.0)

# Faint vertical neon smears on the wet asphalt, mirroring each building's hue
# down toward the camera. Kept very low alpha so it reads as a sheen, not paint.
func _draw_wet_reflections(ordered: Array) -> void:
	for b in ordered:
		var p: float = Perspective.progress(b.wy)
		if p <= 0.05 or p >= 1.05:
			continue
		var sc: float = Perspective.depth_scale(p)
		var sy: float = Perspective.screen_y(p)
		var edge: float = Perspective.TRACK_LEFT if b.side < 0 else Perspective.TRACK_RIGHT
		var inner_x: float = Perspective.converge_x(edge, p)
		var fade: float = clampf(p * 1.3, 0.05, 0.7)
		var refl_len: float = 150.0 * sc
		var w: float = 34.0 * sc
		# tapering smear pointing toward the camera (downward on screen)
		var hue: Color = b.hue
		draw_colored_polygon(PackedVector2Array([
			Vector2(inner_x - w, sy), Vector2(inner_x + w, sy),
			Vector2(inner_x, sy + refl_len),
		]), Color(hue.r, hue.g, hue.b, 0.10 * fade))
		# brighter thin core
		draw_line(Vector2(inner_x, sy), Vector2(inner_x, sy + refl_len * 0.8),
			Color(hue.r, hue.g, hue.b, 0.16 * fade), maxf(1.0, 3.0 * sc))

# Scrolling reflective flecks + sheen streaks on the asphalt. Sells texture,
# wetness and speed so the ground doesn't read as a flat painted triangle.
func _draw_road_texture() -> void:
	var rim: Color = _pal_color(3)
	var curb: Color = _pal_color(4)
	# Scrolling transverse asphalt panels — alternating tone bands give the road
	# a tiled, physical surface instead of a flat gradient.
	for i in range(RUNG_COUNT):
		var pp: float = fmod(phase + float(i) / float(RUNG_COUNT), 1.0)
		if pp <= 0.02:
			continue
		if i % 2 == 0:
			var y0: float = Perspective.screen_y(pp)
			var pp2: float = clampf(pp + 1.0 / float(RUNG_COUNT), 0.0, 1.0)
			var y1: float = Perspective.screen_y(pp2)
			var lx0: float = Perspective.converge_x(Perspective.TRACK_LEFT, pp)
			var rx0: float = Perspective.converge_x(Perspective.TRACK_RIGHT, pp)
			var lx1: float = Perspective.converge_x(Perspective.TRACK_LEFT, pp2)
			var rx1: float = Perspective.converge_x(Perspective.TRACK_RIGHT, pp2)
			draw_colored_polygon(PackedVector2Array([
				Vector2(lx0, y0), Vector2(rx0, y0), Vector2(rx1, y1), Vector2(lx1, y1)]),
				Color(curb.r, curb.g, curb.b, 0.05))
	# Reflective wet flecks scattered across the surface.
	for f in flecks:
		var p: float = fmod(f.poff + phase * 2.3, 1.0)
		if p <= 0.06 or p >= 1.0:
			continue
		var base_x: float = 540.0 + f.xf * 360.0
		var sx: float = Perspective.converge_x(base_x, p)
		var sy: float = Perspective.screen_y(p)
		var sc: float = Perspective.depth_scale(p)
		var a: float = clampf(p * 0.7, 0.06, 0.55)
		var r: float = maxf(1.0, 3.0 * sc * f.sz)
		draw_circle(Vector2(sx, sy), r, Color(rim.r, rim.g, rim.b, a))
		draw_line(Vector2(sx, sy), Vector2(sx, sy + 22.0 * sc * f.sz),
			Color(rim.r, rim.g, rim.b, a * 0.5), maxf(1.0, 1.6 * sc))

func _draw_road_fill(vanish: Vector2) -> void:
	var road_col: Color = _pal_color(2)
	# Slightly lighter than the ground plane — add a touch of brightness
	var fill_col := Color(road_col.r + 0.02, road_col.g + 0.015, road_col.b + 0.03, 1.0)
	var lb := Vector2(Perspective.TRACK_LEFT, 1920.0)
	var rb := Vector2(Perspective.TRACK_RIGHT, 1920.0)
	draw_colored_polygon(PackedVector2Array([lb, rb, vanish]), fill_col)

func _draw_lane_dashes(edge_x: float) -> void:
	# Dashes marching toward the camera along a lane divider.
	for i in range(RUNG_COUNT):
		var p: float = fmod(phase * 1.0 + float(i) / float(RUNG_COUNT), 1.0)
		if p <= 0.04:
			continue
		var p2: float = clampf(p + 0.022, 0.0, 1.0)
		var y0: float = Perspective.screen_y(p)
		var y1: float = Perspective.screen_y(p2)
		var x0: float = Perspective.converge_x(edge_x, p)
		var x1: float = Perspective.converge_x(edge_x, p2)
		var a: float = clampf(0.12 + 0.5 * p, 0.0, 0.7)
		draw_line(Vector2(x0, y0), Vector2(x1, y1), Color(1.0, 1.0, 1.0, a), 1.0 + 5.0 * p)

# Dispatch to zone-specific building style based on current zone.
func _draw_building(b: Dictionary) -> void:
	var p: float = Perspective.progress(b.wy)
	if p <= 0.0 or p >= 1.05:
		return
	var sc: float = Perspective.depth_scale(p)
	var sy: float = Perspective.screen_y(p)
	var edge: float = Perspective.TRACK_LEFT if b.side < 0 else Perspective.TRACK_RIGHT
	var inner_x: float = Perspective.converge_x(edge, p)
	var bw: float = b.w * sc
	var bh: float = b.h * sc
	var fade: float = clampf(p * 1.6, 0.15, 1.0)
	var x_out: float = inner_x - bw if b.side < 0 else inner_x + bw
	var left_x: float = minf(inner_x, x_out)
	var facade := Rect2(left_x, sy - bh, bw, bh)

	match _current_zone:
		2: _draw_tunnel_arch(b, facade, sc, fade, sy)
		3: _draw_sewer_wall(b, facade, sc, fade)
		4: _draw_arcology_panel(b, facade, sc, fade)
		5: _draw_rooftop_silhouette(b, facade, sc, fade, sy)
		_: _draw_city_storefront(b, facade, sc, fade)

func _draw_city_storefront(b: Dictionary, facade: Rect2, sc: float, fade: float) -> void:
	draw_rect(facade, Color(0.06, 0.05, 0.11, 1.0))
	draw_rect(facade, Color(b.hue.r, b.hue.g, b.hue.b, 0.06 * fade))
	draw_rect(facade, Color(b.hue.r, b.hue.g, b.hue.b, 0.85 * fade), false, maxf(1.0, 3.0 * sc))
	var cols := 3
	var rows := int(clampf(b.h / 240.0, 2.0, 4.0))
	var mx: float = facade.size.x * 0.16
	var my: float = facade.size.y * 0.12
	var cw: float = (facade.size.x - mx * (cols + 1)) / cols
	var ch: float = (facade.size.y - my * (rows + 1)) / rows
	for r in range(rows):
		for cc in range(cols):
			var wx: float = facade.position.x + mx + cc * (cw + mx)
			var wy_: float = facade.position.y + my + r * (ch + my)
			var lit: bool = ((int(b.wy / 50.0) + r * 3 + cc * 7) % 5) != 0
			draw_rect(Rect2(wx, wy_, cw, ch),
				Color(b.hue.r, b.hue.g, b.hue.b, (0.5 if lit else 0.12) * fade))
	_draw_sign(b, facade, sc, fade)

# Zone 2 — Transit Underground: concrete tunnel arch with amber overhead lights
func _draw_tunnel_arch(b: Dictionary, facade: Rect2, sc: float, fade: float, sy: float) -> void:
	draw_rect(facade, Color(0.09, 0.08, 0.07, 1.0))
	draw_rect(facade, Color(b.hue.r, b.hue.g, b.hue.b, 0.05 * fade))
	draw_rect(facade, Color(b.hue.r, b.hue.g, b.hue.b, 0.6 * fade), false, maxf(1.0, 2.5 * sc))
	# Support pillars
	var pillar_w: float = facade.size.x * 0.11
	for i in range(3):
		var px: float = facade.position.x + facade.size.x * (float(i) + 0.5) / 3.0 - pillar_w * 0.5
		var pr := Rect2(px, facade.position.y, pillar_w, facade.size.y)
		draw_rect(pr, Color(0.12, 0.10, 0.08, 0.9))
		draw_rect(pr, Color(b.hue.r, b.hue.g, b.hue.b, 0.55 * fade), false, maxf(1.0, 2.0 * sc))
	# Amber overhead light strip
	var strip_h: float = facade.size.y * 0.07
	draw_rect(Rect2(facade.position.x, facade.position.y, facade.size.x, strip_h),
		Color(1.0, 0.75, 0.2, 0.75 * fade))
	draw_rect(Rect2(facade.position.x, facade.position.y + strip_h, facade.size.x, strip_h * 2.5),
		Color(1.0, 0.55, 0.0, 0.14 * fade))

# Zone 3 — Sewer Network: mossy brick walls with dripping green pipes
func _draw_sewer_wall(b: Dictionary, facade: Rect2, sc: float, fade: float) -> void:
	draw_rect(facade, Color(0.04, 0.07, 0.04, 1.0))
	draw_rect(facade, Color(b.hue.r, b.hue.g, b.hue.b, 0.04 * fade))
	draw_rect(facade, Color(b.hue.r, b.hue.g, b.hue.b, 0.5 * fade), false, maxf(1.0, 2.0 * sc))
	# Brick lines
	var rows: int = int(clampf(facade.size.y / (22.0 * sc), 3.0, 8.0))
	for r in range(rows):
		var ry: float = facade.position.y + facade.size.y * float(r) / float(rows)
		draw_line(Vector2(facade.position.x, ry), Vector2(facade.position.x + facade.size.x, ry),
			Color(0.1, 0.18, 0.1, 0.5 * fade), maxf(1.0, sc))
	# Dripping pipe
	var pw: float = maxf(8.0, 14.0 * sc)
	var pipe_x: float = facade.position.x + facade.size.x * 0.3
	draw_rect(Rect2(pipe_x, facade.position.y, pw, facade.size.y), Color(0.10, 0.14, 0.08, 0.85))
	draw_rect(Rect2(pipe_x, facade.position.y, pw, facade.size.y),
		Color(b.hue.r, b.hue.g, b.hue.b, 0.45 * fade), false, maxf(1.0, sc))
	# Animated drip (uses wy as clock so each building drips at its own rate)
	var drip_t: float = fmod(b.wy / 90.0, 1.0)
	var dy: float = facade.position.y + facade.size.y * drip_t
	draw_circle(Vector2(pipe_x + pw * 0.5, dy), maxf(3.0, 4.0 * sc),
		Color(b.hue.r, b.hue.g, b.hue.b, 0.7 * fade))

# Zone 4 — Corporate Arcology: sleek glass curtain-wall panels, lit offices
func _draw_arcology_panel(b: Dictionary, facade: Rect2, sc: float, fade: float) -> void:
	draw_rect(facade, Color(0.04, 0.08, 0.20, 0.95))
	draw_rect(facade, Color(b.hue.r, b.hue.g, b.hue.b, 0.06 * fade))
	draw_rect(facade, Color(b.hue.r, b.hue.g, b.hue.b, 0.75 * fade), false, maxf(1.0, 2.0 * sc))
	var cols := 4
	var rows: int = int(clampf(facade.size.y / (18.0 * sc), 3.0, 6.0))
	var wx: float = facade.size.x / float(cols)
	var wh: float = facade.size.y / float(rows)
	for r in range(rows):
		for cc in range(cols):
			var lit: bool = ((int(b.wy / 40.0) + r + cc) % 3) != 2
			var wl: float = facade.position.x + cc * wx + wx * 0.12
			var wt: float = facade.position.y + r * wh + wh * 0.15
			draw_rect(Rect2(wl, wt, wx * 0.76, wh * 0.7),
				Color(b.hue.r, b.hue.g, b.hue.b, (0.55 if lit else 0.08) * fade))
	# Corporate stripe near top
	var bar_h: float = facade.size.y * 0.04
	draw_rect(Rect2(facade.position.x + facade.size.x*0.1, facade.position.y,
		facade.size.x * 0.8, bar_h), Color(b.hue.r, b.hue.g, b.hue.b, 0.7 * fade))

# Zone 5 — Rooftop Chase: open air, just parapet walls + antennas + water tanks
func _draw_rooftop_silhouette(b: Dictionary, facade: Rect2, sc: float, fade: float, sy: float) -> void:
	var parapet_h: float = facade.size.y * 0.24
	var parapet := Rect2(facade.position.x, sy - parapet_h, facade.size.x, parapet_h)
	draw_rect(parapet, Color(0.10, 0.08, 0.18, 0.92))
	draw_rect(parapet, Color(b.hue.r, b.hue.g, b.hue.b, 0.65 * fade), false, maxf(1.0, 2.0 * sc))
	# Antennas
	var num_ant: int = 2 + (int(b.wy / 300.0) % 2)
	for i in range(num_ant):
		var ax: float = facade.position.x + facade.size.x * (float(i) + 0.5) / float(num_ant)
		var ah: float = facade.size.y * (0.35 + float(i) * 0.15)
		draw_line(Vector2(ax, sy - parapet_h), Vector2(ax, sy - parapet_h - ah),
			Color(b.hue.r, b.hue.g, b.hue.b, 0.75 * fade), maxf(2.0, 3.0 * sc))
		var blink: float = 0.5 + 0.5 * sin(b.wy * 0.08 + float(i) * 1.7)
		draw_circle(Vector2(ax, sy - parapet_h - ah),
			maxf(3.0, 5.0 * sc), Color(1.0, 0.15, 0.15, blink * fade))
	# Water tank (every other building)
	if int(b.wy / 280.0) % 2 == 0:
		var tw: float = facade.size.x * 0.28
		var th: float = facade.size.y * 0.32
		var tx: float = facade.position.x + facade.size.x * 0.58
		draw_rect(Rect2(tx - tw*0.5, sy - parapet_h - th, tw, th),
			Color(0.14, 0.11, 0.22, 0.88))
		draw_rect(Rect2(tx - tw*0.5, sy - parapet_h - th, tw, th),
			Color(b.hue.r, b.hue.g, b.hue.b, 0.5 * fade), false, maxf(1.0, 2.0 * sc))

func _draw_sign(b: Dictionary, facade: Rect2, sc: float, fade: float) -> void:
	if b.sign == 0:
		# Neon Possum logo sign across the storefront top.
		var lw: float = facade.size.x * 0.9
		var lh: float = lw * (float(LOGO.get_height()) / float(LOGO.get_width()))
		lh = minf(lh, facade.size.y * 0.42)
		lw = lh * (float(LOGO.get_width()) / float(LOGO.get_height()))
		var lx: float = facade.position.x + (facade.size.x - lw) * 0.5
		var ly: float = facade.position.y + facade.size.y * 0.10
		# glow backing
		draw_rect(Rect2(lx - 6, ly - 6, lw + 12, lh + 12), Color(0, 0.9, 1.0, 0.10 * fade))
		draw_texture_rect(LOGO, Rect2(lx, ly, lw, lh), false, Color(1, 1, 1, fade))
	else:
		# Abstract neon sign bar (glowing rounded panel).
		var sw: float = facade.size.x * 0.66
		var sh: float = facade.size.y * 0.18
		var sx: float = facade.position.x + (facade.size.x - sw) * 0.5
		var syy: float = facade.position.y + facade.size.y * 0.12
		var panel := Rect2(sx, syy, sw, sh)
		draw_rect(panel, Color(b.hue.r, b.hue.g, b.hue.b, 0.18 * fade))
		draw_rect(panel, Color(b.hue.r, b.hue.g, b.hue.b, 0.95 * fade), false, maxf(1.0, 3.0 * sc))
		# a couple of "text" strokes
		var ty: float = panel.position.y + panel.size.y * 0.5
		var pad: float = panel.size.x * 0.14
		draw_line(Vector2(panel.position.x + pad, ty),
			Vector2(panel.position.x + panel.size.x - pad, ty),
			Color(1, 1, 1, 0.85 * fade), maxf(1.0, 4.0 * sc))
