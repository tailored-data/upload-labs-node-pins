extends "res://scripts/data.gd"

# Script extension for the Data autoload. After the vanilla _init() loads
# data/*.json, inject the Node Pins perks so they show up natively in the
# token store (tokens_tab builds perk panels dynamically from Data.perks).
#
# - "node_pins": token-cost upgrade, 5 levels. The per-level token costs
#   (10/20/20/30/50) don't fit the game's cost formula, so they are applied
#   by the perk_panel script extension; the values here are the formula
#   fallback for level 1.
# - "node_pins_slots": research-cost upgrade, +1 max pin per level, up to
#   +3 (absolute maximum 8 pins). Exponential: 1.0T, 10T, 100T research.

const NP_MOD_ID := "Taylor-NodePins"
const NP_LOG_NAME := NP_MOD_ID + ":Data"
const NP_PERK_ID := "node_pins"
const NP_SLOTS_PERK_ID := "node_pins_slots"


func _init() -> void:
	super()
	_np_inject_perks()


func _np_inject_perks() -> void:
	if perks.has(NP_PERK_ID) or perks.has(NP_SLOTS_PERK_ID):
		ModLoaderLog.warning("Node Pins perk ids already exist, skipping injection.", NP_LOG_NAME)
		return

	perks[NP_PERK_ID] = {
		"name": "Node Pins",
		"icon": "tether",
		"description": "Pin nodes to your screen as translucent overlays that stay visible while you pan around the desktop.",
		"type": 0,
		"limit": 5,
		"currency": "token",
		"cost": 10.0,
		"cost_e": 0,
		"cost_inc": 1.0,
		"level": 2,
		"requirement": [],
		"attributes": {},
		"window_attributes": {},
		"deprecated": false
	}

	perks[NP_SLOTS_PERK_ID] = {
		"name": "Extra Pin Slots",
		"icon": "plus",
		"description": "Increases the maximum number of Node Pins by 1.",
		"type": 0,
		"limit": 3,
		"currency": "research",
		"cost": 1.0,
		"cost_e": 12,
		"cost_inc": 10.0,
		"level": 2,
		"requirement": ["perk.node_pins"],
		"attributes": {},
		"window_attributes": {},
		"deprecated": false
	}

	ModLoaderLog.info(
		"Injected \"%s\" (5 levels, tokens: 10/20/20/30/50) and \"%s\" (3 levels, research from 1.0T x10)."
		% [NP_PERK_ID, NP_SLOTS_PERK_ID],
		NP_LOG_NAME
	)
