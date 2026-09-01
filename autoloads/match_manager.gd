extends Node

## Autoload singleton. Tracks the 2-minute match timer and the
## rescue-lock phase (rescues disabled in the final 25% of the match).
## In multiplayer, only the server (peer id 1) runs the countdown; it
## pushes updates out to everyone else via RPC. In single-player/local
## testing (no multiplayer peer set up) it just runs locally.

@export var MATCH_DURATION: float = 120.0
@export var RESCUE_LOCK_FRACTION: float = 0.75  # rescues disabled after this fraction of time elapses
@export var SYNC_INTERVAL: float = 0.25  # how often the server broadcasts the timer, in seconds

signal time_updated(time_remaining: float, match_duration: float)
signal rescues_locked
signal match_started
signal match_ended(sili_won: bool)

var time_remaining: float = 0.0
var is_running: bool = false
var are_rescues_locked: bool = false
var _sync_accumulator: float = 0.0


func _is_networked() -> bool:
	return multiplayer.has_multiplayer_peer()


func _is_authority() -> bool:
	return not _is_networked() or multiplayer.is_server()


func start_match() -> void:
	if not _is_authority():
		return
	time_remaining = MATCH_DURATION
	is_running = true
	are_rescues_locked = false

	if _is_networked():
		_rpc_start_match.rpc(MATCH_DURATION)
	else:
		match_started.emit()
		time_updated.emit(time_remaining, MATCH_DURATION)


func _process(delta: float) -> void:
	if not is_running or not _is_authority():
		return

	time_remaining = max(0.0, time_remaining - delta)

	if _is_networked():
		_sync_accumulator += delta
		if _sync_accumulator >= SYNC_INTERVAL:
			_sync_accumulator = 0.0
			_rpc_time_update.rpc(time_remaining)
	else:
		time_updated.emit(time_remaining, MATCH_DURATION)

	if not are_rescues_locked and time_remaining <= MATCH_DURATION * (1.0 - RESCUE_LOCK_FRACTION):
		are_rescues_locked = true
		if _is_networked():
			_rpc_rescues_locked.rpc()
		else:
			rescues_locked.emit()

	if time_remaining <= 0.0:
		end_match(false)  # Tubig survives to the buzzer


func end_match(sili_won: bool) -> void:
	if not is_running or not _is_authority():
		return
	is_running = false

	if _is_networked():
		_rpc_match_ended.rpc(sili_won)
	else:
		match_ended.emit(sili_won)


func rescues_available() -> bool:
	return is_running and not are_rescues_locked


# --- Network broadcast handlers (run on every peer, including the server via call_local) ---

@rpc("authority", "call_local", "reliable")
func _rpc_start_match(duration: float) -> void:
	is_running = true
	are_rescues_locked = false
	time_remaining = duration
	match_started.emit()
	time_updated.emit(time_remaining, duration)


@rpc("authority", "call_local", "unreliable")
func _rpc_time_update(remaining: float) -> void:
	time_remaining = remaining
	time_updated.emit(time_remaining, MATCH_DURATION)


@rpc("authority", "call_local", "reliable")
func _rpc_rescues_locked() -> void:
	are_rescues_locked = true
	rescues_locked.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_match_ended(sili_won: bool) -> void:
	is_running = false
	match_ended.emit(sili_won)
