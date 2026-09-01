extends Control

@onready var master_slider: HSlider = $VBox/MasterRow/MasterSlider
@onready var music_slider: HSlider = $VBox/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $VBox/SFXRow/SFXSlider
@onready var back_button: Button = $VBox/BackButton


func _ready() -> void:
	master_slider.value = GameSettings.master_volume
	music_slider.value = GameSettings.music_volume
	sfx_slider.value = GameSettings.sfx_volume

	master_slider.value_changed.connect(GameSettings.set_master_volume)
	music_slider.value_changed.connect(GameSettings.set_music_volume)
	sfx_slider.value_changed.connect(GameSettings.set_sfx_volume)
	back_button.pressed.connect(_on_back_pressed)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/title_screen/title_screen.tscn")
