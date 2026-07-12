extends PanelContainer

# One pinned node: an interactive live view of the real window rendered
# through a SubViewport that shares the main World2D, with its own camera
# locked to the window. Clicks and connection drags over the view are
# translated into world coordinates and applied to the real node.
#
# The pin window is draggable by its header, resizable by its bottom-right
# corner, titled "Node Pin #N", and marks the real node with a colored
# border frame (cycleable via the palette button). The settings (cog)
# panel adjusts render zoom (hard-limited). Pins are fully opaque.
#
# Favorites: the star button favorites the currently viewed node (dot on
# the true node in the world). A page-indicator row of circles under the
# view lists same-color favorites — filled circle = current node; click
# an empty circle to smoothly pan this pin's camera over to that node.

const MIN_ZOOM := 0.15
const MAX_ZOOM := 1.5
const PADDING := 16.0
const RESIZE_GRAB := 26.0
const MIN_VIEW_SIZE := Vector2(160.0, 120.0)
const HEADER_ICON_SIZE := Vector2(26, 26)
const BOTTOM_CLEARANCE := 130.0
# Pins render beneath the game's HUD (so menus stay on top), which means
# anything overlapping the bottom bar gets covered — keep pins above it.
const BOTTOM_UI_MARGIN := 100.0
const FAVORITE_TINT := Color(1.0, 0.9, 0.4)

const PIN_COLORS: Array[Color] = [
	Color(0.55, 0.95, 1.0),
	Color(0.65, 1.0, 0.65),
	Color(1.0, 0.85, 0.45),
	Color(1.0, 0.6, 0.85),
	Color(0.75, 0.7, 1.0),
	Color(1.0, 0.55, 0.5),
]

var window: Control
var manager: Node
var window_key := ""
var pin_number := 1
var pin_scale := 0.6
var color_index := 0
var view_size := Vector2.ZERO
var view_zoom := 0.0

var _viewport: SubViewport
var _camera: Camera2D
var _vp_container: SubViewportContainer
var _title: Label
var _settings_panel: PanelContainer
var _panel_style: StyleBoxFlat
var _frame: Panel
var _frame_style: StyleBoxFlat
var _favorite_button: Button
var _fav_strip: Control
var _fav_keys: Array[String] = []
var _saved_position := Vector2.INF
var _dragging := false
var _drag_offset := Vector2.ZERO
var _resizing := false
var _resize_start_mouse := Vector2.ZERO
var _resize_start_size := Vector2.ZERO
var _pin_connecting := false
var _swapping := false
var _closing := false


func setup(p_window: Control, p_manager: Node, p_number: int, settings: Dictionary = {}) -> void:
	window = p_window
	manager = p_manager
	window_key = String(p_window.name)
	pin_number = p_number
	pin_scale = clampf(float(settings.get("scale", pin_scale)), 0.2, 2.0)
	color_index = clampi(int(settings.get("color", 0)), 0, PIN_COLORS.size() - 1)
	if settings.has("w") and settings.has("h"):
		view_size = Vector2(float(settings.w), float(settings.h))
	if settings.has("zoom"):
		view_zoom = clampf(float(settings.zoom), MIN_ZOOM, MAX_ZOOM)
	if settings.has("x") and settings.has("y"):
		_saved_position = Vector2(float(settings.x), float(settings.y))


func get_settings() -> Dictionary:
	return {
		"color": color_index,
		"x": position.x,
		"y": position.y,
		"w": view_size.x,
		"h": view_size.y,
		"zoom": view_zoom,
	}


func _ready() -> void:
	name = "Pin" + str(pin_number)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_panel_gui_input)

	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.098, 0.122, 0.169, 1.0)
	_panel_style.set_corner_radius_all(10)
	_panel_style.set_content_margin_all(8)
	_panel_style.content_margin_bottom = 14.0
	_panel_style.content_margin_right = 14.0
	_panel_style.set_border_width_all(2)
	add_theme_stylebox_override("panel", _panel_style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var header := PanelContainer.new()
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color(0, 0, 0, 0.25)
	header_style.set_corner_radius_all(6)
	header_style.set_content_margin_all(4)
	header.add_theme_stylebox_override("panel", header_style)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	header.gui_input.connect(_on_header_gui_input)
	root.add_child(header)

	var header_box := HBoxContainer.new()
	header_box.add_theme_constant_override("separation", 4)
	header_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(header_box)

	var pin_icon := TextureRect.new()
	pin_icon.texture = load("res://textures/icons/tether.png")
	pin_icon.custom_minimum_size = Vector2(20, 20)
	pin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_box.add_child(pin_icon)

	_title = Label.new()
	_title.text = "Node Pin #%d" % pin_number
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.add_theme_font_size_override("font_size", 18)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_box.add_child(_title)

	_favorite_button = _make_icon_button("res://textures/icons/star.png")
	_favorite_button.tooltip_text = "Favorite this node"
	_favorite_button.pressed.connect(_on_favorite_pressed)
	header_box.add_child(_favorite_button)

	var color_button := _make_icon_button("res://textures/icons/palette.png")
	color_button.tooltip_text = "Cycle pin color"
	color_button.pressed.connect(_on_color_pressed)
	header_box.add_child(color_button)

	var settings_button := _make_icon_button("res://textures/icons/cog.png")
	settings_button.tooltip_text = "Pin settings"
	settings_button.pressed.connect(_on_settings_pressed)
	header_box.add_child(settings_button)

	var unpin_button := _make_icon_button("res://textures/icons/x.png")
	unpin_button.tooltip_text = "Unpin"
	unpin_button.pressed.connect(_on_unpin_pressed)
	header_box.add_child(unpin_button)

	_settings_panel = PanelContainer.new()
	_settings_panel.visible = false
	var settings_style := StyleBoxFlat.new()
	settings_style.bg_color = Color(0, 0, 0, 0.35)
	settings_style.set_corner_radius_all(8)
	settings_style.set_content_margin_all(8)
	_settings_panel.add_theme_stylebox_override("panel", settings_style)
	root.add_child(_settings_panel)

	var settings_box := VBoxContainer.new()
	settings_box.add_theme_constant_override("separation", 6)
	_settings_panel.add_child(settings_box)

	settings_box.add_child(_make_slider_row(
		"res://textures/icons/zoom_in.png", "Zoom",
		MIN_ZOOM, MAX_ZOOM, 0.05, maxf(view_zoom, MIN_ZOOM), _on_zoom_changed
	))

	_vp_container = SubViewportContainer.new()
	_vp_container.stretch = true
	_vp_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_vp_container.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# GUI input cannot be forwarded through a shared-world viewport (the
	# game's controls belong to the root viewport), so clicks on the view
	# are translated to world coordinates and dispatched manually.
	_vp_container.gui_input.connect(_on_view_gui_input)
	root.add_child(_vp_container)

	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Render only the default layer: the zoomed-out LOD icon overlay lives
	# on a separate visibility layer (see the desktop extension) so pins
	# never show the dark LOD box/icon over the node.
	_viewport.canvas_cull_mask = 1
	_vp_container.add_child(_viewport)
	_viewport.world_2d = get_viewport().world_2d

	_camera = Camera2D.new()
	_viewport.add_child(_camera)

	# Page indicator for favorites: ONE control that both draws every
	# circle and resolves clicks with the same geometry, so the visuals
	# and the hit-testing can never disagree. Filled circle = the favorite
	# currently in view; click an empty one to swap to it.
	_fav_strip = Control.new()
	_fav_strip.custom_minimum_size = Vector2(0, 22)
	_fav_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	_fav_strip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_fav_strip.tooltip_text = "Favorites: click a filled circle to swap"
	_fav_strip.visible = false
	_fav_strip.draw.connect(_on_strip_draw)
	_fav_strip.gui_input.connect(_on_strip_gui_input)
	root.add_child(_fav_strip)

	if manager.has_signal("favorites_changed"):
		manager.connect("favorites_changed", _refresh_favorites)

	_init_view_defaults()
	_vp_container.custom_minimum_size = view_size
	_create_frame()
	_apply_color()
	_refresh_favorites()
	modulate.a = 0.0
	_init_position.call_deferred()


func _exit_tree() -> void:
	_remove_frame()


func _process(delta: float) -> void:
	if not is_instance_valid(window) or window.is_queued_for_deletion():
		set_process(false)
		_remove_frame()
		manager.call("view_window_freed", window_key)
		return

	_update_camera()
	_update_frame()
	_update_resize_cursor()
	_sync_favorite_fill()


# Controls only repaint when told to. Redraw the indicator strip every
# frame so the drawn fill always reflects which node this pin is viewing
# (a handful of 20px circles; the cost is negligible).
func _sync_favorite_fill() -> void:
	if _fav_strip != null and _fav_strip.visible:
		_fav_strip.queue_redraw()


# --- Favorites -----------------------------------------------------------

func _on_favorite_pressed() -> void:
	manager.call("toggle_favorite", window_key, color_index)


# Smoothly pans this pin's camera over to another (favorited) node and
# rebinds the view, frame, and interaction to it.
func retarget(new_window: Control) -> void:
	window = new_window
	window_key = String(new_window.name)
	_swapping = true
	var target: Vector2 = window.global_position + _window_world_size() * 0.5
	var tween := create_tween()
	tween.tween_property(_camera, "global_position", target, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(func() -> void: _swapping = false)
	manager.call("pin_settings_changed", window_key, get_settings())
	_refresh_favorites()
	Sound.play("click_toggle2")


func _refresh_favorites() -> void:
	if _fav_strip == null:
		return

	# Stable order (no reordering): each circle represents one favorited
	# node, and the FILL moves between circles as the view swaps.
	_fav_keys.clear()
	for key in manager.call("favorites_of_color", color_index):
		_fav_keys.append(String(key))
	_fav_strip.visible = _fav_keys.size() > 0
	_fav_strip.queue_redraw()

	var is_favorite: bool = manager.call("is_favorite", window_key)
	_favorite_button.self_modulate = FAVORITE_TINT if is_favorite else Color(1, 1, 1)
	_favorite_button.tooltip_text = "Unfavorite this node" if is_favorite else "Favorite this node"


# One circle slot is 20px wide with 8px gaps, the whole run centered in
# the strip. Drawing and click hit-testing both use exactly this layout.
func _circle_center(index: int) -> Vector2:
	var total := float(_fav_keys.size()) * 20.0 + maxf(0.0, float(_fav_keys.size() - 1) * 8.0)
	var start_x := (_fav_strip.size.x - total) * 0.5
	return Vector2(start_x + float(index) * 28.0 + 10.0, _fav_strip.size.y * 0.5)


func _on_strip_draw() -> void:
	var circle_color := PIN_COLORS[color_index]
	for index in _fav_keys.size():
		var center := _circle_center(index)
		if _fav_keys[index] == window_key:
			_fav_strip.draw_circle(center, 7.0, circle_color)
		else:
			_fav_strip.draw_arc(center, 6.0, 0.0, TAU, 64, circle_color, 2.0, true)


func _on_strip_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		for index in _fav_keys.size():
			if event.position.distance_to(_circle_center(index)) <= 12.0:
				if _fav_keys[index] != window_key:
					manager.call("request_swap", self, _fav_keys[index])
				_fav_strip.accept_event()
				return


# Initial frame size derives from the node's own dimensions (scaled, with
# padding); the initial zoom fits the node inside that frame. Both are
# free afterwards: the user resizes the frame and zooms independently.
func _init_view_defaults() -> void:
	var world_size := _window_world_size()
	if view_size == Vector2.ZERO:
		view_size = world_size * pin_scale + Vector2(PADDING, PADDING) * 2.0
	view_size = _clamp_view_size(view_size)

	if view_zoom <= 0.0:
		view_zoom = minf(
			(view_size.x - PADDING * 2.0) / world_size.x,
			(view_size.y - PADDING * 2.0) / world_size.y
		)
	view_zoom = clampf(view_zoom, MIN_ZOOM, MAX_ZOOM)


func _clamp_view_size(desired: Vector2) -> Vector2:
	var max_size := get_viewport_rect().size * 0.55
	return desired.clamp(MIN_VIEW_SIZE, max_size.max(MIN_VIEW_SIZE))


func _init_position() -> void:
	await get_tree().process_frame
	var viewport_size := get_viewport_rect().size
	if _saved_position != Vector2.INF:
		position = _saved_position
	else:
		# Bottom-center, sitting just above the node browser bar, cascading
		# up-right for additional pins.
		position = Vector2(
			(viewport_size.x - size.x) * 0.5 + float(pin_number - 1) * 36.0,
			viewport_size.y - size.y - BOTTOM_CLEARANCE - float(pin_number - 1) * 36.0
		)
	_clamp_to_screen()
	manager.call("pin_settings_changed", window_key, get_settings())
	_play_intro()


# --- Animations -----------------------------------------------------------

func _play_intro() -> void:
	# "Fade-in slam": starts oversized and transparent, slams down to size.
	pivot_offset = size / 2.0
	scale = Vector2(1.35, 1.35)
	var tween := create_tween()
	tween.set_parallel()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.22)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.18)


func play_outro() -> void:
	# "Fade-out peel": rotates off its bottom-left corner while fading.
	if _closing:
		return
	_closing = true
	set_process(false)
	_remove_frame()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = Vector2(0.0, size.y)
	var tween := create_tween()
	tween.set_parallel()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "rotation_degrees", -14.0, 0.22)
	tween.tween_property(self, "scale", Vector2(0.7, 0.7), 0.22)
	tween.tween_property(self, "modulate:a", 0.0, 0.22)
	tween.chain().tween_callback(queue_free)


# --- Node frame (colored border on the real node) --------------------------

func _create_frame() -> void:
	if not is_instance_valid(window):
		return
	_frame = Panel.new()
	_frame.name = "NodePinFrame_" + window_key
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.z_index = 1
	_frame_style = StyleBoxFlat.new()
	_frame_style.draw_center = false
	_frame_style.set_border_width_all(6)
	_frame_style.set_corner_radius_all(14)
	_frame_style.set_expand_margin_all(6.0)
	_frame.add_theme_stylebox_override("panel", _frame_style)
	# NOT a child of $Windows: the desktop iterates $Windows children with
	# typed WindowContainer loops (update_lod, heatspot, connection lookup)
	# and a foreign Panel in there breaks them — notably update_lod, which
	# runs exactly when the player zooms out. Parent to the desktop instead.
	var desktop: Node = window.get_parent().get_parent()
	desktop.add_child(_frame)
	_update_frame()


func _update_frame() -> void:
	if _frame == null or not is_instance_valid(_frame) or not is_instance_valid(window):
		return
	_frame.global_position = window.global_position
	_frame.size = _window_world_size()


func _remove_frame() -> void:
	if _frame != null and is_instance_valid(_frame):
		_frame.queue_free()
	_frame = null


# --- Layout / camera --------------------------------------------------------

func _window_world_size() -> Vector2:
	var height := 0.0
	var title_panel: Control = window.get_node_or_null("TitlePanel")
	var body_panel: Control = window.get_node_or_null("PanelContainer")
	if title_panel != null:
		height += title_panel.size.y
	if body_panel != null:
		height += body_panel.size.y
	return Vector2(maxf(window.size.x, 100.0), maxf(height, 100.0))


func _update_camera() -> void:
	if not _swapping:
		_camera.global_position = window.global_position + _window_world_size() * 0.5
	_camera.zoom = Vector2(view_zoom, view_zoom)


# --- Interaction: clicks and connection drags over the view are mapped
# --- into the world and applied to the real node.

func _on_view_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if _pin_connecting:
				_finish_pin_drag()
				accept_event()
			elif _dispatch_world_click(_view_to_world(event.position)):
				accept_event()
	elif event is InputEventMouseMotion and event.button_mask == MOUSE_BUTTON_MASK_LEFT:
		if not _pin_connecting and Globals.connecting.is_empty():
			_try_start_pin_drag(event.position - event.relative)


# Dragging out of a connector inside the pin starts a connection, exactly
# like dragging a connector in the world.
func _try_start_pin_drag(view_pos: Vector2) -> void:
	var connector: Control = _find_connector_at(_view_to_world(view_pos))
	if connector == null:
		return
	var container = connector.get("container")
	if connector.get("type") == Utils.connections_types.INPUT and connector.call("has_connection"):
		Signals.delete_connection.emit(container.get("input_id"), container.get("id"))
	Globals.set_connecting(container.get("id"), connector.get("type"))
	Sound.play("connector")
	_pin_connecting = true


# Releasing a pin-started connection drops it at the world point under the
# cursor: inside this or another pin the desktop extension remaps it, and
# out in the open world it resolves against the main camera view.
func _finish_pin_drag() -> void:
	_pin_connecting = false
	if Globals.connecting.is_empty():
		return
	var screen_size := get_viewport_rect().size
	var mouse_screen := get_viewport().get_mouse_position()
	var world_at: Vector2 = Globals.camera_center + (mouse_screen - screen_size * 0.5) / Globals.camera_zoom.x
	var connecting_id: String = Globals.connecting
	var connecting_type: int = Globals.connection_type
	Signals.connection_droppped.emit(connecting_id, connecting_type, world_at)
	Globals.set_connecting("", 0)


func _view_to_world(view_pos: Vector2) -> Vector2:
	var viewport_size := Vector2(_viewport.size)
	return _camera.global_position + (view_pos - viewport_size * 0.5) / _camera.zoom.x


func mouse_to_world() -> Vector2:
	return _view_to_world(_vp_container.get_local_mouse_position())


func view_contains_screen_point(point: Vector2) -> bool:
	return _vp_container.get_global_rect().has_point(point)


# Applies a click at the given world point to the pinned node. Connector
# buttons (inputs/outputs) get the game's own press handling — starting,
# cancelling, or completing a connection exactly like a direct click —
# and regular buttons inside the node get pressed. Returns true if the
# click hit something.
func _dispatch_world_click(world_point: Vector2) -> bool:
	if not is_instance_valid(window):
		return false
	if Globals.tool == Utils.tools.MOVE:
		return false

	var connector: Control = _find_connector_at(world_point)
	if connector != null:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = false
		# ConnectorButton resolves the drop point as global_position +
		# event.position, so make that sum equal the world point.
		click.position = world_point - connector.global_position
		connector.call("handle_press_input", click)
		return true

	var button: BaseButton = _find_button_at(world_point)
	if button != null:
		button.pressed.emit()
		return true

	return false


func _find_connector_at(world_point: Vector2) -> Control:
	if "containers" not in window:
		return null

	var best: Control = null
	var best_distance := INF
	for container in window.get("containers"):
		if not is_instance_valid(container):
			continue
		for connector_name: String in ["InputConnector", "OutputConnector"]:
			var connector: Control = container.get_node_or_null(connector_name)
			if connector == null:
				continue
			if connector.get("disabled") or not connector.is_visible_in_tree():
				continue
			var rect: Rect2 = connector.get_global_rect().grow(8.0)
			if rect.has_point(world_point):
				var distance := rect.get_center().distance_to(world_point)
				if distance < best_distance:
					best_distance = distance
					best = connector
	return best


func _find_button_at(world_point: Vector2) -> BaseButton:
	var best: BaseButton = null
	var best_distance := INF
	for node: Node in window.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button == null or button.disabled or not button.is_visible_in_tree():
			continue
		var rect: Rect2 = button.get_global_rect()
		if rect.has_point(world_point):
			var distance := rect.get_center().distance_to(world_point)
			if distance < best_distance:
				best_distance = distance
				best = button
	return best


# --- Drag (header) and resize (bottom-right corner) -------------------------

func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = get_global_mouse_position() - global_position
		else:
			_dragging = false
			_clamp_to_screen()
			manager.call("pin_settings_changed", window_key, get_settings())
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_offset


func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _in_resize_corner(event.position):
			_resizing = true
			_resize_start_mouse = get_global_mouse_position()
			_resize_start_size = view_size
			accept_event()
		elif not event.pressed and _resizing:
			_resizing = false
			_clamp_to_screen()
			manager.call("pin_settings_changed", window_key, get_settings())
			accept_event()
	elif event is InputEventMouseMotion and _resizing:
		var delta := get_global_mouse_position() - _resize_start_mouse
		view_size = _clamp_view_size(_resize_start_size + delta)
		_vp_container.custom_minimum_size = view_size
		reset_size()


func _in_resize_corner(local_pos: Vector2) -> bool:
	return local_pos.x > size.x - RESIZE_GRAB and local_pos.y > size.y - RESIZE_GRAB


func _update_resize_cursor() -> void:
	if _resizing:
		return
	if _in_resize_corner(get_local_mouse_position()):
		mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	else:
		mouse_default_cursor_shape = Control.CURSOR_ARROW


func _clamp_to_screen() -> void:
	var viewport_size := get_viewport_rect().size
	var limit := (viewport_size - size - Vector2(0.0, BOTTOM_UI_MARGIN)).max(Vector2.ZERO)
	position = position.clamp(Vector2.ZERO, limit)


# --- UI construction and settings -------------------------------------------

func _make_icon_button(icon_path: String) -> Button:
	var button := Button.new()
	button.flat = true
	button.custom_minimum_size = HEADER_ICON_SIZE
	button.expand_icon = true
	button.icon = load(icon_path)
	button.focus_mode = Control.FOCUS_NONE
	return button


func _make_slider_row(icon_path: String, tooltip: String, min_value: float, max_value: float, step: float, value: float, callback: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var icon := TextureRect.new()
	icon.texture = load(icon_path)
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.tooltip_text = tooltip
	row.add_child(icon)

	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(150, 18)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(callback)
	row.add_child(slider)

	return row


func _apply_color() -> void:
	var tint := PIN_COLORS[color_index]
	_panel_style.border_color = tint
	if _frame_style != null:
		_frame_style.border_color = tint


func _on_zoom_changed(value: float) -> void:
	view_zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
	manager.call("pin_settings_changed", window_key, get_settings())


func _on_color_pressed() -> void:
	color_index = (color_index + 1) % PIN_COLORS.size()
	_apply_color()
	_refresh_favorites()
	manager.call("pin_settings_changed", window_key, get_settings())
	Sound.play("click_toggle2")


func _on_settings_pressed() -> void:
	_settings_panel.visible = not _settings_panel.visible
	Sound.play("click_toggle2")


func _on_unpin_pressed() -> void:
	manager.call("unpin_by_key", window_key)
