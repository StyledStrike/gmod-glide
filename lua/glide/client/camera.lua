local Camera = Glide.Camera

Camera.hooks = Camera.hooks or {}
Camera.isInFirstPerson = Camera.isInFirstPerson == true
Camera.lastAimPos = Vector()

function Glide.GetCameraAimPos()
    return Camera.lastAimPos
end

hook.Add( "Glide_OnLocalEnterVehicle", "Glide.SetupCamera", function( vehicle, seatIndex )
    Camera:Initialize( LocalPlayer(), vehicle, seatIndex )
end )

hook.Add( "Glide_OnLocalExitVehicle", "Glide.ShutdownCamera", function()
    Camera:Shutdown()
end )

local function AddHook( name, priority )
    local id = "GlideCamera_" .. name
    Camera.hooks[id] = name

    hook.Add( name, id, function( a, b, c )
        return Camera[name]( Camera, a, b, c )
    end, priority )
end

function Camera:Initialize( user, vehicle, seatIndex )
    self.user = user
    self.vehicle = vehicle
    self.seatIndex = seatIndex

    self.fov = 80
    self.position = Vector()
    self.angles = self.vehicle:GetAngles()

    self.mode = 0
    self.isActive = false
    self.isUsingDirectMouse = false
    self.muffleSound = false
    self.allowRolling = false
    self.centerStrength = 0
    self.lastMouseMoveTime = 0

    self.distanceFraction = 1
    self.trailerDistanceFraction = 0

    self.punchAngle = Angle()
    self.punchVelocity = Angle()
    self.shakeOffset = Vector()

    self.lastAimEntity = NULL
    self.lastAimPosAnglesFromEyes = Angle()
    self.lastAimPosDistanceFromEyes = 0

    self:SetFirstPerson( self.isInFirstPerson )

    AddHook( "Think" )
    AddHook( "CalcView", HOOK_HIGH )
    AddHook( "CreateMove", HOOK_HIGH )
    AddHook( "PlayerBindPress" )
    AddHook( "InputMouseApply", HOOK_HIGH )
end

function Camera:Shutdown()
    if IsValid( self.vehicle ) then
        self.vehicle.isLocalPlayerInFirstPerson = false
    end

    if IsValid( self.user ) then
        self.user:SetDSP( 1 )
        self.user:SetEyeAngles( Angle() )
    end

    self.user = nil
    self.vehicle = nil
    self.seatIndex = nil
    self.lastAimEntity = NULL
    self.muffleSound = false

    for id, name in pairs( self.hooks ) do
        hook.Remove( name, id )
    end

    table.Empty( self.hooks )
end

function Camera:ShouldBeActive()
    if not self.user:Alive() then
        return false
    end

    if self.user:GetViewEntity() ~= self.user then
        return false
    end

    if pace and pace.Active then
        return false
    end

    return true
end

function Camera:SetFirstPerson( enable )
    local wasFixed = self:IsFixed()

    self.isInFirstPerson = enable
    self.centerStrength = 0
    self.lastMouseMoveTime = 0

    local muffleSound = self.isInFirstPerson
    local vehicle = self.vehicle

    if IsValid( vehicle ) then
        vehicle.isLocalPlayerInFirstPerson = enable
        muffleSound = muffleSound and vehicle:AllowFirstPersonMuffledSound( self.seatIndex )

        if self:IsFixed() ~= wasFixed then
            if wasFixed then
                self.angles = vehicle:LocalToWorldAngles( self.angles )
            else
                self.angles = vehicle:WorldToLocalAngles( self.angles )
            end
        end
    end

    self.muffleSound = muffleSound

    if IsValid( self.user ) then
        self.user:SetDSP( muffleSound and 30 or 1 )
    end
end

local Config = Glide.Config

function Camera:IsFixed()
    local fixedMode = Config.fixedCameraMode
    if fixedMode < 1 then return false end

    -- Fixed on first person only
    if fixedMode == 1 and self.isInFirstPerson then return true end

    -- Fixed on third person only
    if fixedMode == 2 and not self.isInFirstPerson then return true end

    -- Fixed on both first and third person
    return fixedMode > 2
end

local Abs = math.abs

function Camera:ViewPunch( pitch, yaw, roll )
    if not self.isActive then return end

    pitch = self.isInFirstPerson and pitch * 2 or pitch
    if Abs( pitch ) < Abs( self.punchVelocity[1] ) then return end

    self.punchVelocity[1] = pitch
    self.punchVelocity[2] = yaw or 0
    self.punchVelocity[3] = roll or 0

    self.punchAngle[1] = 0
    self.punchAngle[2] = 0
    self.punchAngle[3] = 0
end

local Cos = math.cos
local Clamp = math.Clamp
local ExpDecay = Glide.ExpDecay

local CAMERA_TYPE = Glide.CAMERA_TYPE

function Camera:DoEffects( t, dt, speed )
    -- Update view punch
    local vel, ang = self.punchVelocity, self.punchAngle

    ang[1] = ExpDecay( ang[1], 0, 6, dt ) + vel[1]
    ang[2] = ExpDecay( ang[2], 0, 6, dt ) + vel[2]

    local decay = self.isInFirstPerson and 8 or 10
    vel[1] = ExpDecay( vel[1], 0, decay, dt )
    vel[2] = ExpDecay( vel[2], 0, decay, dt )

    -- Update FOV depending on user settings and speed
    speed = speed - 400

    local fov = ( self.isInFirstPerson and Config.cameraFOVInternal or Config.cameraFOVExternal ) + Clamp( speed * 0.01, 0, 20 )
    local keyZoom = self.user:KeyDown( IN_ZOOM )

    self.fov = ExpDecay( self.fov, keyZoom and 20 or fov, keyZoom and 5 or 2, dt )

    -- Apply a small shake
    if self.mode == CAMERA_TYPE.CAR then
        local mult = Clamp( speed * 0.0005, 0, 1 ) * Config.shakeStrength

        self.shakeOffset[2] = Cos( t * 1.5 ) * 4 * mult
        self.shakeOffset[3] = ( ( Cos( t * 2 ) * 1.8 ) + ( Cos( t * 30 ) * 0.4 ) ) * mult
    end
end

local IsValid = IsValid
local RealTime = RealTime
local FrameTime = FrameTime

local TraceLine = util.TraceLine
local ExpDecayAngle = Glide.ExpDecayAngle

local MOUSE_FLY_MODE = Glide.MOUSE_FLY_MODE
local MOUSE_STEER_MODE = Glide.MOUSE_STEER_MODE

function Camera:Think()
    local vehicle = self.vehicle

    if not IsValid( vehicle ) then
        self:Shutdown()
        return
    end

    self.isActive = self:ShouldBeActive()
    if not self.isActive then return end

    local isSwitchKeyDown = self.user:KeyDown( IN_DUCK ) and not vgui.CursorVisible()

    if self.isSwitchKeyDown ~= isSwitchKeyDown then
        self.isSwitchKeyDown = isSwitchKeyDown

        if isSwitchKeyDown then
            self:SetFirstPerson( not self.isInFirstPerson )
        end
    end

    local t = RealTime()
    local dt = FrameTime()

    self.distanceFraction = ExpDecay( self.distanceFraction, 1, 2, dt )
    self.trailerDistanceFraction = ExpDecay( self.trailerDistanceFraction, vehicle:GetConnectedReceptacleCount() > 0 and 1 or 0, 2, dt )

    local velocity = vehicle:GetVelocity()
    local speed = Abs( velocity:Length() )
    local mode = vehicle:GetCameraType( self.seatIndex )

    self.mode = mode
    self:DoEffects( t, dt, speed )

    local freeLook = input.IsKeyDown( Config.binds.general_controls.free_look )

    if self:IsFixed() then
        if mode == CAMERA_TYPE.AIRCRAFT then
            self.isUsingDirectMouse = Config.mouseFlyMode == MOUSE_FLY_MODE.DIRECT and self.seatIndex == 1 and not freeLook

        elseif mode ~= CAMERA_TYPE.TURRET then
            self.isUsingDirectMouse = Config.mouseSteerMode == MOUSE_STEER_MODE.DIRECT and self.seatIndex == 1 and not freeLook
        end

        return
    end

    local angles = self.angles
    local vehicleAngles = vehicle:GetAngles()
    local decay, rollDecay = 3, 3

    if mode == CAMERA_TYPE.TURRET then
        self.centerStrength = 0
        self.allowRolling = false
        decay = 0

    elseif mode == CAMERA_TYPE.AIRCRAFT then
        self.isUsingDirectMouse = Config.mouseFlyMode == MOUSE_FLY_MODE.DIRECT and self.seatIndex == 1 and not freeLook
        self.allowRolling = Config.mouseFlyMode ~= MOUSE_FLY_MODE.AIM

        -- Only make the camera angles point towards the vehicle's
        -- forward direction while moving.
        decay = ( self.isUsingDirectMouse or self.isInFirstPerson ) and 6 or Clamp( ( speed - 5 ) * 0.01, 0, 1 ) * 3
        decay = decay * self.centerStrength

    else
        self.isUsingDirectMouse = Config.mouseSteerMode == MOUSE_STEER_MODE.DIRECT and self.seatIndex == 1 and not freeLook

        if self.isUsingDirectMouse then
            self.allowRolling = self.isInFirstPerson

            -- Make the camera angles always point towards
            -- the vehicle's forward direction.
            decay = 6 * self.centerStrength
            rollDecay = 8

        elseif self.isInFirstPerson then
            self.allowRolling = true

            -- Only make the camera angles point towards the vehicle's
            -- forward direction while moving.
            decay = Clamp( ( speed - 5 ) * 0.002, 0, 1 ) * 8 * self.centerStrength
            rollDecay = 8
        else
            self.allowRolling = false

            vehicleAngles = velocity:Angle()
            vehicleAngles[1] = vehicleAngles[1] + 5 * self.trailerDistanceFraction
            vehicleAngles[3] = 0

            -- Only make the camera angles point towards the vehicle's
            -- forward direction while moving.
            decay = Clamp( ( speed - 10 ) * 0.002, 0, 1 ) * 4 * self.centerStrength
        end
    end

    if self.allowRolling then
        -- Roll the camera so it stays "upright" relative to the vehicle
        vehicleAngles[3] = vehicleAngles[3] * vehicle:GetForward():Dot( angles:Forward() )
    end

    angles[1] = ExpDecayAngle( angles[1], vehicleAngles[1], decay, dt )
    angles[2] = ExpDecayAngle( angles[2], vehicleAngles[2], decay, dt )
    angles[3] = ExpDecayAngle( angles[3], self.allowRolling and vehicleAngles[3] or 0, rollDecay, dt )

    -- Recenter if some time has passed since last time we moved the mouse
    local allowAutoCenter = Config.enableAutoCenter and t > self.lastMouseMoveTime + Config.autoCenterDelay

    -- Recenter if using "Control movement directly"  on land vehicles,
    -- or using "Control movement directly" on aircraft.
    if self.seatIndex < 2 then
        allowAutoCenter = allowAutoCenter or self.isUsingDirectMouse
    end

    -- Don't recenter if using "Steer towards aim direction" on land vehicles,
    -- or if using "Point-to-aim" on aircraft.
    if
        ( mode == CAMERA_TYPE.AIRCRAFT and Config.mouseFlyMode == MOUSE_FLY_MODE.AIM ) or
        ( mode ~= CAMERA_TYPE.AIRCRAFT and Config.mouseSteerMode == MOUSE_STEER_MODE.AIM )
    then
        allowAutoCenter = false
    end

    -- Don't recenter on turrets
    if mode == CAMERA_TYPE.TURRET then
        allowAutoCenter = false
    end

    self.centerStrength = allowAutoCenter and ExpDecay( self.centerStrength, 1, 2, dt ) or 0
end

local traceResult = {}
local traceData = { filter = {}, output = traceResult }

function Camera:CalcView()
    if not self.isActive then return end

    local vehicle = self.vehicle
    if not IsValid( vehicle ) then return end

    local angles = self.angles

    if self:IsFixed() then
        -- Force to stay behind the vehicle while
        -- using direct mouse flying/steering mode.
        if self.isUsingDirectMouse then
            angles[1] = 0
            angles[2] = 0
        end

        angles[3] = 0
        angles = vehicle:LocalToWorldAngles( angles )
    end

    local user = self.user
    local offset, pivot

    if self.isInFirstPerson then
        local localEyePos = vehicle:WorldToLocal( user:EyePos() )
        local localPos = vehicle:GetFirstPersonOffset( self.seatIndex, localEyePos )
        pivot = vehicle:LocalToWorld( localPos )
        offset = Vector()
    else
        angles = angles + vehicle.CameraAngleOffset
        pivot = vehicle:LocalToWorld( vehicle.CameraCenterOffset + vehicle.CameraTrailerOffset * self.trailerDistanceFraction )

        offset = vehicle.CameraOffset * Vector( Config.cameraDistance *
            ( 1 + self.trailerDistanceFraction * vehicle.CameraTrailerDistanceMultiplier ), 1, Config.cameraHeight )

        -- Try to make the camera stay outside of walls
        local endPos = pivot
            + angles:Forward() * offset[1]
            + angles:Right() * offset[2]
            + angles:Up() * offset[3]

        local offsetDir = endPos - pivot
        local offsetLen = offsetDir:Length()
        offsetDir:Normalize()

        traceData.start = pivot
        traceData.endpos = endPos + offsetDir * 10
        traceData.mask = 16395 -- MASK_SOLID_BRUSHONLY

        TraceLine( traceData )

        fraction = self.distanceFraction

        if traceResult.Hit then
            fraction = ( offsetLen * traceResult.Fraction ) / offsetLen

            if fraction < self.distanceFraction then
                self.distanceFraction = fraction
            end
        end

        offset = self.shakeOffset + offset * fraction
    end

    self.position = pivot
        + angles:Forward() * offset[1]
        + angles:Right() * offset[2]
        + angles:Up() * offset[3]

    -- Cache the camera's aim properties.
    -- Start the trace from the camera's pivot point,
    -- without taking the "forward" axis into consideration.
    traceData.mask = nil
    traceData.start = pivot
        + angles:Right() * offset[2]
        + angles:Up() * offset[3]

    traceData.endpos = traceData.start + angles:Forward() * 50000
    traceData.filter[1] = user
    traceData.filter[2] = vehicle

    TraceLine( traceData )

    self.lastAimPos = traceResult.HitPos
    self.lastAimEntity = traceResult.Entity

    -- Save the aim angles and position distance
    -- to be used on the player's CUserCmd later.
    local aimDir = traceResult.HitPos - user:EyePos()
    self.lastAimPosDistanceFromEyes = aimDir:Length()

    aimDir:Normalize()
    self.lastAimPosAnglesFromEyes = aimDir:Angle()

    return {
        origin = self.position,
        angles = angles + self.punchAngle,
        fov = self.fov,
        drawviewer = not self.isInFirstPerson
    }
end

function Camera:CreateMove( cmd )
    if self.isActive then
        cmd:SetViewAngles( self.lastAimPosAnglesFromEyes )
        cmd:SetUpMove( Clamp( self.lastAimPosDistanceFromEyes, 0, 10000 ) )
    end
end

function Camera:PlayerBindPress( ply, bind )
    if self.isActive and ply == self.user and ( bind == "+right" or bind == "+left" ) then
        return false
    end
end

function Camera:InputMouseApply( _, x, y )
    if not self.isActive then return end
    if self.isUsingDirectMouse then return end

    local vehicle = self.vehicle
    if not IsValid( vehicle ) then return end

    local sensitivity = Config.lookSensitivity
    local lookX = ( Config.cameraInvertX and -x or x ) * 0.05 * sensitivity
    local lookY = ( Config.cameraInvertY and -y or y ) * 0.05 * sensitivity

    if Abs( lookX ) + Abs( lookY ) > 0.1 then
        self.lastMouseMoveTime = RealTime()
        self.centerStrength = 0
    end

    local angles = self.allowRolling and vehicle:WorldToLocalAngles( self.angles ) or self.angles

    angles[1] = Clamp( angles[1] + lookY, -80, 60 )
    angles[2] = ( angles[2] - lookX ) % 360

    self.angles = self.allowRolling and vehicle:LocalToWorldAngles( angles ) or angles
end
