class_name PokeGesture
extends Node3D

## Gates each hand's fingertip Poke on a "point" gesture, so a button only
## presses when the player is actually pointing (index out, other fingers
## curled) — not when an open or flat hand happens to brush it. Hand-tracking
## only: a hand with no joint data (controllers, or lost tracking) keeps its
## poke enabled, preserving the default touch behaviour.

# ponytail: curl thresholds eyeballed in radians — tune in-headset. The gap
# between them is a dead zone so a half-curled finger doesn't flicker the gate.
const EXTENDED_MAX := 0.6  # index must bend less than this to count as "out"
const CURLED_MIN := 1.0  # other fingers must bend more than this to count "in"

# Dot only shows while pointing; fully transparent otherwise (matches the purple hand tint).
const SHOW := Color(0.78, 0.7, 0.89, 0.85)
const HIDE := Color(0, 0, 0, 0)

# Poke node path + matching OpenXR hand-tracker name, per hand.
const HANDS := [
	["XROrigin3D/LeftHand/Poke", "/user/hand_tracker/left"],
	["XROrigin3D/RightHand/Poke", "/user/hand_tracker/right"],
]


func _process(_delta: float) -> void:
	for hand in HANDS:
		var poke := get_node_or_null(hand[0])
		if poke:
			var pointing := _is_pointing(hand[1])
			poke.enabled = pointing  # only the pointing hand can press a button
			var want := SHOW if pointing else HIDE
			if poke.color != want:
				poke.color = want


# True unless hand-joint data clearly shows a non-pointing pose.
func _is_pointing(tracker_name: String) -> bool:
	var tracker := XRServer.get_tracker(tracker_name) as XRHandTracker
	if not tracker or not tracker.has_tracking_data:
		return true  # no hand tracking → leave the poke on (controller fallback)

	if _finger_curl(tracker, XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL) > EXTENDED_MAX:
		return false  # index not extended
	for base in [
		XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL,
		XRHandTracker.HAND_JOINT_RING_FINGER_METACARPAL,
		XRHandTracker.HAND_JOINT_PINKY_FINGER_METACARPAL,
	]:
		if _finger_curl(tracker, base) < CURLED_MIN:
			return false  # another finger still out → open hand, not a point
	return true


# Curl angle (radians) at a finger: 0 = straight, larger = more curled. `base`
# is the finger's METACARPAL joint; the joints run metacarpal, proximal,
# intermediate, distal, tip — so base+1 is proximal and base+4 is the tip.
func _finger_curl(tracker: XRHandTracker, base: int) -> float:
	var metacarpal := tracker.get_hand_joint_transform(base).origin
	var proximal := tracker.get_hand_joint_transform(base + 1).origin
	var tip := tracker.get_hand_joint_transform(base + 4).origin
	return (proximal - metacarpal).angle_to(tip - proximal)
