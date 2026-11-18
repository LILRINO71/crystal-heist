# AI agent tools: CLI-Anything and REA for Crystal Heist (Roblox)

Research note, 2026-11-17. It covers two agent toolkits:

- **[CLI-Anything](https://github.com/HKUDS/CLI-Anything)** (Apache-2.0) wraps real desktop programs (FreeCAD, Blender, 3MF and others) in CLIs that agents can drive.
- **[REA](https://github.com/morluto/rea)** (MIT) is an MCP server and CLI that gives agents reverse-engineering tools.

This file covers only what matters for **this** repo.

How to read the labels:

- **Confirmed**: checked against the tool's own repo or docs.
- **Recommendation**: a suggestion, not tested.
- Nothing below was run end to end on this project yet.

## What could help here

There's little to gain here, and this file says so plainly.

- **No Roblox Studio harness exists** in CLI-Anything's registry. Studio is closed-source, and CLI-Anything only wraps software with a programmatic interface. **Confirmed**: neither registry has a Roblox entry.
- **Don't use REA on the Roblox client or other people's games.** Reverse engineering the client breaks Roblox's Terms, and REA's disclaimer limits it to software we own or are authorized to examine.
- **Possible use (recommendation):** the CLI-Anything **Blender** harness can batch-make or decimate meshes (crystals, decorations), with the results imported through Studio as usual. That only helps if the map uses custom meshes.

## Proposed changes

None. Keep the Rojo + Luau workflow.

## Status on the dev PC (updated 2026-11-17)

- **Installed and working:**
  - Agent skills `cli-hub-meta-skill` and `reverse-engineer-anything`.
  - `cli-anything-hub` 0.4.1.
  - Node 24.22.1.
  - REA 6.9.0 (global `rea`), registered as an MCP server in Claude Code. `rea doctor` reports it healthy.
  - FreeCAD 1.1.4, with the `cli-anything-freecad` harness (`FREECAD_PATH` points at `FreeCADCmd.exe`).
- **Smoke-tested:**
  - REA's JS analysis of the shot-sim build.
  - A FreeCAD cube built and measured (volume and center of mass correct), then exported to STEP through headless FreeCAD.
- **Not installed:** REA's optional engines (Ghidra, IDA, JADX/JDK 17+, Kuna), adb, and Blender.

## Rules for REA

Use REA only on code and builds we made, or on devices we own. Reverse engineering commercial software can break its EULA or DMCA §1201, and §1201(f) covers only narrow interoperability work. REA's tool results are sent to the AI model provider, so never point it at keys, `.env` files or credentials.
