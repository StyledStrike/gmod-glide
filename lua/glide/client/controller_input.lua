CreateConVar( "glide_input_X", "0", FCVAR_USERINFO + FCVAR_UNREGISTERED, "Transmit the X axis to the server.", -1, 1 )
CreateConVar( "glide_input_Y", "0", FCVAR_USERINFO + FCVAR_UNREGISTERED, "Transmit the Y axis to the server.", -1, 1 )
CreateConVar( "glide_input_Z", "0", FCVAR_USERINFO + FCVAR_UNREGISTERED, "Transmit the Z axis to the server.", -1, 1 )

local ControllerInput = Glide.ControllerInput or {}

Glide.ControllerInput = ControllerInput

hook.Add( "Glide_OnLocalEnterVehicle", "Glide.ActivateControllerInput", function()
    ControllerInput:Activate()
end )

hook.Add( "Glide_OnLocalExitVehicle", "Glide.DeactivateControllerInput", function()
    ControllerInput:Deactivate()
end )

local Config = Glide.Config

function ControllerInput:Activate()
    local vehicle = Glide.currentVehicle

    if not IsValid( vehicle ) or Glide.currentSeatIndex > 1 then
        self:Deactivate()
        return
    end

    if
        not Glide.IsAircraft( vehicle )
        and Config.controllerInputMode == Glide.CONTROLLER_INPUT_MODE.ENABLED
        and vehicle:GetCameraType( 1 ) == Glide.CAMERA_TYPE.CAR
    then

        self:Prepare()

        return
    end
    self:Deactivate()
end

function ControllerInput:Prepare()
    self.controller = { 0, 0, 0 }
    self.freeLook = false
    self:Reset()

    self.cvarX = GetConVar( "glide_input_X" )
    self.cvarY = GetConVar( "glide_input_Y" )
    self.cvarZ = GetConVar( "glide_input_Z" )

    hook.Add( "Think", "Glide.UpdateControllerInput", function()
        local freeLook = input.IsKeyDown( Config.binds.general_controls.free_look ) or vgui.CursorVisible()

        if self.freeLook ~= freeLook then
            self.freeLook = freeLook
            self:Reset()
        end
    end )
end

function ControllerInput:Deactivate()
    hook.Remove( "Think", "Glide.UpdateControllerInput" )
end

function ControllerInput:Reset()
    self.cvarX:SetFloat( 0 )
    self.cvarY:SetFloat( 0 )
    self.cvarZ:SetFloat( 0 )
end

local Abs = math.abs
local Clamp = math.Clamp
local mult = 1 / 32768

local function ProcessInput( axis, deadzone, sensitivity )
    local value = input.GetAnalogValue( axis )
    if Abs( value ) < deadzone then return 0 end

    -- all of this can look kinda scary i guess
    local sign = value >= 0 and 1 or -1
    local normalized = Abs( value * mult ) 
    local out = sign * (normalized * normalized) * sensitivity 
    -- i use only multiplication to try to save on cpu cycles
    -- speed i feel is critical to keeping glide optimized and fast

    return Clamp( out, -1, 1 )
end
