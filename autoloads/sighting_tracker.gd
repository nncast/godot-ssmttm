extends Node

## Autoload singleton. Answers one question for the whole Tubig team:
## "is ANY of us looking at the Sili right now?"
##
## Each Tubig client decides for itself whether the Sili is on its own screen
## (see tubig.gd's _can_see_sili) and reports only that boolean up to the
## server. The server ORs every report together and pushes the combined
## result back out, so the red dot on the mini-map appears the moment one
## teammate spots the Sili and vanishes the moment the last of them loses
## sight - no averaging, no lingering "last known position" timer.
##
## Only the boolean travels over the wire. Every peer already has the Sili's
## replicated position locally (see sili.tscn's MPSync), so the mini-map reads
## the position straight off the node once this flag goes true.

signal sili_spotted_changed(is_spotted: bool)

var is_sili_spotted: bool = false

## peer_id (int) -> bool. Server-side only; clients never populate this.
var _reports: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


## Call at the start of every match so a stale sighting from the previous
## round doesn't carry over.
func reset() -> void:
	_reports.clear()
	if _is_authority():
		_broadcast_spotted(false)


## Called by the locally-controlled Tubig whenever its own answer flips.
func report_sighting(seen: bool) -> void:
	if _is_networked():
		_rpc_report_sighting.rpc_id(1, seen)
	else:
		_apply_report(1, seen)


func _apply_report(peer_id: int, seen: bool) -> void:
	if seen:
		_reports[peer_id] = true
	else:
		_reports.erase(peer_id)  # absent == not seeing, keeps the dict small
	_recompute()


func _recompute() -> void:
	if not _is_authority():
		return
	var anyone_sees := not _reports.is_empty()
	if anyone_sees == is_sili_spotted:
		return
	_broadcast_spotted(anyone_sees)


func _broadcast_spotted(spotted: bool) -> void:
	if _is_networked():
		_rpc_set_spotted.rpc(spotted)
	else:
		_rpc_set_spotted(spotted)


func _on_peer_disconnected(peer_id: int) -> void:
	if _reports.erase(peer_id):
		_recompute()


func _is_networked() -> bool:
	return multiplayer.has_multiplayer_peer()


func _is_authority() -> bool:
	return not _is_networked() or multiplayer.is_server()


# --- RPCs ---

@rpc("any_peer", "call_local", "reliable")
func _rpc_report_sighting(seen: bool) -> void:
	if _is_networked() and not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()  # the host reporting on itself
	_apply_report(sender, seen)


@rpc("authority", "call_local", "reliable")
func _rpc_set_spotted(spotted: bool) -> void:
	if spotted == is_sili_spotted:
		return
	is_sili_spotted = spotted
	sili_spotted_changed.emit(spotted)
