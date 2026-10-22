# Known limitations

What Indoor Climate Redone does not do, or does differently from what you might expect. Most of these are the
original mod's behaviour, kept on purpose so the gameplay stays the same. Where a limit is new, it says so.

## Devices

- **Devices change the air you feel, not the room.** A heater or fan changes the air near it for the player standing
  there (and what other mods read for that player). The room's own temperature, which the rest of the building shares
  and keeps after you leave, is not changed by it. A heater left on in an empty house does not warm the house.
- **Their reach ignores walls.** A device reaches every square on its own floor within its radius, measured in a
  straight line, through walls and into the next room or outdoors. It does not reach other floors.
- **A device that is picked up comes back off.** A device switched on, picked up and put down again is off, wherever
  it is put down. The original left it on. This one is a change.
- **Grid-powered devices must stand in a room.** On grid power, an electric device runs only on a square inside a
  room. Outdoors it needs a generator.
- **Generators power devices, not rooms.** A generator keeps the devices near it running. It does not make the
  building's rooms head for the powered target; only grid power does.

## Rooms

- **Cold rooms are invisible to the game without Extensive Health Redone.** The game's heat sources can only warm.
  The mod raises the game's air when a room is warmer than it, but cannot lower it when a room is colder. Cold rooms,
  and the fan's cooling, reach your character only through mods that read this mod's room air, such as Extensive
  Health Redone's heat and cold meters.
- **Player-built rooms are simple.** Each roofed player-built room is its own zone. It shares no heat through walls
  or doors with the next one.
- **Rebuilt player-built rooms forget their temperature.** The game can give a player-built room a new identity when
  part of it is rebuilt. The room then starts again like an unvisited building, at the outdoor air plus the buffer.
- **Empty buildings stand still.** Only buildings with a player in them are simulated. The time missed is caught up
  when someone comes back, up to a week; a building left alone for longer is treated as if a week had passed.
- **Stairs join floors once used.** Two floors of a building share heat only after someone has walked between
  them.
- **Saved buildings are capped.** The world keeps the temperatures of up to 1,024 buildings and player-built rooms.
  When there are more, the ones not seen for the longest time are dropped and start again as unvisited.

## Multiplayer

- **A client knows only its own room.** A mod on a client that asks for the temperature of another square gets the
  game's own air there, unless the square is in the room the player is in. On the server and in single player every
  room with a saved temperature is known. This one is new: the original worked out rooms on each client.
- **Old saves:** the original kept rooms per player. The first time a player is seen, the building temperatures the
  original saved in their data are taken over for every building that has none yet. Player-built rooms are not taken
  over: their identities differ between a server and its clients, so they start again. This one is new.
