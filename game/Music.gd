# game/Music.gd — Autoload "Music". Background track: loops one track, cycles on demand, and
# ducks (pauses) around a one-shot jingle so the win/lose/draw sting is heard clean, then resumes.
# ─────────────────────────────────────────────────────────────────────────────
# Non-positional (both ears) — it's a soundtrack, not a world sound. One AudioStreamPlayer; the
# track list is the whole config. The game opens on retro-gaming (index 0).
extends Node

# Cycle order; retro-gaming first so the game starts on it (per spec). name = HUD popup caption.
const TRACKS := [
	{"path": "res://music/retro-gaming.mp3", "name": "Retro Gaming"},
	{"path": "res://music/upbeat-gaming.mp3", "name": "Upbeat Gaming"},
	{"path": "res://music/gaming-rock.mp3", "name": "Gaming Rock"},
	{"path": "res://music/cyberpunk-edm.mp3", "name": "Cyberpunk EDM"},
	{"path": "res://music/jazz-sunny-cafe.mp3", "name": "Jazz Sunny Cafe"},
	{"path": "res://music/champion.mp3", "name": "Champion"},
]

var _i := 0
var _player: AudioStreamPlayer
# Two independent reasons to be silent: the player pressed pause, or a jingle is ducking us.
# Kept apart so a jingle's resume() can't undo a manual pause (and vice-versa).
var _user_paused := false
var _ducked := false
var _creepy := false  # true only while the 鬼/HARD creepy override is the live track
var _kickstarted := false  # re-played the opening track once the app actually had audio focus


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	# ponytail: sit the music under the jingles; tune in-headset if it's too loud/quiet.
	_player.volume_db = -8.0
	add_child(_player)
	_play_current()


# Autoloads init before the headset grants the app audio focus, so the _ready() play() above is
# sometimes silent (the soundtrack "didn't start"). Re-issue it the first time we actually gain
# focus. Once only — later focus regains (headset off/on) auto-resume, so don't restart the track.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and not _kickstarted:
		_kickstarted = true
		if _player and not _user_paused:
			_player.play()


func _play_current() -> void:
	_creepy = false
	var stream: AudioStream = load(TRACKS[_i].path)
	if stream == null:  # not-yet-imported file just means silence, never a crash
		return
	if stream is AudioStreamMP3:
		stream.loop = true  # loop until the track is changed
	_player.stream = stream
	_player.play()
	_apply_pause()


func _apply_pause() -> void:
	if _player:
		_player.stream_paused = _user_paused or _ducked


# Advance to the next track and return its display name (the HUD shows it for ~2 s). Skipping
# resumes playback — pressing skip means "play this next one".
func next_track() -> String:
	_i = (_i + 1) % TRACKS.size()
	_user_paused = false
	_play_current()
	return TRACKS[_i].name


# Play/pause toggle (the HUD's play/pause half). Returns true if now playing.
func toggle_play() -> bool:
	_user_paused = not _user_paused
	_apply_pause()
	return not _user_paused


func is_playing() -> bool:
	return not _user_paused


# Swap the soundtrack to a fixed track outside the cycle (looping). reset_track() puts the
# cycled track back; skip/next also escapes it. Shared by victory/evil_laugh/play_creepy.
func _play_override(path: String) -> void:
	_creepy = false  # play_creepy() re-sets this after; victory/evil_laugh leave it off
	var stream: AudioStream = load(path)
	if stream == null:  # not-yet-imported file just means silence, never a crash
		return
	if stream is AudioStreamMP3:
		stream.loop = true
	_user_paused = false
	_player.stream = stream
	_player.play()
	_apply_pause()


# Win celebration: the victory anthem. PlayZone calls victory() on a game-over win,
# evil_laugh() on a game-over loss (robot reached 3), and reset_track() on Restart.
func victory() -> void:
	_play_override("res://music/Victory.mp3")


# Robot took the match — cackle until Restart.
func evil_laugh() -> void:
	_play_override("res://music/evil-laughing.mp3")


# Force the creepy track when 鬼/HARD is picked; the player can skip back to the cycle.
# Returns the HUD caption (like next_track()).
func play_creepy() -> String:
	_play_override("res://music/creepy-song.mp3")
	_creepy = true
	return "Creepy Song"


# Leaving 鬼/HARD: restore the cycle track, but only if creepy is still the live track (a skip
# back to the cycle, or a win/lose anthem, should be left alone).
func reset_if_creepy() -> void:
	if _creepy:
		reset_track()


# Back to the currently-selected cycle track (turns off the victory anthem on Restart).
func reset_track() -> void:
	_user_paused = false
	_play_current()


# Pause/resume around a one-shot jingle (PlayZone calls these on stinger play/finish).
func duck() -> void:
	_ducked = true
	_apply_pause()


func resume() -> void:
	_ducked = false
	_apply_pause()
