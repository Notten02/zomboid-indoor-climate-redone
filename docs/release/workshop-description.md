# Steam Workshop page text

The description of the Steam Workshop item, in Steam BBCode: everything between the two `PASTE` lines.

---

----- PASTE FROM HERE -----
[h1]Indoor Climate Redone[/h1]
Room air temperature for Project Zomboid Build 42. Buildings hold heat, open doors and broken windows let it out, a power cut lets a warm house cool down over hours, and placeable heaters and a fan change the air near them.

A from-scratch rewrite of [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3772549209]Indoor Climate (EHR Addon)[/url] by [b]Frozen_Heart[/b], the original author. The gameplay follows the original; the code is new, open source (MIT), and the server runs the simulation, so it works in multiplayer.

Back up your saves before switching, and report what you find.
[b]Do not enable it together with the original.[/b] See "Switching from the original".

[h2]Credits[/h2]
The design, the devices, their models, textures and icons, the sandbox options and the English and Russian texts come from Frozen_Heart's mod. They stay credited to Frozen_Heart and are not relicensed.
[quote=Frozen_Heart]Feel free to modify, fix, edit, whatever. I don't own these mods, the community does. The only thing I ask is that you credit me as the original author[/quote]

[h2]What it does[/h2]
[list]
[*]Every room of a building has its own temperature, saved with the world.
[*]With grid power, rooms head for 22 C. Without it, they drift toward the outdoor air: slowly while sealed, up to 12 times faster with outer doors and windows open or broken. Barricades cut the leak; a metal sheet nearly seals a window.
[*]Heat moves between rooms through passages, open and closed doors, walls and stairs.
[*]Unvisited buildings start at the outdoor temperature plus 2 C. Only buildings with a player in them are simulated; the time you were away is caught up when you return.
[*]Vanilla buildings, several floors, and roofed player-built rooms.
[*]Warm rooms warm your character through the game's own air. The mod never writes body temperature and does not touch clothing, insulation, food or vehicles.
[*]Simulation speed, heat loss, leaks and more in the sandbox options (page "Indoor Climate").
[/list]

[h2]Devices[/h2]
[list]
[*][b]Cheap Heater:[/b] electric, 6-tile reach, +12 C at the heater.
[*][b]Premium Heater:[/b] electric, 12-tile reach, lifts the air toward 25 C.
[*][b]Standing Fan:[/b] electric, 8-tile reach, -10 C at the fan.
[*][b]Propane Heater:[/b] 10-tile reach, lifts the air toward 25 C. Runs on a vanilla propane tank (about 40 hours a tank); insert, replace or remove tanks from its menu.
[/list]
Right-click a device in your inventory to install it, then right-click it to turn it on. Electric devices need grid power (inside a room) or a generator, switch off when the power goes, and add to a generator's fuel use (heaters 0.04 L/h, the fan 0.20 L/h). Find them in appliance and electronics stores, Gigamart, garages, warehouses and storage units; propane heaters also in camping stores and crates.
A device changes the air you feel near it, not the room's own temperature, and its reach goes through walls on its floor.

[h2]Multiplayer[/h2]
[list]
[*]The server runs the simulation. Everyone in a room sees the same temperature, and the server saves it with the world.
[*]Each player is sent only their own room's temperature.
[*]Build 42.21 works out body warmth on the server, so the mod places its heat sources there as well as on the clients.
[*]Device state is kept by the server.
[/list]

[h2]Requirements and compatibility[/h2]
[list]
[*]Build 42.21 or newer. No other mod needed. Load order does not matter.
[*][url=<EHR_REDONE_URL>]Extensive Health Redone[/url] (optional, recommended): its heat and cold meters read the room air, also on a dedicated server. That is how cold rooms and the fan reach your character; the game alone can only feel warm rooms.
[*][b]Lua Digital Watch UI[/b]: the watch shows the room air.
[*][b]Unseasonal Weather[/b]: its clock shows the room air.
[*][b]Realistic Temperature[/b]: not compatible. While it is enabled, this mod does not simulate rooms.
[*]Extensive Health Rework Evolved: reads the same API, not tested.
[*]Other mods can read the room air through the global IndoorClimateLite API, as with the original.
[/list]

[h2]Switching from the original[/h2]
Back up your save, disable Indoor Climate (EHR Addon), enable this one. Servers: change IndoorClimateLiteB42 to IndoorClimateRedone in Mods= and 3772549209 to <WORKSHOP_ID> in WorkshopItems=.
[list]
[*]Kept: item IDs, placed devices (on or off, propane tank), every sandbox option, and the temperatures of map buildings.
[*]Player-built rooms start again.
[*]Changed: the server runs the simulation; a device picked up while on comes back off; the load order no longer matters.
[/list]

[h2]Known limitations[/h2]
[list]
[*]Without Extensive Health Redone, rooms colder than the game's own air, and the fan, do not chill your character.
[*]Devices warm or cool the air near them, not the room, and their reach ignores walls.
[*]Each player-built room is its own zone, and a rebuilt one forgets its temperature.
[*]Generators power devices, not rooms.
[/list]
Full list, changes from the original and the API: [url=https://github.com/Notten02/zomboid-indoor-climate-redone]GitHub[/url].

[h2]Bugs, source, licence[/h2]
Report bugs with your console.txt at [url=https://github.com/Notten02/zomboid-indoor-climate-redone/issues]GitHub issues[/url]. Code: MIT. Models, textures, icons, item scripts and texts: credited to Frozen_Heart, not relicensed; see ASSETS.md in the repository.

Mod ID: IndoorClimateRedone
----- PASTE TO HERE -----
