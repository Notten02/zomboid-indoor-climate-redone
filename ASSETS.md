# Assets and credits

Indoor Climate Redone is a rewrite. Its **code** is new and MIT-licensed (see `LICENSE`). Its **content** comes from
the mod it continues. That content is credited to its author below and is **not** relicensed under MIT.

## Origin

| Mod | Author | Workshop | Mod ID |
|---|---|---|---|
| Indoor Climate (EHR Addon), shown in game as Indoor Climate Lite (v0.12.2) | Frozen_Heart | [3772549209](https://steamcommunity.com/sharedfiles/filedetails/?id=3772549209) | `IndoorClimateLiteB42` |

The original files don't record who made each model and texture. They are credited here as supplied by the original
mod. If the original author asks, they will be replaced.

## Permission

The original author opened the mod for others to continue. Their Workshop page says: *"Feel free to modify, fix, edit,
whatever. I don't own these mods, the community does. The only thing I ask is that you credit me as the original
author."*

## What was reused

Every file taken from the original mod is listed here, with any change made on import.

| Content | Location in this repo | Count | Change on import |
|---|---|---|---|
| Device models (`Heater2`, `PremiumHeater`, `PropaneHeater`, `StandingFan`) | `Contents/mods/IndoorClimateRedone/common/media/models_X/IndoorClimateLite/*.fbx` | 4 | none |
| Device model textures (same four names) | `Contents/mods/IndoorClimateRedone/common/media/textures/IndoorClimateLite/*.png` | 4 | none |
| Item icons (`Item_CheapHeater`, `Item_PremiumHeater`, `Item_PropaneHeater`, `Item_StandingFan`) | `Contents/mods/IndoorClimateRedone/common/media/textures/Item_*.png` | 4 | none |
| Item and model scripts (module `IndoorClimateLite`) | `Contents/mods/IndoorClimateRedone/42/media/scripts/IndoorClimateRedone/indoorclimate_items.txt`, `indoorclimate_models.txt` | 2 | renamed from `icl_heater_items.txt` and `icl_heater_models.txt`; content unchanged |
| English and Russian translations (`ContextMenu`, `ItemName`, `Sandbox`, `UI`) | `Contents/mods/IndoorClimateRedone/42/media/lua/shared/Translate/{EN,RU}/*.json` | 8 | Russian files reformatted (same texts). `Sandbox.json`, in both languages: the title text `Sandbox_IndoorClimateLite` names this mod (the sandbox page itself is still called Indoor Climate), six tooltips have a sentence added about how this mod behaves, and two of them (generator fuel use, debug logging) are also reworded. The other texts are unchanged |
| The Workshop page text and the mod's `README.md` | `docs/original-author-guides/workshop-description.md`, `mod-readme.md` | 2 | archived word for word under a header saying where they come from; the README's headings moved down one level |

The original also ships a copy of each item icon as `textures/IndoorClimateLite/Icon_*.png`, its two UI texts a
second time in the older `UI_EN.txt` / `UI_RU.txt` form, and a `language.txt` per language. Nothing refers to those
files, so they were left out.

The mod's icon, poster and Workshop preview are not taken from the original. They are new, drawn by
`tools/make-release-art.py`, and are covered by the MIT licence with the code.

The sandbox option names, ranges and defaults, the room and device figures and the loot weights are the original's
too; the code that uses them is new.
