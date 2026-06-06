AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )

include( "shared.lua" )

DEFINE_BASECLASS( "base_glide_plane" )

--- Override this base class function.
function ENT:OnPostInitialize()
    BaseClass.OnPostInitialize( self )

    -- Setup variables used on all VTOL planes
    self.vtolState = 0
    self:SetVTOLState( 0 )

    self:RegisterHoldAction( "landing_gear", 1.0, { name = "ToggleVTOLMode" } )
end

function ENT:OnHoldInputAction( _action, data )
    if data.name ~= "ToggleVTOLMode" then return end

    local state = self.vtolState

    if state == 0 or state == 3 then
        self:SetVTOLState( 1 )
    else
        self:SetVTOLState( 3 )
    end
end

function ENT:SetVTOLState( state )
    -- Do transition sounds
    if state ~= self.vtolState then
        local soundParams = self.VTOLStateSounds[state]

        if soundParams[1] ~= "" then
            self:EmitSound( soundParams[1], 90, soundParams[3], soundParams[2] )
        end
    end

    if state == 1 then
        -- Transition to horizontal flight
        self.vtolState = 1

    elseif state == 2 then
        -- Set to horizontal flight now
        self.vtolState = 2
        self:SetVerticalFlight( 0 )
        self:UpdateRotorPositions( 0 )

    elseif state == 3 then
        -- Transition to vertical flight
        self.vtolState = 3

    else
        -- Set to vertical flight now
        self.vtolState = 0
        self:SetVerticalFlight( 1 )
        self:UpdateRotorPositions( 1 )
    end
end

--- Override this base class function.
function ENT:OnPostThink( dt, selfTbl )
    BaseClass.OnPostThink( self, dt, selfTbl )

    local vtolState = self.vtolState

    -- Suppress stall warning while in vertical flight
    if vtolState ~= 2 then
        self:SetIsStalling( false )
    end

    if vtolState == 1 then -- Is it changing to horizontal flight?
        local value = self:GetVerticalFlight() - dt / selfTbl.VTOLTransitionTime

        if value < 0 then
            self:SetVTOLState( 2 )
        else
            self:SetVerticalFlight( value )
            self:UpdateRotorPositions( value )
        end

    elseif vtolState == 3 then -- Is it changing to vertical flight?
        local value = self:GetVerticalFlight() + dt / selfTbl.VTOLTransitionTime

        if value > 1 then
            self:SetVTOLState( 0 )
        else
            self:SetVerticalFlight( value )
            self:UpdateRotorPositions( value )
        end
    end
end

local EntityPairs = Glide.EntityPairs

--- Override this base class function.
function ENT:UpdatePlaneWheels( selfTbl )
    if selfTbl.vtolState == 2 then
        BaseClass.UpdatePlaneWheels( self, selfTbl )
        return
    end

    local throttle = self:GetInputFloat( 1, "throttle" )

    if throttle < 0 and selfTbl.forwardSpeed > 0 then
        selfTbl.brake = 1
    else
        selfTbl.brake = 0.5
    end

    local isGrounded = false
    local state

    for _, w in EntityPairs( self.wheels ) do
        state = w.state
        state.brake = selfTbl.brake
        state.torque = 0

        if state.isOnGround then
            isGrounded = true
        end
    end

    selfTbl.isGrounded = isGrounded
end

local Clamp = math.Clamp

--- Implement this base class function.
function ENT:OnSimulatePhysics( phys, dt, outLin, outAng )
    if self:WaterLevel() > 1 then return end

    local power = Clamp( self:GetPower(), 0, 1 )
    local heliEffectiveness = self:GetVerticalFlight()
    local planeEffectiveness = 1 - heliEffectiveness

    if heliEffectiveness > 0.1 then
        self:SimulateHelicopter( phys, self.HelicopterParams, heliEffectiveness * power, outLin, outAng )
    end

    -- Allow plane physics when powered off
    planeEffectiveness = Clamp( planeEffectiveness + Clamp( 1 - power, 0, 1 ), 0, 1 )

    if planeEffectiveness > 0.1 then
        self:SimulatePlane( phys, dt, self.PlaneParams, planeEffectiveness, outLin, outAng )
    end
end
