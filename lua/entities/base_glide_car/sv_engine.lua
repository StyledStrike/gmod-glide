function ENT:EngineInit()
    self:UpdateGearList()

    -- Fake flywheel parameters
    self.flywheelMass = 80
    self.flywheelRadius = 0.5

    self.flywheelFriction = -6000
    self.flywheelTorque = 20000
    self.engineBrakeTorque = 2000

    -- Fake engine variables
    self.flywheelVelocity = 0
    self.clutch = 1
    self.switchCD = 0
    self.switchBaseDelay = 0.3

    -- Wheel control variables
    self.groundedCount = 0
    self.burnout = 0

    self.frontBrake = 0
    self.rearBrake = 0
    self.availableFrontTorque = 0
    self.availableRearTorque = 0

    self.frontTractionMult = 1
    self.rearTractionMult = 1

    self.avgSideSlip = 0
    self.avgPoweredRPM = 0
    self.avgForwardSlip = 0
end

--- Returns a list of available transmission gears.
--- Unlike `ENT:GetGears()` this will return overrides from
--- the Transmission Editor tool, if they're set.
function ENT:GetGearList()
    local overrideGears = self.EntityMods["glide_transmission_overrides"]

    if type( overrideGears ) == "table" then
        return overrideGears
    end

    return self:GetGears()
end

function ENT:UpdateGearList()
    local gears = self:GetGearList()
    local ClampGearRatio = Glide.ClampGearRatio

    local minGear = 0
    local maxGear = 0
    local gearRatios = {}

    for gear, ratio in pairs( gears ) do
        gearRatios[gear] = ClampGearRatio( ratio )

        if gear < minGear then minGear = gear end
        if gear > maxGear then maxGear = gear end
    end

    if self.minGear ~= minGear or self.maxGear ~= maxGear then
        self:SwitchGear( 0, 0 )
    end

    self.minGear = minGear
    self.maxGear = maxGear
    self.gearRatios = gearRatios

    if WireLib then
        WireLib.TriggerOutput( self, "MaxGear", self.maxGear )
    end
end

--- Override this base class function.
function ENT:OnEntityReload()
    self:UpdateGearList()
end

local EntityPairs = Glide.EntityPairs

function ENT:UpdatePowerDistribution()
    self.shouldUpdatePowerDistribution = false

    local frontCount, rearCount = 0, 0

    -- First, count how many wheels are in the front/rear
    for _, w in EntityPairs( self.wheels ) do
        if w.state.isFrontWheel then
            frontCount = frontCount + 1
        else
            rearCount = rearCount + 1
        end
    end

    -- Then, use that count to split the front/rear torque between wheels later
    local frontDistribution = 0.5 + self:GetPowerDistribution() * 0.5
    local rearDistribution = 1 - frontDistribution

    frontDistribution = frontDistribution / frontCount
    rearDistribution = rearDistribution / rearCount

    for _, w in EntityPairs( self.wheels ) do
        w.state.distributionFactor = w.state.isFrontWheel and frontDistribution or rearDistribution
    end
end

do
    local TAU = math.pi * 2

    function ENT:GetFlywheelRPM()
        return self.flywheelVelocity * 60 / TAU
    end

    function ENT:SetFlywheelRPM( rpm )
        self.flywheelVelocity = rpm * TAU / 60
        self:SetEngineRPM( rpm )
    end

    function ENT:TransmissionToEngineRPM( gear, selfTbl )
        return selfTbl.avgPoweredRPM * selfTbl.gearRatios[gear] * self:GetDifferentialRatio() * 60 / TAU
    end

    function ENT:GetTransmissionMaxRPM( gear, selfTbl )
        return self:GetFlywheelRPM() / selfTbl.gearRatios[gear] / self:GetDifferentialRatio()
    end
end

function ENT:EngineAccelerate( torque, dt )
    -- Calculate moment of inertia
    local radius = self.flywheelRadius
    local inertia = 0.5 * self.flywheelMass * radius * radius

    -- Calculate angular acceleration using Newton's second law for rotation
    local angularAcceleration = torque / inertia -- Ah, the classic F = m * a, a = F / m

    -- Calculate new angular velocity after delta time
    self.flywheelVelocity = self.flywheelVelocity + angularAcceleration * dt
end

local Clamp = math.Clamp

function ENT:SwitchGear( index, cooldown )
    if self:GetGear() == index then return end

    index = Clamp( index, self.minGear, self.maxGear )
    cooldown = cooldown or self.switchBaseDelay

    self.switchCD = cooldown * ( index == 1 and 0 or ( self:GetFastTransmission() and 0.5 or 1 ) )
    self.clutch = 1
    self:SetGear( index )
end

local Remap = math.Remap

function ENT:GetTransmissionTorque( gear, minTorque, maxTorque )
    local torque = Remap( self:GetFlywheelRPM(), self:GetMinRPM(), self:GetMaxRPM(), minTorque, maxTorque )

    -- Validation
    torque = Clamp( torque, minTorque, maxTorque )

    -- Clutch
    torque = torque * ( 1 - self.clutch )

    -- Gearing, differential & losses
    torque = torque * self.gearRatios[gear] * self:GetDifferentialRatio() * self:GetTransmissionEfficiency()

    return gear == -1 and -torque or torque
end

local Abs = math.abs

function ENT:AutoGearSwitch( throttle, selfTbl )
    -- Are we trying to go backwards?
    if selfTbl.forwardSpeed < 100 and self:GetInputFloat( 1, "brake", selfTbl ) > 0.2 then
        self:SwitchGear( -1, 0 )
        return
    end

    -- Don't switch from reverse gear while still going backwards fast enough
    local currentGear = self:GetGear()
    if currentGear < 0 and selfTbl.forwardSpeed < -100 then return end

    -- Don't switch when the wheels are slipping forwards
    if Abs( selfTbl.avgForwardSlip ) > 3 then return end

    local gear = Clamp( currentGear, 1, selfTbl.maxGear )
    local minRPM, maxRPM = self:GetMinRPM(), self:GetMaxRPM()

    -- Avoid hitting the redline
    maxRPM = maxRPM * 0.95

    -- When accelerating, switch up early when the throttle is low
    if selfTbl.forwardAcceleration > 0 then
        maxRPM = maxRPM * ( 0.6 + throttle * 0.4 )
    end

    local gearRPM

    -- Pick the gear that matches better the engine-to-transmission RPM
    for i = 1, selfTbl.maxGear do
        gearRPM = self:TransmissionToEngineRPM( i, selfTbl )

        -- If this is the first gear, and it's transmission RPM is below the `minRPM`, OR;
        -- If this gear's transmission RPM is between `minRPM` and `maxRPM`...
        if ( i == 1 and gearRPM < minRPM ) or ( gearRPM > minRPM and gearRPM < maxRPM ) then
            gear = i -- Pick this gear
            break
        end
    end

    -- Only shift one gear down if the RPM is too low
    local threshold = minRPM + ( maxRPM - minRPM ) * ( 0.5 - throttle * 0.3 )
    if gear < currentGear and gear > currentGear - 2 and self:GetEngineRPM() > threshold then return end

    self:SwitchGear( gear )
end

-- These locals are used both on `ENT:EngineClutch` and `ENT:EngineThink`
local inputThrottle, inputBrake, inputHandbrake

function ENT:EngineClutch( dt, selfTbl )
    -- Is the gear switch on cooldown?
    if selfTbl.switchCD > 0 then
        selfTbl.switchCD = selfTbl.switchCD - dt
        inputThrottle = 0
        return 0
    end

    if inputHandbrake then
        return 1
    end

    local absForwardSpeed = Abs( selfTbl.forwardSpeed )

    -- Are we airborne while going fast?
    if selfTbl.groundedCount < 1 and absForwardSpeed > 30 then
        return 1
    end

    -- Are we trying to break from a backwards velocity?
    if selfTbl.forwardSpeed < -50 and inputBrake > 0 and self:GetGear() < 0 then
        return 1
    end

    -- Engage the clutch when moving fast enough
    if absForwardSpeed > 200 then
        return 0
    end

    -- Engage the clutch while the throttle is high
    return inputThrottle > 0.1 and 0 or 1
end

local Max = math.max
local Approach = math.Approach

function ENT:EngineThink( dt, selfTbl )
    local gear = self:GetGear()
    local amphibiousMode = selfTbl.IsAmphibious and self:GetWaterState() > 0

    -- These variables are used both on `ENT:EngineClutch` and `ENT:EngineThink`
    inputThrottle = self:GetInputFloat( 1, "accelerate", selfTbl )
    inputBrake = self:GetInputFloat( 1, "brake", selfTbl )
    inputHandbrake = self:GetInputBool( 1, "handbrake", selfTbl )

    if amphibiousMode then
        selfTbl.burnout = 0
        self:BoatEngineThink( dt )
        self:SetIsRedlining( false )

        if inputThrottle > 0 then
            self:SwitchGear( 1, 0 )

        elseif inputBrake > 0 then
            self:SwitchGear( -1, 0 )
        end

    elseif selfTbl.burnout > 0 then
        self:SwitchGear( 1, 0 )

        if inputThrottle < 0.1 or inputBrake < 0.1 then
            selfTbl.burnout = 0
        end

    elseif not selfTbl.inputManualShift then
        self:AutoGearSwitch( inputThrottle, selfTbl )
    end

    -- Reverse the throttle/brake inputs while in reverse gear
    if gear < 0 and not selfTbl.inputManualShift then
        inputThrottle, inputBrake = inputBrake, inputThrottle
    end

    -- When the engine is damaged, reduce the throttle
    if selfTbl.damageThrottleCooldown and selfTbl.damageThrottleCooldown < 0.3 then
        inputThrottle = inputThrottle * 0.3
    end

    -- When the engine is on fire, reduce the throttle
    if self:GetIsEngineOnFire() then
        inputThrottle = inputThrottle * 0.7
    end

    local rpm = self:GetFlywheelRPM()
    local minRPM = self:GetMinRPM()

    -- Handle auto-clutch
    local clutch = amphibiousMode and 1 or self:EngineClutch( dt, selfTbl )

    -- Do a burnout when holding down the throttle and brake inputs
    if inputThrottle > 0.1 and inputBrake > 0.1 and Abs( selfTbl.forwardSpeed ) < 50 then
        selfTbl.burnout = Approach( selfTbl.burnout, 1, dt * 2 )

        clutch = 0

        -- Allow the driver to spin the car
        local phys = self:GetPhysicsObject()
        local mins, maxs = self:OBBMins(), self:OBBMaxs()
        local burnoutForce = phys:GetMass() * selfTbl.BurnoutForce * selfTbl.burnout * dt

        burnoutForce = burnoutForce * selfTbl.inputSteer * Clamp( Abs( selfTbl.avgForwardSlip ) * 0.1, 0, 1 )

        local frontBurnout = self:GetPowerDistribution() > 0
        local dir = frontBurnout and self:GetRight() or -self:GetRight()

        selfTbl.frontBrake = frontBurnout and 0 or 0.25
        selfTbl.rearBrake = frontBurnout and 0.25 or 0

        selfTbl.frontTractionMult = frontBurnout and 0.25 or 2
        selfTbl.rearTractionMult = frontBurnout and 2 or 0.25

        for _, w in EntityPairs( selfTbl.wheels ) do
            if w.state.isFrontWheel == frontBurnout then
                local pos = w:GetLocalPos()

                pos[1] = pos[1] > 0 and maxs[1] * 2 or mins[1] * 2
                pos = self:LocalToWorld( pos )

                phys:ApplyForceOffset( dir * burnoutForce, pos )
            end
        end

    elseif inputHandbrake then
        selfTbl.frontTractionMult = 1
        selfTbl.rearTractionMult = 0.5

        selfTbl.frontBrake = 0
        selfTbl.rearBrake = 0.5
        selfTbl.clutch = 1
        clutch = 1

    else
        -- Automatically apply brakes when not accelerating, on the ground,
        -- with low engine RPM, while on first gear or reverse gear.
        if
            ( gear == -1 or gear == 1 ) and
            inputThrottle < 0.05 and
            inputBrake < 0.1 and
            selfTbl.groundedCount > 1 and
            rpm < minRPM * 1.2
        then
            inputBrake = 0.2
        end

        selfTbl.frontBrake = inputBrake * 0.5
        selfTbl.rearBrake = inputBrake * 0.5

        selfTbl.frontTractionMult = 1
        selfTbl.rearTractionMult = 1
    end

    clutch = Approach( selfTbl.clutch, clutch, dt * ( ( gear < 2 and inputThrottle > 0.1 ) and 6 or 2 ) )
    selfTbl.clutch = clutch

    local isRedlining = false
    local transmissionRPM = 0

    -- If we're not in neutral, convert the avg.
    -- transmission RPM back to the engine RPM.
    if gear ~= 0 then
        transmissionRPM = self:TransmissionToEngineRPM( gear, selfTbl )
        transmissionRPM = gear < 0 and -transmissionRPM or transmissionRPM
        rpm = ( rpm * clutch ) + ( Max( 0, transmissionRPM ) * ( 1 - clutch ) )
    end

    local throttle = self:GetEngineThrottle()
    local gearTorque = self:GetTransmissionTorque( gear, self:GetMinRPMTorque(), self:GetMaxRPMTorque() )
    local availableTorque = gearTorque * throttle

    -- Simulate engine braking
    if transmissionRPM < 0 then
        -- The vehicle is moving against the current gear, do some hard engine braking.
        availableTorque = availableTorque + gearTorque * 2
    else
        -- The vehicle is coasting, apply a custom engine brake torque.
        local engineBrakeTorque = self:GetTransmissionTorque( gear, selfTbl.engineBrakeTorque, selfTbl.engineBrakeTorque )
        availableTorque = availableTorque - engineBrakeTorque * ( 1 - throttle ) * 0.5
    end

    -- Limit the engine RPM, check if it's redlining
    local maxRPM = self:GetMaxRPM()

    if rpm > maxRPM then
        if rpm > maxRPM * 1.2 then
            availableTorque = 0
        end

        rpm = maxRPM

        if gear ~= selfTbl.maxGear or selfTbl.groundedCount < selfTbl.wheelCount then
            isRedlining = true
        end
    end

    rpm = Clamp( rpm, minRPM, maxRPM )
    self:SetFlywheelRPM( rpm )

    -- Update the amount of available torque to the transmission
    if self:GetTurboCharged() then
        availableTorque = availableTorque * ( 1 + ( rpm / maxRPM ) * 0.3 )
    end

    if selfTbl.burnout > 0 then
        availableTorque = availableTorque + availableTorque * selfTbl.burnout * 0.1
    end

    -- Split torque between front and rear wheels
    local front = 0.5 + self:GetPowerDistribution() * 0.5
    local rear = 1 - front

    selfTbl.availableFrontTorque = availableTorque * front
    selfTbl.availableRearTorque = availableTorque * rear

    if not amphibiousMode then
        -- Accelerate the engine flywheel and update network variables
        throttle = Approach( throttle, inputThrottle, dt * 4 )

        self:EngineAccelerate( selfTbl.flywheelFriction + selfTbl.flywheelTorque * throttle, dt )
        self:SetEngineThrottle( throttle )
        self:SetIsRedlining( isRedlining and inputThrottle > 0 )
    end
end

local ExpDecay = Glide.ExpDecay

function ENT:BoatEngineThink( dt )
    local waterState = self:GetWaterState()
    local speed = self.forwardSpeed

    throttle = 0

    if Abs( speed ) > 20 or waterState > 0 then
        throttle = inputThrottle - inputBrake
    end

    self:SetEngineThrottle( ExpDecay( self:GetEngineThrottle(), Abs( throttle ), 5, dt ) )

    local power = Abs( throttle )

    if throttle < 0 then
        power = power * Clamp( -speed / self.BoatParams.maxSpeed * 4, 0, 1 )
        power = power * 0.4

    elseif waterState > 0 then
        power = power * ( 0.4 + Clamp( Abs( speed ) / self.BoatParams.maxSpeed, 0, 1 ) * 0.6 )
        power = power * ( waterState > 1 and 0.6 or 1 )
    end

    local minRPM = self:GetMinRPM()
    local rpmRange = self:GetMaxRPM() - minRPM
    local currentPower = ( self:GetEngineRPM() - minRPM ) / rpmRange

    currentPower = ExpDecay( currentPower, power, 2 + power * 2, dt )

    self:SetFlywheelRPM( minRPM + rpmRange * currentPower )
end
