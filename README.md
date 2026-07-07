# 💎🏴 Crystal Heist

**Grow it. Steal it. Defend it.** A Roblox game that fuses the two biggest breakout formats of 2025–26 — the cozy grow-simulator (*Grow a Garden*, 35B+ visits) and the PvP stealing game (*Steal a Brainrot*, all-time CCU record holder) — plus a tower-defense twist. Built **100% in code**: the map, the UI, the economy, everything is generated from Luau source. Managed with [Rojo](https://rojo.space) so the whole game lives in this repo.

[![CI](https://github.com/LILRINO71/crystal-heist/actions/workflows/ci.yml/badge.svg)](https://github.com/LILRINO71/crystal-heist/actions/workflows/ci.yml)

## The loop

1. **GROW** 💎 — Plant shards on your plot's pedestals. Crystals grow in **real time, even offline**, and secretly roll **mutations** at plant time (Shiny x3 → Celestial x300, revealed at maturity).
2. **CHARGE** ⚡ — Click growing crystals to shave seconds off. Idle players wait; active players print money.
3. **HARVEST** ✨ — Ready crystals glow and sparkle. Click (or HARVEST ALL) to cash in.
4. **STEAL** 🏴 — Ready crystals on *other players'* plots are fair game: click one and it floats over your head — you're slowed, highlighted red for the whole server, and must sprint to the hub's **Black Market** to bank ~50% of its value.
5. **DEFEND** 🛡️ — Victims get an alarm and can chase + click the thief to **zap** the crystal home. **Guard Turrets** (3 tiers) auto-zap thieves still on your plot. Pity shields after being robbed; join shields on spawn.
6. **VOID SURGE** 🌌 — Random server-wide events: 3x mutation luck, 75% steal payouts, purple sky. Chaos by design.

The tension is the design: only READY crystals are stealable, so AFK farming is risky, harvesting fast matters, and every sparkle on someone else's plot is a temptation.

## Architecture

```
src/
├── shared/
│   ├── Config.luau      # every tunable number: shards, mutations, heists, turrets, IDs
│   └── Formulas.luau    # pure math shared by server (authority) and client (display)
├── server/
│   ├── init.server.luau # entry: creates remotes, wires services (explicit DI)
│   ├── Data.luau        # profiles, DataStore (offline-growth timestamps), autosave
│   ├── Plots.luau       # plots, pedestals, crystal lifecycle, shields, turrets
│   ├── Heist.luau       # stealing: carry, zap, bank, turret enforcement
│   ├── Events.luau      # Void Surge loop
│   ├── Monetization.luau# gamepass cache + ProcessReceipt with product handlers
│   ├── MapBuilder.luau  # hub, Black Market, environment ring, borders — all code
│   └── GlobalLeaderboard.luau
└── client/
    ├── init.client.luau
    ├── UI.luau          # tiny declarative UI toolkit + window manager
    ├── Hud.luau         # stat pills, HARVEST ALL, menu buttons
    ├── PlantMenu.luau   # pedestal click -> shard picker
    ├── ShopUi.luau      # Shards / Defense / Robux tabs
    ├── Instructions.luau# How to Play (auto-opens on first ever join)
    └── Effects.luau     # popups, toasts, alarms, Void Surge tint
```

**Security model:** the client is only ever a *view*. Charging, harvesting and stealing run through server-connected ClickDetectors (nothing to spoof); planting/purchases are remotes that the server fully re-validates (costs, slot ownership, shields, cooldowns, ranges). Offline growth uses server timestamps, so clock-cheating does nothing.

**Anti-grief by construction:** join shields, pity shields after every successful theft, steal cooldowns after being zapped, carry timeouts, only-READY-crystals rule, and a 200-stud invisible wall over the rock border so nobody parkours out of the map.

## Run it locally

1. Install [Roblox Studio](https://create.roblox.com/) and [Rojo](https://rojo.space/docs/v7/getting-started/installation/) (or use `tools/rojo.exe` if present)
2. Build the place file:
   ```
   rojo build default.project.json -o build/CrystalHeist.rbxl
   ```
3. Open the `.rbxl` in Studio and hit **Play** — or use **Test → Clients and Servers → 2 players** to try stealing from yourself!

> DataStores and gamepasses are silently disabled in unpublished local playtests — the game detects this and runs with in-memory data.

## Enabling monetization

1. Publish the game (File → Publish to Roblox)
2. Creator Dashboard → your experience → **Monetization**:
   - **Passes**: 2x Coins (199 R$), Auto Charge (349 R$), Lucky (499 R$), Master Thief (449 R$)
   - **Developer Products**: 5K Coins (49 R$), 40K Coins (199 R$), 300K Coins (799 R$), Instant Grow (99 R$), Plot Shield 30min (79 R$)
3. Paste the IDs into `Config.GamePasses` / `Config.DevProducts` in [Config.luau](src/shared/Config.luau)
4. Game Settings → Security → enable **Studio Access to API Services**

Items with an ID of `0` are hidden from the shop automatically, so the game is fully playable before this step. Note the monetization covers **both sides of the conflict**: Instant Grow / Lucky for growers, Master Thief for raiders, Shields for defenders.

## Roadmap

- [ ] Pets that auto-harvest or auto-defend (the genre's biggest retention system)
- [ ] Heist streaks + bounties on serial thieves
- [ ] Crystal fusion (merge 3 identical → next tier with guaranteed mutation roll)
- [ ] Robust receipt dedupe via DataStore-backed purchase history
- [ ] Seasonal shard events + limited-time mutations
- [ ] Publish via Open Cloud from CI (push-to-deploy)
