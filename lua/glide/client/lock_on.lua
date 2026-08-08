-- Handle sound effects for missiles locked on the local player's vehicle.
local LockOnHandler = Glide.LockOnHandler or {}

Glide.LockOnHandler = LockOnHandler

LockOnHandler.missiles = LockOnHandler.missiles or {}
LockOnHandler.incomingLockCD = 0
LockOnHandler.incomingMissileCD = 0
LockOnHandler.lastBeep = 0

function LockOnHandler:OnIncomingLockOn()
    local t = RealTime()
    if t < self.incomingLockCD then return end

    self.incomingLockCD = t + 1
    surface.PlaySound( "glide/weapons/incoming_lockon.wav" )
end

local IsValid = IsValid

function LockOnHandler:OnIncomingMissile( entIndex )
    if not IsValid( self.vehicle ) then return end

    self.missiles[entIndex] = {
        timeout = RealTime() + 10
    }
end

function LockOnHandler:Setup( vehicle )
    self.vehicle = vehicle

    hook.Add( "Think", "Glide.UpdateLockOnHandler", function()
        self:Think()
    end )

    if self.beepSound ~= nil then return end

    local path = "sound/glide/weapons/incoming_missile_2.ogg"

    sound.PlayFile( path, "noplay noblock", function( snd, _, err )
        if not IsValid( snd ) then
            Glide.Print( "Failed to load lock-on sound '%s': %s", path, err )
            return
        end

        if not IsValid( self.vehicle ) then
            snd:Stop()
            return
        end

        self.beepSound = snd

        snd:EnableLooping( true )
        snd:SetVolume( 0.9 )
    end )
end

function LockOnHandler:Cleanup()
    hook.Remove( "Think", "Glide.UpdateLockOnHandler" )

    table.Empty( self.missiles )

    if IsValid( self.beepSound ) then
        self.beepSound:Stop()
    end

    self.vehicle = nil
    self.incomingLockCD = 0
    self.incomingMissileCD = 0
    self.lastBeep = 0
    self.beepSound = nil
end

local IsValid = IsValid
local BEEP_DIST = 15000 * 15000

function LockOnHandler:Think()
    if not IsValid( self.vehicle ) then
        self:Cleanup()
        return
    end

    local missiles = self.missiles
    local t = RealTime()

    -- Try to find the closest missile targeting us
    local myPos = self.vehicle:GetPos()
    local dist, closest = 9999999999, nil

    for id, data in pairs( missiles ) do
        if t > data.timeout then
            missiles[id] = nil
        else
            local ent = data.ent

            if ent == nil then
                -- Try to check if the entity exists clientside using it's ID
                ent = Entity( id )

                if IsValid( ent ) and ent.GetHasTarget then
                    data.ent = ent -- The missile finally exists clientside
                end

            elseif IsValid( ent ) and ent:GetHasTarget() then
                -- Is this the closest missile we have?
                local d = myPos:DistToSqr( ent:GetPos() )

                if d < dist then
                    dist = d
                    closest = ent
                end
            end
        end
    end

    local beepSound = self.beepSound

    if closest then
        if t > self.incomingMissileCD then
            self.incomingMissileCD = t + 1.8
            surface.PlaySound( "glide/weapons/incoming_missile_1.wav" )
        end

        if beepSound then
            dist = dist - 500

            local distanceFactor = math.Clamp( dist / BEEP_DIST, 0, 1 )
            local delay = distanceFactor * 1.8

            if not self.isPlayingBeep then
                self.isPlayingBeep = true
                self.lastBeep = t - 0.8
                beepSound:Play()
            end

            if t > self.lastBeep + delay then
                self.lastBeep = t
            end

            -- Make the beeps shorter as it gets closer
            local beepLen = math.min( 0.1, ( delay + 0.01 ) * 0.5 )

            beepSound:SetVolume( t < self.lastBeep + beepLen and 1 or 0 )
        end
    else
        -- Reset cooldowns, stop beeping
        if beepSound and self.isPlayingBeep then
            beepSound:Pause()
        end

        self.incomingMissileCD = 0
        self.isPlayingBeep = false
    end
end

local glideVehicle = nil
local GetParent = FindMetaTable( "Entity" ).GetParent
local GetVehicle = FindMetaTable( "Player" ).GetVehicle
local IsValid = IsValid

local function EnterVehicle( vehicle )
    if not IsValid( vehicle ) then return end
    local vehicleSelect = IsValid( GetParent( vehicle ) ) and GetParent( vehicle ) or vehicle
    if glideVehicle == vehicleSelect then return end

    LockOnHandler:Setup( vehicleSelect )
    glideVehicle = vehicleSelect
end

hook.Add( "Glide_OnLocalEnterVehicle", "Glide.LockOnHandlerSetup", EnterVehicle )
hook.Add( "Glide_OnLocalEnterNotGlideVehicle", "Glide.LockOnHandlerSetup", function( vehicle )
    -- In vehicle systems, a passenger's GetParent is nil. Moving to the next frame isn't enough; you need to add 0.1 seconds.
    timer.Create( "Glide.LockOnHandlerSetup", 0.1, 1, function()
        EnterVehicle( vehicle )
    end )
end )

local function ExitVehicle( bIsGlide )
    timer.Simple( 0.5, function()
        local ply = LocalPlayer()
        if not IsValid( ply ) then return end

        local vehicle = ply:GlideGetVehicle()
        if not bIsGlide then
            local vehicleTarget = GetVehicle( ply )
            vehicle = IsValid( vehicleTarget ) and GetParent( vehicleTarget ) or vehicleTarget
        end

        if IsValid( vehicle ) and glideVehicle == vehicle then return end

        LockOnHandler:Cleanup()
        glideVehicle = nil
    end )
end

hook.Add( "Glide_OnLocalExitVehicle", "Glide.LockOnHandlerCleanup", function()
    ExitVehicle( true )
end )

hook.Add( "Glide_OnLocalExitNotGlideVehicle", "Glide.LockOnHandlerCleanup", function()
    ExitVehicle( false )
end )