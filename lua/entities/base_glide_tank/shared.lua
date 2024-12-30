ENT.Type = "anim"
ENT.Base = "base_glide"

ENT.PrintName = "Glide Tank"
ENT.Author = "StyledStrike"
ENT.AdminOnly = false
ENT.AutomaticFrameAdvance = true

-- Change vehicle type
ENT.VehicleType = Glide.VEHICLE_TYPE.TANK

-- Increase default max. chassis health
ENT.MaxChassisHealth = 3000

-- Turrets are predictable, so their properties
-- should be set both on SERVER and CLIENT.
ENT.TurretOffset = Vector( 0, 0, 50 )
ENT.HighPitchAng = -25
ENT.LowPitchAng = 10
ENT.MaxYawSpeed = 50
ENT.YawSpeed = 1500

--[[
    For tanks, the values on Get/SetEngineState mean:

    0 - Off
    1 - Starting
    2 - Running
]]

DEFINE_BASECLASS( "base_glide" )

--- Override this base class function.
function ENT:SetupDataTables()
    BaseClass.SetupDataTables( self )

    self:NetworkVar( "Float", "EngineThrottle" )
    self:NetworkVar( "Float", "EnginePower" )
    self:NetworkVar( "Float", "TrackSpeed" )

    self:NetworkVar( "Angle", "TurretAngle" )
    self:NetworkVar( "Bool", "IsAimingAtTarget" )
end

--- Override this base class function.
function ENT:IsEngineOn()
    return self:GetEngineState() > 1
end

--- Override this base class function.
function ENT:GetFirstPersonOffset()
    return Vector( 0, 0, 90 )
end

--- Override this base class function.
function ENT:GetPlayerSitSequence( _seatIndex )
    return "sit"
end

-- Children classes should override this function
-- to update the turret/cannon bones.
-- This exists both on the client and server side,
-- to allow returning the correct bone position
-- when creating the projectile serverside.
function ENT:ManipulateTurretBones( _turretAngle ) end

if CLIENT then
    ENT.MaxMiscDistance = 5000
    ENT.WheelSkidmarkScale = 1

    --- Override this base class function.
    function ENT:GetCameraType( _seatIndex )
        return 1 -- Glide.CAMERA_TYPE.TURRET
    end

    -- Setup default cannon
    ENT.WeaponInfo = {
        { name = "#glide.weapons.cannon" }
    }

    -- Strips/lines where smoke particles are spawned when the engine is damaged
    ENT.EngineSmokeStrips = {}

    -- How much does the engine smoke gets shot up?
    ENT.EngineSmokeMaxZVel = 50

    -- Track sound parameters
    ENT.TrackSound = ")glide/tanks/tracks_leopard.wav"
    ENT.TrackVolume = 0.7

    -- Engine sounds
    ENT.StartSound = "Glide.Engine.TruckStart"
    ENT.StartTailSound = "Glide.Engine.CarStartTail"
    ENT.StartedSound = "glide/engines/start_tail_truck.mp3"
    ENT.StoppedSound = "glide/engines/shut_down_1.mp3"

    -- Other sounds
    ENT.TurrentMoveSound = "glide/tanks/turret_move.wav"
    ENT.TurrentMoveVolume = 1.0

    -- Children classes should override this
    -- function to add engine sounds to the stream.
    function ENT:OnCreateEngineStream( _stream ) end

    -- Children classes should override this function
    -- to update animations (the tracks/suspension for example).
    function ENT:OnUpdateAnimations() end
end

if SERVER then
    ENT.IsHeavyVehicle = true
    ENT.ChassisMass = 20000

    ENT.BulletDamageMultiplier = 0.25
    ENT.BlastDamageMultiplier = 1
    ENT.CollisionDamageMultiplier = 0.8
    ENT.EngineDamageMultiplier = 0.00035
    ENT.BlastForceMultiplier = 0.005

    ENT.SuspensionHeavySound = "Glide.Suspension.CompressTruck"
    ENT.SuspensionDownSound = "Glide.Suspension.Stress"

    -- How long does it take for the vehicle to start up?
    ENT.StartupTime = 0.8

    -- Setup default cannon
    ENT.WeaponSlots = {
        { maxAmmo = 0, fireRate = 2.0 },
    }

    ENT.TurretFireSound = ")glide/tanks/acf_fire4.mp3"
    ENT.TurretFireVolume = 0.8
    ENT.TurretRecoilForce = 50

    -- How much torque to distribute among all wheels?
    ENT.EngineTorque = 40000

    -- How much extra torque to apply when trying to spin in place?
    ENT.SpinEngineTorqueMultiplier = 3

    ENT.MaxSpeed = 700
    ENT.MaxSteerAngle = 35

    -- Children classes should override this function
    -- to set where the cannon projectile is spawned.
    function ENT:GetProjectileStartPos()
        return self:GetPos()
    end
end

local Clamp = math.Clamp
local ExpDecayAngle = Glide.ExpDecayAngle
local AngleDifference = Glide.AngleDifference

function ENT:UpdateTurret( driver, dt, currentAng )
    local aimPos = SERVER and driver:GlideGetAimPos() or Glide.GetCameraAimPos()
    local origin = self:LocalToWorld( self.TurretOffset )
    local targetDir = aimPos - origin
    targetDir:Normalize()

    local targetAng = self:WorldToLocalAngles( targetDir:Angle() )
    local isAimingAtTarget = true

    if targetAng[1] > self.LowPitchAng then
        targetAng[1] = self.LowPitchAng
        isAimingAtTarget = false

    elseif targetAng[1] < self.HighPitchAng then
        targetAng[1] = self.HighPitchAng
        isAimingAtTarget = false
    end

    currentAng[1] = ExpDecayAngle( currentAng[1], targetAng[1], 10, dt )
    currentAng[2] = currentAng[2] + Clamp( AngleDifference( currentAng[2], targetAng[2] ) * self.YawSpeed * dt, -self.MaxYawSpeed, self.MaxYawSpeed ) * dt

    isAimingAtTarget = isAimingAtTarget and targetDir:Dot( self:LocalToWorldAngles( currentAng ):Forward() ) > 0.99

    return currentAng, isAimingAtTarget
end
