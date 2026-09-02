extends Control

## Pulsing red screen-edge vignette that tells a Tubig how close the Sili is
## WITHOUT telling them which direction it's coming from.
##
## Two things scale with proximity: how strong the red gets, and how fast it
## throbs. A slow faint pulse means "somewhere nearby", a fast hard pulse means
## "turn around". Direction is deliberately withheld - that's what the mini-map
## and actually looking around are for.
##
## Sili players never see this (they're the threat), and it fades out once the
## local player is Dead since there's nothing left to run from.

@export var MAX_RANGE: float = 320.0    # beyond this, no vignette at all
@export var MIN_RANGE: float = 48.0     # at or inside this, full intensity
@export var MAX_ALPHA: float = 0.55     # opacity ceiling so the map stays readable
@export var SLOW_PULSE_HZ: float = 0.7  # throb speed at the edge of MAX_RANGE
@export var FAST_PULSE_HZ: float = 3.6  # throb speed at MIN_RANGE
@export var RESPONSE_SPEED: float = 6.0 # how quickly intensity chases the target

const VIGNETTE_SHADER_CODE := """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(0.85, 0.05, 0.08);

void fragment() {
	// Distance from screen centre, corrected so the falloff hugs all four
	// edges evenly instead of bulging on the wider axis.
	vec2 centred = (UV - vec2(0.5)) * 2.0;
	float d = max(abs(centred.x), abs(centred.y)) * 0.6 + length(centred) * 0.4;
	float edge = smoothstep(0.45, 1.15, d);
	COLOR = vec4(tint, edge * intensity);
}
"""

var _overlay: ColorRect
var _material: ShaderMaterial
var _tracked_player: Node2D = null
var _phase: float = 0.0
var _intensity: float = 0.0
var _enabled: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER_CODE

	_material = ShaderMaterial.new()
	_material.shader = shader

	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.color = Color(1, 1, 1, 1)  # the shader supplies the real colour
	_overlay.material = _material
	add_child(_overlay)

	visible = false
	set_process(false)


## Called by the arena once it knows which character belongs to this peer.
## Passing anything other than a Tubig (or null) just leaves the vignette off.
func track_player(player: Node2D, is_tubig: bool) -> void:
	_tracked_player = player
	_enabled = is_tubig and player != null
	visible = _enabled
	set_process(_enabled)
	_intensity = 0.0
	_phase = 0.0
	if _material:
		_material.set_shader_parameter("intensity", 0.0)


func _process(delta: float) -> void:
	if not _enabled or not is_instance_valid(_tracked_player):
		_fade_out(delta)
		return

	var target := _target_intensity()
	var pulse_hz: float = lerp(SLOW_PULSE_HZ, FAST_PULSE_HZ, _proximity())

	_phase = fmod(_phase + TAU * pulse_hz * delta, TAU)
	_intensity = move_toward(_intensity, target, RESPONSE_SPEED * delta)

	# sin() mapped into 0.45-1.0 so the vignette never fully blinks off while
	# the Sili is close - it breathes rather than strobes.
	var throb := 0.45 + 0.55 * (0.5 + 0.5 * sin(_phase))
	_material.set_shader_parameter("intensity", _intensity * throb * MAX_ALPHA)


func _target_intensity() -> float:
	var heat = _tracked_player.get_node_or_null("HeatStatus")
	if heat and heat.is_dead():
		return 0.0  # nothing left to warn them about
	return _proximity()


## 0.0 at MAX_RANGE or further, 1.0 at MIN_RANGE or closer.
func _proximity() -> float:
	var sili := get_tree().get_first_node_in_group("sili")
	if sili == null or not is_instance_valid(sili):
		return 0.0
	var distance := _tracked_player.global_position.distance_to(sili.global_position)
	if distance >= MAX_RANGE:
		return 0.0
	if distance <= MIN_RANGE:
		return 1.0
	return 1.0 - (distance - MIN_RANGE) / (MAX_RANGE - MIN_RANGE)


func _fade_out(delta: float) -> void:
	_intensity = move_toward(_intensity, 0.0, RESPONSE_SPEED * delta)
	if _material:
		_material.set_shader_parameter("intensity", _intensity * MAX_ALPHA)
	if is_zero_approx(_intensity):
		set_process(false)
		visible = false
