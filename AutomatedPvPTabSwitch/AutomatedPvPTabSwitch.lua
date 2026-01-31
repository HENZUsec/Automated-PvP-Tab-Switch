-- AutomatedPvPTabSwitch.lua
-- Adds announcements and combat-safe binding application.

local ADDON = "AutomatedPvPTabSwitch"
local PREFIX = "|cff00ff00[Automated PvP]|r "
local f = CreateFrame("Frame")

local function IsInPvPZone()
    local instType = select(2, IsInInstance())
    return instType == "arena" or instType == "pvp"
end

-- Apply the TAB binding (combat-safe). If in combat, queue the change.
local pendingBinding = nil
local appliedState = nil -- nil = unknown, true = PvP binding applied, false = normal

local function announce(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
    else
        print(PREFIX .. msg)
    end
end

-- Secure hidden button that runs a macro. Using macro text is more stable across API/name changes
-- than relying on internal action strings (which can change between patches).
local secureBtn = CreateFrame("Button", ADDON .. "SecureTargetButton", UIParent, "SecureActionButtonTemplate")
secureBtn:SetAttribute("type", "macro")

local function applyBindingNow(pvp)
    -- macros are more future-proof than raw action names
    local macro = pvp and "/targetenemyplayer" or "/targetenemy"

    -- attempt secure-override binding (preferred)
    secureBtn:SetAttribute("macrotext", macro)
    ClearOverrideBindings(f)
    -- SetOverrideBindingClick binds the key to click the secure button which runs the macro
    if SetOverrideBindingClick then
        SetOverrideBindingClick(f, false, "TAB", secureBtn:GetName())
        appliedState = pvp
        announce(pvp and "Switching to PvP tab — using TAB to target players." or "Restored normal tab (targets NPCs).")
        return
    end

    -- fallback: older/rare environments — try regular bindings
    local command = pvp and "TARGETNEARESTPLAYERENEMY" or "TARGETNEARESTENEMY"
    SetBinding("TAB", command)
    SaveBindings(GetCurrentBindingSet())
    appliedState = pvp
    announce(pvp and "Switching to PvP tab — using TAB to target players." or "Restored normal tab (targets NPCs).")
end

local function ApplyBinding(pvp)
    if InCombatLockdown() then
        pendingBinding = pvp
        announce("In combat — will switch after combat ends.")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    -- only apply if state changed (avoids spam and unnecessary SaveBindings)
    if appliedState == pvp then
        return
    end

    applyBindingNow(pvp)
end

-- Events
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")

f:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        -- initial debug/visibility message
        announce("Loaded. Use /reload or zone into a PvP instance to test.")
        -- set initial state (safe: may be called before LOGIN but OK on ADDON_LOADED)
        appliedState = nil
        ApplyBinding(IsInPvPZone())
        return
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        local pvp = IsInPvPZone()
        -- only announce/apply when state actually changes
        if pvp ~= appliedState then
            ApplyBinding(pvp)
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        f:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if pendingBinding ~= nil then
            ApplyBinding(pendingBinding)
            pendingBinding = nil
        end
        return
    end
end)

-- Optional slash command for quick testing
SLASH_AUTOPVPTAB1 = "/autopvptab"
SlashCmdList["AUTOPVPTAB"] = function(msg)
    local cmd = msg:lower():match("^(%w+)") or "status"
    if cmd == "testpvp" then
        ApplyBinding(true)
    elseif cmd == "testnorm" then
        ApplyBinding(false)
    else
        announce((appliedState and "Currently using PvP tab." ) or (appliedState == false and "Currently using normal tab.") or "State unknown — re-zone or /reload to initialise.")
    end
end
