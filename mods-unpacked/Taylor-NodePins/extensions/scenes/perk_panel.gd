extends "res://scenes/perk_panel.gd"

# Script extension for perk store panels. The Node Pins token costs
# (10/20/20/30/50) don't follow the game's cost * cost_inc^level formula,
# so override the computed cost with the fixed per-level sequence.

const NP_TOKEN_COSTS: Array[float] = [10.0, 20.0, 20.0, 30.0, 50.0]


func update_all() -> void:
	super()
	if String(name) != "node_pins":
		return
	var index: int = clampi(level, 0, NP_TOKEN_COSTS.size() - 1)
	cost = NP_TOKEN_COSTS[index]
	$Purchase / CostContainer / Label.text = Utils.print_string(cost, true)
