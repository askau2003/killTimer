local start, kills, lastStep, lastMob, lootFromMob
local mobs, mobOrder = {}, {}    -- mob name -> kill count (+ display order)
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

local f = CreateFrame("Frame", "killTimerFrame", UIParent)
f:SetSize(220, 20)
f:SetPoint("TOP", 0, -120)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)

local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
text:SetPoint("TOPLEFT")
text:SetJustifyH("LEFT")

-- Active "item" quest objectives (e.g. "Wolf Pelt: 2/8"), keyed by item name.
-- Lets a required item show up at 0% from the first kill, not just after the first drop.
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
                    local name = obj.text:match("^(.-)%s*:?%s*%d+%s*/%s*%d+$") or obj.text
                    if name ~= "" then
                        goals[name] = { fulfilled = obj.numFulfilled, required = obj.numRequired }
                    end
                end
            end
        end
    end
    return goals
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
    local onlyCurrentStep = next(currentStepItems) ~= nil
    for name, goal in pairs(QuestItemGoals()) do
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

-- Used both for the overlay and for the chat summary when a step ends.
local function Lines()
    local t = start and GetTime() - start or 0
    local out = { ("%d:%02d  %d kills"):format(math.floor(t / 60), math.floor(t % 60), kills or 0) }
    for _, name in ipairs(mobOrder) do
        out[#out + 1] = ("%d  %s"):format(mobs[name], name)
    end
    for _, name in ipairs(itemOrder) do
        local item = items[name]
        local pct = kills > 0 and math.floor(item.count / kills * 100 + 0.5) or 0
        if item.required then
            out[#out + 1] = ("|cff00ccff%d  %s (%d%%)  %d/%d|r"):format(
                item.count, name, pct, item.fulfilled or 0, item.required)
        else
            out[#out + 1] = ("|cff00ccff%d  %s (%d%%)|r"):format(item.count, name, pct)
        end
    end
    return out
end

local function Reset()
    start, kills, lastMob = nil, 0, nil
    wipe(mobs) wipe(mobOrder) wipe(items) wipe(itemOrder)
end

f:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
f:RegisterEvent("CHAT_MSG_LOOT")
f:RegisterEvent("LOOT_READY")
f:SetScript("OnEvent", function(_, event, msg)
    if event == "CHAT_MSG_COMBAT_XP_GAIN" then
        local mob = msg:match(killPattern)
        if not mob then return end
        start = start or GetTime()
        kills = kills + 1
        if not mobs[mob] then
            mobs[mob] = 0
            mobOrder[#mobOrder + 1] = mob
        end
        mobs[mob] = mobs[mob] + 1
        lastMob = mob

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
        Reset()
    end
    SyncGoals()
    text:SetText(table.concat(Lines(), "\n"))
end)

SLASH_KILLTIMER1 = "/killtimer"
SlashCmdList.KILLTIMER = Reset

Reset()
