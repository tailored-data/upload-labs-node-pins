extends "res://scripts/data.gd"

# Script extension for the Data autoload. After the vanilla _init() loads
# data/*.json, inject the "node_pins" perk so it shows up natively in the
# token store (tokens_tab builds perk panels dynamically from Data.perks).

const NP_MOD_ID := "Taylor-NodePins"
const NP_LOG_NAME := NP_MOD_ID + ":Data"
const NP_PERK_ID := "node_pins"


func _init() -> void:
	super()
	_np_inject_perk()


func _np_inject_perk() -> void:
	if perks.has(NP_PERK_ID):
		ModLoaderLog.warning("Perk id \"%s\" already exists, skipping injection." % NP_PERK_ID, NP_LOG_NAME)
		return

	var base_cost := 4.0
	var cost_growth := 2.0
	var max_level := 5

	var config: ModConfig = ModLoaderConfig.get_current_config(NP_MOD_ID)
	if config != null and not config.data.is_empty():
		base_cost = maxf(1.0, float(config.data.get("perk_base_cost", base_cost)))
		cost_growth = maxf(1.0, float(config.data.get("perk_cost_growth", cost_growth)))
		max_level = maxi(1, int(config.data.get("perk_max_level", max_level)))

	perks[NP_PERK_ID] = {
		"name": "Node Pins",
		"icon": "tether",
		"description": "Pin nodes to your screen as translucent overlays that stay visible while you pan around the desktop.",
		"type": 0,
		"limit": max_level,
		"currency": "token",
		"cost": base_cost,
		"cost_e": 0,
		"cost_inc": cost_growth,
		"level": 2,
		"requirement": [],
		"attributes": {},
		"window_attributes": {},
		"deprecated": false
	}

	ModLoaderLog.info(
		"Injected \"%s\" perk: max level %d, base cost %d tokens, growth x%.1f."
		% [NP_PERK_ID, max_level, int(base_cost), cost_growth],
		NP_LOG_NAME
	)
