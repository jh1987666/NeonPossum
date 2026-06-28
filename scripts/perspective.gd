extends RefCounted

# Loaded via `const Perspective = preload(...)` in the scripts that use it, so it
# doesn't depend on Godot's global class-name cache being built first.

# ---------------------------------------------------------------------------
# Pseudo-3D projection for the endless runner.
#
# Gameplay still happens in flat "world" coordinates (a thing's position.y goes
# from SPAWN_WY at the top to PLAYER_WY at the player, exactly like before, so
# all the existing collision/spawn code is unchanged). This helper only maps a
# world point onto the screen so it LOOKS like a track receding to a horizon:
# things emerge tiny at the vanishing point, fan out to their lane, and grow as
# they rush the camera.
#
# Tune these constants to taste — they only affect visuals, never gameplay.
# ---------------------------------------------------------------------------

const VANISH_X: float   = 540.0     # horizon / vanishing point X (screen center)
const HORIZON_Y: float  = 620.0     # screen Y of the horizon (far)
const NEAR_Y: float     = 1500.0    # screen Y at the player plane (near)

const SPAWN_WY: float   = -100.0    # world Y where things spawn (far)
const PLAYER_WY: float  = 1500.0    # world Y of the player / collision plane (near)

const FAR_SCALE: float  = 0.12      # size multiplier at the horizon
const NEAR_SCALE: float = 1.0       # size multiplier at the player
const MAX_SCALE: float  = 1.5       # cap when something blows past the camera

const Y_POW: float = 1.5            # approach easing — lower = steadier, more readable timing
const S_POW: float = 1.6            # scale easing
const X_POW: float = 1.2            # lane fan-out easing — lower = lanes separate sooner

# Outer track edges + lane dividers at the NEAR plane (screen X).
const TRACK_LEFT: float  = 135.0
const TRACK_RIGHT: float = 945.0
const DIV_LEFT: float    = 405.0
const DIV_RIGHT: float   = 675.0


# 0.0 at spawn (far), 1.0 at the player plane (near), >1 past the camera.
static func progress(world_y: float) -> float:
	return (world_y - SPAWN_WY) / (PLAYER_WY - SPAWN_WY)

static func screen_y(p: float) -> float:
	return HORIZON_Y + (NEAR_Y - HORIZON_Y) * pow(max(p, 0.0), Y_POW)

static func depth_scale(p: float) -> float:
	var s: float = FAR_SCALE + (NEAR_SCALE - FAR_SCALE) * pow(max(p, 0.0), S_POW)
	return clampf(s, FAR_SCALE, MAX_SCALE)

# Fan a lane's near-plane X out from the vanishing point as it approaches.
static func converge_x(lane_x: float, p: float) -> float:
	var t: float = pow(clampf(p, 0.0, 1.0), X_POW)
	return lerpf(VANISH_X, lane_x, t)

# Convenience: full screen position for a world point on a given lane X.
static func project(lane_x: float, world_y: float) -> Vector2:
	var p: float = progress(world_y)
	return Vector2(converge_x(lane_x, p), screen_y(p))
