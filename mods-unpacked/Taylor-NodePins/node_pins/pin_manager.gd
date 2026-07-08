extends Node

# Owns the pin layer (a CanvasLayer that draws under the game HUD, since
# autoloads precede the Main scene in the tree) and the lifecycle of all
# pinned node views. Pin capacity is gated by the "node_pins" perk level.
# Pins are free-floating windows titled "Node Pin #N" that spawn at the
# top-center of the screen and can be dragged anywhere.

signal pins_changed

const MOD_ID := "Taylor-NodePins"
const LOG_NAME := MOD_ID + ":Manager"
const PERK_ID := "node_pins"
const STATE_PATH := "user://taylor_node_pins.json"

const PinViewScript := preload("res://mods-unpacked/Taylor-NodePins/node_pins/pin_view.gd")

var canvas: CanvasLayer
var pin_layer: Control
var views: Dictionary = {}
var saved_state: Dictionary = {}
var restoring := false

var default_opacity := 0.75
var default_scale := 0.6

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

	pin_layer = Control.new()
	pin_layer.name = "PinLayer"
	pin_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pin_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(pin_layer)

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

	ModLoaderLog.info("Pin manager online (defaults: opacity %.2f, scale %.2f)." % [default_opacity, default_scale], LOG_NAME)

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

	var merged := {
		"opacity": default_opacity,
		"scale": default_scale,
	}
	merged.merge(settings, true)

	var view: PanelContainer = PinViewScript.new()
	view.setup(window, self, _next_pin_number(), merged)
	pin_layer.add_child(view)
	views[key] = view

	if not restoring:
		Sound.play("select")

	ModLoaderLog.debug("Pinned \"%s\" as Node Pin #%d (%d/%d slots)." % [key, view.pin_number, pin_count(), capacity()], LOG_NAME)
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


func pin_settings_changed(key: String, settings: Dictionary) -> void:
	saved_state[key] = settings
	_schedule_write()


func _next_pin_number() -> int:
	var used: Array[int] = []
	for view: Node in views.values():
		if is_instance_valid(view):
			used.append(int(view.pin_number))
	var number := 1
	while used.has(number):
		number += 1
	return number


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
		default_scale = clampf(float(config.data.get("default_pin_scale", default_scale)), 0.2, 2.0)


func _load_state() -> void:
	if not FileAccess.file_exists(STATE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STATE_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		saved_state = parsed


func _schedule_write() -> void:
	if _write_timer != null:
		_write_timer.start()


# End-to-end exercise of the pin connection flow, enabled by setting the
# environment variable NODEPINS_SELFTEST=1. Finds a compatible output ->
# input connector pair on two different nodes, pins both, performs the
# connection entirely through the pin views, verifies it, then deletes it
# again — so the savegame is left exactly as it was. Uses a runtime
# capacity override instead of granting perk levels.
func _run_self_test() -> void:
	await get_tree().create_timer(3.0).timeout
	_test_capacity = 99
	ModLoaderLog.info("[selftest] capacity=%d pin_count=%d" % [capacity(), pin_count()], LOG_NAME)

	var source_connector: Control = null
	var target_connector: Control = null
	var windows: Array[Node] = get_tree().get_nodes_in_group("window")

	for w: Node in windows:
		if "containers" not in w or w.get("closing"):
			continue
		for c in w.get("containers"):
			if not is_instance_valid(c):
				continue
			var out: Control = c.get_node_or_null("OutputConnector")
			if out == null or out.get("disabled") or not out.is_visible_in_tree():
				continue
			for w2: Node in windows:
				if w2 == w or "containers" not in w2 or w2.get("closing"):
					continue
				for c2 in w2.get("containers"):
					if not is_instance_valid(c2):
						continue
					var inp: Control = c2.get_node_or_null("InputConnector")
					if inp == null or inp.get("disabled") or not inp.is_visible_in_tree():
						continue
					if inp.call("has_connection"):
						continue
					if not inp.call("can_connect", c, Utils.connections_types.OUTPUT):
						continue
					source_connector = out
					target_connector = inp
					break
				if target_connector != null:
					break
			if target_connector != null:
				break
		if target_connector != null:
			break

	if source_connector == null or target_connector == null:
		ModLoaderLog.warning("[selftest] No compatible unconnected connector pair found; skipping connection test.", LOG_NAME)
		_test_capacity = 0
		return

	var source_window := _window_ancestor_of(source_connector)
	var target_window := _window_ancestor_of(target_connector)
	var source_was_pinned := is_pinned(source_window)
	var target_was_pinned := is_pinned(target_window)
	pin(source_window)
	pin(target_window)
	await get_tree().create_timer(1.0).timeout

	var view_a: Node = views.get(String(source_window.name))
	var view_b: Node = views.get(String(target_window.name))
	if view_a == null or view_b == null:
		ModLoaderLog.warning("[selftest] Pin views missing, aborting.", LOG_NAME)
		_test_capacity = 0
		return

	# Verify the view -> world coordinate mapping round-trips.
	var out_center: Vector2 = source_connector.get_global_rect().get_center()
	var viewport_size: Vector2 = Vector2(view_a._viewport.size)
	var view_pos: Vector2 = (out_center - view_a._camera.global_position) * view_a._camera.zoom.x + viewport_size * 0.5
	var mapping_error: float = view_a._view_to_world(view_pos).distance_to(out_center)
	ModLoaderLog.info("[selftest] view->world mapping error: %.3f px" % mapping_error, LOG_NAME)

	# Click the source node's OUTPUT through pin A.
	var handled: bool = view_a._dispatch_world_click(out_center)
	ModLoaderLog.info("[selftest] output click through pin A: handled=%s connecting=\"%s\" (expected \"%s\")" % [str(handled), Globals.connecting, source_connector.get("container").get("id")], LOG_NAME)

	await get_tree().create_timer(0.5).timeout

	# Click the target node's INPUT through pin B to complete the connection.
	var in_center: Vector2 = target_connector.get_global_rect().get_center()
	handled = view_b._dispatch_world_click(in_center)
	await get_tree().create_timer(0.5).timeout

	var source_id: String = source_connector.get("container").get("id")
	var target_container = target_connector.get("container")
	var target_id: String = target_container.get("id")
	var connected: bool = target_container.get("input_id") == source_id
	ModLoaderLog.info("[selftest] input click through pin B: handled=%s -> target input_id=\"%s\" (expected \"%s\")" % [str(handled), target_container.get("input_id"), source_id], LOG_NAME)

	# Cleanup: remove the test connection and any test pins, reset state.
	if connected:
		Signals.delete_connection.emit(source_id, target_id)
		await get_tree().create_timer(0.5).timeout
		ModLoaderLog.info("[selftest] cleanup: connection deleted, target input_id=\"%s\"" % target_container.get("input_id"), LOG_NAME)
	Globals.set_connecting("", 0)
	if not source_was_pinned:
		unpin_by_key(String(source_window.name))
	if not target_was_pinned:
		unpin_by_key(String(target_window.name))
	_test_capacity = 0

	if connected:
		ModLoaderLog.info("[selftest] CONNECTION THROUGH PINS PASSED", LOG_NAME)
	else:
		ModLoaderLog.error("[selftest] CONNECTION THROUGH PINS FAILED", LOG_NAME)


func _window_ancestor_of(node: Node) -> Control:
	var current: Node = node
	while current != null:
		if current.is_in_group("window"):
			return current
		current = current.get_parent()
	return null


func _write_state() -> void:
	var file: FileAccess = FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file == null:
		ModLoaderLog.warning("Could not write pin state to %s" % STATE_PATH, LOG_NAME)
		return
	file.store_string(JSON.stringify(saved_state))
