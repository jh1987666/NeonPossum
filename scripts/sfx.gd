extends Node

# Global audio. Registered as the "Sfx" autoload, so any script can call
# Sfx.play("jump"), Sfx.start_music(), etc.

const SOUNDS := {
	"jump":    "res://assets/audio/jump.ogg",
	"slide":   "res://assets/audio/slide.ogg",
	"gem":     "res://assets/audio/gem.ogg",
	"powerup": "res://assets/audio/powerup.ogg",
	"hit":     "res://assets/audio/hit.ogg",
}

var _players: Dictionary = {}
var _music: AudioStreamPlayer
var muted: bool = false

func _ready() -> void:
	for key in SOUNDS:
		var p := AudioStreamPlayer.new()
		p.stream = load(SOUNDS[key])
		p.volume_db = -4.0
		add_child(p)
		_players[key] = p
	_music = AudioStreamPlayer.new()
	_music.stream = load("res://assets/audio/music.ogg")
	_music.volume_db = -12.0
	add_child(_music)
	# loop the bed by replaying when it finishes (clean seam baked into the wav)
	_music.finished.connect(func():
		if _music.stream:
			_music.play())

func play(name: String) -> void:
	if muted:
		return
	if _players.has(name):
		_players[name].play()

func start_music() -> void:
	if muted:
		return
	if _music and not _music.playing:
		_music.play()

func stop_music() -> void:
	if _music:
		_music.stop()

func set_muted(m: bool) -> void:
	muted = m
	if m:
		stop_music()
