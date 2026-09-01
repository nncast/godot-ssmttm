extends Control

@onready var name_edit: LineEdit = $VBox/NameRow/NameEdit
@onready var host_button: Button = $VBox/HostButton
@onready var join_button: Button = $VBox/JoinButton
@onready var settings_button: Button = $VBox/SettingsButton
@onready var exit_button: Button = $VBox/ExitButton
@onready var status_label: Label = $VBox/StatusLabel

@onready var join_panel: PanelContainer = $JoinPanel
@onready var code_edit: LineEdit = $JoinPanel/VBox/CodeEdit
@onready var join_confirm_button: Button = $JoinPanel/VBox/ButtonsRow/JoinConfirmButton
@onready var join_cancel_button: Button = $JoinPanel/VBox/ButtonsRow/JoinCancelButton

@onready var exit_confirm: ConfirmationDialog = $ExitConfirm


func _ready() -> void:
	join_panel.visible = false
	status_label.text = ""

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

	join_confirm_button.pressed.connect(_on_join_confirm_pressed)
	join_cancel_button.pressed.connect(_on_join_cancel_pressed)

	exit_confirm.confirmed.connect(_on_exit_confirmed)

	NetworkManager.player_list_changed.connect(_on_player_list_changed)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.code_lookup_failed.connect(_on_code_lookup_failed)


func _on_host_pressed() -> void:
	var err := NetworkManager.host_game(_resolved_name())
	if err != OK:
		status_label.text = "Couldn't host (error %s)." % err
		return
	get_tree().change_scene_to_file("res://ui/lobby/lobby.tscn")


func _on_join_pressed() -> void:
	status_label.text = ""
	join_panel.visible = true


func _on_join_cancel_pressed() -> void:
	join_panel.visible = false
	join_confirm_button.disabled = false


func _on_join_confirm_pressed() -> void:
	var code := code_edit.text.strip_edges()
	if code.length() != 4 or not code.is_valid_int():
		status_label.text = "Enter the 4-digit lobby code."
		return

	status_label.text = "Looking for lobby %s..." % code
	join_confirm_button.disabled = true
	NetworkManager.join_by_code(code, _resolved_name())


## Fires once we're actually registered with the host - safe to move on.
func _on_player_list_changed() -> void:
	if not NetworkManager.is_host() and NetworkManager.players.size() > 0:
		get_tree().change_scene_to_file("res://ui/lobby/lobby.tscn")


func _on_connection_failed() -> void:
	status_label.text = "Connection failed."
	join_confirm_button.disabled = false


func _on_code_lookup_failed() -> void:
	status_label.text = "No lobby found with that code (same Wi-Fi/LAN only)."
	join_confirm_button.disabled = false


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/settings/settings.tscn")


func _on_exit_pressed() -> void:
	exit_confirm.popup_centered()


func _on_exit_confirmed() -> void:
	get_tree().quit()


func _resolved_name() -> String:
	var typed := name_edit.text.strip_edges()
	return typed if not typed.is_empty() else "Player%d" % (randi() % 1000)
