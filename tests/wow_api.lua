-- Enough of the WoW API to load killTimer.lua outside the game and drive it:
-- frames are no-op stubs that remember their scripts and text, and the quest log,
-- loot and RestedXP state are plain tables the tests write to. Everything here is
-- global on purpose - that's the environment an addon runs in.

NOW = 1000              -- what GetTime() returns; Tick() advances it
FS = {}                 -- every FontString created, in creation order
FRAMES = {}             -- every frame created, in creation order
QUESTS = {}             -- the quest log: { { questID, objectives = { ... } }, ... }
ITEM_CLASS = {}         -- item name -> classID returned by GetItemInfoInstant
LOOT_SOURCE = nil       -- GUID the open loot window is reading from
PRINTS = {}             -- everything the addon printed to chat

local emit = print      -- the real print, for test output

function GetTime() return NOW end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function date() return "2026-11-20 12:00" end
function print(s) PRINTS[#PRINTS + 1] = tostring(s) end

tinsert = table.insert
UISpecialFrames = {}
SlashCmdList = {}
UNKNOWN = "Unknown"
COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
LOOT_ITEM_SELF = "You receive loot: %s."
ChatFontNormal = {}
C_Timer = { After = function(_, fn) fn() end }

-- Any method not named here is a no-op that returns nil, which is all the layout,
-- backdrop and font calls need to get through loading.
local function stub(kind)
    local o = { _kind = kind, _scripts = {} }
    o.SetScript = function(self, ev, fn) self._scripts[ev] = fn end
    o.GetScript = function(self, ev) return self._scripts[ev] end
    o.SetText = function(self, s) self._text = s end
    o.GetText = function(self) return self._text end
    o.SetShown = function(self, v) self._shown = v end
    o.GetPoint = function() return "TOPLEFT", nil, "TOP", 0, 0 end
    o.GetFontString = function() return stub("FontString") end
    o.CreateFontString = function()
        local fs = stub("FontString")
        FS[#FS + 1] = fs
        return fs
    end
    o.CreateTexture = function() return stub("Texture") end
    setmetatable(o, { __index = function(t, k)
        local noop = function() return nil end
        t[k] = noop
        return noop
    end })
    return o
end

function CreateFrame(kind, name)
    local f = stub(kind)
    FRAMES[#FRAMES + 1] = f
    if name then _G[name] = f end
    return f
end

UIParent = stub("Frame")

GameTooltip = stub("Frame")
GameTooltip._lines = {}
GameTooltip.AddLine = function(self, s) self._lines[#self._lines + 1] = s end

C_QuestLog = {
    GetNumQuestLogEntries = function() return #QUESTS end,
    GetInfo = function(i)
        local q = QUESTS[i]
        if not q then return nil end
        return { isHeader = false, questID = q.questID }
    end,
    GetQuestObjectives = function(questID)
        for _, q in ipairs(QUESTS) do
            if q.questID == questID then return q.objectives end
        end
        return {}
    end,
}

function GetNumLootItems() return LOOT_SOURCE and 1 or 0 end
function GetLootSourceInfo() return LOOT_SOURCE end

function GetItemInfoInstant(link)
    local name = link:match("%[(.-)%]")
    return 1234, "Quest", "Quest", "", 1, ITEM_CLASS[name] or 12
end

-- RestedXP: RXPCData.currentStep is the step number the addon watches, and
-- RXPFrame holds the guide window's internal frame pool it reads targets from.
RXPCData = {}
RXPFrame = nil

-- `elements` mimics one displayed step's elements, e.g.
-- { { text = "0/10 Hatefury Horn", questId = 100 } }. Passing none hides the
-- guide window entirely, like running without RestedXP.
function SetStep(n, elements)
    RXPCData = RXPCData or {}
    RXPCData.currentStep = n
    if elements then
        RXPFrame = { CurrentStepFrame = { framePool = { { step = { elements = elements } } } } }
    else
        RXPFrame = nil
    end
end

-- Quest log shorthands.
function Quest(id, objectives) return { questID = id, objectives = objectives } end

function MonsterObjective(text, fulfilled, required)
    return { type = "monster", text = text, numFulfilled = fulfilled, numRequired = required }
end

function ItemObjective(text, fulfilled, required)
    return { type = "item", text = text, numFulfilled = fulfilled, numRequired = required, finished = false }
end

local frame, OnEvent, OnUpdate

function LoadAddon(path)
    local chunk, err = loadfile(path)
    if not chunk then
        emit("LOAD ERROR: " .. tostring(err))
        os.exit(1)
    end
    chunk()
    frame = _G.killTimerFrame
    OnEvent = frame:GetScript("OnEvent")
    OnUpdate = frame:GetScript("OnUpdate")
    -- Creation order in killTimer.lua: title, header, body text.
    HEADER, BODY = FS[2], FS[3]
end

-- One OnUpdate tick. The default is just over the addon's own 0.2s throttle, so
-- a single call always produces a full update.
function Tick(dt)
    dt = dt or 0.25
    NOW = NOW + dt
    OnUpdate(frame, dt)
end

function Kill(mob)
    OnEvent(frame, "CHAT_MSG_COMBAT_XP_GAIN", mob .. " dies, you gain 50 experience.")
end

function LootReady(fromMob)
    LOOT_SOURCE = fromMob and "Creature-0-1-2-3-4-5" or "GameObject-0-1-2-3-4-5"
    OnEvent(frame, "LOOT_READY")
end

function Loot(item, qty)
    OnEvent(frame, "CHAT_MSG_LOOT", ("You receive loot: |cffffffff|Hitem:1234|h[%s]|h|r%s."):format(
        item, qty and ("x" .. qty) or ""))
end

function SlashCommand(command) return SlashCmdList.KILLTIMER(command or "") end
function SlashReset() SlashCommand("") end

local function strip(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- The overlay as the player sees it: header first, then one entry per body line.
function Display()
    local out = { strip(HEADER._text or "") }
    if BODY._text then
        for line in BODY._text:gmatch("[^\n]+") do out[#out + 1] = strip(line) end
    end
    return out
end

function Header() return Display()[1] end

function HeaderKills() return tonumber(Header():match("(%d+) kills")) or -1 end

function HeaderSeconds()
    local m, s = Header():match("(%d+):(%d%d)")
    if not m then return -1 end
    return tonumber(m) * 60 + tonumber(s)
end

function BodyHas(pattern)
    for i = 2, #Display() do
        local line = Display()[i]
        if line:find(pattern) then return true, line end
    end
    return false
end

-- Leading count on the body line matching `pattern`, e.g. 3 for "3  Kolkar".
function LineCount(pattern)
    local found, line = BodyHas(pattern)
    if not found then return nil end
    return tonumber(line:match("^(%d+)%s")), line
end

-- The per-mob breakdown, which lives in the panel's tooltip rather than the body.
function Tooltip()
    GameTooltip._lines = {}
    for _, fr in ipairs(FRAMES) do
        local fn = fr._scripts.OnEnter
        if fn then fn(fr) end
    end
    return GameTooltip._lines
end

function TooltipHas(pattern)
    for _, line in ipairs(Tooltip()) do
        if line:find(pattern) then return true, line end
    end
    return false
end

-- Assertions.
PASSED, FAILED = 0, 0

function Case(name)
    emit("\n" .. name)
end

function Check(label, condition, detail)
    if condition then
        PASSED = PASSED + 1
        emit("  ok    " .. label)
    else
        FAILED = FAILED + 1
        emit(("  FAIL  %s%s"):format(label, detail and ("\n          got: " .. tostring(detail)) or ""))
    end
end

function Report()
    emit(("\n%d passed, %d failed"):format(PASSED, FAILED))
    return FAILED == 0
end
