extends Control

## End-of-match overlay: drops the world into slow motion, freezes the players,
## and puts the verdict in the middle of the screen with somewhere to go next.
##
## The verdict is per-player, not per-match. MatchManager only reports whether
## the Sili won; whether that means YOU WIN depends on which side you're on, so
## the same signal produces opposite text on different screens.
##
## Built in code rather than in the .tscn, matching pregame_reveal.gd - the
## layout is driven by outcome and by whether you're the host, so there's little
## worth laying out by hand.
##
## SLOW MOTION uses Engine.time_scale, which is global and does NOT reset on its
## own. Every exit path from this screen has to put it back to 1.0 or the title
## screen inherits the slowdown - hence _restore_time_scale() and the
## _exit_tree() safety net.

const SLOW_MOTION_SCALE := 0.25
const SLOW_MOTION_RAMP := 0.8
const BACKDROP_ALPHA := 0.72

const COLOR_WIN := Color(1.0, 0.85, 0.35)
const COLOR_LOSE := Color(1.0, 0.42, 0.38)

var _backdrop: ColorRect
var _verdict_label: Label
var _detail_label: Label
var _button_row: HBoxContainer
var _replay_button: Button
var _title_button: Button
var _hint_label: Label
var _fade_tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Ignore until there's actually something to click, so the overlay can't
	# swallow input from the HUD underneath it during play.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_build_ui()

	MatchManager.match_ended.connect(_on_match_ended)


func _exit_tree() -> void:
	# Last line of defence: if this scene is torn down by anything other than
	# our own buttons (host reloading the arena, a disconnect), the slowdown
	# must not follow us into the next scene.
	_restore_time_scale()


func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color(0.02, 0.03, 0.06, 0.0)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_verdict_label = Label.new()
	_verdict_label.name = "Verdict"
	_verdict_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_verdict_label.add_theme_font_size_override("font_size", 88)
	_verdict_label.add_theme_constant_override("outline_size", 12)
	_verdict_label.add_theme_color_override("font_outline_color", Color.BLACK)
	column.add_child(_verdict_label)

	_detail_label = Label.new()
	_detail_label.name = "Detail"
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_label.add_theme_font_size_override("font_size", 26)
	_detail_label.add_theme_color_override("font_color", Color(0.88, 0.9, 0.95))
	column.add_child(_detail_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	column.add_child(spacer)

	_button_row = HBoxContainer.new()
	_button_row.name = "Buttons"
	_button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_button_row.add_theme_constant_override("separation", 24)
	column.add_child(_button_row)

	_replay_button = Button.new()
	_replay_button.name = "ReplayButton"
	_replay_button.text = "Play Again"
	_replay_button.custom_minimum_size = Vector2(210, 56)
	_replay_button.pressed.connect(_on_replay_pressed)
	_button_row.add_child(_replay_button)

	_title_button = Button.new()
	_title_button.name = "TitleButton"
	_title_button.text = "Back to Title"
	_title_button.custom_minimum_size = Vector2(210, 56)
	_title_button.pressed.connect(_on_title_pressed)
	_button_row.add_child(_title_button)

	_hint_label = Label.new()
	_hint_label.name = "Hint"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 18)
	_hint_label.add_theme_color_override("font_color", Color(0.72, 0.75, 0.82))
	column.add_child(_hint_label)


func _on_match_ended(sili_won: bool) -> void:
	var i_won := _local_role() == ("sili" if sili_won else "tubig")

	_verdict_label.text = "YOU WIN!" if i_won else "YOU LOSE!"
	_verdict_label.add_theme_color_override("font_color", COLOR_WIN if i_won else COLOR_LOSE)
	_detail_label.text = "The Sili caught everyone." if sili_won else "The Tubig lasted the whole match."

	# Only the host can start another round - a client pressing Play Again would
	# reshuffle roles for a lobby it doesn't own. Clients get told to wait
	# instead of being handed a button that quietly does nothing.
	var can_replay := NetworkManager.is_host() or not multiplayer.has_multiplayer_peer()
	_replay_button.visible = can_replay
	_hint_label.text = "" if can_replay else "Waiting for the host to start another round..."

	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_title_button.grab_focus()

	_start_slow_motion()

	# ignore_time_scale, or the fade would crawl at the slowed rate and the
	# verdict would take three seconds to become readable.
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_ignore_time_scale(true)
	_fade_tween.tween_property(_backdrop, "color:a", BACKDROP_ALPHA, 0.45)


## Whose side the person at this screen is on. Falls back to Tubig for an
## offline test session, where there are no assigned roles at all.
func _local_role() -> String:
	var my_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	return NetworkManager.roles.get(my_id, "tubig")



## Eased rather than snapped: the moment of the tag reads better if the world
## drags to a halt over a beat instead of stuttering into it.
func _start_slow_motion() -> void:
	var tween := create_tween()
	tween.set_ignore_time_scale(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# tween_method rather than tween_property: Engine is an engine singleton,
	# not a scene node, and driving its property through a setter is the
	# unambiguous way to animate it.
	tween.tween_method(_set_time_scale, 1.0, SLOW_MOTION_SCALE, SLOW_MOTION_RAMP)


func _set_time_scale(value: float) -> void:
	Engine.time_scale = value


func _restore_time_scale() -> void:
	Engine.time_scale = 1.0


func _on_replay_pressed() -> void:
	_restore_time_scale()
	if NetworkManager.is_host():
		# Reshuffles roles and reloads the arena on every peer, so the Sili
		# isn't the same player two rounds running.
		NetworkManager.start_match()
	else:
		# Offline session - nothing to coordinate, just run the level again.
		get_tree().reload_current_scene()


func _on_title_pressed() -> void:
	_restore_time_scale()
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://ui/title_screen/title_screen.tscn")
