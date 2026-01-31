-- Automated PvP Tab Switch
-- Patch: 12.0.0 (Midnight pre-patch)
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

-- MIDNIGHT-only: unified PvP detection (arena + battleground) and secure override via a macro button
local function isMidnightRuntime()
    return type(SetOverrideBindingClick) == "function"
end

local function IsInPvPInstance()
    -- Primary: direct instance type (arena, pvp, battleground)
    local _, instanceType = IsInInstance()
    if instanceType then
        instanceType = tostring(instanceType):lower()
        if instanceType:find("arena") or instanceType:find("pvp") or instanceType:find("battleground") then
            return true, instanceType
        end
    end

    -- Fallback: GetInstanceInfo (some clients report differently)
    if type(GetInstanceInfo) == "function" then
        local _, giType = GetInstanceInfo()
        if giType and tostring(giType):lower():find("pvp") then
            return true, giType
        end
    end

    -- Battlefield API: treat any 'active' battlefield as inside a PvP instance
    if type(GetBattlefieldStatus) == "function" then
        for i = 1, 7 do
            local _, status = GetBattlefieldStatus(i)
            if status and tostring(status):lower() == "active" then
                return true, status
            end
        end
    end

    -- Optional zone PvP info (guarded)
    if type(GetZonePVPInfo) == "function" then
        local zonePvP = select(1, GetZonePVPInfo())
        if zonePvP and tostring(zonePvP):lower():find("battleground") then
            return true, zonePvP
        end
    end

    return false, nil
end

-- secure macro button (Midnight)
local secureBtn = CreateFrame("Button", "" .. ADDON_TAG .. "SecureBtn", UIParent, "SecureActionButtonTemplate")
secureBtn:SetAttribute("type", "macro")

local function ApplyOverride(pvpType)
    -- pvpType: string like 'arena' or 'battleground' (may be nil)
    local macro = "/targetenemyplayer"
    secureBtn:SetAttribute("macrotext", macro)

    -- clear previous overrides and bind TAB to click the secure button
    ClearOverrideBindings(frame)
    SetOverrideBindingClick(frame, false, "TAB", secureBtn:GetName())

    -- Verify the override actually took effect; if not, schedule a retry
    local bound = tostring(GetBindingAction("TAB") or ""):lower()
    local btnname = tostring(secureBtn:GetName() or ""):lower()
    if bound:find("click") and bound:find(btnname) then
        isApplied = true
        if pvpType and tostring(pvpType):lower():find("arena") then
            Print("Arena detected. TAB switched to target enemy players.")
        else
            Print("Battleground/PvP detected. TAB switched to target enemy players.")
        end
        return
    end

    -- If binding didn't stick, try again shortly (handles race conditions / other addons)
    isApplied = false
    Print("Warning: TAB override did not apply immediately — retrying shortly.")
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(0.5, UpdateState)
        C_Timer.After(1.5, UpdateState)
        C_Timer.After(4, UpdateState)
    else
        -- fallback immediate retry
        UpdateState()
    end
end

local function ClearOverride()
    ClearOverrideBindings(frame)
    isApplied = false
    Print("Left PvP instance. TAB restored to your normal binding.")
end

local function scheduleUpdate(delay)
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(delay, UpdateState)
    else
        -- fallback: call immediately (shouldn't happen on Midnight)
        UpdateState()
    end
end

function UpdateState()
    if not isMidnightRuntime() then
        Print("Disabled: this build is not Midnight — addon requires Midnight-only APIs.")
        return
    end

    if InCombatLockdown() then
        pendingAfterCombat = true
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")

-- Slash / diagnostics
SLASH_AUTOPVPTAB1 = "/autopvptab"
SlashCmdList["AUTOPVPTAB"] = function(msg)
    local cmd = (msg or ""):lower():match("^(%w+)") or "status"
    if cmd == "testpvp" or cmd == "testbg" then
        ApplyOverride("battleground")
        return
    elseif cmd == "testarena" then
        ApplyOverride("arena")
        return
    elseif cmd == "dump" then
        Print("--- Autopvptab dump ---")
        Print("IsInInstance(): " .. tostring(IsInInstance()))
        if type(GetInstanceInfo) == "function" then
            local a,b = GetInstanceInfo()
            Print("GetInstanceInfo() -> " .. tostring(a) .. ", " .. tostring(b))
        end
        if type(GetZonePVPInfo) == "function" then
            local z = select(1, GetZonePVPInfo())
            Print("GetZonePVPInfo() -> " .. tostring(z))
        end
        if type(GetBattlefieldStatus) == "function" then
            for i=1,7 do
                local _,status = GetBattlefieldStatus(i)
                if status and status ~= "" then
                    Print("GetBattlefieldStatus("..i..") -> "..tostring(status))
                end
            end
        end
        Print("GetBindingAction('TAB') -> " .. tostring(GetBindingAction("TAB")))
        Print("------------------------")
        return
    else
        if isMidnightRuntime() then
            Print(isApplied and "Currently using PvP tab." or "Currently using normal tab.")
        else
            Print("Disabled — requires Midnight client.")
        end
    end
end
        Print("Cannot change TAB during combat. Will retry after combat.")
        return
    end

    pendingAfterCombat = false
    frame:UnregisterEvent("PLAYER_REGEN_ENABLED")

    -- check PvP instance; force reapply when entering world to handle BG joins
    local inPvP, pvpType = IsInPvPInstance()
    if inPvP then
        if not isApplied then
            ApplyOverride(pvpType)
        else
            -- re-apply in case bindings were lost (force)
            ApplyOverride(pvpType)
        end
        return
    end

    if isApplied then
        ClearOverride()
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingAfterCombat then
            UpdateState()
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        -- battleground/instance state may finalise slightly after this event; do immediate + delayed checks
        UpdateState()
        scheduleUpdate(0.5)
        scheduleUpdate(2)
        scheduleUpdate(4)
        return
    end

    if event == "UPDATE_BATTLEFIELD_STATUS" then
        -- battlefield queue/confirm/enter updates — run several rechecks because join timing varies
        scheduleUpdate(0.3)
        scheduleUpdate(1.5)
        scheduleUpdate(4)
        return
    end

    -- other zone change events
    UpdateState()
end)

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")