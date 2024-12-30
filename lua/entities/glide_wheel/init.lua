AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "cl_init.lua" )

include( "shared.lua" )

local EntityMeta = FindMetaTable( "Entity" )
local getTable = EntityMeta.GetTable

function ENT:Initialize()
    self:SetModel( "models/editor/axis_helper.mdl" )
    self:SetSolid( SOLID_NONE )
    self:SetMoveType( MOVETYPE_VPHYSICS )

    self.torque = 0     -- Amount of torque to apply to the wheel
    self.brake = 0      -- Amount of brake torque to apply to the wheel
    self.spin = 0       -- Wheel spin angle around it's axle axis

    -- Traction multiplier, used for forward traction bias on cars
    self.forwardTractionMult = 1

    self.isOnGround = false
    self.lastFraction = 1
    self.lastSpringOffset = 0
    self.angularVelocity = 0

    self.downSoundCD = 0
    self.upSoundCD = 0
    self.enableSounds = true

    self:SetupWheel()
end

--- Set the size, models and steering properties to use on this wheel.
function ENT:SetupWheel( params )
    params = params or {}

    -- Wheel offset relative to the parent
    self.basePos = params.basePos or self:GetLocalPos()
    self.isOnRight = self.basePos[2] < 0

    -- How much the parent's steering angle affects this wheel
    self.steerMultiplier = params.steerMultiplier or 0

    -- Regular model
    if params.model then
        self.model = params.model
        Glide.HideEntity( self, false )
    end

    -- Model rotation and scale
    self.modelScale = params.modelScale or Vector( 0.3, 1, 1 )
    self:SetModelAngle( params.modelAngle or Angle( 0, 0, 0 ) )
    self:SetModelOffset( params.modelOffset or Vector( 0, 0, 0 ) )

    -- Default (not blown) radius of the wheel
    self.defaultRadius = params.radius or 15

    -- Should we apply forces at the axle position?
    self.enableAxleForces = params.enableAxleForces or false

    self:Repair()
end

function ENT:Repair()
    if self.modelOverride then
        self:SetModel( self.modelOverride )

    elseif self.model then
        self:SetModel( self.model )
    end

    self:ChangeRadius()
end

function ENT:Blow()
    self:ChangeRadius( self.defaultRadius * 0.8 )
    self:EmitSound( "glide/wheels/blowout.mp3", 80, math.random( 95, 105 ), 1 )
end

function ENT:ChangeRadius( radius )
    radius = radius or self.defaultRadius

    local size = self.modelScale * radius * 2
    local bounds = self:OBBMaxs() - self:OBBMins()
    local scale = Vector( size[1] / bounds[1], size[2] / bounds[2], size[3] / bounds[3] )

    self:SetRadius( radius )
    self:SetModelScale2( scale )

    -- Used on util.TraceHull
    self.traceMins = Vector( radius * -0.2, radius * -0.2, 0 )
    self.traceMaxs = Vector( radius * 0.2, radius * 0.2, 1 )
end

do
    local Deg = math.deg
    local Approach = math.Approach

    function ENT:Update( vehicle, steerAngle, isAsleep, dt )
        local selfTbl = getTable( self )
        -- Get the wheel rotation relative to the vehicle, while applying the steering angle
        local ang = vehicle:LocalToWorldAngles( steerAngle * selfTbl.steerMultiplier )

        -- Rotate the wheel around the axle axis
        selfTbl.spin = ( selfTbl.spin - Deg( selfTbl.angularVelocity ) * dt ) % 360
        ang:RotateAroundAxis( ang:Right(), selfTbl.spin )
        self:SetAngles( ang )

        if isAsleep then
            self:SetForwardSlip( 0 )
            self:SetSideSlip( 0 )
        else
            self:SetLastSpin( selfTbl.spin )
            self:SetLastOffset( self:GetLocalPos()[3] - selfTbl.basePos[3] )
        end

        if isAsleep or not selfTbl.isOnGround then
            selfTbl.angularVelocity = selfTbl.angularVelocity + ( selfTbl.torque / 20 ) * dt
            selfTbl.angularVelocity = Approach( selfTbl.angularVelocity, 0, dt * 5 )
        end
    end

    local TAU = math.pi * 2

    function ENT:GetRPM()
        return self.angularVelocity * 60 / TAU
    end

    function ENT:SetRPM( rpm )
        self.angularVelocity = rpm / ( 60 / TAU )
    end
end

local Abs = math.abs
local Clamp = math.Clamp

do
    local CurTime = CurTime
    local PlaySoundSet = Glide.PlaySoundSet

    function ENT:DoSuspensionSounds( change, vehicle )
        if not self.enableSounds then return end

        local t = CurTime()

        if change > 0.01 and t > self.upSoundCD then
            self.upSoundCD = t + 0.3
            PlaySoundSet( vehicle.SuspensionUpSound, self, Clamp( Abs( change ) * 15, 0, 0.5 ) )
        end

        if change < -0.01 and t > self.downSoundCD then
            change = Abs( change )

            self.downSoundCD = t + 0.3
            PlaySoundSet( change > 0.03 and vehicle.SuspensionHeavySound or vehicle.SuspensionDownSound, self, Clamp( change * 20, 0, 1 ) )
        end
    end
end

local SURFACE_GRIP = Glide.SURFACE_GRIP
local SURFACE_RESISTANCE = Glide.SURFACE_RESISTANCE
local MAP_SURFACE_OVERRIDES = Glide.MAP_SURFACE_OVERRIDES

local PI = math.pi
local TAU = math.pi * 2

local Min = math.min
local Max = math.max
local Atan2 = math.atan2
local Approach = math.Approach
local TraceHull = util.TraceHull
local TractionRamp = Glide.TractionRamp

-- Temporary variables
local pos, ang, fw, rt, up, radius, maxLen
local ray, fraction, contactPos, surfaceId, vel, velF, velR, absVelR
local offset, springForce, damperForce, upDotNormal
local brake, surfaceGrip, maxTraction, brakeForce, forwardForce, signForwardForce
local tractionCycle, gripLoss, groundAngularVelocity, angularVelocity = Vector()
local slipAngle, sideForce
local force, linearImp, angularImp

function ENT:DoPhysics( vehicle, phys, params, traceData, outLin, outAng, dt )
    local selfTbl = getTable( self )
    -- Get the starting point of the raycast, where the suspension connects to the chassis
    pos = phys:LocalToWorld( selfTbl.basePos )

    -- Get the wheel rotation relative to the chassis, applying the steering angle if necessary
    ang = vehicle:LocalToWorldAngles( vehicle.steerAngle * selfTbl.steerMultiplier )

    -- Store some directions
    fw = ang:Forward()
    rt = ang:Right()
    up = ang:Up()

    -- Do the raycast
    radius = self:GetRadius()
    maxLen = params.suspensionLength + radius

    traceData.start = pos
    traceData.endpos = pos - up * maxLen
    traceData.mins = selfTbl.traceMins
    traceData.maxs = selfTbl.traceMaxs

    ray = TraceHull( traceData )
    fraction = Clamp( ray.Fraction, radius / maxLen, 1 )
    contactPos = pos - maxLen * fraction * up

    -- Update ground contact NW variables
    surfaceId = ray.MatType or 0
    surfaceId = MAP_SURFACE_OVERRIDES[surfaceId] or surfaceId

    --debugoverlay.Cross( pos, 10, 0.05, Color( 100, 100, 100 ), true )
    --debugoverlay.Box( contactPos, self.traceMins, self.traceMaxs, 0.05, Color( 0, 200, 0 ) )

    selfTbl.isOnGround = ray.Hit
    self:SetContactSurface( surfaceId )

    -- Update the wheel position and sounds
    self:SetLocalPos( phys:WorldToLocal( contactPos + up * radius ) )
    self:DoSuspensionSounds( fraction - selfTbl.lastFraction, vehicle )
    selfTbl.lastFraction = fraction

    if not ray.Hit then
        self:SetForwardSlip( 0 )
        self:SetSideSlip( 0 )

        -- Let the torque spin the wheel's fake mass
        selfTbl.angularVelocity = selfTbl.angularVelocity + ( selfTbl.torque / 20 ) * dt

        return
    end

    pos = self.enableAxleForces and pos or contactPos

    -- Get the velocity at the wheel position
    vel = phys:GetVelocityAtPoint( pos )

    -- Split that velocity among our local directions
    velF = fw:Dot( vel )
    velR = rt:Dot( vel )
    absVelR = Abs( velR )

    -- Suspension spring force & damping
    offset = maxLen - ( fraction * maxLen )
    springForce = ( offset * params.springStrength )
    damperForce = ( selfTbl.lastSpringOffset - offset ) * params.springDamper

    selfTbl.lastSpringOffset = offset

    upDotNormal = up:Dot( ray.HitNormal )
    force = ( springForce - damperForce ) * upDotNormal * ray.HitNormal

    -- Rolling resistance
    force:Add( ( SURFACE_RESISTANCE[surfaceId] or 0.05 ) * fw * -velF )

    -- Brake and torque forces
    brake = selfTbl.brake
    surfaceGrip = SURFACE_GRIP[surfaceId] or 1
    maxTraction = params.forwardTractionMax * surfaceGrip * selfTbl.forwardTractionMult

    -- This grip loss logic was inspired by simfphys
    brakeForce = Clamp( -velF, -brake, brake ) * params.brakePower * surfaceGrip
    forwardForce = selfTbl.torque + brakeForce
    signForwardForce = forwardForce > 0 and 1 or ( forwardForce < 0 and -1 or 0 )

    -- Given an amount of sideways slippage (up to the max. traction)
    -- and the forward force, calculate how much grip we are losing.
    tractionCycle[1] = Min( absVelR, maxTraction )
    tractionCycle[2] = forwardForce
    gripLoss = Max( tractionCycle:Length() - maxTraction, 0 )

    -- Reduce the forward force by the amount of grip we lost,
    -- but still allow some amount of brake force to apply regardless.
    forwardForce = forwardForce - ( gripLoss * signForwardForce ) + Clamp( brakeForce * 0.5, -maxTraction, maxTraction )
    force:Add( fw * forwardForce )

    -- Get how fast the wheel would be spinning if it had never lost grip
    groundAngularVelocity = TAU * ( velF / ( radius * TAU ) )

    -- Add our grip loss to our spin velocity
    angularVelocity = groundAngularVelocity + gripLoss * ( selfTbl.torque > 0 and 1 or ( selfTbl.torque < 0 and -1 or 0 ) )

    -- Smoothly match our current angular velocity to the angular velocity affected by grip loss
    selfTbl.angularVelocity = Approach( selfTbl.angularVelocity, angularVelocity, dt * 200 )

    gripLoss = groundAngularVelocity - selfTbl.angularVelocity
    self:SetForwardSlip( gripLoss )

    -- Calculate side slip angle
    slipAngle = ( Atan2( velR, Abs( velF ) ) / PI ) * 2
    self:SetSideSlip( slipAngle * Clamp( vehicle.totalSpeed * 0.005, 0, 1 ) * 2 )
    slipAngle = Abs( slipAngle * slipAngle )

    -- Reduce sideways traction as the suspension spring applies less force
    surfaceGrip = surfaceGrip * Clamp( ( springForce * 0.5 ) / params.springStrength, 0, 1 )

    -- Sideways traction ramp
    maxTraction = TractionRamp( slipAngle ) * surfaceGrip
    sideForce = -rt:Dot( vel * params.sideTractionMultiplier )

    -- Reduce sideways traction force as the wheel slips forward
    sideForce = sideForce * ( 1 - Clamp( Abs( gripLoss ) * 0.1, 0, 1 ) * 0.9 )

    -- Apply sideways traction force
    force:Add( Clamp( sideForce, -maxTraction, maxTraction ) * rt )

    -- Apply an extra, small sideways force that is not clamped by maxTraction.
    -- This helps at lot with cornering at high speed.
    force:Add( velR * params.sideTractionMultiplier * -0.1 * rt )

    -- Apply the forces at the axle/ground contact position
    linearImp, angularImp = phys:CalculateForceOffset( force, pos )

    outLin[1] = outLin[1] + linearImp[1] / dt
    outLin[2] = outLin[2] + linearImp[2] / dt
    outLin[3] = outLin[3] + linearImp[3] / dt

    outAng[1] = outAng[1] + angularImp[1] / dt
    outAng[2] = outAng[2] + angularImp[2] / dt
    outAng[3] = outAng[3] + angularImp[3] / dt
end
