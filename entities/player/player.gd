extends CharacterBody2D

const WALK_SPEED = 100.0
const RUN_SPEED = 180.0
const FRICTION = 1200.0

## --- Stamina System ---
@export var MAX_STAMINA: float = 100.0
@export var STAMINA_DRAIN_RATE: float = 25.0   # per second while sprinting
@export var STAMINA_REGEN_RATE: float = 20.0   # per second while walking or standing still
@export var EXHAUSTION_DURATION: float = 2.0   # seconds sprint is disabled after hitting 0 stamina

signal stamina_changed(current_stamina: float, max_stamina: float)
signal exhausted
signal recovered_from_exhaustion

var stamina: float = MAX_STAMINA
var is_exhausted: bool = false
var _exhaustion_timer: float = 0.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var stamina_bar: ProgressBar = $ui/StaminaBar


var last_direction: String = "s" # Default facing direction (South/Down)

func _ready() -> void:
	stamina_bar.max_value = MAX_STAMINA
	stamina_bar.value = stamina
	stamina_changed.connect(_on_stamina_changed)

func _physics_process(delta: float) -> void:
	# Ignore input processing if this character belongs to another player over the network
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return

	# 1. Get 360-degree vector input (Fixed for Godot 4)
	var input_vector := Input.get_vector("left", "right", "up", "down")

	# 2. Check if the player is holding the run button
	var wants_to_run := Input.is_action_pressed("run") or Input.is_key_pressed(KEY_SHIFT)
	var is_moving := input_vector != Vector2.ZERO

	# Sprinting only actually happens while moving, stamina is available, and not exhausted
	var is_running := wants_to_run and is_moving and not is_exhausted and stamina > 0.0

	_update_stamina(delta, is_running)

	var current_speed := RUN_SPEED if is_running else WALK_SPEED

	# 3. Handle smooth top-down movement & animations
	if is_moving:
		velocity = input_vector * current_speed
		var suffix = get_direction_suffix(input_vector)
		last_direction = suffix

		# Flip sprite horizontally if moving left
		animated_sprite.flip_h = (input_vector.x < 0)

		# Select animation state (run_ vs walk_)
		var anim_prefix := "run_" if is_running else "walk_"
		animated_sprite.play(anim_prefix + suffix)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		animated_sprite.play("idle_" + last_direction)

	move_and_slide()

# Handles draining, regenerating, and exhaustion timing for the stamina bar.
func _update_stamina(delta: float, is_running: bool) -> void:
	var previous_stamina := stamina

	if is_running:
		stamina = max(0.0, stamina - STAMINA_DRAIN_RATE * delta)
		if stamina == 0.0 and not is_exhausted:
			_enter_exhaustion()
	else:
		# Walking or standing still both refill stamina
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

# --- UI callbacks ---
func _on_stamina_changed(current_stamina: float, max_stamina: float) -> void:
	stamina_bar.value = current_stamina


# Converts a 2D movement vector into 5 directional suffixes (e, se, s, ne, n)
func get_direction_suffix(dir: Vector2) -> String:
	var angle = dir.angle() # Angle in radians (-PI to PI)
	
	# Pure Vertical (North / South)
	if angle >= 3*PI/8 and angle < 5*PI/8:
		return "s"   # South / Down
	elif angle >= -5*PI/8 and angle < -3*PI/8:
		return "n"   # North / Up
		
	# Diagonals
	elif (angle >= PI/8 and angle < 3*PI/8) or (angle >= 5*PI/8 and angle < 7*PI/8):
		return "se"  # South-East / South-West (flipped)
	elif (angle >= -3*PI/8 and angle < -PI/8) or (angle >= -7*PI/8 and angle < -5*PI/8):
		return "ne"  # North-East / North-West (flipped)
		
	# Horizontals (East / West)
	else:
		return "e"   # East / West (flipped)
