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

--- The returned value from this function is multiplied with
--- the yaw angle from `ENT.AngularDrag` before appling it to the vehicle.
function ENT:GetYawDragMultiplier()
    return 1
end

function ENT:WheelThink( dt, selfTbl )
    local phys = self:GetPhysicsObject()
    local isAsleep = phys:IsValid() and phys:IsAsleep()

    for _, w in EntityPairs( self.wheels ) do
        w:Update( self, selfTbl.steerAngle, isAsleep, dt )
    end
end

local EntityMeta = FindMetaTable( "Entity" )
local GetTable = EntityMeta.GetTable

local VectorUnpack = FindMetaTable( "Vector" ).Unpack
local VectorSetUnpacked = FindMetaTable( "Vector" ).SetUnpacked

local Abs = math.abs
local Clamp = math.Clamp
local ClampForce = Glide.ClampForce

local linForce, angForce = Vector(), Vector()

function ENT:PhysicsSimulate( phys, dt )
    local selfTbl = GetTable( self )

    -- Prepare output vectors, do angular drag
    local mass = phys:GetMass()

    VectorSetUnpacked( linForce, 0, 0, 0 )

    local angDragX, angDragY, angDragZ = VectorUnpack( selfTbl.AngularDrag )
    local angVelX, angVelY, angVelZ = VectorUnpack( phys:GetAngleVelocity() )

    VectorSetUnpacked( angForce,
        angVelX * angDragX * mass,
        angVelY * angDragY * mass,
        angVelZ * angDragZ * self:GetYawDragMultiplier() * mass
    )

    local groundedCount = 0

    -- Do wheel physics
    if selfTbl.wheelCount > 0 and selfTbl.wheelsEnabled then
        local traceFilter = selfTbl.wheelTraceFilter
        local surfaceGrip = selfTbl.surfaceGrip
        local surfaceResistance = selfTbl.surfaceResistance

        local vehPos = phys:GetPos()
        local vehVel = phys:GetVelocity()
        local vehAngVel = phys:GetAngleVelocity()

        for _, w in EntityPairs( selfTbl.wheels ) do
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
        local totalSpeed = selfTbl.totalSpeed + Abs( angVelZ )
        local factor = 1 - Clamp( totalSpeed / 30, 0, 1 )

        if factor > 0.1 then
            local rt = self:GetRight()
            linForce:Sub( ( rt:Dot( phys:GetVelocity() ) / dt ) * mass * factor * rt )
        end
    end

    -- Prevent crashes
    ClampForce( angForce )
    ClampForce( linForce )

    return angForce, linForce, 4 -- SIM_GLOBAL_FORCE
end

local function LimitInputWithAngle( value, ang, maxAng )
    if ang > maxAng then
        value = value * ( 1 - Clamp( ( ang - maxAng ) / 20, 0, 1 ) )
    end

    return value
end

local mass

local function AddForce( out, f )
    out[1] = out[1] + f[1] * mass
    out[2] = out[2] + f[2] * mass
    out[3] = out[3] + f[3] * mass
end

local linearImp, angularImp

local function AddForceOffset( outLin, outAng, phys, dt, pos, f )
    linearImp, angularImp = phys:CalculateForceOffset( f * mass, pos )

    outLin[1] = outLin[1] + linearImp[1] / dt
    outLin[2] = outLin[2] + linearImp[2] / dt
    outLin[3] = outLin[3] + linearImp[3] / dt

    outAng[1] = outAng[1] + angularImp[1] / dt
    outAng[2] = outAng[2] + angularImp[2] / dt
    outAng[3] = outAng[3] + angularImp[3] / dt
end

local TraceLine = util.TraceLine
local GetGravity = physenv.GetGravity

local ray = {}
local traceData = { output = ray, endpos = Vector(), mask = MASK_SOLID + CONTENTS_WATER + CONTENTS_SLIME }
local fw, rt, up, vel, speed
local WORLD_UP = Vector( 0, 0, 1 )

--- Simulate a hover/hovercraft vehicle.
--- Can optionally fly depending on the `flightStrength`.
---
--- It requires a `HoverParams` table to be defined on this entity.
---
--- Returns the count of `hoverPoints` traces that have hit a surface.
---
function ENT:SimulateHovercraft( strength, flightStrength, hoverPoints, phys, dt, outLin, outAng )
    mass = phys:GetMass()
    fw = self:GetForward()
    rt = self:GetRight()
    up = self:GetUp()

    vel = phys:GetVelocity()
    speed = fw:Dot( vel )

    local params = self.HoverParams

    -- Hover forces
    local hoverDist = params.hoverDistance
    local hoverForce, upVel, avgNormal = 0, 0, Vector()
    local contactHoverPointCount = 0

    traceData.filter = self

    for _, point in ipairs( hoverPoints ) do
        point = self:LocalToWorld( point )

        -- Check how far from a surface this point is
        traceData.start = point
        traceData.endpos[1] = point[1] - up[1] * hoverDist
        traceData.endpos[2] = point[2] - up[2] * hoverDist
        traceData.endpos[3] = point[3] - up[3] * hoverDist

        TraceLine( traceData )

        if ray.Hit then
            upVel = up:Dot( phys:GetVelocityAtPoint( point ) )

            hoverForce = params.hoverForce * ( 0.5 - ray.Fraction ) * strength
            hoverForce = hoverForce - upVel * params.hoverZDrag

            -- Don't push down if flightStrength is not 0
            if hoverForce > 0 then
                hoverForce = hoverForce * ( 1 - flightStrength )
            end

            AddForceOffset( outLin, outAng, phys, dt, point, up * hoverForce )

            avgNormal[1] = avgNormal[1] + ray.HitNormal[1]
            avgNormal[2] = avgNormal[2] + ray.HitNormal[2]
            avgNormal[3] = avgNormal[3] + ray.HitNormal[3]

            contactHoverPointCount = contactHoverPointCount + 1
        else
            avgNormal[3] = avgNormal[3] + 1
        end
    end

    local count = #hoverPoints

    avgNormal[1] = avgNormal[1] / count
    avgNormal[2] = avgNormal[2] / count
    avgNormal[3] = avgNormal[3] / count
    avgNormal:Normalize()

    -- Lift & keep upright forces
    AddForce( outLin, -flightStrength * GetGravity()[3] * WORLD_UP )

    outAng[1] = outAng[1] + rt:Dot( avgNormal ) * params.uprightForce * strength * mass
    outAng[2] = outAng[2] + fw:Dot( avgNormal ) * params.uprightForce * strength * mass

    -- Drag forces
    AddForce( outLin, Clamp( speed, -500, 500 ) * -params.linearDrag[1] * strength * fw )
    AddForce( outLin, rt:Dot( vel ) * -params.linearDrag[2] * strength * rt )
    AddForce( outLin, up:Dot( vel ) * -params.linearDrag[3] * strength * flightStrength * up )

    local angDrag = params.angularDrag
    local angVel = phys:GetAngleVelocity()

    outAng[1] = outAng[1] + angVel[1] * angDrag[1] * mass * strength
    outAng[2] = outAng[2] + angVel[2] * angDrag[2] * mass * strength
    outAng[3] = outAng[3] + angVel[3] * angDrag[3] * mass * strength

    -- Engine force
    local throttle = self:GetInputFloat( 1, "accelerate" ) - self:GetInputFloat( 1, "brake" )

    if throttle > 0 and speed < params.maxSpeed then
        AddForce( outLin, params.engineForce * throttle * strength * fw )

    elseif throttle < 0 and speed > params.maxSpeed * -0.25 then
        AddForce( outLin, params.engineForce * throttle * strength * fw )
    end

    -- Steering force
    local steer = self:GetInputFloat( 1, "steer" )

    if speed < -100 then
        steer = -steer
    end

    outAng[3] = outAng[3] - params.turnForce * steer * mass * strength

    -- Pitch force
    local pitchInput = self:GetInputFloat( 1, "lean_pitch" )
    pitchInput = LimitInputWithAngle( pitchInput, Abs( self:GetAngles()[1] ), 5 )
    outAng[2] = outAng[2] + params.pitchForce * mass * pitchInput * flightStrength

    return contactHoverPointCount
end
