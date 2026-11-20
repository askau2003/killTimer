-- Runs killTimer's test suite outside WoW: `lua tests/run.lua [path/to/killTimer.lua]`.
-- Exits non-zero if anything failed, so CI can gate on it.
local here = arg[0]:match("^(.*)[/\\]") or "."

dofile(here .. "/wow_api.lua")
LoadAddon(arg[1] or (here .. "/../killTimer.lua"))
dofile(here .. "/killtimer_spec.lua")

os.exit(Report() and 0 or 1)
