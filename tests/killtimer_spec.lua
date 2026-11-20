-- Regression tests for killTimer's counting, grouping, timing and logging.
-- Every case here failed on the code before the bug sweep it was written for, so
-- they describe behaviour that was actually wrong rather than just restating the
-- implementation. Run them with `lua tests/run.lua`.

Case("a kill that counts for two quests is still one kill")
QUESTS = {
    Quest(100, { MonsterObjective("0/5 Centaur", 0, 5) }),
    Quest(200, { MonsterObjective("0/5 Centaur", 0, 5) }),
}
SetStep(1, { { text = "0/5 Centaur", questId = 100 }, { questId = 200 } })
SlashReset() Tick()
Kill("Centaur Plunderer")
QUESTS[1].objectives[1].numFulfilled, QUESTS[1].objectives[1].text = 1, "1/5 Centaur"
QUESTS[2].objectives[1].numFulfilled, QUESTS[2].objectives[1].text = 1, "1/5 Centaur"
Tick()
Check("header counts it once", HeaderKills() == 1, Header())
local centaurLines = 0
for _, line in ipairs(Display()) do
    if line:find("Centaur") then centaurLines = centaurLines + 1 end
end
Check("both objectives still listed", centaurLines == 2, centaurLines)

Case("a farming kill in the same tick as an objective kill survives")
QUESTS = { Quest(100, {
    MonsterObjective("0/5 Centaur", 0, 5),
    ItemObjective("0/10 Hatefury Horn", 0, 10),
}) }
SetStep(2, { { text = "0/5 Centaur", questId = 100 }, { text = "0/10 Hatefury Horn", questId = 100 } })
SlashReset() Tick()
Kill("Mangy Wolf")
Kill("Centaur Plunderer")
QUESTS[1].objectives[1].numFulfilled, QUESTS[1].objectives[1].text = 1, "1/5 Centaur"
Tick()
Check("both kills counted", HeaderKills() == 2, Header())
Check("the objective kill is grouped", (BodyHas("Centaur")), table.concat(Display(), " | "))
Check("the farming kill is kept", LineCount("Mangy Wolf") == 1, table.concat(Display(), " | "))
Check("the objective kill is not also listed as farming",
    not BodyHas("Centaur Plunderer"), table.concat(Display(), " | "))

Case("a dry item goal carries across a step change that doesn't mention it")
QUESTS = { Quest(100, { ItemObjective("0/10 Hatefury Horn", 0, 10) }) }
SetStep(3, { { text = "0/10 Hatefury Horn", questId = 100 } })
SlashReset() Tick()
for _ = 1, 40 do Kill("Hatefury Felsworn") Tick() end
Check("the dry streak is tracked", HeaderKills() == 40 and HeaderSeconds() > 5,
    Header())
SetStep(4, { { text = "0/1 Something Else", questId = 999 } })
Tick()
Check("the goal survives", (BodyHas("Hatefury Horn")), table.concat(Display(), " | "))
Check("its kill count survives", HeaderKills() == 40, Header())

Case("the header clock measures work time, not wall-clock")
local frozen = HeaderSeconds()
for _ = 1, 400 do Tick(0.25) end
Check("frozen while on an unrelated step", HeaderSeconds() == frozen,
    HeaderSeconds() .. "s, was " .. frozen .. "s")
SetStep(3, { { text = "0/10 Hatefury Horn", questId = 100 } })
for _ = 1, 40 do Tick(0.25) end
Check("running again on the relevant step", HeaderSeconds() > frozen, HeaderSeconds())

Case("results are logged when an objective finishes, not every step change")
QUESTS = { Quest(100, { MonsterObjective("0/5 Centaur", 0, 5) }) }
SetStep(10, { { questId = 100 } })
SlashReset() Tick()
Kill("Centaur Plunderer")
QUESTS[1].objectives[1].numFulfilled, QUESTS[1].objectives[1].text = 1, "1/5 Centaur"
Tick()
killTimerLog = {}
for step = 11, 15 do SetStep(step, { { questId = 100 } }) Tick() end
Check("nothing logged while the objective is open", #killTimerLog == 0, #killTimerLog)
QUESTS = {}
SetStep(16, { { questId = 999 } })
Tick()
Check("one entry once it leaves the quest log", #killTimerLog == 1, #killTimerLog)
Check("the entry holds the finished objective",
    (killTimerLog[1].result or ""):find("Centaur") ~= nil, killTimerLog[1].result)

Case("the log is capped instead of growing for the character's lifetime")
killTimerLog = {}
for i = 1, 260 do killTimerLog[i] = { step = i, result = "x" } end
QUESTS = { Quest(100, { MonsterObjective("0/5 Centaur", 0, 5) }) }
SetStep(20, { { questId = 100 } })
SlashReset() Tick()
Kill("Centaur Plunderer")
QUESTS[1].objectives[1].numFulfilled = 1
Tick()
QUESTS = {}
SetStep(21, { { questId = 999 } })
Tick()
Check("trimmed to 200 entries", #killTimerLog == 200, #killTimerLog)
Check("the oldest entries go first", killTimerLog[1].step ~= 1, killTimerLog[1].step)

Case("quest items outside Blizzard's Quest item class still count")
ITEM_CLASS["Bear Flank"] = 7    -- Trade Goods
ITEM_CLASS["Grey Junk"] = 15    -- Miscellaneous
QUESTS = { Quest(100, { ItemObjective("0/10 Bear Flank", 0, 10) }) }
SetStep(30, { { text = "0/10 Bear Flank", questId = 100 } })
SlashReset() Tick()
Kill("Mangy Bear")
LootReady(true)
Loot("Bear Flank")
Loot("Grey Junk")
Tick()
Check("a trade good the quest asks for counts", LineCount("Bear Flank") == 1,
    table.concat(Display(), " | "))
Check("unrelated junk does not", not BodyHas("Grey Junk"), table.concat(Display(), " | "))

Case("objective progress long after the last kill isn't pinned on that mob")
QUESTS = { Quest(100, { MonsterObjective("0/5 Centaur", 0, 5) }) }
SetStep(40, { { questId = 100 } })
SlashReset() Tick()
Kill("Centaur Plunderer")
QUESTS[1].objectives[1].numFulfilled = 1
Tick()
Check("a fresh kill is credited to the mob", (TooltipHas("Centaur Plunderer")),
    table.concat(Tooltip(), " | "))
for _ = 1, 200 do Tick(0.25) end
QUESTS[1].objectives[1].numFulfilled = 2
Tick()
Check("stale progress is credited to Unknown", (TooltipHas("Unknown")),
    table.concat(Tooltip(), " | "))

Case("a drop only counts while it came from the open corpse")
QUESTS = { Quest(100, { ItemObjective("0/10 Hatefury Horn", 0, 10) }) }
SetStep(50, { { text = "0/10 Hatefury Horn", questId = 100 } })
SlashReset() Tick()
Kill("Hatefury Felsworn")
LootReady(true)
Loot("Hatefury Horn")
Tick()
Check("the corpse drop counts", LineCount("Hatefury Horn") == 1, table.concat(Display(), " | "))
for _ = 1, 100 do Tick(0.25) end
Loot("Hatefury Horn")
Tick()
Check("a drop long after that corpse is ignored", LineCount("Hatefury Horn") == 1,
    table.concat(Display(), " | "))
LootReady(false)
Loot("Hatefury Horn")
Tick()
Check("a drop from a chest is ignored", LineCount("Hatefury Horn") == 1,
    table.concat(Display(), " | "))

Case("farming kills group by family word, not by qualifier")
QUESTS = { Quest(100, { ItemObjective("0/10 Hatefury Horn", 0, 10) }) }
SetStep(60, { { text = "0/10 Hatefury Horn", questId = 100 } })
SlashReset() Tick()
Kill("Mangy Wolf") Tick()
Kill("Mangy Jaguar") Tick()
Check("\"Mangy\" alone does not merge them",
    BodyHas("Mangy Wolf") and BodyHas("Mangy Jaguar"), table.concat(Display(), " | "))
SlashReset() Tick()
Kill("Dreaming Whelp") Tick()
Kill("Adolescent Whelp") Tick()
local _, whelpLine = BodyHas("Whelp")
Check("a shared family word merges them", whelpLine == "2  Whelp", table.concat(Display(), " | "))
Check("the breakdown keeps both names",
    TooltipHas("Dreaming Whelp") and TooltipHas("Adolescent Whelp"), table.concat(Tooltip(), " | "))
SlashReset() Tick()
Kill("Kolkar Mauler") Tick()
Kill("Kolkar Battle Lord") Tick()
local _, kolkarLine = BodyHas("Kolkar")
Check("a shared first word merges them", kolkarLine == "2  Kolkar", table.concat(Display(), " | "))

Case("the quest log is scanned once per tick")
local realGetObjectives = C_QuestLog.GetQuestObjectives
local scans = 0
C_QuestLog.GetQuestObjectives = function(id)
    scans = scans + 1
    return realGetObjectives(id)
end
QUESTS = {
    Quest(100, { MonsterObjective("0/5 Centaur", 0, 5) }),
    Quest(200, { ItemObjective("0/10 Hatefury Horn", 0, 10) }),
    Quest(300, { MonsterObjective("0/8 Harpy", 0, 8) }),
}
SetStep(70, { { questId = 100 } })
SlashReset()
scans = 0
Tick()
-- One pass for the monster objectives, one for the item goals. OnUpdate used to
-- rebuild both several times per tick, five times a second.
Check("two passes over three quests on a steady tick", scans == 6, scans)
scans = 0
SetStep(71, { { questId = 100 } })
Tick()
Check("a step change doesn't add more passes", scans == 6, scans)
C_QuestLog.GetQuestObjectives = realGetObjectives

Case("the slash commands run")
Check("/killtimer copy", (pcall(SlashCommand, "copy")))
Check("/killtimer log", (pcall(SlashCommand, "log")))
Check("/killtimer", (pcall(SlashCommand, "")))

Case("it works without RestedXP installed")
RXPFrame = nil
RXPCData = nil
QUESTS = { Quest(100, { MonsterObjective("0/5 Centaur", 0, 5) }) }
SlashReset() Tick()
Kill("Centaur Plunderer")
QUESTS[1].objectives[1].numFulfilled = 1
Tick()
Check("kills are still counted", HeaderKills() == 1, Header())
for _ = 1, 20 do Tick(0.25) end
Check("the clock runs with no step information", HeaderSeconds() > 0, Header())
