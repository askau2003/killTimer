local start, kills, lastStep, lastMob, lootFromMob
local lastMonsterCounts = {}
local pendingKills = {}  -- mobs killed since the last OnUpdate tick, oldest first
-- Kills not tied to a quest kill-objective (pure item farming) are grouped by
-- whatever word(s) a mob's name shares with another already-seen mob (e.g.
-- "Kolkar Mauler" and "Kolkar Battle Lord" group under "Kolkar"; "Dreaming Whelp"
-- and "Adolescent Whelp" group under "Whelp") since there's no Blizzard-provided
-- family name to group by here. See GroupMob() below.
-- Step-scoped like start/kills (see PruneFinishedObjectives), not wiped on every
-- step change: a concurrent item/monster objective can still be open.
local mobs, mobOrder = {}, {}    -- group label -> kill count (+ display order)
local mobBreakdown = {}          -- group label -> { counts = {full name -> count}, order, words }
local monsterGroups, groupOrder = {}, {}  -- objective key -> { text, fulfilled, required, mobs, mobOrder }
local items, itemOrder = {}, {}  -- item name -> { count = n, fulfilled = f, required = r }

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

-- Item names from RestedXP's own currently-displayed step(s), read straight off its
-- guide-window frames (RXPFrame.CurrentStepFrame.framePool[n].step.elements[n]).
-- This isn't a public RXPGuides API - it's internal UI state - so it can break on a
-- RestedXP update. If that happens this just returns an empty table and SyncGoals()
-- falls back to showing every active quest-item goal instead of only the current step's.
-- Objective elements don't set `itemName`; their rendered text is "1/10 Hatefury Claw"
-- (count first), the reverse of Blizzard's own "Hatefury Claw: 1/10" quest log text.
local function CurrentStepItemNames()
    local names = {}
    local framePool = RXPFrame and RXPFrame.CurrentStepFrame and RXPFrame.CurrentStepFrame.framePool
    if not framePool then return names end
    for _, stepframe in ipairs(framePool) do
        local step = stepframe.step
        for _, element in ipairs(step and step.elements or {}) do
            if element.itemName then
                names[element.itemName] = true
            end
            local text = element.rawtext or element.text
            local name = text and text:match("^%d+%s*/%s*%d+%s+(.+)$")
            if name then
                names[name] = true
            end
        end
    end
    return names
end

-- Seeds `items` with any active quest-item goal (at 0 if not looted yet) and
-- refreshes its fulfilled/required count from the quest log. Restricted to the
-- item(s) RestedXP's current step is asking for, when that's known.
local function SyncGoals()
    local currentStepItems = CurrentStepItemNames()
    local goals = QuestItemGoals()
    local onlyCurrentStep = next(currentStepItems) ~= nil

    -- RestedXP's guide window can take a tick to repopulate after e.g. /reload. Any
    -- goal seeded below during that gap (filter briefly off) needs pruning once the
    -- filter comes back - but only if nothing was actually looted for it yet.
    if onlyCurrentStep then
        for i = #itemOrder, 1, -1 do
            local name = itemOrder[i]
            local item = items[name]
            if item.required and item.count == 0 and not currentStepItems[name] then
                items[name] = nil
                table.remove(itemOrder, i)
            end
        end
    end

    for name, goal in pairs(goals) do
        if not onlyCurrentStep or currentStepItems[name] then
            local item = items[name]
            if not item then
                item = { count = 0 }
                items[name] = item
                itemOrder[#itemOrder + 1] = name
            end
            item.fulfilled, item.required = goal.fulfilled, goal.required
        end
    end
end

local function FormatTime(t)
    t = t or 0
    return ("%d:%02d"):format(math.floor(t / 60), math.floor(t % 60))
end

-- Used both for the overlay and for the chat summary when a step ends.
local function Lines()
    local t = start and GetTime() - start or 0
    local out = { ("%s  %d kills"):format(FormatTime(t), kills or 0) }
    for _, name in ipairs(mobOrder) do
        out[#out + 1] = ("%d  %s"):format(mobs[name], name)
    end
    for _, key in ipairs(groupOrder) do
        local group = monsterGroups[key]
        if group.required then
            local pct = group.required > 0 and math.floor(group.fulfilled / group.required * 100 + 0.5) or 0
            out[#out + 1] = ("%d  %s (%d%%)  %d/%d  %s"):format(
                group.fulfilled, group.text, pct, group.fulfilled, group.required, FormatTime(group.elapsed))
        else
            out[#out + 1] = ("%d  %s"):format(group.fulfilled, group.text)
        end
    end
    for _, name in ipairs(itemOrder) do
        local item = items[name]
        local pct = kills > 0 and math.floor(item.count / kills * 100 + 0.5) or 0
        if item.required then
            out[#out + 1] = ("|cff00ccff%d  %s (%d%%)  %d/%d  %s|r"):format(
                item.count, name, pct, item.fulfilled or 0, item.required, FormatTime(item.elapsed))
        else
            out[#out + 1] = ("|cff00ccff%d  %s (%d%%)|r"):format(item.count, name, pct)
        end
    end
    return out
end

-- Assigns a pure item-farming kill to a group, merging it into an existing
-- group when its name shares a word with one (e.g. "Dreaming Whelp" joins a
-- group already holding "Adolescent Whelp" because both contain "Whelp"),
-- otherwise starting a new group keyed by the mob's first word. A group's
-- label narrows to just the word(s) still common to every member once it has
-- more than one, and the group is renamed (migrating its stored counts) when
-- that narrowed label differs from its current one.
local function GroupMob(mob)
    local mobWords = {}
    for w in mob:gmatch("%S+") do mobWords[w] = true end

    local matchedKey
    for _, key in ipairs(mobOrder) do
        for w in pairs(mobBreakdown[key].words) do
            if mobWords[w] then
                matchedKey = key
                break
            end
        end
        if matchedKey then break end
    end

    if not matchedKey then
        local key = mob:match("^(%S+)") or mob
        mobs[key] = 0
        mobOrder[#mobOrder + 1] = key
        mobBreakdown[key] = { counts = {}, order = {}, words = mobWords }
        return key
    end

    local breakdown = mobBreakdown[matchedKey]
    local narrowed = {}
    for w in pairs(breakdown.words) do
        if mobWords[w] then narrowed[w] = true end
    end
    breakdown.words = narrowed

    -- Pick the longest shared word as the label (ties broken alphabetically)
    -- since that tends to be the most specific/descriptive one, e.g. "Whelp"
    -- over a shorter shared word that might just be a common adjective.
    local label
    for w in pairs(narrowed) do
        if not label or #w > #label or (#w == #label and w < label) then
            label = w
        end
    end
    label = label or matchedKey

    if label == matchedKey then return matchedKey end

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
    start, kills, lastMob = nil, 0, nil
    wipe(mobs) wipe(mobOrder) wipe(mobBreakdown) wipe(items) wipe(itemOrder) wipe(pendingKills)
    wipe(monsterGroups) wipe(groupOrder)
    -- Baseline so progress already made on a quest before this reset isn't
    -- mistaken for a kill once the next OnUpdate tick diffs against it.
    local baseline = {}
    for key, obj in pairs(MonsterObjectives()) do baseline[key] = obj.fulfilled end
    lastMonsterCounts = baseline
end

-- Called on every RestedXP step change instead of Reset(): a step boundary doesn't
-- mean a quest's monster/item objective is done - RestedXP often asks you to kill or
-- loot something "on the way" across several steps of the same quest. So only the
-- groups/items whose objective has actually left the quest log (turned in or
-- abandoned) are dropped here; everything still open keeps its kill count, mob
-- breakdown and "work time" (group.elapsed/item.elapsed, see OnUpdate) across the
-- step change. Pure item-farming kills (mobs/mobOrder) have no Blizzard objective to
-- key them by, so they stay step-scoped like before.
local function PruneFinishedObjectives()
    local liveObjectives = MonsterObjectives()
    for i = #groupOrder, 1, -1 do
        local key = groupOrder[i]
        if not liveObjectives[key] then
            monsterGroups[key] = nil
            table.remove(groupOrder, i)
        end
    end

    -- An item with no `.required` was looted without ever matching an active quest
    -- goal (see the CHAT_MSG_LOOT handler) - there's no persistent key for those, so
    -- they stay step-scoped like the farming-mob fallback above/below instead of
    -- carrying over.
    local liveGoals = QuestItemGoals()
    for i = #itemOrder, 1, -1 do
        local name = itemOrder[i]
        local item = items[name]
        if not item.required or not liveGoals[name] then
            items[name] = nil
            table.remove(itemOrder, i)
        end
    end

    -- Nothing carried over - this is a genuinely fresh start, not a mid-quest
    -- step change, so the header's timer/kill count resets like before. The
    -- farming-mob fallback tally (mobs/mobOrder) has no objective of its own to
    -- key continuity by, so it only wipes alongside that same fresh start -
    -- otherwise it would reset mid-farm whenever some *other* concurrent
    -- item/monster objective's step just happened to end.
    if #groupOrder == 0 and #itemOrder == 0 then
        start, kills = nil, 0
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
        -- actually advanced a quest objective (see MonsterObjectiveCounts above).
        lastMob = mob
        pendingKills[#pendingKills + 1] = mob

    elseif event == "LOOT_READY" then
        -- Is this a corpse we're looting (and not e.g. a chest or Rocket Car Rubble)?
        local guid = GetLootSourceInfo and GetNumLootItems() > 0 and GetLootSourceInfo(1)
        lootFromMob = type(guid) == "string" and guid:find("^Creature") ~= nil

    elseif event == "CHAT_MSG_LOOT" then
        if msg:find(lootPrefix, 1, true) ~= 1 then return end
        local link = msg:match("|Hitem:.-|h%[.-%]|h")
        if not link or select(6, GetItemInfoInstant(link)) ~= QUEST_ITEM_CLASS then return end
        if not lootFromMob or not lastMob then return end
        local name = link:match("%[(.-)%]")
        local item = items[name]
        if not item then
            item = { count = 0 }
            items[name] = item
            itemOrder[#itemOrder + 1] = name
        end
        item.count = item.count + (tonumber(msg:match("|h|rx(%d+)")) or 1)
    end
end)

local sinceUpdate = 0
f:SetScript("OnUpdate", function(_, elapsed)
    sinceUpdate = sinceUpdate + elapsed
    if sinceUpdate < 0.2 then return end
    local dt = sinceUpdate
    sinceUpdate = 0

    -- RestedXP stores the active step in the global RXPCData.
    -- Without RestedXP, step stays nil and the overlay just keeps running.
    local step = RXPCData and RXPCData.currentStep
    if step ~= lastStep then
        if start and lastStep then
            local lines = Lines()
            print("killTimer: step " .. tostring(lastStep))
            for _, line in ipairs(lines) do print("  " .. line) end
            killTimerLog = killTimerLog or {}
            killTimerLog[#killTimerLog + 1] = {
                step = lastStep,
                time = date("%Y-%m-%d %H:%M"),
                result = table.concat(lines, "\n"),
            }
        end
        lastStep = step
        PruneFinishedObjectives()
    end

    local objectives = MonsterObjectives()

    -- An active, unfulfilled item-type objective means a quest item needs looting
    -- from *some* mob - there's no way to tell which NPCs can drop it, so every
    -- kill counts while that's the case, same as before mob filtering existed.
    -- Restricted to RestedXP's current step (like SyncGoals) so an unrelated item
    -- quest sitting elsewhere in the quest log doesn't turn off mob filtering here.
    local currentStepItems = CurrentStepItemNames()
    local onlyCurrentStep = next(currentStepItems) ~= nil
    local farmingItem = false
    for name, goal in pairs(QuestItemGoals()) do
        if (not onlyCurrentStep or currentStepItems[name])
            and goal.required and (goal.fulfilled or 0) < goal.required then
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
    -- into one display line instead of one line per distinct NPC name. This runs
    -- regardless of farmingItem, so a step tracking both a monster kill-count and
    -- an item drop still groups the monster kills instead of losing them to the
    -- item-farming fallback below.
    local creditedThisTick = 0
    for key, obj in pairs(objectives) do
        local prev = lastMonsterCounts[key] or obj.fulfilled
        local objDelta = obj.fulfilled - prev
        if objDelta > 0 and lastMob then
            start = start or GetTime()
            kills = kills + objDelta
            creditedThisTick = creditedThisTick + objDelta
            local group = monsterGroups[key]
            if not group then
                group = { mobs = {}, mobOrder = {} }
                monsterGroups[key] = group
                groupOrder[#groupOrder + 1] = key
            end
            if not group.mobs[lastMob] then
                group.mobs[lastMob] = 0
                group.mobOrder[#group.mobOrder + 1] = lastMob
            end
            group.mobs[lastMob] = group.mobs[lastMob] + objDelta
        end
    end

    -- Only fall back to counting every pending kill individually on ticks where
    -- nothing was already credited to a monster objective above - otherwise the
    -- same kill would be both grouped under its objective and added again here.
    if farmingItem and creditedThisTick == 0 then
        for _, mob in ipairs(pendingKills) do
            start = start or GetTime()
            kills = kills + 1
            local key = GroupMob(mob)
            mobs[key] = mobs[key] + 1
            local breakdown = mobBreakdown[key]
            if not breakdown.counts[mob] then
                breakdown.counts[mob] = 0
                breakdown.order[#breakdown.order + 1] = mob
            end
            breakdown.counts[mob] = breakdown.counts[mob] + 1
        end
    end
    wipe(pendingKills)

    -- Keep every known group's displayed progress in sync with the quest log,
    -- even on ticks where nothing died (e.g. right after a /reload).
    for key, group in pairs(monsterGroups) do
        local obj = objectives[key]
        if obj then
            group.text, group.fulfilled, group.required = obj.text, obj.fulfilled, obj.required
        end
    end

    -- Each group's "work time" only runs while RestedXP's current step is actually
    -- about it - freezing while you're on an unrelated step and picking back up
    -- (from the saved total, not from zero) once it's relevant again. Without a
    -- known current step (onlyCurrentStep false), there's nothing to compare
    -- against, so every group just keeps ticking like a single shared timer did
    -- before this existed.
    for _, key in ipairs(groupOrder) do
        local group = monsterGroups[key]
        if not onlyCurrentStep or currentStepItems[group.text] then
            group.elapsed = (group.elapsed or 0) + dt
        end
    end

    local baseline = {}
    for key, obj in pairs(objectives) do baseline[key] = obj.fulfilled end
    lastMonsterCounts = baseline

    SyncGoals()

    for _, name in ipairs(itemOrder) do
        local item = items[name]
        if item.required and (not onlyCurrentStep or currentStepItems[name]) then
            item.elapsed = (item.elapsed or 0) + dt
        end
    end

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

SLASH_KILLTIMER1 = "/killtimer"
SlashCmdList.KILLTIMER = function(msg)
    if msg and msg:lower():match("^copy") then
        ShowCopyPopup()
    else
        Reset()
    end
end

Reset()
