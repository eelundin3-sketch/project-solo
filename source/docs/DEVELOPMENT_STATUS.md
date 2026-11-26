# Development status

Verified 2026-11-20 on branch `feature/quick-wins` (commit `74320c3` plus the handover commit). "Verified" below means checked by running the tests, running the game headless, reading the code or taking screenshots. **None of the work in sections 2 and 3 has been hand-played by the owner**: the game was launched once at the end (no feedback yet).

## 1. Snapshot

| Item | Value |
|---|---|
| Tests | 108 in `scripts/test.sh`, all passed (last full run 2026-11-26, season soak included) |
| Frame rate (2026-11-26, 1280x720, measured with two game windows open) | about 59 FPS zoom 2 at noon, 57 at night, 46 zoom 1, 32 zoom 0.5, 43 far (0.2), about 600 on the map; the code from before this stretch gives 57 / 46 / 35 / 42 under the same load, so the drop from the 2026-11-25 numbers is the machine, not the code. Worst simulation tick 25.6 ms idle (24.5 for the older code, same load); a one-off 25 ms when you first draw (the cover lookup is built). Records: `docs/validation/view_benchmark_after_life_*.json`, `full_game_benchmark_after_life.json` |
| Code size (GDScript, excluding Finder copies) | `sim/` about 11,800 lines, `view/` 9,400, `app/` 900, `tests/` 7,700 |
| GitHub | **PR #14** (`feature/quick-wins` into `chore/app-first-layout`) opened 2026-11-20 at the owner's request; PR #13 (`chore/app-first-layout`) is open and its checks passed; neither is merged |

### Git state (verified with `git fetch` and `git rev-list`)

| Branch | State |
|---|---|
| `main` | `be26892`, includes PRs #10 (performance), #11 (test fixes), #12 (roads, map, sleep, travel) |
| `chore/app-first-layout` | PR #13, open: moves the game into `source/` so `Project Solo.app` is first; CI timeout raised to 45 min (commit `fd8adbd`) |
| `feature/people-trade-families-sheriffs` | 5 commits on top of the layout commit `8d3ec4d` (they reach GitHub inside PR #14; this branch name itself was never pushed): stall keepers, family economy, sheriff tactics, bleeding, trade window, cover heights |
| `feature/quick-wins` (current) | the 5 above plus 17 more: steps 1-4 (below). Pushed as PR #14 (23 commits ahead of PR #13's branch, 24 ahead of `main` counting the layout commit). Does **not** contain `fd8adbd`, so its CI file still says 20 minutes |
| Other local branches | old, merged work (`chore/*`, `claude/*`, `codex/*`, `feature/*` from earlier sessions) with some linked worktrees under `~/Documents/ChatGPT/` |

Big-push order when the owner asks: **PR #13 first**, then the feature branches on top (they were built on the layout commit). See `docs/HANDOVER.md` section 6.

## 2. Implemented and tested

**Earlier work (merged to `main`, PRs #10-#12):** performance rewrite (derived lookups, C++ `AStarGrid2D` pathfinding, clock cap, batched shadows, view culling); fixed test suite; jail door stays shut; click-what-you-press inside buildings; sleeping with 8x fast-forward; trader walking on roads and smoothly; faster walking on roads; planned road network with forks and signposts; drawn medieval map painted once per opening; travel to a town by clicking its name; Esc closes the map; looping wind sound removed.

**On the local branches (not pushed):**

| Feature | Where | Test |
|---|---|---|
| Stall keepers hurry to a stall, haggling, "ask about family/news" | `sim/economy/stall_service.gd` | `people_trade_test` |
| Family economy: shared purse, wages at 19:00, 07:00 shopping, pantry, shared surname | `sim/entities/family_economy.gd` | `people_trade_test` |
| Bleeding until bandaged; everyone bandages; sheriffs carry bandages | `sim/combat/bleeding.gd` | `sheriff_tactics_test` |
| Sheriffs advance cover to cover, slowly, only while the gunman is quiet | `sim/combat/gunfire.gd` | `sheriff_tactics_test` |
| High/low cover; cover only when crouched or in combat | `sim/combat/cover.gd` | `cover_test` |
| Designed Trade window; no sun shadows indoors | `view/ui/trade_window.gd` | `trade_capture` screenshot |
| **Carrying weight** (limit 40/55, bands 75/100/150%) | `sim/player/encumbrance.gd` | `encumbrance_test` |
| **Hit reactions** (drop grip, hurt arm widens aim, hurt leg limps) | `shotgun.gd`, `body_health.gd`, `animation_director.gd` | `hit_reactions_test` |
| **Autosave 06:00 (two files), Continue, F9 loads newest, background saving** | `app/save_slots.gd` | `save_slots_test` |
| **Signposts with distances** | `road_planner.gd` `ensure_ways` | `signpost_test` |
| **Memories** with weights and fading; `Society.opinion` | `sim/factions/society.gd` | `memory_test` |
| **Chronicle** of events with witnesses | `sim/world/chronicle.gd` | `memory_test` |
| **Reputation per town** | `sim/factions/reputation.gd` | `reputation_test` |
| **Conversation window** (Trade and Talk tabs) | `trade_window.gd`, `sim/player/dialogue.gd` | `conversation_test` |
| **Witnesses** run to the sheriff; recognition by clothes | `sim/law/witness_reports.gd`, `law.gd` | `witness_test` |
| **Gossip** (chat, family, traders; grows in the telling) | `sim/entities/gossip.gd` | `gossip_test` |
| **Body carrying** | `sim/player/carrying.gd` | `carrying_test` |
| **Trespass** ("Get out of my house!") | `sim/law/trespass.gd` | `trespass_test` |
| **Your look** (beard, dust, mud, blood, rain; wash; shave) | `sim/player/look.gd`, `drawn_character.gd` | `look_test` |
| Bandaging someone is remembered | `context_actions.gd` | `memory_test` |
| **Rifle as main gun**; gun weapon table | `sim/combat/shotgun.gd` | `rifle_stealth_test`, `shotgun_test` |
| **Gunshots heard by distance** | `gunfire.gd` `town_in_earshot` | `rifle_stealth_test` |
| **Silent kill / knock-out from behind** | `sim/combat/takedown.gd` | `rifle_stealth_test` |
| **Talk with tone; bribes; persuasion** | `sim/player/talk.gd` | `talk_favours_test` |
| **Favours** (bread for a bare pantry, bandages for an office) | `sim/player/requests.gd` | `talk_favours_test` |
| **Journal (J)**; standing under town names on the map | `view/ui/journal_window.gd`, `medieval_map.gd` | `talk_favours_test`, `journal_capture` |
| **Milestone 5: night lighting** (street lamps, lit windows, lantern; `Light.level`) | `sim/world/light.gd`, `view/world/night_layer.gd` | `light_test`, `night_capture` |
| **Weather per town**, drought and crops, trades by climate, families moving | `sim/world/weather.gd`, `crops.gd`, `society.gd` | `regional_weather_test` |
| **Mud, fog, rain/snow particles, wet ground** | `pace.gd`, `weather.gd`, `view/world/weather_layer.gd`, `landscape.gdshader` | `weather_feel_test`, `weather_capture` |
| **Seasons and harvest**; seasonal colours | `crops.gd`, `professions.gd`, `world_view.gd` | `seasons_test`, `season_soak_test`, `season_capture` |
| **Price trends** and prices known in other towns | `market.gd`, `trade_window.gd` | `price_trend_test`, `trade_capture` |
| **Four parts of the day**, sun path and shadows, own bedtimes, 15-day seasons, summer start at 07:00 | `sim/world/day_clock.gd` | `day_clock_test`, `shadow_capture` |
| **Winter stores** (rye reaches the baker; storehouses lay up food) | `job_board.gd`, `recipe_system.gd` | `season_soak_test` |
| **Smoke** from oven and forge, through a flue in the back wall | `view/world/fixture_art.gd` | `smoke_capture` |
| **Jail release**: fetched from the cell, things returned, walked to the door, shoved out | `sim/law/law.gd` | `law_test` |
| **Bandit camp**: demand, robbery, captivity and escape, fights, cleared camp and reward | `sim/factions/bandits.gd` | `bandits_test`, `bandit_capture` |
| **Dustvale the capital**: 3 sheriffs per town (5 there), governor's town house, saloon and barkeep, drinks | `sim/settlement/capital.gd` | `dustvale_capital_test`, `capital_capture` |
| **Sheriffs who end the fight**: close in cover to cover, a flanker when you're in cover, aimed shots at legs or gun arm until it turns lethal, a holdout who keeps his gun out is moved in on after 20 s, shouts only on a change | `sim/combat/gunfire.gd`, `wounds.gd` | `gunfire_tactics_test` |
| **Reinforcements**: a witnessed killing sends a runner to the nearest town; two sheriffs come, join the fight, or visit the office and talk, then go home | `sim/law/reinforcements.gd` | `reinforcements_test` |
| **Poses**: sitting (desk, saloon, campfire), tied with ropes, backpedal and strafe legs, an arrest from the ground (held down, then hauled up) | `animation_director.gd`, `drawn_character.gd`, `law.gd` | `poses_test`, `law_test`, `poses_capture` |
| **A living bandit camp**: big tents they sleep in, sit/cook/fetch wood/keep watch, cover in a fight, an animated fire | `sim/factions/bandits.gd`, `frontier_map_art.gd` | `bandit_camp_test`, `bandit_capture` |
| **Roofs** on every building except the one you're in; people indoors hidden; zoomed out: roofs only, no "YOU" marker or name tags | `view/world/roofs.gd`, `world_view.gd` | `roofs_test`, `roofs_capture` |
| **Bandits look like outlaws** (duster, black hat, bandana; leader in a long coat); guns pointed at you while sheriffs and bandits move in | `outfits.gd`, `drawn_character.gd`, `animation_director.gd` | `poses_test` |
| **Bandits fight like the sheriffs**: one shared cover cycle (`gunfire.gd fight_cycle`), positions (front, flank, camp), 5-round reloads, morale (give up or run) | `sim/factions/bandits.gd`, `sim/combat/gunfire.gd` | `bandit_fight_test` |
| **Hold-up and captivity**: guards on both sides, a spoken countdown, walked to the post, a night watch in shifts, F works the ropes, the loot pile guarded | `bandits.gd` | `bandit_captive_test` |
| **Bandits in town get arrested**: supply runs every third day, sightings, two sheriffs, surrender or a shootout between people, three days in the cell | `sim/law/outlaw_arrest.gd` | `outlaw_arrest_test` |
| **Townsfolk react by temperament** (confront then fetch the sheriff, fight, flee); a witness reports a shooting once it's quiet | `brawl.gd`, `fear.gd`, `witness_reports.gd` | `civilian_reactions_test` |
| **Wanted and remembered**: townsfolk know you, shops refuse or charge double, sightings, fines, turning yourself in, HUD line, journal, notice by the office | `sim/law/notoriety.gd` | `wanted_memory_test`, `wanted_capture` |
| **Smarter conversations**: openers from memories, real news told once with follow-ups, introductions, sheriff/barkeep/Governor/bandit/watch/prisoner topics, amends, paged options | `sim/player/conversation.gd` | `smart_talk_test` |
| **Missing people and investigations**: missed after an hour, house then search, body examined (cause of death), witnesses asked, filed / suspect / open, laid to rest | `sim/law/investigation.gd` | `investigation_test` |
| **Bounties and prisoners; the gang grows back** (newcomers up to five, beaten leave, a new gang a season after clearing) | `sim/law/bounties.gd`, `bandits.gd` | `bandit_bounty_test` |
| **Esc pause menu** (Resume, Save, Load, Quit to title, Quit) | `view/ui/pause_menu.gd`, `world_controller.gd` | `pause_menu_test` |
| **Buildings with height** (front walls and raised roofs; people shorter than houses) and **fronts that show what each building is for** | `view/world/roofs.gd` | `roofs_test`, `buildings_capture` |
| **Smooth walking for everyone** (each NPC walks at its own step rate) | `animation_director.gd` | `slow_walk_test` |
| **NPCs animated like you in a fight** (exact aim, recoil, reload, tackle as a shove); fighters spread over different cover; no small talk mid-fight | `animation_director.gd`, `gunfire.gd` | `npc_animation_test`, `bandit_fight_capture` |
| **Down in a gunfight, they rush in and take you alive** (sheriffs and bandits, flankers covering) | `gunfire.gd`, `law.gd`, `bandits.gd` | `capture_rush_test` |
| **Jail waits**: the fast-forward stops with two minutes left; sentences over four hours are caught up behind a card in seconds | `world_controller.gd` | `jail_wait_test` |
| **Everyday walks follow the roads**, and townsfolk are quicker on them | `nav_grid.gd` (street grid), `residents.gd` | `road_walk_test` |
| **Your house** on the west side of Alder Hollow: bedroom, living room with kitchen and fridge, back terrace with squat rack, bench, deadlift platform, pull-up bar; F uses them step by step (fitness, healing drink, rest) | `sim/settlement/player_house.gd`, `sim/player/activities.gd`, `view/world/home_art.gd` | `player_house_test`, `workout_test`, `home_poses_test`, `house_capture` |
| **A new game starts at home, mid-activity** (a workout set, the fridge, the bed or the sofa; a different one each game) | `activities.gd` `begin_at_home`, `world_controller.gd` | `player_house_test`, `home_start_capture` |

## 3. Partly implemented (exact gaps)

| Feature | What exists | What is missing |
|---|---|---|
| Unseen crimes | killings: missed, searched for, investigated (`investigation.gd`) | thefts nobody saw stay in `s.law.hidden` unread; no footprints or spent shells as clues yet |
| Wanted posters | wanted records store the clothes witnesses described (`law.wanted[town].outfit`) | no notice board fixture, no poster art (planned with town laws, ROADMAP milestone 6) |
| Save slots | autosave, Continue, F9 | named manual slots; needs a pause menu that does not exist (milestone 9) |
| Favours | deliver and supply requests | courier ("carry this letter") and "find someone" kinds |
| Your look | player only | buying clothes; NPC looks do not change |
| Body carrying | works and is tested | the pose is basic: the body is drawn up at shoulder height, no real carry animation (milestone 7) |
| Hit reactions | grip, aim, limp | dropped goods stay in the pack: there are no loose items on the ground |
| Lanterns | the player starts with one; held in hand it is lit | not sold in stores; NPC lanterns are drawn light only |
| Seasonal trees | trees tint and go bare in winter | autumn leaves only shift toward olive: the tree art needs real autumn colours |
| Item weights | table in `encumbrance.gd` | not in `content/items/core.json` (only 8 items listed there; weights default to 0.5 for the rest) |
| Gun table | rifle, shotgun | pistol, bow, knife, gun wear (milestones 7 and 9) |
| Takedown awareness | uses the target's next path step as "facing" | NPCs have no real facing field; stealth with light/noise not built |
| Talk window | up to 7 lines | `TALK_MAX = 7`; extra options would be silently cut |

## 4. Not implemented

Everything in `docs/ROADMAP.md` milestones 5-14 (night lighting, per-town weather, seasons and harvest, town mood, mayor and laws, notice board, weekly rhythm, friendships, stealth with light/noise, more weapons, trials, jail escape, bounties, home ownership, crafting, own stall, hiring, loans, ageing/marriage/heirs, outlaw gangs and posses, starting stories, tutorial, skills, music, animals, fire, rivers, and about 35 optional ideas). Also not built: a pause menu, settings screen, controller support.

## 5. Known problems and technical debt

1. **Hidden crimes, partly resolved (2026-11-25):** an unwitnessed killing is now found through a missing-person report or a body, and investigated (`investigation.gd`). Unwitnessed thefts in `s.law.hidden` are still never read.
2. **Render error at launch (fixed 2026-11-25):** `Invalid polygon data, triangulation failed` came from shapes that cannot be filled (fallen logs, blood stains); `prop_art.gd` `fillable` now checks first and those are outlined or drawn as ovals.
3. **678 untracked Finder duplicate files** ("name 2.gd", "Project Solo 2.app", ...) litter the working folder. They are not in git and `check_layout.py` fails on any that get tracked. **Never run `git add -A` or `git add .`; add files by name.** A `.gitignore` rule for them has not been added.
4. **Godot exists only at `/private/tmp/living-world-engine/Godot.app`** (4.6 stable). A reboot or temp cleanup can remove it; `/Applications/Godot.app` is not installed. The launcher `Project Solo.app` looks in `/Applications` first. Moving it is an open task.
5. **Stale documents** (written before steps 1-4; they still say what they said): `README.md` (start kit now rifle; edited lightly 2026-11-20), `docs/status/CURRENT_GAME.md` and `IMPLEMENTATION_STATUS.md` (10 residents, two towns, shotgun, 384 x 256 region; banners added 2026-11-20), `docs/status/CHANGELOG.md` (stops at 2026-11-18; PRs #10-#13 and today's work are in git history and `docs/DECISIONS.md`).
6. **Comment/code mismatch:** several comments and the earlier plan say `Households.daily()` runs "each morning"; it runs at 12:00 (tick 7200). Reputation, gossip cleanup and new favours therefore update at noon.
7. **CI:** this branch's `tests.yml` has a 20-minute limit; the suite takes about 20 minutes on GitHub. Only PR #13's branch has the 45-minute limit.
8. **Empty folders:** `tests/unit`, `tests/integration`, `tests/determinism` have no files.
9. **Not verified:** whether the Windows and Linux builds run on those systems; whether GitHub Actions passes for the feature branches (it passed for PR #13's Build workflow earlier).
10. **Autosave is in the view layer** (`world_controller.gd`), so headless runs never autosave. Intended, but worth knowing.
11. **Test timing sensitivity:** several tests keep NPCs in place by re-setting their cell each tick and pausing their routine with `impact_until` (see `trespass_test.gd`). New systems that move people can break them.

## 6. Open decisions waiting for the owner

- Start milestone 5 (the owner answered "Not now" on 2026-11-20).
- Merging: PR #13 first (layout), then PR #14 (retarget it to `main` if GitHub does not do so itself). The owner has not said to merge.
- Publish a first GitHub Release (the README says Releases exist; none do).
- Delete about 10 old merged branches on GitHub (offered earlier, no answer).
- Move Godot out of `/private/tmp`, rename the old local folders (open since earlier).

## 7. What to do first next time

1. Let the owner hand-play steps 1-4 and the rifle; collect feedback before building more (nothing from this stretch has been seen by a person).
2. Fix section 3's first row (hidden crimes) if the owner agrees: it is small and makes witnesses and body-hiding complete.
3. (Done 2026-11-25: the render error in section 5.2 is fixed.)
4. Then milestone 5 from `docs/ROADMAP.md`: night lighting, per-town weather, mud and fog, seasons and harvest, seasonal colours, price trends. Show the plan first.
