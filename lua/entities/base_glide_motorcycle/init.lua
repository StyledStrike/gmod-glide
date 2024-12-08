AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

duplicator.RegisterEntityClass( "base_glide_motorcycle", Glide.VehicleFactory, "Data" )

DEFINE_BASECLASS( "base_glide_car" )

--- Override this base class function.
function ENT:OnPostInitialize()
    BaseClass.OnPostInitialize( self )

    -- Bike specific variables
    self.steerTilt = 0
    self.stayUpright = false
    self.reverseInput = 0

    -- Change slip parameters to better suit bikes
    self:SetExtremumValue( 7 )
    self:SetAsymptoteSlip( 0.8 )
    self:SetAsymptoteValue( 3 )

    self:SetMaxSlip( 25 )
    self:SetSlipForce( 50 )
    self:SetMaxSteerAngle( 35 )
end

function ENT:SetStaySpright( toggle )
    self.stayUpright = toggle

    local phys = self:GetPhysicsObject()
    if IsValid( phys ) then phys:Wake() end
end

--- Override this base class function.
function ENT:TurnOn()
    BaseClass.TurnOn( self )
    self:SetStaySpright( true )
end

--- Override this base class function.
function ENT:TurnOff()
    BaseClass.TurnOff( self )

    local driver = self:GetDriver()

    if not IsValid( driver ) then
        self:SetStaySpright( false )
    end
end

--- Override this base class function.
function ENT:OnDriverExit()
    if self.hasRagdolledAllPlayers then
        self:SetStaySpright( false )
    else
        BaseClass.OnDriverExit( self )
    end
end

--- Override this base class function.
function ENT:Use( activator )
    if not IsValid( activator ) then return end
    if not activator:IsPlayer() then return end
    if self:WaterLevel() > 2 then return end

    local freeSeat = self:GetFreeSeat()
    if not freeSeat then return end

    local WORLD_UP = Vector( 0, 0, 1 )

    if WORLD_UP:Dot( self:GetUp() ) < 0.7 then
        self:SetStaySpright( true )

        return
    end

    activator:SetAllowWeaponsInVehicle( false )
    activator:EnterVehicle( freeSeat )
end

local Abs = math.abs
local Clamp = math.Clamp
local ExpDecay = Glide.ExpDecay

--- Override this base class function.
function ENT:UpdateSteering( dt )
    local inputSteer = Clamp( self:GetInputFloat( 1, "steer" ), -1, 1 )
    local sideSlip = Clamp( self.avgSideSlip, -1, 1 )
    local speedOverFactor = Clamp( self.totalSpeed / self.SteerSpeedFactor, 0, 1 )
    local invSpeedOverFactor = 1 - speedOverFactor

    local tilt = Clamp( sideSlip * -2, -0.5, 0.5 )

    if self.areDriveWheelsGrounded then
        tilt = tilt + inputSteer * Clamp( self.forwardSpeed / 300, 0, 1 )

        if self.totalSpeed < 20 then
            tilt = tilt - 0.3
        end
    end

    self.steerTilt = ExpDecay( self.steerTilt, tilt, 6 + invSpeedOverFactor * 4, dt )

    local decay = 10 - ( Abs( inputSteer ) * 8 ) * ( 1 - Abs( sideSlip ) )

    decay = decay + invSpeedOverFactor * 5
    inputSteer = inputSteer * Clamp( invSpeedOverFactor, 0.2, 1 )
    inputSteer = ExpDecay( self.inputSteer, inputSteer, decay * 2, dt )

    local counterSteer = self.forwardSpeed > 0 and sideSlip * ( 1 - invSpeedOverFactor ) or 0

    counterSteer = Clamp( counterSteer * 0.1, -0.05, 0.05 )
    inputSteer = Clamp( inputSteer + counterSteer, -1, 1 )

    self:SetSteering( inputSteer )
    self.inputSteer = inputSteer
    self.steerAngle[2] = -inputSteer * self:GetMaxSteerAngle()

    if
        self:GetInputFloat( 1, "brake" ) > 0 and
        self:GetInputFloat( 1, "accelerate" ) < 0.1 and
        self.forwardSpeed < 10 and
        self.forwardSpeed > -100 and
        self.areDriveWheelsGrounded
    then
        if self.forwardSpeed > -50 then
            self.reverseInput = 1
        end

        self.brake = 0
        self.clutch = 1
        self:SetIsBraking( false )
    else
        self.reverseInput = 0
    end
end

--- Override this base class function.
function ENT:UpdateUnflip( _phys, _dt ) end

local WORLD_UP = Vector( 0, 0, 1 )

--- Implement this base class function.
function ENT:OnSimulatePhysics( phys, _, outLin, outAng )
    if not self.stayUpright then return end

    local angVel = phys:GetAngleVelocity()
    local mass = phys:GetMass()

    -- Apply an extra yaw angular drag
    if self.areDriveWheelsGrounded then
        outAng[3] = outAng[3] + angVel[3] * mass * self.YawDrag
    else
        self.steerTilt = 0
    end

    local rt = self:GetRight()
    local angles = self:GetAngles()

    -- Wheelie
    local leanBack = self:GetInputBool( 1, "lean_back" )

    if leanBack and self.areDriveWheelsGrounded then
        local strength = 1 - Clamp( Abs( angles[1] ) / self.WheelieMaxAng, 0, 1 )

        strength = strength * Clamp( self.totalSpeed / 200, 0, 1 )
        strength = strength * ( 1 - self.brake )

        -- Drag
        outAng[2] = outAng[2] + angVel[2] * mass * self.WheelieDrag * strength

        local frontPos = self.wheels[1]:GetPos()
        local l, a = phys:CalculateForceOffset( self:GetUp() * mass * strength * self.WheelieForce, frontPos )

        outLin[1] = outLin[1] + l[1]
        outLin[2] = outLin[2] + l[2]
        outLin[3] = outLin[3] + l[3]

        outAng[1] = outAng[1] + a[1]
        outAng[2] = outAng[2] + a[2]
        outAng[3] = outAng[3] + a[3]
    end

    -- Apply keep upright force depending on how much we are tilting
    local dot = WORLD_UP:Dot( rt )
    dot = angles[3] > -90 and angles[3] < 90 and dot or -dot

    local isGrounded = self.areDriveWheelsGrounded
    local tiltForce = isGrounded and self.TiltForce or self.TiltForce * 0.2
    local uprightForce = isGrounded and self.KeepUprightForce or self.KeepUprightForce * 0.5

    outAng[1] = outAng[1] + self.steerTilt * mass * tiltForce
    outAng[1] = outAng[1] + angVel[1] * mass * self.KeepUprightDrag
    outAng[1] = outAng[1] + dot * mass * uprightForce

    local revForce = self:GetForward() * phys:GetMass() * self.reverseInput * -400

    outLin[1] = outLin[1] + revForce[1]
    outLin[2] = outLin[2] + revForce[2]
    outLin[3] = outLin[3] + revForce[3]
end
