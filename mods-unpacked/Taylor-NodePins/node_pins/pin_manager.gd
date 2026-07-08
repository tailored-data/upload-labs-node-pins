extends Node

# Owns the pin dock (a CanvasLayer that draws under the game HUD, since
# autoloads precede the Main scene in the tree) and the lifecycle of all
# pinned node views. Pin capacity is gated by the "node_pins" perk level.

signal pins_changed

const MOD_ID := "Taylor-NodePins"
const LOG_NAME := MOD_ID + ":Manager"
const PERK_ID := "node_pins"
const STATE_PATH := "user://taylor_node_pins.json"

const PinViewScript := preload("res://mods-unpacked/Taylor-NodePins/node_pins/pin_view.gd")

var canvas: CanvasLayer
var dock: VBoxContainer
var views: Dictionary = {}
var saved_state: Dictionary = {}
var restoring := false

var default_opacity := 0.75
var default_width := 300.0

# Runtime-only capacity override used by the self-test; never persisted.
var _test_capacity := 0

var _write_timer: Timer


func _ready() -> void:
	add_to_group("taylor_node_pins")
	_load_config()
	_load_state()

	canvas = CanvasLayer.new()
	canvas.name = "NodePinsCanvas"
	canvas.layer = 1
	add_child(canvas)

	dock = VBoxContainer.new()
	dock.name = "PinDock"
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	dock.offset_top = 150.0
	dock.offset_right = -12.0
	dock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	dock.grow_vertical = Control.GROW_DIRECTION_END
	dock.add_theme_constant_override("separation", 10)
	canvas.add_child(dock)

	_write_timer = Timer.new()
	_write_timer.one_shot = true
	_write_timer.wait_time = 0.5
	_write_timer.timeout.connect(_write_state)
	add_child(_write_timer)

	var lod_timer := Timer.new()
	lod_timer.wait_time = 0.25
	lod_timer.autostart = true
	lod_timer.timeout.connect(_keep_pinned_windows_awake)
	add_child(lod_timer)

	Signals.window_deleted.connect(_on_window_deleted)
	Signals.screen_set.connect(_on_screen_set)
	Signals.reboot.connect(_on_reboot)
	Signals.desktop_ready.connect(_on_desktop_ready)

	ModLoaderLog.info("Pin manager online (defaults: opacity %.2f, width %d)." % [default_opacity, int(default_width)], LOG_NAME)

	if OS.get_environment("NODEPINS_SELFTEST") == "1":
		ModLoaderLog.info("Self-test armed, waiting for desktop.", LOG_NAME)
		Signals.desktop_ready.connect(_run_self_test, CONNECT_ONE_SHOT)


func capacity() -> int:
	return maxi(int(Globals.perks.get(PERK_ID, 0)), _test_capacity)


func pin_count() -> int:
	return views.size()


func can_pin_more() -> bool:
	return pin_count() < capacity()


func is_pinned(window: Control) -> bool:
	return views.has(String(window.name))


func toggle_pin(window: Control) -> void:
	if is_pinned(window):
		unpin_by_key(String(window.name))
	else:
		pin(window)


func pin(window: Control, settings: Dictionary = {}) -> void:
	var key := String(window.name)
	if views.has(key):
		return
	if not can_pin_more():
		Signals.notify.emit("tether", "All pin slots are in use")
		Sound.play("error")
		return

	var view: PanelContainer = PinViewScript.new()
	view.setup(
		window,
		self,
		float(settings.get("opacity", default_opacity)),
		float(settings.get("width", default_width))
	)
	dock.add_child(view)
	views[key] = view

	if not restoring:
		saved_state[key] = {"opacity": view.opacity, "width": view.view_width}
		_schedule_write()
		Sound.play("select")

	ModLoaderLog.debug("Pinned \"%s\" (%d/%d slots)." % [key, pin_count(), capacity()], LOG_NAME)
	pins_changed.emit()


func unpin_by_key(key: String) -> void:
	if not views.has(key):
		return
	var view: Node = views[key]
	views.erase(key)
	if is_instance_valid(view):
		view.queue_free()
	saved_state.erase(key)
	_schedule_write()
	if not restoring:
		Sound.play("close")
	pins_changed.emit()


# Called by a PinView when its target window was freed without a delete
# signal (e.g. the whole scene rebooted). Keeps saved_state so the pin can
# be restored when the desktop loads again.
func view_window_freed(key: String) -> void:
	if not views.has(key):
		return
	var view: Node = views[key]
	views.erase(key)
	if is_instance_valid(view):
		view.queue_free()
	pins_changed.emit()


func pin_settings_changed(key: String, opacity: float, width: float) -> void:
	saved_state[key] = {"opacity": opacity, "width": width}
	_schedule_write()


func _on_window_deleted(window: WindowContainer) -> void:
	unpin_by_key(String(window.name))


func _on_screen_set(screen: int) -> void:
	canvas.visible = screen == 0


func _on_reboot() -> void:
	for key: String in views.keys():
		var view: Node = views[key]
		if is_instance_valid(view):
			view.queue_free()
	views.clear()
	pins_changed.emit()


func _on_desktop_ready() -> void:
	_restore_pins.call_deferred()


func _restore_pins() -> void:
	if saved_state.is_empty():
		return
	restoring = true
	await get_tree().create_timer(1.0).timeout

	var restored := 0
	for key: String in saved_state.keys():
		if not can_pin_more():
			break
		if views.has(key):
			continue
		var window := _find_window(key)
		if window != null:
			pin(window, saved_state[key])
			restored += 1

	restoring = false
	if restored > 0:
		ModLoaderLog.info("Restored %d pin(s) from previous session." % restored, LOG_NAME)


func _find_window(key: String) -> Control:
	for node: Node in get_tree().get_nodes_in_group("window"):
		if String(node.name) != key:
			continue
		if node is not Control:
			continue
		if node.get("closing"):
			continue
		if "importing" in node and node.get("importing"):
			continue
		return node
	return null


# The game hides window contents and stops their processing when they are
# off screen or the camera is zoomed far out. Pinned windows must stay live,
# so periodically clear those flags on them.
func _keep_pinned_windows_awake() -> void:
	for view: Node in views.values():
		if not is_instance_valid(view):
			continue
		var window: Control = view.window
		if not is_instance_valid(window):
			continue
		if window.get("out_of_screen") or window.get("is_far"):
			window.set("out_of_screen", false)
			window.set("is_far", false)
			window.call("update_visibility")
			window.call("update_processing")


func _load_config() -> void:
	var config: ModConfig = ModLoaderConfig.get_current_config(MOD_ID)
	if config != null and not config.data.is_empty():
		default_opacity = clampf(float(config.data.get("default_opacity", default_opacity)), 0.2, 1.0)
		default_width = clampf(float(config.data.get("default_pin_width", default_width)), 180.0, 480.0)


func _load_state() -> void:
	if not FileAccess.file_exists(STATE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STATE_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		saved_state = parsed


func _schedule_write() -> void:
	if _write_timer != null:
		_write_timer.start()


# End-to-end exercise of the pin lifecycle, enabled by setting the
# environment variable NODEPINS_SELFTEST=1. Uses a runtime capacity
# override instead of granting perk levels, so the savegame is untouched.
func _run_self_test() -> void:
	await get_tree().create_timer(3.0).timeout
	_test_capacity = 2
	ModLoaderLog.info("[selftest] capacity=%d pin_count=%d" % [capacity(), pin_count()], LOG_NAME)

	var target: Control = null
	for node: Node in get_tree().get_nodes_in_group("window"):
		if node is Control and not node.get("closing"):
			target = node
			break

	if target == null:
		ModLoaderLog.warning("[selftest] No window found on desktop, cannot test pinning.", LOG_NAME)
		return

	ModLoaderLog.info("[selftest] Pinning \"%s\"" % String(target.name), LOG_NAME)
	pin(target)
	ModLoaderLog.info("[selftest] is_pinned=%s pin_count=%d" % [str(is_pinned(target)), pin_count()], LOG_NAME)

	await get_tree().create_timer(1.5).timeout

	var view: Node = views.get(String(target.name))
	if view != null and is_instance_valid(view):
		var texture_size: Vector2 = view._viewport.get_texture().get_size()
		ModLoaderLog.info("[selftest] Pin viewport texture size: %s, camera zoom: %s, view opacity: %.2f" % [str(texture_size), str(view._camera.zoom), view.modulate.a], LOG_NAME)
		view._on_settings_pressed()
		view._on_opacity_changed(0.5)
		view._on_width_changed(360.0)
		ModLoaderLog.info("[selftest] Applied settings: opacity=%.2f width=%d settings_visible=%s" % [view.opacity, int(view.view_width), str(view._settings_panel.visible)], LOG_NAME)
	else:
		ModLoaderLog.warning("[selftest] Pin view missing after pin().", LOG_NAME)

	await get_tree().create_timer(1.0).timeout

	unpin_by_key(String(target.name))
	ModLoaderLog.info("[selftest] After unpin: pin_count=%d" % pin_count(), LOG_NAME)
	_test_capacity = 0
	ModLoaderLog.info("[selftest] COMPLETE", LOG_NAME)


func _write_state() -> void:
	var file: FileAccess = FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file == null:
		ModLoaderLog.warning("Could not write pin state to %s" % STATE_PATH, LOG_NAME)
		return
	file.store_string(JSON.stringify(saved_state))
