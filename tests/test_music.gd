# tests/test_music.gd — headless assert suite for the Music autoload's victory/restart behavior.
# ─────────────────────────────────────────────────────────────────────────────
# Covers what happens to the soundtrack on a game-over win (PlayZone → Music.victory()) and on
# Restart (PlayZone → Music.reset_track()). The rest of the win/restart flow (banner, fireworks,
# no auto-restart) is VR-scene/Sprite3D and is exercised in-headset, not here.
#
# RUN (desktop, no VR):
#   godot --headless --path . --script res://tests/test_music.gd ; echo "exit=$?"
# Exit code 0 = all pass, 1 = ≥1 failure (CI-friendly).
#
# Like the GameState suite, --script SceneTree mode does NOT load Autoloads, so we instantiate
# Music.gd directly and call _ready() ourselves (the main loop hasn't started, so the engine
# hasn't called it). _initialize runs before the tree is live, so the AudioStreamPlayer never
# actually plays here — that's fine: we assert on the LOGICAL state (_user_paused, _ducked, which
# stream is loaded, the cycle index), never on real playback. Run with --audio-driver Dummy so
# the macOS CoreAudio backend doesn't hang the process on exit.
extends SceneTree

const MUSIC_SCRIPT := preload("res://game/Music.gd")
const VICTORY := "res://music/Victory.mp3"
const CREEPY := "res://music/creepy-song.mp3"
const EVIL := "res://music/evil-laughing.mp3"

var _passes := 0
var _failures: Array[String] = []


func _initialize() -> void:
	var music = MUSIC_SCRIPT.new()
	root.add_child(music)
	music._ready()  # _initialize is pre-main-loop, so _ready isn't auto-called yet

	_m1_opens_on_cycle_track(music)
	_m2_victory_swaps_and_plays(music)
	_m3_victory_overrides_a_user_pause(music)
	_m4_stinger_ducks_then_resumes_the_anthem(music)
	_m5_reset_returns_to_the_selected_track(music)
	_m6_reset_overrides_a_user_pause(music)
	_m7_forced_tracks_swap_outside_the_cycle(music)

	music.free()

	# ── Report ──
	print("\n──────── Music test suite ────────")
	print("  passed: %d   failed: %d" % [_passes, _failures.size()])
	for f in _failures:
		print("  ✗ ", f)
	if _failures.is_empty():
		print("  ✓ ALL GREEN — victory + restart\n")
	quit(0 if _failures.is_empty() else 1)


# ── helpers ──────────────────────────────────────────────────────────────────
func _check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures.append(msg)


func _path(music) -> String:
	return music._player.stream.resource_path if music._player.stream else ""


# ── M1 — opens on the first cycle track, not paused ──────────────────────────
func _m1_opens_on_cycle_track(music) -> void:
	_check(
		_path(music) == music.TRACKS[0].path, "M1: should open on track 0, got %s" % _path(music)
	)
	_check(not music._user_paused and not music._ducked, "M1: opening track should be playing")


# ── M2 — a win swaps to the victory anthem without touching the cycle index ──
func _m2_victory_swaps_and_plays(music) -> void:
	var before_i = music._i
	music.victory()
	_check(_path(music) == VICTORY, "M2: victory() should load the anthem, got %s" % _path(music))
	_check(not music._user_paused, "M2: victory anthem should be playing, not paused")
	_check(music._i == before_i, "M2: victory() must not advance the cycle index")
	music.reset_track()  # restore for the next case


# ── M3 — winning is heard even if the player had paused the music ────────────
func _m3_victory_overrides_a_user_pause(music) -> void:
	if music.is_playing():
		music.toggle_play()  # force a user pause
	_check(not music.is_playing(), "M3: precondition — music should be user-paused")
	music.victory()
	_check(not music._user_paused, "M3: victory() should clear a user pause")
	music.reset_track()


# ── M4 — the win stinger ducks the anthem, then resumes it (not the cycle track) ─
func _m4_stinger_ducks_then_resumes_the_anthem(music) -> void:
	music.victory()
	music.duck()  # PlayZone ducks while the win.wav jingle plays
	_check(music._ducked, "M4: anthem should be ducked while the stinger plays")
	_check(_path(music) == VICTORY, "M4: ducking must not change the stream")
	music.resume()  # _sfx.finished
	_check(not music._ducked, "M4: anthem should un-duck after the stinger")
	_check(_path(music) == VICTORY, "M4: resume must keep the anthem, not the cycle track")
	music.reset_track()


# ── M5 — Restart turns off the anthem and returns to the player's selected track ─
func _m5_reset_returns_to_the_selected_track(music) -> void:
	music.next_track()  # player had picked a non-default track (index 1)
	var selected = music.TRACKS[music._i].path
	music.victory()
	_check(_path(music) == VICTORY, "M5: precondition — anthem playing")
	music.reset_track()
	_check(
		_path(music) == selected,
		"M5: reset should return to the selected track, got %s" % _path(music)
	)
	_check(not music._user_paused, "M5: the restored track should be playing")


# ── M6 — Restart resumes the music even if it was paused at game over ────────
func _m6_reset_overrides_a_user_pause(music) -> void:
	if music.is_playing():
		music.toggle_play()
	music.reset_track()
	_check(not music._user_paused, "M6: reset_track() should clear a user pause")


# ── M7 — 鬼 creepy track and the robot's evil laugh swap outside the cycle, then reset ─
func _m7_forced_tracks_swap_outside_the_cycle(music) -> void:
	var before_i = music._i
	_check(music.play_creepy() == "Creepy Song", "M7: play_creepy() should return the HUD caption")
	_check(
		_path(music) == CREEPY,
		"M7: play_creepy() should load the creepy track, got %s" % _path(music)
	)
	_check(music._i == before_i, "M7: forced tracks must not advance the cycle index")
	music.evil_laugh()
	_check(_path(music) == EVIL, "M7: evil_laugh() should load the laugh, got %s" % _path(music))
	_check(not music._user_paused, "M7: a forced track should be playing, not paused")
	music.reset_track()
	_check(
		_path(music) == music.TRACKS[before_i].path, "M7: reset should return to the cycle track"
	)
	# Leaving 鬼: reset_if_creepy() restores the cycle while creepy plays, but leaves a non-creepy
	# track (a skip-away, or a win/lose anthem) alone.
	music.play_creepy()
	music.reset_if_creepy()
	_check(_path(music) != CREEPY, "M7: reset_if_creepy() should drop the creepy track")
	music.victory()
	music.reset_if_creepy()
	_check(_path(music) == VICTORY, "M7: reset_if_creepy() must not clobber a non-creepy track")
