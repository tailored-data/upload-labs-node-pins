extends PanelContainer

# One pinned node: an interactive live view of the real window rendered
# through a SubViewport that shares the main World2D, with its own camera
# locked to the window. Input over the view is forwarded into the shared
# world, so the node's inputs/outputs stay fully usable while pinned.
#
# The pin window is draggable by its header, titled "Node Pin #N", tints
# the real node with a cycleable vibrant color, and sizes itself relative
# to the node's own dimensions (pin_scale x node size, plus padding).

const MIN_OPACITY := 0.2
const MAX_OPACITY := 1.0
const MIN_SCALE := 0.2
const MAX_SCALE := 2.0
const PADDING := 16.0
const HEADER_ICON_SIZE := Vector2(26, 26)

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
var opacity := 0.75
var pin_scale := 0.6
var color_index := 0

var _viewport: SubViewport
var _camera: Camera2D
var _vp_container: SubViewportContainer
var _title: Label
var _settings_panel: PanelContainer
var _scale_edit: LineEdit
var _panel_style: StyleBoxFlat
var _saved_position := Vector2.INF
var _dragging := false
var _drag_offset := Vector2.ZERO


func setup(p_window: Control, p_manager: Node, p_number: int, settings: Dictionary = {}) -> void:
	window = p_window
	manager = p_manager
	window_key = String(p_window.name)
	pin_number = p_number
	opacity = clampf(float(settings.get("opacity", opacity)), MIN_OPACITY, MAX_OPACITY)
	pin_scale = clampf(float(settings.get("scale", pin_scale)), MIN_SCALE, MAX_SCALE)
	color_index = clampi(int(settings.get("color", 0)), 0, PIN_COLORS.size() - 1)
	if settings.has("x") and settings.has("y"):
		_saved_position = Vector2(float(settings.x), float(settings.y))


func get_settings() -> Dictionary:
	return {
		"opacity": opacity,
		"scale": pin_scale,
		"color": color_index,
		"x": position.x,
		"y": position.y,
	}


func _ready() -> void:
	name = "Pin" + str(pin_number)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.098, 0.122, 0.169, 0.92)
	_panel_style.set_corner_radius_all(10)
	_panel_style.set_content_margin_all(8)
	_panel_style.set_border_width_all(2)
	add_theme_stylebox_override("panel", _panel_style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
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

	settings_box.add_child(_make_opacity_row())
	settings_box.add_child(_make_scale_row())

	_vp_container = SubViewportContainer.new()
	_vp_container.stretch = true
	_vp_container.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_vp_container)

	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.gui_disable_input = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp_container.add_child(_viewport)
	_viewport.world_2d = get_viewport().world_2d

	_camera = Camera2D.new()
	_viewport.add_child(_camera)

	modulate.a = opacity
	_apply_color()
	_update_layout(true)
	_init_position.call_deferred()


func _exit_tree() -> void:
	# Return the node to its vanilla tint when the pin goes away.
	if is_instance_valid(window):
		window.modulate = window.call("get_color")


func _process(delta: float) -> void:
	if not is_instance_valid(window) or window.is_queued_for_deletion():
		set_process(false)
		manager.call("view_window_freed", window_key)
		return

	_update_layout(false)
	_update_camera()
	_apply_window_tint()


func _init_position() -> void:
	# Runs one frame after _ready so the container layout has resolved and
	# our size is known. New pins appear at the top-center of the screen;
	# restored pins return to where the player left them.
	await get_tree().process_frame
	var viewport_size := get_viewport_rect().size
	if _saved_position != Vector2.INF:
		position = _saved_position
	else:
		position = Vector2(
			(viewport_size.x - size.x) * 0.5 + float(pin_number - 1) * 36.0,
			16.0 + float(pin_number - 1) * 36.0
		)
	_clamp_to_screen()
	manager.call("pin_settings_changed", window_key, get_settings())


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
	# The pin view scales with the node itself: node size x pin_scale,
	# plus even padding, clamped so huge nodes cannot flood the screen.
	var world_size := _window_world_size()
	var desired := world_size * pin_scale + Vector2(PADDING, PADDING) * 2.0
	var max_size := get_viewport_rect().size * 0.45
	desired = desired.clamp(Vector2(140, 100), max_size)

	if force or (desired - _vp_container.custom_minimum_size).length() > 3.0:
		_vp_container.custom_minimum_size = desired
		reset_size()


func _update_camera() -> void:
	var world_size := _window_world_size()
	_camera.global_position = window.global_position + world_size * 0.5

	var viewport_size := Vector2(_viewport.size)
	if viewport_size.x < 1.0 or viewport_size.y < 1.0:
		return
	var zoom_factor := minf(
		(viewport_size.x - PADDING * 2.0) / world_size.x,
		(viewport_size.y - PADDING * 2.0) / world_size.y
	)
	zoom_factor = maxf(zoom_factor, 0.01)
	_camera.zoom = Vector2(zoom_factor, zoom_factor)


func _apply_color() -> void:
	var tint := PIN_COLORS[color_index]
	_panel_style.border_color = tint
	_apply_window_tint()


func _apply_window_tint() -> void:
	if is_instance_valid(window):
		var base: Color = window.call("get_color")
		window.modulate = base * PIN_COLORS[color_index]


func _clamp_to_screen() -> void:
	var viewport_size := get_viewport_rect().size
	position = position.clamp(Vector2.ZERO, (viewport_size - size).max(Vector2.ZERO))


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


func _make_icon_button(icon_path: String) -> Button:
	var button := Button.new()
	button.flat = true
	button.custom_minimum_size = HEADER_ICON_SIZE
	button.expand_icon = true
	button.icon = load(icon_path)
	button.focus_mode = Control.FOCUS_NONE
	return button


func _make_opacity_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var icon := TextureRect.new()
	icon.texture = load("res://textures/icons/eye_ball.png")
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.tooltip_text = "Opacity"
	row.add_child(icon)

	var slider := HSlider.new()
	slider.min_value = MIN_OPACITY
	slider.max_value = MAX_OPACITY
	slider.step = 0.05
	slider.value = opacity
	slider.custom_minimum_size = Vector2(150, 18)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(_on_opacity_changed)
	row.add_child(slider)

	return row


func _make_scale_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var icon := TextureRect.new()
	icon.texture = load("res://textures/icons/zoom_in.png")
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.tooltip_text = "Scale"
	row.add_child(icon)

	_scale_edit = LineEdit.new()
	_scale_edit.text = String.num(pin_scale, 2)
	_scale_edit.custom_minimum_size = Vector2(80, 0)
	_scale_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale_edit.tooltip_text = "Pin scale (%.1f - %.1f)" % [MIN_SCALE, MAX_SCALE]
	_scale_edit.text_submitted.connect(func(_text: String) -> void: _on_scale_save())
	row.add_child(_scale_edit)

	var save_button := _make_icon_button("res://textures/icons/save.png")
	save_button.tooltip_text = "Save scale"
	save_button.pressed.connect(_on_scale_save)
	row.add_child(save_button)

	return row


func _on_opacity_changed(value: float) -> void:
	opacity = clampf(value, MIN_OPACITY, MAX_OPACITY)
	modulate.a = opacity
	manager.call("pin_settings_changed", window_key, get_settings())


func _on_scale_save() -> void:
	var text := _scale_edit.text.strip_edges()
	if not text.is_valid_float():
		_scale_edit.text = String.num(pin_scale, 2)
		Sound.play("error")
		return

	pin_scale = clampf(text.to_float(), MIN_SCALE, MAX_SCALE)
	_scale_edit.text = String.num(pin_scale, 2)
	_update_layout(true)
	_clamp_to_screen.call_deferred()
	manager.call("pin_settings_changed", window_key, get_settings())
	Sound.play("click2")


func _on_color_pressed() -> void:
	color_index = (color_index + 1) % PIN_COLORS.size()
	_apply_color()
	manager.call("pin_settings_changed", window_key, get_settings())
	Sound.play("click_toggle2")


func _on_settings_pressed() -> void:
	_settings_panel.visible = not _settings_panel.visible
	Sound.play("click_toggle2")


func _on_unpin_pressed() -> void:
	manager.call("unpin_by_key", window_key)
