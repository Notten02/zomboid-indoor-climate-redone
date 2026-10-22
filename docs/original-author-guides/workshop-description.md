# Workshop description (Indoor Climate (EHR Addon))

> Workshop page description by Frozen_Heart (mod author), Workshop ID 3772549209, mod ID IndoorClimateLiteB42, v0.12.2.
> Last updated on the Workshop on 2026-08-17. Archived verbatim (Steam BBCode) on 2026-10-22, read through the public
> Steam Web API (`ISteamRemoteStorage/GetPublishedFileDetails`).
> Source: https://steamcommunity.com/sharedfiles/filedetails/?id=3772549209
>
> The first heading is the author's public permission for anyone to modify or continue the mod, on the condition that
> they are credited as the original author. The text below is theirs and is not covered by this repository's MIT
> licence. It describes the original mod, not Indoor Climate Redone; see `docs/changes-from-original.md` for the
> differences.

```text
[h1]❗❗❗I'm taking a break from modding for a while - could be 1-2 months, could be 1-2 years. Feel free to modify, fix, edit, whatever. I don't own these mods, the community does. The only thing I ask is that you credit me as the original author [/h1]

[h1]This mod is created mainly for compatibility with [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3726328119] Extensive Health Rework Evolved[/url], since [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3600401184]Realistic Temperatures[/url] mod has it's own systems that hard to make fully compatible, especially body temperature[/h1]

Just like Realistic Temperatures this mod makes indoor temperatures respond to outdoor weather. Temperature depends on central heating systems(shut's off after power goes down), the condition of the building, and open/broken/barricaded windows or doors. 

It works quite different tho and performance wise is much lighter

[h1] If you want purely indoor temps simulation it's probably better to use Realistic Temperatures mod (tho it can be quite performance heavy). 

My mod just fully compatible with EHR unlike RT [/h1]

[h1] Main Features[/h1]
[list]
[*]Separate temperatures for individual rooms within the same building.
[*]Heat gradually moves between rooms through doors, open passages, and stairways.
[*]Open or broken exterior doors and windows increase heat exchange with the outdoors.
[*]Barricaded windows still cause a small amount of leakage, but retain heat much better.
[*]After the power shuts off, buildings gradually cool down or warm up toward the outdoor temperature.
[*]Unvisited buildings begin close to the current outdoor temperature, with a configurable +2 °C buffer by default. To avoid offline simulation and keep performance high.
[*]Supports vanilla buildings, multiple floors, and roofed player-built structures.
[*]Room temperatures are preserved while moving through the building and when returning later.
[*]Adds several placeable heating and cooling devices.
[*]Simulation speed, heat loss, opening leakage, and other values can be configured through Sandbox settings.

[list]
[*]IC changes ambient air temperature only.
[*]IC does not directly overwrite the character's core temperature.
[*]IC does not modify clothing or item insulation.
[*]IC does not replace vanilla thermoregulation.
[*]IC uses room-based simulation, cached building data, and scheduled updates.
[*]IC can provide its ambient temperature data to EHR for a more complete health simulation.
[/list]

[h1]Items[/h1]
[b]Cheap Heater[/b]
A basic electric space heater with a 6-tile radius. Best suited for small rooms.

[b]Premium Heater[/b]
A powerful electric heater with a 12-tile radius. It attempts to maintain a temperature of approximately 25 °C.

[b]Standing Fan[/b]
An electric standing fan with an 8-tile radius. It can reduce the local temperature by up to 10 °C near the device.

[b]Propane Heater[/b]
A propane-powered heater with a 10-tile radius and a target temperature of approximately 25 °C. It uses vanilla propane tanks. Tanks can be inserted, removed, or replaced through the object's context menu. 

Electric devices require grid or generator power and automatically stop working after losing electricity. Devices powered by a generator add to its fuel consumption.

All devices can be found in appropriate loot locations, including electronics stores, household departments, garages, warehouses, U-Store-It facilities, camping suppliers, and residential storage. 

Electronics Stores, warehouses and U-Store-it has highest chances where you can find it.

[h1] Place this mods at the bottom of load order list [/h1]
[img]https://i.postimg.cc/Kjm7P6Vq/image.png[/img]

[h1] Build[/h1]
✅42.20
✅42.19
Multiplayer tested as one person on the server 

Workshop ID: 3772549209
Mod ID: IndoorClimateLiteB42

Workshop ID: 3772549209
Mod ID: IndoorClimateLiteB42
```
