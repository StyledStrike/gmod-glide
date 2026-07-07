include( "shared.lua" )

local EntityMeta = FindMetaTable( "Entity" )
local GetTable = EntityMeta.GetTable

function ENT:Initialize()
    self.isActive = false
    self.modelCD = 0
    self.particleCD = 0

    self.sounds = {}
    self.soundSurface = {}
    self.soundPitchMult = math.Rand( 0.9, 1.1 )

    self.enableParticles = true
    self.enableSkidmarks = true
end

function ENT:OnRemove()
    self:CleanupSounds()
end

function ENT:CleanupSounds()
    self.lastSkidId = nil
    self.lastRollId = nil

    for _, snd in pairs( self.sounds ) do
        snd:Stop()
    end

    table.Empty( self.sounds )
    table.Empty( self.soundSurface )
end

local IsString = isstring
local Clamp = math.Clamp
local GetVolume = Glide.Config.GetVolume

function ENT:ProcessSound( vehicle, id, surfaceId, soundSet, altSurface, volume, pitch, selfTbl, vehicleTbl )
    if not selfTbl.GetSoundsEnabled( self ) then return end

    local path = IsString( soundSet ) and soundSet or (
        vehicleTbl:OverrideWheelSound( vehicle, id, surfaceId ) or soundSet[surfaceId] )
    local snd = selfTbl.sounds[id]

    -- Remove the sound if we're on the air, or the volume is too low,
    -- or we are missing a sound path/alternative sound path for this surface.
    if surfaceId == 0 or volume < 0.01 or ( not path and not altSurface ) then
        if snd then
            snd:Stop()
            selfTbl.sounds[id] = nil
        end

        return
    end

    -- Remove the sound if the surface has changed since the last call
    if surfaceId ~= selfTbl.soundSurface[id] then
        selfTbl.soundSurface[id] = surfaceId

        if snd then
            selfTbl.sounds[id] = nil
            snd:Stop()
            snd = nil
        end
    end

    if not snd then
        snd = CreateSound( self, path or soundSet[altSurface] )
        snd:SetSoundLevel( 80 )
        snd:PlayEx( 0, 100 )
        selfTbl.sounds[id] = snd
    end

    snd:ChangeVolume( volume )
    snd:ChangePitch( pitch * selfTbl.soundPitchMult )
end

local WHEEL_SOUNDS = Glide.WHEEL_SOUNDS
local ROLL_VOLUME = Glide.WHEEL_SOUNDS.ROLL_VOLUME
local ROLL_MARK_SURFACES = Glide.ROLL_MARK_SURFACES

local AddSkidMarkPiece = Glide.AddSkidMarkPiece
local AddTireRollPiece = Glide.AddTireRollPiece

local IsValid = IsValid
local CurTime = CurTime
local Abs = math.abs

local Effect = util.Effect
local EffectData = EffectData
local IsUnderWater = Glide.IsUnderWater

local m = Matrix()
local MAT_SLOSH = MAT_SLOSH

local HARD_SURFACES = {
    [MAT_DEFAULT] = true,
    [MAT_CONCRETE] = true,
    [MAT_PLASTIC] = true,
    [MAT_VENT] = true,
    [MAT_WOOD] = true,
    [MAT_GLASS] = true,
    [MAT_GRATE] = true,
    [MAT_METAL] = true,
    [MAT_TILE] = true,
}

function ENT:Think()
    local t = CurTime()

    local selfTbl = GetTable( self )
    self:SetNextClientThink( t + 0.01 )

    -- Periodically rotate and resize the wheel model
    if t > selfTbl.modelCD then
        m:SetTranslation( selfTbl.GetModelOffset( self ) )
        m:SetAngles( selfTbl.GetModelAngle( self ) )
        m:SetScale( selfTbl.GetModelScale2( self ) )
        self:EnableMatrix( "RenderMultiply", m )
        selfTbl.modelCD = t + 1
    end

    local parent = self:GetParent()
    if not IsValid( parent ) then return true end

    local parentTbl = GetTable( parent )
    if not parentTbl.rfMisc then return true end

    -- Stop processing when the "rfMisc" RangedFeature
    -- from our parent vehicle is not active.
    -- (When the player is too far away or out of the PVS).
    local isActive = parentTbl.rfMisc.isActive
    if not isActive then return true end

    local velocity = parent:GetVelocity()
    local speed = Abs( parent:WorldToLocal( parent:GetPos() + velocity )[1] )
    local baseVolume = GetVolume( "carVolume" )

    local up = parent:GetUp()
    local surfaceId = selfTbl.GetContactSurface( self )
    local contactPos = self:GetPos() - up * selfTbl.GetRadius( self )

    -- Force water surface when contactPos is under water
    if surfaceId > 0 and IsUnderWater( contactPos ) then
        surfaceId = MAT_SLOSH
    end

    -- Mute concrete sounds when this wheel is part of a tank
    local muteRollSound = surfaceId == 67 and parentTbl.VehicleType == 5

    -- Disable some effects when a blown tire is touching a "hard" surface
    local isBlownOnHardSurface = selfTbl.IsBlown( self ) and HARD_SURFACES[surfaceId]

    -- Fast roll sound
    local fastFactor = speed / 600

    selfTbl.ProcessSound( self, parent, "fastRoll", surfaceId, WHEEL_SOUNDS.ROLL, nil,
        Clamp( fastFactor * 0.75, 0, ROLL_VOLUME[surfaceId] or 0.4 ) * baseVolume, 70 + 25 * fastFactor, selfTbl, parentTbl )

    -- Slow roll sound
    local slowFactor = ( isBlownOnHardSurface or muteRollSound ) and 0 or 1.02 - fastFactor

    selfTbl.ProcessSound( self, parent, "slowRoll", surfaceId, WHEEL_SOUNDS.ROLL_SLOW, 88,
        slowFactor * fastFactor * 2 * baseVolume, 110 - 30 * slowFactor, selfTbl, parentTbl )

    -- Side slip sound
    local sideSlipFactor = muteRollSound and 0 or Abs( selfTbl.GetSideSlip( self ) ) - 0.1

    sideSlipFactor = Clamp( sideSlipFactor * 1.5, 0, 0.8 )

    selfTbl.ProcessSound( self, parent, "sideSlip", surfaceId, WHEEL_SOUNDS.SIDE_SLIP, nil,
        ( isBlownOnHardSurface and 0 or sideSlipFactor ) * baseVolume, 110 - 30 * sideSlipFactor, selfTbl, parentTbl )

    -- Forward slip sound
    local forwardSlip = selfTbl.GetForwardSlip( self ) * 0.04
    local forwardSlipFactor = Clamp( Abs( forwardSlip ) - 0.1, 0, 1 )

    selfTbl.ProcessSound( self, parent, "forwardSlip", surfaceId, WHEEL_SOUNDS.FORWARD_SLIP, 88,
        ( isBlownOnHardSurface and 0 or forwardSlipFactor )  * baseVolume, 100 - forwardSlipFactor * 10, selfTbl, parentTbl )

    -- Blown tire/rim sound
    local blownTire = isBlownOnHardSurface and Clamp( sideSlipFactor + forwardSlipFactor + ( speed / 1000 ), 0, 1 ) or 0

    selfTbl.ProcessSound( self, parent, "blownTire", surfaceId, "glide/wheels/blowout_wheel_rim.wav", 88,
        blownTire * 0.8 * baseVolume, 80 + blownTire * 30, selfTbl, parentTbl )

    if muteRollSound then
        selfTbl.lastSkidId = nil
        selfTbl.lastRollId = nil

        return true
    end

    if t < selfTbl.particleCD then
        return true
    end

    selfTbl.particleCD = t + 0.05

    if blownTire > 0.1 then
        local normal = ( parent:GetForward() * ( forwardSlip > 1 and 1 or -1 ) ) + up * 0.2

        local eff = EffectData()
        eff:SetOrigin( contactPos + up )
        eff:SetNormal( normal * blownTire * 2 )
        eff:SetScale( blownTire )
        eff:SetColor( 200 )
        Effect( "glide_metal_impact", eff )
    end

    if isBlownOnHardSurface then return end

    -- Emit side slip/tire roll particles
    local particleSize = Clamp( selfTbl.GetRadius( self ), 5, 10 )
    local rollFactor = sideSlipFactor - 0.5

    if ROLL_MARK_SURFACES[surfaceId] or surfaceId == MAT_SLOSH then
        rollFactor = rollFactor + fastFactor
    end

    if rollFactor > 0.1 and selfTbl.enableParticles then
        rollFactor = Clamp( rollFactor, 0, 0.5 )

        local eff = EffectData()
        eff:SetOrigin( contactPos )
        eff:SetStart( velocity )
        eff:SetSurfaceProp( surfaceId )
        eff:SetScale( particleSize * rollFactor )
        eff:SetEntity( parent )
        Effect( "glide_tire_roll", eff )
    end

    if forwardSlipFactor > 0.2 and selfTbl.enableParticles then
        forwardSlipFactor = Clamp( forwardSlipFactor, 0, 1 )

        local eff = EffectData()
        eff:SetOrigin( contactPos )
        eff:SetSurfaceProp( surfaceId )
        eff:SetScale( particleSize * forwardSlipFactor )
        eff:SetNormal( parent:GetForward() * ( forwardSlip > 1 and 1 or -1 ) )
        eff:SetEntity( parent )
        Effect( "glide_tire_slip_forward", eff )
    end

    if surfaceId == MAT_SLOSH then
        selfTbl.lastSkidId = nil
        selfTbl.lastRollId = nil
        return true
    end

    if not selfTbl.enableSkidmarks then return true end

    -- Create skidmarks
    local skidmarkSize = selfTbl.GetRadius( self ) * parentTbl.WheelSkidmarkScale

    contactPos = contactPos + velocity * 0.04

    if ROLL_MARK_SURFACES[surfaceId] then
        if Abs( fastFactor ) + forwardSlipFactor + sideSlipFactor > 0.01 then
            selfTbl.lastRollId = AddTireRollPiece( selfTbl.lastRollId, contactPos, velocity, up, skidmarkSize, 1 )
        else
            selfTbl.lastRollId = nil
        end

        -- Don't create skidmarks if this surface uses roll marks
        selfTbl.lastSkidId = nil
        return true
    end

    selfTbl.lastRollId = nil

    local totalSlipFactor = Clamp( forwardSlipFactor + sideSlipFactor, 0, 1 )

    if totalSlipFactor > 0.3 then
        selfTbl.lastSkidId = AddSkidMarkPiece( selfTbl.lastSkidId, contactPos, velocity, up, skidmarkSize, totalSlipFactor )
    else
        selfTbl.lastSkidId = nil
    end

    return true
end
