local started, kills, activeTime = false, 0, 0
local lastStep, lastMob, lastMobTime, lootFromMobTime
local lastMonsterCounts = {}
local pendingKills = {}  -- mobs killed since the last OnUpdate tick, oldest first
-- Kills not tied to a quest kill-objective (pure item farming) are grouped by
-- whatever word(s) a mob's name shares with another already-seen mob (e.g.
-- "Kolkar Mauler" and "Kolkar Battle Lord" group under "Kolkar"; "Dreaming Whelp"
-- and "Adolescent Whelp" group under "Whelp") since there's no Blizzard-provided
-- family name to group by here. See GroupMob() below.
-- Dropped together with the header's timer and kill count (see
-- PruneFinishedObjectives), not on every step change: a concurrent item or monster
-- objective can still be open.
local mobs, mobOrder = {}, {}    -- group label -> kill count (+ display order)
local mobBreakdown = {}          -- group label -> { counts = {full name -> count}, order, words }
-- objective key -> { text, questID, fulfilled, required, mobs, mobOrder, elapsed }
local monsterGroups, groupOrder = {}, {}
local items, itemOrder = {}, {}  -- item name -> { count, fulfilled, required, questID, elapsed, seenInStep }

-- Builds a pattern from the game's own text "%s dies, you gain %d experience."
-- Quest XP ("You gain %d experience.") doesn't match, so only kills count.
local killPattern = "^" .. COMBATLOG_XPGAIN_FIRSTPERSON
    :gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
    :gsub("%%s", "(.+)")
    :gsub("%%d", "%%d+")
-- "You receive loot: " - so other players' loot in a group doesn't count.
local lootPrefix = LOOT_ITEM_SELF:match("^(.-)%%s") or ""
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local QUEST_ITEM_CLASS = 12

-- A quest objective can advance without a kill message (a grey mob, or any kill at
-- the level cap, earns no XP), so the most recently killed mob is only credited
-- while it's still fresh - past that the progress is listed as UNKNOWN instead of
-- being pinned on something that died minutes ago.
local KILL_CREDIT_WINDOW = 10
-- "You receive loot:" covers chests, herbs and fishing too, so a drop only counts
-- while the corpse it came from is still the open loot window.
local LOOT_WINDOW = 15
-- Recent progress keeps a line's work clock running even when its objective text
-- can't be matched against the current step, so the clock can't sit at 0:00 while
-- you're visibly farming.
local ACTIVITY_WINDOW = 60
local LOG_MAX = 200
local UNKNOWN_MOB = UNKNOWN or "Unknown"
-- Words that qualify a mob instead of naming its family, so that "Mangy Wolf" and
-- "Mangy Jaguar" don't become one group while "Dreaming Whelp" and "Adolescent
-- Whelp" still do. A heuristic: the kill text carries no family name to group by.
local STOP_WORDS = {}
for w in ([[a an and of the lone young elder ancient adolescent juvenile adult old
    great greater lesser giant huge large small mangy rabid diseased starving
    crazed enraged feral savage wild fierce dire mature elite rare]]):gmatch("%S+") do
    STOP_WORDS[w] = true
end

local PADDING = 22
local WIDTH_MIN, WIDTH_MAX = 150, 600
local HEIGHT_MIN, HEIGHT_MAX = 60, 400
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 300, 180
local DEFAULT_POINT = { "TOPLEFT", UIParent, "TOP", -DEFAULT_WIDTH / 2, -120 }
local GOLD = { 1, 0.82, 0 }
local FONT = "Fonts\\FRIZQT__.TTF"

-- UI prefs (scale, size, lock), shared across characters. Loaded before this file runs.
killTimerDB = killTimerDB or {}
if killTimerDB.scale == nil then killTimerDB.scale = 1 end
if killTimerDB.width == nil then killTimerDB.width = DEFAULT_WIDTH end
if killTimerDB.height == nil then killTimerDB.height = DEFAULT_HEIGHT end
if killTimerDB.locked == nil then killTimerDB.locked = false end

local f = CreateFrame("Frame", "killTimerFrame", UIParent, "BackdropTemplate")
-- Anchored by its own TOPLEFT corner, which stays fixed on screen as scale or
-- size change - only "TOP" (top-center) would make those controls appear to
-- also shift the panel's position.
if killTimerDB.point then
    local p = killTimerDB.point
    f:SetPoint(p.point, _G[p.relativeTo] or UIParent, p.relativePoint, p.x, p.y)
else
    f:SetPoint(unpack(DEFAULT_POINT))
end
f:SetScale(killTimerDB.scale)
f:SetClipsChildren(true)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
local function BeginDrag()
    if not killTimerDB.locked then f:StartMoving() end
end

-- Dragging only moves the frame on screen - without persisting the resulting
-- point here, the panel would snap back to DEFAULT_POINT on the next /reload.
-- Shared with textHitbox below, since that overlay covers most of the panel.
local function EndDrag()
    f:StopMovingOrSizing()
    local point, relativeTo, relativePoint, x, y = f:GetPoint()
    killTimerDB.point = {
        point = point,
        relativeTo = relativeTo and relativeTo.GetName and relativeTo:GetName() or "UIParent",
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

f:SetScript("OnDragStart", BeginDrag)
f:SetScript("OnDragStop", EndDrag)
f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
f:SetBackdropColor(0, 0, 0, 0.75)
f:SetBackdropBorderColor(unpack(GOLD))

-- Title: the addon's own name, so the overlay is recognizable at a glance.
local title = f:CreateFontString(nil, "OVERLAY")
title:SetFont(FONT, 12)
title:SetPoint("TOPLEFT", PADDING, -PADDING)
title:SetJustifyH("LEFT")
title:SetWordWrap(false)
title:SetText("killTimer")
title:SetTextColor(unpack(GOLD))

-- Header: elapsed time + kill count, shown larger/bolder than the mob/item list.
local header = f:CreateFontString(nil, "OVERLAY")
header:SetFont(FONT, 16)
header:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
header:SetJustifyH("LEFT")
header:SetWordWrap(false)

-- Small button so sharing data doesn't require remembering the /killtimer copy command.
local copyButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
copyButton:SetSize(44, 16)
copyButton:SetPoint("TOPRIGHT", -PADDING + 12, -PADDING + 3)
copyButton:SetText("Copy")
copyButton:GetFontString():SetFont(FONT, 9)

local divider = f:CreateTexture(nil, "ARTWORK")
divider:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.4)
divider:SetHeight(2)
divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -12)
divider:SetPoint("RIGHT", f, "RIGHT", -PADDING, 0)

local text = f:CreateFontString(nil, "OVERLAY")
text:SetFont(FONT, 12)
text:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -12)
text:SetJustifyH("LEFT")
-- Word wrap must stay on for embedded "\n" line breaks to render correctly;
-- with it off WoW shows a placeholder glyph instead of breaking the line.
text:SetWordWrap(true)
text:SetSpacing(6)

-- Grouped monster-objective lines collapse every contributing NPC name into one
-- line (see MonsterObjectives), so the per-mob breakdown that used to be visible
-- directly is shown as a tooltip instead. This needs its own frame rather than
-- EnableMouse() directly on the `text` FontString: a mouse-enabled Region swallows
-- clicks, so dragging from this part of the panel (most of its body) would stop
-- working - this overlay forwards drag to the panel instead of just eating it.
local textHitbox = CreateFrame("Frame", nil, f)
textHitbox:SetPoint("TOPLEFT", text, "TOPLEFT")
textHitbox:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT")
textHitbox:EnableMouse(true)
textHitbox:RegisterForDrag("LeftButton")
textHitbox:SetScript("OnDragStart", BeginDrag)
textHitbox:SetScript("OnDragStop", EndDrag)
textHitbox:SetScript("OnEnter", function(self)
    if #groupOrder == 0 and #mobOrder == 0 then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local first = true
    for _, key in ipairs(groupOrder) do
        local group = monsterGroups[key]
        if not first then GameTooltip:AddLine(" ") end
        first = false
        GameTooltip:AddLine(group.text, GOLD[1], GOLD[2], GOLD[3])
        for _, name in ipairs(group.mobOrder) do
            GameTooltip:AddLine(("%d  %s"):format(group.mobs[name], name), 1, 1, 1)
        end
    end
    for _, key in ipairs(mobOrder) do
        local breakdown = mobBreakdown[key]
        if not first then GameTooltip:AddLine(" ") end
        first = false
        GameTooltip:AddLine(key, GOLD[1], GOLD[2], GOLD[3])
        for _, name in ipairs(breakdown.order) do
            GameTooltip:AddLine(("%d  %s"):format(breakdown.counts[name], name), 1, 1, 1)
        end
    end
    GameTooltip:Show()
end)
textHitbox:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- The panel is a fixed size (set via the options panel's Width/Height sliders),
-- so content wraps/clips to it instead of the panel growing to fit the content.
local function ApplySize(width, height)
    f:SetSize(width, height)
    text:SetWidth(width - PADDING * 2)
end
ApplySize(killTimerDB.width, killTimerDB.height)

-- SetScale()/SetSize() applied this early - while the addon's own file is still
-- loading, before the UI has done its first layout pass - can render at the
-- wrong effective size on screen until something touches the frame again later
-- (e.g. re-clicking an Options slider to the same value fixes it). Reapplying
-- once on the next frame tick avoids depending on that manual nudge.
C_Timer.After(0, function()
    f:SetScale(killTimerDB.scale)
    ApplySize(killTimerDB.width, killTimerDB.height)
end)

-- This client's objective text is "1/10 Hatefury Horn" (count first), not Blizzard's
-- usual "Hatefury Horn: 1/10" - try that form first, falling back to the usual one.
local function ObjectiveName(objectiveText)
    if not objectiveText then return nil end
    return objectiveText:match("^%d+%s*/%s*%d+%s+(.+)$")
        or objectiveText:match("^(.-)%s*:?%s*%d+%s*/%s*%d+$")
        or objectiveText
end

-- Mob and item names reach us from two sources - RestedXP's rendered step text and
-- Blizzard's quest log - which only have to mean the same thing, not match byte for
-- byte, so they're compared in this form.
local function NormalizeName(s)
    return (s:lower():gsub("%p", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- Active "item" quest objectives, keyed by item name. Lets a required item show up
-- at 0% from the first kill, not just after the first drop.
local function QuestItemGoals()
    local goals = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo
        and C_QuestLog.GetQuestObjectives) then
        return goals
    end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            for _, obj in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                if obj.type == "item" and not obj.finished and obj.text then
                    local name = ObjectiveName(obj.text)
                    if name and name ~= "" then
                        goals[name] = {
                            fulfilled = obj.numFulfilled,
                            required = obj.numRequired,
                            questID = info.questID,
                        }
                    end
                end
            end
        end
    end
    return goals
end

-- Every active "kill X mobs" quest objective, keyed by questID:index, with its
-- display name (the creature family, e.g. "Centaur") and progress. A quest's
-- monster objective can name a whole creature family rather than the specific NPC
-- in the kill text ("Centaur Plunderer"), so matching by name doesn't work -
-- instead the kill list watches numFulfilled for increases and credits whichever
-- mob was killed most recently (see OnUpdate), grouped under this objective.
local function MonsterObjectives()
    local objectives = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo
        and C_QuestLog.GetQuestObjectives) then
        return objectives
    end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            for idx, obj in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                if obj.type == "monster" then
                    objectives[info.questID .. ":" .. idx] = {
                        text = ObjectiveName(obj.text) or obj.text,
                        questID = info.questID,
                        fulfilled = obj.numFulfilled or 0,
                        required = obj.numRequired,
                    }
                end
            end
        end
    end
    return objectives
end

-- What RestedXP's own currently-displayed step(s) are asking for, read straight off
-- its guide-window frames (RXPFrame.CurrentStepFrame.framePool[n].step.elements[n]):
-- the quest IDs involved, plus names for the elements that only render text.
-- This isn't a public RXPGuides API - it's internal UI state - so it can break on a
-- RestedXP update. If that happens both tables come back empty and the callers fall
-- back to tracking every active objective instead of only the current step's.
-- Objective elements don't set `itemName`; their rendered text is "1/10 Hatefury Claw"
-- (count first), the reverse of Blizzard's own "Hatefury Claw: 1/10" quest log text.
local function CurrentStepTargets()
    local names, quests = {}, {}
    local framePool = RXPFrame and RXPFrame.CurrentStepFrame and RXPFrame.CurrentStepFrame.framePool
    if not framePool then return names, quests end
    for _, stepframe in ipairs(framePool) do
        local step = stepframe.step
        for _, element in ipairs(step and step.elements or {}) do
            if element.itemName then
                names[NormalizeName(element.itemName)] = true
            end
            local elementText = element.rawtext or element.text
            local name = elementText and elementText:match("^%d+%s*/%s*%d+%s+(.+)$")
            if name then
                names[NormalizeName(name)] = true
            end
            local questID = tonumber(element.questId or element.questID)
            if questID then
                quests[questID] = true
            end
        end
    end
    return names, quests
end

-- Whether an objective is what the current step is about. Its quest ID is the
-- reliable key; the name is only compared for step elements that render text
-- without one. With no step information at all (no RestedXP, or its guide window
-- not populated yet) everything counts as current, as it did before this filter.
local function IsCurrentStep(stepNames, stepQuests, name, questID)
    if not next(stepNames) and not next(stepQuests) then return true end
    if questID and stepQuests[questID] then return true end
    return name ~= nil and stepNames[NormalizeName(name)] == true
end

-- Seeds `items` with any active quest-item goal (at 0 if not looted yet) and
-- refreshes its fulfilled/required count from the quest log. Restricted to the
-- item(s) RestedXP's current step is asking for, when that's known.
local function SyncGoals(goals, stepNames, stepQuests)
    -- RestedXP's guide window can take a tick to repopulate after e.g. /reload. Any
    -- goal seeded below during that gap (filter briefly off) needs pruning once the
    -- filter is back - but only goals that were never part of a current step: one
    -- that was carries over across step changes on purpose (see
    -- PruneFinishedObjectives), and a long dry streak is exactly the count == 0 case
    -- this would otherwise throw away.
    for i = #itemOrder, 1, -1 do
        local name = itemOrder[i]
        local item = items[name]
        if item.required and item.count == 0 and not item.seenInStep
            and not IsCurrentStep(stepNames, stepQuests, name, item.questID) then
            items[name] = nil
            table.remove(itemOrder, i)
        end
    end

    for name, goal in pairs(goals) do
        local current = IsCurrentStep(stepNames, stepQuests, name, goal.questID)
        -- Already-tracked goals keep refreshing once the step moves on, so a line
        -- carried across a step change doesn't show a frozen x/y.
        if current or items[name] then
            local item = items[name]
            if not item then
                item = { count = 0 }
                items[name] = item
                itemOrder[#itemOrder + 1] = name
            end
            item.fulfilled, item.required, item.questID = goal.fulfilled, goal.required, goal.questID
            item.seenInStep = item.seenInStep or current
        end
    end
end

local function FormatTime(t)
    t = t or 0
    return ("%d:%02d"):format(math.floor(t / 60), math.floor(t % 60))
end

-- The header's clock is work time, not wall-clock since the first kill: it only
-- runs on ticks where something listed below it is being worked on (see OnUpdate),
-- which keeps it comparable to the per-line clocks now that both survive a step
-- change - wall-clock would also count every turn-in and flight path in between.
local function HeaderLine()
    return ("%s  %d kills"):format(FormatTime(activeTime), kills)
end

local function MobLine(key)
    return ("%d  %s"):format(mobs[key], key)
end

local function GroupLine(group)
    if not group.required then
        return ("%d  %s"):format(group.fulfilled, group.text)
    end
    local pct = group.required > 0 and math.floor(group.fulfilled / group.required * 100 + 0.5) or 0
    return ("%d  %s (%d%%)  %d/%d  %s"):format(
        group.fulfilled, group.text, pct, group.fulfilled, group.required, FormatTime(group.elapsed))
end

local function ItemLine(name, item)
    local pct = kills > 0 and math.floor(item.count / kills * 100 + 0.5) or 0
    if not item.required then
        return ("|cff00ccff%d  %s (%d%%)|r"):format(item.count, name, pct)
    end
    return ("|cff00ccff%d  %s (%d%%)  %d/%d  %s|r"):format(
        item.count, name, pct, item.fulfilled or 0, item.required, FormatTime(item.elapsed))
end

-- Used both for the overlay and for the chat summary when objectives finish.
local function Lines()
    local out = { HeaderLine() }
    for _, name in ipairs(mobOrder) do
        out[#out + 1] = MobLine(name)
    end
    for _, key in ipairs(groupOrder) do
        out[#out + 1] = GroupLine(monsterGroups[key])
    end
    for _, name in ipairs(itemOrder) do
        out[#out + 1] = ItemLine(name, items[name])
    end
    return out
end

-- A mob name split into the words that can identify a family, keyed by their
-- normalized form (so "Kolkar" and "Kolkar's" match) and mapped to the spelling a
-- label should use.
local function MobWords(mob)
    local words = {}
    for w in mob:gmatch("%S+") do
        local norm = NormalizeName(w)
        if norm ~= "" and not STOP_WORDS[norm] then
            words[norm] = (w:gsub("%p+$", ""))
        end
    end
    return words
end

-- Assigns a pure item-farming kill to a group, merging it into an existing group
-- when its name shares a family word with one (e.g. "Dreaming Whelp" joins a group
-- already holding "Adolescent Whelp" because both contain "Whelp"), otherwise
-- starting a group of its own. A group of one is labelled with the full mob name;
-- once it has more members the label narrows to the word(s) still common to all of
-- them, and the group is renamed (migrating its stored counts) to match.
local function GroupMob(mob)
    local mobWords = MobWords(mob)

    local matchedKey
    for _, key in ipairs(mobOrder) do
        for norm in pairs(mobBreakdown[key].words) do
            if mobWords[norm] then
                matchedKey = key
                break
            end
        end
        if matchedKey then break end
    end

    if not matchedKey then
        if not mobBreakdown[mob] then
            mobs[mob] = 0
            mobOrder[#mobOrder + 1] = mob
            mobBreakdown[mob] = { counts = {}, order = {}, words = mobWords }
        end
        return mob
    end

    local breakdown = mobBreakdown[matchedKey]
    local narrowed = {}
    for norm, word in pairs(breakdown.words) do
        if mobWords[norm] then narrowed[norm] = word end
    end
    breakdown.words = narrowed

    -- Pick the longest shared word as the label (ties broken alphabetically)
    -- since that tends to be the most specific/descriptive one, e.g. "Whelp"
    -- over a shorter shared word that might just be a common adjective.
    local label
    for _, word in pairs(narrowed) do
        if not label or #word > #label or (#word == #label and word < label) then
            label = word
        end
    end

    -- An already-taken label means either this group's own current key (nothing to
    -- do) or another group's - renaming into that would silently overwrite its
    -- counts, so the current key stays.
    if not label or mobs[label] then return matchedKey end

    mobs[label] = mobs[matchedKey]
    mobs[matchedKey] = nil
    mobBreakdown[label] = breakdown
    mobBreakdown[matchedKey] = nil
    for i, key in ipairs(mobOrder) do
        if key == matchedKey then
            mobOrder[i] = label
            break
        end
    end
    return label
end

local function Reset()
    started, kills, activeTime = false, 0, 0
    lastMob, lastMobTime = nil, nil
    wipe(mobs) wipe(mobOrder) wipe(mobBreakdown) wipe(items) wipe(itemOrder) wipe(pendingKills)
    wipe(monsterGroups) wipe(groupOrder)
    -- Baseline so progress already made on a quest before this reset isn't
    -- mistaken for a kill once the next OnUpdate tick diffs against it.
    local baseline = {}
    for key, obj in pairs(MonsterObjectives()) do baseline[key] = obj.fulfilled end
    lastMonsterCounts = baseline
end

-- Chat and killTimerLog summary, written when objectives finish rather than on
-- every step change: the totals now span however many steps an objective stays
-- open, so logging them per step would repeat the same kills entry after entry.
local function LogStep(step, lines)
    print("killTimer: step " .. tostring(step))
    for _, line in ipairs(lines) do print("  " .. line) end
    killTimerLog = killTimerLog or {}
    killTimerLog[#killTimerLog + 1] = {
        step = step,
        time = date("%Y-%m-%d %H:%M"),
        result = table.concat(lines, "\n"),
    }
    -- Only /killtimer log ever reads this back, so it's capped rather than grown
    -- for the lifetime of the character.
    while #killTimerLog > LOG_MAX do table.remove(killTimerLog, 1) end
end

-- Called on every RestedXP step change instead of Reset(): a step boundary doesn't
-- mean a quest's monster/item objective is done - RestedXP often asks you to kill or
-- loot something "on the way" across several steps of the same quest. So only the
-- groups/items whose objective has actually left the quest log (turned in or
-- abandoned) are dropped here, and those are what gets reported; everything still
-- open keeps its kill count, mob breakdown and work time (group.elapsed/item.elapsed,
-- see OnUpdate) across the step change.
local function PruneFinishedObjectives(step, objectives, goals)
    local finished = {}

    for _, key in ipairs(groupOrder) do
        if not objectives[key] then
            finished[#finished + 1] = GroupLine(monsterGroups[key])
        end
    end
    for i = #groupOrder, 1, -1 do
        local key = groupOrder[i]
        if not objectives[key] then
            monsterGroups[key] = nil
            table.remove(groupOrder, i)
        end
    end

    -- An item with no `.required` was looted without ever matching an active quest
    -- goal (see the CHAT_MSG_LOOT handler) - there's no objective to key those by, so
    -- they stay step-scoped instead of carrying over, and there's nothing to report.
    for _, name in ipairs(itemOrder) do
        local item = items[name]
        if item.required and not goals[name] then
            finished[#finished + 1] = ItemLine(name, item)
        end
    end
    for i = #itemOrder, 1, -1 do
        local name = itemOrder[i]
        local item = items[name]
        if not item.required or not goals[name] then
            items[name] = nil
            table.remove(itemOrder, i)
        end
    end

    -- Nothing carried over - this is a genuinely fresh start, not a mid-quest step
    -- change, so the header's work time and kill count reset. The farming-mob
    -- fallback tally (mobs/mobOrder) has no objective of its own to key continuity
    -- by, so it only drops alongside that same fresh start - otherwise it would
    -- reset mid-farm whenever some *other* concurrent objective's step just ended.
    local freshStart = #groupOrder == 0 and #itemOrder == 0
    if freshStart then
        for _, key in ipairs(mobOrder) do
            finished[#finished + 1] = MobLine(key)
        end
    end

    if started and #finished > 0 then
        table.insert(finished, 1, HeaderLine())
        LogStep(step, finished)
    end

    if freshStart then
        started, kills, activeTime = false, 0, 0
        wipe(mobs) wipe(mobOrder) wipe(mobBreakdown)
    end
end

-- Popup with a selectable, multi-line EditBox - addons can't touch the OS
-- clipboard directly, so Ctrl+A/Ctrl+C in a text box is the standard workaround.
local copyFrame = CreateFrame("Frame", "killTimerCopyFrame", UIParent, "BackdropTemplate")
copyFrame:SetSize(360, 280)
copyFrame:SetPoint("CENTER")
copyFrame:SetFrameStrata("DIALOG")
copyFrame:SetClampedToScreen(true)
copyFrame:SetMovable(true)
copyFrame:EnableMouse(true)
copyFrame:RegisterForDrag("LeftButton")
copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
copyFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
copyFrame:SetBackdropColor(0, 0, 0, 0.9)
copyFrame:SetBackdropBorderColor(unpack(GOLD))
copyFrame:Hide()
tinsert(UISpecialFrames, "killTimerCopyFrame") -- lets Escape close it like a Blizzard dialog

local copyTitle = copyFrame:CreateFontString(nil, "OVERLAY")
copyTitle:SetFont(FONT, 12)
copyTitle:SetPoint("TOPLEFT", PADDING, -PADDING)
copyTitle:SetPoint("RIGHT", copyFrame, "RIGHT", -PADDING, 0)
copyTitle:SetJustifyH("LEFT")
copyTitle:SetWordWrap(true)
copyTitle:SetText("Ctrl+A to select, Ctrl+C to copy")
copyTitle:SetTextColor(unpack(GOLD))

local copyClose = CreateFrame("Button", nil, copyFrame, "UIPanelCloseButton")
copyClose:SetPoint("TOPRIGHT", -2, -2)

local copyScroll = CreateFrame("ScrollFrame", "killTimerCopyScroll", copyFrame, "UIPanelScrollFrameTemplate")
copyScroll:SetPoint("TOPLEFT", copyTitle, "BOTTOMLEFT", 0, -10)
copyScroll:SetPoint("BOTTOMRIGHT", -30, PADDING)

local copyEditBox = CreateFrame("EditBox", nil, copyScroll)
copyEditBox:SetMultiLine(true)
copyEditBox:SetFontObject(ChatFontNormal)
copyEditBox:SetWidth(300)
copyEditBox:SetAutoFocus(false)
copyEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() copyFrame:Hide() end)
copyScroll:SetScrollChild(copyEditBox)

-- Strip WoW's |cAARRGGBB...|r color codes so the copied text is plain, shareable
-- plain text (e.g. for pasting into Discord) instead of raw escape sequences.
local function StripColors(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function ShowCopyPopup()
    local lines = Lines()
    for i, line in ipairs(lines) do
        lines[i] = StripColors(line)
    end
    copyEditBox:SetText(table.concat(lines, "\n"))
    copyFrame:Show()
    copyEditBox:SetFocus()
    copyEditBox:HighlightText()
end

copyButton:SetScript("OnClick", ShowCopyPopup)

f:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
f:RegisterEvent("CHAT_MSG_LOOT")
f:RegisterEvent("LOOT_READY")
f:SetScript("OnEvent", function(_, event, msg)
    if event == "CHAT_MSG_COMBAT_XP_GAIN" then
        local mob = msg:match(killPattern)
        if not mob then return end
        -- Counting/crediting happens later, once OnUpdate sees whether this kill
        -- actually advanced a quest objective.
        lastMob, lastMobTime = mob, GetTime()
        pendingKills[#pendingKills + 1] = mob

    elseif event == "LOOT_READY" then
        -- Is this a corpse we're looting (and not e.g. a chest or Rocket Car Rubble)?
        local guid = GetLootSourceInfo and GetNumLootItems() > 0 and GetLootSourceInfo(1)
        local fromMob = type(guid) == "string" and guid:find("^Creature") ~= nil
        lootFromMobTime = fromMob and GetTime() or nil

    elseif event == "CHAT_MSG_LOOT" then
        if msg:find(lootPrefix, 1, true) ~= 1 then return end
        local link = msg:match("|Hitem:.-|h%[.-%]|h")
        local name = link and link:match("%[(.-)%]")
        if not name then return end
        local item = items[name]
        -- Blizzard's "Quest" item class covers most of what quests ask for, but not
        -- all of it - plenty of collection quests want a trade good or a plain junk
        -- item - so anything the quest log is actually asking for (seeded by
        -- SyncGoals) counts no matter its class.
        local isQuestItem = select(6, GetItemInfoInstant(link)) == QUEST_ITEM_CLASS
        if not isQuestItem and not (item and item.required) then return end
        if not lastMob or not lootFromMobTime
            or GetTime() - lootFromMobTime > LOOT_WINDOW then
            return
        end
        if not item then
            item = { count = 0 }
            items[name] = item
            itemOrder[#itemOrder + 1] = name
        end
        item.count = item.count + (tonumber(msg:match("|h|rx(%d+)")) or 1)
        item.lastLoot = GetTime()
    end
end)

local sinceUpdate = 0
f:SetScript("OnUpdate", function(_, elapsed)
    sinceUpdate = sinceUpdate + elapsed
    if sinceUpdate < 0.2 then return end
    local dt = sinceUpdate
    sinceUpdate = 0
    local now = GetTime()

    -- One pass over the quest log per tick, shared by everything below: each of
    -- these walks every quest and all of its objectives, five times a second.
    local objectives = MonsterObjectives()
    local goals = QuestItemGoals()
    local stepNames, stepQuests = CurrentStepTargets()

    -- RestedXP stores the active step in the global RXPCData.
    -- Without RestedXP, step stays nil and the overlay just keeps running.
    local step = RXPCData and RXPCData.currentStep
    if step ~= lastStep then
        local prevStep = lastStep
        lastStep = step
        PruneFinishedObjectives(prevStep, objectives, goals)
    end

    -- An active, unfulfilled item-type objective means a quest item needs looting
    -- from *some* mob - there's no way to tell which NPCs can drop it, so every
    -- kill counts while that's the case, same as before mob filtering existed.
    -- Restricted to RestedXP's current step (like SyncGoals) so an unrelated item
    -- quest sitting elsewhere in the quest log doesn't turn off mob filtering here.
    local farmingItem = false
    for name, goal in pairs(goals) do
        if goal.required and (goal.fulfilled or 0) < goal.required
            and IsCurrentStep(stepNames, stepQuests, name, goal.questID) then
            farmingItem = true
            break
        end
    end

    -- Credit a kill once a monster objective's progress actually increases, rather
    -- than matching the kill text's mob name against objective text (which fails
    -- when an objective names a creature family, e.g. "Centaur", instead of the
    -- specific NPC killed). The delta is credited to the most recently killed mob
    -- (lastMob); if two different quest mobs die within the same 0.2s tick, the
    -- earlier one can be misattributed to the later one. Every mob that
    -- contributes to the same objective (e.g. every Centaur variant) is grouped
    -- into one display line instead of one line per distinct NPC name.
    local objectiveKills = 0
    for key, obj in pairs(objectives) do
        local prev = lastMonsterCounts[key] or obj.fulfilled
        local objDelta = obj.fulfilled - prev
        if objDelta > 0 then
            -- One mob can count towards two quests at once, so these deltas overlap:
            -- the largest is how many mobs the tick can account for, while adding
            -- them up would count a shared kill once per quest in the header.
            objectiveKills = math.max(objectiveKills, objDelta)
            local mob = UNKNOWN_MOB
            if lastMob and lastMobTime and now - lastMobTime <= KILL_CREDIT_WINDOW then
                mob = lastMob
            end
            local group = monsterGroups[key]
            if not group then
                group = { mobs = {}, mobOrder = {}, questID = obj.questID }
                monsterGroups[key] = group
                groupOrder[#groupOrder + 1] = key
            end
            if not group.mobs[mob] then
                group.mobs[mob] = 0
                group.mobOrder[#group.mobOrder + 1] = mob
            end
            group.mobs[mob] = group.mobs[mob] + objDelta
            group.lastProgress = now
        end
    end

    -- Whatever fed an objective above are the newest kills on this tick; any older
    -- ones died for an item drop instead and are counted here, so a mixed step (a
    -- kill quest plus a drop to farm) loses neither to the other.
    local farmed = 0
    if farmingItem then
        for i = 1, #pendingKills - objectiveKills do
            local mob = pendingKills[i]
            local key = GroupMob(mob)
            mobs[key] = mobs[key] + 1
            local breakdown = mobBreakdown[key]
            if not breakdown.counts[mob] then
                breakdown.counts[mob] = 0
                breakdown.order[#breakdown.order + 1] = mob
            end
            breakdown.counts[mob] = breakdown.counts[mob] + 1
            farmed = farmed + 1
        end
    end
    wipe(pendingKills)

    local killsThisTick = objectiveKills + farmed
    if killsThisTick > 0 then
        started = true
        kills = kills + killsThisTick
    end

    -- Keep every known group's displayed progress in sync with the quest log,
    -- even on ticks where nothing died (e.g. right after a /reload).
    for key, group in pairs(monsterGroups) do
        local obj = objectives[key]
        if obj then
            group.text, group.fulfilled, group.required = obj.text, obj.fulfilled, obj.required
            group.questID = group.questID or obj.questID
        end
    end

    SyncGoals(goals, stepNames, stepQuests)

    -- Each line's work time only runs while RestedXP's current step is actually
    -- about it - freezing while you're on an unrelated step and picking back up
    -- (from the saved total, not from zero) once it's relevant again. Progress
    -- within ACTIVITY_WINDOW counts as current on its own, so an objective whose
    -- text or quest ID can't be matched against the step can't freeze the clock
    -- while you're standing there working on it.
    local working = false
    for _, key in ipairs(groupOrder) do
        local group = monsterGroups[key]
        if IsCurrentStep(stepNames, stepQuests, group.text, group.questID)
            or (group.lastProgress and now - group.lastProgress <= ACTIVITY_WINDOW) then
            group.elapsed = (group.elapsed or 0) + dt
            working = true
        end
    end
    for _, name in ipairs(itemOrder) do
        local item = items[name]
        if item.required and (IsCurrentStep(stepNames, stepQuests, name, item.questID)
            or (item.lastLoot and now - item.lastLoot <= ACTIVITY_WINDOW)) then
            item.elapsed = (item.elapsed or 0) + dt
            working = true
        end
    end

    -- The header's clock is the union of those per-line windows, plus any tick that
    -- counted a kill, so it measures the time actually spent on what's listed below.
    if started and (working or killsThisTick > 0) then
        activeTime = activeTime + dt
    end

    local baseline = {}
    for key, obj in pairs(objectives) do baseline[key] = obj.fulfilled end
    lastMonsterCounts = baseline

    local lines = Lines()
    header:SetText(lines[1])
    local hasBody = #lines > 1
    text:SetShown(hasBody)
    divider:SetShown(hasBody)
    if hasBody then
        text:SetText(table.concat(lines, "\n", 2))
    end
end)

-- Shared state/helpers for killTimerOptions.lua. Addon files are separate Lua
-- chunks that don't see each other's locals, so this is the handoff point.
killTimerNS = {
    frame = f,
    ApplySize = ApplySize,
    DEFAULT_POINT = DEFAULT_POINT,
    WIDTH_MIN = WIDTH_MIN,
    WIDTH_MAX = WIDTH_MAX,
    HEIGHT_MIN = HEIGHT_MIN,
    HEIGHT_MAX = HEIGHT_MAX,
    ShowCopyPopup = ShowCopyPopup,
}

local LOG_SHOWN = 10

SLASH_KILLTIMER1 = "/killtimer"
SlashCmdList.KILLTIMER = function(msg)
    msg = (msg or ""):lower()
    if msg:match("^copy") then
        ShowCopyPopup()
    elseif msg:match("^log") then
        local log = killTimerLog or {}
        print(("killTimer: %d logged step(s)"):format(#log))
        for i = math.max(1, #log - LOG_SHOWN + 1), #log do
            print(("  [%s] step %s"):format(tostring(log[i].time), tostring(log[i].step)))
            for line in (log[i].result or ""):gmatch("[^\n]+") do print("    " .. line) end
        end
    else
        Reset()
    end
end

Reset()
