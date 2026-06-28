# Neon Possum — Project Notes (for Claude)

Cyberpunk endless runner, Godot 4.7, Android, ad-free. Inspired by Subway Surfers + Minion Rush.
**"Neon Possum" is the STUDIO / parent company** (ties to the neon look), not the game's final name — multiple games will ship under it. This game needs its own title eventually.
**ComfyUI asset pipeline**: user has existing workflows + ControlNet + a CivitAI account. Plan to consolidate all workflows into `D:\J Hayes\AI\ComfyUI\workflows`. This is the sprite-sheet animation pipeline for per-character run frames. Do this when starting the animation pass (don't scatter his files mid-coding).
Owner: John (non-coder, creative direction + playtesting). Claude does all implementation.
Wife: **Zoe** — the in-game character ZOE (Character 8, always in a hoodie) is named after her.

## Session protocol — keep context lean (READ FIRST)
The recurring pain is filling the context window mid-session. No tool fixes window size — the fix is cheap resumes + frugal context. Rules for future-me:
- **This file IS the handoff.** A fresh session reads it and is up to speed. Prefer short focused sessions over marathons; restarting is cheap *because* of this file.
- **Verify with COMPILE-CHECK (text, ~free), not screenshots.** Capture at most ONE frame, only at a genuine visual milestone, and read a single frame — each image ≈1.5k tokens.
- **Targeted reads** (offset/limit or Grep). Never re-read a file you just edited — Edit already confirmed the change.
- **Filter bash output hard** — grep the result, don't dump full logs/greps into context.
- **Checkpoint before the wall:** when context feels heavy, update "NEXT UP" below + Known gaps, tell John to start a fresh session, and stop. Don't push to the limit.
- **Keep THIS file tight** — it loads every session, so it costs tokens every session. Prune as much as you add.

## NEXT UP
- Difficulty ramp tuning: high scores ~19k — tighten before release. Raise MIN_ARRIVAL_GAP, more beam/slick weight in later zones.
- Sound pass: spring launch needs a "boing" SFX; hoverbike could have engine hum. Currently reuses jump/powerup.
- Per-character in-game models: all still share possum run cutouts. ComfyUI pass — biggest art gap.
- Death screen StatLabel Y offset (620) may need eyeballing in-game against ReviveButton.
- Mission mini-bar (MissionMini0/1/2) is at Y=1820 — test on device, may need nudge up.
- Homeless cart-pusher art: user has old-men ComfyUI sprites; considering a distinct new character sprite sheet.

## Run / verify
- Godot exe: `D:\J Hayes\Desktop\Godot_v4.7-stable_win64.exe`
- Compile-check ALL scripts (loads autoloads): `Godot --headless --editor --quit` then grep stderr for `SCRIPT ERROR|Parse Error|Compile Error|Failed to load script`. Single-file `--check-only` gives FALSE "Sfx/SaveData/Missions not found" (autoloads not loaded in isolation) — don't trust it.
- Screenshot headlessly: env hook in `scripts/main.gd` `_debug_autostart` — `NP_AUTO=run|boss|select` boots straight into that screen. Capture: `NP_AUTO=boss Godot --write-movie out.png --fixed-fps 12 --quit-after 40` writes a numbered PNG sequence (540×960). Vulkan errors are harmless (falls back). Clean up frames after.

## Architecture
- `main.gd` (Node2D, PROCESS_MODE_ALWAYS) orchestrates. Gameplay children are set PAUSABLE in `_ready` so tree-pause actually stops them.
- Pseudo-3D: flat world-Y coords → screen via `scripts/perspective.gd` (`progress`, `screen_y`, `depth_scale`, `converge_x`). Player sits at fixed screen pos; world scrolls toward camera.
- `perspective_floor.gd` draws sky, sun, parallax skyline (2 layers), zone-styled side buildings, road + scrolling flecks/panels, grid, lane dashes. Zone palettes lerp over ~2s.
- `obstacle.gd` / `obstacle_spawner.gd`: spawner spaces obstacles by **arrival time at the player** (not fixed distance) so fast oncoming + slow parked don't stack undodgeably. Obstacle styles: sprite, beam, slick, npc(punch), wall_gap(hole/evade). `rideable` vehicles (car/bus/train) → land on roof via `player.mount_roof`. `self_speed` = oncoming closing speed.
- `player.gd`: states IDLE/RUN/JUMP/SLIDE/BALL/JETPACK/HOVERBIKE/DEAD. `ground_override` raises "ground" to a vehicle roof while riding. `_apply_run_feel` adds stride bob + lane lean + jump squash. Tunables from `game_config.json`. `apply_perk(char_id)` sets per-char modifiers each run: ZOE passive magnet, LUMEN duration mult, NOVA/KANE start-shield, VIBE lane speed, PIXEL jump height. Main-side perks (RIX, ECHO, JINX, SABLE, CIRA) applied in `main._apply_char_perk()`.
- `boss.gd`: Minion-Rush-style boss on a jumbotron at track top. Phase machine (TELEGRAPH→FIRE→STRIKE|SALVO→COOLDOWN). Chest-core lasers fire into telegraphed lanes (dodge by lane). Odd fire cycles → single STRIKE (npc punch); even cycles (or below half HP) → SALVO (2-3 simultaneous npc punch targets, "PUNCH BACK!" HUD prompt, spinning orb visual on chest). Each salvo hit does 1 damage. HP: 6/8/8/10/10 by zone. TODO: real animated sprite sheet / rig instead of one still; male/non-cyborg boss types (new session).
- Juice: dust puffs on jump/land (`player._spawn_puff`), full-screen radial vignette (`main._build_postfx`), death hit-stop (`main._hitstop` via Engine.time_scale), gem-count ping. Leap combo (Zombie-Tsunami style) in `main.on_obstacle_cleared` — jump obstacles in sequence for escalating points + "LEAP ×N!" popups.
- `char_select_layer.gd`: 12-card portrait grid (built in code). `DEV_UNLOCK_ALL`-style: all open for owner, paywalls later. Cards use `assets/sprites/Character N/` portraits.
- `shop_layer.gd`: gem-sink upgrade shop (built in code). Buys powerup duration levels (magnet/ball/speed/jetpack), persisted in `save_data.upgrades`, applied via `save_data.upgrade_mult` read in `player.activate_powerup` (+20%/level, max 5). Menu has SHOP + BOSS FIGHT buttons side-by-side. NP_AUTO=shop to capture.
- Autoloads: `Sfx`, `SaveData`, `Missions`. Config: `game_config.json`. Design bible: `NEON_POSSUM_PRD.md`.

## Tuning notes (fairness)
- Obstacle spacing is by ARRIVAL TIME at the player (`obstacle_spawner._arrival_time`), not fixed distance. `MIN_ARRIVAL_GAP` 0.95 + `ARRIVAL_PAD` 0.15 absorbs the speed-ramp compression. self_speeds were lowered (car_oncoming 210, moto 260, train 200, bus_oncoming 150) so oncoming traffic reads clearly and doesn't overtake/bunch. If runs feel cramped again, raise MIN_ARRIVAL_GAP first.
- Air-slide: pressing slide mid-jump dives + slides on landing (`player._slide_queued`).
- Magnet range scales with its shop upgrade (`player` magnet case ×mult, base 720) → leveled magnet pulls across all lanes.
- Beams/slicks now draw a ground shadow + posts/stripe (beam) and a crisp rim + leading-edge (slick) for depth/timing readability.

## Known gaps / TODO
- Comedic dumpster death: DONE. Grounded collision → "dumpster" cause → legs-up procedural draw, "BONK. 🗑️" death screen.
- Occlusion guard: DONE. `OCCLUDER_EXTRA=1.3s` + lane-based tracking in `obstacle_spawner.gd` — hazards blocked in occluder lanes until clear.
- Springboard: DONE. Standalone `springboard` obstacle + safe lane of wall_gap auto-launches player via `spring_launch()`. "spring" cleared signal → leap combo + missions.
- Hover bike: DONE. `State.HOVERBIKE`, orange Oppressor MkII procedural draw, 200px off ground, 7s gate, clears all ground hazards.
- Boss salvo orbs: DONE. `salvo_projectile=true` on obs → spinning yellow energy orb in `_draw_npc()` instead of goblin.
- Character perks: DONE. All 12 wired mechanically. See player.apply_perk() + main._apply_char_perk().
- Missions: DONE. 7 new templates (spring, hoverbike, near_miss, boss_hit ×2). All events report to Missions autoload.
- Per-character in-game models: all chars still share possum run cutouts — biggest art gap, needs ComfyUI.
- Roster names beyond ZEE/ZOE/LUMEN are placeholders (NOVA/RIX/KANE/ECHO/VIBE/PIXEL/JINX/SABLE/CIRA); backstories come later for launch videos.
- Audio: DONE. All 6 files converted to .ogg (music 738KB→107KB), sfx.gd updated.
- NPC variety: DONE. npc_small (fast/blue/120pts), npc_big (orange/200pts, zone 2+), npc_gold (rare/400pts, zone 3+).
- Roof gems: DONE. `main.spawn_roof_gems()` called from `player.mount_roof()` — 5 teal gems staggered ahead on the roof.
- Mission mini-bar: DONE. MissionMini0/1/2 labels in HUD, updated in `_update_mission_minibars()` each frame.
- ZOE magnet ring: DONE. Soft purple `draw_arc` in `player._draw()` when `perk_passive_magnet == true`.
- Boss intro card: DONE. 1.2s title card (zone name + boss name + "INCOMING") via `_boss_intro_card()`, fades before lasers start.
- Boss unique patterns: DONE. Each zone boss has a distinct `_pick_lanes()` strategy (SENTINEL=sweep sides, TRANSIT=pincer, RAT QUEEN=center on odd, SYNAPSIS=rotating triples, APEX=enraged all-3).
- Seeded combos: DONE. 12% chance after a springboard → queues elec_high or wall_gap as a follow-up (~0.9s after spring's arrival), 18s cooldown between combos.
- RIX revive: DONE. Uses `revive_cap` local var (4 for RIX, 3 otherwise) instead of `revives_used = -1` hack.
- Roadmap: leaderboards (Google Play), achievements, IAP gem packs, voice lines, sprite-sheet animation + per-character models. (Shop = DONE.)
- "Way down the line" (user): rename characters + backstories, redo main screen to feature the main girl, change missions, blend intro-video black into loading black (kill the video box seam).
