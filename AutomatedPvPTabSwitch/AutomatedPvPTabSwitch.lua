-- AutomatedPvPTabSwitch.lua
-- 12.0.1 (midnight prepatch) compatible implementation — feature-detects APIs and avoids newer calls.

local ADDON = "AutomatedPvPTabSwitch"
local PREFIX = "|cff00ff00[Automated PvP]|r "
local f = CreateFrame("Frame")

-- Runtime compatibility guard: ensures only APIs present in 12.0.1 are used.
local function isRuntimeCompatible()
    if type(IsInInstance) ~= "function" then return false end
    if type(InCombatLockdown) ~= "function" then return false end
    -- we require at least one way to bind keys: override-click or legacy SetBinding
    if type(SetOverrideBindingClick) ~= "function" and type(SetBinding) ~= "function" then return false end
    return true
end

local function IsInPvPZone()
    -- Use only APIs that exist on 12.0.1; guard optional calls.
    local function isPvPType(t)
        if not t then return false end
        t = tostring(t):lower()
        if t:find("pvp") then return true end
        if t:find("arena") then return true end
        if t:find("battleground") then return true end
        return false
    end

    -- primary: IsInInstance()
    local _, instType = IsInInstance()
    if isPvPType(instType) then return true end

    -- fallback: GetInstanceInfo() — present in 12.0.1 but feature-detect anyway
    if type(GetInstanceInfo) == "function" then
        local _, giType = GetInstanceInfo()
        if isPvPType(giType) then return true end
    end

    -- optional: GetZonePVPInfo existed on many clients but may not be present everywhere — only call if available
    if type(GetZonePVPInfo) == "function" then
        local zonePvP = select(1, GetZonePVPInfo())
        if isPvPType(zonePvP) then return true end
    end

    return false
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

    -- apply the macro to the secure button (always safe)
    secureBtn:SetAttribute("macrotext", macro)

    -- clear overrides only if the API exists on this runtime
    if type(ClearOverrideBindings) == "function" then
        ClearOverrideBindings(f)
    end

    -- Preferred: bind TAB to click the secure button (does not modify saved keybinds)
    if type(SetOverrideBindingClick) == "function" then
        SetOverrideBindingClick(f, false, "TAB", secureBtn:GetName())
        appliedState = pvp
        announce(pvp and "Switching to PvP tab — using TAB to target players." or "Restored normal tab (targets NPCs).")
        return
    end

    -- Fallback: legacy SetBinding (may modify saved bindings). Only call SaveBindings if available.
    if type(SetBinding) == "function" then
        local command = pvp and "TARGETNEARESTPLAYERENEMY" or "TARGETNEARESTENEMY"
        SetBinding("TAB", command)
        if type(SaveBindings) == "function" and type(GetCurrentBindingSet) == "function" then
            SaveBindings(GetCurrentBindingSet())
        end
        appliedState = pvp
        announce(pvp and "Switching to PvP tab — using TAB to target players." or "Restored normal tab (targets NPCs).")
        return
    end

    -- If we reach here, runtime doesn't provide any usable binding API
    announce("AddOn disabled: required keybinding APIs not present on this client.")
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
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")

f:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        appliedState = nil
        if not isRuntimeCompatible() then
            announce("Disabled: this client lacks required APIs for 12.0.1 compatibility.")
            -- don't attempt any bindings
            return
        end
        -- visible debug message; delay the first binding until PLAYER_LOGIN where secure APIs are guaranteed
        announce("Loaded. Waiting for PLAYER_LOGIN to initialise bindings.")
        return
    end

    if event == "PLAYER_LOGIN" then
        -- secure APIs are ready — apply binding for the first time
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
