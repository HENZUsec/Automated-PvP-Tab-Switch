-- Automated PvP Tab Switch
-- Patch: 12.0.1 (Midnight pre-patch)
-- Arena behavior:
--   TAB -> TARGETNEARESTENEMYPLAYER
-- Outside arena:
--   TAB -> user's normal binding

local ADDON_TAG = "|cff00ff88Automated PvP Tab Switch|r:"

local frame = CreateFrame("Frame")
local isApplied = false
local pendingAfterCombat = false

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(ADDON_TAG .. " " .. msg)
end

local function IsInArena()
    local _, instanceType = IsInInstance()
    return instanceType == "arena"
end

local function ApplyOverride()
    SetOverrideBinding(frame, true, "TAB", "TARGETNEARESTENEMYPLAYER")
    isApplied = true

    local action = GetBindingAction("TAB")
    if action == "TARGETNEARESTENEMYPLAYER" then
        Print("Arena detected. TAB switched to Target Nearest Enemy Player.")
    else
        Print("Arena detected. TAB override applied.")
    end
end

local function ClearOverride()
    ClearOverrideBindings(frame)
    isApplied = false
    Print("Left arena. TAB restored to your normal binding.")
end

local function UpdateState()
    if InCombatLockdown() then
        pendingAfterCombat = true
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        Print("Cannot change TAB during combat. Will retry after combat.")
        return
    end

    pendingAfterCombat = false
    frame:UnregisterEvent("PLAYER_REGEN_ENABLED")

    if IsInArena() then
        if not isApplied then
            ApplyOverride()
        end
    else
        if isApplied then
            ClearOverride()
        end
    end
end

frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingAfterCombat then
            UpdateState()
        end
        return
    end

    UpdateState()
end)

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")