-- WoW runs Lua 5.1 and exposes its whole API as globals, so every API name the
-- addon touches is listed here: anything not in these tables is a typo rather
-- than an API call, which is most of what this linter is worth on an addon.
std = "lua51"
max_line_length = 120

read_globals = {
    -- Frames and widgets
    "CreateFrame",
    "UIParent",
    "GameTooltip",
    "ChatFontNormal",
    "UISpecialFrames",
    -- Namespaced API
    "C_Item",
    "C_QuestLog",
    "C_Timer",
    -- Functions
    "GetItemInfoInstant",
    "GetLootSourceInfo",
    "GetNumLootItems",
    "GetTime",
    "date",
    "tinsert",
    "wipe",
    -- Options panel registration, old and new client UI
    "InterfaceOptions_AddCategory",
    "Settings",
    -- Localized strings the kill/loot patterns are built from
    "COMBATLOG_XPGAIN_FIRSTPERSON",
    "LOOT_ITEM_SELF",
    "UNKNOWN",
    -- RestedXP, read defensively: absent unless the player has it installed
    "RXPCData",
    "RXPFrame",
}

globals = {
    -- Saved variables, declared in killTimer.toc
    "killTimerDB",
    "killTimerLog",
    -- Handoff between killTimer.lua and killTimerOptions.lua
    "killTimerNS",
    -- Slash command registration
    "SLASH_KILLTIMER1",
    "SlashCmdList",
}

-- The test harness stands in for that same global environment, so it defines
-- globals on purpose. Listing what it exports keeps the specs checkable too -
-- this is the contract between tests/wow_api.lua and the spec files.
files["tests/"] = {
    globals = {
        -- Stubbed client state the tests write to
        "NOW", "FS", "FRAMES", "QUESTS", "ITEM_CLASS", "LOOT_SOURCE", "PRINTS",
        "HEADER", "BODY",
        -- The stubbed API itself
        "CreateFrame", "UIParent", "GameTooltip", "ChatFontNormal", "UISpecialFrames",
        "C_Item", "C_QuestLog", "C_Timer",
        "GetItemInfoInstant", "GetLootSourceInfo", "GetNumLootItems", "GetTime",
        "date", "tinsert", "wipe", "print",
        "COMBATLOG_XPGAIN_FIRSTPERSON", "LOOT_ITEM_SELF", "UNKNOWN",
        "RXPCData", "RXPFrame",
        "killTimerDB", "killTimerLog", "killTimerNS",
        "SLASH_KILLTIMER1", "SlashCmdList",
        -- Harness API used by the specs
        "LoadAddon", "SetStep", "Quest", "MonsterObjective", "ItemObjective",
        "Tick", "Kill", "LootReady", "Loot", "SlashCommand", "SlashReset",
        "Display", "Header", "HeaderKills", "HeaderSeconds",
        "BodyHas", "LineCount", "Tooltip", "TooltipHas",
        "Case", "Check", "Report", "PASSED", "FAILED",
    },
}
