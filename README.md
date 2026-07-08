# Upload Labs — Node Pins

Pin your nodes to the screen. A gameplay mod for [Upload Labs](https://store.steampowered.com/app/3606890/Upload_Labs/) built on the [Godot Mod Loader](https://wiki.godotmodding.com/) that ships inside the game.

> This mod supersedes the earlier **Balance Tweaks** proof-of-concept mod.

## What it does

- **Pin any node to your screen.** Select a node and press the new pin button (⚲) in the options bar. A live, translucent copy of the node stays fixed on your screen while you pan and zoom anywhere on the desktop — perfect for keeping an eye on a Reconstructor, Verifier, or breach across the map.
- **Unlocked through normal gameplay.** "Node Pins" appears as a standard token-cost upgrade in the token store (Nodes tab). Each level adds one pin slot: level 1 costs 4 tokens, and the price doubles per level (4 → 8 → 16 → 32 → 64, max 5 slots by default).
- **Per-pin settings.** Every pinned node has its own ⚙ settings button that opens a small config panel with **opacity** (how transparent the pin is) and **size** (how large it renders) sliders, plus an ✕ button to unpin.
- **Live view, not a screenshot.** Pins render the real node through a viewport that shares the game world — progress bars, resource counts, and animations all update in real time, even when the node is far off-screen (the mod keeps pinned nodes processing despite the game's off-screen optimizations).
- **Pins persist.** Your pins and their settings are remembered across game sessions (matched by node identity, within your pin capacity).

## Installation

1. Download `Taylor-NodePins-x.y.z.zip` from the [latest release](../../releases/latest). Do **not** unzip it.
2. Find your Upload Labs install folder (Steam: right-click the game → Manage → Browse local files).
3. Create a folder named `mods` next to `Upload Labs.exe` if it doesn't exist.
4. Drop the ZIP into that `mods` folder and launch the game.

To uninstall, delete the ZIP. Saves stay fully compatible — the upgrade level simply becomes inert data that the game ignores.

## Usage

1. Reach a token income (the upgrade appears in the token store once you've passed the early game).
2. Buy **Node Pins** in the token store → **Nodes** tab.
3. Select any placed node — a pin button appears in the options bar next to pause.
4. Click it. The node is now pinned to the right edge of your screen.
5. Use the ⚙ on the pin for opacity/size, ✕ to unpin. Pin more nodes by buying more levels.

## Configuration

After the first launch, `%APPDATA%\Upload Labs\mod_configs\Taylor-NodePins\default.json` lets you tune:

| Key | Default | Meaning |
|---|---|---|
| `perk_base_cost` | `4` | Token cost of upgrade level 1 |
| `perk_cost_growth` | `2` | Cost multiplier per level |
| `perk_max_level` | `5` | Maximum pin slots purchasable |
| `default_opacity` | `0.75` | Starting transparency of new pins |
| `default_pin_width` | `300` | Starting on-screen width (px) of new pins |

## How it works

- A script extension on the game's `Data` autoload injects the `node_pins` perk into `Data.perks` at load time. The game's own store UI, save system, unlock tracker, and purchase flow handle it natively from there — no UI scenes are patched.
- A script extension on the options bar adds the pin button, gated by perk ownership.
- Each pin is a `SubViewport` sharing the main `World2D` with its own `Camera2D` locked onto the pinned node — a true live view. The pin dock draws beneath the game's HUD, so menus stay on top.
- The game normally hides and stops processing off-screen nodes; the mod keeps pinned nodes awake so their pins stay live.

### Developer self-test

Set the environment variable `NODEPINS_SELFTEST=1` before launching and the mod will automatically pin a node, verify the render, change settings, and unpin — logging each step to `%APPDATA%\Upload Labs\logs\modloader.log`. It uses a runtime capacity override, so your save is never modified.

### Building from source

```powershell
./build_zip.ps1            # produces Taylor-NodePins-<version>.zip
```

## Compatibility

- Game version: 2.2.12 (Godot 4.6.1, Mod Loader 7.0.1)
- Save-safe both ways: installing adds one perk entry; uninstalling leaves saves loadable (the game skips unknown perk ids by design).

## License

MIT — see [LICENSE](LICENSE).
