# Game design

Last verified against the code: 2026-11-20. This describes how the game **behaves now** and the principles behind it. Numbers are quoted from the code with the file that owns them: change the file, then fix the number here. Not-yet-built ideas are in `docs/ROADMAP.md`, not here.

Tags used below: **[owner]** = the owner said so in conversation; **[design pack]** = from `docs/design/01_GAME_FOUNDATION.md`; **[inferred]** = my reading of the owner's direction, not a direct instruction.

## 1. Vision

A single-player, top-down 2D **living frontier sandbox**. Every resident pursues their own needs and work, goods move through real supply chains, and the player is one traveller in a world that carries on without them **[design pack]**. On top of that, the owner has steered the game toward a **consequence-driven frontier**: crimes have witnesses and are remembered, news spreads, gunshots are heard, and how people treat you depends on what you did and how you look **[owner, across steps 1-4]**. No scripted quests; stories come from systems.

## 2. The world

- **Three towns**, far apart on a 582 by 420 cell map (1 cell = 1 m): **Alder Hollow** (west, forested, the starting town), **Reedbank** (east), **Dustvale** (far south, dry country, adobe and stone, a big iron rock to mine). 6 residents each at the start, plus the player.
- **Roads** link the towns with shared trunks that fork, planned around rocks, buildings and fields (`sim/world/road_planner.gd`); **signposts** at the forks name each town with its distance in paces and point down each road **[owner: realistic roads, signposts]**. Walking is about 15% quicker on town streets and 30% on the roads between towns (`sim/movement/pace.gd`) **[owner]**.
- About 6,300 trees form real forests with clearings around houses, doors, workshops, fields and roads. 13 house types; each household lives in a home with a pantry and a garden.
- **Weather** is per town (clear, rain, fog, snow), re-rolled every 6 game hours from each town's climate (Reedbank wet, Dustvale dry). Drought slows crops, rain makes road mud, fog shortens sight. **Seasons are 15 days**, and a game opens on the first day of summer **[owner]**; winter stops crops and the farmers cut wood or mine (`sim/world/weather.gd`, `sim/farming/crops.gd`).

## 3. Time and the daily rhythm

1 tick = 0.1 s at 1x; 600 ticks = 1 hour; **14,400 ticks = 1 day** (about 24 real minutes). A new game starts at 07:00 on day 1 **[owner]**. **The day has four parts [owner]:** morning 04:00-10:00, day 10:00-16:00, evening 16:00-22:00, night 22:00-04:00. The sun rises in the east at 05:00, is highest at 13:00 and sets in the west at 21:00, and shadows follow it. People get up between 06:00 and 07:00 and go to bed between 21:00 and 22:00, each at their own fixed time (`sim/world/day_clock.gd`). The table below predates this and some hours in it have moved: shopping 07:30, garden chores 07:00-08:30 and 17:30-19:30, shops open 07:00-21:00, street lamps 20:00-05:00.

| Time | What happens | Where |
|---|---|---|
| 05:30 / 20:30 | night starts/ends (`Needs.is_night`) | `sim/entities/needs.gd` |
| 06:00 | autosave (view side); people may tend gardens 06:00-07:30 | `app/save_slots.gd`, `households.gd` |
| 07:00 | family shopping errands | `family_economy.gd` |
| 12:00 | **daily update**: pairing, births, professions, purses, gossip cleanup, favours raised, reputation recomputed | `Households.daily` |
| 17:30-19:30 | evening garden time | `households.gd` |
| 19:00 | payday: families are paid for finished jobs, sheriffs their wage | `FamilyEconomy.payday` |
| 06:00-21:00 | workshops open to visitors | `sim/law/trespass.gd` |
| 22:00-05:30 | trespass at night gets one warning, not three | `trespass.gd` |

Sleep: click a bed and choose Sleep; the clock runs 8x until you are rested, it is 06:00, you are hurt, or you press any key **[owner]**.

## 4. People, families and money

- Residents have an occupation (Farmer, Woodsman, Sawyer, Baker, Blacksmith, Miner, Builder, Trader, Sheriff, Gatherer, Child), needs (hunger, thirst, fatigue), a household, memories and opinions. How many of each trade a town wants comes from what the land offers (`sim/settlement/professions.gd`: trees, ore, fields, population, danger).
- **Families live together** and run a **family economy** **[owner]**: a household has a home, a shared surname and a purse (`accounts["household:<key>"]`). Finished jobs earn the family 5 coins each, a sheriff 30 a day, paid at 19:00; at 07:00 someone shops for food; families can afford meals from the purse (`family_economy.gd`). Adults pair up, move in together and have up to 3 children; children grow up after 8 days (`households.gd`). Overcrowded towns send people to towns with room (`society.gd` `migrate`).
- **Prices follow supply**: each item's price in each town is `BASE * TARGET / (stock + TARGET/2)`, clamped 2-100 (`sim/economy/market.gd`). Traders walk the roads between towns buying cheap and selling dear while the gap pays (`traders.gd`).
- **Stalls and keepers**: when you come to an unstaffed stall the keeper (or the nearest free adult) **hurries over** and you wait for them before trading **[owner]**. You can **haggle** once per visit (chance depends on their anger and how they feel about you; success 10-20% off, failure 10% dearer). Prices also move with how they feel about you (grudge +15%, friend -10%) and how you look (filthy +10%, well turned out -5%).
- All money and goods are **conserved**: nothing appears from nothing (`sim/diagnostics/invariants.gd` checks the coin total).

## 5. The player

- **Start**: Alder Hollow, a backpack, 4 food, 6 bandages, 2 antiseptic, **a rifle (slung) and 10 cartridges**, about 1000 coins **[owner: rifle is the main gun]**.
- **Body**: per-part health (bruises, cuts, infection), limbs that go hurt then useless (a bad leg slows and limps you, two make you crawl, a bad arm spoils your aim), bleeding that costs health until bandaged, stamina (sprint drains it; empty = collapse). Press H to treat injuries. Condition icons down the left edge: bleeding, pain, hungry, thirsty, tired, stressed, unhappy, wet, cold, overloaded.
- **Carrying**: items weigh something; the limit is 40 (55 with a backpack). Over 75% you walk 10% slower, over 100% (no running, tire faster) 30%, over 150% 60% (`sim/player/encumbrance.gd`). A person over your shoulder always counts as an overload.
- **Your look** (`sim/player/look.gd`): beard grows 3 a day, hair 1; dust builds outdoors and at work, mud on wet roads, blood from cuts and from handling the dead; rain makes you wet. Filthy or bloodied strangers get cold greetings and pay more; sheriffs warn them. Wash at a well; pay 3 coins at the storehouse for a shave.
- **Hotbar** keys 1-4: weapons you pick up go there; the rifle and shotgun can both be carried, one readied at a time.

## 6. Guns, fights and cover

- **Rifle** (main gun): one fast accurate bullet, range 26 cells, hits 2.6x a pellet, reload 20 ticks per round, 5 rounds, **heard 60 cells**. **Shotgun** (still works if you have one): 7 pellets, range 9, heard 45 (`sim/combat/shotgun.gd` `WEAPONS`).
- **Gunshots are loud** **[owner]**: a town reacts only if the shot is within earshot of the town or one of its sheriffs; out in the wilds nobody official does. People who hear but don't see it say so; **only those who see you shoot can name you** (`gunfire.gd` `town_in_earshot`).
- **Silent takedown** **[owner]**: crouched, adjacent and unseen (the target isn't watching you or walking toward you), you can kill or knock someone out silently (`sim/combat/takedown.gd`). If **anyone sees it** they run to the sheriff; a sheriff only counts if he has a clear line of sight. Unseen, nobody knows who did it.
- **Fists**: punch or shove; do it twice and they beat you; blunt hits bruise where they land.
- **Cover** **[owner]**: you only take cover when sneaking (crouched) or in combat. Everything solid is **high** (walls, standing trees, big rocks, lockers, racks, ovens, forges: cover while standing) or **low** (beds, chests, tables, small rocks: only if you crouch, otherwise you are shot through it) (`sim/combat/cover.gd`).
- **Sheriffs in a fight** **[owner]**: they move slowly from cover to cover to get a shot without risk, only while the gunman is quiet or reloading, one at a time; they **bandage** themselves behind cover when hurt, because a gunshot wound bleeds until treated **[owner]** (`gunfire.gd` `cover_cycle`; `bleeding.gd`). Wounded villagers fetch and bind their own bandages.
- Hit while holding something in your hands and you lose your grip (the goods stay in your pack); a hurt arm widens your aim by 30%.

## 7. Law, crime and witnesses

- **Wanted** is per town, in hours (max 48): theft 3, assault 2, assault on a sheriff 4, kicking someone down 3, murder 24, firing in town 2, shooting someone 6, trespass 1, bribery 2 (`sim/law/law.gd` `SENTENCE`).
- **Who knows**: a sheriff within 24 cells who sees it (or is the victim) acts at once; otherwise **townspeople who saw it (or the victim) run to the nearest sheriff and you are only wanted when they arrive**; stop them and it never is **[owner: witnesses]**. A murder or theft nobody saw is kept as an unsolved crime in `s.law.hidden` (nothing reads that list yet, see `docs/DEVELOPMENT_STATUS.md`); other unseen crimes leave only the victim's memory.
- **Recognition**: a sheriff who saw it knows your face; one who only has a description knows you if at least 3 pieces of your clothing still match. Change clothes and you may slip away.
- **Arrest flow**: standoff at gunpoint (F raises your hands), cuffing, escort, booking (property to the locker, mugshot, uniform), cell, release with your things back.
- **Trespass** **[owner]**: walk into someone's home uninvited and they warn you three times (150 ticks apart; once at night), getting angrier and remembering it; then an angry one throws you out and a calmer one runs for the sheriff. Family, friends (opinion 35+) and invited guests are welcome; the common lodges, storehouses and sheriffs' offices are always open (`trespass.gd`).
- **Bodies**: you can carry someone out cold or dead over your shoulder (slow, no running, no gun); put them down out of sight and they are not found, in the open and they are found and it is news. Seen carrying a body = a witnessed crime (`sim/player/carrying.gd`).
- **Bribing or talking your way out** when a sheriff has his gun on you: 10/25/50 coins (never for murder; a refused bribe is another charge) or an excuse for a minor charge (`sim/player/talk.gd`).

## 8. The social layer

- **Memory**: people remember what you did to them, their family and what they saw. Each memory kind has a strength and fades over days; a killing in the family never fades. They keep at most 16, dropping the faintest first. `Society.opinion` adds trust and live memories (-100..100) (`society.gd`).
- **Opinion changes**: prices, haggling chance, greetings (cold, warm, scruffy), the mood chip in the Talk window, whether they welcome you in their home.
- **Reputation per town** (-100..100): recomputed at 12:00 from what each town knows (witnessed there, or news that reached it); old deeds fade over 28 days, killings 84. Labels: Feared, Distrusted, a Stranger, Known, Respected, Beloved. Shown in the journal, the Talk window, and under each town's name on the map (`sim/factions/reputation.gd`).
- **Gossip**: witnesses know first; neighbours who chat pass the newest thing the other hasn't heard (50%, and 15% to make it bigger); families share daily; **traders carry the news to the next town**. When a third of a town's adults have heard something the town "knows" it. News is forgotten after 14 days. Asking someone for news gets real gossip (`sim/entities/gossip.gd`).
- **Talk**: friendly, firm or threatening small talk, judged by each person's temper (calm, warm, gruff, nervous, proud), how they feel about you, and luck. A threat can cow a nervous person into a 15% discount but costs good will (`talk.gd`).
- **Favours**: a family with a bare pantry asks for 5 bread; a sheriff's office short of bandages asks for 4. Agree, bring them, get paid from the family purse (or the town's) and be remembered; two days to do it (`requests.gd`). Courier and find-a-person favours are not built.
- **Journal (J)**: people met, news heard, favours, and your standing/looks/load.
- **Context menu (left-click)** **[owner: "click what you press"]**: clicking a person or object lists what you can do to it; clicking a bed offers Sleep, the weapon rack offers a gun, plain floor offers nothing.

## 9. Controls

| Input | Action |
|---|---|
| WASD, Shift, X | walk (diagonals), sprint, crouch/sneak |
| Left-click | action menu on a person or object; double-click open ground to walk there |
| Right mouse (hold) + left click | aim and fire when a gun is readied; Space shoves; right-click twice walks |
| 1 / 2 / 3 / 4, R | hotbar (weapons go there), reload |
| F, E, Q | interact, eat, drink at a well |
| I, H, C, J | inventory, health, clothes, journal |
| M, Tab | drawn map (click a town name to travel there), camera follow |
| P, `,` `.` | pause, slower/faster |
| T, G | rotate or tidy the nearest furniture |
| F5 / F9 | quick save / load the newest save |
| F3, F4, F8, Esc | observer mode, performance tab, debug details, close the open window (map first, then a travel, then panels) |

## 10. Design principles

1. **Deterministic and legible.** Same seed and commands give the same world; the player should be able to find out why something happened **[design pack]**.
2. **Everything physical is conserved**: coins and goods only move, never appear **[design pack]**.
3. **The simulation decides, the view draws.** Windows list what the sim offers; they never decide outcomes.
4. **Original content only**; no assets or code from other games **[design pack, AGENTS.md]**.
5. **Frame rate is a feature** **[owner]**: the owner asked that the game stay smooth with high FPS after everything is built. Budgets in `docs/ROADMAP.md` section 6.
6. **Show people being people**: absent keepers hurry over, families share money, sheriffs take cover carefully, wounds need treating, shadows only outdoors **[owner]**.
7. **Systems over scripts**: new features should plug into memories, the chronicle, reputation, gossip and the Talk window rather than add isolated mechanics **[inferred from how steps 1-4 were agreed]**.

## 11. Owner's decisions about play that are not obvious from the code

- The rifle, not the shotgun, is the starting gun. (Sheriffs' own weapons and AI were not changed; the owner did not ask.)
- Silent kills are allowed and are a crime only if seen; gunshots are always loud.
- Cover rules, bleeding-until-bandaged and sheriff cover-to-cover movement as in section 6.
- The jail cell door stays shut while you are locked in; Esc closes the map first.
- The drawn medieval map is painted once when M is pressed (it costs nothing per frame) and repainted each time M is pressed again.
- No repeating ambient sound loops.
