extends "res://scripts/desktop.gd"

# Script extension for the desktop. Connection drags/drops resolve their
# target by WORLD position under the cursor — when the cursor is over a
# pin (a screen-space overlay), that world position is whatever lies
# behind the pin, so drops onto pinned nodes miss. Remap: if the mouse is
# over a pin's view, translate the cursor through the pin's camera into
# the pinned node's world space before resolving.
#
# Bonus "auto-connect": if a connection is dropped anywhere on a pin but
# not precisely on a connector, connect it to the best compatible
# connector of the pinned node.


func _on_connection_dropped(connection: String, type: int, at: Vector2) -> void:
	var pin_view: Control = _np_pin_under_mouse()
	if pin_view == null:
		super(connection, type, at)
		return

	var world_at: Vector2 = pin_view.call("mouse_to_world")
	var connector: ConnectorButton = get_connection_at(connection, type, world_at)
	if connector == null:
		connector = _np_auto_connector(pin_view, connection, type)

	if connector != null:
		if connector.type == Utils.connections_types.OUTPUT:
			Signals.create_connection.emit(connector.container.id, connection)
		elif connector.type == Utils.connections_types.INPUT:
			if connector.has_connection():
				Signals.delete_connection.emit(connector.container.input_id, connector.container.id)
			Signals.create_connection.emit(connection, connector.container.id)
		Sound.play("connect")
		cursor_connector.attached = null
	else:
		super(connection, type, world_at)


func _on_connection_dragged(connection: String, type: int, at: Vector2) -> void:
	var pin_view: Control = _np_pin_under_mouse()
	if pin_view != null:
		at = pin_view.call("mouse_to_world")
	super(connection, type, at)


func _np_pin_under_mouse() -> Control:
	var manager: Node = get_tree().get_first_node_in_group("taylor_node_pins")
	if manager == null:
		return null
	return manager.call("pin_view_at_screen_point", get_viewport().get_mouse_position())


# Picks the connector the player most likely means when dropping a
# connection anywhere on a pin: a compatible connector of the pinned
# node, preferring ones without an existing connection.
func _np_auto_connector(pin_view: Control, connection: String, type: int) -> ConnectorButton:
	var resource: ResourceContainer = get_resource(connection)
	if resource == null:
		return null
	var window: Control = pin_view.get("window")
	if not is_instance_valid(window) or "containers" not in window:
		return null

	var best: ConnectorButton = null
	for container in window.get("containers"):
		if not is_instance_valid(container):
			continue
		for connector_name: String in ["InputConnector", "OutputConnector"]:
			var connector: ConnectorButton = container.get_node_or_null(connector_name)
			if connector == null or connector.disabled or not connector.is_visible_in_tree():
				continue
			if not connector.can_connect(resource, type):
				continue
			if best == null:
				best = connector
			elif best.has_connection() and not connector.has_connection():
				best = connector
	return best
