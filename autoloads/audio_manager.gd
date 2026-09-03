extends Node

## Autoload. Owns every non-positional sound in the game: the two music
## tracks, the UI hover/click blips, and the crossfade between them.
##
## Bus routing (see assets/audio/bus_layout.tres):
##   Music     -> Master     the two .ogg tracks
##   SFX       -> Master     parent of everything below, so one slider rules all
##     UI        -> SFX      hover / click blips
##     Ambience  -> SFX      the ocean loop
##     Footsteps -> SFX      per-surface steps from surface_audio.gd
##
## UI sounds wire themselves up: rather than making every scene remember to
## connect its own buttons, this listens to the SceneTree and hooks any Button
## the moment it enters the tree, anywhere in the game. Add a node to the
## "silent_ui" group to opt it out.

const MUSIC_TITLE: AudioStream = preload("res://assets/audio/music/Music_Title.ogg")
const MUSIC_INGAME: AudioStream = preload("res://assets/audio/music/Music_Ingame.ogg")
const SFX_UI_HOVER: AudioStream = preload("res://assets/audio/ui/ui_hover.wav")
const SFX_UI_CLICK: AudioStream = preload("res://assets/audio/ui/ui_click.wav")

const CROSSFADE_TIME := 1.2
## Music sits well under the game now - background texture, not a score.
## Footsteps and the ocean are the cues that carry information in a game about
## hearing where someone is, so the music has to leave room for them.
const MUSIC_DB := -20.0
## Hover fires constantly as the pointer sweeps a menu, so it sits well under
## the click and refuses to retrigger while the previous blip is still going.
const HOVER_DB := -8.0   # Increased from -14.0 to make hovers louder
const HOVER_MIN_GAP := 0.06
const UI_VOICES := 4

## SFX bus boost - raises volume for all sounds routed through SFX bus
## (footsteps, ambience, and UI sounds together)
const SFX_BUS_BOOST_DB := 3.0  # Increase this value for louder SFX

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active_music: AudioStreamPlayer
var _current_track: AudioStream = null
var _fade_tween: Tween

var _ui_voices: Array[AudioStreamPlayer] = []
var _ui_voice_index := 0
var _last_hover_at := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_music_a = _make_music_player("MusicA")
	_music_b = _make_music_player("MusicB")
	_active_music = _music_a

	for i in UI_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "UIVoice%d" % i
		voice.bus = "UI"
		add_child(voice)
		_ui_voices.append(voice)

	# Boost the SFX bus for all non-music sounds (footsteps, ambience, etc.)
	_boost_sfx_bus()

	get_tree().node_added.connect(_on_node_added)
	# Anything already in the tree when we boot (the title screen itself)
	# never fires node_added, so sweep it once by hand.
	_wire_buttons_under(get_tree().root)

	MatchManager.match_started.connect(_on_match_started)
	MatchManager.match_ended.connect(_on_match_ended)

	play_title_music()


func _make_music_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = "Music"
	player.volume_db = MUSIC_DB
	# Enable looping for music tracks
	player.finished.connect(_on_music_finished.bind(player))
	add_child(player)
	return player


## Boost the SFX bus volume to make footsteps, ambience, and UI sounds louder
func _boost_sfx_bus() -> void:
	var sfx_bus_idx := AudioServer.get_bus_index("SFX")
	if sfx_bus_idx != -1:
		# Get current volume and add our boost
		var current_db := AudioServer.get_bus_volume_db(sfx_bus_idx)
		AudioServer.set_bus_volume_db(sfx_bus_idx, current_db + SFX_BUS_BOOST_DB)
	else:
		push_warning("SFX bus not found! Check bus_layout.tres")


# --- Music ------------------------------------------------------------------

func play_title_music() -> void:
	_crossfade_to(MUSIC_TITLE)


func play_game_music() -> void:
	_crossfade_to(MUSIC_INGAME)


func stop_music() -> void:
	_crossfade_to(null)


## Swaps between two AudioStreamPlayers rather than restarting one, so the
## outgoing track can fade out over the top of the incoming one instead of
## cutting dead the moment the scene changes.
func _crossfade_to(stream: AudioStream) -> void:
	if stream == _current_track and _active_music.playing:
		return
	_current_track = stream

	var outgoing := _active_music
	var incoming := _music_b if _active_music == _music_a else _music_a
	_active_music = incoming

	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)

	if stream != null:
		incoming.stream = stream
		incoming.volume_db = GameSettings.MIN_DB
		incoming.play()
		_fade_tween.tween_property(incoming, "volume_db", MUSIC_DB, CROSSFADE_TIME)

	if outgoing.playing:
		_fade_tween.tween_property(outgoing, "volume_db", GameSettings.MIN_DB, CROSSFADE_TIME)
		# finished fires once the whole (parallel) tween is done, which is the
		# simplest correct moment to free the voice up for the next swap.
		_fade_tween.finished.connect(outgoing.stop, CONNECT_ONE_SHOT)


## Handle music looping - when a track finishes, restart it if it's still
## the current active track and we're not crossfading to something else.
func _on_music_finished(player: AudioStreamPlayer) -> void:
	# Only loop if this is still the active music player and we have a track
	if player == _active_music and _current_track != null and player.playing == false:
		player.play()


func _on_match_started() -> void:
	play_game_music()


func _on_match_ended(_sili_won: bool) -> void:
	play_title_music()


# --- UI blips ---------------------------------------------------------------

func play_ui_hover() -> void:
	# Sweeping a pointer across a menu can fire mouse_entered many times a
	# second; without this gate the blips pile up into a buzz.
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_hover_at < HOVER_MIN_GAP:
		return
	_last_hover_at = now
	_play_ui(SFX_UI_HOVER, HOVER_DB)


func play_ui_click() -> void:
	_play_ui(SFX_UI_CLICK, 0.0)


## Round-robins a small pool so a click landing on top of a hover doesn't cut
## the hover off mid-sample.
func _play_ui(stream: AudioStream, volume_db: float) -> void:
	var voice := _ui_voices[_ui_voice_index]
	_ui_voice_index = (_ui_voice_index + 1) % _ui_voices.size()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.play()


# --- Automatic button wiring ------------------------------------------------

func _on_node_added(node: Node) -> void:
	_wire_button(node)


func _wire_buttons_under(root: Node) -> void:
	_wire_button(root)
	for child in root.get_children():
		_wire_buttons_under(child)


## Covers Button, CheckBox, OptionButton and friends - they all derive from
## BaseButton, so menu toggles blip too without naming each type here.
func _wire_button(node: Node) -> void:
	var button := node as BaseButton
	if button == null or button.is_in_group("silent_ui"):
		return
	if not button.mouse_entered.is_connected(play_ui_hover):
		button.mouse_entered.connect(play_ui_hover)
	if not button.pressed.is_connected(play_ui_click):
		button.pressed.connect(play_ui_click)
