# Forever Dungeon Routes

Routes, boss order and notes for the classic dungeons, drawn on the world map of
**World of Warcraft: Forever**. Pick a ready route, tick off bosses during the run, or draw your
own route on the map and share it as text.

## Requirements

WoW: Forever has no dungeon map art of its own. Forever Dungeon Routes draws on top of the dungeon
maps that another addon provides, for example **MapUtils**. Without such an addon the routes cannot
be shown, and the addon says so once when you enter a dungeon.

## Install

1. Download `ForeverDungeonRoutes-<version>.zip` from the [releases](../../releases).
2. Unzip it into `World of Warcraft\<Forever folder>\Interface\AddOns\`. The folder must be named
   `ForeverDungeonRoutes`.
3. Make sure MapUtils (or another addon with dungeon maps) is enabled.

## Use

- Open the world map inside a dungeon, or browse to a dungeon map. The route appears as a line whose
  color runs from the entrance to the last boss, with arrows in walking direction.
- Numbered pins mark the bosses in route order, `R` marks rares, `+` optional bosses, `!` notes.
  Blue squares switch to the next map level.
- The panel in the top right corner lists the stops. Click a stop to tick it off, shift-click to
  show it on the map. "New run" clears the checkmarks.
- Click the route name to choose a route, create a new one, copy, rename, delete, export or import.

Stratholme and Dire Maul North come with two standard routes each (living and undead side, full
clear and tribute run).

## Own routes

"Edit" on a standard route creates a copy, the standard route itself stays unchanged.
While editing:

- **Path / Side path**: left-click adds a point, right-click removes the last one, shift-click
  starts a new piece, ctrl-click selects an existing piece.
- **Stop**: left-click places a stop. On a stop: click for options (rename, note, kind, order),
  drag to move, right-click to delete.
- **Note**: left-click places a note. On a note: click to edit, drag to move, right-click to delete.
- **Undo** reverts the last change, **Done** ends editing.

Dungeons without a standard route, for example the new dungeons of WoW: Forever, work the same way:
open the dungeon map and choose "New route".

## Commands

`/fdr` toggles the routes on the map, `/fdr panel` the panel, `/fdr reset` clears the checkmarks,
`/fdr map` prints the current map IDs.

## Dungeons with a standard route

Ragefire Chasm, The Deadmines, Wailing Caverns, Shadowfang Keep, Blackfathom Deeps, The Stockade,
Razorfen Kraul, Gnomeregan, Scarlet Monastery (Graveyard, Library, Armory, Cathedral),
Razorfen Downs, Uldaman, Zul'Farrak, Blackrock Depths, Lower Blackrock Spire, Dire Maul (East,
West, North), Stratholme.

## Credits

The standard routes were traced from the dungeon walkthrough maps of aetherflask.com, which went
offline in 2022 and are mirrored at [eintr.net](https://eintr.net/WoW/World-of-Warcraft-Classic-Dungeon-Walkthrough.html).
The addon ships no map art; the dungeon maps come from the map addon you use.

## License

MIT, see [LICENSE](LICENSE).
