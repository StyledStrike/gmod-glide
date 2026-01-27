include( "shared.lua" )
include( "cl_lights.lua" )
include( "cl_hud.lua" )
include( "cl_water.lua" )
include( "sh_vehicle_compat.lua" )

ENT.AutomaticFrameAdvance = true

function ENT:OnReloaded()
    -- Let UpdateHeadlights recreate the lights
    self.headlightState = 0

    -- Let children classes do their own logic
    self:OnEntityReload()
end

function ENT:Initialize()
    self.shouldThinkNow = false
    self.lazyThinkCD = 0

    self.sounds = {}
    self.isSoundActive = false
    self.isLocalPlayerInFirstPerson = false
    self.isLocalPlayerInVehicle = false
    self.waterSideSlide = 0

    self.weapons = {}
    self.weaponSlotIndex = 0

    -- Create a RangedFeature to handle automatic creation/destruction of
    -- features like sounds, lights, particles and animations.
    self.rfMisc = Glide.CreateRangedFeature( self, self.MaxFeaturesDistance )
    self.rfMisc:SetActivateCallback( "InternalActivateFeatures" )
    self.rfMisc:SetDeactivateCallback( "InternalDeactivateFeatures" )
    self.rfMisc:SetUpdateCallback( "InternalUpdateFeatures" )

    self:OnPostInitialize()
end

function ENT:OnRemove( fullUpdate )
    if self.lockOnSound then
        self.lockOnSound:Stop()
        self.lockOnSound = nil
    end

    if fullUpdate then return end

    if self.rfMisc then
        self.rfMisc:Destroy()
        self.rfMisc = nil
    end
end

function ENT:OnEngineStateChange( _, lastState, state )
    if state == 1 then
        -- If we have a "startup" sound, play it now.
        if self.rfMisc and self.rfMisc.isActive and self.StartSound and self.StartSound ~= "" then
            local snd = self:CreateLoopingSound( "start", Glide.GetRandomSound( self.StartSound ), 70, self )
            snd:PlayEx( 1, 100 )
        end

    elseif lastState ~= 3 and state == 2 then
        self:OnTurnOn()

    elseif state == 0 then
        self:OnTurnOff()
    end
end

local IsValid = IsValid

function ENT:GetWheelSpin( index )
    local wheel = self.wheels and self.wheels[index]

    if IsValid( wheel ) and wheel.GetLastSpin then
        return wheel:GetLastSpin()
    end

    return 0
end

function ENT:GetWheelOffset( index )
    local wheel = self.wheels and self.wheels[index]

    if IsValid( wheel ) and wheel.GetBaseZPos then
        return wheel:GetLocalPos()[3] - wheel:GetBaseZPos()
    end

    return 0
end

local EntityPairs = Glide.EntityPairs

function ENT:InternalActivateFeatures()
    -- Find and store the wheel and seat entities we have
    local wheels = {}
    local seats = {}

    for _, ent in ipairs( self:GetChildren() ) do
        if ent:GetClass() == "glide_wheel" then
            wheels[#wheels + 1] = ent

        elseif ent:IsVehicle() then
            seats[#seats + 1] = ent
        end
    end

    self.wheels = table.Reverse( wheels )
    self.seats = table.Reverse( seats )

    -- Cache player names to display on the HUD
    self.lastNick = {}

    -- Store state for particles and headlights
    self.particleCD = 0
    self.headlightState = nil
    self.activeHeadlights = {}

    -- Let children classes create their own stuff
    self:OnActivateMisc()

    -- Let children classes setup wheels clientside
    for i, w in EntityPairs( self.wheels ) do
        self:OnActivateWheel( w, i )
    end
end

function ENT:InternalDeactivateFeatures()
    if self.wheels then
        for _, w in EntityPairs( self.wheels ) do
            w:CleanupSounds()
        end
    end

    -- Manually remove the engine fire sound since it
    -- is not created with ENT:CreateLoopingSound
    if self.engineFireSound then
        self.engineFireSound:Stop()
        self.engineFireSound = nil
    end

    self.wheels = nil
    self.seats = nil
    self.lastNick = nil
    self:RemoveHeadlights()
    self:InternalDeactivateSounds()

    -- Let children classes cleanup their own stuff
    self:OnDeactivateMisc()
end

--- Create a new looping sound and store it on the slot `id`.
---
--- This sound will be automatically removed when the `rfMisc`
--- RangedFeature is deactivated, or when `ENT:ShouldActivateSounds` returns `false`.
function ENT:CreateLoopingSound( id, path, level, parent )
    local snd = self.sounds[id]

    if not snd then
        snd = CreateSound( parent or self, path )
        snd:SetSoundLevel( level )
        self.sounds[id] = snd
    end

    return snd
end

function ENT:InternalDeactivateSounds()
    self.isSoundActive = false

    -- Remove all sounds we've created so far
    local sounds = self.sounds

    for k, snd in pairs( sounds ) do
        snd:Stop()
        sounds[k] = nil
    end

    -- Let children classes do their own thing
    self:OnDeactivateSounds()
end

local RealTime = RealTime
local Effect = util.Effect
local IsGameUIVisible = gui.IsGameUIVisible
local GetTable = FindMetaTable( "Entity" ).GetTable

local DEFAULT_FLAME_ANGLE = Angle()

function ENT:InternalUpdateFeatures()
    local t = RealTime()
    local selfTbl = GetTable( self )

    -- Keep particles consistent even at high FPS
    if t > selfTbl.particleCD and self:WaterLevel() < 3 and not IsGameUIVisible() then
        selfTbl.particleCD = t + 0.03

        self:OnUpdateParticles()

        if self:GetIsEngineOnFire() then
            local velocity = self:GetVelocity()
            local eff = EffectData()

            for _, v in ipairs( selfTbl.EngineFireOffsets ) do
                eff:SetStart( velocity )
                eff:SetOrigin( self:LocalToWorld( v.offset ) )
                eff:SetAngles( self:LocalToWorldAngles( v.angle or DEFAULT_FLAME_ANGLE ) )
                eff:SetScale( v.scale or 1 )
                Effect( "glide_fire", eff, true, true )
            end
        end
    end

    -- Manually manage the engine fire sound instead of using ENT:CreateLoopingSound
    if self:GetIsEngineOnFire() then
        if not selfTbl.engineFireSound then
            selfTbl.engineFireSound = CreateSound( self, "glide/fire/fire_loop_1.wav" )
            selfTbl.engineFireSound:SetSoundLevel( 80 )
            selfTbl.engineFireSound:PlayEx( 0.9, 100 )
        end

    elseif selfTbl.engineFireSound then
        selfTbl.engineFireSound:Stop()
        selfTbl.engineFireSound = nil
    end

    if selfTbl.shouldThinkNow then
        local isSoundActive = self:ShouldActivateSounds()

        if isSoundActive then
            if not selfTbl.isSoundActive then
                selfTbl.isSoundActive = true
                self:OnActivateSounds()
            end

            -- Let children classes do their own thing
            self:OnUpdateSounds()

        elseif selfTbl.isSoundActive then
            self:InternalDeactivateSounds()
        end

        local signal = self:GetTurnSignalState()

        if signal > 0 and selfTbl.TurnSignalVolume > 0 then
            local signalBlink = ( CurTime() % selfTbl.TurnSignalCycle ) > selfTbl.TurnSignalCycle * 0.5

            if selfTbl.lastSignalBlink ~= signalBlink then
                selfTbl.lastSignalBlink = signalBlink

                if signalBlink and selfTbl.TurnSignalTickOnSound ~= "" then
                    self:EmitSound( selfTbl.TurnSignalTickOnSound, 65, selfTbl.TurnSignalPitch, selfTbl.TurnSignalVolume )

                elseif not signalBlink and selfTbl.TurnSignalTickOffSound ~= "" then
                    self:EmitSound( selfTbl.TurnSignalTickOffSound, 65, selfTbl.TurnSignalPitch, selfTbl.TurnSignalVolume )
                end
            end
        end

        local sounds = selfTbl.sounds

        if sounds.start and self:GetEngineState() ~= 1 then
            sounds.start:Stop()
            sounds.start = nil

            if selfTbl.StartTailSound and selfTbl.StartTailSound ~= "" then
                Glide.PlaySoundSet( selfTbl.StartTailSound, self )
            end
        end
    end

    -- Update lights and sprites
    self:UpdateLights( selfTbl )

    -- Let children classes do their own thing
    self:OnUpdateMisc()
    self:OnUpdateAnimations()
end

function ENT:Think()
    self:SetNextClientThink( CurTime() )

    -- Run some things less frequently when the
    -- local player is not inside this vehicle.
    local t = RealTime()
    local shouldThinkNow = true

    if not self.isLocalPlayerInVehicle then
        shouldThinkNow = t > self.lazyThinkCD

        if shouldThinkNow then
            self.lazyThinkCD = t + 0.05
        end
    end

    self.shouldThinkNow = shouldThinkNow

    if self.rfMisc then
        self.rfMisc:Think()
    end

    return true
end
