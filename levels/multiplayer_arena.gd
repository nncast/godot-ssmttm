extends Node2D

const SILI_SCENE: PackedScene = preload("res://entities/sili/sili.tscn")
const TUBIG_SCENE: PackedScene = preload("res://entities/tubig/tubig.tscn")
const HEART_TEXTURE: Texture2D = preload("res://assets/ui/heart.png")

## Team-panel status circle. Blue = free, red = tagged and still savable,
## grey = burn timed out and they're gone for good.
const DOT_SIZE := 18
const TUBIG_FREE_COLOR := Color(0.24, 0.55, 0.95)
const TUBIG_TAGGED_COLOR := Color(0.88, 0.22, 0.20)
const TUBIG_DEAD_COLOR := Color(0.42, 0.42, 0.44)
const DEAD_ROW_TINT := Color(0.55, 0.55, 0.55, 0.65)

@onready var match_label: Label = $HUD/MatchLabel
@onready var team_panel: VBoxContainer = $HUD/TeamPanel
@onready var settings_button: Button = $HUD/SettingsButton
@onready var settings_popup: PanelContainer = $HUD/SettingsPopup
@onready var master_slider: HSlider = $HUD/SettingsPopup/VBox/MasterRow/MasterSlider
@onready var music_slider: HSlider = $HUD/SettingsPopup/VBox/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $HUD/SettingsPopup/VBox/SFXRow/SFXSlider
@onready var ambience_slider: HSlider = $HUD/SettingsPopup/VBox/AmbienceRow/AmbienceSlider
@onready var close_settings_button: Button = $HUD/SettingsPopup/VBox/CloseButton
@onready var sili_spawner: MultiplayerSpawner = $SiliSpawner
@onready var tubig_spawner: MultiplayerSpawner = $TubigSpawner
@onready var sili_container: Node2D = $Map/SiliContainer
@onready var tubig_container: Node2D = $Map/TubigContainer
@onready var spawn_points_root: Node2D = $Map/SpawnPoints
@onready var minimap: Control = $HUD/Minimap
@onready var threat_vignette: Control = $ThreatLayer/ThreatVignette

var _tubig_players: Array = []


## Only used if Map/SpawnPoints is missing or has no marker for a role - the
## real positions come from the SpawnPoint nodes you drag around in the editor.
## Keeping a fallback means deleting a marker mid-edit can't crash a match.
const FALLBACK_SPAWN_POINTS: Array[Vector2] = [
	Vector2(-40, -40), Vector2(60, 40), Vector2(-60, 60),
	Vector2(80, -60), Vector2(-90, -20), Vector2(30, 90),
]


func _ready() -> void:
	sili_spawner.spawn_function = _spawn_sili
	tubig_spawner.spawn_function = _spawn_tubig
	sili_spawner.spawned.connect(_on_player_spawned)
	tubig_spawner.spawned.connect(_on_player_spawned)

	MatchManager.time_updated.connect(_on_time_updated)
	MatchManager.match_ended.connect(_on_match_ended)

	_setup_settings_popup()

	# Bake the mini-map straight off the level's own tilemap, bottom-up, so it
	# can never drift out of sync with the map the players are running around
	# in. We hand it the Map node rather than one layer: build_from_node walks
	# the children itself, so every painted layer (sea, sand, grass, road,
	# buildings...) ends up in the bake.
	minimap.build_from_node($Map)

	# Only the host decides who spawns where and starts the clock.
	if NetworkManager.is_host():
		SightingTracker.reset()
		_spawn_all_players()
		MatchManager.start_match()

	# Everyone (not just the host) needs to see the team status panel, so
	# this runs on every peer - only the win-check inside it is server-gated.
	call_deferred("_refresh_team_state")


## Placeholder in-match settings panel - just the same Master/Music/SFX
## sliders as the main Settings screen, without leaving the match scene.
func _setup_settings_popup() -> void:
	master_slider.value = GameSettings.master_volume
	music_slider.value = GameSettings.music_volume
	sfx_slider.value = GameSettings.sfx_volume
	ambience_slider.value = GameSettings.ambience_volume

	master_slider.value_changed.connect(GameSettings.set_master_volume)
	music_slider.value_changed.connect(GameSettings.set_music_volume)
	sfx_slider.value_changed.connect(GameSettings.set_sfx_volume)
	ambience_slider.value_changed.connect(GameSettings.set_ambience_volume)

	settings_button.pressed.connect(func(): settings_popup.visible = not settings_popup.visible)
	close_settings_button.pressed.connect(func(): settings_popup.visible = false)


func _spawn_all_players() -> void:
	# One counter per role: the roles have separate marker lists, so a shared
	# index would leave gaps (two Tubigs would land on markers 2 and 3 when the
	# Sili took 1, never touching marker 1).
	var role_counts := {"sili": 0, "tubig": 0}
	for peer_id in NetworkManager.roles.keys():
		var role: String = NetworkManager.roles[peer_id]
		var index: int = role_counts.get(role, 0)
		role_counts[role] = index + 1
		var data := {"peer_id": peer_id, "role": role, "spawn_index": index}
		if role == "sili":
			sili_spawner.spawn(data)
		else:
			tubig_spawner.spawn(data)


## Reads the position off the matching SpawnPoint marker. Markers live in the
## scene, so every peer sees the same ones and independently works out the same
## spawn - no position needs replicating.
##
## Converted through the container rather than used raw: the marker is a child
## of Map (which is offset from the scene root), while the character is added
## under Map/SiliContainer, so a straight copy of marker.position would land the
## player one Map-offset away from the marker you dragged.
func _spawn_position_for(role: String, index: int, container: Node2D) -> Vector2:
	var markers := _markers_for(role)
	if markers.is_empty():
		return FALLBACK_SPAWN_POINTS[index % FALLBACK_SPAWN_POINTS.size()]
	var marker: SpawnPoint = markers[index % markers.size()]
	return container.to_local(marker.global_position)


func _markers_for(role: String) -> Array:
	var markers: Array = []
	if spawn_points_root == null:
		return markers
	for child in spawn_points_root.get_children():
		var marker := child as SpawnPoint
		if marker and marker.role_name() == role:
			markers.append(marker)
	return markers


## Runs on EVERY peer (that's the point of spawn_function) so all clients
## build the exact same node with the exact same authority, without needing
## the authority property itself to be network-replicated. Split into two
## thin wrappers (one per spawner) that both defer to the shared builder below.
func _spawn_sili(data: Dictionary) -> Node:
	return _build_player(data)


func _spawn_tubig(data: Dictionary) -> Node:
	return _build_player(data)


func _build_player(data: Dictionary) -> Node:
	var peer_id: int = data["peer_id"]
	var role: String = data["role"]
	var index: int = data.get("spawn_index", 0)

	var scene := SILI_SCENE if role == "sili" else TUBIG_SCENE
	var container: Node2D = sili_container if role == "sili" else tubig_container
	var instance := scene.instantiate()
	instance.name = "player_%d" % peer_id
	instance.position = _spawn_position_for(role, index, container)
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


## Fires locally on EVERY peer, the instant a spawn actually lands in their
## own scene tree - the correct way to know spawning finished, instead of
## guessing with a fixed timer that could be wrong on a slower connection
## and permanently leave the local HUD (or a teammate's team-panel row)
## unconfigured.
func _on_player_spawned(_node: Node) -> void:
	_refresh_team_state()


func _refresh_team_state() -> void:
	var previous_count := _tubig_players.size()
	_tubig_players = get_tree().get_nodes_in_group("tubig")

	for tubig in _tubig_players:
		var heat: HeatStatus = tubig.get_node_or_null("HeatStatus")
		if heat and not heat.burned.is_connected(_check_for_sili_win):
			heat.burned.connect(_check_for_sili_win)
			heat.died.connect(_check_for_sili_win)

	# Rebuilding is cheap for a handful of rows and keeps this correct no
	# matter what order peers finish spawning in.
	if _tubig_players.size() != previous_count:
		_build_team_panel()
	_configure_local_hud()


## The mini-map and the threat vignette both need to know which character on
## this screen is ours, and which side it's on - the map shows a different set
## of dots per team, and the vignette is Tubig-only.
func _configure_local_hud() -> void:
	var my_id := _local_peer_id()
	var is_sili: bool = NetworkManager.roles.get(my_id, "tubig") == "sili"
	var container := sili_container if is_sili else tubig_container
	var local_player := container.get_node_or_null("player_%d" % my_id) as Node2D

	minimap.configure(local_player, is_sili)
	threat_vignette.track_player(local_player, not is_sili)


func _local_peer_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1


## Character nodes are named "player_<peer_id>" by _build_player, which is the
## only link back from a spawned body to the name its owner typed in the lobby.
func _peer_id_for(character: Node) -> int:
	var node_name := String(character.name)
	if not node_name.begins_with("player_"):
		return 0
	return int(node_name.trim_prefix("player_"))


func _display_name_for(character: Node) -> String:
	var peer_id := _peer_id_for(character)
	if peer_id == 0:
		return "Tubig"
	return NetworkManager.players.get(peer_id, "Player %d" % peer_id)


## Doc section 5.2's "Team Status Panel" - one row per Tubig, sized to
## however many are actually in the match. Each row is a status circle and the
## player's name side by side, then their remaining rescue charges.
##
## The circle carries the state at a glance: blue while they're free, red the
## moment the Sili tags them, grey once the burn times out. Runs on every peer
## so everyone can read the same board.
func _build_team_panel() -> void:
	for child in team_panel.get_children():
		child.queue_free()

	for tubig in _tubig_players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		team_panel.add_child(row)

		# A Panel with a fully-rounded StyleBoxFlat is a real circle without
		# needing a texture asset or a custom _draw.
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
		var dot_style := StyleBoxFlat.new()
		dot_style.bg_color = TUBIG_FREE_COLOR
		dot_style.set_corner_radius_all(DOT_SIZE / 2)
		dot.add_theme_stylebox_override("panel", dot_style)
		row.add_child(dot)

		# The ONLY place a player's name appears during a match. Names are
		# deliberately never drawn above characters in-world: at a glance
		# mid-chase you should be reading team colour and nothing else, so
		# picking a target out of a scattering crowd stays a real decision.
		var name_label := Label.new()
		name_label.custom_minimum_size = Vector2(96, 0)
		name_label.text = _display_name_for(tubig)
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.clip_text = true
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_label)

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
					dot_style.bg_color = TUBIG_TAGGED_COLOR
					row.modulate = Color.WHITE
				HeatStatus.State.DEAD:
					# Grey circle plus a grey row tint: the hearts and the name
					# are near-white, so multiplying them down reads as the
					# whole entry draining to greyscale.
					dot_style.bg_color = TUBIG_DEAD_COLOR
					row.modulate = DEAD_ROW_TINT
				_:
					dot_style.bg_color = TUBIG_FREE_COLOR
					row.modulate = Color.WHITE
		if heat:
			heat.state_changed.connect(update_dot)
			update_dot.call(heat.state)

		var update_hearts := func(rescues_remaining: int):
			for i in heart_icons.size():
				heart_icons[i].modulate = Color.WHITE if i < rescues_remaining else Color(0.25, 0.25, 0.25, 0.5)
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
	# Just the clock now - tag/rescue/speed lines go to HUD/EventFeed, which has
	# room to show what actually happened instead of a bare percentage.
	match_label.text = "%d:%02d" % [minutes, seconds]





func _on_match_ended(sili_won: bool) -> void:
	match_label.text = "Sili wins!" if sili_won else "Tubig survives!"
