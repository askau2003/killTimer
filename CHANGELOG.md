# Changelog

All notable changes to this addon are documented here. Versions correspond to
the `## Version` field in `killTimer.toc` and to GitHub release tags.

## [1.6] - 2026-11-18

### Changed
- Pure item-farming kills are now grouped by any word shared with another
  already-seen mob, not just the first word - e.g. "Dreaming Whelp" and
  "Adolescent Whelp" now group together under "Whelp" instead of staying
  split apart by their differing first word.

## [1.5] - 2026-11-18

### Fixed
- Pure item-farming (e.g. a "loot X Charms" quest with no kill-count
  objective) only disabled monster-objective grouping for the current
  RestedXP step, not the whole quest log - an unrelated item quest sitting
  elsewhere no longer turns off mob filtering on other steps.
- A step that tracks both a "kill X" quest objective and a separate item drop
  no longer loses the monster-objective grouping (e.g. every Centaur variant)
  to the item-farming fallback - both are credited correctly.

### Added
- Pure item-farming kills with no Blizzard kill-count objective (e.g. every
  Kolkar variant while farming Crude Charms) are now grouped by the mob
  name's first word into one summary line, with the individual mob counts
  shown in a tooltip on hover - consistent with quest-objective grouping.

## [1.4] - 2026-11-16

### Added
- Group every mob that contributes to the same "kill X" quest objective (e.g.
  every Centaur variant) into one summary line instead of one line per NPC
  name, with the individual mob counts shown in a tooltip on hover.
- Remember the overlay's dragged screen position across `/reload` and relog -
  previously only scale, width, height and the lock setting were saved.

### Fixed
- The panel no longer renders at the wrong scale/size right after login until
  a slider in Settings is touched - `SetScale`/`SetSize` are now reapplied
  once after the UI's first layout pass.
- The Options panel's sliders and lock checkbox now reflect the saved values
  every time the panel is reopened, instead of only on the very first load.
- Dragging the panel from inside its body (the kill/quest list area) stopped
  working once hover tooltips were added - that area now forwards drags to
  the panel instead of swallowing the click.

## [1.3] - 2026-11-16

### Added
- Copy-to-clipboard popup for sharing kill/time/loot stats.

## [1.2] - 2026-11-16

### Added
- Settings > AddOns > killTimer panel: Scale, Width and Height sliders, a
  Lock position checkbox, and a Reset position button.

### Changed
- The overlay is now a fixed size instead of auto-sizing to its content.

## [1.1] - 2026-11-16

### Added
- Initial release: live kill count, elapsed time, and quest-item drop-% overlay
  while leveling.
- RestedXP step-change integration - resets and logs a chat summary each time
  the active guide step changes.
- Redesigned overlay with a title, a larger header for time/kills, and an
  auto-sizing panel.
