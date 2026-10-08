# Changelog

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
