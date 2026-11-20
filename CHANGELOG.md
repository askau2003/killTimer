# Changelog

All notable changes to this addon are documented here. Versions correspond to
the `## Version` field in `killTimer.toc` and to GitHub release tags.

## [1.7] - 2026-11-20

### Added
- Each quest objective line now shows how long you have spent working on it,
  next to its progress.
- `/killtimer log` prints the most recent logged step results back into chat.
  The log is kept per character and now holds the last 200 entries - it used
  to grow for the lifetime of the character with no way to read it back.

### Changed
- An open quest objective now keeps its kill count, mob breakdown and time
  across RestedXP step changes instead of being reset at every step boundary -
  RestedXP often asks you to kill or loot something "on the way" over several
  steps of the same quest. Its result is printed to chat when the objective
  actually leaves your quest log (turned in or abandoned) rather than at every
  step change, which also stops the same kills being repeated in entry after
  entry.
- The clock is now time spent working rather than wall-clock: it only runs
  while you are on a step the line below it is about, so walking to a turn-in,
  taking a flight path or doing an unrelated step no longer inflates it.
- Item-farming kills group on a shared family word instead of any shared word,
  so "Mangy Wolf" and "Mangy Jaguar" stay apart while "Dreaming Whelp" and
  "Adolescent Whelp" still group under "Whelp". A group holding a single mob
  type is now labelled with its full name instead of just its first word, and
  a name's punctuation no longer prevents a match ("Kolkar's" and "Kolkar").

### Fixed
- A mob that counts towards two quests at once was added to the kill total
  once per quest, so a single kill read as two.
- A mob killed for an item drop in the same moment as a quest-objective kill
  was dropped from the counts entirely.
- A quest item that is not of Blizzard's "Quest" item class - plenty of
  collection quests ask for a trade good or a plain junk item - was shown at
  0% forever while it was in fact being looted.
- A quest-item goal that had not dropped yet was forgotten as soon as the
  current step stopped naming it, losing exactly the long dry streak that is
  worth tracking.
- A drop counted whenever the last thing looted had been a corpse, so a quest
  item received well afterwards, or from a chest, could be counted as a drop.
- Quest progress that arrives without a kill message - a grey mob, or any kill
  at the level cap - was credited to whatever died last, even if that was
  minutes earlier. It is listed as Unknown instead, and still counted.
- An objective's work time could sit at 0:00 for an entire farm when
  RestedXP's step wording didn't match the quest log's; objectives are now
  matched by quest ID, and recent progress keeps the clock running on its own.
- The overlay rebuilt its quest-log data several times per update, five times
  a second, where once per update is enough.

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
