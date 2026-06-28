# NEON POSSUM — Product Requirements Document
**Version 1.0 | Author: J. Hayes + Claude | Date: 2026-06-25**
**Engine: Godot 4.7 | Platform: Android (Google Play) | Target Device: Samsung S24 Ultra**

---

## 1. VISION STATEMENT

Neon Possum is a cyberpunk endless runner for adults — the game Subway Surfers and Minion Rush would be if they were designed for people who hate ads. No ads. Ever. The business model is: make a game so fun people *want* to spend money on it.

**Pillars:**
1. **Flow** — controls so tight that dying always feels like your fault, never the game's
2. **Addiction** — every session ends with unfinished business pulling you back
3. **Personality** — the world, the characters, the sounds have a voice; this isn't a clone
4. **Depth** — casual surface, deep meta; a new player and a 100-hour player have different experiences

**Tone:** Neon-soaked wet city streets at 2am. Cyberpunk but funny. Gritty but not grimdark. Think *Arcane* art direction crossed with Saturday morning cartoon energy.

---

## 2. CORE LOOP

```
RUN → DIE / PAUSE → SCORE SCREEN → SHOP / MISSIONS → RUN
```

A run lasts until the player dies or quits. There is no finish line. The goal is always: run farther than last time, complete missions, bank gems.

**Sub-loops (the retention engine):**
- **Micro loop (per run):** dodge, collect, combo, powerup, beat personal best
- **Session loop (per day):** claim daily reward, complete 1–3 missions, unlock a thing
- **Macro loop (per week/month):** progress toward character unlock, outfit set, zone unlock, boss clear

---

## 3. CONTROLS

| Input | Action |
|-------|--------|
| Swipe left/right | Switch lane (one lane per gesture; mid-air OK) |
| Swipe up | Jump (buffered 0.13s before landing) |
| Swipe down | Slide (auto-stands after duration) |
| Swipe down while jumping | Cancel into slide on land |
| Swipe up while sliding | Cancel slide into jump |
| Tap pause button | Pause |

- Swipe threshold: 120px (prevents micro-swipe misfires on large phone screens)
- Lane switch is discrete: one gesture = one lane. Cannot skip lanes in a single swipe.
- Long horizontal swipe does NOT skip lanes.

---

## 4. WORLD PROGRESSION — ZONES

The world changes as the player runs farther. Each zone has a distinct visual theme, obstacle set additions, and ambient audio layer. Transition is seamless — the road morphs.

| Zone | Name | Distance Trigger | Visual Theme | Unique Obstacles |
|------|------|-----------------|--------------|-----------------|
| 1 | **Neon City** | 0–5,000 ft | Wet city streets, neon signs, rain | Baseline obstacle set |
| 2 | **Transit Underground** | 5,001–15,000 ft | Subway tunnel, oncoming trains, third rail | Moving trains (2-lane), sparking rails (floor beam) |
| 3 | **Sewer Network** | 15,001–30,000 ft | Green-lit sewers, pipes, toxic runoff | Pipe bursts (vertical blocker), floating debris, rat swarms |
| 4 | **Corporate Arcology** | 30,001–55,000 ft | Glass tower interior, holographic ads, security drones | Drones (dive-bomb), laser grids, glass walls |
| 5 | **Rooftop Chase** | 55,001+ ft | Open sky, rooftop gaps, ventilation units, neon signs | Gap jumps (must be airborne), falling AC units, wind gusts (push lane) |

**Design note:** Each zone introduction plays a 2-second ambient sting + brief visual flash ("ENTERING TRANSIT UNDERGROUND"). The floor shader changes color temperature. Background building silhouettes update. Core obstacle speed is unchanged — difficulty comes from new obstacle types, not just speed.

**Weather system (layered onto zones):**
- Random chance per run: clear / light rain / heavy rain / electrical storm
- Storm: more electric beams, reduced visibility, larger combo windows to compensate
- Rain: wet-floor reflections intensify (already built into perspective_floor.gd)

---

## 5. CHARACTER ROSTER

### 5A. Playable Characters (Launch: 3–4)

All playable characters run in the same world. Perks are passive or active buffs that change playstyle, not difficulty. Characters are unlocked via milestones, missions, OR gem purchase.

| # | Name | Description | Perk | Unlock Method |
|---|------|-------------|------|---------------|
| 1 | **Zee** *(default)* | Goblin girl, purple mohawk, leather jacket | None — balanced starter | Default |
| 2 | **Rex** | Large goblin bruiser, broken horns | **Tank:** Shield absorbs 2 hits instead of 1 | 50,000 ft total lifetime distance |
| 3 | **Pip** | Tiny goblin, big ears, thief's coat | **Pickpocket:** Magnet is always active (short range, half a normal magnet) | Complete "Gem Hoarder" mission set (collect 500 total gems) |
| 4 | **Vex** | Cyber-elf, chrome arm, visor | **Overclock:** Speed powerup lasts 2× longer | Gem purchase: 2,500 gems OR complete "Speedrunner" mission set |

**Outfits (per character, cosmetic only):**
Each character has 5 outfit slots:
- Slot 1: Default (free)
- Slot 2: Unlocked at character Level 5
- Slot 3: Gem purchase (350–800 gems)
- Slot 4: Limited-time event (rotating weekly/monthly)
- Slot 5: Prestige (complete all missions for that character)

### 5B. Enemy / NPC Roster (50+ total, my recommendations)

Enemies are obstacles with personality. Most are **punch targets** (score reward, never kill). Some are **blocking enemies** (kill on contact). All are pulled from the `npc` style with action-based collision.

**Punch-Target Enemies (bowl over for combo score — never kill player):**
| Enemy | Visual | Behavior | Score |
|-------|--------|----------|-------|
| Goblin Kid | Small goblin, skateboard | Wanders left/right slightly | 75 |
| Trash Panda | Raccoon in hoodie, holding stolen goods | Slow, wobbles | 100 |
| Courier Bot | Small delivery drone on legs | Zigzags, slight evasion | 125 |
| Glitch Ghost | Translucent goblin, flickering | Phases in/out every 1.5s; only hittable when solid | 200 |
| Tag Artist | Teen goblin with spray can | Stops to spray wall briefly = easier to hit | 150 |

**Blocking Enemies (dodge like obstacles, but animated):**
| Enemy | Visual | Behavior | Dodge |
|-------|--------|----------|-------|
| Street Enforcer | Armored cop-bot, baton | Walks toward player, takes up 1 lane | Jump |
| Cyber Dog | Robotic dog, low profile | Low to ground, fast | Jump |
| Neon Drone | Flying security drone | Hovers at head height, sweeps lane | Slide |
| Rat King | Giant sewer rat (Zone 3) | 2 lanes wide, slow | Jump to flanking lane |
| Security Turret | Wall-mounted laser (Zone 4) | Fires in short bursts, telegraphed with red dot | Time jump or slide |

**Zone-Specific Enemies:**
- Zone 2 (Transit): **Commuter NPC** (punch target, holding coffee); **Transit Bot** (blocker, sweeps platform)
- Zone 3 (Sewer): **Slime Crawler** (floor level, slide over); **Pipe Worker** (punch target, has wrench)
- Zone 4 (Arcology): **Security Guard** (blocker, shouts warnings); **Cleaning Bot** (punch target, spinning mop)
- Zone 5 (Rooftops): **Maintenance Worker** (punch target); **Gargoyle Bot** (drops from above, jump triggers it)

**Boss Enemies (one per zone — see Section 8):**
- Zone 1 Boss: **The Commissioner** (crooked city official in hoverchair)
- Zone 2 Boss: **Transit Authority Rex** (giant armored transit cop bot)
- Zone 3 Boss: **The Rat Queen** (massive cyber-rat empress)
- Zone 4 Boss: **Synapsis** (rogue corporate AI in hologram form)
- Zone 5 Boss: **Apex** (military drone, final boss of current content)

---

## 6. OBSTACLE SYSTEM

### Current Obstacles (Zone 1 Baseline)
| ID | Style | Action | Description |
|----|-------|--------|-------------|
| car | sprite | jump | Single-lane vehicle, rear view |
| bus | sprite | jump | 2-lane vehicle |
| cart | sprite | jump | Shopping cart |
| barrier | sprite | jump | Road barrier |
| cone | sprite | jump | Traffic cone |
| dumpster | sprite | jump | Dumpster |
| moto | sprite | jump | Motorcycle |
| trashcan | sprite | jump | Trash can |
| elec_low | beam | slide | Head-height electric beam (duck under) |
| elec_wide | beam | slide | Full-width head-height beam (duck under) |
| elec_high | beam | jump | Low electric beam (hop over) |
| slick | slick | slide | Floor acid/oil puddle (slide or jump over) |
| npc | npc | punch | Goblin kid punch target |

### Zone 2 Obstacle Additions
| ID | Style | Action | Description |
|----|-------|--------|-------------|
| train | sprite | jump | Moving train, 2 lanes, faster than bus |
| third_rail | beam | jump | Low sparking rail on floor |
| turnstile | sprite | jump | Subway turnstile |
| signal_light | sprite | slide | Hanging signal light |

### Zone 3 Obstacle Additions
| ID | Style | Action | Description |
|----|-------|--------|-------------|
| pipe_burst | beam | slide | Steam/water jet from wall, head height |
| debris_float | sprite | jump | Floating debris on water |
| rat_swarm | slick | slide | Floor-level rat swarm (slide through or jump) |

### Zone 4 Obstacle Additions
| ID | Style | Action | Description |
|----|-------|--------|-------------|
| laser_grid | beam | slide | Corporate laser at head height |
| glass_wall | sprite | jump | Full-lane glass barrier |
| drone_dive | npc | slide | Aerial drone that dive-bombs (duck) |

### Zone 5 Obstacle Additions
| ID | Style | Action | Description |
|----|-------|--------|-------------|
| rooftop_gap | gap | jump | Gap in roof — MUST be airborne |
| ac_unit | sprite | jump | Falling AC unit (telegraphed shadow) |

### Moving/Swerving Obstacles (Launch Feature)
- **Swerving moto:** motorcycle that randomly changes lanes (seeded pattern, telegraphed with light indicator)
- **Rolling barrel:** bounces between lanes on a predictable timer
- **Homing npc:** punch-target enemy that moves toward the player's lane

---

## 7. POWERUP SYSTEM

### Powerups (via Gates)

| ID | Name | Effect | Duration | Upgradeable |
|----|------|--------|----------|-------------|
| ball | Ball Form | Invincible sphere, rolls through everything, bounce-jumps | 4s base | Yes (+1s per level) |
| speed | Speed Boost | 1.5× world speed, auto-collects in path | 3s base | Yes (+0.5s per level) |
| shield | Shield | Absorbs 1 hit (2 hits with Rex) | 1 hit | Yes (+1 hit at max) |
| magnet | Magnet | Pulls gems within 620px radius | 6s base | Yes (+2s, +150px per level) |
| jetpack | Jetpack | Flies above all obstacles, auto-collects everything | 5s | Yes (+1s per level) |
| multiplier | 2× Score | Doubles all points earned | 8s | No |

**Jetpack** (new, to build): Player lifts off the road, floats at mid-height, all obstacles pass underneath. Gems that would be in lanes are all collected automatically. Visual: rocket pack on character's back, leaving neon trail.

**Character perk interaction:**
- Rex + Shield gate = 3 hits total before death
- Pip + Magnet gate = double range magnet
- Vex + Speed gate = 4.5s duration (2× her base)
- All characters: powerups stack (magnet + speed active simultaneously = valid)

### Powerup Upgrade System (Shop)
Each powerup has 3 upgrade levels purchased with gems:
- Level 1 (base): free
- Level 2: 200 gems
- Level 3: 500 gems
- Max: 800 gems

---

## 8. BOSS FIGHTS

Inspired by Minion Rush boss encounter structure. Bosses appear as scripted events triggered by distance milestone on first crossing, then randomly on repeat runs past that zone.

**Boss Encounter Flow:**
1. **Warning phase (3s):** Screen edge flashes red, boss silhouette slides in from the side. Warning label: "⚠ BOSS INCOMING"
2. **Active phase (15–25s):** Boss runs alongside or ahead, throwing attacks into lanes
3. **Player response:** Survive without dying + throw back collectibles (tap boss when highlighted) OR just survive the timer
4. **Resolution:** Boss defeated → gem chest drops (25–75 gems + chance at outfit shard). Boss escapes → no reward but run continues

**Attack patterns (pool, random per phase):**
- Projectile into specific lane (telegraphed 1.5s before) → dodge to other lane
- Sweep attack (clears 2 lanes for 0.5s) → 1 safe lane, highlighted
- Ground slam (creates floor beam for 2s) → jump
- Overhead attack (creates head-height beam) → slide

**Boss HP** (measured in successful player dodges):
- Tier 1 bosses (Zone 1–2): 8 dodge events
- Tier 2 bosses (Zone 3–4): 12 dodge events
- Tier 3 (Apex, Zone 5): 18 dodge events with mixed patterns

**Rewards by outcome:**
| Outcome | Reward |
|---------|--------|
| Perfect clear (0 hits taken) | 75 gems + outfit shard |
| Clear with hits | 40 gems |
| Survived (no defeat) | 15 gems |
| Died during boss | 0 gems, run ends |

---

## 9. ECONOMY & SHOP

### Currency: Gems (◈)
- **Earned in-game:** collected during runs, mission rewards, daily login, boss clears
- **Purchased (IAP):** gem packs sold on Google Play
- **Gem sinks (what you spend on):** revives, character unlocks, outfit purchases, powerup upgrades, mystery boxes

### Gem Earn Rates (design targets)
| Source | Rate |
|--------|------|
| Average run (casual) | 15–40 gems |
| Daily reward (Day 1) | 25 gems |
| Daily reward (Day 7 streak) | 130 gems |
| Mission completion (easy) | 20–35 gems |
| Mission completion (hard) | 60–80 gems |
| Boss clear (perfect) | 75 gems |
| Mystery box (rare) | 200–500 gems |

### IAP Packages (Google Play)
| Package | Gems | Price |
|---------|------|-------|
| Handful | 150 | $0.99 |
| Pouch | 500 | $2.99 |
| Bag | 1,200 | $4.99 |
| Chest | 3,000 | $9.99 |
| Vault | 8,000 | $19.99 |

*All IAP optional. Game is fully completable free. IAP is time-compression, not pay-to-win.*

### Shop Screen Layout
1. **Characters** — playable roster, unlock/purchase, perk preview
2. **Outfits** — per-character cosmetics, outfit sets
3. **Powerups** — upgrade levels, cost display
4. **Mystery Box** — spend 50 gems per pull, contents: gems / outfit shards / powerup upgrades / rare character
5. **Gem Store** — IAP packages

### Revive System (Death Screen)
- Available while `total_gems >= cost` and `revives_used < 3`
- Cost escalates: 40 / 80 / 120 gems
- Revive: center lane, 3s grace shield, spawners restart with gap

---

## 10. PROGRESSION & UNLOCK SYSTEM

### Distance Milestones (first-time rewards)
| Milestone | Reward |
|-----------|--------|
| 500 ft | 25 gems |
| 1,000 ft | New outfit for Zee |
| 2,500 ft | 50 gems |
| 5,000 ft | Zone 2 unlocks |
| 7,500 ft | Rex unlocked |
| 10,000 ft | 100 gems + mystery box pull |
| 15,000 ft | Zone 3 unlocks |
| 20,000 ft | Pip unlocked |
| 30,000 ft | Zone 4 unlocks |
| 40,000 ft | Vex unlocked |
| 55,000 ft | Zone 5 unlocks |
| 100,000 ft | Prestige Outfit (Zee) |

### Missions System (3 active slots, rotating)
Mission types: gems collected / distance run / goblins bowled / powerups grabbed / combo achieved / runs played
- Completing a mission: gem reward + slot rerolls immediately with new mission
- Mission progress is never reset (Zeigarnik effect — partial progress pulls players back)
- Mission verbs use the character's world: "Bowl over X goblins" not "eliminate X enemies"

### Daily Login Streak
| Streak Day | Reward |
|-----------|--------|
| 1 | 25 gems |
| 2 | 40 gems |
| 3 | 55 gems |
| 4 | 70 gems |
| 5 | 85 gems |
| 6 | 100 gems |
| 7 | 130 gems + mystery box |
| 8+ | Caps at 150 gems/day |
- Missed a day: streak resets to 1
- Streak displayed on main menu to reinforce the behavior

### Character Levels (per character)
Each character has levels 1–10. XP is earned by playing runs WITH that character.
- Level 3: unlock outfit slot 2
- Level 5: +5% gem value bonus
- Level 8: unlock outfit slot 5 (prestige)
- Level 10: character-specific achievement badge + 200 gems

---

## 11. PSYCHOLOGICAL RETENTION MECHANICS

Research-backed design patterns from Minion Rush, Subway Surfers, and behavioral psychology:

### Variable Reward Schedule
- Mystery box contents are random within defined rarity tiers
- Gem clusters during runs spawn in irregular patterns, not predictable lines
- Boss reward chest has RNG element (guaranteed gems + chance at outfit shard)
- Effect: same dopamine mechanism as slot machines without gambling classification

### Zeigarnik Effect (Unfinished Business)
- Missions always display current progress on main menu ("Bowl over 3/10 goblins")
- Progress is never reset — even an abandoned run contributes to missions
- After death: show which missions moved forward ("Mission Progress: +3 goblins!")
- Effect: brain registers incomplete tasks as more salient; pulls player back

### Near-Miss Feedback
- When player barely avoids an obstacle (within 15px): brief green flash on edges, small screen shake, "CLOSE!" text flash
- Effect: near-misses register as exciting, not frustrating — player wants to replay

### Endowment Effect
- Characters the player has invested in (leveled up, outfitted) feel like possessions worth protecting
- Outfit previews show ON the character before purchase (you're already imagining owning it)

### Loss Aversion (Revive System)
- Death screen shows your CURRENT score prominently, with revive offer
- "You're at 14,250 ft — your best is 15,000 ft. Spend 40 ◈ to keep going?"
- Player is closer to completing a mission — show it: "2 more goblins to complete Bowl Over!"
- Effect: spending 40 gems to avoid losing progress feels less costly than it is

### Social Comparison
- Global leaderboard visible during run (small rank indicator in HUD)
- "You just passed TXrunner99 — rank #847" notification mid-run
- Friend leaderboard shows friend ghosts on track (future feature)
- Effect: competitive motivation even in a solo game

### FOMO (Fear Of Missing Out)
- Weekly rotating outfit in Shop (gone after 7 days, clearly labeled)
- Limited boss event rewards (outfit shard only obtainable during event window)
- Daily reward streak counter — missing a day visible and punished mildly

### Flow State Design
- Difficulty ramp follows a Yerkes-Dodson curve: easy start → increasing challenge → brief breather (powerup gate) → spike → repeat
- Speed increments are small (18 units every 5 seconds) so player adapts imperceptibly
- Death should always feel survivable in retrospect: "I could have made that"

### "One More Run" Engineering
- Death screen → restart is 1 tap. Zero loading. Zero friction.
- End screen always shows 1–2 missions that moved forward: "3 more gems to finish Collect 30 gems!"
- Daily reward on menu screen creates urgency: "Claim your daily reward before midnight!"

---

## 12. SOCIAL & PLATFORM FEATURES

### Leaderboards (Google Play Games)
- **Global All-Time:** highest single-run score, all players
- **Weekly:** resets every Monday, creates recurring competition
- **Friends:** separate tab, shows people the player follows via Google Play Games
- **Local Device:** separate section, no internet required, tracks devices/accounts on this phone

### Achievements (Google Play Games + In-Game)
| Achievement | Trigger |
|-------------|---------|
| First Run | Complete first run |
| Speed Demon | Activate Speed powerup 10 times |
| Bowl-O-Rama | Bowl over 100 goblins total |
| Untouchable | Complete a run of 1,000+ ft without getting hit |
| Combo King | Achieve x10 combo in a single run |
| Boss Slayer | Defeat all 5 bosses |
| Globe Trotter | Reach Zone 5 for the first time |
| Shopaholic | Spend 1,000 gems in the shop |
| Dedicated | Maintain a 7-day login streak |
| Legendary | Reach 100,000 ft in a single run |

---

## 13. AUDIO DIRECTION

### Music
- **Zone 1:** Synthwave, mid-tempo, wet drums, neon bass. Think Kavinsky or Perturbator-lite.
- **Zone 2:** Industrial techno, rhythm synced to running tempo
- **Zone 3:** Lo-fi cyberpunk, dripping ambience, muted bass
- **Zone 4:** Corporate electronic, clean but sinister
- **Zone 5:** Aggressive synth, high energy, full-on
- Each zone has its own music layer that crossfades on transition

### SFX
| Sound | Trigger |
|-------|---------|
| Jump | Player jumps |
| Slide | Player slides |
| Gem collect | Individual gem, pitch-scaled (higher pitch each in a chain) |
| Powerup | Gate collected |
| Hit | Player death |
| Combo | Goblin bowled, + combo voice line |
| Near miss | Close obstacle dodge |
| Boss warning | Boss approach sting |
| Zone change | Ambient sting on zone transition |
| Daily reward | Coin flourish on menu open |

### Character Voice Lines (Zee, launch character)
Short, punchy, occasional. Not constant. Triggered by:
- Run start: "Let's go!", "Time to run!", "On your left!"
- Big combo: "Nailed it!", "Come on!", "Keep coming!"
- Boss approach: "Oh hell no—", "Really?!"
- Death: "Ugh—", "Not again!", *surprised grunt*
- Revive: "One more shot!", "Not done yet!"
- Powerup grab: "YES!", "Magnet — nice!"

---

## 14. VISUAL STYLE GUIDE

**Reference:** Zee's reference image — wet neon city street, goblin girl running, tall buildings with neon billboards, rain-slicked road, perspective vanishing point in center.

**Color palette:**
- Background: very dark navy/black (#040410 to #080820)
- Road: dark grey with wet sheen, neon reflections
- Neon accents: hot pink (#FF2266), cyan (#00FFCC), electric purple (#AA00FF), gold (#FFCC00)
- Character: warm skin tones against cool environment

**Buildings:**
- 7 per side, parallax scrolling at varying depths
- Neon facades: random shop names (NOODLE BAR, CYBER LOUNGE, POSSUM CASH, etc.)
- Lit windows: random, flickering occasionally
- Neon Possum logo signs mixed in (Easter egg)

**Obstacles:**
- Vehicles: rear-facing, head-on view, cyberpunk modifications
- Electric beams: crackling, pulsing, color matches type
- NPCs: distinct silhouettes, readable at speed

**HUD:**
- Minimal — score top center, gems top left, powerup indicator center, pause top right
- Combo text: large, center-screen, brief
- Mission complete: text flash (not popup — never interrupts flow)

---

## 15. TECHNICAL SPECIFICATIONS

| Spec | Value |
|------|-------|
| Engine | Godot 4.7 GDScript |
| Resolution | 1080×1920 (portrait) |
| Render window | 540×960 (scale ×2 canvas_items) |
| Target FPS | 60fps locked |
| Min Android | API 26 (Android 8.0) |
| Target device | Samsung S24 Ultra |
| Orientation | Portrait only |
| Offline | Fully playable offline |
| Internet | Required for leaderboards, IAP only |
| Save location | user://neonpossum_save.json |
| Autoloads | Sfx, SaveData, Missions |

### Key Architecture Principles
- All world objects use `main.get_speed()` per frame — NEVER cache spawn speed
- Pseudo-3D via perspective.gd: flat world-Y coords → screen projection
- Score = `int(distance) + gem_count * gem_multiplier + bonus_score`
- Emit `score_changed` only when value changes (no per-frame string GC)
- `process_mode = ALWAYS` on Main so pause toggle works
- CanvasLayers (HUD/menus) ignore Node2D shake transform
- Gems banked LIVE to `total_gems` so revive is spendable mid-run

---

## 16. LAUNCH SCOPE vs. ROADMAP

### v1.0 Launch (must-have)
- [x] Core runner mechanics (jump, slide, lane switch)
- [x] Obstacle system (all Zone 1 types + swerving obstacles)
- [x] Gem, gate, powerup system (ball, speed, shield, magnet)
- [x] Combo system (punch targets, score multiplier)
- [x] Missions (3 slots, rotating)
- [x] Daily login reward
- [x] Revive system
- [x] Save/load persistence
- [x] Pause, death, menu screens
- [ ] Jetpack powerup
- [ ] Zone 1–2 complete (city + transit)
- [ ] 1 boss fight (The Commissioner)
- [ ] Zee + Rex playable, Pip + Vex visible (locked)
- [ ] Basic shop (outfits, powerup upgrades)
- [ ] Google Play Games leaderboard (global + friends)
- [ ] Character voice lines (Zee)
- [ ] Zone-specific music
- [ ] IAP gem packs (3 tiers)
- [ ] Android export, S24 Ultra tested, Play Store listing

### v1.1 Post-Launch
- [ ] Zone 3 (Sewer) + Zone 3 boss
- [ ] Pip + Vex playable
- [ ] Mystery box system
- [ ] Achievement system
- [ ] Weekly rotating outfits (FOMO cycle)
- [ ] More boss events

### v1.2+
- [ ] Zones 4–5
- [ ] Friend ghost system
- [ ] Seasonal events (holidays)
- [ ] iOS port (PlatformManager.gd routing)
- [ ] Object pooling optimization (if performance issues on mid-range Android)

---

## 17. ENEMY/CHARACTER ASSET PIPELINE

Assets are generated via ComfyUI JuggernautXL checkpoint, background-removed with birefnet-general, auto-cropped and placed in:
- Playable: `res://assets/sprites/final/`
- NPCs/Enemies: `res://assets/sprites/npc/`
- Obstacles: `res://assets/sprites/obstacles/`
- UI: `res://assets/sprites/ui/`

Prompt template for enemies:
```
cyberpunk [CREATURE TYPE] character, flat rear elevation view, 
perfectly symmetrical, full body, neon city street, dynamic pose,
2D game sprite style, clean outline, no background
Negative: three-quarter view, angled, rotated, background, shadow
```

---

## 18. NAMING CONVENTIONS (CONSISTENCY RULES)

To prevent cross-file reference bugs, all systems use these canonical names:

| Concept | Canonical Name | File/Variable |
|---------|---------------|---------------|
| Player gem count (this run) | `gem_count` | main.gd |
| Lifetime spendable gems | `total_gems` | save_data.gd |
| Current world speed | `get_speed()` | main.gd method |
| Player state enum | `State.RUN/JUMP/SLIDE/BALL/DEAD` | player.gd |
| Main game state | `State.MENU/PLAYING/DEAD` | main.gd |
| Score (computed each frame) | `score` | main.gd |
| Bonus score accumulator | `bonus_score` | main.gd |
| Mission event: gem | `"gems"` | missions.gd |
| Mission event: goblin punch | `"punch"` | missions.gd |
| Mission event: distance | `"distance"` | missions.gd |
| Mission event: powerup | `"powerups"` | missions.gd |
| Mission event: combo (max) | `"combo"` via report_max | missions.gd |
| Mission event: run count | `"runs"` | missions.gd |

---

*This document is the source of truth. When in doubt: what does this PRD say? If it's not in the PRD, it's a design decision that needs to be added here before implementation.*
