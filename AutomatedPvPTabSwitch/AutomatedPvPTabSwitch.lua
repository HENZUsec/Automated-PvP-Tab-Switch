-- Automated PvP Tab Switch (12.0.0 / Interface 120000)
-- PvP instances (arena + battleground): TAB -> TARGETNEARESTENEMYPLAYER
-- Non-PvP instances: TAB -> TARGETNEARESTENEMY
--
-- Uses PRIORITY override bindings and only prints when mode actually changes.

local f = CreateFrame("Frame")
local lastMode = nil         -- "PVP" or "PVE"
local pendingMode = nil      -- boolean or nil (true = pvp, false = pve)

local function IsInstancedPvP()
    -- GetInstanceInfo is reliable for differentiating "pvp" and "arena"
    local _, instanceType = GetInstanceInfo()
    return instanceType == "pvp" or instanceType == "arena"
end

local function VerifyTab()
    -- true => include override bindings in the lookup
    return GetBindingAction("TAB", true)
end

local function PrintMode(isPvP, ok, detail)
    if isPvP then
        if ok then
            print("|cffe3ab2dAutomated PvP Tab Switch:|r |cffff7d0a[PvP]|r TAB -> Enemy Players")
        else
            print("|cffe3ab2dAutomated PvP Tab Switch:|r |cffff7d0a[PvP]|r failed: " .. (detail or "unknown"))
        end
    else
        if ok then
            print("|cffe3ab2dAutomated PvP Tab Switch:|r |cff00ff00[PvE]|r TAB -> Nearest Enemy")
        else
            print("|cffe3ab2dAutomated PvP Tab Switch:|r |cff00ff00[PvE]|r failed: " .. (detail or "unknown"))
        end
    end
end

local function ApplyTabBinding(isPvP)
    local mode = isPvP and "PVP" or "PVE"
    if lastMode == mode then return end

    -- Combat lockdown: defer once, do not spam
    if InCombatLockdown() then
        pendingMode = isPvP
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    lastMode = mode
    pendingMode = nil

    -- Always reset overrides we own, then set the desired one
    ClearOverrideBindings(f)

    -- PRIORITY override so we win vs non-priority overrides from other addons
    if isPvP then
        SetOverrideBinding(f, true, "TAB", "TARGETNEARESTENEMYPLAYER")
    else
        SetOverrideBinding(f, true, "TAB", "TARGETNEARESTENEMY")
    end

    -- Verify (including overrides)
    local action = VerifyTab()
    if isPvP and action == "TARGETNEARESTENEMYPLAYER" then
        PrintMode(true, true)
    elseif (not isPvP) and action == "TARGETNEARESTENEMY" then
        PrintMode(false, true)
    else
        PrintMode(isPvP, false, "TAB resolves to " .. tostring(action))
    end
end

local function Update()
    ApplyTabBinding(IsInstancedPvP())
end

-- Events: entering world covers instance transitions; zone change helps in some edge cases
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")

-- Debug: /apts
SLASH_APTS1 = "/apts"
SlashCmdList["APTS"] = function()
    local _, it = GetInstanceInfo()
    print("|cffe3ab2dAutomated PvP Tab Switch:|r instanceType=" .. tostring(it) ..
        " lastMode=" .. tostring(lastMode) ..
        " TAB(withOverride)=" .. tostring(VerifyTab()))
end

f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        f:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if pendingMode ~= nil then
            -- Force re-apply after combat
            lastMode = nil
            ApplyTabBinding(pendingMode)
        end
        return
    end

    Update()
end)
