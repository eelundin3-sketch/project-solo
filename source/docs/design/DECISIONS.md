# Design and implementation decisions

## D001 — Pin Godot 4.6 stable, standard edition

Reason: a stable Godot 4 release matching the design pack's API baseline. No engine
was found on PATH or in standard application locations; the official universal
macOS build was downloaded into `/private/tmp` for validation. Actual build:
`4.6.stable.official.89cea1439`.
Alternative: another stable 4.x release. Reversible with an explicit pin update
and rerun of import/tests. Validation: version output and passing smoke pin check.

## D002 — Compatibility renderer and presentation-only scene

Reason: simple desktop 2D needs no advanced rendering. Main composes a drawn grid,
Camera2D and CanvasLayer HUD. Ground is an original procedural drawing, not world
generation. No persistent simulation state exists in these Nodes.
Alternative: imported textures/TileMapLayer, deferred until a world model exists.
Reversibility: views can be replaced independently. Validation: scene smoke test
and native graphical startup; visual UI inspection unavailable due to tool timeout.

## D003 — Dependency-free SceneTree smoke runner

Reason: exercise actual Godot scene loading and return reliable CI exit status
without frameworks/plugins. Seeded pure-data samples live only in tests.
Alternative: third-party test framework, unnecessary for M0. Reversible later.
Validation: headless import and smoke command both exited 0. Initial sandboxed
import reported blocked user/cache writes; rerun with normal directory access
completed cleanly. See README for exact commands.

## D004 — Scope and camera controls

Reason: implement the hand-off's first bounded task, M0. Reserve future folders
with `.gitkeep` instead of speculative interfaces. Physical WASD moves an observer
camera at a zoom-adjusted rate; wheel zoom is bounded; pan stays near the grid.
Alternative: configurable InputMap/player controls, deferred until gameplay.
Reversibility: camera input can change without simulation migrations.
Validation: pan distance, wheel handling and both zoom bounds pass automated tests.
M1 and later work remain pending; no automatic commit or release tag was made.

## D005 — Full-roadmap implementation authorized

The follow-up request authorizes continuing beyond M0. Work proceeds sequentially,
with executable gates at each integration seam. The initial implementation uses
plain serializable dictionaries, integer cells/quantities, and RefCounted services.
Simulation owns the snapshot; services receive it explicitly through public entry
points. Render Nodes hold only selection, camera and UI state. This favors clear
save/replay contracts over a framework or premature packed-array optimization.
Canonical snapshots include commands, events, RNG streams and content version.

## D006 — Physical custody, transactions and inspectable work

InventoryStore owns stack changes and capacity promises. Gathering jobs lease
exclusive targets and warehouse capacity; interrupted carriers keep their goods.
Removed workers become recoverable stashes. Sawmill inputs travel in the sawyer's
inventory; outputs travel back the same way. Builders carry planks to a site and
consume them only at completion. Recipes consume/produce at one validated commit
point. The accounting ledger records explicit initial stocks, growth, consumption,
recipe conversion and incident losses. Markets move the same stacks and integer
currency. No rendered object owns these values.

## D007 — Regional simulation and fidelity

The first complete scenario has two settlements and a bounded 384×256-cell region.
Chunks are 64×64 and generated on demand by seed/version; rendering culls to the
camera bounds and does not spawn a Node for each offscreen actor. Residents keep
one identity and inventory across detailed (2-tick actions), coarse (10-tick
batches), and aggregate (100-tick batches) simulation. Batched travel and labour
advance arithmetically across transaction boundaries rather than executing each
intermediate cell. Town population/stocks/resource summaries are derived views,
not independent owners of goods. Visible resources plus hidden residuals equal
the exact source records. All initial citizens remain named; anonymous population
expansion at tens of thousands of residents is not part of this prototype.

Caravans own cargo throughout a scheduled journey. A blocked road reschedules the
same commitment; a matching event ID makes arrivals once-only. New departures
respect treaties and risk. Distant movement is a commitment, not a hidden sprite.

## D008 — Society and non-graphic danger

Households group named residents, sparse relationships cap at 32 edges, memories
at 16 entries. Selling supplies creates a memory and trust change. Shortages change
work priorities; excess population can migrate to spare housing. Migration removes
a worker from local assignment until arrival. Guard assignment reduces incident
risk. Conflict uses one resolver and an actor's current fidelity, records losses
through InventoryStore, and never resolves the same incident twice. Injury stops
at one health in this initial non-lethal conflict model.

## D009 — Persistence, external content and reproducible checks

Save envelope v2 contains a checksum, pinned engine version and explicit state.
Temporary-write/readback/backup/rename prevents replacing a valid save with an
invalid write. Loading validates schema, quantities and invariants before swapping
state, recovers a backup on corruption, and migrates v1 metadata. This migration
supports this project's v1 snapshot schema; it is not a generic importer.

Recipe JSON is data-only, capacity-bounded, with namespaced mod IDs. A loaded
recipe is embedded in the authoritative snapshot. External recipe data is validated and embedded in the queued command at
submission, so command replay does not reread a mutable external file. Active
batches retain a frozen recipe until commit or cancellation. Controls live in a separate user settings file and do not enter the
simulation hash. No external gameplay framework/plugin was introduced.

## D010 — Build and performance scope

Official 4.6 export templates produce Windows x86_64, Linux x86_64, and universal
macOS debug/release artifacts. Local macOS binaries are launch-tested. Windows and
Linux exports require testing on those operating systems before distribution.
Builds are unsigned and not notarized. macOS export requires ETC2/ASTC import enabled
and its template installed in Godot's standard export-template directory.

Performance is measured on the actual Apple M4 host, not the hypothetical Windows
reference in the design pack. Simulation budget is 100 ms/tick at 10 Hz. Results
for 20/100/300 residents and a five-minute graphical run are recorded separately.
No language change or multithreading is justified by the current measurements.

## D011 — Walkable building footprints and unified frontier map art

The graphics request now includes functional building interiors. Building records
will own integer-cell footprints and south-facing door cells; a separate wall-cell
index participates in WorldDB.walkable and navigation revisions. Views draw floors,
furnishings and cutaway walls from those records. Construction validates the whole
footprint and adds walls only at completion. Existing saves receive missing layout
metadata on restore, preserving inventories/IDs while clearing new wall collisions.
Art remains original code-native ink outlines and a warm earth palette, matching
the character renderer without external image assets or plugins.

## D012 — Readable work cycles, forest abundance and sound

Animation follows explicit simulation actions: approach → work (anticipation,
impact, recovery) → pickup → loaded travel → drop-off. Gathering gains timed pickup
and deposit phases before its existing atomic transfer points. Other inventory
changes create short presentation-only handling transitions. A view-owned animation
director interpolates positions, tracks facing and foot contacts, and emits bounded
sound cues; it never owns goods, jobs or random simulation state. Pause freezes
motion/cues, and load resets presentation history without replaying old sounds.

Forests gain unique, spaced trees outside village/road/footprint clearances and a
one-time, ledger-accounted upgrade for older saves. Wind is a coherent low-frequency
field with small per-tree offsets. Wood impacts, walking, sawing and handling use
original synthesized audio assets, distance attenuation and a bounded voice pool.

## D013 — Reference-led architecture and village plan

The visual redesign requires real navigable rooms, not painted internal dividers.
New buildings use larger kind-specific footprints and a persisted `interior_walls`
list; both navigation and rendering consume these cells. A two-cell internal
passage preserves access to every room. Initial homes and mills move apart and
construction prioritizes street-facing plots outside the storehouse square.
This changes initial layouts and travel distances, not ownership or economic rules.
Original reference-inspired art remains code/vector assets, with no copied source.

## D014 — Physical fixtures and observed handling

Sawmills and stores define blocked fixture cells plus a reachable operator/handling
stance in authoritative building data. Workers route to that stance for production,
collection and depositing; the view draws the machine/rack at the same fixture rect.
Fixtures share their building inventory, rather than introducing a second owner.
Inventory transfers publish a bounded 32-record deterministic observation ring with
monotonic serials. The view animates nearby worker/fixture transfers once, suppresses
historic events on load, and owns only interpolation. Machine rotation/feed follows
active staffed work, freezes on pause, and stops when work is interrupted.

## D015 — Contextual player controls and personal condition

The playable traveller uses WASD, I (inventory), F (contextual action), H (body and
treatment screen), mouse wheel and trackpad pinch zoom, with Shift sprint. Body-part
injuries, treatment timers, bandage condition and stamina are saved simulation data.
Inventory items remain the authoritative goods owner; the hand-held stack is a
selected subset, never a duplicate. Sprint stamina is spent per accepted move and
regenerates after release. Views submit commands and only display simulation state.

## D016 — Metric tiles, staged construction and minimal play HUD

One authoritative grid cell is defined as one metre (24 rendered pixels at default
zoom); buildings and terrain use those integer cells as their measurements. Terrain,
flooring and walls render as individually outlined cell blocks. Construction now
stages its plank deliveries in the site's central fixture, then commits visible floor,
wall, doorway and roof tiles in order. Each completed wall tile immediately updates
the collision index; the doorway stays clear while work is underway. Tile progress,
used materials and wall cells are serialized with the construction site, allowing an
exact resume after loading. Ten work points place each tile, while the site obtains
its total material cost once across staged deliveries.

The play HUD keeps only the clock, compact stocks, stamina and pause/1×/2×/3× controls
in the upper-left corner. Observer tools are opt-in. Actor ground shadows and the
selection circle were removed; selection uses corner brackets. Walking poses now
alternate knee/foot lift and arm swing with torso sway and body bounce. These are
presentation changes except for saved construction progress and its wall collision.

## D017 — Seeded weather and presentation

Weather is a saved simulation record updated in six-hour blocks using its own RNG
streams; snow accumulation advances in fixed simulation intervals. Presentation
interpolates transitions over 300 ticks and draws bounded precipitation, fog and
wind-driven vegetation. Weather does not currently alter movement or production.
Legacy snapshots receive an initial clear weather record on restoration.
This is an original implementation informed by RimWorld-Go's separation of weather
simulation, presentation motion, and per-frame environment rendering. No reference
source or asset was copied.

## D018 — Local combat encounter

Local encounters use a saved simulation-owned fighter and projectile store, separate
from abstract caravan incidents. Nearby residents interrupt their jobs and become
defenders; raiders and defenders select opposing targets, route to attack positions,
and use timed ranged or melee attacks. Projectiles advance cell by cell and walls
stop them. Damage and incapacitation are authoritative simulation results. The view
projects aiming, swings, hit reactions, projectiles and impact effects from those
records. A player-invoked observer demonstration creates an encounter; autonomous
raids, player attacks, medical recovery for NPCs and broader combat AI are not yet
implemented. This is original GDScript and art informed by the reference project's
combat/engage and creature/combat organization; no reference assets were reused.

## D019 — Directional character facing

Character headings are presentation state derived from actual movement or a combat
target. The player can hold the right mouse button to face the cursor at any angle;
this overrides movement-facing until release. The drawn figure uses front, side and
back projection changes while remaining upright. Facing has no effect on simulated
movement, inventory or combat. NPC direction eases between headings; player cursor
facing follows directly. Losing application focus clears the held mouse state.

## D020 — Volumetric character rigs (superseded by directional vector characters)

Visible characters are presented by original procedural 3D mesh rigs in transparent
Godot SubViewports projected into the existing 2D world. Heading rotates the actual
model around its vertical axis; arms and legs animate from the presentation director's
existing work, locomotion and combat states. Viewports are created only for actors
near the camera and discarded when they leave view. The simulation still owns all
positions, inventory and decisions. This adds GPU rendering cost per visible actor;
the 2D world and its simulation contracts are unchanged.

## D021 — Sprint pace and running gait

Healthy walking advances one grid cell every two simulation ticks; sprinting uses
one per tick while stamina remains. Only successful sprint moves spend stamina;
injured or exhausted players use the walking cadence or slower. Rendering retains
the running pose between movement ticks and uses articulated knees, arm drive,
forward lean and a small lift cycle. These are presentation projections of accepted
movement and do not change collision or the inventory model.

## D022 — Physical construction work cycle

Construction retains the existing fixed plank cost and central site inventory. The
builder transfers a real plank into their own inventory, routes to a reachable cell
beside the next build tile, works there, then returns the remaining plank to the
site before repeating. A plank is consumed from the worker's inventory at the same
proportional cost thresholds as before; a partly used plank is returned for reuse.
The current phase, path, material custody and tile progress live in saved simulation
state. Navigation revisions trigger replanning and needs or combat interrupt work
without fabricating goods. This intentionally lengthens construction time.

## D023 — Ink-styled 3D characters (superseded by directional vector characters)

The existing rotating 3D rigs use toon diffuse lighting and an original dark
outline pass, with front-facing eye, shirt, vest, lapel and hat details in the
frontier palette. These additions are view-only and share the existing animation
and simulation contracts. The outline adds a render pass to visible meshes, so
large-crowd GPU performance should be profiled on target platforms.

## D024 — Ground-position depth sorting

Walls retain their one-cell collision footprint but are drawn taller. Individual
wall sections, trees, rocks, fixtures, furnishings, dropped items, carts and 3D
characters are view nodes sorted by their ground-contact Y coordinate. This allows
foreground objects to cover actors behind them as either moves. Floors and paths
remain background drawings. The authoritative simulation and navigation are
unchanged. Nodes are culled outside the camera view; scenery artwork such as the
decorative porch trim remains part of its background layer.

## D025 — Clearer cutaway interiors

Connected wall tiles use broad timber faces and light trim instead of repeated
horizontal bands. Their visible connections derive from adjacent authoritative
wall cells, including walls under construction; their collision and depth anchors
stay unchanged. Floor planks remain continuous across the 1 m grid, with subtler
shading and less decorative clutter. Furnishings stay in the depth-sorted layer.
This presentation uses original artwork informed by the supplied reference image.

## D026 — Greener terrain and clustered forest

Woodland outside the settlements uses a darker green ground and canopy palette,
blending into warm earth around the villages. Seeded groves add 100 harvestable
trees around Alder Hollow and 60 around Reedbank. They preserve road clearances,
building plots, active construction sites and existing entity positions. Version 2
saves receive the new stands once, with added timber recorded as created inventory.
The added trees are existing simulation entities, not a second decorative resource.

## D027 — Continuous walking presentation

Input queues the next walk command one simulation tick before its execution is due,
eliminating an extra idle tick. Character interpolation travels at the same rate as
the authoritative two-tick walking and one-tick sprint cadence. Collision and
stamina remain simulation-owned; the renderer does not predict through obstacles.

## D028 — Unarmed player actions

Holding the left mouse button displays a screen-space pointer and ready pose;
pressing it while the right button is held submits a directional punch. Space
submits a shove and P pauses. Actions record their direction and a timed impact in
the authoritative simulation. Punches damage an adjacent person, while shoves
displace them only into an unoccupied, walkable cell; both trigger a brief hit
reaction and interrupt active jobs safely. Camera and ready stance remain view
state. These basic actions do not constitute a complete social retaliation system.

### Stepped home footprint

Homes use a one-metre-cell stepped outline, shared by construction, collision,
and floor rendering. Existing completed homes migrate once on load; active
construction retains its saved stages and original outline until completion.
The bounding rectangle remains the conservative plot reservation. This keeps
navigation and save data authoritative while allowing the cutaway presentation.

The cutaway wall revision joins the inside corner of stepped homes with one
additional wall cell so the wall outline does not touch only at a point.
Completed homes receive that corner on load. In-progress construction follows
its recorded tile list. Cutaway surfaces stay within each wall's footprint and
retain the southern ground edge as their draw order anchor.

### Directional vector characters

The live character renderer uses original layered 2D drawing and projects
planar pose offsets according to a continuous heading. Front and back clothing,
facial features, and the order of the limbs change with direction. This supersedes
the 3D character presentation described above. The animation director still
reads simulation snapshots, and input, collisions, and combat remain authoritative.

### Larger building plans and roads as terrain

New lodges are 17 × 14 cells, storehouses 17 × 15, and workshops and markets
15 × 13. A cell still measures one metre. Construction uses the larger floor,
wall, door and roof plans. On load, completed buildings expand only where the
new footprint leaves neighboring plots clear. Existing work sites retain their
saved plans and reserved materials.

Roads and footpaths are feathered coverage in the terrain shader. Their sand
and gravel use the same ground texture and lighting, while collision and routes
continue to come from the simulation.

### Walls-first construction and visible tile work

New sites stock their actual central pile before starting, then build walls,
floors, doors and roofs in order. Each tile uses a pickup, transit, work and
return trip. Saved sites retain their serialized stage order and stockpile
position. The renderer reads the active tile and its work fraction, including
partial walls before their collision is committed. Completed buildings are
shown in cutaway so rooms remain visible.

### Furnished aisles, bulk workshops and market counters

Fixture and furniture rectangles are simulation records. The navigation index
blocks those same tiles, and the view draws furnishings at their recorded
locations. A workshop's saw and rack have separate approach cells and share the
same workshop inventory. Reserving a buffered recipe does not transfer those
inputs to a duplicate inventory. The hired worker delivers finished items by
walking to the stall or warehouse, then transferring actual stock.

Each open-air stall owns its inventory and coin account. Stalls draw opening
stock and cash from the town store and treasury. Retail purchases use the
stall and its category list. The underlying town market still owns regional
price history and order matching. Current saves keep all records. A one-time
stall and fixture upgrade adds the layout to supported older saves. Old saved
populations remain intact when the new-game default changes.


## 2026-11-16 — Rye, households, trades, weapons, needs, placement

- **Rye is integer growth ticks.** A plot stores `grown` out of 43,200 ticks; the six
  stages are derived thresholds and the art is a continuous function of the same
  value, so saves and replays stay exact and the crop never "pops" between sprites.
- **Grain is not food.** Farms produce `rye`; only the baker (or a household oven, at
  a worse ratio) produces `food`. This keeps the baker meaningful and food
  conservation exact. Farms keep any legacy `food` stock and gatherers still haul it.
- **Trades are derived, not enforced.** `Professions.demand` computes head-count per
  trade from nearby trees, ore, fields, population, danger and the workshops that
  exist. Farmers and a sheriff appear through the food and safety terms, so a tiny
  hamlet with no fields would not get a farmer. Gathering trades only take jobs on
  their own resource kind.
- **Pantry = the home's inventory.** Avoids a second ledger; the invariants and
  conservation checks cover household food automatically.
- **Garden clearing relocates trees** with `move_record` instead of deleting them so
  logs remain accounted for.
- **Placement is lazy-loaded.** `placement.gd` and `world_db.gd` depend on each other
  through `fixtures.gd`; `placement.gd` loads World/Navigation at call time to avoid a
  preload cycle.
- **Shotgun pellets are simulated** (7 per shot, 2 cells per tick, 9 damage each) in
  `sim/combat/shotgun.gd`; the view only draws `state.shotgun`. Damage is non-lethal
  to residents like the existing combat (health floors at zero).
- **Player needs run slower than residents'** (about one meal and two drinks a day)
  so a human player is not starving within minutes.
- **Research basis.** The indicator design follows Project Zomboid's moodles as
  described by community guides (icons that appear only when relevant, four severity
  levels, thirst/hunger/tired/pain/stress/unhappy families). Exact in-game
  percentages were not verified. Market dressing follows general period references
  (paved square, central well, awnings, goods around stalls); no precise frontier
  stall-spacing source was found.
- **Not done:** extra craftsmen (carpenter etc.) exist as a named trade with no
  production chain; objects facing "up" reuse the "down" art; the Windows/Linux
  exports were not rebuilt.


## 2026-11-16 — Character proportions and drawn contours

The existing 2D vector puppet remains the presentation model. This redesign uses
29 px hip height, 49 px chest height and 60.5 px head height, with the existing world
scale and foot anchor. The longer leg proportion and open resting arm pose make
clothing and limbs readable without widening the character's collision footprint.
The eight facing directions and existing pose blending remain in place.

Cloth is drawn from two convex, rounded bone panels; their geometric union supplies
one exterior ink outline. This avoids self-intersecting sleeve polygons when an
arm folds back on itself or is foreshortened. Shading is flat and restrained rather
than circular specular highlights. All artwork is original code-native vector art;
no external assets, plugins or simulation/save contracts were added.

The health diagram already derives its regions from the figure's joints. Tests
now verify that the revised proportions fit the panel and its hands and feet
remain individually selectable. World movement, inventory and collision stay in
the authoritative simulation.


### Character follow-up: neck and sprint recovery — 2026-11-16

The head now sits 2.5 canvas pixels lower and the exposed neck is shortened; the
health diagram's neck selection follows the new position. During sprint swing,
the heel first travels 8 pixels farther behind toe-off, then folds up and recovers
forward. Two cubic curves preserve the planted-foot horizontal velocity at
lift-off and landing. The previous extra 10% reach at landing was removed so the
cycle wraps continuously. Walking speed, stamina and simulation movement are unchanged.

## 2026-11-19 — Carrying weight, background saves, signpost distances

**Item weights live in code for now.** `sim/player/encumbrance.gd` holds a table of
weights in tenths (integer maths; anything unlisted, including clothing, weighs
0.5). `content/items/core.json` lists only eight items and not the shotgun,
shells or clothing, so a data-file version waits for the move of all tuning
tables into `content/`. The load is computed from the inventory when needed,
never stored. Heavy, overloaded and crushing loads lengthen steps by 10, 30 and
60% through `Pace.delay(..., slower)`. With `slower = 0` that function gives
exactly the old result, so no existing route or test changes.

**Saves are written on a background thread.** A save of the real world costs about
340 ms: a checksum, the write, then a full verify (re-read, checksum again,
invariants, schema). Only the deep copy of the state (`sim.snapshot()`, about
12 ms) has to run on the main thread. `SaveManager.save_snapshot(data, path)`
does the rest on that private copy, so `app/world_controller.gd` runs it on a
`Thread` (one at a time). A load first waits for any save still running.
Autosaves go to the older of `autosave_a.save` and `autosave_b.save` at 06:00
each in-game day. Each save gets a small `.info` JSON file (day, time, town,
when written) so the title screen can offer Continue without verifying a whole
world. Named manual slots wait for a pause menu.

**Signposts measure their roads once.** `RoadPlanner.ensure_ways` routes from each
signpost to every town's gate (`town_gate`, which auto-travel now shares) on the
travel grid. It stores the distance in paces and the heading in thousandths on
the signpost entity. It runs at the end of `start_game`, and in `restore` for
older saves (about 28 ms once). Signposts that already have `ways` are skipped,
so it is stable across save and load.

## 2026-11-19: The rifle is the main gun; shots are heard; silent takedowns

**Rifle as the main gun.** At the owner's request, the player starts with a rifle
and ten cartridges, and the office racks hold rifles. The rifle fires one
accurate bullet to 26 cells at 2.6 times a pellet's force. It is slower and
louder than the shotgun. The gun code became a weapon table
(`Shotgun.WEAPONS`, `kind()`, `spec()`), so the shotgun keeps working for anyone
who has one. The state key stays `s.shotgun`, now with a `kind` field, so old
saves load unchanged. Each projectile carries its own strength and speed.

**Shots are heard, not seen.** A rifle carries 60 cells and a shotgun 45.
`Gunfire.town_in_earshot` decides whether a town reacts: the shot must be near
enough to the town, or one of its sheriffs must be within earshot. Out in the
wilds, beyond anyone's hearing, nothing happens. This replaces "anything
within 70 cells of a storehouse". People who hear a shot but can't see it say
so. Only those who see it are witnesses (chronicle and witness reports).

**Silent takedowns.** `sim/combat/takedown.gd`: crouched, adjacent and not seen
coming (the target isn't walking toward you and isn't already alert), you can
kill or knock out without a sound. Such crimes call
`Law.crime(..., silent = true)`, and then a sheriff counts as a witness only
with a clear line of sight. Normally any sheriff within 24 cells counts.

## 2026-11-20: Milestone 5, night, weather and seasons

**Light is simulation data.** Street lamps are entities (`street_lamp`) placed at
fixed spacing beside every town street and lane, with no randomness. They are
added at the end of `start_game`, and in `restore` for older saves. They burn
19:30-05:30 on a timer (no lamplighter yet). `Light.level(s, cell)` gives 0-100
from daylight, lamps within 5 cells and the player's lantern, so milestone 7's
stealth reads it from the sim. The lantern is an ordinary item, lit while held
in hand, so it needs no new command. `Needs.is_night` is unchanged, so sleep and
trespass behave as before; lamps use their own window.

**One darkness pass for the night.** The view draws night as one shader
rectangle with up to 64 light pools (lamps, lit windows of homes with someone
awake, lanterns), nearest the middle of the view first. It sits under the
speech bubbles, which stay readable. The day/night `CanvasModulate` keeps only
a cool tint, so night is not darkened twice. No `PointLight2D` nodes, because
each one costs.

**Weather per town; the top-level record is the player's.** `s.weather.regions[town]`
holds kind, wind, snow, mud and dry days per town, rolled on
`weather:kind:<id>` from a climate table (Reedbank wet, Dustvale dry).
`s.weather.kind/previous/since/wind/snow` mirrors the player's town at each
roll and when the player walks into another town's weather, so every old
reader works unchanged. A tile belongs to the nearest town (`Region.of`, now
the one shared lookup; `Gunfire.town_of` uses it). A world without towns keeps
the old single roll. Old saves start each town with the weather they had.

**Drought and seasons work through growth, not new stock.** Dry days slow
crops (half speed from 5, none from 9) and cut the yield per cell (never below
1). Summer grows 20% faster and winter not at all. The first frost turns every
growing plot fallow (the crop is lost). The autumn harvest leaves a field bare,
and spring sows it again. Farmers switch to wood and ore work for the winter
(`seasonal: "Farmer"`) and go back to farming in spring. A late-autumn-to-spring
soak shows at worst 4% of people near starving.

**Whole families move.** After a harvest at half or less, a farming household
with an empty pantry may move (25% a day each, never the town's last farmer)
to the town that most wants farmers and has room. Room is a free house, or
else beds in the lodge. The household keeps its key, so purse and surname move
with it. This also fixed coins being erased when a `migrant:` household broke
up: `FamilyEconomy.ensure` now finds that household's town.

**Fog and mud.** Fog cuts sight ranges by 40% where it lies: witnesses, fear,
seeing a shot, and sheriffs spotting a wanted player. Rain makes road mud (5 an
hour, drying 2 an hour); above 50 it adds 15% to each step on a road
(`Pace.delay`).

**Prices still follow stock.** The trend arrow compares today's quote with a
daily snapshot (`markets[town].trend`). Prices the player has seen in a town
(`player_status.known_prices`, refreshed hourly while there) give a "better in
<town>" hint when 3 coins or more better, greyed after 3 days.

**Not done here, on purpose:** lanterns are not sold in stores yet (the player
starts with one); autumn trees only shift toward olive, because the tree art is
drawn dark green and needs new art for true orange leaves; there is no rain
sound (S3, milestone 13).

## 2026-11-20: Four parts of the day, 15-day seasons, a summer start

**[owner]** The day has four parts of six hours: morning 04-10, day 10-16,
evening 16-22, night 22-04. Seasons are 15 days. A new game opens on the first
day of summer, at 07:00 (the owner chose 07:00 over midnight or 10:00).

**One clock file.** `sim/world/day_clock.gd` holds the parts of the day, the
daylight curve (dawn 04-06, full light 06-20, dusk 20-22, dark at night) and
the sun's path (rises east at 05:00, highest at 13:00, sets west at 21:00).
The day tint (with a golden evening), the night darkness, sun shadows,
`Light.level`, street lamps (20:00-05:00), `Needs.is_night`, trespass night
and shop hours all read it, so they cannot drift apart again. Before this,
night meant four different things in four files.

**Each person keeps their own hours.** Bedtime between 21:00 and 22:00 and
waking time between 06:00 and 07:00, fixed from the person's id (no random
stream, nothing saved). A tired person (fatigue 20 or more) goes to bed after
their bedtime; the exhausted (75) still sleep any time. Shops are open
07:00-21:00, family shopping is at 07:30, and the morning garden chores are at
07:00-08:30, so people are up first. Greetings match the part of the day.

**Summer first without moving tick 0.** The season formula carries an offset
(`SEASON_OFFSET = 1`) instead of the game starting at a later tick, so tick 0
is still day 1 at midnight and day numbers stay right. `start_game` sets the
tick to 4,200 (07:00); `start_village` (bare test worlds) keeps tick 0. Saves
made before this keep their tick and so may find themselves in a different
season.

## 2026-11-21: Winter stores, smoke, the jail release, the bandit camp, and Dustvale as capital

**Winter stores [owner chose "store up in autumn"].** With 15-day winters the
towns starved (up to 70% near starving). The cause was rye: it piled up at the
farms because carriers took a farm's food first, the storehouse stopped taking
an item at 200, and the baker stopped at 300 bread. Now carriers take whichever
of food or rye the storehouse has less of, the storehouse lays up 800 of each,
and the baker bakes up to 800. The winter soak shows at worst 4%.

**Smoke goes outside [owner].** The bakery oven's and the forge's flue runs up
through the building's back wall to a stack outside, and smoke rises there
only while the stove works. View only.

**Shown out of jail [owner].** On release the sheriff comes into the cell and
takes the prisoner by the arm, returns their things at the desk, walks them to
the door and shoves them into the street. New phases `grab` and `show_out` in
`law.gd`.

**The bandit camp [owner; captivity and reward chosen by the owner].** Three
bandits are residents with no town (settlement 0, occupation "Bandit"), so the
town systems pass them by and `bandits.gd` runs them. The camp is placed as far
from every town as the map allows. They demand your coins and gun; surrender
hands them over, then they either let you go or tie you up at the camp (50%,
stream "bandits"). Refusing, running or hurting one starts a fight (they shoot
with `Gunfire.fire_at_player`). Going down or surrendering means robbery and
captivity. You slip free once they all sleep (after two hours at least), or
after a day. Beating them leaves their loot pile and the leader's purse to you
and records `bandits_cleared`, which every town hears (+25 reputation). Crimes
against outlaws are not crimes (`Law.crime` ignores town 0 and bandit victims).
Only full games get a camp (not bare test worlds).

**Dustvale is the capital [owner].** Three sheriffs per town, five in the
capital (`Capital.sheriffs_wanted`); a second sheriff with the same surname
keeps his first name, so names stay unique. Two new building kinds, `town_hall`
and `saloon`, and the building kinds are now one shared list,
`World.BUILDING_KINDS`. The Governor lives in the town house and works at his
desk 08:00-16:00. The barkeep lives at the saloon and tends the bar
14:00-23:00, keeping later hours (bed 23-00, up 08-09). Neither pairs off or
moves house. Townsfolk drop in 18:00-21:00 (30% once a day), and the player
can buy a drink (3 coins to the barkeep: thirst and mood). Dustvale's office
keeps its two sheriff beds: five sheriffs share them in shifts (there is no
room for a third bed beside the rack).

## 2026-11-25: Far-zoom frame rate accepted [owner]

After milestone 5 and the follow-up work, the overview zoom (0.2) runs at about 52 FPS against 58
before (-10.5%), just past the rule that a drop of 10% or more is fixed or accepted. The cause is
mostly more to draw: 28 people instead of 18 (the extra sheriffs, the governor, the barkeep, the
bandits), street lamps and the new buildings. Normal play (zoom 2) is at 74-75 FPS (budget 60),
rain at 68 (budget 50), the map unchanged, the worst simulation tick 14 ms (budget 15). The owner
accepted the far-zoom figure on 2026-11-25. Records: docs/validation/view_benchmark_*_m5_*.json.

## 2026-11-25: Fights that end, reinforcements, a living camp, roofs [owner]

**Sheriffs end fights.** Until the fight turns lethal (you killed someone or keep firing), sheriffs
aim for your legs, or your gun arm if you shoot back (`Wounds.pick(sim, aim)`, 75% aimed). They
close in cover to cover, or straight in while you're quiet if there is no cover; when you're in
cover one of them flanks (`alert.flanker`). Holding your gun without firing for 200 ticks
(20 s) turns into an arrest; crawling does too. Wounded sheriffs bandage instead of freezing. A
sheriff shouts at most once every 100 ticks, and only on a change.

**Reinforcements.** A killing by the player with a witness is filed as murder (it was only
remembered) and sends a civilian runner to the nearest other town (`sim/law/reinforcements.gd`).
That town sends two sheriffs, always keeping one at home (`Sheriff.strength` counts those away).
They travel as a trip (one path, cheap position lookup). On arrival they join the fight; if you're
already caught they visit the office, talk, and go home.

**Arrest from the ground.** A downed suspect is held down while cuffed (`arrest.pinned`), then
hauled up in a new `lift` phase (40 ticks) before the escort; no more popping up standing.

**Bandit camp.** Three big open tents (one per bandit, slept in), a pot, seats, a woodpile and a
lookout. By day each bandit takes turns to sit, cook, fetch wood and keep watch; crates, rocks and
the woodpile are solid cover. The fire is drawn every frame (not baked into the background).

**Roofs.** Every finished building has a roof over its exact shape (`view/world/roofs.gd`), y-sorted
at its front edge. The roof over the building the player is in is lifted; people inside any other
roofed building are not drawn. Zoomed far out every roof stays on, building floor images are
hidden, the "YOU" label and player dot are removed, and name tags are hidden. Town names draw on
their own layer above the roofs. View only: nothing in `sim/` changed for roofs.

Benchmarks (2026-11-25, same machine, before = commit 5e6bb3b, 1280x720), FPS before -> after:
noon zoom 2 76.5 -> 72.6 (-5%), zoom 1 50.5 -> 53.5, zoom 0.5 35.6 -> 39.0, far zoom 0.2
45.0 -> 48.6, map 699 -> 683; night zoom 2 67.3 -> 69.6, far 44.6 -> 48.0. Roofs make the far and
middle zooms faster (no floors, no people indoors). The machine ran slower overall than in the
earlier records. Worst simulation tick after warm-up 14.3 ms (budget 15). All 91 tests pass.
Records: docs/validation/view_benchmark_{before,after}_fights_{12,23}.json.
