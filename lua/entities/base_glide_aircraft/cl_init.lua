include( "shared.lua" )

DEFINE_BASECLASS( "base_glide" )

--- Implement this base class function.
function ENT:ShouldActivateSounds()
    return self:GetPower() > 0.1
end

--- Override this base class function.
function ENT:ActivateSounds()
    BaseClass.ActivateSounds( self )

    -- Setup variables for the beat sounds
    self.nextBeat = 0
    self.beatDiff = 0
end

local Clamp = math.Clamp
local Effect = util.Effect
local EffectData = EffectData

--- Implement this base class function.
function ENT:OnUpdateParticles()
    local health = self:GetEngineHealth()
    if health > 0.5 then return end

    local velocity = self:GetVelocity()
    local normal = -self:GetForward()
    local power = self:GetPower()

    health = Clamp( health * 255, 0, 255 )

    for _, pos in ipairs( self.ExhaustPositions ) do
        local eff = EffectData()
        eff:SetOrigin( self:LocalToWorld( pos ) )
        eff:SetNormal( normal )
        eff:SetColor( health )
        eff:SetMagnitude( power * 1000 )
        eff:SetStart( velocity )
        eff:SetScale( 1 )
        Effect( "glide_damaged_exhaust", eff, true, true )
    end
end

local RealTime = RealTime
local DrawLight = Glide.DrawLight
local DrawLightSprite = Glide.DrawLightSprite

--- Implement this base class function.
function ENT:OnUpdateMisc()
    if self:GetDriver() == NULL and self:GetPower() < 0.1 then return end

    -- Update strobe lights
    local t = RealTime()
    local on, pos, color

    t = t % 1

    for i, v in ipairs( self.StrobeLights ) do
        on = t > v.blinkTime and t < v.blinkTime + ( v.blinkDuration or 0.05 )

        if on then
            pos = self:LocalToWorld( v.offset )
            color = self.StrobeLightColors[i]

            if self.StrobeLightRadius > 0 then
                DrawLight( pos, color, self.StrobeLightRadius )
            end

            DrawLightSprite( pos, nil, self.StrobeLightSpriteSize, color )
        end
    end
end

local GetTable = FindMetaTable( "Entity" ).GetTable

--- Override this base class function.
function ENT:UpdateSounds()
    BaseClass.UpdateSounds( self )

    local selfTbl = GetTable( self )

    if selfTbl.RotorBeatInterval and selfTbl.RotorBeatInterval > 0 then
        self:DoRotorBeatSounds( selfTbl )
    end
end

local Abs = math.abs
local RealTime = RealTime

local GetVolume = Glide.Config.GetVolume
local PlaySoundSet = Glide.PlaySoundSet

function ENT:DoRotorBeatSounds( selfTbl )
    local t = RealTime()
    if t < selfTbl.nextBeat then return end

    local power = self:GetPower()
    local delay = selfTbl.RotorBeatInterval + Clamp( 0.6 - power, 0, 1 ) * 0.1

    -- Calculate the time difference between the time we expected to play
    -- the beat and the time when it actually played, to compensate frame inconsistencies.
    selfTbl.beatDiff = Clamp( t - selfTbl.nextBeat, -0.05, 0.05 )
    selfTbl.nextBeat = t + delay - selfTbl.beatDiff

    -- Change beat pitch/volume depending on power and angles
    local ang = self:GetAngles()
    local angMult = Clamp( ( Abs( ang[1] * 0.8 ) + Abs( ang[3] ) ) / 50, 0, 1 )

    local beatVolume = ( Clamp( power, 0, 1 ) - 0.1 ) * GetVolume( "aircraftVolume" )
    local beatPitch = 70 + ( 30 * power ) - ( angMult * 20 )
    local midVolume = ( selfTbl.MidSoundVol * 0.8 ) + selfTbl.MidSoundVol * angMult
    local highVolume = selfTbl.HighSoundVol - selfTbl.HighSoundVol * angMult * 0.4

    PlaySoundSet( selfTbl.BassSoundSet, self, beatVolume * selfTbl.BassSoundVol, beatPitch )
    PlaySoundSet( selfTbl.MidSoundSet, self, midVolume * beatVolume, beatPitch )
    PlaySoundSet( selfTbl.HighSoundSet, self, highVolume * beatVolume, beatPitch )
end
