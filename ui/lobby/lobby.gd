extends Control

@onready var code_label: Label = $VBox/CodeLabel
@onready var player_list: ItemList = $VBox/PlayerList
@onready var start_button: Button = $VBox/StartButton
@onready var leave_button: Button = $VBox/LeaveButton
@onready var status_label: Label = $VBox/StatusLabel


func _ready() -> void:
	NetworkManager.player_list_changed.connect(_refresh_player_list)
	NetworkManager.lobby_code_ready.connect(_on_lobby_code_ready)
	NetworkManager.server_disconnected.connect(_on_disconnected)

	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)

	status_label.text = ""

	if NetworkManager.is_host():
		code_label.text = "Lobby Code: %s" % NetworkManager.lobby_code
		start_button.visible = true
	else:
		code_label.text = "Joined lobby"
		start_button.visible = false

	_refresh_player_list()


func _on_lobby_code_ready(code: String) -> void:
	code_label.text = "Lobby Code: %s" % code


func _refresh_player_list() -> void:
	player_list.clear()
	for id in NetworkManager.players.keys():
		var suffix := " (host)" if id == 1 else ""
		player_list.add_item(str(NetworkManager.players[id]) + suffix)

	if NetworkManager.is_host():
		start_button.disabled = NetworkManager.players.size() < 2


func _on_start_pressed() -> void:
	if NetworkManager.players.size() < 2:
		status_label.text = "Need at least 2 players to start."
		return
	NetworkManager.start_match()


func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://ui/title_screen/title_screen.tscn")


func _on_disconnected() -> void:
	get_tree().change_scene_to_file("res://ui/title_screen/title_screen.tscn")
