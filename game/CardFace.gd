# game/CardFace.gd — STUB (wired in Stage 2; DESIGN §6, FSD R5–R8).
# ─────────────────────────────────────────────────────────────────────────────
# Attach to a Card (RigidBody3D). Holds the card's type + 6 expression frames and runs the
# blink loop. At rest it blinks neutral; while HELD (grabbed/selected) it shows a determined
# face and blinks that. Faces are a 2D sprite swap on the material's albedo_texture — NO
# rigging (R5). (determined/determined_blink extend FSD R5's four frames — see docs/SPRITES.md.)
#
# ⚠️ This is a STUB: it references a child `MeshInstance3D` that exists once Card.tscn
# is authored. It parses on its own but is exercised in-headset, not by unit tests
# (testing the VR/sprite layer would be anti-YAGNI — see _dev_notes/00 §4).
#
# Encodes finding F2 (per-instance material) and E13 (await-after-free guard).
# Root extends XRToolsPickable (a RigidBody3D) so ONE node is grabbable/throwable AND owns
# its face; PlayZone reads card_type / show_smile() off the body entering the zone (DESIGN §6).
extends "res://addons/godot-xr-tools/objects/pickable.gd"  # XRToolsPickable, a RigidBody3D

# Card type as 0/1/2 — SAME ordering as GameState.Type (WATER=0, SKY=1, EARTH=2).
# Using @export_enum int (not `: GameState.Type`) so this stub compiles standalone and
# avoids autoload-name-as-type fragility; PlayZone/GameState read it as a plain int.
@export_enum("Water_Fish", "Sky_Bird", "Earth_Dino") var card_type: int = 0

# The 6 frames (R5/R8 + the determined pair). Assign in the inspector or via GameRoot's
# per-type arrays. blink = neutral eyes-closed; determined_blink = determined eyes-closed.
@export var tex_neutral: Texture2D
@export var tex_blink: Texture2D
@export var tex_smile: Texture2D
@export var tex_cry: Texture2D
@export var tex_determined: Texture2D  # shown while the card is held/selected
@export var tex_determined_blink: Texture2D  # determined, eyes closed (blink while held)

# Tunable blink cadence (R6, FSD §5.1 — @export so it's venue-calibratable in-editor).
@export var blink_interval_min: float = 3.0
@export var blink_interval_max: float = 4.5
@export var blink_hold: float = 0.15

var _mat: StandardMaterial3D
var _blink_timer: Timer
var _locked := false  # once the card emotes (smile/cry), stop blinking (R7)
# Current blink pair: rest = neutral/blink, held = determined/determined_blink.
var _open_tex: Texture2D
var _closed_tex: Texture2D

@onready var _mesh: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	super()  # CRITICAL: let XRToolsPickable collect grab points / init grab state (else throw breaks)
	_ensure_unique_material()  # F2 — must be per-instance or every card's face changes together
	_open_tex = tex_neutral
	_closed_tex = tex_blink
	_apply_texture(_open_tex)
	_blink_timer = Timer.new()
	_blink_timer.one_shot = true
	add_child(_blink_timer)
	_blink_timer.timeout.connect(_do_blink)
	_schedule_blink()
	# Determined face on select: XRToolsPickable fires picked_up on grab, dropped on release.
	picked_up.connect(_on_picked_up)
	dropped.connect(_on_dropped)


# F2: guarantee THIS card owns its material. If a surface-override is present, duplicate it;
# else duplicate the mesh's active material into a per-instance override. Without this, the
# material is shared by reference and swapping one face swaps ALL cards (edge E11).
func _ensure_unique_material() -> void:
	var src: Material = _mesh.get_surface_override_material(0)
	if src == null:
		src = _mesh.get_active_material(0)
	if src is StandardMaterial3D:
		_mat = (src as StandardMaterial3D).duplicate()
	else:
		_mat = StandardMaterial3D.new()
	# Crisp 2D faces on a 3D quad: unshaded + alpha scissor (see _dev_notes/godot_tutorials.md §3).
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_mesh.set_surface_override_material(0, _mat)


func _apply_texture(t: Texture2D) -> void:
	if _mat and t:
		_mat.albedo_texture = t


func _schedule_blink() -> void:
	_blink_timer.start(randf_range(blink_interval_min, blink_interval_max))


func _do_blink() -> void:
	if _locked:
		return
	_apply_texture(_closed_tex)
	# SceneTreeTimer await — guard against the node being freed mid-await (edge E13).
	await get_tree().create_timer(blink_hold).timeout
	if not is_instance_valid(self) or _locked:
		return
	_apply_texture(_open_tex)
	_schedule_blink()


# Grab = select: switch to the determined face and blink THAT while held. Falls back to
# neutral if no determined art is assigned, so a missing frame never freezes the card.
func _on_picked_up(_pickable: Node) -> void:
	if _locked or not tex_determined:
		return
	_open_tex = tex_determined
	_closed_tex = tex_determined_blink if tex_determined_blink else tex_determined
	_apply_texture(_open_tex)


# Release: back to the resting neutral face (resolution then locks smile/cry once it lands).
func _on_dropped(_pickable: Node) -> void:
	if _locked:
		return
	_open_tex = tex_neutral
	_closed_tex = tex_blink
	_apply_texture(_open_tex)


# Called by PlayZone on resolution (R7). Locking stops the blink loop.
func show_smile() -> void:
	_locked = true
	_apply_texture(tex_smile)


func show_cry() -> void:
	_locked = true
	_apply_texture(tex_cry)
