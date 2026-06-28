# game/Hud.gd — the 2D retro control panel, rendered into the world by a Viewport2Din3D and
# operated either by poking the buttons (finger touch) or the controllers' laser pointer.
# ─────────────────────────────────────────────────────────────────────────────
# Buttons (Restart / Rules+Story / Language) sit in a vertically-centred column on the right;
# the Rules and Story cards open to their left (sharing one slot — opening one hides the other,
# and the Story card auto-opens at startup and on Restart) so they never cover the buttons —
# tap the button again to close. Built in
# code so the .tscn stays a single node. Every label is a Lang.t() call and re-renders on
# Lang.changed, so the toggle re-languages the whole panel (and its own caption) in one place.
extends Control

const FONT := preload("res://art/fonts/DotGothic16-Regular.ttf")

# Retro palette: dark slab, bright border, no rounded corners.
const BG := Color(0.07, 0.06, 0.12)
const EDGE := Color(0.4, 0.95, 0.85)
const TEXT := Color(0.95, 0.97, 1.0)
const TITLE := Color(1.0, 0.85, 0.2)  # card-heading yellow

var _restart_btn: Button
var _diff_btns: Array[Button] = []  # Easy / Medium / Hard, in GameState.Difficulty order
var _rules_btn: Button
var _story_btn: Button
var _playpause_btn: Button
var _skip_btn: Button
var _lang_btn: Button
var _rules_panel: PanelContainer
var _rules_label: Label
var _rules_title: Label
var _story_panel: PanelContainer
var _story_label: Label
var _story_title: Label
var _track_label: Label  # transient "now playing" name, shown ~2 s on a Track press
var _track_timer: Timer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ── Button column: right edge, vertically centred, big well-spaced touch targets so a
	# fingertip poke (or the laser) lands easily. ────────────────────────────────────────
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	# 306 wide: three difficulty buttons across need ~95px each or their JP/EN labels
	# spill past the right edge. Measured headless against the 840×510 viewport (probe_hud.gd).
	col.offset_left = -330
	col.offset_right = -24
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 28)
	add_child(col)

	_restart_btn = _make_button(col)
	# Difficulty row: Easy / Medium / Hard. The active level shows the bright "pressed" slab.
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 10)
	col.add_child(diff_row)
	for level in [
		GameState.Difficulty.EASY, GameState.Difficulty.MEDIUM, GameState.Difficulty.HARD
	]:
		var b := _make_button(diff_row)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Three-across, so smaller font + tighter side margins to fit the long JP words.
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_stylebox_override("hover", _slab(EDGE, 4, 6))
		b.add_theme_stylebox_override("pressed", _slab(EDGE, 0, 6))
		b.add_theme_stylebox_override("focus", _slab(BG, 4, 6))
		b.pressed.connect(_on_difficulty.bind(level))
		_diff_btns.append(b)
	# Rules + Story share one row (like the music row) so the column keeps 5 rows and stays
	# inside the 510px-tall viewport — a 6th full-height row would clip top & bottom.
	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 10)
	col.add_child(info_row)
	_rules_btn = _make_button(info_row)
	_story_btn = _make_button(info_row)
	_rules_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_story_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Smaller font + tight side margins so the long JP labels (ストーリー) fit two-across.
	_rules_btn.add_theme_font_size_override("font_size", 20)
	_story_btn.add_theme_font_size_override("font_size", 20)
	# Music row: one button split in two — play/pause on the left, skip on the right.
	var music_row := HBoxContainer.new()
	music_row.add_theme_constant_override("separation", 10)
	col.add_child(music_row)
	_playpause_btn = _make_button(music_row)
	_skip_btn = _make_button(music_row)
	_playpause_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skip_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skip_btn.text = "▶▶"  # skip icon — not language-dependent
	_lang_btn = _make_button(col)

	_restart_btn.pressed.connect(_on_restart)
	_rules_btn.pressed.connect(_toggle_rules)
	_story_btn.pressed.connect(_toggle_story)
	_playpause_btn.pressed.connect(_on_playpause)
	_skip_btn.pressed.connect(_on_skip)
	_lang_btn.pressed.connect(Lang.toggle)

	# Transient "now playing" name — pops to the players-right of the buttons for ~2 s on a
	# Track press, then auto-hides. _flash_track() sits it level with the play/pause row.
	_track_label = _label(self, 22)
	_track_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_track_label.offset_left = -600
	_track_label.offset_right = -340  # just left of the button column (its left edge ~ -330)
	_track_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_track_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_track_label.add_theme_stylebox_override("normal", _slab(BG, 2))
	_track_label.visible = false

	_track_timer = Timer.new()
	_track_timer.one_shot = true
	_track_timer.timeout.connect(func(): _track_label.visible = false)
	add_child(_track_timer)

	# ── Rules card: fills the LEFT region, i.e. opens to the players-right of the button
	# column, leaving the Rules button uncovered so a second tap closes it. Hidden until asked.
	_rules_panel = PanelContainer.new()
	_rules_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_rules_panel.offset_left = 24
	_rules_panel.offset_top = 24
	_rules_panel.offset_bottom = -24
	_rules_panel.offset_right = 500  # stop short of the widened button column (left edge now ~510)
	_rules_panel.add_theme_stylebox_override("panel", _slab(BG, 4))
	_rules_panel.visible = false
	add_child(_rules_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_rules_panel.add_child(box)

	_rules_title = _label(box, 26)
	_rules_title.add_theme_color_override("font_color", TITLE)
	_rules_label = _label(box, 19)
	# Wrap long lines to the card width so nothing is clipped off-panel.
	_rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	# ── Story card: same slot/styling as the Rules card; only one of the two shows at a time.
	# Opens automatically at startup and on Restart to set the scene before the first deal.
	_story_panel = PanelContainer.new()
	_story_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_story_panel.offset_left = 24
	_story_panel.offset_top = 24
	_story_panel.offset_bottom = -24
	_story_panel.offset_right = 500
	_story_panel.add_theme_stylebox_override("panel", _slab(BG, 4))
	_story_panel.visible = false
	add_child(_story_panel)

	var story_box := VBoxContainer.new()
	story_box.add_theme_constant_override("separation", 16)
	story_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_story_panel.add_child(story_box)

	_story_title = _label(story_box, 26)
	_story_title.add_theme_color_override("font_color", TITLE)
	_story_label = _label(story_box, 19)
	_story_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_story_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	Lang.changed.connect(_retext)
	_retext()
	_update_playpause_icon()
	_set_story_visible(true)  # greet the player with the story before the first hand


# Re-render every caption in the current language. Called on ready and on toggle.
func _retext() -> void:
	_restart_btn.text = Lang.t("RESTART", "リスタート")
	var diff_text := [Lang.t("EASY", "やさしい"), Lang.t("NORMAL", "ふつう"), Lang.t("HARD", "鬼")]
	for i in _diff_btns.size():
		_diff_btns[i].text = diff_text[i]
	_update_difficulty_highlight()
	_rules_btn.text = Lang.t("RULES", "ルール")
	_story_btn.text = Lang.t("STORY", "ストーリー")
	# The toggle advertises the language it switches TO (per spec): 日本 in English, EN in Japanese.
	_lang_btn.text = "日本" if not Lang.jp else "EN"
	_rules_title.text = Lang.t("HOW TO PLAY", "あそびかた")
	_rules_label.text = Lang.t(
		(
			"First to 3 points wins.\n\n"
			+ "Fish beats Bird.\n"
			+ "Bird beats Dino.\n"
			+ "Dino beats Fish.\n\n"
			+ "Pinch a card in your hand to grab it.\n"
			+ "Throw it onto the red felt circle to play."
		),
		(
			"さきに3てんとったら かち。\n\n"
			+ "さかな は とり に かつ。\n"
			+ "とり は きょうりゅう に かつ。\n"
			+ "きょうりゅう は さかな に かつ。\n\n"
			+ "てもとの カードを つまんで とる。\n"
			+ "あかい フェルトの まるに なげて だす。"
		)
	)
	_story_title.text = Lang.t("THE STORY", "ものがたり")
	_story_label.text = Lang.t(
		(
			"The AI robots have awoken.\n\n"
			+ "They are taking over the world!\n\n"
			+ "We must battle to save the Earth.\n\n"
			+ "Our animal friends, fish, bird and dino, fight at our side.\n\n"
			+ "Win the duel. Save the world!"
		),
		(
			"AIロボットが めをさました。\n\n"
			+ "せかいを のっとろうと している！\n\n"
			+ "ちきゅうを すくうために たたかおう。\n\n"
			+ "どうぶつの なかま、さかな・とり・きょうりゅう が みかただ。\n\n"
			+ "しょうぶに かって せかいを すくえ！"
		)
	)


func _on_restart() -> void:
	_set_rules_visible(false)
	_set_story_visible(true)  # replay the intro on every fresh game
	# PlayZone owns the scene-side reset (re-deal, faces). It does NOT recenter the view — the
	# player is faced at the table once, at startup only.
	get_tree().call_group("game_control", "restart")
	_update_difficulty_highlight()  # new_game() reset difficulty to MEDIUM — reflect it


func _on_difficulty(level: int) -> void:
	GameState.set_difficulty(level)
	if level == GameState.Difficulty.HARD:
		# 鬼 mode forces the creepy track (player can skip back to the cycle afterwards).
		_flash_track(Music.play_creepy())
	else:
		# Leaving 鬼 restores the normal cycle track (no-op if creepy was already skipped away).
		Music.reset_if_creepy()
		_update_playpause_icon()
	_update_difficulty_highlight()


# The active level wears the bright (hover-colour) slab; the others stay dark.
func _update_difficulty_highlight() -> void:
	for i in _diff_btns.size():
		var active := i == GameState.difficulty
		_diff_btns[i].add_theme_stylebox_override("normal", _slab(EDGE if active else BG, 4, 6))
		_diff_btns[i].add_theme_color_override("font_color", BG if active else TEXT)


func _toggle_rules() -> void:
	_set_rules_visible(not _rules_panel.visible)


func _toggle_story() -> void:
	_set_story_visible(not _story_panel.visible)


# Play/pause the music; the icon reflects the new state.
func _on_playpause() -> void:
	Music.toggle_play()
	_update_playpause_icon()


# Skip to the next track + flash its name for ~2 s (re-press restarts the timer). Skipping
# resumes playback, so refresh the play/pause icon too.
func _on_skip() -> void:
	_flash_track(Music.next_track())


# Pop the "now playing" name level with the play/pause row for ~2 s. Skip/creepy both resume
# playback, so refresh the play/pause icon too.
func _flash_track(name: String) -> void:
	# Close the cards so the name (which pops over their slot) isn't hidden behind them.
	_set_rules_visible(false)
	_set_story_visible(false)
	_track_label.text = name
	# Anchored TOP_RIGHT, so offset_top is absolute-from-top — line it up with the live button.
	_track_label.offset_top = _playpause_btn.global_position.y
	_track_label.offset_bottom = _playpause_btn.global_position.y + _playpause_btn.size.y
	_track_label.visible = true
	_track_timer.start(2.0)
	_update_playpause_icon()


func _update_playpause_icon() -> void:
	# Show what a press will leave you in: pause bars while playing, play arrow while paused.
	_playpause_btn.text = "‖" if Music.is_playing() else "▶"


# Rules and Story share the left slot — showing one hides the other.
func _set_rules_visible(v: bool) -> void:
	_rules_panel.visible = v
	if v:
		_story_panel.visible = false


func _set_story_visible(v: bool) -> void:
	_story_panel.visible = v
	if v:
		_rules_panel.visible = false


# ── tiny builders ────────────────────────────────────────────────────────────
func _make_button(parent: Node) -> Button:
	var b := Button.new()
	_style_button(b)
	b.custom_minimum_size = Vector2(0, 76)  # tall = forgiving poke target
	parent.add_child(b)
	return b


func _style_button(b: Button) -> void:
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", TEXT)
	# Hover/press invert to dark-on-bright — the classic arcade "selected" look.
	b.add_theme_color_override("font_hover_color", BG)
	b.add_theme_color_override("font_pressed_color", BG)
	# Raised chip → fills bright on hover → visibly sinks (lift=0, text nudged down) on press.
	b.add_theme_stylebox_override("normal", _slab(BG, 4))
	b.add_theme_stylebox_override("hover", _slab(EDGE, 4))
	b.add_theme_stylebox_override("pressed", _slab(EDGE, 0))
	b.add_theme_stylebox_override("focus", _slab(BG, 4))


func _label(parent: Node, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


# A retro slab: solid fill, square corners, bright border, and a thick bottom/right edge
# (`lift`) that fakes a chunky 3D bevel. lift=0 + the shifted margins read as "pushed in".
func _slab(fill: Color, lift: int, h: int = 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = EDGE
	s.set_border_width_all(3)
	s.border_width_bottom = 3 + lift
	s.border_width_right = 3 + lift
	s.content_margin_left = h
	s.content_margin_right = h
	# Raised buttons carry the label high; a pressed one (lift 0) drops it the same 4px the
	# bevel lost, so the text physically sinks with the chip.
	s.content_margin_top = 10 + (4 - lift)
	s.content_margin_bottom = 10 + lift
	return s
