#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
GODOT_BIN=${GODOT_BIN:-godot}
TEST_OUTPUT=$(mktemp /tmp/solo-test-output.XXXXXX)
trap 'rm -f "$TEST_OUTPUT"' EXIT
run_checked() {
  if "$GODOT_BIN" "$@" > "$TEST_OUTPUT" 2>&1; then
    cat "$TEST_OUTPUT"
  else
    cat "$TEST_OUTPUT"
    return 1
  fi
  # Some SceneTree scripts can quit(0) after a runtime error: reject that too.
  if grep -Eq '^(SCRIPT ERROR:|ERROR:|FAIL:)' "$TEST_OUTPUT"; then return 1; fi
}
python3 tools/check_layout.py   # dangling paths, broken links, layering, unlisted tests
run_checked --headless --path . --editor --import --log-file /tmp/solo-import.log
for test in sim/nav_test sim/encumbrance_test sim/hit_reactions_test view/save_slots_test sim/signpost_test sim/memory_test sim/reputation_test sim/conversation_test sim/witness_test sim/gossip_test sim/carrying_test sim/trespass_test sim/look_test sim/rifle_stealth_test sim/talk_favours_test sim/people_trade_test sim/sheriff_tactics_test sim/auto_travel_test view/trader_walk_test sim/road_network_test sim/player_sleep_test view/click_parts_test sim/wound_test sim/cover_test sim/door_assist_test view/door_test view/map_overlay_test sim/gunfire_test sim/sheriff_roster_test sim/law_test sim/layout_test sim/house_shapes_test sim/combat_speech_test sim/trader_test sim/housing_test view/sheriff_rest_menu_test view/crouch_forest_sun_test view/character_art_test sim/loot_test sim/context_test sim/sleep_test sim/brawl_test sim/hotbar_test sim/diagonal_names_test sim/needs_test sim/crops_test sim/households_test sim/placement_test view/shotgun_test sim/kernel_test sim/world_test sim/forest_groves_test sim/weather_test sim/travel_reroute_test view/local_combat_test view/unarmed_test sim/building_test view/construction_stages_test sim/architecture_test view/depth_order_test view/fixtures_test sim/player_health_test sim/player_interaction_test view/player_panels_test view/player_mobility_test view/animation_test view/animation_live_test view/poses_test sim/village_test sim/production_test sim/economy_test sim/regional_test sim/society_test sim/persistence_test sim/interruptions_test view/smoke_test view/save_migration_test sim/light_test sim/day_clock_test sim/bandits_test sim/bandit_camp_test sim/gunfire_tactics_test sim/reinforcements_test sim/dustvale_capital_test sim/regional_weather_test sim/weather_feel_test sim/seasons_test sim/price_trend_test soak/full_game_test soak/season_soak_test; do
  run_checked --headless --path . --script "res://tests/$test.gd" --log-file /tmp/solo-test.log
done
