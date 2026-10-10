# Changelog

## 0.5.3

- Fixed a Lua error when the mouse rests on the route button or on "New run" (issue #1).
- Button at the minimap: a click shows or hides the map, dragging moves it around the minimap.
  It can be switched off behind the gear button.
- WoW gives addons no position inside dungeons (since patch 7.1), so the arrow for you and your
  group could never show there. Instead the map now follows your run: after a boss kill it shows
  the level of the next open boss, and it opens there. The crosshair button shows the next open
  boss. The setting "Show my position and group" and the hint on the map are gone.
- Scarlet Monastery and Dire Maul: a boss kill tells which wing you are in.

## 0.5.2

- Share routes with your group in game: "Send to group" in the route menu or `/fdr send`. Group
  members with the addon are asked whether to take the route over; a route they already have is
  not added twice. Standard routes travel as a short hint, own routes in pieces of at most 255
  characters. Sending waits while the game holds addon messages back (boss fights).
- Imported routes (text or group) lose the "|" character in names and notes, so they cannot bring
  colour codes, links or pictures along.

## 0.5.1

- Hints in the tooltips and in the editor toolbar stand on separate lines. They were separated by
  the "|" character, which is a control character in WoW texts.
- README: preview images of the map window.

## 0.5.0

- Bosses tick themselves off: when the game reports a boss kill, its stop gets the checkmark. Rares
  without a boss fight stay manual. Can be switched off behind the gear button.
- Standard routes for the last three dungeons: Maraudon (purple and orange side, both to the
  Princess), Temple of Atal'Hakkar and Scholomance. All 24 classic dungeons now have a route.
- Boss names in the language of the game client, taken from the game's own boss list.
- Editor: a stop named like a boss of the dungeon is linked to it; the stop menu has "Boss in the
  game" to link it by hand. Shared routes keep the link.
- Scholomance: the stairs between the map levels are clickable on the map.
- Fixed boss names: Wolf Master Nandos, Grimlok, The Lost Dwarves.

## 0.4.0

The map moves into its own window and no longer needs a map addon.

- Own map window in the spirit of Mythic Dungeon Tools: dungeon and map level in the header, the map
  on the left, the stops on the right. Size and position can be changed, settings sit behind the
  gear button.
- The dungeon maps are the game's own map art, drawn by the addon. WoW: Forever has no dungeon maps
  in its map tables, so 0.3.0 could not show the routes without MapUtils; MapUtils is no longer
  needed.
- Your position as an arrow and your group as dots, where the game reveals them. Inside a dungeon
  the map follows you to the next map level; the crosshair button brings it back after browsing.
- Scarlet Monastery and Dire Maul: the wing is recognized by position.
- Zoom with the mouse wheel, move by dragging, right-click zooms out.
- Key binding (section AddOns) and an entry in the addon list at the minimap.
- Optional: open the map automatically when entering a dungeon.
- `/fdr` now opens and closes the map; `/fdr pos` prints the position data for bug reports.
- Dire Maul North uses one map level instead of two identical ones.
- Imported routes keep only what lies on the levels of their dungeon.
- Safe with the secret values of restricted instances (no errors, no guessing).

## 0.3.0

First public test version for the WoW: Forever beta.

- Routes on the world map for 21 classic dungeons, drawn on top of the dungeon maps of a map addon
  such as MapUtils. Color runs from the entrance to the last boss, arrows show the walking direction.
- Numbered boss pins in route order, rares and optional bosses, notes from the original maps
  (keys, events, quest items). Link pins switch to the next map level.
- Panel on the world map with the stops of the route and checkmarks per character. "New run" clears
  them, an old run is cleared automatically after three hours.
- Stratholme (living and undead side) and Dire Maul North (full clear and tribute run) have two
  standard routes each.
- Route editor: paths, side paths, stops and notes, drag to move, undo. Editing a standard route
  creates a copy.
- Export and import of routes as text.
- Own routes also for dungeons without a standard route, including the new Forever dungeons.
- English and German.
