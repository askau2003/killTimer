# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

- All comments must be written in English.
- Testing: after every edit to `killTimer.lua`, immediately copy it to the AddOns folder at
  `/home/aslss/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/killTimer/killTimer.lua`
  without being asked - then tell the user it's ready for them to `/reload`.
- Keep `CHANGELOG.md` up to date: add an entry for every version bump, in the same commit
  as the bump. Bump `## Version` in `killTimer.toc` to match. Pushing a `v*` tag triggers
  `.github/workflows/release.yml`, which packages the addon into a zip and creates the
  GitHub release automatically, using the `## [x.y]` section of `CHANGELOG.md` matching the
  tag as the release notes - so that section must already exist before the tag is pushed.
- Never skip a version number in `CHANGELOG.md` or GitHub releases - every bumped version
  gets its own changelog entry and its own tagged release, even if that version was never
  previously published.
- The user always tests a change in-game first, before bumping the version or touching
  `CHANGELOG.md`. Don't bump the version or update the changelog right after an edit -
  wait for the user to confirm the in-game test passed.
- After every edit to `killTimer.lua`, `killTimerOptions.lua` or `tests/`, run
  `lua5.1 tests/run.lua` and `luacheck .` before reporting the change as done. The tests
  stub the WoW API (`tests/wow_api.lua`) and drive the addon headless; a behaviour change
  belongs in `tests/killtimer_spec.lua` in the same commit. This never replaces the
  in-game test above - it only catches what's checkable outside the client.
