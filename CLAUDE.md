# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

- All comments must be written in English.
- Testing: copy `killTimer.lua` to the AddOns folder at
  `/home/aslss/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/killTimer/killTimer.lua`,
  then the user reloads the game (`/reload`) to pick up the change.
- Keep `CHANGELOG.md` up to date: add an entry for every version bump, in the same commit
  as the bump. Bump `## Version` in `killTimer.toc` to match. When cutting a GitHub release,
  reuse that changelog entry as the release notes.
- Never skip a version number in `CHANGELOG.md` or GitHub releases - every bumped version
  gets its own changelog entry and its own tagged release, even if that version was never
  previously published. GitHub's release list sorts by each release's creation time, not
  by the tag it points to or by semver, so when releases are created/recreated out of
  version order, recreate ALL of them (oldest version first, with a short delay between
  each) so the displayed order still matches version order.
