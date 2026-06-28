extends Node

# Mission system — 3 rotating goals at a time, à la Subway Surfers / Minion Rush.
# This is the ad-free retention loop: complete a goal -> gem reward -> new goal.
# Active missions + progress persist in user://neonpossum_missions.json.

const SAVE_PATH := "user://neonpossum_missions.json"
const SLOTS := 3

signal mission_completed(text: String, reward: int)

# Template pool. {type, amount, reward, verb} — text is built from these.
const TEMPLATES := [
	{"type": "gems",     "amount": 30,   "reward": 25,  "verb": "Collect %d gems"},
	{"type": "gems",     "amount": 75,   "reward": 60,  "verb": "Collect %d gems"},
	{"type": "distance", "amount": 2600, "reward": 30,  "verb": "Run %d feet"},
	{"type": "distance", "amount": 6500, "reward": 80,  "verb": "Run %d feet"},
	{"type": "punch",    "amount": 10,   "reward": 30,  "verb": "Bowl over %d goblins"},
	{"type": "punch",    "amount": 25,   "reward": 70,  "verb": "Bowl over %d goblins"},
	{"type": "powerups", "amount": 4,    "reward": 35,  "verb": "Grab %d power-ups"},
	{"type": "combo",    "amount": 4,    "reward": 50,  "verb": "Hit a x%d combo"},
	{"type": "runs",      "amount": 3,   "reward": 20,  "verb": "Play %d runs"},
	{"type": "spring",    "amount": 5,   "reward": 25,  "verb": "Hit %d springboards"},
	{"type": "spring",    "amount": 15,  "reward": 55,  "verb": "Hit %d springboards"},
	{"type": "hoverbike", "amount": 3,   "reward": 30,  "verb": "Grab %d hover bikes"},
	{"type": "near_miss", "amount": 8,   "reward": 40,  "verb": "Get %d close calls"},
	{"type": "boss_hit",  "amount": 1,   "reward": 50,  "verb": "Damage a boss"},
	{"type": "boss_hit",  "amount": 5,   "reward": 100, "verb": "Damage a boss %d times"},
]

var active: Array = []   # each: {type, amount, reward, verb, progress, done}

func _ready() -> void:
	_load()
	if active.size() < SLOTS:
		_fill_slots()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_fill_slots()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		_fill_slots()
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) == TYPE_ARRAY:
		active = data
	if active.size() < SLOTS:
		_fill_slots()

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(active))

func _fill_slots() -> void:
	while active.size() < SLOTS:
		active.append(_roll(_active_types()))
	_save()

func _active_types() -> Array:
	var t: Array = []
	for m in active:
		t.append(m.type)
	return t

# Pick a template not already in the active set (avoid duplicates) and seed it.
func _roll(avoid: Array) -> Dictionary:
	var choices: Array = TEMPLATES.filter(func(t): return not avoid.has(t.type))
	if choices.is_empty():
		choices = TEMPLATES
	var t: Dictionary = choices[randi() % choices.size()]
	return {
		"type": t.type, "amount": t.amount, "reward": t.reward,
		"verb": t.verb, "progress": 0, "done": false,
	}

# Report progress for an event type; grants reward + rerolls on completion.
# Returns total gems awarded this call (so the caller can add to currency).
func report(type: String, amount: int) -> int:
	var awarded := 0
	for i in range(active.size()):
		var m: Dictionary = active[i]
		if m.done or m.type != type:
			continue
		m.progress = int(m.progress) + amount
		if m.progress >= m.amount:
			m.done = true
			awarded += int(m.reward)
			emit_signal("mission_completed", text_for(m), int(m.reward))
			active[i] = _roll(_active_types())  # replace completed slot
	if awarded > 0:
		_save()
	return awarded

# For "best" style goals (combo) report the peak rather than summing.
func report_max(type: String, value: int) -> int:
	var awarded := 0
	for i in range(active.size()):
		var m: Dictionary = active[i]
		if m.done or m.type != type:
			continue
		if value > int(m.progress):
			m.progress = value
		if m.progress >= m.amount:
			m.done = true
			awarded += int(m.reward)
			emit_signal("mission_completed", text_for(m), int(m.reward))
			active[i] = _roll(_active_types())
	if awarded > 0:
		_save()
	return awarded

func text_for(m: Dictionary) -> String:
	return (m.verb % m.amount)

# For the menu: ["Collect 30 gems  12/30  +25", ...]
func summaries() -> Array:
	var out: Array = []
	for m in active:
		out.append("%s   %d/%d   +%d" % [text_for(m), int(m.progress), int(m.amount), int(m.reward)])
	return out

func progress_save() -> void:
	_save()
