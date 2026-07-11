# Upload Labs — Node Pins

Pin your nodes to the screen. A gameplay mod for [Upload Labs](https://store.steampowered.com/app/3606890/Upload_Labs/) built on the [Godot Mod Loader](https://wiki.godotmodding.com/), which ships inside the game — no patching, no game file changes.

Steam Workshop: [Node Pins (QoL) - https://steamcommunity.com/sharedfiles/filedetails/?id=3760233672](https://steamcommunity.com/sharedfiles/filedetails/?id=3760233672)

## Features

- **Pin any node to your screen.** Select a node and press the pin button (⚲) in the options bar. A live, translucent view of the node — titled **Node Pin #1**, **#2**, … — appears at the top-center of your screen and stays there while you pan and zoom anywhere on the desktop.
- **Fully interactive — click or drag.** Clicks inside a pin are mapped into the world and applied to the real node, and **connection drags work too**: drag from any connector straight onto a pin (or from a pin's connector out into the world) and it connects. Dropping anywhere on a pin's frame **auto-connects** to the best compatible endpoint of that node. Compatible connectors glow inside the pin while connecting, and regular buttons on the node work through the pin.
- **Draggable and resizable.** Grab a pin by its header to move it; drag its bottom-right corner to resize the frame. The ⚙ settings panel has **opacity** and **zoom** sliders — zoom in or out on the node rendered inside the frame (hard-limited to a sane range). Everything is remembered per pin.
- **Framed nodes.** The pinned node gets a vibrant colored border frame in the world so it's easy to spot — only the frame is colored, never the node's contents — and the pin's border matches. The 🎨 button cycles through six colors.
- **Unlocked through normal gameplay.** "Node Pins" is a token-cost upgrade in the token store (Nodes tab): 5 pin slots costing 10, 20, 20, 30, 50 tokens. A second upgrade, **Extra Pin Slots**, adds up to 3 more slots (8 absolute max) at exponentially increasing Research costs starting at 1.0T (1T → 10T → 100T).
- **Animated.** Pins slam in when created and peel away when removed.
- **Live and persistent.** Pins render the real node through a viewport that shares the game world — progress bars and counts update in real time, even far off-screen (the mod keeps pinned nodes processing despite the game's off-screen optimizations). Pins, positions, sizes, zoom, colors, and opacity survive game restarts.

## Installation

### Manual (GitHub release)

1. Download `Taylor-NodePins-x.y.z.zip` from the [latest release](../../releases/latest). Do **not** unzip it.
2. Find your Upload Labs install folder (Steam: right-click the game → Manage → Browse local files).
3. Create a folder named `mods` next to `Upload Labs.exe` if it doesn't exist.
4. Drop the ZIP into that `mods` folder and launch the game.

To uninstall, delete the ZIP. Saves stay fully compatible in both directions — the upgrade level simply becomes inert data that the game ignores.

### Steam Workshop

The game's mod loader also loads mods subscribed via the Steam Workshop. If you found this mod on the Workshop, subscribing is all you need — no manual steps.

## Usage

1. Buy **Node Pins** in the token store → **Nodes** tab (it appears once you've passed the early game). Buy **Extra Pin Slots** with Research later for up to 3 more.
2. Select any placed node — a pin button (⚲) appears in the options bar next to pause.
3. Click it. The node slams onto the top-center of your screen and gets a colored frame so you can spot it in the world.
4. Drag the pin by its header to place it; drag its bottom-right corner to resize. Use 🎨 to cycle its color, ⚙ for opacity/zoom, ✕ to unpin.
5. To connect across the map: drag (or click) a connection from any node and drop it on the pin — landing anywhere on the pin auto-connects to the best matching endpoint, or hit a specific connector for full control. Works in both directions.

## Configuration

After the first launch, edit `%APPDATA%\Upload Labs\mod_configs\Taylor-NodePins\default.json` and restart:

| Key | Default | Meaning |
|---|---|---|
| `default_opacity` | `0.75` | Starting transparency of new pins (0.2–1) |
| `default_pin_scale` | `0.6` | Initial size of new pins relative to the node's own size (resizable afterwards) |

## Repository layout

```
mods-unpacked/
  Taylor-NodePins/        <- the mod itself (what ships in the ZIP)
    manifest.json         <- Godot Mod Loader manifest + config schema
    mod_main.gd           <- entry point; installs the script extensions
    extensions/
      scripts/
        data.gd           <- injects the "node_pins" perk into the token store
        options_bar.gd    <- adds the pin button to the node options bar
    node_pins/
      pin_manager.gd      <- pin lifecycle, capacity, persistence, self-test
      pin_view.gd         <- one pin window: live view, drag, color, settings
build_zip.ps1             <- build helper (see below), NOT part of the mod
README.md / LICENSE
```

### About `build_zip.ps1`

This PowerShell script is a **build tool only** — it is never included in the released ZIP and never runs on players' machines. It exists because PowerShell's built-in `Compress-Archive` writes Windows-style backslash paths inside ZIP files, which Godot's ZIP reader cannot resolve; the script zips `mods-unpacked/` with proper forward-slash entries instead. You can read it — it's ~20 lines. To build from source:

```powershell
./build_zip.ps1 -Version 1.3.0    # produces Taylor-NodePins-1.3.0.zip
```

The `mods-unpacked/<Namespace>-<ModName>/` layout inside the ZIP is the structure the Godot Mod Loader requires, and it is the same ZIP that gets uploaded as a Steam Workshop item — the loader scans subscribed workshop content for exactly this kind of archive.

## How it works

- A script extension on the game's `Data` autoload injects the `node_pins` perk into `Data.perks` at load time. The game's own store UI, save system, unlock tracker, and purchase flow handle it natively from there — no UI scenes are patched.
- A script extension on the options bar adds the pin button, gated by perk ownership.
- Each pin is a `SubViewport` sharing the main `World2D` with its own `Camera2D` locked onto the pinned node — a true live view drawn beneath the game's HUD.
- Viewports that share a world share **rendering only**, not GUI input, so the pin maps every click through its camera into world coordinates and dispatches it to the real node: connector buttons receive the game's own connector press handling (start, cancel, complete, disconnect), and regular buttons are pressed directly.
- The game normally hides and stops processing off-screen nodes; the mod keeps pinned nodes awake so their pins stay live.

### Developer self-test

Launch the game with the environment variable `NODEPINS_SELFTEST=1` and the mod runs an automated end-to-end check, logged to `%APPDATA%\Upload Labs\logs\modloader.log`: it pins two compatible nodes, performs a real output → input connection entirely through the pin views, verifies it, then deletes the connection and unpins. It uses a runtime capacity override and cleans up after itself, so the savegame is never modified.

## Compatibility

- Game version: 2.2.12 (Godot 4.6.1, Godot Mod Loader 7.0.1)
- Save-safe both ways: installing adds one perk entry; uninstalling leaves saves loadable (the game skips unknown perk ids by design).

## License

MIT — see [LICENSE](LICENSE).
