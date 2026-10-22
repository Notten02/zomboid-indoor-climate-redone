# Player guide

How Indoor Climate Redone works in the game. The numbers are the defaults; most can be changed in the sandbox options
(see the end).

Indoor Climate Redone follows the rules of Frozen_Heart's Indoor Climate (EHR Addon). What is different is listed in
[changes-from-original.md](changes-from-original.md), what it cannot do in [known-limitations.md](known-limitations.md).

## What it does

Every room of a building gets its own air temperature, which the mod keeps in the world's save.

- **With grid power**, a room heads for 22 C (Powered building target), closing about 95% of the gap in an hour.
  Open or broken outer doors and windows pull it toward the outdoor air.
- **Without power**, a room drifts toward the outdoor air: slowly while it is sealed (0.06 per hour, so it keeps most
  of its warmth for many hours), and up to 12 times faster when its outer doors and windows are open or broken.
  After a power cut a warm house cools down over the following hours and days, instead of at once.
- **Warmth from the game itself** (sun, a fire, a heat source) warms an unpowered room when the game's own air there
  is warmer than the room.
- **Rooms share heat.** Open passages and open inner doors even out two rooms quickly, closed doors slowly, walls
  very slowly. Stairs join floors once someone has walked them.
- **Unvisited buildings** start at the outdoor temperature plus 2 C the first time someone enters. Only buildings
  with a player in them are simulated; when you come back, the time you were away is caught up at once (up to a
  week).
- **Player-built rooms** count when they are fully roofed. Each one is its own zone and starts like an unvisited
  building.

The mod changes the **air**. It never writes body temperature, and never changes clothing, insulation, food or
vehicles. The game warms your character from that air through its own thermoregulation (see "How you feel it" below).

## Doors, windows and barricades

Only openings in a room's outer wall let air out. How much each one lets through:

| Opening | Share |
|---|---|
| Open door | 1.00 |
| Smashed window, window with the glass removed, empty window frame | 0.85 |
| Open window | 0.70 |
| Closed door, closed window | 0 |

Barricades on a window or frame keep air in: 1 plank lets 60% through, 2 planks 40%, 3 planks 25%, 4 planks 12%, a
metal sheet 5%, metal bars 30%. Barricades on both sides multiply. Barricades on doors do not count. A room's leaks are
added up and capped at 1 (fully open).

## How you feel it

- **Warm rooms:** when your room is more than 0.25 C warmer than the game's own air, the mod places a small game heat
  source on your square (the "native bridge"), so the game's air there matches the room and your character feels
  it. This is the option "Feed retained warmth to vanilla climate".
- **Cold rooms:** the game's heat sources can only warm, not cool. A room colder than the game's own air does not
  chill your character by itself. With **Extensive Health Redone**, its heat and cold meters read the room air from
  this mod, so cold rooms count there.
- **The temperature you see:** mods that show the air (Extensive Health Redone, Lua Digital Watch UI) show the room's
  temperature, including the devices near you.
- Outdoors, the game's own air applies; what other mods read still includes the devices near you. In a vehicle, Lua
  Digital Watch UI shows its own reading again.

## Devices

Four devices, with the original's items, models and figures.

| Device | Item ID | Power | Reach | Effect at the device |
|---|---|---|---|---|
| Cheap Heater | `IndoorClimateLite.ElectricHeater` | grid or generator | 6 tiles | +12 C |
| Premium Heater | `IndoorClimateLite.PremiumHeater` | grid or generator | 12 tiles | lifts the air toward 25 C |
| Standing Fan | `IndoorClimateLite.StandingFan` | grid or generator | 8 tiles | -10 C |
| Propane Heater | `IndoorClimateLite.PropaneHeater` | a propane tank | 10 tiles | lifts the air toward 25 C |

- **Placing:** right-click the device in your inventory and choose **Install ...**. It goes down like any other item
  you place on the ground. A favourite item cannot be placed.
- **Switching:** right-click the placed device and choose **Turn On** or **Turn Off**. You have to be within 3 tiles,
  on the same floor; from further away the menu still shows, but nothing happens. The option is greyed out, with the
  reason, when the device cannot run.
- **Electric devices** run on a generator, or on the grid when they stand in a room. They switch off by themselves
  when the power goes. With the grid off, each one draws on the nearest running generator within 20 tiles and 3
  floors: a heater 0.04 L/h (Heater generator fuel use), the fan 0.20 L/h. The generator's info window lists the
  devices it powers and adds their draw to the total. A generator that runs dry switches off with its devices.
- **The propane heater** uses a vanilla propane tank. Its menu shows the tank's fill and lets you insert a tank from
  your inventory, replace it (the old tank comes back with what was left in it) or remove it. It burns 0.025 of a
  tank an hour, so a full tank lasts 40 game hours, and switches off when the tank is empty.
- **How the warmth spreads:** a device changes the air on its own floor within its reach, strongest at the device and
  fading in a straight line to nothing at the edge of its reach. Cheap heaters and fans add up, at most +16 C or
  -20 C in all. Of the premium and propane heaters only the strongest lift counts, and it comes on top. A leaking
  room weakens a device: in a fully open room only a quarter of its effect is left (Powered-room breach influence).
- **Heaters warm you, not the room.** A device changes the air you feel near it. The room's own temperature, which
  the rest of the building shares, is not changed by it. Switch it off or walk away and you are back to the room.
- Heaters (not the fan) also place a game heat source, so the game's own air near them warms.
- A device switched on, picked up and put down again comes back switched off.

**Where to find them:** appliance and electronics stores are the best source, then Gigamart electronics and
housewares, garages, and (rarely) closet shelves in homes. Propane heaters also turn up in camping stores and propane
and camping crates. Warehouses and storage units have an extra roll per container (15% and 17%, times the "other
loot" setting).

## Multiplayer

- The server runs the simulation and keeps the rooms. Every player in the same room sees the same temperature, and a
  server-side mod reads the same value the player's client shows.
- Each player is sent their own room's temperature only, when it changes by 0.2 C or more, when they change room, and
  at least every 30 seconds.
- In Build 42.21 the game works out body warmth on the server. The mod therefore places its heat sources (the bridge
  and the heaters) on the server as well as on the clients, so the warmth you feel matches what you see.
- Device state is kept by the server. Your client sends the menu choice; the server checks it and tells every client.

Single player runs the same code in one game.

## Sandbox options

Under **Indoor Climate** in the sandbox settings. The names are the original's, so existing server configs carry
over.

| Option | Default | Range | What it does |
|---|---|---|---|
| Enable indoor climate simulation | on | | Switches the mod off when unticked. It also stays off while Realistic Temperature is enabled. |
| Simulation interval (in-game minutes) | 1 | 1 to 60 | How often an occupied building is updated. A larger value costs less; the temperatures come out about the same. |
| Unvisited building temperature buffer (C) | 2 | 0 to 10 | An unvisited building starts at the outdoor air plus this. |
| Heater generator fuel use (L/h) | 0.04 | 0 to 0.25 | Generator fuel for each switched-on electric heater. The fan always uses 0.20 L/h. |
| Powered building target (C) | 22 | 22 to 27 | The temperature a room with grid power heads for. |
| Powered heating response per hour | 3 | 0.1 to 10 | How fast a powered room reaches the target. |
| Powered-room breach influence | 0.75 | 0 to 1 | How much open doors and windows pull a powered room toward the outdoor air, and how much they weaken devices. |
| Sealed room heat-loss rate per hour | 0.06 | 0.005 to 0.5 | How fast a closed, unpowered room drifts toward the outdoor air. |
| Open door/window heat-loss multiplier | 12 | 1 to 30 | How much faster a fully open room loses heat. |
| Door/window scan radius | 5 | 2 to 10 | The squares around a player checked for doors and windows while the scan of their building or player-built room is not finished yet. |
| Feed retained warmth to vanilla climate | on | | The native bridge (see "How you feel it"). |
| Debug logging | off | | One line per player and update, and the simulation's cost once an hour, in the log (the server's, in multiplayer). |

## For other mods

The global `IndoorClimateLite` table answers what the room air is for a player or a square. See
[api.md](api.md).
