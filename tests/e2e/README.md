# Multiplayer end-to-end tests

`IndoorClimateRedoneE2E` is a dev-only test mod. It never ships. It runs on a local, non-Steam dedicated server with
clients that join by themselves, and depends on the `PZE2EHarness` test harness mod, which provides `PZE2E.test`,
`PZE2E.check`, `PZE2E.ask` and `PZE2E.answer`. The harness mod and its bench script `pz-e2e.sh` are not part of
this repository.

- Server files (`42/media/lua/server/`) hold the test steps. They run on the server, a few game minutes apart, once
  the first player is in the world.
- Client files (`42/media/lua/client/`) answer the server's questions about what that client sees.
- Results are `[PZE2E]` lines in the server log. A test fails on any `CHECK FAIL` or `ERROR` line.

With the bench script of the harness, from the repo root:

```sh
pz-e2e.sh setup . tests/e2e/IndoorClimateRedoneE2E
pz-e2e.sh server-start --fresh
pz-e2e.sh client-start 1
pz-e2e.sh wait-ingame 1
pz-e2e.sh wait-tests
pz-e2e.sh client-stop all; pz-e2e.sh server-stop
```

`world data survives a restart` only checks something on the second run on the same world: after the first pass,
stop the server, start it again without `--fresh`, start the client again and wait for the tests.

`Smoke_Server.lua` checks that the mod is loaded and active on the server and on the client.

`Climate_Server.lua` covers the room simulation: the player's own room, a door and a window opened through the vanilla
timed actions, a multi-storey building and its stairs (the player is moved with the admin teleport command, so client
1 must be the admin), a building at the edge of the loaded map, the restart, and the cost of scanning and stepping the
buildings near the player (logged as a `[PZE2E]` line).

`Sync_Server.lua` checks that the client's public API serves the room the server simulates for its player, and that
the bridge raises the game's air at the player when the room is warmer. It also logs the air for the character as
the client and the server each see it.

`Devices_Server.lua` covers the devices: a client switches a propane heater on and off the way its context menu
does, both sides agree on its state and heat source, the tank burns and the client hears about it, the electric
heater's menu builds on the client, the items, icons, models and loot lists are loaded, and Lua Digital Watch UI shows
the room air. The watch check needs Lua Digital Watch UI on the bench; add its mod folder to `setup` (Workshop item
3676456221), otherwise the test only logs that it is missing.

`Warmth_Server.lua` runs last. It holds the outdoor air at -15 C with the admin climate override, moves the player
outdoors (indoors the game holds a powered building at 22 C), runs a propane heater on their square and logs, for two
game hours, the air each side's thermoregulator works with and the core temperature. The game works out body warmth
on the server, so the test checks that the server's air near the heater is warmed as much as the client's. It puts
the weather and the player back when it is done.

The bench lives in `.cache/pz-e2e` and never touches `~/Zomboid`. `tools/test.sh` runs the Kahlua and game API checks
on these files too, since they run in the game.
