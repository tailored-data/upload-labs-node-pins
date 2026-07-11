extends Node

const MOD_NAME := "Taylor-NodePins"
const LOG_NAME := MOD_NAME + ":Main"

var mod_dir_path := ""


func _init() -> void:
	ModLoaderLog.info("Initializing", LOG_NAME)
	mod_dir_path = ModLoaderMod.get_unpacked_dir().path_join(MOD_NAME)
	var extensions_dir_path := mod_dir_path.path_join("extensions")

	ModLoaderMod.install_script_extension(extensions_dir_path.path_join("scripts/data.gd"))
	ModLoaderMod.install_script_extension(extensions_dir_path.path_join("scripts/options_bar.gd"))
	ModLoaderMod.install_script_extension(extensions_dir_path.path_join("scripts/desktop.gd"))
	ModLoaderMod.install_script_extension(extensions_dir_path.path_join("scenes/perk_panel.gd"))


func _ready() -> void:
	var manager_script: GDScript = load(mod_dir_path.path_join("node_pins/pin_manager.gd"))
	var manager: Node = manager_script.new()
	manager.name = "NodePins"
	add_child(manager)
	ModLoaderLog.info("Ready", LOG_NAME)
