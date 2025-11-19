function ENT:WheelInit()
    self.wheels = {}
    self.wheelCount = 0
    self.wheelsEnabled = true
    self.steerAngle = Angle()

    -- This was deprecated. Putting values here does nothing.
    -- Wheel parameters are stored on each wheel now.
    -- This will be removed in the future.
    self.wheelParams = {}
end

function ENT:CreateWheel( offset, params )
    params = params or {}

    local pos = self:LocalToWorld( offset )
    local ang = self:LocalToWorldAngles( Angle() )

    local wheel = ents.Create( "glide_wheel" )
    wheel:SetPos( pos )
    wheel:SetAngles( ang )
    wheel:SetOwner( self )
    wheel:SetParent( self )
    wheel:Spawn()
    wheel:SetupWheel( params )

    self:DeleteOnRemove( wheel )

    Glide.CopyEntityCreator( self, wheel )

    local index = self.wheelCount + 1

    self.wheelCount = index
    self.wheels[index] = wheel
    wheel:SetNWInt( "glide_wheel_index", index )

    return wheel
end

local EntityPairs = Glide.EntityPairs

function ENT:ChangeWheelRadius( radius )
    if not self.wheels then return end

    for _, w in EntityPairs( self.wheels ) do
        if IsValid( w ) then
            w.params.radius = radius
            w:ChangeRadius( radius )
        end
    end
end

function ENT:ApplyWheelBlowModifications()
    if not self.wheels then return end

    local iBlow = 0
    for _, w in EntityPairs( self.wheels ) do
        if IsValid( w ) and w:IsBlown() then
            print(_, " wheel is blown.")
            iBlow = iBlow + 1
        end
    end

    local iPercentage = ( iBlow / self.wheelCount ) * 100

    print( "[Glide] Applying wheel blow modification: ", iBlow, " wheels blown (", iPercentage, "%)" )

    if self.GetSteerConeChangeRate and self.SetSteerConeChangeRate then
        self.iOldSteerConeChangeRate = self.iOldSteerConeChangeRate or self:GetSteerConeChangeRate()

        self:SetSteerConeChangeRate(self:GetSteerConeChangeRate() * (1 - iPercentage / 100))
    end

    if self.GetMaxSteerAngle and self.SetMaxSteerAngle then
        self.iOldMaxSteerAngle = self.iOldMaxSteerAngle or self:GetMaxSteerAngle()

        self:SetMaxSteerAngle(self:GetMaxSteerAngle() * (1 - iPercentage / 100))
    end

    if iPercentage == 0 then
        -- Restore old values
        if self.iOldSteerConeChangeRate and self.GetSteerConeChangeRate and self.SetSteerConeChangeRate then
            self:SetSteerConeChangeRate(self.iOldSteerConeChangeRate)
            self.iOldSteerConeChangeRate = nil
        end

        if self.iOldMaxSteerAngle and self.GetMaxSteerAngle and self.SetMaxSteerAngle then
            self:SetMaxSteerAngle(self.iOldMaxSteerAngle)
            self.iOldMaxSteerAngle = nil
        end
    end

    if iBlow == 0 then
        return
    end

    local iDamage = self:GetChassisHealth() / 2 * ( iPercentage / 100 )
    self:SetChassisHealth(self:GetChassisHealth() - iDamage)

    --         ent:SetSteerConeChangeRate(ent:GetSteerConeChangeRate() * 0.6)
    --         ent:SetMaxSteerAngle(ent:GetMaxSteerAngle() * 0.8)

end

--- The returned value from this function is multiplied with
--- the yaw angle from `ENT.AngularDrag` before appling it to the vehicle.
function ENT:GetYawDragMultiplier()
    return 1
end

function ENT:WheelThink( dt )
    local phys = self:GetPhysicsObject()
    local isAsleep = phys:IsValid() and phys:IsAsleep()

    for _, w in EntityPairs( self.wheels ) do
        w:Update( self, self.steerAngle, isAsleep, dt )
    end
end

local Abs = math.abs
local Clamp = math.Clamp
local ClampForce = Glide.ClampForce

local linForce, angForce = Vector(), Vector()

function ENT:PhysicsSimulate( phys, dt )
    -- Prepare output vectors, do angular drag
    local drag = self.AngularDrag
    local mass = phys:GetMass()
    local angVel = phys:GetAngleVelocity()

    linForce[1] = 0
    linForce[2] = 0
    linForce[3] = 0

    angForce[1] = angVel[1] * drag[1] * mass
    angForce[2] = angVel[2] * drag[2] * mass
    angForce[3] = angVel[3] * drag[3] * self:GetYawDragMultiplier() * mass

    local groundedCount = 0

    -- Do wheel physics
    if self.wheelCount > 0 and self.wheelsEnabled then
        local traceFilter = self.wheelTraceFilter
        local surfaceGrip = self.surfaceGrip
        local surfaceResistance = self.surfaceResistance

        local vehPos = phys:GetPos()
        local vehVel = phys:GetVelocity()
        local vehAngVel = phys:GetAngleVelocity()

        for _, w in EntityPairs( self.wheels ) do
            w:DoPhysics( self, phys, traceFilter, linForce, angForce, dt, surfaceGrip, surfaceResistance, vehPos, vehVel, vehAngVel )

            if w.state.isOnGround then
                groundedCount = groundedCount + 1
            end
        end

        phys:SetPos( vehPos )
        phys:SetVelocityInstantaneous( vehVel )
        phys:SetAngleVelocityInstantaneous( vehAngVel )
    end

    -- Let children classes do additional physics if they want to
    self:OnSimulatePhysics( phys, dt, linForce, angForce )

    -- At slow speeds, try to prevent slipping sideways on mildly steep slopes
    if groundedCount > 0 then
        local totalSpeed = self.totalSpeed + Abs( angVel[3] )
        local factor = 1 - Clamp( totalSpeed / 30, 0, 1 )

        if factor > 0.1 then
            local vel = phys:GetVelocity()
            local rt = self:GetRight()
            local force = ( rt:Dot( vel ) / dt ) * mass * factor * rt

            linForce[1] = linForce[1] - force[1]
            linForce[2] = linForce[2] - force[2]
            linForce[3] = linForce[3] - force[3]
        end
    end

    -- Prevent crashes
    ClampForce( angForce )
    ClampForce( linForce )

    return angForce, linForce, 4 -- SIM_GLOBAL_FORCE
end
