local start, kills, lastStep, lastMob, lootFromMob
local mobs, mobOrder = {}, {}    -- mob name -> kill count (+ display order)
local items, itemOrder = {}, {}  -- item name -> { count = n, mobs = { mob name = true } }

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

local f = CreateFrame("Frame", "KillTimerFrame", UIParent)
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

-- Used both for the overlay and for the chat summary when a step ends.
local function Lines()
    local t = start and GetTime() - start or 0
    local out = { ("%d:%02d  %d kills"):format(math.floor(t / 60), math.floor(t % 60), kills or 0) }
    for _, name in ipairs(mobOrder) do
        out[#out + 1] = ("%d  %s"):format(mobs[name], name)
    end
    for _, name in ipairs(itemOrder) do
        local item, from = items[name], 0
        for mob in pairs(item.mobs) do from = from + mobs[mob] end
        if from > 0 then
            out[#out + 1] = ("|cff00ccff%d  %s (%d%%)|r"):format(
                item.count, name, math.floor(item.count / from * 100 + 0.5))
        else
            out[#out + 1] = ("|cff00ccff%d  %s|r"):format(item.count, name)
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
            item = { count = 0, mobs = {} }
            items[name] = item
            itemOrder[#itemOrder + 1] = name
        end
        item.count = item.count + (tonumber(msg:match("|h|rx(%d+)")) or 1)
        -- We're not told which mob the item came from, so it's attributed to the most recently killed one.
        item.mobs[lastMob] = true
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
            print("KillTimer: step " .. tostring(lastStep))
            for _, line in ipairs(lines) do print("  " .. line) end
            KillTimerLog = KillTimerLog or {}
            KillTimerLog[#KillTimerLog + 1] = {
                step = lastStep,
                time = date("%Y-%m-%d %H:%M"),
                result = table.concat(lines, "\n"),
            }
        end
        lastStep = step
        Reset()
    end
    text:SetText(table.concat(Lines(), "\n"))
end)

SLASH_KILLTIMER1 = "/killtimer"
SlashCmdList.KILLTIMER = Reset

Reset()
