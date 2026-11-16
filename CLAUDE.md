# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

- All comments must be written in English.
- Testing: copy `killTimer.lua` to the AddOns folder at
  `/home/aslss/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/killTimer/killTimer.lua`,
  then the user reloads the game (`/reload`) to pick up the change.
- Keep `CHANGELOG.md` up to date: add an entry for every version bump, in the same commit
  as the bump. Bump `## Version` in `killTimer.toc` to match. When cutting a GitHub release,
  reuse that changelog entry as the release notes.
