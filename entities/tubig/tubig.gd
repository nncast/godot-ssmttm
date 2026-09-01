extends CharacterBody2D

const WALK_SPEED = 100.0
const RUN_SPEED = 180.0
const FRICTION = 1200.0

## --- Stamina System ---
@export var MAX_STAMINA: float = 100.0
@export var STAMINA_DRAIN_RATE: float = 25.0
@export var STAMINA_REGEN_RATE: float = 20.0
@export var EXHAUSTION_DURATION: float = 2.0

## --- Rescue System ---
@export var MAX_RESCUES: int = 3
@export var RESCUE_CHANNEL_TIME: float = 6.0  # seconds, per doc's 5-8s range

signal stamina_changed(current_stamina: float, max_stamina: float)
signal exhausted
signal recovered_from_exhaustion
signal rescues_changed(rescues_left: int)
signal rescue_progress(progress: float)  # 0.0 - 1.0, for a channel bar

var stamina: float = MAX_STAMINA
var is_exhausted: bool = false
var _exhaustion_timer: float = 0.0
var last_direction: String = "s"

## Property (not a plain var) so rescues_changed fires consistently whether
## the change comes from this peer's own code or gets set directly by
## MultiplayerSynchronizer on a remote peer - same reasoning as HeatStatus.state.
var rescues_left: int = MAX_RESCUES:
	set(value):
		if value == rescues_left:
			return
		rescues_left = value
		rescues_changed.emit(value)

var _rescue_target: Node2D = null
var _rescue_timer: float = 0.0
var _is_channeling: bool = false
var _progress_broadcast_accum: float = 0.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var ui_layer: CanvasLayer = $ui
@onready var stamina_bar: ProgressBar = $ui/StaminaBar
@onready var rescue_bar: ProgressBar = $ui/RescueBar
@onready var hearts: Array = [$ui/HeartsRow/Heart1, $ui/HeartsRow/Heart2, $ui/HeartsRow/Heart3]
@onready var heat_status: HeatStatus = $HeatStatus
@onready var interaction_area: Area2D = $InteractionArea
@onready var rescue_indicator: ProgressBar = $RescueIndicator
@onready var rescue_indicator_label: Label = $RescueIndicator/RescueLabel


func _ready() -> void:
	# Every spawned character has its own HUD CanvasLayer, but a CanvasLayer
	# always draws full-screen regardless of which node it's attached to - so
	# without this, every remote player's stamina bar would draw stacked on
	# top of yours in the same screen spot. Only the locally-controlled
	# character's HUD should ever be visible.
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		ui_layer.visible = false

	stamina_bar.max_value = MAX_STAMINA
	stamina_bar.value = stamina
	stamina_changed.connect(_on_stamina_changed)

	heat_status.state_changed.connect(_on_heat_state_changed)

	rescue_bar.visible = false
	rescue_progress.connect(_on_rescue_progress)
	rescues_changed.connect(_on_rescues_changed)
	_update_hearts(rescues_left)

	rescue_indicator.visible = false

	add_to_group("player")  # keeps compatibility with the canopy fade (over.gd)
	add_to_group("tubig")


func _physics_process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return

	# Burning/Dead = rooted. Can't walk, run, or rescue anyone else. Dead is
	# permanent; Burning can still be saved by a teammate before it expires.
	if heat_status.is_incapacitated():
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		_play_heat_animation()
		move_and_slide()
		_cancel_rescue_channel()
		return

	var input_vector := Input.get_vector("left", "right", "up", "down")
	var wants_to_run := Input.is_action_pressed("run") or Input.is_key_pressed(KEY_SHIFT)
	var wants_to_rescue := Input.is_action_pressed("rescue")

	var is_moving := input_vector != Vector2.ZERO

	# Channeling a rescue locks you in place - moving cancels it.
	if wants_to_rescue and not is_moving:
		_handle_rescue_channel(delta)
	else:
		_cancel_rescue_channel()

	var is_running := wants_to_run and is_moving and not is_exhausted and stamina > 0.0 and not _is_channeling

	_update_stamina(delta, is_running)

	if _is_channeling:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var current_speed := RUN_SPEED if is_running else WALK_SPEED

	if is_moving:
		velocity = input_vector * current_speed
		var suffix = get_direction_suffix(input_vector)
		last_direction = suffix
		animated_sprite.flip_h = (input_vector.x < 0)
		var anim_prefix := "run_" if is_running else "walk_"
		animated_sprite.play(anim_prefix + suffix)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		animated_sprite.play("idle_" + last_direction)

	move_and_slide()


# --- Rescue ("Tubig!") ---

func _handle_rescue_channel(delta: float) -> void:
	if rescues_left <= 0 or not MatchManager.rescues_available():
		_cancel_rescue_channel()
		return

	var target := _find_burning_ally()
	if target == null:
		_cancel_rescue_channel()
		return

	if target != _rescue_target:
		_rescue_target = target
		_rescue_timer = 0.0
		_progress_broadcast_accum = 0.0

	_is_channeling = true
	_rescue_timer += delta
	var progress: float = _rescue_timer / RESCUE_CHANNEL_TIME
	rescue_progress.emit(progress)

	# Throttled broadcast so everyone (especially the person being rescued)
	# sees a countdown above their head, not just the rescuer's own screen.
	_progress_broadcast_accum += delta
	if _progress_broadcast_accum >= 0.1 or progress >= 1.0:
		_progress_broadcast_accum = 0.0
		target.rpc("show_rescue_progress", progress, RESCUE_CHANNEL_TIME - _rescue_timer)

	if _rescue_timer >= RESCUE_CHANNEL_TIME:
		_complete_rescue()


func _complete_rescue() -> void:
	if _rescue_target and is_instance_valid(_rescue_target):
		var target_heat: HeatStatus = _rescue_target.get_node_or_null("HeatStatus")
		if target_heat:
			if multiplayer.has_multiplayer_peer():
				target_heat.rpc_id(1, "request_cool_fully")
			else:
				target_heat.cool_fully()
		_rescue_target.rpc("show_rescue_progress", 0.0, 0.0)

	rescues_left -= 1
	_cancel_rescue_channel()


func _cancel_rescue_channel() -> void:
	var was_channeling := _is_channeling
	_is_channeling = false
	if was_channeling and _rescue_target and is_instance_valid(_rescue_target):
		_rescue_target.rpc("show_rescue_progress", 0.0, 0.0)
	_rescue_target = null
	_rescue_timer = 0.0
	_progress_broadcast_accum = 0.0
	rescue_progress.emit(0.0)


func _find_burning_ally() -> Node2D:
	var closest: Node2D = null
	var closest_dist := INF
	for body in interaction_area.get_overlapping_bodies():
		if body == self or not body.is_in_group("tubig"):
			continue
		var body_heat: HeatStatus = body.get_node_or_null("HeatStatus")
		if body_heat and body_heat.is_burning():
			var dist := global_position.distance_squared_to(body.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = body
	return closest


# --- Stamina ---

func _update_stamina(delta: float, is_running: bool) -> void:
	var previous_stamina := stamina

	if is_running:
		stamina = max(0.0, stamina - STAMINA_DRAIN_RATE * delta)
		if stamina == 0.0 and not is_exhausted:
			_enter_exhaustion()
	else:
		stamina = min(MAX_STAMINA, stamina + STAMINA_REGEN_RATE * delta)

	if is_exhausted:
		_exhaustion_timer -= delta
		if _exhaustion_timer <= 0.0:
			_exit_exhaustion()

	if stamina != previous_stamina:
		stamina_changed.emit(stamina, MAX_STAMINA)


func _enter_exhaustion() -> void:
	is_exhausted = true
	_exhaustion_timer = EXHAUSTION_DURATION
	exhausted.emit()


func _exit_exhaustion() -> void:
	is_exhausted = false
	_exhaustion_timer = 0.0
	recovered_from_exhaustion.emit()


func _on_stamina_changed(current_stamina: float, max_stamina: float) -> void:
	stamina_bar.value = current_stamina


func _on_rescue_progress(progress: float) -> void:
	rescue_bar.visible = progress > 0.0
	rescue_bar.value = progress * 100.0


func _on_rescues_changed(new_rescues_left: int) -> void:
	_update_hearts(new_rescues_left)


func _update_hearts(rescues_remaining: int) -> void:
	for i in hearts.size():
		hearts[i].modulate = Color(1, 0.25, 0.35) if i < rescues_remaining else Color(0.25, 0.25, 0.25, 0.5)


func _on_heat_state_changed(new_state: HeatStatus.State) -> void:
	if new_state == HeatStatus.State.BURNING:
		animated_sprite.play("heat_" + last_direction)


## Keeps the burn animation matched to whichever direction the player was
## last facing, and freezes it once they're Dead instead of looping forever.
func _play_heat_animation() -> void:
	var anim := "heat_" + last_direction
	if heat_status.is_dead():
		if animated_sprite.animation != anim:
			animated_sprite.play(anim)
		animated_sprite.pause()
	elif animated_sprite.animation != anim or not animated_sprite.is_playing():
		animated_sprite.play(anim)


## Broadcast by whoever is channeling a rescue ON this Tubig, so the
## countdown shows above the burning player's own head - visible to
## everyone, not just the rescuer. Any peer may call this; it's purely
## cosmetic (no game-state change), so it isn't authority-gated.
@rpc("any_peer", "call_local", "unreliable")
func show_rescue_progress(progress: float, seconds_left: float) -> void:
	rescue_indicator.visible = progress > 0.0
	rescue_indicator.value = progress * 100.0
	rescue_indicator_label.text = str(int(ceil(seconds_left)))


func get_direction_suffix(dir: Vector2) -> String:
	var angle = dir.angle()

	if angle >= 3*PI/8 and angle < 5*PI/8:
		return "s"
	elif angle >= -5*PI/8 and angle < -3*PI/8:
		return "n"
	elif (angle >= PI/8 and angle < 3*PI/8) or (angle >= 5*PI/8 and angle < 7*PI/8):
		return "se"
	elif (angle >= -3*PI/8 and angle < -PI/8) or (angle >= -7*PI/8 and angle < -5*PI/8):
		return "ne"
	else:
		return "e"
