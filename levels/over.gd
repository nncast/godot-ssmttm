extends TileMapLayer

@export var target_alpha: float = 0.4  # Opacity when player is behind (40%)
@export var fade_duration: float = 0.2  # Duration of the fade in seconds

var tween: Tween

func _on_canopy_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		fade_layer(target_alpha)

func _on_canopy_area_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		fade_layer(1.0)

func fade_layer(target_opacity: float) -> void:
	# Cancel active animation to avoid jittering when entering/exiting quickly
	if tween and tween.is_running():
		tween.kill()
		
	tween = create_tween()
	tween.tween_property(self, "modulate:a", target_opacity, fade_duration)
