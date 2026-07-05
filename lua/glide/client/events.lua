local cvarIsMouseVisible = CreateConVar( "cl_glide_is_mouse_visible", "0", { FCVAR_USERINFO, FCVAR_DONTRECORD } )

concommand.Add( "glide_switch_seat", function( ply, _, args )
    if ply ~= LocalPlayer() then return end
    if #args == 0 then return end

    local seatIndex = tonumber( args[1] )
    if not seatIndex then return end

    local vehicle = ply:GlideGetVehicle()
    if not IsValid( vehicle ) then return end

    Glide.StartCommand( Glide.CMD_SWITCH_SEATS )
    net.WriteUInt( seatIndex, 5 )
    net.SendToServer()
end, nil, "Switch seats while inside a Glide vehicle." )

----- Check if the local player has entered/left a Glide vehicle.

local hideComponent = {
    ["CHudHealth"] = true,
    ["CHudBattery"] = true
}

local function HUDShouldDraw( name )
    if hideComponent[name] then return false end
end

-- Block (some) binds that uses the same buttons as Glide

local ACTION_FILTER = {
    ["countermeasures"] = true,
    ["landing_gear"] = true,
    ["shift_up"] = true,
    ["shift_down"] = true,
    ["shift_neutral"] = true
}

local usedButtons = {}

hook.Add( "Glide_OnConfigChange", "Glide.BlockBindConflicts", function()
    table.Empty( usedButtons )

    for _, actions in pairs( Glide.Config.binds ) do
        for action, button in pairs( actions ) do
            if ACTION_FILTER[action] then
                usedButtons[button] = true
            end
        end
    end
end )

local DONT_BLOCK = {
    ["+use"] = true,
    ["+reload"] = true,
    ["+attack"] = true,
    ["+attack2"] = true,
    ["+attack3"] = true,
    ["+walk"] = true
}

local function BlockBinds( _, bind, _, code )
    if usedButtons[code] and not DONT_BLOCK[bind] then
        return true
    end
end

local ScrW, ScrH = ScrW, ScrH
local activeVehicle = NULL
local cvarDrawHud = GetConVar( "cl_drawhud" )

local function DrawVehicleHUD()
    if
        IsValid( activeVehicle ) and
        cvarDrawHud:GetBool() and
        hook.Run( "Glide_CanDrawHUD", activeVehicle ) ~= false
    then
        activeVehicle:DrawVehicleHUD( ScrW(), ScrH() )
    end
end

local calcViewFunctions = {}
local sndFixed = GetConVar( "snd_fixed_rate" )
local bSetSNDFixed = false
local vguiCursorVisible = vgui.CursorVisible

function Glide.OnEnter( vehicle, seatIndex )
    vehicle:OnLocalPlayerEnter( seatIndex )
    vehicle.isLocalPlayerInVehicle = true
    vehicle.headlightState = 0

    activeVehicle = vehicle

    Glide.currentVehicle = vehicle
    Glide.currentSeatIndex = seatIndex

    hook.Add( "PlayerBindPress", "Glide.BlockBinds", BlockBinds )
    hook.Add( "HUDShouldDraw", "Glide.HideDefaultHealth", HUDShouldDraw )
    hook.Add( "HUDPaint", "Glide.DrawVehicleHUD", DrawVehicleHUD )
    hook.Run( "Glide_OnLocalEnterVehicle", vehicle, seatIndex )

    timer.Create( "Glide.CheckMouseVisibility", 0.25, 0, function()
        cvarIsMouseVisible:SetInt( vguiCursorVisible() and 1 or 0 )
    end )

    if vehicle.VehicleType == Glide.VEHICLE_TYPE.HELICOPTER and system.IsLinux() and sndFixed:GetInt() ~= 1 then
        Glide.Print( "Linux system detected, setting snd_fixed_rate to 1" )
        RunConsoleCommand( "snd_fixed_rate", "1" )
        bSetSNDFixed = true
    end

    -- Forcibly disable hooks from camera addons defined on Glide.CAMERA_CALC_VIEW_HOOKS
    local calcViewHookTable = hook.GetTable()["CalcView"]

    if calcViewHookTable then
        for hookId, _ in pairs( Glide.CAMERA_CALC_VIEW_HOOKS ) do
            local func = calcViewHookTable[hookId]

            if func then
                calcViewFunctions[hookId] = func
                hook.Remove( "CalcView", hookId )
            end
        end
    end
end

function Glide.OnLeave( ply )
    if IsValid( activeVehicle ) then
        activeVehicle:OnLocalPlayerExit()
        activeVehicle.isLocalPlayerInVehicle = false
        activeVehicle.headlightState = 0
    end

    activeVehicle = nil

    Glide.currentVehicle = nil
    Glide.currentSeatIndex = nil
    Glide.ResetBoneManipulations( ply )

    hook.Remove( "PlayerBindPress", "Glide.BlockBinds" )
    hook.Remove( "HUDShouldDraw", "Glide.HideDefaultHealth" )
    hook.Remove( "HUDPaint", "Glide.DrawVehicleHUD" )
    hook.Run( "Glide_OnLocalExitVehicle" )

    if system.IsLinux() and sndFixed:GetInt() == 1 and bSetSNDFixed then
        Glide.Print( "Linux system detected, setting snd_fixed_rate to 0" )
        RunConsoleCommand( "snd_fixed_rate", "0" )
    end

    timer.Remove( "Glide.CheckMouseVisibility" )
    cvarIsMouseVisible:SetInt( 0 )

    -- Restore disabled hooks from camera addons defined on Glide.CAMERA_CALC_VIEW_HOOKS
    for hookId, func in pairs( calcViewFunctions ) do
        hook.Add( "CalcView", hookId, func )
    end
end