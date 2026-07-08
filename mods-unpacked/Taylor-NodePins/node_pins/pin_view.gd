extends PanelContainer

# One pinned node: a live view of the real window rendered through a
# SubViewport that shares the main World2D, with its own camera locked to
# the window. Header has the node title, a settings (cog) button and an
# unpin (x) button. The settings panel adjusts opacity and size per pin.

const HEADER_ICON_SIZE := Vector2(26, 26)
const MIN_OPACITY := 0.2
const MAX_OPACITY := 1.0
const MIN_WIDTH := 180.0
const MAX_WIDTH := 480.0

var window: Control
var manager: Node
var window_key := ""
var opacity := 0.75
var view_width := 300.0

var _viewport: SubViewport
var _camera: Camera2D
var _vp_container: SubViewportContainer
var _title: Label
var _settings_panel: PanelContainer
var _last_height := 0.0


func setup(p_window: Control, p_manager: Node, p_opacity: float, p_width: float) -> void:
	window = p_window
	manager = p_manager
	window_key = String(p_window.name)
	opacity = clampf(p_opacity, MIN_OPACITY, MAX_OPACITY)
	view_width = clampf(p_width, MIN_WIDTH, MAX_WIDTH)


func _ready() -> void:
	name = "Pin_" + window_key
	mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.098, 0.122, 0.169, 0.92)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(8)
	style.set_border_width_all(1)
	style.border_color = Color(0.35, 0.45, 0.62, 0.6)
	add_theme_stylebox_override("panel", style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	var pin_icon := TextureRect.new()
	pin_icon.texture = load("res://textures/icons/tether.png")
	pin_icon.custom_minimum_size = Vector2(20, 20)
	pin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(pin_icon)

	_title = Label.new()
	_title.text = _get_window_title()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.add_theme_font_size_override("font_size", 18)
	header.add_child(_title)

	var settings_button := _make_icon_button("res://textures/icons/cog.png")
	settings_button.tooltip_text = "Pin settings"
	settings_button.pressed.connect(_on_settings_pressed)
	header.add_child(settings_button)

	var unpin_button := _make_icon_button("res://textures/icons/x.png")
	unpin_button.tooltip_text = "Unpin"
	unpin_button.pressed.connect(_on_unpin_pressed)
	header.add_child(unpin_button)

	_settings_panel = PanelContainer.new()
	_settings_panel.visible = false
	var settings_style := StyleBoxFlat.new()
	settings_style.bg_color = Color(0, 0, 0, 0.35)
	settings_style.set_corner_radius_all(8)
	settings_style.set_content_margin_all(8)
	_settings_panel.add_theme_stylebox_override("panel", settings_style)
	root.add_child(_settings_panel)

	var settings_box := VBoxContainer.new()
	settings_box.add_theme_constant_override("separation", 4)
	_settings_panel.add_child(settings_box)

	settings_box.add_child(_make_slider_row(
		"res://textures/icons/eye_ball.png", "Opacity",
		MIN_OPACITY, MAX_OPACITY, 0.05, opacity, _on_opacity_changed
	))
	settings_box.add_child(_make_slider_row(
		"res://textures/icons/zoom_in.png", "Size",
		MIN_WIDTH, MAX_WIDTH, 20.0, view_width, _on_width_changed
	))

	_vp_container = SubViewportContainer.new()
	_vp_container.stretch = true
	_vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_vp_container)

	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp_container.add_child(_viewport)
	_viewport.world_2d = get_viewport().world_2d

	_camera = Camera2D.new()
	_viewport.add_child(_camera)

	modulate.a = opacity
	_update_layout(true)


func _process(delta: float) -> void:
	if not is_instance_valid(window) or window.is_queued_for_deletion():
		set_process(false)
		manager.call("view_window_freed", window_key)
		return

	_update_layout(false)
	_update_camera()
	_title.text = _get_window_title()


func _window_world_size() -> Vector2:
	var height := 0.0
	var title_panel: Control = window.get_node_or_null("TitlePanel")
	var body_panel: Control = window.get_node_or_null("PanelContainer")
	if title_panel != null:
		height += title_panel.size.y
	if body_panel != null:
		height += body_panel.size.y
	return Vector2(maxf(window.size.x, 100.0), maxf(height, 100.0))


func _update_layout(force: bool) -> void:
	var world_size := _window_world_size()
	var aspect := clampf(world_size.y / world_size.x, 0.4, 1.6)
	var height := view_width * aspect

	if force or absf(height - _last_height) > 2.0 or absf(_vp_container.custom_minimum_size.x - view_width) > 1.0:
		_last_height = height
		_vp_container.custom_minimum_size = Vector2(view_width, height)


func _update_camera() -> void:
	var world_size := _window_world_size()
	_camera.global_position = window.global_position + world_size * 0.5

	var viewport_size := Vector2(_viewport.size)
	if viewport_size.x < 1.0 or viewport_size.y < 1.0:
		return
	var padding := 50.0
	var zoom_factor := minf(
		viewport_size.x / (world_size.x + padding),
		viewport_size.y / (world_size.y + padding)
	)
	_camera.zoom = Vector2(zoom_factor, zoom_factor)


func _get_window_title() -> String:
	var label: Label = window.get_node_or_null("TitlePanel/TitleContainer/Title")
	if label != null:
		return label.text
	return window_key


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


func _on_opacity_changed(value: float) -> void:
	opacity = clampf(value, MIN_OPACITY, MAX_OPACITY)
	modulate.a = opacity
	manager.call("pin_settings_changed", window_key, opacity, view_width)


func _on_width_changed(value: float) -> void:
	view_width = clampf(value, MIN_WIDTH, MAX_WIDTH)
	_update_layout(true)
	manager.call("pin_settings_changed", window_key, opacity, view_width)


func _on_settings_pressed() -> void:
	_settings_panel.visible = not _settings_panel.visible
	Sound.play("click_toggle2")


func _on_unpin_pressed() -> void:
	manager.call("unpin_by_key", window_key)
