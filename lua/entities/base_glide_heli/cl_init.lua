include( "shared.lua" )

function ENT:OnOutOfControlChange( _, _, value )
    if value then
        local path = ( "glide/helicopters/spinout_%d.wav" ):format( math.random( 1, 6 ) )
        local snd = self:CreateLoopingSound( "outOfControl", path, 100 )
        snd:PlayEx( 1, 100 )

    elseif self.sounds.outOfControl then
        self.sounds.outOfControl:Stop()
        self.sounds.outOfControl = nil
    end
end

--- Implement this base class function.
function ENT:OnTurnOn()
    if self:GetPower() < 0.1 then
        self:EmitSound( self.StartSound, 80, 100, 0.6 )
    end
end

--- Implement this base class function.
function ENT:OnActivateSounds()
    -- Create a client-side entity to play the tail rotor sound
    if self.TailSoundPath ~= "" then
        self.entTailRotor = ClientsideModel( "models/hunter/plates/plate.mdl" )
        self.entTailRotor:SetPos( self:LocalToWorld( self.TailRotorOffset ) )
        self.entTailRotor:Spawn()
        self.entTailRotor:SetParent( self )
        self.entTailRotor:SetNoDraw( true )

        self:CreateLoopingSound( "tail", self.TailSoundPath, self.TailSoundLevel, self.entTailRotor )
    end

    -- Create engine loop sounds
    self:CreateLoopingSound( "distant", self.DistantSoundPath, 90 )
    self:CreateLoopingSound( "engine", self.EngineSoundPath, self.EngineSoundLevel )
    self:CreateLoopingSound( "jet", self.JetSoundPath, self.JetSoundLevel )
end

--- Implement this base class function.
function ENT:OnDeactivateSounds()
    if IsValid( self.entTailRotor ) then
        self.entTailRotor:Remove()
        self.entTailRotor = nil
    end
end

local Clamp = math.Clamp
local GetVolume = Glide.Config.GetVolume

--- Implement this base class function.
function ENT:OnUpdateSounds()
    local sounds = self.sounds
    local vol = GetVolume( "aircraftVolume" )

    for id, snd in pairs( sounds ) do
        if not snd:IsPlaying() and id ~= "outOfControl" then
            snd:PlayEx( 0, 1 )
        end
    end

    local power = self:GetPower()

    if not self.isLazyThink then
        sounds.distant:ChangePitch( Clamp( power, 0, 1 ) * 100 )
        sounds.distant:ChangeVolume( Clamp( power - 0.2, 0, 0.8 ) * 0.5 * vol )

        sounds.engine:ChangePitch( Clamp( 0.6 + power * 0.4, 0, 1 ) * 100 )
        sounds.engine:ChangeVolume( ( Clamp( power - 0.2, 0, 1 ) * ( 1.3 - power ) ) * self.EngineSoundVolume * vol )

        sounds.jet:ChangePitch( Clamp( 0.6 + power * 0.4, 0, 1 ) * 100 )
        sounds.jet:ChangeVolume( Clamp( power - 0.2, 0, 1 ) * self.JetSoundVolume * vol )

        if sounds.tail then
            sounds.tail:ChangePitch( Clamp( 0.5 + power * 0.5, 0, 1 ) * 100 )
            sounds.tail:ChangeVolume( Clamp( power - 0.1, 0, 1 ) * 0.6 * vol )
        end
    end

    local isEngineDying = self:GetIsEngineDying() and LocalPlayer():GlideGetVehicle() == self

    if isEngineDying then
        if not sounds.engineWarning and self.EngineFailSound ~= "" then
            local snd = self:CreateLoopingSound( "engineWarning", self.EngineFailSound, 130, self )
            snd:PlayEx( self.EngineFailVolume, 130 )
        end

    elseif sounds.engineWarning then
        sounds.engineWarning:Stop()
        sounds.engineWarning = nil
    end
end
