# Architecture

Last verified against the code: 2026-11-20 (branch `feature/quick-wins`). Facts here were checked by running the game headless and reading the code, not copied from older docs. The original design pack (`docs/design/01_GAME_FOUNDATION.md`, `02_TECHNICAL_LAYERS.md`, `03_BUILD_ROADMAP.md`) is the intent; this file is what exists. Where they differ, this file and the code win.

## 1. The one rule that shapes everything

**The simulation is authoritative and runs headlessly; the view only reads it and submits commands.**

- `sim/` never references `view/` or `app/` (the CI layout checker `tools/check_layout.py` fails on it).
- The view never owns money, goods, needs or world state. A click becomes `sim.submit("command", payload)`; the simulation applies it on the next tick.
- Same seed + same commands = same world. Saving, loading and continuing must give the same `state_hash()`.

## 2. Folder map (all inside `source/`)

| Folder | Contents |
|---|---|
| `sim/core/` | `simulation.gd` (the kernel), `sim_clock.gd`, `random_streams.gd`, `canonical.gd` (state hash), `derived_cache.gd` |
| `sim/world/` | `world_db.gd` (cells, chunks, entities, buildings), `town_layout.gd`, `road_planner.gd`, `terrain.gd`, `weather.gd`, `fixtures.gd`, `placement.gd`, `orient.gd`, `spatial.gd`, `fidelity.gd`, `chronicle.gd` (event record) |
| `sim/entities/` | `residents.gd` (people and their goals), `households.gd`, `family_economy.gd`, `needs.gd`, `outfits.gd`, `speech.gd`, `gossip.gd`, `fear.gd`, `chests.gd`, `names.gd` |
| `sim/factions/` | `society.gd` (memories, opinion, migration), `reputation.gd`, `risk_system.gd` |
| `sim/law/` | `law.gd` (crimes, wanted, arrest, jail), `sheriff.gd`, `witness_reports.gd`, `trespass.gd` |
| `sim/combat/` | `shotgun.gd` (the player's guns: rifle and shotgun), `gunfire.gd` (alerts, sheriff tactics), `cover.gd`, `wounds.gd`, `bleeding.gd`, `limbs.gd`, `body_health.gd`, `brawl.gd`, `unarmed.gd`, `takedown.gd`, `local_combat.gd` |
| `sim/economy/` | `market.gd`, `stall_service.gd`, `traders.gd`, `regional_trade.gd` |
| `sim/player/` | `player_actions.gd`, `context_actions.gd`, `dialogue.gd`, `talk.gd`, `requests.gd`, `carrying.gd`, `encumbrance.gd`, `look.gd`, `sleep.gd`, `hotbar.gd`, `looting.gd`, `door_assist.gd`, `player_status.gd` |
| `sim/settlement/` | `professions.gd`, `housing.gd`, `planner.gd` (construction), `dustvale.gd` |
| `sim/` others | `movement/` (`nav_grid.gd`, `navigation.gd`, `pace.gd`), `jobs/job_board.gd`, `farming/crops.gd`, `inventory/inventory_store.gd`, `production/` (recipes, content loader), `persistence/save_manager.gd`, `diagnostics/` (`invariants.gd`, `perf_probe.gd`) |
| `view/world/` | `world_view.gd` (draws the world), `landscape.gdshader`, `frontier_map_art.gd`, `interior_art.gd`, `fixture_art.gd`, `prop_art.gd`, `crop_art.gd`, `road_surface.gd`, `observer_camera.gd` |
| `view/actors/` | `animation_director.gd` (decides each person's pose), `drawn_character.gd` (draws a person), `character_3d.gd`, `frontier_character.gd`, `build_motion.gd` |
| `view/ui/` | `trade_window.gd` (Trade/Talk), `journal_window.gd`, `medieval_map.gd`, `map_overlay.gd`, `inventory_window.gd`, `player_panels.gd`, `health_window.gd`, `bottom_bar.gd` (hotbar), `moodles.gd` (condition icons), `main_menu.gd`, `context_menu.gd`, `item_icons.gd`, `knockout_screen.gd`, `perf_overlay.gd`, others |
| `view/audio/` | `world_audio.gd` (all sound) |
| `app/` | `main.tscn`, `world_controller.gd` (input, wiring, saves, camera), `input_settings.gd`, `save_slots.gd`, `save_migration.gd` |
| `content/` | `items/core.json`, `recipes/*.json`, `art/`, `audio/`, `biomes/`, `buildings/`, `professions/` (most tuning tables are still in `.gd` files) |
| `tests/` | `sim/` (56 files), `view/` (20), `soak/` (1), `benchmark/` (6), `captures/` (49 screenshot scripts). `scripts/test.sh` lists every test to run |
| `scripts/`, `tools/` | `play.sh`, `test.sh`, `export.sh`, `package_*.sh`; `check_layout.py`, asset generators |
| `docs/` | `design/` (original pack + decision log), `status/` (changelog, older status), `validation/` (benchmark records), `screenshots/`, and the handover set (this file's siblings) |
| repo root | `Project Solo.app` (Mac launcher, must stay first in the folder), `README.md`, `.github/` (CI), `source/` |

## 3. The simulation kernel

`sim/core/simulation.gd` is the `Simulation` class. Everything lives in one dictionary, `sim.state`.

- **Ticks:** 10 per second at 1x speed. 10 ticks = 1 in-game minute, 600 = 1 hour, **14,400 = 1 day**. Tick 0 is midnight on day 1, the first day of summer; a new game starts at tick 4,200 (07:00). The day has four parts (`sim/world/day_clock.gd`): morning 04-10, day 10-16, evening 16-22, night 22-04. Light, the sun, sleep and shop hours all read that one file.
- **Clock:** `sim_clock.gd` turns frame time into whole ticks. At most 10 ms of simulation per frame, and the backlog is clamped so one slow tick cannot snowball. The tick count, not wall time, is the authority.
- **Commands and events:** two queues in state, `commands` and `events`, drained at the start of each step in due-tick then id order. Player actions are the strings in `PLAYER_ACTS`. `submit(kind, payload)` queues a command.
- **Randomness:** `sim.random_int("stream_name", low, high)`; each stream is an independent seeded generator stored in `state.rng`. Streams in use include `brawl, speech, wounds, gunfire, shotgun, talk, gossip, bribe, haggle, family, names, weather:kind`. Give each new feature its own stream.
- **Hash and saves:** `state_hash()` hashes the canonical form (`canonical.gd`). `snapshot()` is a deep copy of state; `restore()` loads one and runs upgrade functions for older saves (names, needs, layouts, fixtures, chests, purses, signposts).
- **Derived caches:** lookups that would otherwise walk all ~6,300 entities (by kind, buildings, trees by cell, walk grids) live in `DerivedCache`, outside state, are never saved, and rebuild when the world changes.
- **Perf probe:** `perf_probe.gd` times each system per step for the F4 tab and the benchmarks. It is never part of state.

### 3.1 What one tick does (`Simulation.step`)

In order: drain commands, drain events, then (once residents exist):

1. `Weather` → `Unarmed` → `Brawl` → `Law` (also runs witness reports) → `Gunfire` → `Fear` → `Bleeding` → `StallService` → `FamilyEconomy` → `Speech` → `ContextActions` → `LocalCombat`
2. The player's route walking (click-to-walk, travel, sleep fast-forward uses the clock, not this)
3. `Jobs.refresh` (every 10 ticks), `Fidelity` + `Regional` (traders) → `Residents` → `Society` + `Risk` → `Recipes` → `Planner`
4. Markets (tents every 600 ticks, clearing every 300)
5. `BodyHealth` → `Limbs` → `Cover` → `PlayerActions` → `Carrying` → `Trespass` → `Needs` → `Look` → `Sleep` → `Hotbar` → `Shotgun`
6. At tick % 14400 == 7200 (**12:00**): `Households.daily()` (which also runs `FamilyEconomy.ensure`, `Gossip.daily`, `Requests.daily`, `Reputation.update`). At == 11400 (19:00): `FamilyEconomy.payday`. Then `Crops.update`; at == 0 (midnight) trees regrow.

Other timed events: 06:00 autosave (in `world_controller.gd`, view-side), 07:00 family shopping, residents' garden hours 06:00-07:30 and 17:30-19:30.

## 4. The world

- **Size:** `world.bounds = [-96, -84, 486, 336]` (582 x 420 cells, 1 cell = 1 m), 64-cell chunks. (`WIDTH=128, HEIGHT=96` in `world_db.gd` are only fallback defaults.)
- **Towns** (warehouse cell): Alder Hollow `[64,46]` (west, wooded), Reedbank `[364,46]` (east), Dustvale `[150,250]` (south, dry, ore). 6 residents each at new-game start (18 total) plus the player, who starts with ~1000 coins in `accounts`.
- **Entities:** about 6,400 at start, nearly all trees; plus warehouses, homes (13), farms, sawmills, bakeries, forges, ore rocks, market stalls (18), offices (3), signposts (3), chests (23).
- **Roads:** `road_planner.gd` routes three links with shared trunks and forks; `world.roads` holds segments and junctions; signposts at forks carry measured `ways` (distance and heading to each town). `pace.gd` makes walking about 15% quicker on town streets and 30% on link roads (integer maths with a carried fraction).
- **Fidelity:** residents far from the player run at "coarse" or "aggregate" fidelity (`fidelity.gd`) so they cost less; identity, goods and needs survive every transition.
- **Weather:** one record per town (`state.weather.regions`, re-rolled every 3,600 ticks from each town's climate); the top-level record is the player's town. Seasons are 15 days, starting with summer (`Weather.season`, `SEASON_OFFSET`).

## 5. Key state (`sim.state`) by area

| Area | Keys |
|---|---|
| World | `world`, `entities`, `crops`, `weather`, `settlements`, `routes`, `construction`, `building_defs` |
| People | `residents`, `households`, `outfits`, `names_used`, `jobs`, `caravans` (traders), `factions` |
| Money and goods | `inventories`, `accounts` (coins; keys are entity ids, `household:<key>`, warehouse ids), `accounting`, `money_initial`, `markets`, `trades` |
| Player | `player` (entity id), `player_control` (input, notices, jail, trespass, carrying), `player_needs`, `player_health`, `player_status` (look, met, heard...), `shotgun` (the active gun state, kind rifle or shotgun), `hotbar` |
| Law and social | `law` (`wanted`, `alert`, `hidden`), `chronicle`, `chronicle_next`, `reputation`, `requests`, `requests_next` |
| Combat | `brawl`, `local_combat`, `limbs` |
| Engine | `tick`, `seed`, `rng`, `commands`, `events`, `next_id` |

Per resident (`state.residents[id]`): `settlement, occupation, household, partner, age_days, health, goal, path, status, fidelity, memories (max 16), relations (max 32), rumours (max 8), anger, knock, brawl, arrest, reporting, serving, bandaging, fear, sleeping`. New fields must default through `.get()` so old saves load.

## 6. How the systems interact (the important flows)

**A crime (the longest chain).** `Law.crime(s, town, kind, victim)` →
1. `Law.remember_crime` writes a **chronicle** entry (`sim/world/chronicle.gd`: kind, actor, victim, cell, and **witnesses** = awake people within 16 cells with a clear line of sight) and **memories** (`Society.witnessed`: victim in full, family at half, witnesses a lesser one).
2. The chronicle calls `Gossip.witnessed` so witnesses know at once; they spread it by chat, family and traders.
3. If a sheriff saw it (within 24 cells; for silent crimes only with line of sight) he arrests at once (`Law.file` + arrest flow). Otherwise `WitnessReports.send` makes the nearest awake witness run to a sheriff; the crime is filed when they arrive (`Law.file`). No witness: the crime is stored in `s.law.hidden` (see `DEVELOPMENT_STATUS.md`: nothing reads it yet).
4. Wanted records say how the culprit is known: by face (a sheriff saw) or by the clothes a witness described (`Law.recognised`).
5. Each day `Reputation.update` sums what each town knows (witnessed there, or `heard_in` via gossip) into a standing per town.
6. Standing and memories feed back: prices (`StallService.price`), greetings (`Speech`), the Talk tab, haggling.

**Trade.** Residents and stalls hold real inventories. `Market.quote` prices from stock; `Market.transact` moves goods and coins together (conserved). The player trades through `StallService` (a keeper hurries to an unstaffed stall first) and `PlayerActions.trade`. Families hold a purse (`FamilyEconomy`): jobs earn wages at payday, mornings include shopping, traders arbitrage between towns.

**Combat.** The player fires through `Shotgun.fire` (a weapon table: `WEAPONS` rifle and shotgun; bullets are simulated projectiles with strength and speed). A shot calls `Gunfire.on_player_shot`, which decides which town hears it (`town_in_earshot`) and raises an alert that makes sheriffs fight from cover to cover (`cover_cycle` phases hide, peek, fire, advance, bandage); villagers who see it run for cover (`Fear`). Hits go through `Wounds.shoot` → limbs, bleeding (`Bleeding`), knockdown or death (`Brawl.kill`). Silent takedowns (`Takedown`) bypass sound.

**Talking.** The Trade/Talk window (`view/ui/trade_window.gd`) draws what `sim/player/dialogue.gd` lists; choices submit `context_action` commands handled in `context_actions.gd`, which call `talk.gd` (tone, bribes, persuasion) and `requests.gd` (favours). The journal (`journal_window.gd`) only reads state.

**Player input path.** `app/world_controller.gd` reads keys/mouse → `simulation.submit(...)` → the kernel applies the command → views read state each frame (`world_view.gd` draws; `animation_director.gd` picks poses; UI windows redraw when their content changes). `ContextActions.request` makes the player walk to the target and then `perform` the action.

## 7. Persistence

- `sim/persistence/save_manager.gd`: checksummed Godot binary envelope; writes `.tmp`, verifies, keeps a `.bak`, renames. `load_into` falls back to `.bak`.
- `app/save_slots.gd`: quick save (F5, `project_solo.save`), two rotating autosaves written at 06:00 (`autosave_a/b.save`), `.info` JSON beside each (day, time, town, when written), Continue/F9 load the newest. The slow part of a save runs on a background `Thread`; only the 12 ms state copy is on the main thread.
- `app/save_migration.gd`: one-time copy of saves from before the game was renamed.
- Saves are `user://`: on macOS `~/Library/Application Support/Godot/app_userdata/Project Solo/`.

## 8. View layer

`world_view.gd` owns drawing; `animation_director.gd` computes each person's pose from sim state (never changes it); `drawn_character.gd` paints them (the player's beard and dust/blood tint come from `player_status.look`). UI windows are `Control`s that read `sim.state`. The map (M) is a parchment image painted once per opening (`medieval_map.gd`), so it costs nothing per frame. All sound is in `world_audio.gd`; there is deliberately no looping ambient sound (a wrong loop point once caused a repeating click).

## 9. Testing, CI and performance tooling

- Every test is a `SceneTree` script ending in `quit(failures)` and printing `Name: PASS`. `scripts/test.sh` runs the list (77 tests including the 7-day soak, about 13 minutes locally, about 20 on GitHub).
- `tools/check_layout.py`: dangling `res://` paths, broken markdown links, a test not in `test.sh`, `sim/` depending on `view/app`, and stray Finder copies named like `name 2.gd`.
- Benchmarks (`tests/benchmark/`): `full_game_benchmark.gd` (headless), `view_benchmark.gd` (windowed, four zooms and the map; `SOLO_BENCH_LABEL=x` writes `docs/validation/view_benchmark_x.json`), plus per-layer and animation benchmarks.
- Captures (`tests/captures/`): screenshot scripts, run in a real window with `SOLO_SHEET_DIR=<dir>`.
- CI (`.github/workflows/`): `tests.yml` (regression, Ubuntu; 20-minute limit on this branch, 45 on PR #13's branch), `build.yml` (Mac and Windows artifacts).
- Performance measured on an Apple M4, 1280x720 window, 2026-11-20 after step 4: about 79 FPS at zoom 2, 57 at zoom 1, 46 at 0.5, about 1,000 on the map; headless worst tick about 12 ms, 99th percentile 3.4 ms. Rules and budgets: `docs/ROADMAP.md` section 6.

## 10. Where to add things

| To add... | Touch |
|---|---|
| A player command | add the string to `PLAYER_ACTS` in `simulation.gd` and handle it in `apply_command` (or a context action in `context_actions.gd`) |
| A talk line or tone | `dialogue.gd` (list) + `talk.gd` / `requests.gd` (effect) + `context_actions.gd` (route) |
| A memory kind | `MEMORY_KINDS` in `society.gd` (weight and fade days) and write it with `Society.remember` / `witnessed` |
| A recorded event | `Chronicle.record(...)`; gossip, reputation and the journal read it |
| A weapon | an entry in `Shotgun.WEAPONS` + an icon in `item_icons.gd` + item weight in `encumbrance.gd` |
| A crime | `SENTENCE` and `CRIME_NAMES` in `law.gd`, call `Law.crime` |
| A daily rule | `Households.daily()` (12:00) |
| New player state | a key in `player_status` via `PlayerStatus.part(s, key, default)` |
| A test | `tests/sim/<name>_test.gd`, then list it in `scripts/test.sh` |
