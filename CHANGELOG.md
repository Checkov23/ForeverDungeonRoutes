# Changelog

## 0.5.7

- The way to the dungeon: outside a dungeon its entrance stands above the stop list ("Entrance:
  Westfall"). A click sets a map pin there that the game tracks, so the arrow on the screen leads
  to the entrance. Also `/fdr way`. The positions come from the game: WoW: Forever's own map points
  where it has them (Wailing Caverns, Uldaman, Maraudon, Temple, Scholomance), else Blizzard's table
  of dungeon entrances.
- Dungeons for your level: in the dungeon list the names are coloured by your level like quests
  (red too high, orange a bit high, green fitting, grey easy), the level above the stop list too.
- Run time: the clock starts when you enter the dungeon and stops at the last boss. The time and
  your best time per dungeon stand above the stop list, and the chat tells a new best time.
  "New run" starts the clock again.
- Small display in dungeons (gear button, off by default): a small movable box with the dungeon,
  bosses down, run time, the next boss and the room you are in, for when the map stays closed. A
  click opens the map.
- The route menu has a "Share" submenu: send to the group, send to the guild (new), post the boss
  order in the group chat as plain text for players without the addon (new; outside a group only
  you see it), export.
- Seven more languages: French, Spanish, Portuguese, Russian, Korean and Chinese (simplified and
  traditional). Names of bosses, dungeons, map levels and rooms come from the game in every
  language; the addon's own texts are translated, corrections are welcome. Notes on the maps stay
  English (German in the German client).
- Boss names in Russian, Korean and Chinese link a stop to its boss and tick it off (letters
  beyond the Latin alphabet were ignored when comparing names).

## 0.5.6

- Where you are, as well as the game allows: inside dungeons WoW gives addons no position, but
  it names the room you are in (the subzone, like the text above the minimap). The addon now
  knows where these rooms lie, taken from the game's own building files: the room lights up on
  the map, its name stands below ("You are in: Mast Room"), and the map follows you to its
  level. Between named rooms and in dungeons without them the map follows your boss kills.
- Rooms come with all dungeons except Shadowfang Keep, The Stockade, Razorfen Kraul, Zul'Farrak and
  Dire Maul (there only the entrance of East and West): the game names no rooms there.
- Scarlet Monastery: the first named room tells the wing, before the first boss.
- The crosshair button shows where you are: your room, else the next open boss.
- `/fdr pos` also prints the room text of the game and the room the addon recognized.
- Copyright: the settings menu ends with version and copyright, the download now contains the
  license (LICENSE.txt).

## 0.5.5

- The minimap ping experiment of 0.5.4 is gone again. Inside dungeons WoW: Forever reports the
  position of a minimap ping as 0, 0, also for pings you click yourself, so it cannot show where
  you stand. Its setting is removed from your saved settings. Inside dungeons the map follows
  your boss kills as in 0.5.3.

## 0.5.4

- Experiment: your own position inside dungeons through a minimap ping. Off by default, switch
  it on behind the gear button. When you enter a dungeon the addon pings the minimap once (your
  group sees it) and then follows that ping, so your arrow walks with you. Ctrl-click on the map
  sets your position by hand. If the game does not play along, the addon says so and stops.

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
