# Development status

Verified 2026-11-20 on branch `feature/quick-wins` (commit `74320c3` plus the handover commit). "Verified" below means checked by running the tests, running the game headless, reading the code or taking screenshots. **None of the work in sections 2 and 3 has been hand-played by the owner**: the game was launched once at the end (no feedback yet).

## 1. Snapshot

| Item | Value |
|---|---|
| Tests | 77 in `scripts/test.sh`, all passed (last full run 2026-11-19 evening, 12 min 48 s) |
| Frame rate (M4, 1280x720) | about 79 FPS zoom 2, 57 zoom 1, 46 zoom 0.5, about 1,000 on the map; headless worst tick about 12 ms. Records: `docs/validation/view_benchmark_*.json` |
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

## 3. Partly implemented (exact gaps)

| Feature | What exists | What is missing |
|---|---|---|
| Unseen crimes | murder/theft nobody saw go to `s.law.hidden` (`witness_reports.gd`) | **Nothing ever reads `s.law.hidden`.** A found body records a `body_found` chronicle entry and a spoken line (`carrying.gd` `_find_bodies`) but does not alert the law or file the crime. Intended: a found body or a missing-goods discovery should surface the crime |
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

1. **Hidden crimes never resolve** (section 3).
2. **Render error at launch:** `ERROR: Invalid polygon data, triangulation failed` from `view/world/prop_art.gd:7` via `log_piece` (a log lying on the ground, drawn by `fixture_director.gd` `draw_transfers`). Seen when the game was launched on 2026-11-20 and repeats; not investigated; **unknown whether it predates this work**. The game keeps running.
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
3. Look at the render error (section 5.2) once to learn whether it predates this branch.
4. Then milestone 5 from `docs/ROADMAP.md`: night lighting, per-town weather, mud and fog, seasons and harvest, seasonal colours, price trends. Show the plan first.
