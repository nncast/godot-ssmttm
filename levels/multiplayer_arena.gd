extends Node2D

const SILI_SCENE: PackedScene = preload("res://entities/sili/sili.tscn")
const TUBIG_SCENE: PackedScene = preload("res://entities/tubig/tubig.tscn")
const HEART_TEXTURE: Texture2D = preload("res://icon.svg")

@onready var match_label: Label = $HUD/MatchLabel
@onready var team_panel: VBoxContainer = $HUD/TeamPanel
@onready var settings_button: Button = $HUD/SettingsButton
@onready var settings_popup: PanelContainer = $HUD/SettingsPopup
@onready var master_slider: HSlider = $HUD/SettingsPopup/VBox/MasterRow/MasterSlider
@onready var music_slider: HSlider = $HUD/SettingsPopup/VBox/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $HUD/SettingsPopup/VBox/SFXRow/SFXSlider
@onready var close_settings_button: Button = $HUD/SettingsPopup/VBox/CloseButton
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var players_container: Node2D = $PlayersContainer

var _tubig_players: Array = []

# Simple ring of spawn points around the map center; expand as the real map grows.
var _spawn_points := [
	Vector2(-40, -40), Vector2(60, 40), Vector2(-60, 60),
	Vector2(80, -60), Vector2(-90, -20), Vector2(30, 90),
]


func _ready() -> void:
	spawner.spawn_function = _spawn_player

	MatchManager.time_updated.connect(_on_time_updated)
	MatchManager.rescues_locked.connect(_on_rescues_locked)
	MatchManager.match_ended.connect(_on_match_ended)

	_setup_settings_popup()

	# Only the host decides who spawns where and starts the clock.
	if NetworkManager.is_host():
		_spawn_all_players()
		MatchManager.start_match()

	# Everyone (not just the host) needs to see the team status panel, so
	# this runs on every peer - only the win-check inside it is server-gated.
	call_deferred("_watch_tubig_team")


## Placeholder in-match settings panel - just the same Master/Music/SFX
## sliders as the main Settings screen, without leaving the match scene.
func _setup_settings_popup() -> void:
	master_slider.value = GameSettings.master_volume
	music_slider.value = GameSettings.music_volume
	sfx_slider.value = GameSettings.sfx_volume

	master_slider.value_changed.connect(GameSettings.set_master_volume)
	music_slider.value_changed.connect(GameSettings.set_music_volume)
	sfx_slider.value_changed.connect(GameSettings.set_sfx_volume)

	settings_button.pressed.connect(func(): settings_popup.visible = not settings_popup.visible)
	close_settings_button.pressed.connect(func(): settings_popup.visible = false)


func _spawn_all_players() -> void:
	var index := 0
	for peer_id in NetworkManager.roles.keys():
		var role: String = NetworkManager.roles[peer_id]
		spawner.spawn({"peer_id": peer_id, "role": role, "spawn_index": index})
		index += 1


## Runs on EVERY peer (that's the point of spawn_function) so all clients
## build the exact same node with the exact same authority, without needing
## the authority property itself to be network-replicated.
func _spawn_player(data: Dictionary) -> Node:
	var peer_id: int = data["peer_id"]
	var role: String = data["role"]
	var index: int = data.get("spawn_index", 0)

	var scene := SILI_SCENE if role == "sili" else TUBIG_SCENE
	var instance := scene.instantiate()
	instance.name = "player_%d" % peer_id
	instance.position = _spawn_points[index % _spawn_points.size()]
	instance.z_index = 0
	instance.set_multiplayer_authority(peer_id)

	if role == "tubig":
		# Heat/burning state is always server-decided, regardless of who
		# controls the Tubig's movement - see heat_status.gd's request_*() RPCs.
		var heat_status := instance.get_node("HeatStatus")
		heat_status.set_multiplayer_authority(1)

	# Only the locally-controlled character should be driving the camera.
	if peer_id != multiplayer.get_unique_id():
		var cam := instance.get_node_or_null("Camera2D")
		if cam:
			cam.enabled = false

	return instance


func _watch_tubig_team() -> void:
	await get_tree().create_timer(0.5).timeout  # let the initial spawns finish replicating
	_tubig_players = get_tree().get_nodes_in_group("tubig")
	for tubig in _tubig_players:
		var heat: HeatStatus = tubig.get_node_or_null("HeatStatus")
		if heat:
			heat.burned.connect(_check_for_sili_win)
			heat.died.connect(_check_for_sili_win)
	_build_team_panel()


## Doc section 5.2's "Team Status Panel" - one row per Tubig, sized to
## however many are actually in the match, each showing burn state and
## remaining rescue charges. Runs on every peer so everyone can read it.
func _build_team_panel() -> void:
	for child in team_panel.get_children():
		child.queue_free()

	for tubig in _tubig_players:
		var row := HBoxContainer.new()
		team_panel.add_child(row)

		var status_dot := ColorRect.new()
		status_dot.custom_minimum_size = Vector2(16, 16)
		row.add_child(status_dot)

		var hearts_row := HBoxContainer.new()
		hearts_row.add_theme_constant_override("separation", 2)
		row.add_child(hearts_row)

		var heart_icons: Array = []
		for i in 3:
			var heart := TextureRect.new()
			heart.custom_minimum_size = Vector2(14, 14)
			heart.texture = HEART_TEXTURE
			heart.expand_mode = 1
			heart.stretch_mode = 5
			hearts_row.add_child(heart)
			heart_icons.append(heart)

		var heat: HeatStatus = tubig.get_node_or_null("HeatStatus")
		var update_dot := func(new_state):
			match new_state:
				HeatStatus.State.BURNING:
					status_dot.color = Color(0.9, 0.55, 0.15)  # orange - still savable
				HeatStatus.State.DEAD:
					status_dot.color = Color(0.15, 0.15, 0.15)  # black - gone for good
				_:
					status_dot.color = Color(0.3, 0.85, 0.4)  # green - free
		if heat:
			heat.state_changed.connect(update_dot)
			update_dot.call(heat.state)

		var update_hearts := func(rescues_remaining: int):
			for i in heart_icons.size():
				heart_icons[i].modulate = Color(1, 0.25, 0.35) if i < rescues_remaining else Color(0.25, 0.25, 0.25, 0.5)
		tubig.rescues_changed.connect(update_hearts)
		update_hearts.call(tubig.rescues_left)


func _check_for_sili_win() -> void:
	if not multiplayer.is_server():
		return
	for tubig in _tubig_players:
		if not is_instance_valid(tubig):
			continue
		var heat: HeatStatus = tubig.get_node_or_null("HeatStatus")
		if heat and heat.state == HeatStatus.State.NORMAL:
			return  # at least one Tubig is still free
	MatchManager.end_match(true)


func _on_time_updated(time_remaining: float, _match_duration: float) -> void:
	var minutes := int(time_remaining) / 60
	var seconds := int(time_remaining) % 60
	match_label.text = "%d:%02d" % [minutes, seconds]


func _on_rescues_locked() -> void:
	match_label.text += "  (RESCUES LOCKED)"


func _on_match_ended(sili_won: bool) -> void:
	match_label.text = "Sili wins!" if sili_won else "Tubig survives!"
