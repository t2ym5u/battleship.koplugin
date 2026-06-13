# battleship.koplugin

A Battleship Puzzle (Solitaire Battleships) plugin for [KOReader](https://github.com/koreader/koreader).


## Screenshot

*(Screenshot to be added.)*

## Rules

Find the hidden fleet in the grid. Row and column clues show the total number of ship segments in each line. Ships are placed horizontally or vertically and cannot touch each other (even diagonally).

## Concept

Solitaire Battleships (also called Bimaru) is a logic puzzle version of the
classic Battleship game. A fleet is hidden in a grid; row and column clues show
how many ship segments are in each line. Deduce the exact position of every ship
using logic alone — no guessing required.

The fleet typically consists of: 1 battleship (4), 2 cruisers (3), 3 destroyers (2),
4 submarines (1).

## Features

- **Multiple grid sizes** — 8×8 (classic), 10×10 (extended)
- **Three difficulty levels** — Easy (more revealed cells), Medium, Hard
- **Cell states** — water, ship segment (with automatic edge/corner detection)
- **Row/column counter** — remaining segments shown and updated in real time
- **Auto-water** — automatically fills water around completed rows/columns
- **Check** — highlights contradictions with the clue counts
- **Reveal solution** — shows the full solution
- **Undo** — step back through your moves
- **Auto-save** — game state saved and restored on next launch

## Controls

| Action | How |
|--------|-----|
| Place a ship segment | Tap a cell (in ship mode) |
| Mark as water | Tap a cell (in water mode) or long-press |
| Toggle ship / water mode | Tap the **Ship / Water** button |
| Undo last move | Tap **Undo** |
| Check progress | Tap **Check** |
| New game | Tap **New game** |
| Change difficulty | Tap **Diff** |
| Show rules | Tap **Rules** |

## Why e-ink friendly?

Each tap places or removes a single cell marking. The grid is fully static
between moves — ideal for e-ink partial refresh.

## License

GPL-3.0
