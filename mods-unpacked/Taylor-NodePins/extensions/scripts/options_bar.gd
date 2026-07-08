extends "res://scripts/options_bar.gd"

# Script extension for the options bar (shown when nodes are selected).
# Adds a "Pin" toggle button, visible once the Node Pins perk is owned
# and exactly one placed node is selected.

var np_pin_button: Button


func _ready() -> void:
	# Build the button before super() so the base _ready() -> update_buttons()
	# call can already refresh it.
	np_pin_button = pause_button.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS) as Button
	np_pin_button.name = "NodePin"
	np_pin_button.icon = load("res://textures/icons/tether.png")
	np_pin_button.visible = false
	np_pin_button.tooltip_text = "Pin node to screen"
	$WindowOptions.add_child(np_pin_button)
	$WindowOptions.move_child(np_pin_button, pause_button.get_index() + 1)
	np_pin_button.pressed.connect(_np_on_pin_pressed)

	super()

	Signals.new_perk.connect(_np_on_new_perk)
	var manager := _np_manager()
	if manager != null:
		manager.pins_changed.connect(_np_update_pin_button)


func update_buttons() -> void:
	super()
	_np_update_pin_button()


func _np_update_pin_button() -> void:
	if np_pin_button == null:
		return

	var manager := _np_manager()
	var show := false
	var pinned := false

	if manager != null and int(Globals.perks.get("node_pins", 0)) > 0:
		if Globals.selections.size() == 1:
			var window: WindowContainer = Globals.selections[0]
			if is_instance_valid(window) and not window.closing:
				var importing: bool = "importing" in window and window.get("importing")
				if not importing:
					show = true
					pinned = manager.is_pinned(window)

	np_pin_button.visible = show
	if show:
		if pinned:
			np_pin_button.self_modulate = Color(0.55, 1.0, 0.75)
			np_pin_button.tooltip_text = "Unpin node"
		else:
			np_pin_button.self_modulate = Color(1, 1, 1)
			np_pin_button.tooltip_text = "Pin node to screen"


func _np_on_pin_pressed() -> void:
	var manager := _np_manager()
	if manager == null or Globals.selections.size() != 1:
		return
	manager.toggle_pin(Globals.selections[0])
	Sound.play("click2")
	_np_update_pin_button()


func _np_on_new_perk(perk: String, levels: int) -> void:
	if perk == "node_pins":
		_np_update_pin_button()


func _np_manager() -> Node:
	return get_tree().get_first_node_in_group("taylor_node_pins")
