extends Node

## High-level multiplayer (built-in ENetMultiplayerPeer). Peer id 1 is
## always the host/server and is authoritative for match state (see
## match_manager.gd and heat_status.gd).
##
## Joining uses a 4-digit lobby code instead of a typed IP: the host listens
## for a UDP broadcast on DISCOVERY_PORT and replies to whoever asks for its
## code with its own address, which the client then uses to open the real
## ENet connection. This only works on the same LAN/Wi-Fi (broadcasts don't
## cross routers) - there's no internet relay/matchmaking server behind this.

const GAME_PORT: int = 7777
const DISCOVERY_PORT: int = 7778
const DISCOVERY_TIMEOUT: float = 4.0
const MAX_PLAYERS: int = 10
const ARENA_SCENE: String = "res://levels/multiplayer_arena.tscn"

signal player_list_changed
signal roles_assigned
signal connection_failed
signal server_disconnected
signal match_starting
signal lobby_code_ready(code: String)
signal code_lookup_failed

var players: Dictionary = {}  # peer_id (int) -> display name (String)
var roles: Dictionary = {}    # peer_id (int) -> "sili" or "tubig"
var my_name: String = "Player"
var lobby_code: String = ""

var _discovery_socket: PacketPeerUDP = null
var _is_discovery_host: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(_delta: float) -> void:
	if _is_discovery_host and _discovery_socket:
		_poll_discovery_requests()


func host_game(player_name: String) -> Error:
	my_name = player_name
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, MAX_PLAYERS)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	players.clear()
	roles.clear()
	players[1] = my_name  # the host is always peer id 1
	player_list_changed.emit()

	_start_discovery_host()
	return OK


## Broadcasts a "who has this code" request on the LAN and connects to
## whoever replies. Emits code_lookup_failed if nobody answers in time.
func join_by_code(code: String, player_name: String) -> void:
	my_name = player_name
	var udp := PacketPeerUDP.new()
	udp.set_broadcast_enabled(true)
	udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	udp.put_packet(("SSMTTM_DISCOVER:%s" % code).to_utf8_buffer())

	var elapsed := 0.0
	var found_ip := ""
	var expected_reply := "SSMTTM_HOST:%s" % code

	while elapsed < DISCOVERY_TIMEOUT:
		if udp.get_available_packet_count() > 0:
			var raw := udp.get_packet()
			var text := raw.get_string_from_utf8()
			if text == expected_reply:
				found_ip = udp.get_packet_ip()
				break
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	udp.close()

	if found_ip == "":
		code_lookup_failed.emit()
		return

	var err := _connect_to_ip(found_ip, player_name)
	if err != OK:
		code_lookup_failed.emit()


func leave_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	roles.clear()
	_stop_discovery_host()


func is_host() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


## Host-only. Randomly picks one connected peer to be Sili, everyone else Tubig,
## then tells every peer to load the arena scene.
func start_match() -> void:
	if not is_host() or players.size() < 2:
		return

	var peer_ids := players.keys()
	peer_ids.shuffle()
	var sili_id: int = peer_ids[0]

	roles.clear()
	for id in peer_ids:
		roles[id] = "sili" if id == sili_id else "tubig"

	_stop_discovery_host()  # match is starting, stop advertising the lobby
	_rpc_assign_roles.rpc(roles)
	_rpc_load_arena.rpc()


# --- Direct connection (used internally once a code resolves to an IP) ---

func _connect_to_ip(ip_address: String, player_name: String) -> Error:
	my_name = player_name
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip_address, GAME_PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


# --- Lobby-code discovery (host side) ---

func _start_discovery_host() -> void:
	lobby_code = "%04d" % (randi() % 10000)
	_discovery_socket = PacketPeerUDP.new()
	var err := _discovery_socket.bind(DISCOVERY_PORT)
	if err != OK:
		_discovery_socket = null
		return
	_is_discovery_host = true
	lobby_code_ready.emit(lobby_code)


func _stop_discovery_host() -> void:
	if _discovery_socket:
		_discovery_socket.close()
		_discovery_socket = null
	_is_discovery_host = false


func _poll_discovery_requests() -> void:
	while _discovery_socket.get_available_packet_count() > 0:
		var raw := _discovery_socket.get_packet()
		var text := raw.get_string_from_utf8()
		if not text.begins_with("SSMTTM_DISCOVER:"):
			continue

		var requested_code := text.substr("SSMTTM_DISCOVER:".length())
		if requested_code != lobby_code:
			continue

		var sender_ip := _discovery_socket.get_packet_ip()
		var sender_port := _discovery_socket.get_packet_port()
		_discovery_socket.set_dest_address(sender_ip, sender_port)
		_discovery_socket.put_packet(("SSMTTM_HOST:%s" % lobby_code).to_utf8_buffer())


# --- Peer lifecycle (host side) ---

func _on_peer_connected(_id: int) -> void:
	pass  # wait for their register_player() RPC so we know their chosen name


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		players.erase(id)
		if is_host():
			_rpc_update_player_list.rpc(players)
		player_list_changed.emit()


# --- Peer lifecycle (client side) ---

func _on_connected_to_server() -> void:
	var my_id := multiplayer.get_unique_id()
	_rpc_register_player.rpc_id(1, my_id, my_name)


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	players.clear()
	roles.clear()
	server_disconnected.emit()


# --- RPCs ---

@rpc("any_peer", "reliable")
func _rpc_register_player(id: int, player_name: String) -> void:
	if not is_host():
		return
	players[id] = player_name
	_rpc_update_player_list.rpc(players)


@rpc("authority", "call_local", "reliable")
func _rpc_update_player_list(new_players: Dictionary) -> void:
	players = new_players
	player_list_changed.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_assign_roles(new_roles: Dictionary) -> void:
	roles = new_roles
	roles_assigned.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_load_arena() -> void:
	match_starting.emit()
	get_tree().change_scene_to_file(ARENA_SCENE)
