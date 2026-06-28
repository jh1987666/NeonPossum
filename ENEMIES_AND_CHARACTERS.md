# Neon Possum — Enemies, Bosses & Player Roster

## Enemies / Bosses (30 total)

| # | Name | Vibe | Core Attack (Laser) | Punch | Salvo |
|---|------|------|---------------------|-------|-------|
| 1 | Transit Inspector | Cyborg in transit uniform | Fare-box laser | Pneumatic door arm | Tracking missiles |
| 2 | Bodega Unit | Industrial vending machine | Vending slot laser | Hydraulic security gate | Missile salvo |
| 3 | Pothole Repair | Construction droid | Furnace laser | Pneumatic jackhammer | Tar-canister missiles |
| 4 | Alleyway Goliath | Bouncer cyborg | Subwoofer sonic laser | Hydraulic haymaker | Micro-missiles |
| 5 | Scrapyard Sovereign | Asymmetrical iron machine | Overheating V8 laser | Car door club | Exhaust manifold missiles |
| 6 | Riot Enforcer | Cybernetic officer | Chest badge laser | Riot-baton fist | Grenade launcher |
| 7 | Infra. Malfunction | Power-line robot | Transformer laser | Pole sledgehammer | Tracking plasma bolts |
| 8 | Corporate Prototype | Business suit android | Arc reactor laser | Telescopic piston | Micro-missiles |
| 9 | Dumpster Maw | Mechanical dumpster | Incinerator laser | Crane arm punch | Mortar missiles |
| 10 | Code-Violation | Cyber-preacher | Neon storefront laser | Telescopic pike | Plasma missiles |
| 11 | Sewer Gator King | Mutant hybrid | Toxic sac laser | Webbed fist | Toxic bubbles |
| 12 | Hive-Mind Roach | Mutant enforcer | Chemical gland laser | Scythe arm | Homing swarm-bugs |
| 13 | Sludge Elemental | Waste-shape | Street lamp laser | Sludge fist | Tracking waste blobs |
| 14 | Mole Miner | Mutant miner | Industrial headlamp | Drill fist | Rocket-drill bits |
| 15 | Bodega Kingpin | Cyber-human | Neon medallion laser | Rocket punch | Heat-seeking drones |
| 16 | Neon Spray Painter | Anarchist human | Chemical chamber laser | Paint-roller hammer | Tracking canisters |
| 17 | Deep-Fryer Cook | Mutant cook | Deep-fryer laser | Cast-iron skillet | Grease-balls |
| 18 | Wire-Stripper | Scavenger human | Car battery laser | Grappling wire-fist | Tracking spark-nodes |
| 19 | Cyber-Doc | Surgeon human | Defibrillator laser | Scalpel strike | Homing syringes |
| 20 | Tech Smuggler | Merchant human | Mainframe laser | Spring-loaded crowbar | Tracking microchips |
| 21 | Glitched Hologram | Rogue AI | Projection lens laser | Digital fist | Tracking code blocks |
| 22 | Rogue Arcade Cab. | Rogue AI | Coin-slot laser | Joystick arm | Pixel fireballs |
| 23 | Delivery Drone | Rogue AI | Barcode scanner laser | Crane arm | Parcel-bombs |
| 24 | Billboard Overlord | Rogue AI | Display matrix laser | Support beam | Tracking rockets |
| 25 | Trash-Compactor | Rogue AI | Pressure gauge laser | Metal plate hand | Scrap metal blocks |
| 26 | Raccoon Rival | Animal hybrid | Bio-battery laser | Dump-truck claw | Tracking trash cans |
| 27 | Alley Cat Siren | Animal hybrid | Vocal amp laser | Cyber-claw | Tracking neon balls |
| 28 | Cyber Pit Bull | Animal hybrid | Shock-collar laser | Metal-gloved hook | Tracking spikes |
| 29 | Electric Eel | Hybrid/Mutant | Bio-electric laser | Tail arm whip | Ball-lightning orbs |
| 30 | Pigeon Lord | Hybrid | Radio scanner laser | Falcon-talon punch | Robotic pigeons |

### Notes
- Lasers fire from the body's natural "power source" (badge, chest, maw, etc.) — fits the existing chest-cannon jumbotron mechanic.
- Punch = single STRIKE phase target. Salvo = SALVO phase (2-3 simultaneous punch-back projectiles).
- Each boss needs: portrait image + per-attack sprite(s). Folder: `assets/sprites/Enemies/<boss_name>/`.
- Current 5 zone bosses (female cyborgs) map to zones 1-5. Remaining 25 are candidates for zones 6-30 or rotating pools.

---

## Player Characters

### Faction: The Sump Goblins
| Character | Perk |
|-----------|------|
| The Rogue Line Cook | Immune to thermal/grease hazards |
| The Soda-Jerk Mutant | Can carry two power-ups simultaneously |
| The Dishwasher Automaton | Trailing soap bubble animation |
| The Boombox Nomad | Slide clears small obstacles |
| The Roller-Derby Rebel | Speed boost for perfect lane-switches |
| The Hazmat Scavenger | Immune to toxic sludge |

### Faction: Feral Urban Wildlife
| Character | Perk |
|-----------|------|
| Sewer Rat Skate-Punk | Small hitbox; slides under low beams |
| Alley-Cat Burglar | Can wall-run to avoid potholes |
| Trash-Bag Raccoon | Dash breaks through cardboard barriers |
| Carrier Pigeon Rebel | Flutter jump over gaps |
| Cyber-Opossum Cadet | Invincible but immobile "play dead" move |
| Junkyard Badger | Saws through wooden barricades |

### Faction: Scrap-Yard & Infrastructure
| Character | Perk |
|-----------|------|
| Wire-Stripper | Pulls gems via built-in magnet |
| Pothole Surfer | Grinds over obstacles |
| Buggy Builder | Smashes one heavy obstacle per run |
| Cable-Management Troll | High health (3 hits before death) |
| The Pothole Inspector | Patches potholes with rubble |

### Faction: Defected AIs
| Character | Perk |
|-----------|------|
| Arcade Token Kid | Leaves ticket trail; drops invincibility stars |
| Short-Circuited Strobe | Jumps over obstacles automatically |
| Hacked Security Drone | Hovers at leg-level |
| Glitched Hologram | Phases through projectiles |

### Faction: The Inner Circle (Premium)
| Character | Perk |
|-----------|------|
| Gemma | "Faceplant Slide" — accidental but effective |
| Claude | "Slight of Hand" — hotwires machines for gems |
| The Serbian | "Battle-Cry Tic" — shatters debris in adjacent lanes |
| Stew | "AI Override" — freezes drones and traps |
| Dr. Hoodie | "Extended Vitality" — regenerates health over time |

### Faction: 101st Veterans
| Character | Perk |
|-----------|------|
| Supply Sergeant | Starts each run with a high-tier power-up |
| Cryptologic Analyst | Predicts track layout ahead (obstacle preview) |
| Motor-Pool Grease-Monkey | "Piston Kick" — shatters obstacles on contact |
| Dish Pit Berserker | Dissolves sticky/grease hazards |
| Exhaust-Hood Phantom | "Smoke Screen" — breaks missile lock-on during boss salvos |

---

## Implementation Priority
1. Current 5 zone bosses: female cyborgs (jumbotron portraits done, salvo + single-strike wired)
2. Next boss batch: needs art → new session. One folder per boss, portrait minimum.
3. Salvo projectiles: currently use NPC goblin texture — replace with glowing energy orbs (no art needed, procedural).
4. Playable characters: all share possum cutouts for now. Per-character models = ComfyUI session.
5. Character perks: flavor only currently — mechanical hookups are post-art-pass work.
