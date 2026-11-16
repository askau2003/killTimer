# killTimer

A World of Warcraft addon for Forever. It overlays kill count, elapsed time, and quest-item
drop-% while leveling, and logs a summary each time RestedXP's leveling step changes.

## Installation

1. Download this repository (via `Code > Download ZIP` on GitHub, or `git clone`).
2. Copy (or symlink) the folder into your AddOns directory, named exactly `killTimer`:
   ```
   World of Warcraft/_forever_/Interface/AddOns/killTimer/
   ```
   The folder must directly contain `killTimer.toc` and `killTimer.lua`.
3. Restart the client, or `/reload` if it's already running.
4. Make sure the addon is enabled in the character-select AddOns list.

## Usage

- A small draggable overlay appears on screen showing elapsed time, kill count, and any
  quest items looted so far (with drop-% once more than one mob has dropped it).
- `/killtimer` resets the overlay and its counters manually.
- With [RestedXP](https://www.restedxp.com/) installed, the overlay resets automatically
  whenever RestedXP's leveling step changes, and a summary is printed to chat and saved to
  `killTimerLog` (per character). Without RestedXP, the overlay just runs continuously.

## Requirements

- World of Warcraft: Forever.
- RestedXP is optional — without it, step-based resets and logging don't happen, but the
  live overlay still works.
