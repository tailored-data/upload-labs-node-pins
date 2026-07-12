extends Node

# Owns the pin layer (a CanvasLayer that draws under the game HUD, since
# autoloads precede the Main scene in the tree) and the lifecycle of all
# pinned node views. Pin capacity is gated by the "node_pins" perk level.
# Pins are free-floating windows titled "Node Pin #N" that spawn at the
# top-center of the screen and can be dragged anywhere.

signal pins_changed
signal favorites_changed

const MOD_ID := "Taylor-NodePins"
const LOG_NAME := MOD_ID + ":Manager"
const PERK_ID := "node_pins"
const SLOTS_PERK_ID := "node_pins_slots"
const STATE_PATH := "user://taylor_node_pins.json"
const FAVORITES_STATE_KEY := "__favorites"
const FAVORITES_PER_COLOR := 2
const FAVORITES_PER_SLOT := 2

const PinViewScript := preload("res://mods-unpacked/Taylor-NodePins/node_pins/pin_view.gd")

var canvas: CanvasLayer
var pin_layer: Control
var views: Dictionary = {}
var saved_state: Dictionary = {}
var restoring := false

# Favorites: window name -> color index; each gets a small colored dot on
# the true node in the world, and page-indicator circles on same-color pins.
var favorites: Dictionary = {}
var favorite_dots: Dictionary = {}
var favorite_windows: Dictionary = {}

var default_scale := 0.6

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

	ModLoaderLog.info("Pin manager online (default scale %.2f)." % default_scale, LOG_NAME)


func capacity() -> int:
	return int(Globals.perks.get(PERK_ID, 0)) + int(Globals.perks.get(SLOTS_PERK_ID, 0))


# Used by the desktop script extension to remap connection drags/drops
# that happen over a pin.
func pin_view_at_screen_point(point: Vector2) -> Control:
	if not canvas.visible:
		return null
	for view: Node in views.values():
		if is_instance_valid(view) and view.call("view_contains_screen_point", point):
			return view
	return null


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

	var merged := settings.duplicate()
	# Pin scale is a global config value, not a per-pin setting (older state
	# files may still carry a per-pin "scale" key — always override it).
	merged["scale"] = default_scale

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
		view.call("play_outro")
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
		view.call("play_outro")
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
	var key := String(window.name)
	unpin_by_key(key)
	if favorites.has(key):
		favorites.erase(key)
		_remove_dot(key)
		_schedule_write()
		favorites_changed.emit()


func _on_screen_set(screen: int) -> void:
	canvas.visible = screen == 0


func _on_reboot() -> void:
	for key: String in views.keys():
		var view: Node = views[key]
		if is_instance_valid(view):
			view.queue_free()
	views.clear()
	# Dots live in the desktop scene, which is being torn down.
	favorite_dots.clear()
	favorite_windows.clear()
	pins_changed.emit()


func _on_desktop_ready() -> void:
	_restore_pins.call_deferred()
	_restore_favorite_dots.call_deferred()


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
		default_scale = clampf(float(config.data.get("default_pin_scale", default_scale)), 0.2, 2.0)


func _load_state() -> void:
	if not FileAccess.file_exists(STATE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STATE_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		saved_state = parsed
		var stored_favorites: Variant = saved_state.get(FAVORITES_STATE_KEY)
		saved_state.erase(FAVORITES_STATE_KEY)
		if typeof(stored_favorites) == TYPE_DICTIONARY:
			for key: String in stored_favorites:
				favorites[key] = int(stored_favorites[key])


func _schedule_write() -> void:
	if _write_timer != null:
		_write_timer.start()


func _write_state() -> void:
	var file: FileAccess = FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file == null:
		ModLoaderLog.warning("Could not write pin state to %s" % STATE_PATH, LOG_NAME)
		return
	var out := saved_state.duplicate()
	out[FAVORITES_STATE_KEY] = favorites
	file.store_string(JSON.stringify(out))


# --- Favorites -----------------------------------------------------------

func is_favorite(key: String) -> bool:
	return favorites.has(key)


func favorites_of_color(color: int) -> Array:
	var result: Array = []
	for key: String in favorites:
		if int(favorites[key]) == color:
			result.append(key)
	return result


func toggle_favorite(key: String, color: int) -> void:
	if favorites.has(key):
		favorites.erase(key)
		_remove_dot(key)
		Sound.play("close")
	else:
		if favorites_of_color(color).size() >= FAVORITES_PER_COLOR:
			Signals.notify.emit("star", "Only %d favorites per color" % FAVORITES_PER_COLOR)
			Sound.play("error")
			return
		if favorites.size() >= capacity() * FAVORITES_PER_SLOT:
			Signals.notify.emit("star", "All favorite slots are in use")
			Sound.play("error")
			return
		favorites[key] = color
		var window := _find_window(key)
		if window != null:
			_create_dot(key, color, window)
		Sound.play("select")
	_schedule_write()
	favorites_changed.emit()


# Swaps which node a pin views: smooth camera pan inside the pin, and the
# pin's key, persistence entry, frame, and interaction move to the target.
func request_swap(view: Control, target_key: String) -> void:
	if views.has(target_key):
		Signals.notify.emit("tether", "That node is already pinned")
		Sound.play("error")
		return
	var target := _find_window(target_key)
	if target == null:
		# Stale favorite (node no longer exists): drop it.
		if favorites.has(target_key):
			favorites.erase(target_key)
			_remove_dot(target_key)
			_schedule_write()
			favorites_changed.emit()
		return

	var old_key: String = view.get("window_key")
	views.erase(old_key)
	views[target_key] = view
	if saved_state.has(old_key):
		saved_state[target_key] = saved_state[old_key]
		saved_state.erase(old_key)
		_schedule_write()
	view.call("retarget", target)
	pins_changed.emit()


func _create_dot(key: String, color: int, window: Control) -> void:
	_remove_dot(key)
	var dot := Panel.new()
	dot.name = "NodePinFavDot_" + key
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.z_index = 2
	dot.size = Vector2(20, 20)
	var style := StyleBoxFlat.new()
	style.bg_color = PinViewScript.PIN_COLORS[clampi(color, 0, PinViewScript.PIN_COLORS.size() - 1)]
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.border_color = Color(0.098, 0.122, 0.169, 1.0)
	dot.add_theme_stylebox_override("panel", style)
	Globals.desktop.add_child(dot)
	favorite_dots[key] = dot
	favorite_windows[key] = window


func _remove_dot(key: String) -> void:
	var dot: Node = favorite_dots.get(key)
	if dot != null and is_instance_valid(dot):
		dot.queue_free()
	favorite_dots.erase(key)
	favorite_windows.erase(key)


func _restore_favorite_dots() -> void:
	var dropped: Array[String] = []
	for key: String in favorites:
		var window := _find_window(key)
		if window != null:
			_create_dot(key, int(favorites[key]), window)
		else:
			dropped.append(key)
	for key: String in dropped:
		favorites.erase(key)
	if not dropped.is_empty():
		_schedule_write()
	favorites_changed.emit()


# Keep favorite dots glued to their nodes: vertically centered in the
# title bar, just inside its right edge.
func _process(_delta: float) -> void:
	for key: String in favorite_dots:
		var dot: Control = favorite_dots[key]
		var window: Control = favorite_windows.get(key)
		if is_instance_valid(dot) and is_instance_valid(window):
			var title_height := 44.0
			var title: Control = window.get_node_or_null("TitlePanel")
			if title != null:
				title_height = title.size.y
			dot.global_position = window.global_position + Vector2(
				window.size.x - dot.size.x - 14.0,
				(title_height - dot.size.y) * 0.5
			)
