extends Control

## Full-screen reveal that runs before the match clock starts.
##
## Nobody should discover who the Sili is by being tagged by them. This names
## the Sili to everyone up front, tells each player which side they're on, and
## flashes a 3-2-1 countdown so the whole lobby starts moving on the same beat.
## Movement is locked for the duration (see MatchManager.inputs_locked), so the
## Sili can't get a head start off the back of a faster loading screen.
##
## Builds its own UI in code rather than in the .tscn - the layout is entirely
## driven by role and player count, so there's nothing useful to lay out by hand.

const COLOR_SILI := Color(1.0, 0.35, 0.3)
const COLOR_TUBIG := Color(0.4, 0.7, 1.0)

var _backdrop: ColorRect
var _flash: ColorRect
var _role_label: Label
var _detail_label: Label
var _countdown_label: Label
var _flash_tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

	MatchManager.pregame_started.connect(_on_pregame_started)
	MatchManager.pregame_tick.connect(_on_pregame_tick)
	MatchManager.pregame_finished.connect(_on_pregame_finished)

	# The host fires the pregame RPC a frame or two after the arena loads, so
	# hold a neutral "get ready" state instead of flashing the live map first.
	_role_label.text = "GET READY"
	_role_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_detail_label.text = "Assigning roles..."
	_countdown_label.text = ""


func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.color = Color(0.02, 0.02, 0.04, 0.82)
	add_child(_backdrop)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	_role_label = Label.new()
	_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_role_label.add_theme_font_size_override("font_size", 52)
	column.add_child(_role_label)

	_detail_label = Label.new()
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_label.add_theme_font_size_override("font_size", 20)
	_detail_label.add_theme_color_override("font_color", Color(0.85, 0.87, 0.92))
	column.add_child(_detail_label)

	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 88)
	column.add_child(_countdown_label)

	# Sits above everything and gets tweened down to zero on each tick.
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	add_child(_flash)


func _on_pregame_started(_duration: float) -> void:
	visible = true

	var my_id: int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var my_role: String = NetworkManager.roles.get(my_id, "tubig")
	var is_sili := my_role == "sili"

	_role_label.text = "YOU ARE SILI" if is_sili else "YOU ARE TUBIG"
	_role_label.add_theme_color_override("font_color", COLOR_SILI if is_sili else COLOR_TUBIG)
	_detail_label.text = _build_detail_text(is_sili)


## Everyone learns the Sili's name here - this isn't a hidden-role game, the
## tension comes from not knowing where they are, not who they are.
func _build_detail_text(is_sili: bool) -> String:
	var sili_name := ""
	var tubig_count := 0
	for peer_id in NetworkManager.roles.keys():
		if NetworkManager.roles[peer_id] == "sili":
			sili_name = NetworkManager.players.get(peer_id, "Player %d" % peer_id)
		else:
			tubig_count += 1

	if sili_name.is_empty():
		return "Get ready!"
	if is_sili:
		return "Catch all %d Tubig before the timer runs out." % tubig_count
	return "%s is the Sili. Stay cool, free your teammates." % sili_name


func _on_pregame_tick(seconds_left: int) -> void:
	if seconds_left <= 0:
		_countdown_label.text = "GO!"
	else:
		_countdown_label.text = str(seconds_left)

	_countdown_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_pulse_flash(0.22 if seconds_left > 0 else 0.45)


func _pulse_flash(strength: float) -> void:
	if _flash_tween and _flash_tween.is_running():
		_flash_tween.kill()
	_flash.color = Color(1, 1, 1, strength)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "color:a", 0.0, 0.35)


func _on_pregame_finished() -> void:
	_countdown_label.text = "GO!"
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(_hide_after_fade)


func _hide_after_fade() -> void:
	visible = false
	modulate.a = 1.0
