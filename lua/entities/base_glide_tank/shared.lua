ENT.Type = "anim"
ENT.Base = "base_glide"

ENT.PrintName = "Glide Tank"
ENT.Author = "StyledStrike"
ENT.AdminOnly = false
ENT.AutomaticFrameAdvance = true

-- Change vehicle type
ENT.VehicleType = Glide.VEHICLE_TYPE.TANK

-- Setup player sit animations
ENT.SeatDriverAnim = "sit"
ENT.SeatPassengerAnim = "sit"

-- Increase default max. chassis health
ENT.MaxChassisHealth = 3000

--[[
    For tanks, the values on Get/SetEngineState mean:

    0 - Off
    1 - Starting
    2 - Running
]]

DEFINE_BASECLASS( "base_glide" )

function ENT:SetupDataTables()
    BaseClass.SetupDataTables( self )

    self:NetworkVar( "Float", "EngineThrottle" )
    self:NetworkVar( "Float", "EnginePower" )
    self:NetworkVar( "Float", "TrackSpeed" )

    self:NetworkVar( "Angle", "TurretAngle" )
    self:NetworkVar( "Bool", "IsAimingAtTarget" )

    if CLIENT then
        -- Callback used to play turrent movement sounds clientside
        self:NetworkVarNotify( "TurretAngle", self.OnTurretAngleChange )
    end
end

--- Override the base class `IsEngineOn` function.
function ENT:IsEngineOn()
    return self:GetEngineState() > 1
end

-- Children classes should override this function
-- to update the turret/cannon bones.
-- This exists both on the client and server side,
-- to allow returning the correct bone position
-- when creating the projectile serverside.
function ENT:ManipulateTurretBones() end

if CLIENT then
    ENT.MaxMiscDistance = 5000
    ENT.WheelSkidmarkScale = 1

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
    ENT.StartedSound = "glide/engines/start_tail_truck.wav"
    ENT.StoppedSound = "glide/engines/shut_down_1.wav"

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
    ENT.TurretFireVolume = 1.0
    ENT.TurretRecoilForce = 50

    ENT.TurretOffset = Vector( 0, 0, 150 )
    ENT.HighPitchAng = -25
    ENT.LowPitchAng = 10
    ENT.MaxYawSpeed = 1

    -- How much torque to distribute among all wheels?
    ENT.EngineTorque = 40000

    -- How much extra torque to apply when trying to spin in place?
    ENT.SpinEngineTorqueMultiplier = 2

    ENT.MaxSpeed = 700
    ENT.MaxSteerAngle = 35

    -- Children classes should override this function
    -- to set where the cannon projectile is spawned.
    function ENT:GetProjectileStartPos()
        return self:GetPos()
    end
end
