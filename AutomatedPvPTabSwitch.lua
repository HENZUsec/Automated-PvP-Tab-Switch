local f = CreateFrame("Frame")

local function IsInPvPZone()
    local instType = select(2, IsInInstance())
    return instType == "arena" or instType == "pvp"
end

local function SetTabKeybind(pvp)
    if pvp then
        SetBinding("TAB", "TARGETNEARESTPLAYERENEMY")
    else
        SetBinding("TAB", "TARGETNEARESTENEMY")
    end
    SaveBindings(GetCurrentBindingSet())
end

f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")

f:SetScript("OnEvent", function(self, event, ...)
    local pvp = IsInPvPZone()
    SetTabKeybind(pvp)
end)
