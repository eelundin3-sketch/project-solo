extends RefCounted
## The one clock for the time of day. A day has four parts of six hours each:
##   morning 04:00-10:00, day 10:00-16:00, evening 16:00-22:00, night 22:00-04:00.
## Light, the sun's path and shadows, sleep, shop hours and chores all ask this file, so they
## agree with each other. Ticks: 10 a minute, 600 an hour, 14400 a day. Integer maths for the
## simulation; the float helpers (sun position) are for drawing only.
const DAY := 14400
const MORNING := 240     # minutes into the day each part begins
const DAYTIME := 600
const EVENING := 960
const NIGHT := 1320
const SUNRISE := 300     # 05:00: the sun comes up in the east...
const SUNSET := 1260     # 21:00: ...and goes down in the west; highest at 13:00
const PHASES := ["morning", "day", "evening", "night"]
## Everyone goes to bed between 21:00 and 22:00 and gets up between 06:00 and 07:00, each at
## their own fixed time (set by their id, so it never changes and needs no saving).
const BED_FROM := 1260
const WAKE_FROM := 360
const SPREAD := 60

static func minute(s: Dictionary) -> int:
	return (int(s.tick) / 10) % 1440

static func minute_of(tick: int) -> int:
	return (tick / 10) % 1440

static func hour(s: Dictionary) -> int:
	return minute(s) / 60

## "morning", "day", "evening" or "night" for a minute of the day.
static func phase_at(m: int) -> String:
	if m >= MORNING and m < DAYTIME: return "morning"
	if m >= DAYTIME and m < EVENING: return "day"
	if m >= EVENING and m < NIGHT: return "evening"
	return "night"

static func phase(s: Dictionary) -> String:
	return phase_at(minute(s))

static func phase_name(s: Dictionary) -> String:
	return phase(s).capitalize()

static func is_night(s: Dictionary) -> bool:
	return phase(s) == "night"

## Daylight 0 (deep night) to 100 (full day): dark at night, dawn 04:00-06:00, full light until
## 20:00, dusk 20:00-22:00.
static func daylight_at(m: int) -> int:
	if m >= 360 and m < 1200: return 100
	if m >= NIGHT or m < MORNING: return 10
	if m < 360: return 10 + (m - MORNING) * 90 / 120
	return 100 - (m - 1200) * 90 / 120

static func daylight(s: Dictionary) -> int:
	return daylight_at(minute(s))

## A person's own bedtime and waking time, in minutes of the day.
## The barkeep keeps later hours: to bed 23:00-00:00, up 08:00-09:00.
static func bedtime(npc: Dictionary) -> int:
	if str(npc.get("occupation", "")) == "Barkeep": return 1380 + posmod(int(npc.get("id", 0)) * 37, SPREAD)
	return BED_FROM + posmod(int(npc.get("id", 0)) * 37, SPREAD)

static func wake_time(npc: Dictionary) -> int:
	if str(npc.get("occupation", "")) == "Barkeep": return 480 + posmod(int(npc.get("id", 0)) * 23 + 11, SPREAD)
	return WAKE_FROM + posmod(int(npc.get("id", 0)) * 23 + 11, SPREAD)

## Past this person's bedtime and before their waking time: the hours they want to be in bed.
static func bed_hours(s: Dictionary, npc: Dictionary) -> bool:
	var m := minute(s)
	return m >= bedtime(npc) or m < wake_time(npc)

# --- the sun, for drawing (floats) -------------------------------------------------------------

## The sun's height: 0 at sunrise and sunset, 1 at 13:00, below 0 at night (lowest at 01:00).
static func sun_elevation(day_fraction: float) -> float:
	var m: float = fposmod(day_fraction, 1.0) * 1440.0
	if m >= SUNRISE and m <= SUNSET: return sin(PI * (m - SUNRISE) / float(SUNSET - SUNRISE))
	var dark: float = fposmod(m - SUNSET, 1440.0)
	return -sin(PI * dark / float(1440 - (SUNSET - SUNRISE)))

## How far the sun has crossed the sky: 0 at sunrise (east) to 1 at sunset (west).
static func sun_arc(day_fraction: float) -> float:
	var m: float = fposmod(day_fraction, 1.0) * 1440.0
	return clampf((m - SUNRISE) / float(SUNSET - SUNRISE), 0.0, 1.0)

## Daylight as a smooth 0..1 for drawing, following daylight_at.
static func light_amount(day_fraction: float) -> float:
	var m: float = fposmod(day_fraction, 1.0) * 1440.0
	if m >= 360.0 and m < 1200.0: return 1.0
	if m >= NIGHT or m < MORNING: return 0.0
	if m < 360.0: return smoothstep(float(MORNING), 360.0, m)
	return 1.0 - smoothstep(1200.0, float(NIGHT), m)

## How golden the light is: rises through the evening, strongest just before dusk.
static func evening_glow(day_fraction: float) -> float:
	var m: float = fposmod(day_fraction, 1.0) * 1440.0
	if m < EVENING or m >= NIGHT: return 0.0
	if m < 1200.0: return smoothstep(float(EVENING), 1200.0, m)
	return 1.0 - smoothstep(1200.0, float(NIGHT), m)
