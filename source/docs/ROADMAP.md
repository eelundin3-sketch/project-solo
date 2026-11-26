# ROADMAP: the master plan for the remaining work

> **This is the full plan with a detailed brief for every remaining feature (about 2,200 lines, 160 KB).**
> Do NOT load it whole. Read section 1 (where things stand) and then only the one milestone you are building:
> `grep -n '^## MILESTONE' docs/ROADMAP.md` lists them; each milestone has its features as `### CODE. Title`.
>
> Copied into the repo on 2026-11-20 from the owner's Desktop file `Project_Solo_Plan.txt` so it survives with the code.
> **Corrections made while copying (verified against the code):**
> - The map is 582 by 420 cells, not 128 by 96. (`world.bounds` is `[-96, -84, 486, 336]`; 128 by 96 are only fallback defaults in `sim/world/world_db.gd`.)
> - `Households.daily()` runs at 12:00 (tick 7200 of the day), not "each morning". Morning events are the 06:00 autosave and the 07:00 family shopping.
> - Sections 2b and 2c below say what existed before and after steps 1-4; where they differ, 2c is current.
> - For what is built, what is partly built and what is broken, `docs/DEVELOPMENT_STATUS.md` is the authority, not this file.

# PROJECT SOLO: THE PLAN

Last updated 2026-11-19. This single file replaces the three earlier plan files. Those are kept in the folder **Project Solo – old plan files** on the Desktop.

**What's in this file:**
1. Where things stand: what's built and what's loose.
2. The rules, and the systems that exist now (read before building).
3. How each milestone is built.
4. The milestones, in order, each with the full brief for every feature.
5. Optional ideas not yet chosen.
6. Performance: the FPS rules and budgets.

**Using it with an AI assistant later:** paste section 2, the section 3 checklist, and the one milestone you want. Ask it to read the code and show you a plan before building.

---

## 1. WHERE THINGS STAND

All of this is on the local branch `feature/quick-wins`, committed and not pushed. The last full check passed all 77 tests, with about 79 FPS at normal zoom and a worst sim tick of 12 ms.

### Built
- **Steps 1–2:**
  - carrying weight (C1);
  - hit reactions (L8);
  - autosave each morning, Continue on the title screen, F9 loads the newest save, and saving runs in the background (part of I3);
  - signposts with distances (W8);
  - crash-safe saves, which were already there (X3);
  - the foundations: memories that fade, the chronicle, reputation per town, the Talk/Trade window, and the player record (F1–F5).
- **Step 3:**
  - memory of you (P1);
  - witnesses run to the sheriff, and an unseen crime stays unsolved (L1);
  - gossip that grows in the telling (P2);
  - body carrying (C2);
  - "get out of my house" (C3);
  - your looks change: beard, dust, mud, blood, wash, shave (C4);
  - bandaging someone is remembered.
- **Your requests:**
  - the rifle is the main gun (the shotgun still works);
  - gunshots are heard (a rifle 60 cells, a shotgun 45);
  - silent kills and knock-outs from behind, reported only if someone sees.
- **Step 4:**
  - tone in talk (T1);
  - bribe or talk your way out of an arrest (T2);
  - favours (T3);
  - the journal on J (G4);
  - standing on the map (G2).
- **Milestone 5 (2026-11-20, local commits):**
  - night lighting with street lamps, lit windows and a lantern; `Light.level` for stealth (V1);
  - weather per town, drought hurting crops, trades by climate, farming families moving (C5);
  - mud slows walking on roads, fog shortens sight, rain and snow particles, wet ground (W1);
  - seasons and harvest (E7); seasonal colours (V2); price trend arrows and known prices (E1).
  - **[owner]** four parts of the day (morning 04-10, day 10-16, evening 16-22, night 22-04) drive light, sun shadows, sleep (bed 21-22, up 06-07) and shop hours; 15-day seasons; a new game starts on the first day of summer at 07:00.
  - Not done: lanterns are not sold yet; autumn trees only shift toward olive (the tree art needs autumn leaves); no rain sound (S3).

### Loose ends, and where they now go
| Loose end | Goes in |
|---|---|
| Wanted posters | 6, with C7's notice board |
| Named save slots | 9, with I2's pause menu |
| Buying clothes and gifts | 9, with B18 |
| Courier and "find someone" favours | 9, as a small T3 extension |
| A proper pose for carrying a body | 7, with A4 |

### The order at a glance
| Milestone | Theme | Sessions |
|---|---|---|
| 5 | Night, weather and seasons | ~2 |
| 6 | Towns with politics | ~2–3 |
| 7 | Stealth and combat depth | ~2–3 |
| 8 | Crime and punishment | ~2 |
| 9 | Making a life | ~3 |
| 10 | Family and legacy | ~2–3 |
| 11 | Outlaws and towns changing hands | ~3 |
| 12 | The shape of the game | ~2–3 |
| 13 | Sound and the wider world | ~3–4 |
| 14 | Technical and the final pass | ~2 |

**Total:** about 24–28 sessions (one session is about one long working stretch). Every milestone ends playable, tested, at 60+ FPS, and committed locally.

---

## 2. RULES AND WHAT EXISTS

### 2a. Project rules (apply to every milestone)

**Game:** Project Solo, a single-player, 2D, deterministic frontier simulation in Godot 4.6 with GDScript. Three towns (Alder Hollow, Reedbank, Dustvale) on a 582 by 420 cell map (bounds x -96..486, y -84..336), joined by roads with signposts.

**Folders:** all game files are in `source/`.
- `sim/` is the authoritative simulation. It runs headlessly with no rendering.
- `view/` draws and animates. Views read sim data and submit commands. **Views never own money, inventory, needs or world state.**
- `app/` is the glue (`world_controller.gd`, `input_settings.gd`).
- `content/` holds data files (`items/core.json`, `recipes/*.json`).
- `tests/` holds the tests. `docs/design/` holds the design documents and the decision log.

**Rules that must hold:**
1. **Determinism.** Same seed and same commands give the same world. Use integer maths and `sim.random_int("stream_name", low, high)`. Never use global random functions in the sim. Give each new feature its own stream name.
2. **Save, load, continue.** `Simulation.snapshot()`, `restore()` and `state_hash()` must give the same hash after a reload. New state fields must have a safe default through `.get("field", default)` so old saves still load. Derived caches (`DerivedCache`) are never saved.
3. **Money and goods are conserved.** All coins live in `s.accounts`; all goods in `s.inventories`. Nothing is created from nothing. `sim/diagnostics/invariants.gd` checks the money sum.
4. **Names are unique.** `s.names_used` is checked when a save loads.
5. **Views never write sim state.** Player actions go through `sim.submit("command", payload)`; the command list is `PLAYER_ACTS` in `sim/core/simulation.gd`.
6. **Tests.** Every `*_test.gd` must be listed in `scripts/test.sh` (`tools/check_layout.py` checks this). Run from `source/`: `GODOT_BIN=/private/tmp/living-world-engine/Godot.app/Contents/MacOS/Godot sh scripts/test.sh`. The whole suite (77 tests, about 13 minutes) must pass before the next idea starts. A change that cannot be unit tested needs a stated reason.
7. **Repository contributor rules (`source/AGENTS.md`):** read `docs/design/01_GAME_FOUNDATION.md`, `02_TECHNICAL_LAYERS.md` and `03_BUILD_ROADMAP.md` first; log any change to a core contract in `docs/design/DECISIONS.md`; no external plugins without approval; do not build a future milestone inside a narrower task; every task ends with a runnable demonstration and a list of changed files, validations run and known issues; keep all art, names and content original.
8. **Git:** commit locally, one commit per idea. Do not push, open PRs or merge until the owner asks for "the big push".
9. **Untracked clutter:** Finder duplicates named like "something 2.gd" exist in the folders. Never stage them. Godot's `.uid` files for new scripts should be committed with the script.

**Time and units (verified in the code):**
- 1 tick is the sim step. 10 ticks = 1 in-game minute. 600 ticks = 1 hour. **14,400 ticks = 1 day.** At normal speed that is about 10 ticks per second, so a day takes about 24 real minutes.
- `s.weather.kind` is "clear", "rain", "fog" or "snow". Seasons are 15-day blocks starting with summer: `Weather.season(s)` (0 spring, 1 summer, 2 autumn, 3 winter; `SEASON_OFFSET = 1`). The day has four parts in `sim/world/day_clock.gd`: morning 04-10, day 10-16, evening 16-22, night 22-04. A new game starts at 07:00 on day 1 (summer).
- Coordinates are integer cells `[x, y]`. Distances use cells.

### 2b. Systems that were already there before steps 1–4

Use this before writing any plan. Many "new" ideas are extensions of these.

**Where 2b and 2c disagree, 2c is current.** For example:
- witnesses are now townspeople too;
- the rack holds rifles;
- memories are used everywhere.

**People and families**
- `sim/entities/residents.gd`: each resident has `settlement`, `occupation`, `household`, `partner`, `age_days`, `health`, `goal`, `path`, `status`, `fidelity`, `skill`, `memories` and `relations`. Goals run through `set_goal` and `_need_action`.
- `sim/entities/households.gd` (`daily()` runs at 12:00): children grow up after 8 days (`CHILD_GROWN_DAYS`); single adults pair up (`_pair_up`, 40% chance a day, from age 16 days); couples move in together (`_move_in_together`); births (`_births`, up to 3 children, only with room, food and after 3 days together). **So pairing, births and growing up already exist. Aging, death by age, weddings, funerals and inheritance do not.**
- `sim/entities/family_economy.gd`: each household has a purse (`s.accounts["household:<key>"]`), profession pay at payday, morning shopping, pantry stocking, and shared surnames.
- `sim/factions/society.gd`: **`remember(s, npc_id, kind, subject, text, trust_delta)`** is an existing memory system. Each resident keeps up to 16 `memories` (`tick`, `kind`, `subject`, `text`) and up to 32 `relations` (`trust` from -100 to 100, `last_tick`). It is used today only for a few events (a helpful delivery, migration). `migrate()` moves a resident to another town; every 14,400 ticks an over-crowded town sends someone to a town with free housing. Every 600 ticks a town sets `town.policy` to "Food first", "Build homes" or "Balanced". **That field name is taken: new town laws must use a different field name (`town.laws`).**
- `sim/settlement/professions.gd`: **profession demand is already derived from the land.** `settlement_resources()` counts trees, ore, fields, population and danger near the town; `demand()` turns that into how many Farmers, Woodsmen, Sawyers, Miners, Blacksmiths, Bakers, a Sheriff and a Trader a town wants. `Professions.assign` runs daily.
- `sim/entities/speech.gd`: speech is a table of canned lines (`LINES`) picked by `sim.random_int("speech", ...)`; idle neighbours chat every 120 ticks; people greet the player.
- `sim/entities/outfits.gd`: hat, vest, shirt, pants, boots, backpack, each a variant; stored only when changed (copy on write); pieces are real inventory items.
- `sim/entities/needs.gd`: player conditions are bleeding, pain, hungry, thirsty, tired, stressed, unhappy, **wet** and **cold**. Wet and cold already come from weather and night (rain makes you wet outdoors; snow and night make you cold).

**Law and combat**
- `sim/law/law.gd`: `crime(s, town, kind, victim)` records crimes per town in `s.law.wanted[town] = {hours, crimes, since}`. The only witnesses are **sheriffs within 24 cells** (`WITNESS_RANGE`) or the victim. Murder and theft are reported even with no witness. Sentences come from a fixed table (`SENTENCE`). There is a full arrest flow: standoff, cuffing, escort, booking, cell, release. There are no civilian witnesses, trials, bail or bounties.
- `sim/law/sheriff.gd`: sheriff rosters per town, desk and patrol duty, a rack of shotguns, bandage kits.
- `sim/combat/gunfire.gd`, `cover.gd`: sheriffs fight from cover to cover (hide, peek, fire, advance, bandage). Cover heights are HIGH or LOW.
- `sim/combat/brawl.gd`: punches, knock-outs (`KO_HEALTH`, `KO_TICKS` = 420), anger (`ANGER_PUNCH`, `HOSTILE_AT` = 50), blood decals, chasing and giving up.
- `sim/combat/limbs.gd`: arm and leg damage (`HURT_AT` 25, `DISABLED_AT` 60). **A bad leg already slows walking (`step_ticks`) and can make the player crawl (`crawling`); a disabled arm already affects aiming (`can_aim`).** `sim/combat/bleeding.gd`: bleeding and bandages for everyone.

**Economy**
- `sim/economy/market.gd`: **prices already follow supply.** `quote()` = `BASE * TARGET / (stock + TARGET/2)` for each item in each town's store, clamped 2 to 100. `transact()` moves goods and coins and keeps both conserved. Tents (`TENT_STOCK` 8, `TENT_FUNDS` 150) and stalls exist.
- `sim/economy/traders.gd`: traders pick the best price gap (`best_deal`, `MIN_MARGIN` 2) and walk the roads. `regional_trade.gd`: caravans between towns.
- `sim/economy/stall_service.gd`: keepers hurry to a stall, haggling, "Ask about family" and "Ask for news".
- `sim/farming/crops.gd`: field plots grow in 43,200 ticks (3 days) from sowing to ripe, 3 yield per cell, no seasons or rain effect.

**World**
- `sim/world/world_db.gd`: chunked cell world, entities, buildings. `terrain.gd` is only woodland noise: **there is no water, river or terrain type.** `road_planner.gd`, `town_layout.gd`: roads, junctions, signposts. `weather.gd`: one global weather for the whole map, re-rolled every 3,600 ticks. `fidelity.gd`: detailed, coarse and aggregate levels of simulation.
- Player: `sim/player/` has context menus (`context_actions.gd`, per-part options for bed, table, chair, lamp, chest, shelf), sleeping (`sleep.gd`), trading, looting, hotbar, auto-travel (`travel`).

**View**
- `view/ui/trade_window.gd` (parchment conversation and trade window), `medieval_map.gd` (the drawn map), `moodles.gd` (condition icons), `inventory_window.gd`, `game_hud.gd`, `main_menu.gd`. `view/actors/animation_director.gd`, `drawn_character.gd`. `view/audio/world_audio.gd`. `view/world/world_view.gd` and the art files.

**Data files:** `content/items/core.json`, `content/recipes/core.json` and `example_mod.json`. Item prices (`BASE`, `TARGET`), professions, names and cover heights are still hard-coded in `.gd` files.

---

### 2c. Systems added in steps 1–4 (reuse these; don't rebuild)
- **Memories and opinion:** `sim/factions/society.gd`.
  - Memory kinds have weights that fade (`MEMORY_KINDS`).
  - `opinion(s, npc, subject)` reads them, and `witnessed()` hands them to the victim, family and witnesses.
- **Chronicle:** `sim/world/chronicle.gd`. The last 200 events, with witnesses (awake and in sight). Stored as `s.chronicle`, because `s.events` is the sim's own queue.
- **Reputation:** `sim/factions/reputation.gd`. Worked out each day at 12:00 (inside `Households.daily`) from what each town knows. `summary()` gives the one-line version.
- **Gossip:** `sim/entities/gossip.gd`. News spreads by chat, family and traders, and grows in the telling. Entries get `heard_in`.
- **Witnesses:** `sim/law/witness_reports.gd`. Witnesses run to a sheriff; unseen crimes go to `s.law.hidden`. In `sim/law/law.gd`:
  - `Law.file()` puts a crime on the books;
  - `recognised()` checks your face or described clothes;
  - `crime(..., silent)`.
- **Trespass:** `sim/law/trespass.gd`.
- **Body carrying:** `sim/player/carrying.gd`.
- **Your look:** `sim/player/look.gd`.
- **Carrying weight:** `sim/player/encumbrance.gd`.
- **Player record:** `sim/player/player_status.gd`, with `part(s, key, default)`.
- **Takedowns:** `sim/combat/takedown.gd`.
- **Guns:** `sim/combat/shotgun.gd`. A weapon table (rifle and shotgun), `kind()` and `spec()`. Saves keep the key `s.shotgun`.
- **Earshot:** `Gunfire.town_in_earshot`.
- **Talk:** `sim/player/talk.gd` for tone, bribes and persuasion. `sim/player/dialogue.gd` holds the tabs and the Talk list.
- **Favours:** `sim/player/requests.gd`.
- **Journal:** `view/ui/journal_window.gd`, opened with J.
- **Saves:** `app/save_slots.gd` (autosave, Continue, info files, background saving).
- **Decision log:** `docs/design/DECISIONS.md` records why each of these was done this way.

---

## 3. HOW EACH MILESTONE IS BUILT (the same every time)

1. **Read** the current code for the milestone, and show a short plan for approval.
2. **Benchmark** before starting (view at all zooms, plus the headless world).
3. **Build** one feature at a time, each with its own test, and commit each locally.
4. **Run** the full suite. All tests must pass, including the 7-day save/load soak.
5. **Benchmark** after. Any drop over 10% is fixed before moving on.
6. **Screenshots** for anything visible, checked by eye.
7. **Update** section 1 of this file.
8. **Stop** and show what's playable. Nothing is pushed until "the big push".

**Each brief below has these parts:**
- Status, Size, Depends on;
- Player sees;
- How it works;
- Plugs into;
- Edge cases;
- Performance note;
- Tests;
- Done when.

An **"Update after steps 1–4"** note at the top of a brief overrides anything older in it.

---

## 4. THE MILESTONES

## MILESTONE 5: NIGHT, WEATHER AND SEASONS (the world looks and feels alive)

**Why here:** The biggest change in feel for the work involved, and stealth (milestone 7) needs night.

**Playable check:** Walk from Reedbank (rain) to Dustvale (dry) at dusk. Lamps come on, the road turns to mud, and in autumn the fields are harvested.

**Size:** ~2 sessions.

**Features, in build order:** V1 Night lighting, C5 Rain matters to farmers; professions thrive by region, W1 Weather you can feel and see, E7 Seasons and harvest, V2 Seasonal colours, E1 Prices that react to events (follow supply).

### V1. ★ Night lighting
> **Update after steps 1–4:** Stealth (L7) will read `Light.level(cell)`. Design it in the sim from the start.

- **Status:** NEW. **Size:** M. **Depends on:** nothing. L7 stealth uses it.
- **Player sees:**
  - Nights get properly dark.
  - Houses glow warm from their windows while people are awake inside.
  - At dusk someone lights the street lamps, and people out late carry lanterns.
  - You can carry a lantern too, but it makes you easy to see.
- **How it works:**
  - **Sim:** `lamp_state` per street lamp, lit between 19:30 and 05:30. Lamps are fixtures; add them to town layouts. The lamplighter task can be a simple timed switch at first.
  - **Player lantern:** `player_status.lantern_on`.
  - `Light.level(s, cell)` returns 0 to 100 from the time of day plus lamps within 5 cells plus lanterns. L7 reads it.
  - **View:** a darkness layer (a `CanvasModulate` or a full-screen shader) with light shapes cut out: windows of awake homes, lamps and lanterns. Godot `PointLight2D` is the simplest, but each light costs. Prefer a single light-mask shader fed with up to about 64 light positions per frame.
- **Plugs into:** `view/world/world_view.gd`, `view/world/landscape.gdshader`, `view/world/fixture_art.gd`, `sim/world/town_layout.gd` (lamp fixtures), `sim/entities/needs.gd` (`is_night`).
- **Edge cases:**
  - Indoors, the room is lit when someone is home.
  - The medieval map isn't affected.
- **Performance note:** this is the biggest frame risk in the visuals group. Limit lights to the ones on screen, cap them at 64, and measure `view_benchmark.gd` at night against the noon and midnight baselines (Section 9).
- **Tests:**
  - Lamps are lit at 20:00 and out at 06:00.
  - `Light.level` is high near a lamp and low far away.
  - The benchmark stays within budget.
- **Done when:** walking into town at night, you see warm windows and lamp pools.

### C5. Rain matters to farmers; professions thrive by region
> **Update after steps 1–4:** Weather is still one global record (`sim/world/weather.gd`). This makes it one per town.

**Status:** PARTLY BUILT. Weather exists (but is global) and profession demand already comes from the land. **Size:** M. **Depends on:** nothing (weather visuals come later, under Weather).

**Player sees:**
- Each town has its own weather and character:
  - Reedbank is green and wet, with good farms;
  - Alder Hollow is wooded and mild, with timber and crafts;
  - Dustvale is dry and rocky, with mining and the forge.
- A dry spell in one region leaves its fields brown and the harvest poor. Farmers complain ("No rain in nine days...").
- After a bad season some farming families pack up and move to a town where farming pays.
- In "Ask for news" people talk about the weather and the harvest.

**How it works:**
- **Regions:** the climate for each town lives in a constant table in `weather.gd`, keyed by settlement id. Each entry is rain chance per block (Reedbank 45, Alder Hollow 35, Dustvale 15), fog chance and snow chance.
- **Per-region weather:** extend `weather.gd` from one global record to `s.weather.regions[town_id] = {kind, previous, since, wind, snow, dry_days}`. Keep `s.weather.kind` working: it becomes the weather of the region the player is in, so existing readers (`needs.weather_kind`, the view) keep working. Each region rolls on its own stream, "weather:kind:<id>". `dry_days` counts days without rain.
- **Crops:** in `crops.gd update()`, growth per tick is scaled by the region's rain:
  - normal growth up to 4 dry days;
  - from 5 dry days, half speed;
  - from 9 dry days, plots stop growing and the expected yield drops 1 per cell per 2 extra dry days, to a minimum of 1;
  - rain resets `dry_days`.

  Store the reduction on the plot (`yield_loss`, default 0) so `expected_yield` reads it.
- **Professions by region:** `Professions.settlement_resources()` already counts fields, trees and ore. Add a `climate` factor to `demand()`: in a dry region (rain chance below 20) the Farmer demand is multiplied by 0.5 and the Miner demand by 1.5; in a wet one Farmers ×1.3. This makes each town's mix of trades follow its land and climate.
- **Moving away:** at the daily update (`daily()`, 12:00) after a harvest with a yield of 50% or less of normal, each Farmer household in that town with an empty pantry has a 25% chance (stream "family") to move to the town with the highest Farmer demand that has room.
  - Use the existing `society.migrate()` for each member, and keep the household together: migrate the household key, not single people. `migrate()` today makes a single-person household on arrival, so extend it to carry the household.
  - The purse moves with the household (it is an account; nothing is created or lost).
- Farmers say new speech topics, "drought" and "rain_relief".

**Plugs into:**
- `sim/world/weather.gd` (`initialize`, `update`);
- `sim/entities/needs.gd` (`weather_kind`: keep its meaning);
- `sim/farming/crops.gd` (`update`, `expected_yield`, `harvest`);
- `sim/settlement/professions.gd` (`demand`);
- `sim/factions/society.gd` (`migrate`, `arrive`);
- `sim/entities/households.gd` (`daily`);
- `sim/entities/speech.gd`.

**Edge cases:**
- Old saves have only the global weather: create regions from it on load, with each copying the current kind.
- The road between towns uses the weather of the nearest town.
- A household that moves keeps its surname and purse.
- The town it leaves must keep at least one Farmer if it has fields, so the moving rule skips the last Farmer.

**Performance note:** weather and drought checks run once per block (3,600 ticks) or once per day, so there is no per-tick cost. The crops update already loops over plots, so the extra multiply adds nothing noticeable.

**Tests:**
- Forcing 10 dry days in Dustvale lowers its harvest, and Reedbank's is unchanged.
- Dustvale's Farmer demand is lower than Reedbank's.
- A drought makes at least one farming household move, with its money and members together.
- Money and names are conserved.
- The same seed gives the same weather per region.
- An old save loads.

**Done when:** you can watch Dustvale's fields stay brown in a dry week while Reedbank is green, and later see a farming family arrive in Reedbank.

### W1. ★ Weather you can feel and see
> **Update after steps 1–4:** Mud and fog matter more now: witnesses and recognition use sight distance, and stealth will use light.

- **Status:** PARTLY BUILT. Global weather exists. Per-region weather is in C5. **Size:** M. **Depends on:** C5.
- **Player sees:**
  - **Rain:** falling rain, darker skies, puddles. Roads turn to mud after a day of rain, and walking on them is slower.
  - **Fog:** you see less, and so do others.
  - **Snow:** it settles and leaves footprints (A6). Wind moves the trees and smoke.
- **How it works:**
  - Mud: `road.mud[town] = 0..100`, rising 5 per rain hour and drying 2 per hour. `Pace.delay` gets −15% when mud is above 50 (the road bonus already lives there).
  - Fog cuts the sight ranges in `fear.gd` (`SEE_RANGE`), L1 recognition and L7 detection by 40%.
  - Snow cover already counts up in `s.weather.snow`.
  - The view draws:
    - rain and snow particles around the camera only;
    - a fog overlay;
    - sky tint;
    - a wet, darker ground shader tint;
    - snow cover from `s.weather.snow`.
- **Plugs into:** `sim/world/weather.gd`, `sim/movement/pace.gd`, `sim/entities/fear.gd`, `view/world/world_view.gd`, `view/world/landscape.gdshader`.
- **Edge cases:** indoors there are no particles, but you hear rain on the roof (S3).
- **Performance note:** keep particles to a fixed count around the camera (GPU particles, about 400 to 800). Measure with `view_benchmark.gd` in rain; it must still meet the FPS budget (Section 9).
- **Tests:**
  - Mud slows walking.
  - Fog lowers the sight range.
  - The view test checks particles are present in rain and absent indoors.
- **Done when:** a rainy evening looks and feels different from a clear morning.

### E7. Seasons and harvest
- **Status:** PARTLY BUILT. Seasons exist in `weather.gd`; crops ignore them. **Size:** M. **Depends on:** C5 (per-region weather) recommended.
- **Player sees:** spring sowing, summer growing, autumn harvest, and in winter the fields lie bare and the town lives off its stores. A good autumn means plenty all winter; a bad one means hunger, higher prices and families moving away.
- **How it works:**
  - The season is `(tick / (14400 × 7)) % 4`: 0 spring, 1 summer, 2 autumn, 3 winter (as in `weather.gd`).
  - In `crops.gd`, sowing is allowed in spring and summer only; growth is ×1.2 in summer and ×0 in winter (plots wait); a ripe crop not harvested before winter spoils (yield 0).
  - Winter eating: `family_economy.buy_food` and pantries already feed people, and the warehouse food falls. When the warehouse drops below 20 in winter, prices rise via `quote` (automatic) and C6 prosperity drops.
  - Farmers in winter switch to wood or ore (Professions demand factor ×0 for Farmer in winter).
- **Plugs into:** `sim/farming/crops.gd` (`sow`, `update`, `harvest`), `sim/world/weather.gd`, `sim/settlement/professions.gd` (`demand`), `sim/entities/family_economy.gd`.
- **Edge cases:**
  - Old saves mid-winter: plots keep their growth.
  - The 3-day grow cycle (`CYCLE_TICKS`) fits inside a 7-day season, so two harvests per summer are possible, which is fine.
- **Performance note:** none (a multiply in an existing loop).
- **Tests:** no growth in winter; unharvested crops spoil at winter; winter hunger raises prices; determinism.
- **Done when:** you notice the bare winter fields and rising bread prices.

### V2. Seasonal colours
- **Status:** NEW. Seasons exist in the sim. **Size:** M. **Depends on:** E7 (bare winter fields).
- **Player sees:** the land changes with the seasons: fresh green in spring, deep green in summer, orange and brown in autumn, and white under snow in winter. Trees lose their leaves in winter.
- **How it works:**
  - The season index from `weather.gd` drives palette uniforms in `landscape.gdshader`, plus tree and crop colour tables in `prop_art.gd` and `crop_art.gd`.
  - Blend over the first day of each season.
  - Snow cover already exists (`s.weather.snow`).
- **Plugs into:** `view/world/landscape.gdshader`, `view/world/prop_art.gd`, `view/world/crop_art.gd`, `sim/world/weather.gd`.
- **Edge cases:** the medieval map can keep its own colours.
- **Performance note:** uniforms only, with no redraw of static geometry unless it is cached. If the trees are baked into a texture, re-bake once per season.
- **Tests:** a capture screenshot per season (`tests/captures/` style).
- **Done when:** autumn looks like autumn.

### E1. Prices that react to events (follow supply)
> **Update after steps 1–4:** Prices already follow stock (`market.quote`). This adds only the trend arrows and remembering prices seen elsewhere.

- **Status:** MOSTLY BUILT. `market.quote` already prices by stock, and traders already chase price gaps. **Size:** S. **Depends on:** nothing.
- **Player sees:** what's there today, plus: prices jump after real events (a failed harvest, a raid on a caravan, a fire at the sawmill), and the trade window shows a small arrow for whether each price is rising or falling compared with yesterday, plus "cheaper in Reedbank" hints when you know other towns' prices.
- **How it works:**
  - Keep `quote()`. Add `market.trend[item] = yesterday's quote` (updated daily) for the arrow.
  - Add `player_status.known_prices[town][item] = {price, tick}`, updated when you visit a stall there or hear a trader's rumour (P2). The window shows the best known other town if it's at least 3 coins better.
  - Event shocks happen naturally, because events change stock (C5, C8, fire); no fake multipliers are needed.
- **Plugs into:** `sim/economy/market.gd` (`quote`), `sim/economy/stall_service.gd` (`price`), `view/ui/trade_window.gd`.
- **Edge cases:** known prices older than 3 days show greyed.
- **Performance note:** a daily copy of a small dictionary.
- **Tests:** the trend arrow matches yesterday; known prices update on a visit.
- **Done when:** you buy planks cheap in Alder Hollow because you remember they sell high in Dustvale.

---

## MILESTONE 6: TOWNS WITH POLITICS (towns that react and organise)

**Why here:** Built on reputation, gossip and the chronicle, which already exist.

**Playable check:** After a shooting, Dustvale's safety seal drops, a gun ban and your wanted poster go up on the notice board, and the sheriff makes you holster your rifle.

**Size:** ~2–3 sessions.

**Features, in build order:** C6 Each town has a mood, C7 Town laws (mayor policies), P5 Weekly rhythm (rest day, market day, bad-weather days), P3 Relationships between townspeople, P6 Idle life, P7 Visible moods (view only), A5 Mood icons above heads.

### C6. Each town has a mood
> **Update after steps 1–4:** The chronicle (`sim/world/chronicle.gd`) and reputation per town (`sim/factions/reputation.gd`) exist, so safety can read crimes straight from the chronicle. Use a new field (`town.mood`). `town.policy` is the economy planner's.

**Status:** NEW. **Size:** M. **Depends on:** F2 (event log) recommended. It can start by reading `s.law.wanted` and `market.history` directly.

**Player sees:**
- Each town has three moods shown on the drawn map as small wax seals (gold, red and blue), and spoken about in "Ask for news":
  - **Prosperity:** "Business is good."
  - **Safety:** "People are scared since the shooting."
  - **Loyalty:** "Nobody trusts the council."
- Moods slowly change with what happens.
- Moods change how the town behaves: a frightened town has empty streets at night and quicker sheriffs; a poor town has thin stalls and higher prices; a disloyal town is easier to bribe and quicker to riot.

**How it works:**
- `town.mood = {prosperity: 50, safety: 70, loyalty: 60}` (defaults if missing), integers from 0 to 100. Recompute in `households.daily()` (once per day) as `new = old + (target - old) / 4`, so moods drift over several days instead of jumping.
- **Targets:**
  - **Prosperity target** = 30 + (coins in household purses of this town ÷ households) / 4, + 1 per trade in the last day (from `market.history`, cap +20), − 15 if the warehouse food is below 40.
  - **Safety target** = 80 − 10 × murders in the last 7 days − 3 × other crimes in the last 7 days (from F2 or `s.law.wanted[town].crimes`) − 20 if an outlaw camp is within 40 cells (C8).
  - **Loyalty target** = 60 + (safety − 50) / 3 + (prosperity − 50) / 3 − 10 × unpaid wages, − the tax rate (C7), − 5 × wrongful arrests (C7 or Trials).
- **Effects** (each a small, documented hook):
  - `market.quote` × (1 + (50 − prosperity) / 250);
  - when safety is under 40, residents go home at 20:00 instead of 21:00;
  - when loyalty is under 30, the bribe chance is +20;
  - when safety is under 25 and loyalty under 25, an outlaw takeover can start (C8).

**Plugs into:**
- `sim/entities/households.gd` (`daily`);
- `sim/economy/market.gd` (`quote`, `history`);
- `sim/law/law.gd` (`s.law.wanted`);
- `sim/entities/family_economy.gd` (purses, payday);
- `sim/factions/risk_system.gd` (route risk, which can feed safety);
- `view/ui/medieval_map.gd` (the seals);
- `sim/economy/stall_service.gd` `news()` (lines about the mood).

**Edge cases:**
- **Town policy clash:** don't change `town.policy`, which is used by `society.update`.
- **Empty town:** a town with no households has no prosperity target; use 50.
- **Old saves:** moods start at their defaults.

**Performance note:** once per day per town; all inputs are already-capped lists.

**Tests:**
- Two murders drop safety over the next days.
- Busy trading raises prosperity.
- Values stay within 0 to 100.
- The same seed gives the same moods.
- The quote changes when prosperity drops.

**Done when:** after a shoot-out, Dustvale's red seal drops and people there talk about it.

### C7. Town laws (mayor policies)
> **Update after steps 1–4:** The gun ban should check `s.shotgun.equipped` (it covers rifle and shotgun). Wanted posters, the loose end from witnesses, belong on the same notice board.

**Status:** PARTLY BUILT. `town.policy` exists, but it is only the economy planner's label. **Size:** M. **Depends on:** C6.

**Player sees:**
- Each town has a mayor, a named resident who lives in the biggest house.
- A notice board by the storehouse lists the town's laws: "Curfew after 22:00", "Trade tax 10%", "No firearms drawn in town".
- Sheriffs enforce them: a warning first, then a fine, then arrest.
- Laws change when the mood changes, for example "After the shooting, the mayor has banned guns in town."

**How it works:**
- **Mayor:** `town.mayor = resident id` (default 0, chosen on the first day). Pick the adult with the highest `age_days`, excluding sheriffs and traders, in id order on ties. When the mayor dies or moves, pick again.
- **Laws:** `town.laws = {curfew: false, tax: 0, gun_ban: false, since: tick}`. Use `laws`, never `policy`.
- **Changing laws:** once per day, after the mood is computed (C6):
  - safety under 45 turns on the gun ban; above 65 turns it off;
  - safety under 35 turns on the curfew; above 55 turns it off;
  - prosperity under 35 sets the tax to 0; above 65 sets it to 10.

  Each change writes an event (F2), a log line, and a rumour (Gossip).
- **Enforcement:**
  - **Gun ban:** when `s.shotgun.equipped` is true inside the town footprint and a sheriff sees it (14 cells), the sheriff warns. After 100 more ticks with it still drawn, a "weapon" crime is recorded (add `"weapon": 1` to `SENTENCE`). Holstering (`Shotgun.toggle`) ends it.
  - **Curfew:** residents go home 2 hours earlier. The player outdoors in town after 22:00 gets a warning, and a "curfew" crime after 150 ticks.
  - **Tax:** in `market.transact`, when the seller isn't the town store, `price × tax / 100` goes from the seller to the town treasury account (`str(town.warehouse)`). Round down, so it is conserved because it's just a transfer.

**Plugs into:**
- `sim/entities/households.gd` (`daily`);
- `sim/law/law.gd` (`SENTENCE`, `CRIME_NAMES`, `crime`);
- `sim/law/sheriff.gd` (patrol sees the player);
- `sim/combat/shotgun.gd` (`equipped`, `toggle`);
- `sim/economy/market.gd` (`transact`);
- `sim/entities/residents.gd` (`_decide`: go home earlier);
- `view/world/fixture_art.gd` (the notice board);
- `sim/economy/stall_service.gd` `news()`.

**Edge cases:**
- During a gunfight (`law.alert`) the gun ban doesn't apply: self-defence.
- A deputy start (Starting stories) is allowed to carry.
- Tax must never make a price round to 0, and must never apply to transfers within a household.
- Old saves have no laws, which means nothing is enforced.

**Performance note:** daily decisions only. The enforcement checks reuse the sheriff's existing per-tick view of the player, so add no new full scans.

**Tests:**
- A forced low safety turns the gun ban on, and a drawn shotgun near a sheriff gets a warning and then a crime.
- The tax moves exactly the right coins, and the money sum is unchanged.
- Under curfew, residents are home earlier.
- A mayor is chosen and replaced when they die.

**Done when:** after trouble in Dustvale you read "No firearms" on the board and the sheriff makes you holster.

### P5. Weekly rhythm (rest day, market day, bad-weather days)
- **Status:** NEW. **Size:** S. **Depends on:** nothing.
- **Player sees:** the week has a shape. On the rest day nobody works: people stroll, sit on the green and visit, and the shops are closed. Each town has a market day with extra stalls and traders timing their arrival for it. On rainy or snowy days the streets are quieter.
- **How it works:**
  - `day_of_week = (tick / 14400) % 7`; day 6 is the rest day. Market day: Alder Hollow on day 1, Reedbank on day 3, Dustvale on day 5.
  - On the rest day, `job_board.gd` offers no jobs, stalls are unstaffed except for a food tent, and residents pick leisure goals (visit, the green, P6 idle activities).
  - On market day, `Market.ensure_tents` adds 2 extra tents with farm goods, and `traders.decide` prefers a town whose market day is tomorrow (+20% to the deal score).
  - In rain or snow (per region, C5), outdoor goals (gathering, gardens) wait an hour and errands are moved indoors when possible.
- **Plugs into:** `sim/jobs/job_board.gd`, `sim/economy/market.gd` (`ensure_tents`), `sim/economy/traders.gd` (`decide`), `sim/entities/residents.gd` (`_decide`), `sim/world/weather.gd`.
- **Edge cases:**
  - Sheriffs work every day.
  - Food must still be available on the rest day (households eat from their pantries).
  - Family payday (`FamilyEconomy.payday`) is daily; keep it, and on the rest day pay no wage.
- **Performance note:** one integer division per decision.
- **Tests:** no jobs taken on day 6; market-day tents appear; rain delays the gathering goals.
- **Done when:** you notice the town is busy on market day and quiet on the rest day.

### P3. Relationships between townspeople
- **Status:** PARTLY BUILT. Partners exist; `relations` exist but only toward the player. **Size:** M. **Depends on:** nothing (P2 makes it richer).
- **Player sees:** neighbours have friends and enemies. In the evening friends visit each other's homes and sit together. Two rivals who meet in the street argue loudly and sometimes it comes to blows, and the sheriff breaks it up. "Ask about family" also mentions friends and feuds.
- **How it works:**
  - Reuse `npc.relations`, keyed by any entity id, not just the player. Seed it at world start: each adult gets 1 to 2 friends (+40 to +70) and a 30% chance of one rival (-40 to -70) in the same town, from stream "bonds".
  - Daily drift: working the same job or eating at the same table adds +1.
  - Evening goal (17:30 to 20:00, using the `EVENING` window in `households.gd`): with a 20% chance, an adult visits their best friend's home for 300 ticks (`set_goal(npc, "visit")`).
  - Rivals within 4 cells: an "argue" exchange (new speech topics), with a 10% chance of `Brawl.engage` between them. Today a brawl targets the player, so it needs an NPC-vs-NPC mode; keep it to shoves only at first.
- **Plugs into:** `sim/entities/residents.gd` (`set_goal`, `_need_action`), `sim/entities/households.gd` (`EVENING`), `sim/entities/speech.gd`, `sim/combat/brawl.gd`, `sim/law/sheriff.gd` (break up fights).
- **Edge cases:**
  - The `relations` cap of 32 drops the oldest, so give bonds priority over minor contacts.
  - Married partners are always friends.
  - A death removes the entry.
- **Performance note:** rival checks only for pairs in the same town, every 120 ticks together with the speech update. Precompute each NPC's rival list once a day.
- **Tests:** visits happen in the evening; rivals argue; NPC brawls end; determinism; save and load.
- **Done when:** you see two neighbours shoving in the square and the sheriff walking over.

### P6. Idle life
- **Status:** PARTLY BUILT. Neighbours chat. **Size:** S–M. **Depends on:** nothing (animations under 7.7).
- **Player sees:** people do small things when they're not working: sweeping the porch, chopping firewood by the house, sitting on a bench, leaning on a fence, kids playing tag, a dog following its owner (dogs need P9).
- **How it works:**
  - When `_decide` finds no goal, pick an idle activity from a table by place and age (stream "idle"): porch sweep, wood chop, bench sit (nearest bench fixture), fence lean, children's tag, staying for 100 to 400 ticks.
  - Store it as `npc.idle = {kind, until, cell}`. Chopping wood puts 1 log per 200 ticks into the home inventory, from the woodpile; it only moves existing goods.
  - The view reads `npc.idle.kind` and plays the matching pose.
- **Plugs into:** `sim/entities/residents.gd` (`_decide`, `set_goal`), `view/actors/animation_director.gd`, `view/world/fixture_art.gd` (benches).
- **Edge cases:** any real need (hunger, a job, fear) interrupts idling, and so does the player talking to them.
- **Performance note:** decided only when a resident becomes idle, not every tick.
- **Tests:** idle residents pick activities; the choices are deterministic; activities end.
- **Done when:** the town looks lived in even when nobody is working.

### P7. Visible moods (view only)
- **Status:** NEW. **Size:** S. **Depends on:** nothing.
- **Player sees:** you can tell how people feel by how they move. A tired person yawns and walks slower, a frightened one keeps glancing over their shoulder, a hungry one rubs their stomach, an angry one stomps, and a drunk one sways (drink needs the saloon idea).
- **How it works:** the view reads existing state (NPC `fatigue`, `fear`, `hunger`, anger from `brawl`) and adds pose overlays and animation speed: tired, 0.9× walk animation; angry, a longer stride. This is the view only; it never changes how fast they move in the sim.
- **Plugs into:** `view/actors/animation_director.gd`, `view/actors/drawn_character.gd`.
- **Edge cases:** one overlay at a time, in the order fear > anger > tired > hungry.
- **Performance note:** add overlays only for actors on screen (the director already skips off-screen ones).
- **Tests:** the pose flags follow the states (in the view test style of `tests/view/animation_live_test.gd`).
- **Done when:** you can spot the frightened villager without clicking them.

### A5. Mood icons above heads
- **Status:** NEW. **Size:** S. **Depends on:** F1 for "happy to see you".
- **Player sees:** a small icon above a person's head for a moment: angry (red), scared (white), happy to see you (gold), sleepy (zz), or suspicious (?, from L7).
- **How it works:** the view reads the states (anger from brawl, fear, opinion when greeting, sleeping, suspicion). It shows an icon for 2 s when the state starts, never constantly, and draws it in the existing label pass.
- **Plugs into:** `view/world/world_view.gd` (the labels pass, already timed as "dw:labels+weather").
- **Edge cases:** at most one icon per person, and none when zoomed far out.
- **Performance note:** draw only for people on screen within a zoom threshold.
- **Tests:** each state shows its icon once.
- **Done when:** you notice a keeper's angry icon when you walk up after robbing them.

---

## MILESTONE 7: STEALTH AND COMBAT DEPTH (sneaking and fighting with more choices)

**Why here:** Night exists (milestone 5), and the silent takedown is already in.

**Playable check:** At night, sneak into a farm with the bow and take down a lookout silently; nobody wakes. Running on the wooden porch does wake them.

**Size:** ~2–3 sessions.

**Features, in build order:** L7 Stealth, B21 View cones, noise rings, a light meter and distractions, L6 More weapons, L9 Surrender, mercy and non-lethal takedowns, A1 Blended animation, A4 Combat animations, A2 Secondary motion, A3 Interaction animations, A8 Camera feel.

### L7. Stealth
> **Update after steps 1–4:** Silent takedowns already exist (`sim/combat/takedown.gd`): crouched, adjacent and unseen. Silent crimes need a sheriff with a line of sight (`Law.crime(..., silent = true)`). Stealth builds on this: light (from V1) and noise decide who notices you.

- **Status:** NEW. Crouching and cover exist (`cover.gd`, `player_low`). **Size:** M. **Depends on:** Night lighting (V1) for light levels; footsteps by surface (S5) for the sound side.
- **Player sees:** at night, crouched in the shadows or in a bush, you're hard to see. Running on wooden floors is loud; creeping on grass is quiet. People who glimpse you get suspicious ("Who's there?") before raising the alarm.
- **How it works:**
  - **Visibility, 0 to 100,** computed for the player every 10 ticks:
    - base 100 by day, 30 at night;
    - +60 within a lit lamp radius (V1);
    - ×0.5 when crouched;
    - ×0.3 in a bush cell (trees are already cover; add bush props);
    - ×1.5 when running.
  - **Noise radius** in cells: walking 3, running 8, crouched 1; wood floor +2, gravel road +1.
  - **Detection:** a resident whose facing is within 70° of the player (a view cone), in range 14 × visibility/100 with `line_clear`, OR who is within the noise radius, notices. They notice in two steps:
    1. "suspicious" for 40 ticks: they turn and walk toward you;
    2. "alarmed" if they still notice after 40 ticks.

    Only alarmed witnesses count for L1.
- **Plugs into:** `sim/combat/cover.gd` (`player_low`, `line_clear`), `sim/entities/fear.gd`, `sim/law/law.gd` (witnesses), `sim/player/` (a new `stealth.gd`), `view/ui/moodles.gd` (an eye icon showing your visibility).
- **Edge cases:**
  - Residents need a facing direction. The view has one; the sim may not, so add `npc.facing` from the last path step.
  - Sleeping residents notice nothing.
- **Performance note:** only check residents within 20 cells of the player, using the spatial lookups, every 10 ticks. That is a small, bounded set.
- **Tests:**
  - Crouched in a bush at night, you aren't noticed at 6 cells.
  - Running on wood is noticed at 9 cells.
  - Suspicion comes before the alarm.
- **Done when:** you sneak past a sheriff in the dark.

### B21. View cones, noise rings, a light meter and distractions
> **Update after steps 1–4:** Needs L7 (stealth). The silent takedown already checks whether a person faces you.

- **Status:** NEW. **Size:** S–M. **Depends on:** L7 (stealth rules).
- **Player sees:** hold a key to see what each nearby person can see (a cone) and how far your noise carries (a ring). A small meter shows how visible you are. Throw a stone to make a guard look the other way.
- **How it works:** the view draws L7's numbers (cones from `npc.facing`, noise from the radius, the meter from visibility). A distraction is a throw command: a noise at a target cell, so residents within 6 cells get the "suspicious" state and walk there.
- **Plugs into:** L7, `view/world/world_view.gd`, `sim/core/simulation.gd` (a throw command).
- **Edge cases:** the overlay only while the key is held.
- **Performance:** cones only for people within 20 cells.
- **Tests:** a thrown stone sends a guard to the spot.
- **Done when:** you plan a sneak with the cones.

### L6. More weapons
> **Update after steps 1–4:** The gun code is already a weapon table (`Shotgun.WEAPONS` in `sim/combat/shotgun.gd`) with the rifle and shotgun, each with its own range, spread, strength, speed and earshot (`heard`). A pistol or bow is mostly a new table entry plus an icon. The knife goes with the silent takedown (`sim/combat/takedown.gd`).

- **Status:** NEW. Only the shotgun exists (`sim/combat/shotgun.gd`). **Size:** M. **Depends on:** nothing. Read the shotgun code first: it handles pellets, surfaces, cover and noise.

**Player sees:** a choice of weapons, each with a clear role:

| Weapon | Range | Fire | Noise |
|---|---|---|---|
| Pistol | 10 cells | 6 shots, quick | Medium |
| Rifle | 25 cells | 1 shot at a time, slow reload, accurate | Loud, far |
| Bow | 15 cells | Arrows, slow | Silent, nobody beyond 3 cells hears it |
| Knife | Melee | Fast cuts that cause bleeding | Silent |

- **How it works:**
  - Turn the shotgun constants into a weapon table: `content/items/weapons.json`, or a const dictionary at first. Each entry has `{pellets, spread, range, damage, reload_ticks, rounds, noise_radius, ammo_item}`.
  - Generalise `shotgun.gd` into `firearm.gd`, keeping `shotgun.gd` as a thin wrapper so existing callers and tests keep working.
  - The noise radius feeds `Fear.on_gunshot` (who hears it) and `gunfire` (who responds).
  - The knife goes through `unarmed.gd` as a strike with `Bleeding.open_wound`.
  - NPC sheriffs keep the shotgun, and can carry a rifle when the player is beyond 12 cells.
- **Plugs into:** `sim/combat/shotgun.gd`, `sim/combat/gunfire.gd`, `sim/combat/wounds.gd`, `sim/entities/fear.gd` (`on_gunshot`), `sim/combat/unarmed.gd`, `sim/player/hotbar.gd`, the market `BASE` prices.
- **Edge cases:**
  - Save compatibility: `s.shotgun` stays as the state of the equipped gun, or migrate it carefully.
  - Ammo types must not mix.
- **Performance note:** a rifle's long line checks cost more per shot, but shots are rare.
- **Tests:**
  - Each weapon's range limit works.
  - The bow alerts nobody beyond 3 cells.
  - The knife causes bleeding.
  - Existing shotgun tests still pass.
- **Done when:** you can take out a sentry silently with a bow.

### L9. Surrender, mercy and non-lethal takedowns
> **Update after steps 1–4:** Knock-outs and silent takedowns exist, and so does body carrying (`sim/player/carrying.gd`), which handing someone in can reuse. What's left: NPCs surrendering, tying up with rope, and handing in.

- **Status:** PARTLY BUILT. Knock-outs exist (`brawl.gd`), and the player can surrender (`law.surrender`). **Size:** S. **Depends on:** C2 (carrying); L2 (bounties) for handing in.
- **Player sees:**
  - Badly hurt enemies sometimes throw down their weapon and beg.
  - You choose to let them go (people remember your mercy), tie them up, or finish them, which is murder.
  - Sneaking up from behind lets you knock someone out with one blow.
  - Tied-up people stay put until someone frees them, and you can hand them to the sheriff.
- **How it works:**
  - **NPC surrender:** in `gunfire.gd`, an NPC combatant (C8 outlaws, guards) with health under 25 has a 40% chance per hit (stream "surrender") to set `npc.surrendered = true`. They drop their weapon item to the ground, stop fighting, and get a hands-up pose.
  - **Context options on a surrendered or knocked person:**
    - "Let go": they leave, you get a `helped` memory, and +5 reputation in their town;
    - "Tie up": `npc.tied = true` needs 1 rope (a new item, 1 weight, sold in the store). Their goals are skipped in `residents.update`, the same as `serving`;
    - "Hand over": for a tied person within 2 cells of a sheriff, they're jailed and a bounty paid if any.
  - **Sneak takedown:** crouched, from behind (outside the target's view cone, L7), "Knock out" is a guaranteed KO with `Brawl.knockdown` kind "ko".
- **Plugs into:** `sim/combat/gunfire.gd`, `sim/combat/brawl.gd` (`knockdown`, `KO_TICKS`), `sim/entities/residents.gd` (`update` skips), `sim/player/context_actions.gd`, L2.
- **Edge cases:**
  - A tied person is freed by any friend who passes by (opinion 30 or more toward them).
  - Tying someone up without a reason is a crime (assault) if witnessed.
- **Performance note:** none.
- **Tests:**
  - A wounded outlaw surrenders on a known seed.
  - Tying up holds them.
  - Handing them in pays the bounty.
  - The sneak takedown knocks them out.
- **Done when:** you spare a surrendering outlaw and later hear people talk about it.

### A1. ★ Blended animation
- **Status:** NEW. **Size:** M.
- **Player sees:** characters move smoothly. Walk, run and idle blend into each other instead of snapping. A character turning around takes a step to turn, and starting and stopping have a short lean.
- **How it works:**
  - Each actor in the director keeps `blend = {from, to, t}`. A change of action starts a 0.15 s crossfade, where the pose is lerped between the two pose samples.
  - A heading change above 90° plays a 0.12 s turn pose before walking on.
  - Start and stop: the first and last 0.1 s of a move get a lean of ±4°.
- **Plugs into:** `view/actors/animation_director.gd`, `view/actors/drawn_character.gd`.
- **Edge cases:**
  - A knock-down or death ignores blending (snap).
  - Very short moves (1 cell) shouldn't play turn, start and stop all at once.
- **Performance note:** lerping two poses per visible actor is cheap. Only actors on screen are updated, which the director already does at reduced rates when zoomed out.
- **Tests:**
  - No pose flips within one frame.
  - The blend weight stays between 0 and 1.
  - A turn pose shows on reversal.
- **Done when:** a villager stopping and turning looks natural.

### A4. Combat animations
> **Update after steps 1–4:** Also add the carry pose for bodies: today a carried body is drawn lying at shoulder height, which is basic.

- **Status:** PARTLY BUILT. Sneaking while advancing and the treat pose exist. **Size:** M.
- **Player sees:** in a fight, people duck behind cover, pop up to peek, fire, and duck again. They feed shells into the shotgun one by one, the wounded crawl, and bandaging is visible.
- **How it works:**
  - `cover_cycle.phase` maps to a pose: hide → crouch, peek → lean out, fire → aim plus recoil, advance → sneak (already done), bandage → treat (already done).
  - Reloading: the shotgun reload state (`shotgun.start_reload`, the `reloading` flag) gives a "reload" pose, with one shell-push per shell.
  - Crawling: `Limbs.crawling` gives a "crawl" pose.
- **Plugs into:** `view/actors/animation_director.gd`, `sim/combat/gunfire.gd` (phase), `sim/combat/shotgun.gd` (reload), `sim/combat/limbs.gd` (`crawling`).
- **Edge cases:** the player and NPCs share the poses.
- **Performance note:** none.
- **Tests:** the phase-to-pose table is complete.
- **Done when:** a gunfight looks like people taking cover, not standing still.

### A2. Secondary motion
- **Status:** NEW. **Size:** S.
- **Player sees:** coat tails, hat brims, loose hair and carried sacks sway and settle as people move and stop.
- **How it works:**
  - A spring per actor: offset += (target − offset) × k − velocity × damping. The target comes from speed and turn rate.
  - It is applied to the drawn coat, hat and carried-item parts.
- **Plugs into:** `view/actors/drawn_character.gd`.
- **Edge cases:** clamp the offset to a few pixels.
- **Performance note:** a few floats per visible actor.
- **Tests:**
  - The offset is bounded.
  - It settles to 0 at rest within 1 s.
- **Done when:** a running man's coat swings.

### A3. Interaction animations
- **Status:** PARTLY BUILT. Sleeping and treating poses exist. **Size:** M.
- **Player sees:** people use the world with their hands: they open a chest lid, sit down on a chair, eat at a table, hand coins over a counter when trading, shake hands with a friend, and sweep with a broom (P6).
- **How it works:** map each sim state to an action:

  | Sim state | Action |
  |---|---|
  | `player_control.work` or a looting state | "open_chest" |
  | sitting (the sheriff `sit` already exists) | "sit" |
  | eating in `_need_action` | "eat" |
  | a trade just completed | "hand_coins", for 0.6 s |
  | a greeting with opinion 50 or more | "shake_hands" |

  Each action gets a pose sequence in `drawn_character.gd`.
- **Plugs into:** `view/actors/animation_director.gd`, `view/actors/drawn_character.gd`, the sim fields named above.
- **Edge cases:** an interrupted action returns to idle through A1.
- **Performance note:** none.
- **Tests:** each state maps to its action.
- **Done when:** trading shows coins changing hands.

### A8. Camera feel
- **Status:** NEW. **Size:** S.
- **Player sees:** the camera gives a small kick when a gun fires nearby (smaller further away), leads slightly in the direction you walk so you see more ahead, and eases smoothly when zooming.
- **How it works:**
  - **Shake:** amplitude = 6 px × (1 − distance/20), decaying over 0.3 s.
  - **Lead:** 1.5 cells × the walk direction, smoothed over 0.5 s.
  - **Zoom:** eased.
  - Add a setting to turn shake off (I2).
- **Plugs into:** `view/world/observer_camera.gd`, `app/world_controller.gd`.
- **Edge cases:** no lead or shake while the map is open or in dialogue.
- **Performance note:** none.
- **Tests:**
  - The shake decays to 0.
  - The lead is bounded.
- **Done when:** a shotgun blast next to you feels punchy.

---

## MILESTONE 8: CRIME AND PUNISHMENT (the law follows through)

**Why here:** Witnesses, wanted records, bribes and carrying already exist.

**Playable check:** Get arrested for a theft only one person saw, pay the fine at the trial, then take a bounty and bring the outlaw in tied up.

**Size:** ~2 sessions.

**Features, in build order:** L4 Trials, fines and bail, L5 Jail escape, L2 Bounties, A6 Footprints in mud and snow (sim and view).

### L4. Trials, fines and bail
> **Update after steps 1–4:** Wanted records now say how you are known: by face, or by the clothes a witness described (`Law.file`, `Law.recognised`). Trials can count the witnesses from the chronicle entry.

- **Status:** NEW. The arrest, booking and jail flow exists; the jail time today comes straight from `SENTENCE`. **Size:** M. **Depends on:** L1 (the evidence is the witnesses).
- **Player sees:**
  - After an arrest you wait in the cell for the court session the next morning at 09:00.
  - The judge (the mayor, C7, or the sheriff in small towns) hears the case.
    - No witnesses: you walk free.
    - One witness: a fine.
    - Several witnesses or a murder: jail time.
  - You can pay bail to get out until the trial, but not turning up is a new crime.
- **How it works:**
  - At booking, store the case on the player: `player_control.case = {town, crimes, witnesses: count, bail, trial_tick}`.
  - Bail = 10 × the wanted hours.
  - At `trial_tick`, the player is escorted to the office desk. The verdict:
    - 0 witnesses and no hidden-crime proof: release;
    - 1 witness: a fine of 5 × hours, from your account to the treasury, or jail if you can't pay;
    - more: jail for the `SENTENCE` hours.
  - The jail state is the existing `player_control.jail.until`.
  - Bail paid: you're released with `case.bail_out = true`. Not being in the office at `trial_tick` turns it into a new `flight` crime and the bail is kept by the town.
- **Plugs into:** `sim/law/law.gd` (`_book`, `_arrive`, the release flow, `jailed`, `SENTENCE`), `sim/core/simulation.gd` (block commands during the trial), the jail banner in `view/ui/game_hud.gd`.
- **Edge cases:**
  - A trial in a town that is under gang rule (C8) doesn't happen.
  - The judge dies: the sheriff judges.
  - Save and load during the trial.
- **Performance note:** none.
- **Tests:**
  - 0 witnesses means release.
  - 1 means a fine with exact coins.
  - 3 means jail.
  - Bail plus no-show means a new crime.
- **Done when:** a crime nobody saw clearly ends with "Case dismissed".

### L5. Jail escape
> **Update after steps 1–4:** Bribing a sheriff already works during an arrest (`sim/player/talk.gd`). The night-guard bribe reuses `Talk.bribe`.

- **Status:** NEW. **Size:** S–M. **Depends on:** T2 (bribe), F1 (friends); L4 helps.
- **Player sees:** three ways out of a cell.
  - **Pick the lock** with a lockpick: it takes time, makes noise, and might break the pick.
  - **Bribe the guard** at night.
  - **A good friend** springs you after dark.

  An escape is a new crime and the sheriffs start a search.
- **How it works:**
  - The cell door is the office's `cell_open` state, which already exists in the sim and is drawn as iron bars.
  - **Lockpick:** a new item, weight 0, sold by shady characters or found. Picking takes 120 ticks. Chance per attempt = 30% + stealth skill / 2 (G3), on stream "lockpick". A failure has a 30% chance to break the pick. A sheriff within 8 cells hears it (noise).
  - **Bribe:** use T2 with the guard on duty, only between 22:00 and 05:00.
  - **Friend:** if any resident has opinion 70 or more (F1), each night a 20% chance they come and open the door.
  - An escape sets `jail = {}`, adds an "escape" crime (`SENTENCE` 6), and puts the sheriffs in pursuit (the existing arrest flow).
- **Plugs into:** `sim/law/law.gd` (`jail`, release flow), `sim/law/sheriff.gd`, the office cell state, `sim/player/context_actions.gd` (the "Pick lock" action on the cell door).
- **Edge cases:**
  - Belongings stay in the office locker (they were taken at booking, `PROPERTY_AT`). Getting them back is up to you.
  - The heir mechanic (C9) is not affected.
- **Performance note:** none.
- **Tests:**
  - The lockpick opens the door on a known seed.
  - An escape adds a crime.
  - A friend at opinion 70 or more frees you at night.
- **Done when:** you pick the lock at night and slip out.

### L2. Bounties
> **Update after steps 1–4:** Witness reports, body carrying and the chronicle exist, so turning in someone carried or tied up, and tracking by rumour (gossip), are ready to use.

- **Status:** NEW. **Size:** M. **Depends on:** L1, C2 (carrying), L9 (tying up). C8 adds outlaw bounties.
- **Player sees:**
  - The sheriff posts bounties on outlaws and wanted NPCs, for example "Wanted: Jeb Cole, 80 coins, alive. 40 dead."
  - Take the job, follow the rumours and tracks, and bring the outlaw back tied up and carried, for the full reward, or dead for half.
  - You can also have a bounty on your own head: then other people may come for you.
- **How it works:**
  - `s.bounties[id] = {target, town, reward_alive, reward_dead, posted, taken_by}`.
  - **Created:** when an NPC commits a crime (gang members, C8; or a resident who turns outlaw), or for the player when wanted hours go above 12. Rewards come from the town treasury and are reserved when posted, so the money is conserved.
  - **Claiming:**
    - Alive: deliver the target tied up (L9) or carried (C2) to the town's office, then they are jailed.
    - Dead: deliver the body.
  - **A bounty on the player:** each day a 10% chance that an armed resident (a "Bounty hunter" role) leaves to hunt you. They use the arrest flow without the sheriff badge.
- **Plugs into:**
  - `sim/law/sheriff.gd`;
  - `sim/law/law.gd`;
  - `sim/player/context_actions.gd` (Hand over);
  - `sim/economy/market.gd` accounts;
  - P2 rumours for tracking;
  - W-footprints (A6).
- **Edge cases:**
  - A target dies of something else: the bounty is cancelled and the money returned.
  - A treasury that can't pay doesn't post.
- **Performance note:** daily creation only.
- **Tests:**
  - Alive pays the full reward.
  - Dead pays half.
  - The money is conserved.
  - A cancelled bounty refunds.
- **Done when:** you carry a tied-up outlaw into the office and collect 80 coins.

### A6. Footprints in mud and snow (sim and view)
- **Status:** NEW. **Size:** S. **Depends on:** W1 (mud) and the snow cover.
- **Player sees:** in snow or mud, people leave footprints that fade over a few hours. You can follow an outlaw's tracks to their hideout.
- **How it works:**
  - The sim keeps the tracks because L2 tracking uses them: `s.tracks = [{cell, id, tick}]`, capped at 400 with the oldest dropped. A track is added when an actor steps onto a mud or snow cell, at most 1 per 2 steps, and expires after 3 hours (1,800 ticks).
  - The view draws small prints rotated by the step direction.
- **Plugs into:** `sim/core/simulation.gd` (movement step), `sim/world/weather.gd`, `view/world/world_view.gd`.
- **Edge cases:** rain washes the tracks away (clear them when rain starts in that region).
- **Performance note:** keep the cap at 400 tracks and draw them as one multimesh or batched draw.
- **Tests:**
  - Tracks appear in snow and not on dry ground.
  - They expire.
  - The cap holds.
- **Done when:** you follow fresh prints in the snow.

---

## MILESTONE 9: MAKING A LIFE (a home, work and money of your own)

**Why here:** Gives the player things to do between adventures.

**Playable check:** Rent a cottage in Reedbank, bake bread there, sell it from your own stall on market day, and pay back your loan.

**Size:** ~3 sessions.

**Features, in build order:** T5 Rent, then buy, a home, I2 Settings, I3 Save slots, autosave and Continue, I4 Parchment-style inventory, I5 Tooltips and a log of notices and speech, E5 Player crafting, E2 Your own stall, T4 Hire people, E4 Loans and debts, E6 Item quality and wear, B18 Gifts with likes and dislikes.

### T5. Rent, then buy, a home
> **Update after steps 1–4:** Trespass rules exist (`sim/law/trespass.gd`) and already welcome the player into a household called "player". Renting makes that household.

- **Status:** NEW. **Size:** M. **Depends on:** C3 (so it's yours), F5.
- **Player sees:** you can rent a room at an inn or a free house by the day, and later buy a house. It's yours: your bed to sleep in, a private chest, a pantry, a garden plot. People need permission to come in, just as you do in theirs.
- **How it works:**
  - A free home is one with no household (`members_of = 0`). Rent is 4 coins a day, paid to the town treasury (`str(town.warehouse)`); buying costs 300 (tunable) to the treasury.
  - Create a player household `s.households["player"] = {settlement, members: [player], home}` and set `player.household`. The existing systems then treat the player as a member: C3's welcome rule, `Sleep.bed` and the home chest.
  - The home inventory is private: others taking from it is theft.
  - Missed rent: after 2 days, the lease ends and your items stay in the chest for 7 days.
- **Plugs into:** `sim/entities/households.gd`, `sim/player/sleep.gd` (`bed`, `lie_down`), `sim/entities/chests.gd`, `sim/player/context_actions.gd` (Rent and Buy at the door), `sim/entities/family_economy.gd` (rent from the player's account).
- **Edge cases:**
  - `_move_in_together` must skip the player's home.
  - A town with no free homes offers an inn bed (a lodge, using `LODGE_CAPACITY`).
  - Old saves: no player household.
- **Performance note:** none.
- **Tests:** renting moves coins; your chest is private; sleeping at home works; trespassers get warned (C3 reversed); the lease ends when unpaid.
- **Done when:** you buy a cottage in Reedbank and keep your loot there.

### I2. Settings
> **Update after steps 1–4:** There is no pause menu yet. Settings and named save slots share it (saving already runs in the background, `app/save_slots.gd`).

- **Status:** NEW. `app/input_settings.gd` and `main_menu.gd` exist. **Size:** S–M.
- **Player sees:** a Settings page in the main menu and the pause menu with:
  - volume sliders (music, effects, ambience, voices);
  - key rebinding;
  - text size;
  - fullscreen or window;
  - camera shake on or off;
  - tips on or off;
  - colour-blind palette.
- **How it works:**
  - Stored in `user://settings.cfg` (`ConfigFile`), never in the sim save.
  - Audio buses are created at startup.
  - Rebinding uses the `InputMap` actions already defined in `input_settings.gd`.
- **Plugs into:** `view/ui/main_menu.gd`, `app/input_settings.gd`, `view/audio/world_audio.gd`.
- **Edge cases:** a bad config file falls back to defaults.
- **Performance note:** none.
- **Tests:**
  - Settings round-trip through the file.
  - Rebinding changes the action.
- **Done when:** you can turn the music down and rebind keys.

### I3. Save slots, autosave and Continue
> **Update after steps 1–4:** DONE: autosave each morning, Continue, and F9 loads the newest. STILL TO DO: three named manual slots, from the pause menu (I2).

- **Status:** NEW. Saving exists (`sim/persistence/save_manager.gd`: `save_state`, `read_state`, `load_into`). **Size:** S.
- **Player sees:** three save slots, an autosave every morning at 06:00 (two rotating), and a Continue button that loads your latest save.
- **How it works:**
  - Paths are `user://saves/slot1.json` and so on, and `autosave_a` and `autosave_b`.
  - Autosave at 06:00 while not in combat (`s.law.alert` empty).
  - Continue = the newest by modified time.
  - The menu shows the day, town and time for each slot.
- **Plugs into:** `sim/persistence/save_manager.gd`, `view/ui/main_menu.gd`, `app/world_controller.gd`, `app/save_migration.gd` (it already copies old saves).
- **Edge cases:** saving during an escort or trial is allowed; restoring must be exact (already tested for the hash).
- **Performance note:** saving writes JSON. Check how long it takes on a big world; if it's over 50 ms, autosave on a background thread with a copy of the snapshot.
- **Tests:**
  - The autosave happens at 06:00.
  - Continue picks the newest.
  - Slots load.
- **Done when:** you never lose more than a day of play.

### I4. Parchment-style inventory
> **Update after steps 1–4:** The inventory shows the carried weight (`Encumbrance.describe`). Restyle it to match the parchment trade window and journal.

- **Status:** NEW. `inventory_window.gd`, `inventory_grid.gd` and `hotbar.gd` exist. **Size:** M. **Depends on:** C1 (the load bar).
- **Player sees:** the inventory matches the parchment trade window: item icons on a ledger grid, drag and drop between slots and the hotbar, a load bar (C1), and a short description and value for the item you hover.
- **How it works:**
  - Restyle using the `trade_window.gd` drawing helpers.
  - Drag and drop submits the existing commands (`hotbar_use`, and a new `hotbar_assign`).
  - Values come from `market.quote` for the current town.
- **Plugs into:** `view/ui/inventory_window.gd`, `view/ui/inventory_grid.gd`, `sim/player/hotbar.gd`, `view/ui/item_icons.gd`.
- **Edge cases:** dropping outside the window drops the item on the ground (a `drop` command).
- **Performance note:** redraw only when the inventory changes.
- **Tests:** drag and drop sends the right command.
- **Done when:** the inventory feels like part of the same game as the trade window.

### I5. Tooltips and a log of notices and speech
- **Status:** NEW. **Size:** S.
- **Player sees:** hover over a person, item or building to see a small tooltip (name, job, value, owner). Press L to scroll back through the last 100 notices and lines people said.
- **How it works:**
  - Tooltips use `WorldView.pick()`, which already finds what's under the cursor, and `ContextActions.subtitle` and `describe`.
  - The log: the view appends every new `pc.notice` and `s.speech` line to a 100-entry list. This is view-only, not saved.
- **Plugs into:** `view/ui/game_hud.gd`, `view/world/world_view.gd` (`pick`), `sim/player/context_actions.gd` (`describe`).
- **Edge cases:** a tooltip only after a 0.4 s hover.
- **Performance note:** pick once per mouse move, not every frame.
- **Tests:** the log keeps 100 entries in order.
- **Done when:** you can check what someone said a minute ago.

### E5. Player crafting
- **Status:** NEW (NPC production exists in `sim/production/recipe_system.gd` with recipes in `content/recipes/core.json`). **Size:** M. **Depends on:** nothing.
- **Player sees:** you can use workshops yourself. Bake bread at the oven from rye, cut planks at the saw from logs, and make bandages from cloth or herbs (with foraging, W6). Repairing your shotgun at the forge needs E6. Each job takes a little time and you see your character working.
- **How it works:**
  - A "Craft" context option at stations (the per-part options already exist in `context_actions._part_options` for saw, oven and forge). It opens a small recipe list from the same recipe data.
  - A craft job is `player_control.work = {recipe, station, until}` (the `work` field already exists in `player_control`). The inputs are consumed at the start and the output produced at the end; walking away cancels it and gives the inputs back.
  - A workshop owned by a town charges a 2-coin fee to the treasury.
- **Plugs into:** `sim/production/recipe_system.gd` (recipes), `sim/player/context_actions.gd` (`_part_options`, `perform`), `content/recipes/core.json`, `view/actors/animation_director.gd`.
- **Edge cases:**
  - An NPC is using the station: wait or share (the first in line gets it).
  - Not enough inputs: the option is greyed with the reason.
- **Performance note:** none.
- **Tests:** baking turns rye into bread with the right time; inputs are consumed; cancelling refunds them.
- **Done when:** you bake your own bread instead of buying it.

### E2. Your own stall
> **Update after steps 1–4:** The trade window (`view/ui/trade_window.gd`) has Trade and Talk tabs. Your own stall needs a third view of it, or a small panel.

- **Status:** NEW. **Size:** M. **Depends on:** T4 (hired keeper, optional).
- **Player sees:** rent a market stall for the day, put your goods out and set your prices. Townspeople on their shopping rounds buy from you if your price is fair. Hire a keeper to run it while you're away; they take a cut.
- **How it works:**
  - The stall rent is 5 coins a day to the treasury. The stall is a stall entity with `owner = player`; you move goods from your inventory to its inventory (`Inventory.transfer`).
  - Prices: `stall.prices[item]`, set in the window.
  - Buyers: `FamilyEconomy.buy_food` today buys from the store. Change it to look at all open stalls in town selling food, and choose the cheapest at or below `quote()`; for the player's stall the stock must be there.
  - Money from sales goes to the player's account (`transact` already moves coins).
  - A hired keeper (T4) stays at the counter and takes 10%.
- **Plugs into:** `sim/economy/market.gd` (stalls, `transact`, `quote`), `sim/economy/stall_service.gd`, `sim/entities/family_economy.gd` (`buy_food`), `view/ui/trade_window.gd`.
- **Edge cases:**
  - An unstaffed stall with the owner away: no sales, unless a keeper is hired.
  - At the end of the rent, the goods return to the player or stay locked for 1 day.
  - Theft from the stall is a crime.
- **Performance note:** a buyer looks at no more than 4 stalls per town.
- **Tests:** a resident buys from your stall at your price; the coins reach you; money and goods are conserved.
- **Done when:** you sell your harvested rye from your own stall on market day.

### T4. Hire people
> **Update after steps 1–4:** The Talk tab (`sim/player/dialogue.gd`) is where a Hire line goes. Wages can use the payday hook in `family_economy.gd`.

- **Status:** NEW. **Size:** M. **Depends on:** F4, F5.
- **Player sees:** you can hire help for a daily wage: a **guard** who walks with you and fights at your side, a **farmhand** to work your field, or a **guide** to take you somewhere. They want paying every morning and they quit if you don't pay or treat them badly.
- **How it works:**
  - A "Hire" option in F4 for any adult who isn't a sheriff, trader or story character, with a willingness check of opinion ≥ 0 and no current job. Wages: guard 15 a day, farmhand 8, guide 5.
  - `s.player_status.hired = [{id, role, wage, since, last_paid}]`. The hired person's `occupation` stays, but their goals are overridden (a `hired` flag skipped in `residents.update`, just like `serving`).
  - **Guard:** follows within 3 cells; in a fight they use the sheriff's cover cycle (`gunfire.gd`) against whoever attacks you. That needs the target generalisation from C8, so start the guard with fists only (`brawl.gd`).
  - **Farmhand:** works the player's field plot (needs a home and field, T5).
  - **Guide:** walks to a chosen place (reuse `travel` pathing) and waits.
  - Payday at 06:00: the wage moves from the player's account to theirs. If the player can't pay, they quit with a bad memory.
- **Plugs into:** `sim/entities/residents.gd` (`update` skip rules), `sim/combat/brawl.gd`, `sim/combat/gunfire.gd`, `sim/entities/family_economy.gd` (payday timing), `sim/player/dialogue.gd`.
- **Edge cases:**
  - Their family still needs them: they go home at night unless they're a guard.
  - A hireling killed on duty means a big negative memory for their family.
  - At most 2 hirelings.
- **Performance note:** hirelings run at detailed fidelity, so cap them at 2.
- **Tests:** a guard follows and punches an attacker; the wage moves daily; an unpaid hireling quits; save and load.
- **Done when:** you hire a burly guard before walking the outlaw road.

### E4. Loans and debts
- **Status:** NEW. **Size:** M. **Depends on:** F4, F5; C9 (inherited debt, optional).
- **Player sees:** the store owner (or a banker) will lend you money, at a price. You have a week to pay it back with interest. Miss the date and a debt collector comes looking for you: first a polite reminder, then threats, then he takes goods or reports you to the sheriff.
- **How it works:**
  - The lender is the town treasury (`str(town.warehouse)` account), through the store keeper. The loan size is up to 100 + reputation × 2 (minimum 0).
  - `s.player_status.debts = [{lender_town, principal, rate, due, paid}]`. Interest is 10% a week, integer, rounded down, added on the due day.
  - Collector: on the due day + 1, a resident (a sheriff off duty, or an adult with the "Collector" role) gets a goal to find the player. They talk (reminder), then 2 days later threaten (C1-weight goods taken equal to the debt, at market value, through `Inventory.transfer` to the treasury), then report it (`Law.crime` "debt", `SENTENCE` 4).
- **Plugs into:** `sim/economy/market.gd` (accounts), `sim/player/dialogue.gd`, `sim/entities/residents.gd` (the collector goal), `sim/law/law.gd`.
- **Edge cases:**
  - Paying part of a debt lowers the principal.
  - The player dies: the heir has the debt (C9), or the debt is written off.
  - Money is conserved: a loan is a transfer from the treasury, and the repayment goes back.
- **Performance note:** daily check.
- **Tests:** interest is exact; repaying clears the debt; the collector appears after the due date; seizing goods keeps the totals.
- **Done when:** you take a loan to buy a house and sweat to pay it back.

### E6. Item quality and wear
- **Status:** NEW. **Size:** S–M. **Depends on:** E5 (repairs).
- **Player sees:** tools and guns wear out. A worn shotgun spreads wider and can jam; a dull axe works slower. The item shows its condition (Good, Worn, Poor). A smith or the forge can repair it, and worn items sell for less.
- **How it works:**
  - Inventory today stores counts per item, which can't hold a per-copy condition. Keep it simple: track condition only for unique gear in `player_status.gear = {shotgun: 100, axe: 100}` (the player's own copy), plus a `tools_condition` average per NPC workshop.
  - The shotgun loses 1 per shot, with a jam chance of (100 − condition)/10 % per shot below 50, and spread × (1 + (100 − condition)/200).
  - Repair: 3 iron at the forge, or 10 coins to the Blacksmith, back to 100.
  - Selling price × condition/100.
- **Plugs into:** `sim/combat/shotgun.gd` (`fire`, `can_fire`), `sim/economy/stall_service.gd` (`price`), E5.
- **Edge cases:**
  - Buying a new shotgun resets condition to 100.
  - Looting someone's shotgun gives a random condition of 40 to 90 (stream "gear").
- **Performance note:** none.
- **Tests:** firing wears the gun; a jam happens below 50 on a known seed; a repair resets it; the price follows condition.
- **Done when:** your gun jams at the worst moment, and you learn to keep it repaired.

### B18. Gifts with likes and dislikes
> **Update after steps 1–4:** This also covers buying clothes, the loose end from "your look": sell outfit pieces at the store.

- **Status:** NEW. **Size:** S. **Depends on:** F1.
- **Player sees:** everyone has favourite and hated things. Give the right gift and they warm to you a lot; the wrong one and they're insulted. You discover their tastes by trying, or by asking their family.
- **How it works:** each resident gets 2 likes and 1 dislike from the item list (stream "tastes", seeded from id). A gift is a "Give" action that moves the item and writes `gift` with weight +15 (liked), +5 (neutral) or −8 (disliked). "Ask about family" can reveal a taste.
- **Plugs into:** F1, `sim/player/context_actions.gd`, `sim/economy/stall_service.gd` (family question).
- **Edge cases:** at most one gift a day counts per person.
- **Performance:** none.
- **Tests:** tastes are stable from the id; weights apply.
- **Done when:** you find out the sheriff loves bread.

---

## MILESTONE 10: FAMILY AND LEGACY (lives that go on)

**Why here:** Needs a home (milestone 9). Pairing up and births already exist.

**Playable check:** Marry, have a child who grows up, die in a gunfight, and keep playing as your daughter.

**Size:** ~2–3 sessions.

**Features, in build order:** P4 Life cycle (ageing, weddings, deaths, funerals, inheritance), T6 Marry into a family, C9 Play as your heir, B27 Ending summary pages.

### P4. Life cycle (ageing, weddings, deaths, funerals, inheritance)
- **Status:** PARTLY BUILT. `age_days`, pairing (`_pair_up`), births (`_births`) and children growing up after 8 days exist. **Size:** L. **Depends on:** P3 (for who marries whom; optional).
- **Player sees:** families change over time. Couples hold a small wedding on the green. Old people slow down and one day pass away, and the town gathers at the graveyard. Their house and purse go to their family. Children grow up and take a trade. Over a long game the towns' faces change.
- **How it works:**
  - **Years:** a configurable `DAYS_PER_YEAR := 14`, a tunable game constant. Age in years = `age_days / DAYS_PER_YEAR`. Start adults at 18 to 60 years (spread from stream "age" at world start; old saves derive it from `age_days`).
  - **Weddings:** `_pair_up` already forms couples by id order at random. Change it to prefer friends (P3), and add a wedding event: on the next rest day (see P5), both families and friends gather at the town green for 600 ticks.
  - **Ageing:** from 60 years, walking is 10% slower; from 70, work is halved.
  - **Natural death:** from 65 years, a daily chance of `(age - 64) × 0.5%`, through `Brawl.kill(sim, npc, "died of old age")`.
  - **Funeral:** the next day at 10:00, the household and friends go to a graveyard spot by the town (a new fixture) for 300 ticks. A grave marker with the name is added and is clickable.
  - **Inheritance:**
    - The purse stays with the household. If the household is now empty, it goes to the nearest relative's household (same surname), else the town treasury. That handover already exists in `FamilyEconomy.ensure` for broken-up households, so reuse it.
    - The house goes to the remaining members. If none are left, it becomes free for `_move_in_together`.
  - **Children:** at 8 days, children already become "Gatherer"; then `Professions.assign` gives them a trade by demand.
- **Plugs into:** `sim/entities/households.gd` (`daily`, `_pair_up`, `_births`, `CHILD_GROWN_DAYS`), `sim/entities/family_economy.gd` (`ensure`), `sim/combat/brawl.gd` (`kill`), `sim/entities/names.gd`, `sim/settlement/professions.gd`, `view/world/fixture_art.gd` (graves).
- **Edge cases:**
  - Population limits: births already check housing, and deaths keep the numbers balanced.
  - The last sheriff dies: `Sheriff.ensure` already refills the roster.
  - Named story characters (P8) must not die mid-story; make them immune until their story ends.
  - Money and names stay conserved and unique.
- **Performance note:** daily only, as `daily()` already loops over residents.
- **Tests:** a 60-day soak keeps the population within ±50% of the start; old residents die; inheritance moves exact coins; graves exist; determinism; save and load.
- **Done when:** over a long game you attend a funeral and see the dead man's son take over the farm.

### T6. Marry into a family
> **Update after steps 1–4:** Talk with tone, opinion and a "pleasant" memory exist. Courtship can count pleasant talks and gifts.

- **Status:** NEW. **Size:** L. **Depends on:** T1, F1, T5 or a home, P4 (weddings). It is required by C9.
- **Player sees:** with time, gifts and good conversation, someone grows fond of you. When their opinion is high enough you can propose. If they accept, there's a wedding on the next rest day, you move into their family home (or they move into yours), and you share the family purse. Children may follow, and they grow up.
- **How it works:**
  - Courtship: an unmarried adult (`partner == 0`) with an opinion of 60 or more shows a "Court" topic, and gifts add more.
  - Proposal: the chance is 50 + (opinion − 60) × 2 (stream "proposal"); a refusal gives a small negative memory and a 7-day cooldown.
  - Wedding: set `partner` on both sides (the player's partner is stored in `player_status.partner`, because the player isn't in `s.residents`) and merge into one household (`s.households` key). The household purse (`household:<key>`) is now shared: the player's own account stays separate, and a "Take from family purse" option is limited to 20 a day so the family doesn't starve.
  - Children: `_births` counts parents from `s.residents`, so it must count the player as a parent.
- **Plugs into:** `sim/entities/households.gd` (`_pair_up`, `_births`, `household_of`), `sim/entities/family_economy.gd` (purse), `sim/player/dialogue.gd`, `sim/factions/society.gd`.
- **Edge cases:**
  - Not with a story character mid-story, or with a sheriff on duty (or allow it, as a choice).
  - The spouse dies: the purse stays and the children stay.
  - Names: the player may take the family surname (`_share_surname` already renames safely).
- **Performance note:** none.
- **Tests:** courtship raises opinion; a proposal at high opinion succeeds; the household merges; a child can be born; the heir exists for C9; money and names are conserved.
- **Done when:** you marry the baker's daughter and move into the bakery.

### C9. Play as your heir
> **Update after steps 1–4:** People already remember you (`Society.opinion`), so an heir can take half through a `heir_of` link. Saves and Continue exist (`app/save_slots.gd`).

**Status:** NEW. **Size:** L. **Depends on:** "Marry into a family" (the player needs a spouse or children); F1 and F3 for inherited reputation; Loans (optional) for debts.

**Player sees:**
- When you die, the screen fades to a short parchment page: "Here lies <name>, 3 years in the frontier... Your son <name> takes up the family name." You then play as your spouse or eldest grown child, in your home.
- **What carries over:** the purse, house and chest. Your reputation carries over at half strength. Enemies who hated you distrust your heir, and debts are still owed.
- If you have no heir, a "Last of the line" ending page summarises your life and the state of each town, then offers a new game.

**How it works:**
- **On death:** when `Brawl.kill_player` runs (it sets `player_control.dead`), wait for the existing knock-out or death screen, then call `Heir.succeed(sim)`.
- **Choosing the heir:** the heir is the living spouse (`partner`), else the oldest adult child of the player's household, else nobody.
- **Switching control:** the player's id is `s.player`. Make the heir the new `s.player`:
  - move the heir's entity to the player role;
  - copy `player_control`, `player_needs` and `player_health` fresh;
  - turn the old player entity into a dead body;
  - remove the heir from `s.residents`, keeping their name, so the name is still unique.

  This is the risky part: many systems read `s.player`. Write it as a single function and test it heavily.
- **What passes on:**
  - the purse: the player's account moves to the heir's new player account;
  - the household stays the same;
  - reputation: `s.reputation[town] /= 2`;
  - memories: residents keep their memories about the old player id. Add a `heir_of` link so `opinion(npc, new_player)` adds half the opinion of the old one;
  - debts and bounties stay.
- **Ending:** with no heir, show the summary (from F2 events and town moods), then the main menu.

**Plugs into:**
- `sim/combat/brawl.gd` (`kill_player`);
- `view/ui/knockout_screen.gd`;
- `sim/entities/households.gd`;
- `sim/entities/family_economy.gd`;
- `sim/factions/society.gd` (opinion);
- `sim/core/simulation.gd` (`s.player`);
- `app/world_controller.gd` (camera target);
- the save files.

**Edge cases:**
- The heir is a child: allow only grown children (not occupation "Child"). If the only heirs are children, the spouse runs things; with no spouse, there is no heir.
- The heir is in another town: start there.
- Things that point at the old player id must be retargeted to the new one: active arrests, a jailed state (cleared), pending commands, the hotbar, outfit, `cover`, `awaiting`.
- Names stay unique.
- An auto-save right after the switch must reload to the same hash.

**Performance note:** this runs once per death, so it adds no ongoing cost.

**Tests:**
- Marry, have a grown child, then die: the child becomes the player with the purse and house.
- Opinions carry over at half.
- Money and names are conserved.
- With no heir, the ending flag is set.
- Save and load after the switch gives the same hash.
- The whole suite still passes, because many systems read `s.player`.

**Done when:** your character dies and you keep playing as your daughter, and the people who hated your father are cold to her.

### B27. Ending summary pages
- **Status:** NEW. **Size:** S. **Depends on:** F2, C6. Used by C9.
- **Player sees:** when you retire (a menu option) or your line ends, a drawn parchment page tells what became of you, each town and the people you knew.
- **How it works:** a template filled from F2 (your biggest events), C6 moods, P4 (who died and who was born) and G5 (goals).
- **Plugs into:** F2, C6, C9, `view/ui/`.
- **Edge cases:** none.
- **Performance:** once.
- **Tests:** it builds from a known save.
- **Done when:** the ending makes you want to play again.

---

## MILESTONE 11: OUTLAWS AND TOWNS CHANGING HANDS (the frontier fights back)

**Why here:** Needs town mood (6), bounties (8) and NPC-against-NPC gunfights (built here).

**Playable check:** Watch Dustvale fall, then ride back with the posse and win it back.

**Size:** ~3 sessions.

**Features, in build order:** E3 Caravans: escort or rob, C8 Towns change hands (outlaw gangs and posses), A7 Wagons and carts (sim and view).

### E3. Caravans: escort or rob
> **Update after steps 1–4:** Robbery is covered by witnesses, memories and gossip. Guards need NPC-against-NPC fighting (see C8).

- **Status:** PARTLY BUILT. NPC caravans exist (`regional_trade.gd`, `traders.gd`). **Size:** M. **Depends on:** F2; the "Witnesses and evidence" brief (L1); C8's target generalisation for armed guards.
- **Player sees:** some traders travel with a cart and 1 to 2 armed guards. Hire on as an escort for a fee, paid on arrival, and help fight off robbers. Or rob them yourself: the guards fight back, the trader remembers your face, and there will be a bounty.
- **How it works:**
  - When a trader's load value is above 150, the trip gets 1 guard: a resident with occupation "Guard", or the town lends a sheriff.
  - Escort: talk to the trader before departure and accept 15 coins; you must stay within 10 cells for the trip, and you're paid on `arrive`.
  - Robbery: attacking the trader or guard on the road is a crime (`assault`, `theft`) in the town the trip left. Taking the cargo uses `Inventory.transfer`.
  - Robbery by the gang (C8) uses the same code.
- **Plugs into:** `sim/economy/traders.gd` (`_set_out`, `arrive`), `sim/economy/regional_trade.gd`, `sim/combat/gunfire.gd`, `sim/law/law.gd`.
- **Edge cases:**
  - A crime on the road between towns is recorded for the departure town.
  - The escort leaves the trader: no pay.
- **Performance note:** guards follow the trader's path at coarse fidelity unless near the player.
- **Tests:** an escort is paid on arrival; a robbery records crimes and moves goods; money and goods are conserved.
- **Done when:** you escort a timber trader to Dustvale and get paid.

### C8. Towns change hands (outlaw gangs and posses)
> **Update after steps 1–4:** Sheriffs already fight from cover. A gang needs the gunfight code (`sim/combat/gunfire.gd`) to target NPCs, not only the player. That is the big technical step.

**Status:** NEW. **Size:** L. **Depends on:**
- C6 (mood);
- C7 (laws);
- Witnesses and evidence (so the gang has crimes);
- Bounties (optional);
- the existing gunfight AI.

**Player sees:**
- **The gang and its raids:** an outlaw gang (4 to 6 named outlaws) camps in the hills. It robs traders on the road, and when a town is weak (scared and disloyal) it rides in.
- **The takeover:** if the gang beats the sheriffs, the town is theirs. The sheriffs' office becomes their hideout, the notice board reads "Pay your dues", some families flee to the other towns, and the rest pay tribute.
- **The posse:** after a day or two, sheriffs from the other towns gather a posse of armed townspeople to win it back.
- **Your part:** you can ride with the posse, join the outlaws, or stay away. Each choice changes your reputation everywhere.

**How it works:**
- **Gang:** `s.gang = {members: [ids], camp: [x, y], target_town: 0, phase: "camp", since}`. Members are residents with `occupation = "Outlaw"`, created at world start (or when a resident turns outlaw after a crime record; optional). The camp is placed at least 30 cells from any road, in woods (`terrain.woodland`).
- **Phases:**
  - **camp:** outlaws rest, and every 2 days one robs a trader on the nearest road. That is an `Inventory.transfer` of cargo and an F2 event; safety drops in both towns at the ends of that road.
  - **raid:** this needs safety under 25 and loyalty under 25 in some town, with a 30% chance per day. The gang walks to that town and engages the sheriffs using `gunfire.gd`'s cover cycle. The outlaws use the same AI, with the town's sheriffs as targets instead of the player. `gunfire.gd` today targets the player, so a target id must be added; that is the biggest change in this idea.
  - **hold:** this happens if all sheriffs of the town are dead or knocked out. Then `town.controller = "gang"` (default "town"), and the gang occupies the office.
    - Laws (C7) are replaced: tax 25 to the gang, the gun ban for townsfolk only.
    - Each household has a 40% chance to flee to another town on the first day (reuse `migrate`, as in C5), and the rest stay and pay.
  - **posse:** this starts 1 to 2 days after "hold". The sheriffs of the other towns, plus armed adults with high loyalty (2 to 4 per town, given a shotgun from the office rack), walk to the town and engage. If all outlaws are down, `controller` returns to "town", a new sheriff is appointed (`Sheriff.ensure`) and the families who fled may return.
- **The player's choice:** joining the posse is a dialogue option with any posse sheriff, giving reputation + in all towns. Joining the gang is a dialogue option with an outlaw at the camp, after which towns treat you as wanted.

**Plugs into:**
- `sim/combat/gunfire.gd` (`engage`, `cover_cycle`; generalise the target);
- `sim/law/sheriff.gd` (`roster`, `ensure`, the rack);
- `sim/law/law.gd`;
- `sim/factions/society.gd` (`migrate`);
- `sim/economy/traders.gd` (robbery);
- `sim/settlement/professions.gd` (an "Outlaw" occupation, kept out of the demand);
- `view/ui/medieval_map.gd` (a camp mark, and a town under outlaw rule drawn with a black flag).

**Edge cases:**
- The player is in jail when the town falls: the outlaws free you (and expect a favour).
- The gang's last member dies in the camp: the gang is gone, and a new gang may form only after 14 days.
- No town is ever weak enough: the gang only robs traders.
- Money: tribute moves from household purses to a gang account (`"gang"`, in `s.accounts`), conserved.
- Save and load in the middle of a fight must restore all phases.

**Performance note:** this is the most expensive idea. Gang members use coarse fidelity while in camp, and detailed fidelity only while near the player or in a raid. A fight with about 10 people on each side multiplies the gunfight AI cost, so run the simulation benchmark with a forced raid and keep the worst tick under 15 ms. If it goes over, spread the AI over ticks (each fighter decides every 3rd tick, offset by id).

**Tests:**
- Force a weak town and run the raid: the controller changes.
- Families flee or pay, and money is conserved.
- A forced posse retakes the town.
- A 14-day soak with a takeover and a retake is deterministic and the same after save and load.
- The benchmark with a raid stays within budget.

**Done when:** you watch Dustvale fall, ride back with the Reedbank sheriff and townsfolk, and win it back.

### A7. Wagons and carts (sim and view)
- **Status:** NEW. **Size:** M. **Depends on:** C1 (load).
- **Player sees:** traders drive carts pulled along the road, with turning wheels and the load visible in the back. Later you can buy a handcart to haul more yourself.
- **How it works:**
  - A cart is an entity that follows its owner one cell behind, along the owner's path. It holds an inventory of 60 weight.
  - A trader with a cart has a `LOAD` of 40 instead of 20, and is 10% slower off road.
  - Player handcart: while pulling, your carry limit is +40 and you can't run.
- **Plugs into:** `sim/economy/traders.gd` (`LOAD`, `_set_out`), `sim/world/world_db.gd` (entities), C1, `view/world/prop_art.gd`.
- **Edge cases:** carts can't go indoors, so they wait at the door.
- **Performance note:** one extra entity per trader.
- **Tests:**
  - The cart follows the path.
  - The capacity applies.
- **Done when:** a loaded wagon rolls into town.

---

## MILESTONE 12: THE SHAPE OF THE GAME (starts, goals and a guided first hour)

**Why here:** Comes once there's enough game for the starts and goals to point at.

**Playable check:** Start as the Deputy, follow the tips, and work toward the sheriff's badge.

**Size:** ~2–3 sessions.

**Features, in build order:** G1 Starting stories, I1 A gentle tutorial for the first hour, G3 Skills that grow by use, G5 Long goals, B1 Event storyteller, P8 Named characters with small story chains, I6 Controller support and accessibility.

### G1. ★ Starting stories
> **Update after steps 1–4:** The Deputy start can reuse sheriff duties. The debt for the Farmer's heir needs E4 (loans). A drifter is today's start.

- **Status:** NEW. **Size:** M. **Depends on:** T5 (home), E4 (debt) and L2 (bounty) for some starts; the journal (G4) for goals.
- **Player sees:** a new game asks who you are:
  - **The Drifter** (as now): 20 coins and nothing else. First goal: "Find work and a bed."
  - **The Farmer's Heir:** a small house and field in Reedbank, 40 coins, and a 150-coin debt due in 2 weeks. First goal: "Bring in the harvest and pay the debt."
  - **The Deputy:** a badge, a shotgun, and a bed in the Alder Hollow office; the sheriffs treat you as one of them. First goal: "Bring in the man who robbed the trader."
- **How it works:**
  - The `main_menu.gd` choice passes `start_kind` to `Simulation.start_game()`.
  - After the normal world creation, `Starts.apply(sim, kind)` sets things up:
    - money: a transfer from the treasury, conserved;
    - the home: through T5's player household;
    - a debt (E4);
    - the deputy flag: `player_status.deputy = true`. This lets law skip crimes like "weapon" and lets you join arrests.
    - a first journal goal.
  - Store `s.start_kind`.
- **Plugs into:** `view/ui/main_menu.gd`, `sim/core/simulation.gd` (`start_game`), `sim/entities/households.gd`, `sim/law/law.gd`.
- **Edge cases:** old saves count as "drifter".
- **Performance note:** none.
- **Tests:**
  - Each start creates a valid state.
  - Invariants pass.
  - Save and load works.
  - The deputy isn't arrested for carrying a gun.
- **Done when:** the three starts feel like three different first hours.

### I1. ★ A gentle tutorial for the first hour
- **Status:** NEW. **Size:** M.
- **Player sees:** small parchment tips appear the first time something new happens, then never again:
  - near a person: "Click a person to talk or trade";
  - at a stall: "The keeper is coming — wait a moment";
  - first gunshot: "Crouch (C) behind walls for cover";
  - first night: "Find a bed to sleep";
  - first map: "Click a town name to travel there".

  You can turn tips off.
- **How it works:**
  - `player_status.tips_seen = {id: true}`, saved, so it stays done after reloading.
  - A table of `{id, condition(s) -> bool, text}` is checked every 30 ticks by a small sim helper. The view shows the newest unseen tip for 8 s.
- **Plugs into:** `view/ui/game_hud.gd`, a new `sim/player/tips.gd`, I2 (on/off).
- **Edge cases:** never show two at once, and none during dialogue or the map.
- **Performance note:** the checks are cheap, every 30 ticks.
- **Tests:**
  - Each tip fires once.
  - It never repeats after a reload.
- **Done when:** a new player knows the basics after 20 minutes without reading the README.

### G3. Skills that grow by use
> **Update after steps 1–4:** Haggling, shooting and takedowns exist, which gives three skills something to grow from at once.

- **Status:** NEW for the player. Residents have a single `skill` number. **Size:** M. **Depends on:** F5.
- **Player sees:** you get better at what you do. Haggle a lot and your offers land more often; shoot a lot and your spread tightens and you reload faster; farm and your fields yield more; sneak and you're quieter. The journal shows each skill with a short title ("Fair Shot", "Sharp Trader").
- **How it works:**
  - `player_status.skills = {trading, shooting, farming, crafting, stealth}`, each 0 to 100, default 0.
  - Each use adds experience: `gain = max(1, 10 - skill/10)` per meaningful action (a haggle attempt, a shot fired at a target, a harvest, a craft, 60 ticks sneaking near people), stored in tenths so it stays integer.
  - **Effects:**
    - trading: haggle chance +skill/5;
    - shooting: spread × (1 - skill/400) and reload ticks × (1 - skill/300);
    - farming: yield +skill/50 per cell;
    - crafting: time × (1 - skill/250);
    - stealth: noise radius −1 at 50 or more.
- **Plugs into:** `sim/economy/stall_service.gd` (`haggle`), `sim/combat/shotgun.gd`, `sim/farming/crops.gd`, E5, L7.
- **Edge cases:** an heir (C9) starts at half the parent's skills.
- **Performance note:** none.
- **Tests:**
  - Haggling raises trading.
  - A higher skill raises the chance.
  - Gains get smaller as the skill rises.
- **Done when:** after a week of trading you notice haggles working more often.

### G5. Long goals
> **Update after steps 1–4:** The journal (`view/ui/journal_window.gd`) has pages. Goals become a fifth page.

- **Status:** NEW. **Size:** L, as a collection. **Depends on:** C7 (mayor), C8 (gang), T5 (home), G2.
- **Player sees:** big ambitions to work toward, shown in the journal with progress:
  - become sheriff;
  - own the general store;
  - wipe out the gang;
  - build your own homestead out in the wilds and get settlers to join you.
- **How it works:** each goal is a check run once a day:
  - **Sheriff:** reputation 60 or more in a town, plus 3 bounties completed. The mayor offers the badge and `player_status.deputy` becomes "sheriff".
  - **Store:** buy it for 1,000 from the treasury when the keeper retires (P4 old age). You then get the store's sales income.
  - **Gang:** the C8 gang has no members left.
  - **Homestead:** buy a plot of land (more than 30 cells from a town) for 200; building uses the existing construction code (`planner.gd`, `construction_stages`) with planks you bring. A family may move in when there's a free house (`society.migrate`).
- **Plugs into:** `sim/settlement/planner.gd`, `sim/world/world_db.gd` (`construction_stages`), C7, C8, T5, E2.
- **Edge cases:** at most one goal reward per day.
- **Performance note:** daily checks.
- **Tests:** forcing each goal's conditions completes it.
- **Done when:** you wear the sheriff's star.

### B1. ★ Event storyteller
- **Status:** NEW. **Size:** M. **Depends on:** F2.
- **Player sees:** the world has a rhythm of incidents. After quiet days something happens: a sick traveller at the gate, a lost child in the woods, a fire, a fat caravan, a raid. After a hard stretch things calm down.
- **How it works:**
  - `s.director = {tension: 0..100, last_event_tick}`. Tension rises +5 per quiet day and falls by the size of each event (crimes, deaths, fires from F2).
  - Once a day, if tension is above 60 and the last event was 2 or more days ago, pick a weighted event from a table (stream "director"). Each event is a function that sets up real sim state, for example spawning a traveller resident, or setting a child's goal "lost" in the woods with a T3 "find" request.
- **Plugs into:** F2, T3, W4, C8, `sim/entities/residents.gd`.
- **Edge cases:** never fire during the tutorial's first hour, or while the player is jailed.
- **Performance:** once a day.
- **Tests:** a quiet week produces an event; a violent day suppresses them; determinism.
- **Done when:** the world surprises you every few days.

### P8. Named characters with small story chains
- **Status:** NEW. **Size:** M. **Depends on:** F4, "Requests and favours" (T3).
- **Player sees:** each town has 2 to 3 hand-written characters with a personality and a short story told over several meetings. Examples: an old prospector in Dustvale who claims there's a lost silver seam, a widow running the Reedbank inn who wants her late husband's debt cleared, and an ambitious deputy in Alder Hollow who wants the sheriff's job.
- **How it works:**
  - Data file `content/characters/core.json`: id, name, town, profession, outfit and steps. Each step has `{trigger, text, request, reward, next}`.
  - Triggers: talked to, day number, an item delivered, an event kind in F2.
  - On world creation they are added as residents with fixed names, reserved in `s.names_used`.
  - The progress is `s.stories[char_id] = {step, since}`. A step's request uses T3, and its reward uses money from the character's purse (or the town treasury), conserved.
- **Plugs into:** `content/` (new), `sim/production/content_loader.gd` (loading), `sim/entities/residents.gd` (`add_resident`), `sim/entities/names.gd`, F4, T3, F2.
- **Edge cases:**
  - The character is immune to old age until their story ends.
  - If killed, the story ends, with a journal note.
  - Old saves: add the characters only to new games.
- **Performance note:** trigger checks only when talking or once per day.
- **Tests:** each chain completes in a headless script; the steps survive save and load; the names stay unique.
- **Done when:** you finish the prospector's three-step story and find the seam.

### I6. Controller support and accessibility
- **Status:** NEW. **Size:** M for the controller, S for accessibility.
- **Player sees:** you can play with a gamepad: stick movement, a cursor or focus for menus, and a radial menu for context actions. Accessibility options: a colour-blind-safe palette, larger text, and subtitles for important sounds ("[Gunshot, east]").
- **How it works:**
  - Add joypad events to the `InputMap` actions.
  - Menus need focus neighbours.
  - The context menu gets a radial layout when a pad is used.
  - Subtitles: `world_audio.gd` posts a caption for gunshots, screams and door knocks.
- **Plugs into:** `app/input_settings.gd`, `view/ui/context_menu.gd`, `view/ui/game_hud.gd`, `view/audio/world_audio.gd`.
- **Edge cases:** switching between mouse and pad on the fly.
- **Performance note:** none.
- **Tests:**
  - Every menu can be reached by pad.
  - A gunshot produces a caption.
- **Done when:** you can play a session on the couch with a controller.

---

## MILESTONE 13: SOUND AND THE WIDER WORLD (music, nature, and places to find)

**Why here:** Each part is independent: pick freely.

**Playable check:** A walk from town to the hermit's cabin at dawn: birdsong, a deer bolting, herbs to pick, a river to cross.

**Size:** ~3–4 sessions.

**Features, in build order:** S1 Adaptive music, S2 Town ambience, S3 Nature ambience, S4 Wordless mumble voices, S5 Footsteps by surface, W2 Places between towns, W6 Mining, foraging and fishing, W7 Buried caches and treasure maps, B30 A treasure map in pieces, P9 Animals, W4 Fire, W5 Rivers and bridges, W3 Homesteads, or a fourth town, V3 Particles, V4 Richer interiors, V5 Bullet holes and broken windows, V6 More on the drawn map.

### S1. ★ Adaptive music
- **Status:** NEW. **Size:** M.
- **Player sees:** soft music that fits the moment: a quiet guitar or fiddle on the open road, a warmer tune in town, tense drums and low strings in a gunfight, and silence now and then so it never wears out. Changes fade smoothly over a few seconds.
- **How it works:**
  - Three music players (explore, town, tension) on a Music bus.
  - Choose the state from the sim: an active gun alert (`s.law.alert` not empty) is tension; the player inside a town footprint is town; otherwise explore.
  - Crossfade over 3 s. After each track, wait 30 to 90 s of silence.
  - Tracks are original: commissioned, or made with a tracker, or generated.
- **Plugs into:** `view/audio/world_audio.gd`, `content/audio/`, the settings (I2) volume.
- **Edge cases:** no music during sleep fast-forward, or at low volume.
- **Performance note:** streaming audio is cheap. Use compressed .ogg.
- **Tests:**
  - The state picks the right bed.
  - The crossfade volumes move in the right direction over time.
- **Done when:** a gunfight's music change makes your heart beat faster.

### S2. Town ambience
- **Status:** NEW. **Size:** S.
- **Player sees:** towns sound alive: distant chatter when people gather, dogs barking, the forge hammer ringing while the smith works, a sign creaking in the wind, and quiet at night.
- **How it works:**
  - Positional one-shots (`AudioStreamPlayer2D`, pooled at about 8) at their sources:
    - chatter at pairs talking (`speech.gd` pairs);
    - a hammer while the forge works;
    - dogs from P9;
    - creaks when the wind is above 60.
  - Volume follows distance; nothing plays where nothing happens.
- **Plugs into:** `view/audio/world_audio.gd`, sim states as listed.
- **Edge cases:** cap the simultaneous sounds at 8.
- **Performance note:** pooled players only.
- **Tests:** emitters follow state, and nothing plays in an empty town at night.
- **Done when:** you hear the forge before you see it.

### S3. Nature ambience
- **Status:** NEW. **Size:** S.
- **Player sees:** birds at dawn, crickets at night, rain pattering on the roof when you're indoors in a storm, and wind in the trees on blustery days. It is always varied, never a repeating hum.
- **How it works:** a scheduler picks a sample from a set every 2 to 12 s, according to time of day and weather, with random pitch (±5%) and pan. Indoors uses a muffled rain loop with proper loop points (a real loop file, not a trimmed one).
- **Plugs into:** `view/audio/world_audio.gd`, `sim/entities/needs.gd` (`is_night`, `indoors`), `sim/world/weather.gd`.
- **Edge cases:** silence in jail? No: you hear muffled outdoor sound.
- **Performance note:** one or two players.
- **Tests:**
  - Samples vary.
  - There is no single continuous loop except the proper indoor rain loop.
- **Done when:** a summer night sounds like one.

### S4. Wordless mumble voices
- **Status:** NEW. **Size:** S–M.
- **Player sees:** when people speak (speech bubbles), you hear short mumbled syllables in their own voice, higher or lower, quicker or slower, so you recognise who's talking without words.
- **How it works:**
  - Voice = pitch and speed seeded from the person's id (stable).
  - When a new line appears in `s.speech`, play 3 to 8 short syllable samples at that pitch, positioned at the speaker.
- **Plugs into:** `view/audio/world_audio.gd`, `sim/entities/speech.gd` (`s.speech` entries).
- **Edge cases:** at most 2 speakers voiced at once, and none for off-screen speakers.
- **Performance note:** pooled players.
- **Tests:** the same person always gets the same pitch.
- **Done when:** you can tell the sheriff's voice apart.

### S5. Footsteps by surface
- **Status:** NEW. Footstep cues exist. **Size:** S.
- **Player sees:** footsteps sound like the ground: hollow on wooden floors, crunchy on gravel roads, soft on grass, squelchy in mud, crisp in snow.
- **How it works:**
  - Surface = indoors floor (wood), a road cell (gravel), mud (W1), snow (`weather.snow` above 30), otherwise grass or dirt.
  - Pick the sample set from the surface. The same surface table feeds L7's noise radius, so put it in the sim (`Surface.at(s, cell)`).
- **Plugs into:** `view/audio/world_audio.gd`, `sim/world/` (new `surface.gd`), `sim/world/town_layout.gd` (`road_kind`).
- **Edge cases:** none.
- **Performance note:** none.
- **Tests:** each surface maps to the right set.
- **Done when:** walking into a house changes your steps.

### W2. Places between towns
- **Status:** NEW. **Size:** M. **Depends on:** nothing. Story characters (P8) can live there.
- **Player sees:** the land between towns has places worth finding:
  - an abandoned mine with ore and danger;
  - a burned-out farmstead with a letter that hints at a story;
  - a hermit's cabin, where the hermit sells herbs and old maps;
  - a lookout hill with a view over all three towns;
  - a ruined chapel.

  They appear on your map once you've been near them.
- **How it works:**
  - Place 4 to 6 places at world creation (stream "places"), each at least 20 cells from towns and 4 from roads, in free land (`placement.gd`).
  - Each place is a small fixed layout (a list of wall and fixture cells with a chest). Reuse building footprints from `world_db.footprint` where possible.
  - `s.places[id] = {kind, cell, discovered: false}`; a place is discovered when the player is within 12 cells.
  - Loot chests use `chests.gd`, restocked every 14 days.
- **Plugs into:** `sim/world/placement.gd`, `sim/world/world_db.gd`, `sim/entities/chests.gd`, `sim/world/road_planner.gd` (keep clear of roads), `view/ui/medieval_map.gd`.
- **Edge cases:**
  - Never place a site on a road cell, a field or a town.
  - The map is 582 by 420 cells (bounds -96..486 by -84..336) with the towns far apart, so there is plenty of room between them; still check each place against roads, fields and the woods mask.
- **Performance note:** places add a few dozen wall cells and fixtures, which is negligible.
- **Tests:**
  - Places are placed deterministically.
  - All are reachable by path.
  - None is on a road.
  - Discovery flips when you come near.
- **Done when:** you stumble on the hermit's cabin in the woods.

### W6. Mining, foraging and fishing
- **Status:** NEW for the player. Miners and gatherers work ore and trees today. **Size:** S–M. **Depends on:** W5 for fishing; E5 for herb bandages.
- **Player sees:** with a pick you can dig ore at the rocks. In the woods you find berries and herbs, which grow back after a while. With a rod, you can fish at the river. Herbs and cloth make bandages at a workbench.
- **How it works:**
  - **Mining:** a "Dig" option at ore entities when you hold a pick tool. It takes 60 ticks for 1 ore and uses the same entity stock the Miners use (`regional_trade.gd` creates ore inventories).
  - **Foraging:** forage spots are new entities placed in woodland at world creation (stream "forage"). "Gather" gives 1 to 2 berries (food) or herbs, and the spot regrows in 2 days.
  - **Fishing:** at water cells (W5), with a rod. A 40% chance per 100 ticks of 1 fish (food).
  - **New items** (with weights): herb, berry, fish, rod, pick.
- **Plugs into:** `sim/player/context_actions.gd`, `sim/world/world_db.gd` (entities), `sim/inventory/inventory_store.gd`, `content/items/core.json`, `content/recipes/core.json`.
- **Edge cases:**
  - Mining another town's ore near their mine competes with their Miners. It's allowed, but the town notices (a memory).
  - Taking from a fenced garden is theft.
- **Performance note:** forage spots are entities, so keep them under 60 and don't scan them every tick.
- **Tests:**
  - Gathering gives items.
  - Spots regrow on time.
  - Mining lowers the ore stock.
- **Done when:** you live off the land for a day without buying food.

### W7. Buried caches and treasure maps
- **Status:** NEW. **Size:** S. **Depends on:** W2 (the hermit sells maps), the medieval map.
- **Player sees:** you buy or find an old map scrap. It shows an X on your drawn map. Go there with a shovel and dig, and you find a chest with coins and goods.
- **How it works:**
  - At world creation, place 3 to 5 caches at off-road cells (stream "caches"). Each is a chest entity marked `buried`: invisible and not interactable until dug.
  - The coins come from a reserved world account (`"caches"` in `s.accounts`, created from the starting money total), so money is conserved.
  - A map item `cache_map:<id>` adds a marker to `medieval_map.gd`.
  - "Dig" with a shovel within 1 cell takes 80 ticks.
- **Plugs into:** `sim/entities/chests.gd`, `view/ui/medieval_map.gd`, `sim/player/context_actions.gd`.
- **Edge cases:** dig only on walkable ground, and the cache is gone once dug.
- **Performance note:** none.
- **Tests:**
  - The map marks the right cell.
  - Digging opens the chest.
  - The money sum is unchanged.
- **Done when:** you follow an X and dig up 60 coins.

### B30. A treasure map in pieces
- **Status:** NEW. It extends W7. **Size:** S.
- **Player sees:** a map torn in 3. One piece is sold by the hermit, one is on an outlaw, one is in a story character's chest. Together they reveal a big cache.
- **How it works:** 3 items `map_piece:<n>`; holding all 3 reveals W7's biggest cache on the map.
- **Plugs into:** W7, W2, P8, C8.
- **Edge cases:** pieces can be lost if their holder dies; drop them as loot.
- **Performance:** none.
- **Tests:** all 3 reveal the cache.
- **Done when:** you hunt down the last piece.

### P9. Animals
- **Status:** NEW. **Size:** M (L with hunting and horses). **Depends on:** nothing.
- **Player sees:**
  - **Dogs** follow their owners and bark at strangers at night.
  - **Farm animals:** chickens peck in yards and cows graze in pens; they give eggs and milk.
  - **Wildlife:** deer graze at the woods' edge and bolt when you come near, and wolves howl at night far from town.
  - **Horses** stand at the hitching posts.
- **How it works:**
  - A new entity kind, "animal", with `{species, owner, home, cell, path}`, run at coarse fidelity away from the player.
  - Dogs follow `owner` within 3 cells.
  - Chickens and cows wander in a pen rect, need 1 feed (rye) per day from the owner's home, and give 1 egg or 1 milk per day into that home's pantry. These are new food items with a weight (C1); without feed, nothing is produced.
  - Wildlife: deer herds of 3 to 5 inside wood areas that flee when the player is within 8 cells; wolves only at night, only far from towns, attacking only if the player is alone and hurt.
  - Population: a fixed cap per species, with regrowth when below the cap (stream "animals").
- **Plugs into:** `sim/world/world_db.gd` (`add_entity`, the entity kinds), `sim/movement/navigation.gd`, `sim/world/fidelity.gd`, `sim/entities/family_economy.gd` (pantry), the new `view/actors` drawing for each species.
- **Edge cases:**
  - Animals are not people: they have no names in `names_used` and no accounts.
  - Killing someone's animal is a crime (`theft`, or a new "animal" crime).
  - Deer must not walk into towns.
- **Performance note:** dozens of animals means more pathing. Use short wander paths (at most 8 cells) and coarse fidelity, and step them every 3rd tick.
- **Tests:** populations stay within their caps; fed pens produce; wildlife stays in the woods; save and load.
- **Done when:** a dog trots after its owner and deer scatter as you walk the road.

### W4. Fire
- **Status:** NEW. **Size:** M. **Depends on:** W1 (wind, rain).
- **Player sees:** fire is a real danger. A knocked-over lamp, a lightning strike or arson sets a building alight. It spreads to neighbours if the wind blows that way. Townsfolk run to the well and pass buckets to fight it. Rain helps. A burned building is a blackened shell until rebuilt, and its stock is lost.
- **How it works:**
  - `s.fires[cell_key] = {strength 1..10, since}`. Every 20 ticks each burning cell:
    - grows by +1, up to 10;
    - spreads to a flammable neighbour (a wooden wall, a tree, a field, a fixture) with a chance of strength × 3%, ×2 downwind (`weather.wind` direction) and 0 in rain.
  - At strength 10 for 200 ticks, the building is burned: its walls are removed (`apply_mutation`) and its inventory destroyed. Record the destroyed goods, because the totals must change deliberately; the invariant needs to allow destroyed goods with a record.
  - **Firefighting:** residents within 25 cells get a "fight_fire" goal: fetch water at the well (`Needs.near_water` already knows the wells), walk to the fire, and lower its strength by 2.
  - **Causes:**
    - lightning in storms: 1% per storm day per town;
    - a lamp in a brawl indoors: 5%;
    - the player's "Set fire" action with a lantern, which is arson (`SENTENCE` 12).
- **Plugs into:** `sim/world/world_db.gd` (`apply_mutation`), `sim/entities/residents.gd` (goals), `sim/entities/needs.gd` (`near_water`), `sim/world/weather.gd`, `sim/diagnostics/invariants.gd` (goods destroyed by fire must be counted), `view/` (flame and smoke particles).
- **Edge cases:**
  - Rebuilding uses the existing construction flow (`planner.gd`).
  - A fire next to the player hurts (burns).
  - Rain puts out all fires.
- **Performance note:** a fire can grow to many cells. Cap the burning cells at 60, update them every 20 ticks, and pool the particles. Benchmark a big fire.
- **Tests:**
  - A fire spreads downwind.
  - A bucket chain puts it out.
  - Rain stops it.
  - Determinism.
  - The invariant passes with destroyed goods recorded.
- **Done when:** you watch the town fight a blaze at the sawmill.

### W5. Rivers and bridges
- **Status:** NEW. **This would be the first water in the game:** `terrain.gd` has only woodland noise, and there is no water cell type. **Size:** M–L. **Depends on:** a map plan (where the river goes without breaking towns and roads).
- **Player sees:** a river winds across the land. Roads cross it on wooden bridges, and in a few places there's a shallow ford you can wade (slowly, and you get wet). After heavy rain the river rises and can wash a bridge away for a few days, so travel takes the long way round. You can fish from the banks (W6).
- **How it works:**
  - **The river:** a noise-guided path of cells from one map edge to another, generated before roads (stream "river"), avoiding town footprints. Water cells are not walkable (`World.walkable`). Fords are walkable at a 3× step cost.
  - **Roads:** `road_planner.gd` must route to cross only at bridge points it creates (a bridge is a walkable fixture over water).
  - **Floods:** after 2 rain days in a row, each bridge has a 20% chance per day to be out (marked not walkable) for 2 days. The nav grid already rebuilds when walls change, so the mutation does the rest.
  - The view draws the water (a shader, or tiles), banks and bridges.
- **Plugs into:** `sim/world/terrain.gd`, `sim/world/world_db.gd` (`walkable`, cells), `sim/world/road_planner.gd`, `sim/movement/nav_grid.gd`, `sim/entities/needs.gd` (`near_water` can include the river), `view/world/landscape.gdshader`.
- **Edge cases:**
  - Old saves have no river, so add it to new worlds only.
  - Traders' routes and auto-travel must handle a washed-out bridge: there must always be a ford.
- **Performance note:** a nav grid rebuild on a flood is a one-off. Check it takes under 50 ms.
- **Tests:**
  - Every town pair stays connected with one bridge out (through the ford).
  - Water isn't walkable.
  - The river generates deterministically.
- **Done when:** a flood makes you wade the ford instead of using the bridge.

### W3. Homesteads, or a fourth town
- **Status:** NEW. **Size:** M for homesteads, L for a town. **Depends on:** W2's placement approach.
- **Player sees:** lonely farms along the roads, each with a family, a field and a fence. Traders stop by, and outlaws raid them (L3). Later, maybe a fourth town on new land.
- **How it works:**
  - **Homesteads:** 2 to 3 single households placed beside roads (stream "homesteads"). Each has a home, a farm plot (`crops.add_plot`) and a family created with `residents.add_resident`, belonging to the nearest town's settlement for laws and trade.
  - **A fourth town:** `town_layout.gd` and many systems assume three towns (`sheriff.OFFICE_CELLS` has 3 entries; `society.initialize` names 3 factions). A fourth town means widening the map (`WIDTH`, `HEIGHT` in `world_db.gd`) and generalising those tables. Plan that as its own project.
- **Plugs into:** `sim/entities/residents.gd` (`add_resident`), `sim/farming/crops.gd`, `sim/world/placement.gd`, `sim/settlement/`, `sim/world/town_layout.gd`.
- **Edge cases:** homestead families still shop in their town, which is a long walk, so give them a bigger pantry.
- **Performance note:** a few more residents at coarse fidelity is fine. A fourth town needs the "Room for more towns" work (X4) first.
- **Tests:**
  - Homesteads exist, are reachable and their family lives normally.
  - Money and names are conserved.
- **Done when:** you pass a farmhouse halfway to Dustvale and the farmer waves.

### V3. Particles
- **Status:** NEW. **Size:** S.
- **Player sees:**
  - dust puffs behind walkers on dry roads;
  - smoke from chimneys while someone cooks inside;
  - sparks at the forge while the smith works;
  - fireflies on summer nights near the woods.
- **How it works:** each emitter is switched by sim state:
  - the road and weather state;
  - a household eating;
  - forge work in `recipe_system`;
  - the season and night.

  Use pooled GPU particle nodes placed near the camera, not one per building.
- **Plugs into:** `view/world/world_view.gd`, `view/world/fixture_director.gd`.
- **Edge cases:** turn emitters off when the zoom is far out.
- **Performance note:** a fixed pool, at most about 12 emitters active, culled off screen.
- **Tests:** emitters switch with their states.
- **Done when:** you see chimney smoke at dinner time.

### V4. Richer interiors
- **Status:** NEW. Interiors exist (`interior_art.gd`, `placement.gd`). **Size:** M.
- **Player sees:** homes reflect who lives there. A poor family has a straw bed, a stool and bare boards. A wealthy one has a rug, a dresser, pictures and a big bed. A blacksmith's home has tools by the door; a farmer's has sacks of grain.
- **How it works:**
  - A wealth tier comes from the household purse (`FamilyEconomy.purse`): poor under 40, middle 40 to 150, rich over 150, checked when the furniture is placed.
  - Furniture sets per tier and profession clutter go into `placement.gd`. Keep the set chosen at placement, and only re-furnish when the tier changes by 2 steps, so it doesn't change every day.
- **Plugs into:** `sim/world/placement.gd`, `view/world/interior_art.gd`, `sim/entities/family_economy.gd`.
- **Edge cases:**
  - Clickable furniture (beds, chests) must still be where `context_actions` expects it.
  - Old saves keep their furniture.
- **Performance note:** more props indoors means more draw items. Interior art is drawn only when the roof is hidden, so check that the cost stays small.
- **Tests:**
  - The rich home has more furniture than the poor one.
  - The result is deterministic.
- **Done when:** you can guess who is rich by looking inside.

### V5. Bullet holes and broken windows
- **Status:** NEW. Blood decals exist (`brawl.add_blood`, `MAX_BLOOD` 96). **Size:** S.
- **Player sees:** pellets that hit a wall leave holes, and shot windows crack and break until the owner fixes them.
- **How it works:**
  - In `shotgun._strike` when the surface is a wall, add a decal `{cell, tick}` to `s.decals` (capped at 64, lasting 2 days), the same pattern as blood.
  - Windows: a `broken_windows[cell]` that the owner repairs after 1 day (a home task).
- **Plugs into:** `sim/combat/shotgun.gd` (`_strike`, `surface_at`), `view/world/world_view.gd`.
- **Edge cases:** the decal is placed on the face the shot came from.
- **Performance note:** the cap of 64, drawn batched.
- **Tests:**
  - A wall hit adds a decal.
  - The cap holds.
  - The window is repaired.
- **Done when:** after a gunfight the walls show it.

### V6. More on the drawn map
- **Status:** PARTLY BUILT. `view/ui/medieval_map.gd` draws the map once when it opens. **Size:** S.
- **Player sees:**
  - You can place your own markers (pin, star, skull, and a note).
  - You can draw a route by clicking points.
  - Known places (W2), bounties (L2), rumours with a location (P2) and cache Xs (W7) show as small inked symbols.
  - The paper looks folded and worn.
- **How it works:**
  - Markers live in the sim save (`player_status.map_marks`), as player data the view only reads; adding one is a command.
  - Draw them in the existing one-time map paint. Adding a marker repaints the map once.
- **Plugs into:** `view/ui/medieval_map.gd`, `view/ui/map_overlay.gd`, `sim/core/simulation.gd` (a command to add or remove a mark).
- **Edge cases:** at most 30 marks.
- **Performance note:** keep the "paint once when M is pressed" rule. Don't redraw every frame.
- **Tests:**
  - Marks persist through save and load.
  - The map repaints once on adding.
- **Done when:** you mark the outlaw camp and plan a route to it.

---

## MILESTONE 14: TECHNICAL AND THE FINAL PASS (ready to share)

**Why here:** Last, so it measures and ships everything else.

**Playable check:** At least 60 FPS everywhere, a 30-minute play check, then the big push and the first Release.

**Size:** ~2 sessions.

**Features, in build order:** X5 Items, recipes, names and tuning in data files, X4 Room for more towns and people, X1 Windows build, X2 First GitHub Release.

### X5. Items, recipes, names and tuning in data files
- **Status:** PARTLY BUILT. `content/items/core.json`, `content/recipes/core.json` and `example_mod.json` load through `sim/production/content_loader.gd`. **Size:** M.
- **Player sees:** nothing directly. It makes the game easy to tune and mod.
- **How it works:** move these hard-coded tables into `content/*.json`, loaded once at start:
  - `market.BASE`, `TARGET`;
  - `names.gd` lists;
  - `cover.HIGH_ITEMS`;
  - `Professions.DESCRIPTIONS`;
  - the weapon stats (L6);
  - the item weights (C1).

  Add a schema check that names the bad file and field, and keep `example_mod.json` as a working sample mod.
- **Plugs into:** `sim/production/content_loader.gd`, `sim/economy/market.gd`, `sim/entities/names.gd`, `sim/combat/cover.gd`, `sim/settlement/professions.gd`.
- **Edge cases:** the data must be identical at load, or determinism differs between machines; sort the keys.
- **Performance note:** load once only.
- **Tests:**
  - A mod adds an item that appears at a stall.
  - A broken file gives a clear error.
  - The hashes are unchanged with the default data.
- **Done when:** changing bread's price is a one-line data edit.

### X4. Room for more towns and people
- **Status:** NEW. The fidelity levels (`fidelity.gd`) and derived caches exist. **Size:** M–L.
- **Player sees:** bigger, busier towns and maybe more of them, still running smoothly.
- **How it works:**
  - Profile first with `tests/benchmark/full_game_benchmark.gd`, `simulation_benchmark.gd` (20, 100 and 300 people) and the F4 perf tab.
  - Then:
    - push residents far from the player to coarse or aggregate fidelity more aggressively;
    - spread daily work across ticks (each town on a different tick offset);
    - add derived lookups wherever a system loops over all entities.
  - Generalise the three-town assumptions (`sheriff.OFFICE_CELLS`, the `society.initialize` factions, `town_layout`) into data.
- **Plugs into:** `sim/world/fidelity.gd`, `sim/core/derived_cache.gd`, `sim/settlement/`, `sim/law/sheriff.gd`, `sim/world/town_layout.gd`, `tests/benchmark/`.
- **Edge cases:** determinism must hold across fidelity changes (it already does today; keep the tests).
- **Performance note:** this is the performance task itself. The target is 3× today's people with the tick budget in Section 9.
- **Tests:** the benchmarks meet the budgets at 3× population.
- **Done when:** the towns are twice as big and the game is just as smooth.

### X1. Windows build
- **Status:** PARTLY BUILT. `scripts/package_windows.sh` exists. **Size:** M.
- **Player sees:** Windows players download a zip whose first item is `Project Solo.exe`.
- **How it works:**
  - Check `export_presets.cfg` has a Windows preset.
  - Run `package_windows.sh` in the Build workflow (`.github/workflows/`, which already builds the Mac app), and upload the zip as an artifact.
  - Test it on a real Windows machine or VM.
- **Plugs into:** `scripts/package_windows.sh`, `export_presets.cfg`, `.github/workflows/`, `tools/prepare_exports.sh`.
- **Edge cases:**
  - Paths with spaces.
  - The save folder location on Windows (`user://`).
- **Performance note:** check FPS on a typical Windows laptop too.
- **Tests:** CI builds the zip, and the game starts and loads a save.
- **Done when:** a friend on Windows can play.

### X2. First GitHub Release
- **Status:** NEW. **Size:** S. **Do this only at the big push.**
- **Player sees:** a Releases page with a version number, the Mac app zip (and Windows later), and short notes.
- **How it works:** tag `v0.1.0` and attach the build artifacts. The README already points to Releases.
- **Plugs into:** GitHub, README.
- **Edge cases:** the zip must open with `Project Solo.app` first.
- **Performance note:** none.
- **Tests:** download the zip and open it.
- **Done when:** someone can download and play without git.

---

## 5. OPTIONAL IDEAS (not chosen yet)

Each can be added to a milestone when you want it. A good home is suggested in brackets.

### B2. ★ Pre-simulated history and a legends book  [fits milestone 12]
- **Status:** NEW. **Size:** M–L. **Depends on:** F2, P4 (life cycle).
- **Player sees:** the world has a past. People mention "the fire of '62" or "old sheriff Ward, shot on the Moss Road". A book in each town hall lists the history and family trees, including what you do as the game goes on.
- **How it works:**
  - Generating a past by running the full sim for 20 years would be far too slow. Instead, generate a **summary history** at world creation: a seeded list of 20 to 40 historical events (founding dates, fires, notable deaths, feuds, a gang), with dead ancestors added to the family trees and names reserved in `s.names_used`.
  - Some events leave traces in the present: a burned ruin (W2), a grave (P4), a feud between two families (P3 rivals).
  - Speech can mention them.
  - The book view reads `s.history` plus F2 events.
- **Plugs into:** `sim/world/world_db.gd` (`seed_world`), `sim/entities/names.gd`, P3, P4, W2, G4.
- **Edge cases:** the history must not contradict the present (a "dead" ancestor can't be alive).
- **Performance:** generated once at world creation, in milliseconds.
- **Tests:** deterministic history; names stay unique; the traces exist.
- **Done when:** an old man's story matches a ruin you found.

### B3. Being beaten and robbed instead of dying  [fits milestone 8]
- **Status:** PARTLY BUILT. Knock-outs exist. **Size:** M.
- **Player sees:** losing a fistfight or ambush doesn't always end the game. You wake up bruised, robbed of your coins, maybe dumped by the road, or helped to the doctor by a kind passer-by.
- **How it works:**
  - When the player's body health would reach 0 from blunt damage (not gunshots or the head), with a 60% chance (stream "mercy") a knock-out happens instead of `kill_player`.
  - The attacker takes 50% of your coins and one random item (`Inventory.transfer`, conserved), and you wake 2 hours later.
  - A resident with opinion 20 or more nearby may carry you to the nearest bed (reuse C2 in reverse).
- **Plugs into:** `sim/combat/brawl.gd` (`kill_player`, `knockdown`), `sim/combat/body_health.gd`, `view/ui/knockout_screen.gd`.
- **Edge cases:** gunshot deaths stay deaths; with C9, it's the heir.
- **Performance:** none.
- **Tests:** a beating to 0 knocks you out and robs you, on a known seed.
- **Done when:** losing a fight becomes a story instead of a reload.

### B4. Limbs heal unevenly; crutches  [fits milestone 7]
- **Status:** PARTLY BUILT. Limb damage and NPC healing (`NPC_HEAL_EVERY`) exist. **Size:** S.
- **Player sees:** a badly hurt leg takes weeks to heal fully; until then you limp. A crutch from the carpenter lets you walk at near-normal speed but you can't use two-handed things.
- **How it works:** player limbs heal 1 point per 600 ticks while resting or sleeping, and 1 per 1,800 otherwise. A disabled limb (`DISABLED_AT`) heals to a scar at most 20 damage permanently, unless a doctor treats it in time. A crutch item cancels the leg slowdown in `step_ticks` but blocks the shotgun.
- **Plugs into:** `sim/combat/limbs.gd` (`update`, `step_ticks`), `sim/combat/body_health.gd`, `sim/combat/shotgun.gd`.
- **Edge cases:** an heir doesn't inherit the injuries.
- **Performance:** none.
- **Tests:** the heal rates; the crutch effect.
- **Done when:** a broken leg changes how you play for a week.

### B5. Build a group of followers  [fits milestone 9]
- **Status:** NEW. It extends T4 (hiring). **Size:** L.
- **Player sees:** people who admire you (opinion 70 or more), or drifters you help, ask to ride with you. They have skills, needs and opinions of their own, and they can stay at your homestead to work it.
- **How it works:** use T4 hirelings without a wage, but with loyalty (F1 opinion). The cap is 3. Followers eat from your supplies, and leave if their opinion falls below 20.
- **Plugs into:** T4, F1, G5 (homestead).
- **Edge cases:** followers' families miss them (a memory).
- **Performance:** detailed fidelity for up to 3 extra people.
- **Tests:** a follower joins at high opinion and leaves at low opinion.
- **Done when:** you have a small crew.

### B6. Neutral wanderers on the roads  [fits milestone 13]
- **Status:** NEW. **Size:** S.
- **Player sees:** pilgrims, peddlers, beggars and lone prospectors walk the roads with their own business. They chat, trade a little, ask for help, or spread news (P2).
- **How it works:**
  - 1 to 3 wanderer residents with no town, walking between towns at coarse fidelity, created and retired by the storyteller (B1) or on a daily chance.
  - They have names (reserved), a small purse, and pass rumours on.
- **Plugs into:** `sim/entities/residents.gd`, `sim/economy/traders.gd` (similar trip logic), P2.
- **Edge cases:** on retirement, their purse goes back to a treasury (conservation).
- **Performance:** coarse fidelity.
- **Tests:** wanderers come and go; money is conserved.
- **Done when:** the road between towns feels travelled.

### B7. Mood breaks  [fits milestone 6]
- **Status:** NEW. **Size:** M. **Depends on:** F1; P4 for grief.
- **Player sees:** people under too much strain crack. A man who lost his wife and his job goes on a drinking binge, picks a fight, or packs up and leaves town.
- **How it works:**
  - `npc.strain` is 0 to 100. It rises from hunger, a death in the family, being robbed, unpaid wages and fear, and falls with good meals, rest days and friends.
  - Above 80, once a day, 20% chance (stream "breaks") of a break for 1 to 2 days:
    - a binge (at the saloon or home, drunk pose P7);
    - a brawl with a rival (P3);
    - leaving (`society.migrate`).
- **Plugs into:** `sim/entities/residents.gd`, `sim/entities/needs.gd`, `sim/factions/society.gd`, `sim/combat/brawl.gd`.
- **Edge cases:** sheriffs breaking during a fight could be dramatic; allow it but rarely.
- **Performance:** daily.
- **Tests:** high strain causes a break; the break ends.
- **Done when:** you see a grieving widower drinking himself into a fight.

### B8. Illness spreading  [fits milestone 6]
- **Status:** NEW. **Size:** M.
- **Player sees:** a fever spreads through a town: people cough, stay home, the market empties and the doctor is overwhelmed. Medicine (antiseptic or herbs) helps. It can reach you.
- **How it works:**
  - `npc.illness = {kind, since, severity}`. Each day each ill person infects each household member (30%) and each talk partner (10%).
  - It lasts 3 to 6 days. The ill stay home and work nothing.
  - Old, hungry people may die (P4).
  - Started by B1 or a traveller.
  - Antiseptic (it already exists as an item) shortens it.
- **Plugs into:** `sim/entities/residents.gd`, `sim/entities/households.gd`, `sim/entities/speech.gd`, `sim/economy/market.gd` (antiseptic demand).
- **Edge cases:** cap it so it can't wipe out a town; immunity for 14 days after recovery.
- **Performance:** daily.
- **Tests:** the spread is deterministic; recovery and immunity work.
- **Done when:** a town shuts down for a few days and recovers.

### B9. Named artifacts  [fits milestone 9]
- **Status:** NEW. **Size:** S. **Depends on:** E6 for gear condition.
- **Player sees:** sometimes a craftsman makes something special: a fine rifle "Widowmaker", a silver-inlaid knife. It has a name, a history and better stats, and people want it.
- **How it works:** on a craft with skill 80 or more, a 2% chance gives a named item, stored in `s.artifacts[id] = {item, name, maker, history: []}`. It is a unique item id in the inventory, with stats ×1.2 and a value ×5. Its history grows with notable events (F2).
- **Plugs into:** `sim/production/recipe_system.gd`, `sim/inventory/inventory_store.gd`, F2.
- **Edge cases:** unique items must survive transfers (a per-copy id).
- **Performance:** none.
- **Tests:** creation on a seed; it survives save and load; the history appends.
- **Done when:** you carry a named gun with a past.

### B10. Your own camp in the wilds  [fits milestone 13]
- **Status:** NEW. **Size:** M.
- **Player sees:** set up camp anywhere: a bedroll, a fire, a pot. Sleep, cook and save there. Later upgrade it with a tent and a stash chest.
- **How it works:** a "camp kit" item places a camp entity (a bedroll counts as a bed for `sleep.gd`, a fire as a cook station). The fire warms you (cancels `cold`). One camp at a time; packing it up returns the items.
- **Plugs into:** `sim/player/sleep.gd`, `sim/entities/needs.gd` (cold), `sim/player/context_actions.gd`, E5.
- **Edge cases:** not inside towns; wolves (P9) can approach at night.
- **Performance:** none.
- **Tests:** placing, sleeping and packing up.
- **Done when:** you spend a night under the stars between towns.

### B11. A horse and the bond with it  [fits milestone 13]
- **Status:** NEW. **Size:** L. **Depends on:** P9 (animals).
- **Player sees:** buy a horse. It is much faster on roads, carries saddlebags, and comes when you whistle. It trusts you more over time and can be stolen.
- **How it works:**
  - A horse entity owned by the player. While riding, `Pace` uses the horse's speed table: road 2.5× walk, off road 1.5×.
  - Saddlebags give +40 carry (C1).
  - `bond` is 0 to 100, rising with feeding and riding. At high bond it comes from farther when you whistle, and it panics less at gunfire.
  - Stealing a horse is a crime.
- **Plugs into:** `sim/movement/pace.gd`, `sim/core/simulation.gd` (movement), P9, C1, `view/actors/` (rider pose).
- **Edge cases:** indoors you dismount automatically; auto-travel (`travel`) uses the horse.
- **Performance:** one more detailed entity.
- **Tests:** riding speed; saddlebag load; bond growth.
- **Done when:** galloping between towns.

### B12. Chance encounters on the road (story cards)  [fits milestone 12]
- **Status:** NEW. **Size:** M. **Depends on:** B1, the auto-travel already in the game.
- **Player sees:** while auto-travelling, a parchment card sometimes pops up: "A wagon lies on its side. A man waves you down." The choices are help, rob or ride on. The result plays out in the world.
- **How it works:** during `travel`, 1 chance per 1,000 ticks of road (stream "encounter"). The card is a data entry with choices, each setting up real state: spawn a resident with a broken cart and a T3 request, a bandit ambush (C8 gang member), or a lost traveller. Travel pauses while the card is open.
- **Plugs into:** `sim/core/simulation.gd` (`_travel_to`), `view/ui/` (a card window), B1, T3.
- **Edge cases:** none while carrying a body or under arrest.
- **Performance:** none.
- **Tests:** a card appears on a known seed; each choice sets up state.
- **Done when:** a quiet ride turns into a small story.

### B13. Hunting with pelt quality  [fits milestone 13]
- **Status:** NEW. **Size:** M. **Depends on:** P9 (wildlife), L6 (rifle or bow).
- **Player sees:** hunt deer for meat and hides. A clean shot gives a fine pelt that sells well to a trapper; a messy shotgun blast ruins it.
- **How it works:** a kill quality comes from the weapon (bow or rifle good, shotgun poor) and the hits (a single hit is good). Butchering gives meat (food) and a pelt with quality 1 to 3. The trapper (a profession or the store) buys pelts at `BASE` × quality.
- **Plugs into:** P9, L6, `sim/economy/market.gd` (`BASE` for pelt).
- **Edge cases:** hunting in a town's fenced pasture is theft.
- **Performance:** none.
- **Tests:** pelt quality by weapon.
- **Done when:** you learn to bring a bow for hunting.

### B14. Learning to read  [fits milestone 12]
- **Status:** NEW. **Size:** S.
- **Player sees:** at the start (drifter) you can't read. Signs, letters, posters and the legends book show scribbles until someone teaches you (lessons from the teacher or a story character, for coins), and then the world opens up.
- **How it works:** `player_status.literate` is false by default for the drifter start, true for others. The view swaps text for glyph scribbles when false. Lessons are 3 sessions of 300 ticks.
- **Plugs into:** `view/` text drawing (signposts, notice board, journal), G1 (starts).
- **Edge cases:** the UI menus stay readable, only in-world text is affected; give it an accessibility override.
- **Performance:** none.
- **Tests:** literacy toggles the text.
- **Done when:** reading your first wanted poster feels like a reward.

### B15. Saving at your bed, or with a paid drink  [fits milestone 9]
- **Status:** NEW. **Size:** S. **Depends on:** I3.
- **Player sees:** an optional "hardcore" mode where you can save only at a bed you own or rent, or by buying a drink at the saloon.
- **How it works:** a setting chosen at new game (`s.rules.save_anywhere`). The save command checks it.
- **Plugs into:** `sim/persistence/save_manager.gd`, I3, T5.
- **Edge cases:** the autosave still runs (or is optional).
- **Performance:** none.
- **Tests:** the rule blocks saving away from a bed.
- **Done when:** risky trips feel risky.

### B16. Lockpick and pickpocket minigames  [fits milestone 8]
- **Status:** NEW. **Size:** M. **Depends on:** L5, L7.
- **Player sees:** picking a lock is a short tactile minigame (find the sweet spot while the pick wears down). Pickpocketing is a quick timing game while the mark isn't looking. Failing alerts people.
- **How it works:** the view runs the minigame, then submits a result command with a seeded validity check: the sim decides success from skill and the minigame score, so determinism holds when replaying commands.
- **Plugs into:** L5, L7, `sim/player/looting.gd`, G3.
- **Edge cases:** the minigame pauses the sim clock.
- **Performance:** none.
- **Tests:** a submitted score gives the right outcome.
- **Done when:** lockpicking is tense.

### B17. Elections for sheriff and mayor  [fits milestone 6]
- **Status:** NEW. **Size:** M. **Depends on:** C7, F1.
- **Player sees:** every 4 weeks, towns vote for mayor (and for sheriff in big towns). Candidates speak in the square. You can run, campaign or rig it with bribes (T2).
- **How it works:** candidates are the 2 to 3 adults with the highest average opinion from others (P3 relations). Each adult votes for the one they like most (and the player if running, by opinion of the player). Bribed votes count. The winner becomes `town.mayor`.
- **Plugs into:** C7, P3, F1, T2.
- **Edge cases:** a tie goes to the older candidate.
- **Performance:** once every 4 weeks.
- **Tests:** the election is deterministic; the player can win with high opinion.
- **Done when:** you become mayor of Reedbank.

### B19. Festivals with contests  [fits milestone 6]
- **Status:** NEW. **Size:** M. **Depends on:** P5 (weekly rhythm), E7 (seasons).
- **Player sees:** a harvest fair in autumn, a winter feast and a spring dance. Townsfolk gather, there's music and stalls, and there are contests (a shooting match, a pie contest, a foot race) you can enter for prizes.
- **How it works:** a festival day on a fixed season day per town. Residents get "festival" goals at the green (no work). Contests:
  - a shooting match: hit targets, scored by skill and the result;
  - a race: the path time;
  - pies: bake (E5) and quality.

  Prizes come from the treasury (conserved).
- **Plugs into:** P5, E5, G3, `sim/entities/residents.gd`, `view/` decorations.
- **Edge cases:** bad weather moves it to the next day.
- **Performance:** many residents in one place; check the pathing load.
- **Tests:** the festival happens on its day; the prize moves coins.
- **Done when:** you win the harvest shooting match.

### B20. Growing your homestead into a hamlet  [fits milestone 13]
- **Status:** NEW. It extends G5. **Size:** L.
- **Player sees:** your homestead attracts settlers once you have spare houses and food. It becomes a small hamlet with its own name.
- **How it works:** when the player's homestead has a free house and food of 20 or more, daily `society.migrate` may move a family from a crowded town there. It becomes a mini-settlement (`s.settlements` entry) once it has 3 households. Today a settlement has a warehouse, market and office, so check what's required and start minimal.
- **Plugs into:** G5, `sim/factions/society.gd`, `sim/settlement/`, X4.
- **Edge cases:** the many three-town assumptions (see X4).
- **Performance:** see X4.
- **Tests:** settlers arrive; the settlement is created.
- **Done when:** a dot with your hamlet's name appears on the map.

### B22. Disguises  [fits milestone 8]
- **Status:** NEW. **Size:** S–M. **Depends on:** L1 (recognition by outfit).
- **Player sees:** wear a deputy's coat and hat to walk into the office unchallenged. People who know the real deputy see through it.
- **How it works:** outfits carry a role (a sheriff's outfit pieces already exist through `Sheriff.dress`). Wearing 3 or more pieces of a role's outfit gives you that role's access for people who don't know you (opinion entry absent) or the owner. Close friends of the real owner see through it at 4 cells.
- **Plugs into:** `sim/entities/outfits.gd`, `sim/law/sheriff.gd` (`dress`), L1, C3.
- **Edge cases:** wearing a uniform taken from a body is theft.
- **Performance:** none.
- **Tests:** disguised access works; a friend sees through it.
- **Done when:** you bluff your way past the jail desk.

### B23. Investigating a crime with clues  [fits milestone 8]
- **Status:** NEW. **Size:** L. **Depends on:** L1, F2, A6.
- **Player sees:** someone else's crime happens in the world, a theft or a murder. As deputy (or for a reward) you investigate: footprints, witnesses who saw "someone in a red vest", who was out of their house that night. Then you accuse the guilty one in front of the sheriff.
- **How it works:**
  - The storyteller (B1) creates an NPC crime with a hidden culprit: an NPC commits theft or murder in the sim, with real F2 witnesses and A6 tracks.
  - Clues are facts in the sim: witness descriptions (outfit pieces), the culprit's tracks, and alibis (residents' goals logged at that time).
  - Accusing the right person gives a reward and a trial (L4); the wrong one gives a bad memory and a "false accusation".
- **Plugs into:** B1, L1, F2, A6, L4, T1.
- **Edge cases:** the culprit flees if they learn they're suspected (through gossip).
- **Performance:** an alibi log is capped (last 2 days).
- **Tests:** the clues point to the culprit; an accusation resolves.
- **Done when:** you solve a murder by following a muddy footprint.

### B24. Using daily routines  [fits milestone 7]
- **Status:** PARTLY BUILT. Residents already follow schedules (work hours, the `MORNING` and `EVENING` windows, sleep). **Size:** S.
- **Player sees:** you learn when people are where. The journal notes it ("The blacksmith leaves the forge at 18:00", "The sheriff sleeps at the desk around 02:00"), which you can use to steal, sneak or meet someone.
- **How it works:** after you've seen a person at the same place and hour on 2 days, add a note to `player_status.routines[id]`; G4 shows it.
- **Plugs into:** G4, `sim/entities/residents.gd`.
- **Edge cases:** a cap of 3 notes per person.
- **Performance:** check only people near the player, every hour.
- **Tests:** a note appears after 2 sightings.
- **Done when:** you plan a theft by the clock.

### B25. Rival factions  [fits milestone 11]
- **Status:** PARTLY BUILT. `s.factions` has one council or compact per town (`society.initialize`). **Size:** L.
- **Player sees:** groups with their own aims: the rail company buying up land, the ranchers who want open range, the outlaws. Helping one angers another, and the towns change depending on who wins.
- **How it works:** each faction has members, goals (own N plots, control a town), standing with the player (F3-like), and offers favours (T3). Its goals push the sim: land purchases, pressure on the mayor's laws (C7), and C8 raids.
- **Plugs into:** `sim/factions/society.gd`, C7, C8, T3, F3.
- **Edge cases:** keep it to 2 to 3 factions.
- **Performance:** daily.
- **Tests:** a faction's goal progresses; player help shifts its standing.
- **Done when:** you have to choose sides.

### B26. Inner thoughts  [fits milestone 12]
- **Status:** NEW. **Size:** M. **Depends on:** G3 (skills), F1.
- **Player sees:** short thoughts from your character pop up: "His hands are shaking. He's lying about the stock." or "You're too tired to aim well." Better skills give sharper hints.
- **How it works:** a rule table `{condition, text, skill gate}` is checked on interactions and every 300 ticks. Examples: a keeper with low opinion and a high trade skill gives the lie hint; tired gives the aim hint.
- **Plugs into:** G3, F1, `view/ui/game_hud.gd`.
- **Edge cases:** at most one thought a minute.
- **Performance:** cheap checks.
- **Tests:** a condition triggers its thought.
- **Done when:** your character feels like someone.

### B28. Food that spoils  [fits milestone 9]
- **Status:** NEW. **Size:** S.
- **Player sees:** fresh food spoils in a few days; bread lasts longer, salted meat lasts weeks. Pantries need managing, and winter stores need salt.
- **How it works:**
  - Inventories count items, not ages. Use batches: `food` becomes `food_fresh` with spoilage tracked per inventory as `{item: [{qty, made_tick}]}`. Alternatively, a simpler rule: each day, 5% of fresh food in each inventory spoils (rounded down, at least 1 if 5 or more). That one is easier and still conserving if the spoiled food is recorded as destroyed.
  - Salt (a new item) turns 1 fresh into 1 salted food.
- **Plugs into:** `sim/inventory/inventory_store.gd`, `sim/diagnostics/invariants.gd` (count spoilage), `sim/entities/family_economy.gd`.
- **Edge cases:** the invariant for goods must accept recorded spoilage.
- **Performance:** a daily pass over inventories that hold food.
- **Tests:** spoilage rates; the invariant passes.
- **Done when:** you buy salt before winter.

### B29. Cold and shelter  [fits milestone 5]
- **Status:** PARTLY BUILT. A `cold` condition exists in `needs.gd` (snow, night, outdoors). **Size:** S.
- **Player sees:** cold has teeth. In winter nights outside without a coat or fire you get colder, shiver, move slower, and can freeze. A coat, a fire (B10) or a roof saves you.
- **How it works:** a `body_heat` number of 0 to 100 falls when cold is 2 or more and you're not by a fire or indoors. A coat outfit piece halves the loss. Below 30, walking is 10% slower; at 0, health damage.
- **Plugs into:** `sim/entities/needs.gd`, `sim/entities/outfits.gd`, `sim/movement/pace.gd`, B10.
- **Edge cases:** NPCs go indoors, as they already mostly do.
- **Performance:** none.
- **Tests:** a winter night outside lowers heat; a fire restores it.
- **Done when:** you plan winter trips around shelters.

### B31. A named rival drifter  [fits milestone 11]
- **Status:** NEW. **Size:** M. **Depends on:** L2, B6.
- **Player sees:** another drifter with a name and a reputation competes with you for bounties and favours, turns up where you are, and grows more famous (or infamous) over time. Friend or enemy, it's up to you.
- **How it works:** one special wanderer (B6) with player-like goals: takes bounties (L2), does requests (T3), gains reputation (F3). Their actions write F2 events, so gossip talks about them.
- **Plugs into:** B6, L2, T3, F3, P2.
- **Edge cases:** if they die, a new rival appears much later.
- **Performance:** one detailed resident near the player, coarse otherwise.
- **Tests:** the rival takes a bounty before you on a known seed.
- **Done when:** you hear "The Kid got there first".

### B32. Scars become traits  [fits milestone 7]
- **Status:** NEW. **Size:** S. **Depends on:** B4.
- **Player sees:** survive something terrible and it marks you. A gunshot scar gives "Hard to scare" (less stress in gunfights); a burned hand gives "Fears fire"; long jail time gives "Jailbird" (outlaws trust you more).
- **How it works:** `player_status.traits = [ids]`, gained on events (F2) with fixed rules. Each trait is a small modifier read by the relevant system.
- **Plugs into:** F2, `sim/entities/needs.gd` (stress), the systems for each trait.
- **Edge cases:** an heir doesn't inherit them.
- **Performance:** none.
- **Tests:** an event gives its trait; the modifier applies.
- **Done when:** your character's history shows in how they play.

### B33. Family ties shape choices  [fits milestone 10]
- **Status:** NEW. **Size:** M. **Depends on:** T6, L2.
- **Player sees:** your relatives are part of the world. Your brother turns outlaw and has a bounty. Your wife's family asks for help. Choices hurt both ways.
- **How it works:** with T6, link the in-laws (`relations`), and let B1 create family events (a relative becomes an outlaw, falls ill (B8), or is in debt (E4)).
- **Plugs into:** T6, B1, L2, B8, E4.
- **Edge cases:** none.
- **Performance:** none.
- **Tests:** a family event sets up the right state.
- **Done when:** you hesitate before turning in your own brother-in-law.

### B34. Earning your place as a stranger  [fits milestone 6]
- **Status:** NEW. **Size:** S. **Depends on:** F3.
- **Player sees:** at first nobody trusts the stranger: prices are higher, some doors are shut, and people keep their distance. As you work and help, you become a familiar face.
- **How it works:** a "Stranger" band in F3 (-25 to 25, plus no completed favours in town) gives prices +10% and no hiring (T4) or renting (T5). Completing 2 favours (T3) or living there 7 days gives "Known".
- **Plugs into:** F3, T3, T4, T5, `sim/economy/stall_service.gd`.
- **Edge cases:** G1 starts other than the drifter begin as Known in their town.
- **Performance:** none.
- **Tests:** the stranger penalty applies and lifts.
- **Done when:** the first week feels like arriving somewhere new.

### B35. Shortage crises  [fits milestone 6]
- **Status:** PARTLY BUILT. `society.update` already switches a town to "Food first" when the warehouse is low. **Size:** M. **Depends on:** C6, C7.
- **Player sees:** a hard winter with too little firewood or food. The mayor rations, prices spike, people argue about who gets what, and you can help (bring supplies) or profit.
- **How it works:** when the warehouse food or logs are below 20% of `TARGET` in winter, a crisis is set: `town.crisis = {kind, since}`. Effects: rationing (households can buy at most 2 a day), C6 loyalty −, T3 requests for the scarce good at 2× reward, and B7 strain +.
- **Plugs into:** `sim/factions/society.gd` (`update`, `policy`), C6, C7, T3, `sim/economy/market.gd`.
- **Edge cases:** it ends when stock is back above 40%.
- **Performance:** daily.
- **Tests:** low stock in winter starts a crisis, and refilling ends it.
- **Done when:** you haul firewood to a freezing town and become a hero.

---

## 6. PERFORMANCE: THE GAME MUST STAY SMOOTH WITH HIGH FPS

This answers the line you added: "After all of this make sure that the game is still run smoothly with high fps." It applies to every milestone, and it has a final check after everything is built.

### 6.1 Where things stand today (measured during the performance work, Apple M4, 1280×720 window)

| Zoom | FPS | p95 frame time |
|---|---|---|
| 2.0, normal play | about 76 | 19 ms |
| 1.0 | about 52 | 22 ms |
| 0.5 | about 45 | 28 ms |
| Map open | about 55 or more | 28 ms |

The drawn medieval map is painted once when you press M, so the map open is now cheap.

On the simulation side, the worst tick in a real three-town world is about 12 ms and the 99th percentile about 3.7 ms. The sim clock spends at most 10 ms per frame on simulation and clamps any backlog, so a slow tick can't snowball.

The tools to measure with:
- `tests/benchmark/view_benchmark.gd`, a windowed run at several zooms and with the map. `SOLO_BENCH_LABEL=<name>` writes `docs/validation/view_benchmark_<name>.json` for before and after comparisons.
- `full_game_benchmark.gd`, the real world headless.
- `simulation_benchmark.gd`, at 20, 100 and 300 people.
- `draw_breakdown.gd`, the render cost per layer.
- `animation_frame_benchmark.gd`.
- The in-game **F4 perf tab**, the ms per frame for each system.

### 6.2 Budgets every feature must keep

| What | Budget |
|---|---|
| Normal play (zoom 2) | at least 60 FPS; p95 frame time of 20 ms or less |
| Map open | at least 60 FPS |
| Night, rain, a big fight on screen | at least 50 FPS |
| Sim tick | 4 ms or less on average; 15 ms or less at worst (real three-town world) |
| Sim with 300 people (`simulation_benchmark.gd`) | no worse than 1.5× today's numbers |
| Save | 100 ms or less; autosave must not cause a visible hitch |
| Memory | no list grows without a cap |

If a feature breaks a budget, it isn't done.

### 6.3 Rules that keep it fast (put them in each plan)

1. **No per-tick loops over all entities.** About 6,400 entities exist (mostly trees). Use the derived lookups (by kind, buildings, trees by cell, in `DerivedCache`), or loop only over the small set involved (bodies, fires, people near the player).
2. **Spread slow work over time.** Daily work runs in `households.daily()` or on `tick % 14400 == offset`, with a **different offset per town** so three towns never do their daily work on the same tick. Hourly work uses `% 600`.
3. **Cap every list.** Examples: events 200, memories 16, rumours 8, tracks 400, decals 64, fires 60 burning cells, speech 30 lines (already there), trades 64 (already there).
4. **Use the fidelity levels.** People far from the player run coarse or aggregate (`fidelity.gd`); new actors (animals, gang members, wanderers, carts) do too.
5. **Pathfinding is the most expensive thing in the sim.** Reuse `AStarGrid2D` (`nav_grid.gd`). Give new movers short paths and don't re-path every tick. Rebuilding the grid (bridges, fires) is fine occasionally, never often.
6. **View effects are pooled and culled.** Lights (V1) at most about 64 on screen; particles from a fixed pool near the camera; sounds through about 8 pooled players. Nothing is created per frame.
7. **Draw only what changes.** UI windows redraw on change, not every frame. The map is painted once per M press. Static art is cached.
8. **Compute on demand, cache when repeated.** For example, carry weight (C1) is computed when the inventory changes, and opinion (F1) when someone talks to you.

### 6.4 Checks for each feature (part of every "Done when")
- Before starting: run `view_benchmark.gd` and `full_game_benchmark.gd` with `SOLO_BENCH_LABEL=before_<feature>`.
- After building: run them again with `after_<feature>`, and compare. Anything 10% or more slower must be explained and fixed or accepted by the owner.
- For features with a stress case (a big fight C8, a big fire W4, night lights V1, rain W1, many animals P9), run a benchmark set up with that stress case.

### 6.5 The final performance pass (after all chosen features are built)
1. Run the whole benchmark set: view at all zooms plus the map, the full game, the simulation at 20, 100 and 300 people, at noon, at night and in rain, with a big gunfight and a fire.
2. Compare with the baselines in 9.1 and the budgets in 9.2.
3. For anything over budget, use the F4 perf tab and `draw_breakdown.gd` to find the cost, fix it, and run again.
4. Play for 30 minutes at normal speed, plus 10 minutes at sleep fast-forward, and look for hitches.
5. Record the final numbers in `docs/validation/` and the decision log.

---

---

## 7. WHERE THE BUILT IDEAS' BRIEFS WENT

The briefs for ideas already built are not repeated here. The code and `docs/design/DECISIONS.md` describe them now. Their original text is in the old Project_Solo_Ideas.txt, in the old plan files folder:

F1, F2, F3, F4, F5, C1, C2, C3, C4, P1, P2, T1, T2, T3, L1, L3, L8, G2, G4, W8, X3.
