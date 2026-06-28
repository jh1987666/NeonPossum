extends Node

# Persistent player progress, stored as JSON in the user data dir
# (user://neonpossum_save.json — survives between runs and app restarts).

const SAVE_PATH := "user://neonpossum_save.json"

var high_score: int = 0
var best_distance: int = 0
var best_combo: int = 0
var total_gems: int = 0      # lifetime gems collected across all runs
var runs: int = 0
var last_claim_day: int = 0  # unix day index of last daily-reward claim
var daily_streak: int = 0
var sound_on: bool = true
var upgrades: Dictionary = {}   # powerup_id -> level (0..MAX_UP_LEVEL), bought in the shop

const MAX_UP_LEVEL: int = 5

func _ready() -> void:
	load_game()

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	high_score     = int(data.get("high_score", 0))
	best_distance  = int(data.get("best_distance", 0))
	best_combo     = int(data.get("best_combo", 0))
	total_gems     = int(data.get("total_gems", 0))
	runs           = int(data.get("runs", 0))
	last_claim_day = int(data.get("last_claim_day", 0))
	daily_streak   = int(data.get("daily_streak", 0))
	sound_on       = bool(data.get("sound_on", true))
	var up = data.get("upgrades", {})
	upgrades = up if typeof(up) == TYPE_DICTIONARY else {}

func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"high_score": high_score,
		"best_distance": best_distance,
		"best_combo": best_combo,
		"total_gems": total_gems,
		"runs": runs,
		"last_claim_day": last_claim_day,
		"daily_streak": daily_streak,
		"sound_on": sound_on,
		"upgrades": upgrades,
	}))

# Daily login reward. Returns {claimed, reward, streak}. Reward escalates with
# the streak (resets if a day was missed). Only pays out once per calendar day.
func try_daily_reward() -> Dictionary:
	var today: int = int(Time.get_unix_time_from_system() / 86400.0)
	if today == last_claim_day:
		return {"claimed": false, "reward": 0, "streak": daily_streak}
	if today == last_claim_day + 1:
		daily_streak += 1
	else:
		daily_streak = 1
	last_claim_day = today
	var reward: int = mini(25 + (daily_streak - 1) * 15, 150)
	total_gems += reward
	save_game()
	return {"claimed": true, "reward": reward, "streak": daily_streak}

# --- Shop upgrades -------------------------------------------------------
func get_upgrade(id: String) -> int:
	return int(upgrades.get(id, 0))

func upgrade_cost(id: String) -> int:
	return 60 * (get_upgrade(id) + 1)   # 60, 120, 180, 240, 300

# A powerup's duration scales 1.0 .. 2.0× across its 5 upgrade levels.
func upgrade_mult(id: String) -> float:
	return 1.0 + 0.2 * float(get_upgrade(id))

func try_buy_upgrade(id: String) -> bool:
	if get_upgrade(id) >= MAX_UP_LEVEL:
		return false
	var cost: int = upgrade_cost(id)
	if total_gems < cost:
		return false
	total_gems -= cost
	upgrades[id] = get_upgrade(id) + 1
	save_game()
	return true

# Add gems (e.g. mission rewards) to the lifetime/spendable tally.
func add_gems(n: int) -> void:
	total_gems += n
	save_game()

# Call at the end of a run. Returns true if this run set a new high score.
# NOTE: gems are banked live (in main.on_gem_collected) so they're spendable
# mid-run; we do NOT add them here or they'd be counted twice.
func record_run(score: int, distance: int, gems: int, run_combo: int = 0) -> bool:
	runs += 1
	best_distance = maxi(best_distance, distance)
	best_combo = maxi(best_combo, run_combo)
	var is_best: bool = score > high_score
	if is_best:
		high_score = score
	save_game()
	return is_best
