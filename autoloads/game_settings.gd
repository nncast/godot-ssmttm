extends Node

## Autoload. Owns the persisted audio settings so they apply at boot
## (not just while the settings screen happens to be open).

const SETTINGS_PATH := "user://settings.cfg"
const MIN_DB := -80.0

var master_volume: float = 1.0
var music_volume: float = 1.0
var sfx_volume: float = 1.0


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_PATH)
	if err == OK:
		master_volume = config.get_value("audio", "master", 1.0)
		music_volume = config.get_value("audio", "music", 1.0)
		sfx_volume = config.get_value("audio", "sfx", 1.0)
	_apply_bus("Master", master_volume)
	_apply_bus("Music", music_volume)
	_apply_bus("SFX", sfx_volume)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.save(SETTINGS_PATH)


func set_master_volume(value: float) -> void:
	master_volume = value
	_apply_bus("Master", value)
	save_settings()


func set_music_volume(value: float) -> void:
	music_volume = value
	_apply_bus("Music", value)
	save_settings()


func set_sfx_volume(value: float) -> void:
	sfx_volume = value
	_apply_bus("SFX", value)
	save_settings()


func _apply_bus(bus_name: String, linear_value: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var db: float = linear_to_db(linear_value) if linear_value > 0.0 else MIN_DB
	AudioServer.set_bus_volume_db(idx, db)
