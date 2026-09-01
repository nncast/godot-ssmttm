extends Node
class_name HeatStatus

## Tracks a Tubig player's heat state.
## Touching the Sili immediately ignites (Burning) and roots the player in
## place. A "Tubig!" rescue channel (or, later, a cold pack) can free them -
## but only within BURN_TIMEOUT seconds. If nobody gets there in time, the
## burn becomes permanent (Dead): rooted for good, no longer a valid rescue
## target. Attach as a child node of a Tubig CharacterBody2D.

enum State { NORMAL, BURNING, DEAD }

@export var BURN_TIMEOUT: float = 15.0  # seconds a player can stay Burning before it's fatal

signal state_changed(new_state: State)
signal burned  # fired the instant a tag lands
signal cooled  # fired when a rescue completes
signal died    # fired when the burn timeout expires unrescued

var _burn_elapsed: float = 0.0

## A property (not a plain var) on purpose: MultiplayerSynchronizer sets this
## directly via Object.set() on remote peers, bypassing ignite()/cool_fully().
## Routing through this setter means state_changed/burned/cooled/died fire
## consistently everywhere - locally on the server AND on every client
## receiving the replicated value - instead of only on the server's screen.
var state: State = State.NORMAL:
	set(value):
		var previous := state
		state = value
		if value == previous:
			return
		state_changed.emit(value)
		if value == State.BURNING:
			burned.emit()
		elif value == State.NORMAL:
			cooled.emit()
		elif value == State.DEAD:
			died.emit()


func _process(delta: float) -> void:
	# The countdown itself is server-only logic, same rule as ignite()/
	# cool_fully() - everyone else just receives the resulting `state` via
	# replication, they never run this clock themselves.
	if _is_networked() and not is_multiplayer_authority():
		return

	if state != State.BURNING:
		_burn_elapsed = 0.0
		return

	_burn_elapsed += delta
	if _burn_elapsed >= BURN_TIMEOUT:
		die()


## Called by the Sili's tag hit. In multiplayer this only takes effect on the
## server; call request_ignite() from client code instead so it gets routed
## there correctly.
func ignite() -> void:
	if state != State.NORMAL:
		return  # already Burning or Dead, a fresh tag does nothing
	_burn_elapsed = 0.0
	state = State.BURNING


## Called on rescue completion. Same server-only rule as ignite(). Rescuing a
## Dead player isn't possible (see is_burning(), which rescue targeting uses),
## so this only ever runs against someone still Burning.
func cool_fully() -> void:
	if state != State.BURNING:
		return
	state = State.NORMAL


## The burn timed out with nobody saving them - permanent, no more rescues.
func die() -> void:
	if state != State.BURNING:
		return
	state = State.DEAD


func is_burning() -> bool:
	return state == State.BURNING


func is_dead() -> bool:
	return state == State.DEAD


## True for either Burning or Dead - both root the player in place.
func is_incapacitated() -> bool:
	return state == State.BURNING or state == State.DEAD


## --- Network entry points ---
## Any peer can call these; they no-op unless run where authoritative
## (the server), and the resulting `state` change is pushed to everyone
## by this node's MultiplayerSynchronizer (see tubig.tscn).

@rpc("any_peer", "call_local", "reliable")
func request_ignite() -> void:
	if _is_networked() and not multiplayer.is_server():
		return
	ignite()


@rpc("any_peer", "call_local", "reliable")
func request_cool_fully() -> void:
	if _is_networked() and not multiplayer.is_server():
		return
	cool_fully()


func _is_networked() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0
