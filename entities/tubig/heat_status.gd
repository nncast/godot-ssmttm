extends Node
class_name HeatStatus

## Tracks a Tubig player's heat state.
## Touching the Sili immediately ignites (Burning) and roots the player in
## place. Only a "Tubig!" rescue channel (or, later, a cold pack) can free
## them. Attach as a child node of a Tubig CharacterBody2D.

enum State { NORMAL, BURNING }

signal state_changed(new_state: State)
signal burned  # fired the instant a tag lands
signal cooled  # fired when a rescue completes

## A property (not a plain var) on purpose: MultiplayerSynchronizer sets this
## directly via Object.set() on remote peers, bypassing ignite()/cool_fully().
## Routing through this setter means state_changed/burned/cooled fire
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


## Called by the Sili's tag hit. In multiplayer this only takes effect on the
## server; call request_ignite() from client code instead so it gets routed
## there correctly.
func ignite() -> void:
	if state == State.BURNING:
		return
	state = State.BURNING


## Called on rescue completion. Same server-only rule as ignite().
func cool_fully() -> void:
	if state == State.NORMAL:
		return
	state = State.NORMAL


func is_burning() -> bool:
	return state == State.BURNING


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
