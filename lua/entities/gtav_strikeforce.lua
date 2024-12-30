-- Example car class
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_glide_plane"
ENT.PrintName = "B-11 Strikeforce"

ENT.GlideCategory = "Default"
ENT.ChassisModel = "models/gta5/vehicles/strikeforce/chassis.mdl"
ENT.MaxChassisHealth = 1500

ENT.PropOffset = Vector( 114, 0, 3 )

DEFINE_BASECLASS( "base_glide_plane" )

function ENT:SetupDataTables()
    BaseClass.SetupDataTables( self )

    self:NetworkVar( "Bool", "FiringGun" )
end

if CLIENT then
    ENT.CameraOffset = Vector( -600, 0, 150 )

    ENT.WeaponInfo = {
        { name = "#glide.weapons.explosive_cannon", icon = "glide/icons/bullets.png" },
        { name = "#glide.weapons.homing_missiles", icon = "glide/icons/rocket.png" },
        { name = "#glide.weapons.barrage_missiles", icon = "glide/icons/rocket.png" }
    }

    ENT.CrosshairInfo = {
        { iconType = "dot", traceOrigin = Vector( 0, 0, -18.5 ) },
        { iconType = "square", traceOrigin = Vector( 0, 0, -19 ) },
        { iconType = "square", traceOrigin = Vector( 0, 0, -19 ) }
    }

    ENT.ExhaustPositions = {
        Vector( -172, 50, 25 ),
        Vector( -172, -50, 25 )
    }

    ENT.StrobeLights = {
        { offset = Vector( -262, 0, 84 ), blinkTime = 0 },
        { offset = Vector( -12, 291, 9 ), blinkTime = 0.1 },
        { offset = Vector( -12, -291, 9 ), blinkTime = 0.6 }
    }

    ENT.EngineFireOffsets = {
        { offset = Vector( -175, 50, 25 ), angle = Angle( 270, 0, 0 ), scale = 0.7 },
        { offset = Vector( -175, -50, 25 ), angle = Angle( 270, 0, 0 ), scale = 0.7 }
    }

    ENT.StartSoundPath = "glide/aircraft/start_4.mp3"
    ENT.DistantSoundPath = "glide/aircraft/jet_stream.wav"
    ENT.PropSoundPath = ""

    ENT.EngineSoundPath = "glide/aircraft/engine_luxor.wav"
    ENT.EngineSoundLevel = 90
    ENT.EngineSoundVolume = 0.45
    ENT.EngineSoundMinPitch = 103
    ENT.EngineSoundMaxPitch = 132

    ENT.ExhaustSoundPath = "glide/aircraft/distant_laser.wav"
    ENT.ExhaustSoundLevel = 90
    ENT.ExhaustSoundVolume = 0.5
    ENT.ExhaustSoundMinPitch = 55
    ENT.ExhaustSoundMaxPitch = 60

    ENT.ThrustSound = "glide/aircraft/thrust_b11.wav"

    function ENT:OnActivateMisc()
        BaseClass.OnActivateMisc( self )

        self.minigunBone = self:LookupBone( "minigun" )
        self.propellerRBone = self:LookupBone( "propeller_r" )
        self.propellerLBone = self:LookupBone( "propeller_l" )

        self.rudderBone = self:LookupBone( "rudder" )
        self.elevatorRBone = self:LookupBone( "elevator_r" )
        self.elevatorLBone = self:LookupBone( "elevator_l" )
        self.aileronRBone = self:LookupBone( "aileron_r" )
        self.aileronLBone = self:LookupBone( "aileron_l" )

        self.propSpin = 0
    end

    local FrameTime = FrameTime
    local ang = Angle()

    function ENT:OnUpdateAnimations()
        if not self.rudderBone then return end

        ang[1] = 0
        ang[2] = self:GetRudder() * -15
        ang[3] = 0

        self:ManipulateBoneAngles( self.rudderBone, ang )

        ang[1] = 0
        ang[2] = self:GetElevator() * -20
        ang[3] = 0

        self:ManipulateBoneAngles( self.elevatorRBone, ang )

        ang[1] = 0
        ang[2] = 0
        ang[3] = self:GetElevator() * -20

        self:ManipulateBoneAngles( self.elevatorLBone, ang )

        local aileron = self:GetAileron()

        ang[1] = 0
        ang[2] = aileron * 15
        ang[3] = 0

        self:ManipulateBoneAngles( self.aileronRBone, ang )

        ang[2] = -ang[2]

        self:ManipulateBoneAngles( self.aileronLBone, ang )

        local power = self:GetPower()

        if power > 0.1 then
            self.propSpin = self.propSpin + FrameTime() * power * 1500
            if self.propSpin > 360 then self.propSpin = 0 end

            ang[1] = self.propSpin
            ang[2] = 0
            ang[3] = 0

            self:ManipulateBoneAngles( self.propellerRBone, ang )
            self:ManipulateBoneAngles( self.propellerLBone, ang )
        end

        if self:GetFiringGun() then
            ang[1] = ( CurTime() * 500 ) % 360
            ang[2] = 0
            ang[3] = 0

            self:ManipulateBoneAngles( self.minigunBone, ang )
        end
    end

    function ENT:OnUpdateSounds()
        BaseClass.OnUpdateSounds( self )

        local sounds = self.sounds

        if self:GetFiringGun() then
            if not sounds.gunFire then
                local gunFire = self:CreateLoopingSound( "gunFire", ")glide/weapons/b11_turret_loop.wav", 95, self )
                gunFire:PlayEx( 1.0, 100 )
            end

        elseif sounds.gunFire then
            sounds.gunFire:Stop()
            sounds.gunFire = nil

            self:EmitSound( ")glide/weapons/b11_turret_loop_end.mp3", 95, 100, 1.0 )
        end
    end
end

if SERVER then
    ENT.ChassisMass = 1500
    ENT.SpawnPositionOffset = Vector( 0, 0, 40 )
    ENT.CollisionDamageMultiplier = 5

    ENT.ExplosionGibs = {
        "models/gta5/vehicles/strikeforce/gibs/chassis.mdl",
        "models/gta5/vehicles/strikeforce/gibs/wing_l.mdl",
        "models/gta5/vehicles/strikeforce/gibs/wing_r.mdl"
    }

    ENT.HasLandingGear = true
    ENT.ReverseTorque = 2000
    ENT.SteerConeMaxSpeed = 900

    ENT.PlaneParams = {
        liftAngularDrag = Vector( -30, -60, -100 ), -- (Roll, pitch, yaw)
        maxSpeed = 2000,
        liftSpeed = 1800,
        engineForce = 250,

        pitchForce = 4000,
        yawForce = 3500,
        rollForce = 5000
    }

    ENT.WeaponSlots = {
        { maxAmmo = 0, fireRate = 0.08, replenishDelay = 0, ammoType = "explosive_cannon" },
        { maxAmmo = 0, fireRate = 1.0, replenishDelay = 0, ammoType = "missile", lockOn = true },
        { maxAmmo = 6, fireRate = 0.15, replenishDelay = 6, ammoType = "barrage" }
    }

    -- Custom weapon logic
    ENT.BulletOffset = Vector( 268, 0, -18.5 )

    ENT.MissileOffsets = {
        Vector( 50, 122, -24 ),
        Vector( 50, -122, -24 )
    }

    function ENT:CreateFeatures()
        self:CreateSeat( Vector( 157, 0, 4 ), Angle( 0, 270, 10 ), Vector( -160, 120, 0 ), true )

        -- Update default wheel params
        self.wheelParams.suspensionLength = 38
        self.wheelParams.springStrength = 1500
        self.wheelParams.springDamper = 6000
        self.wheelParams.brakePower = 2000
        self.wheelParams.sideTractionMultiplier = 250

        -- Front
        self:CreateWheel( Vector( 180, -12, -25 ), {
            steerMultiplier = 1
        } )

        self:CreateWheel( Vector( -13, 85, -25 ) ) -- Rear left
        self:CreateWheel( Vector( -13, -85, -25 ) ) -- Rear right

        self:ChangeWheelRadius( 12 )

        for _, w in ipairs( self.wheels ) do
            Glide.HideEntity( w, true )
        end

        self.missileIndex = 0
    end

    function ENT:OnWeaponFire( weapon )
        local attacker = self:GetSeatDriver( 1 )

        if weapon.ammoType == "explosive_cannon" then
            self:SetFiringGun( true )

            self:FireBullet( {
                pos = self:LocalToWorld( self.BulletOffset ),
                ang = self:GetAngles(),
                attacker = attacker,
                isExplosive = true,
                length = 8000
            } )
        else
            self.missileIndex = self.missileIndex + 1

            if self.missileIndex > #self.MissileOffsets then
                self.missileIndex = 1
            end

            local target

            -- Only make the missile follow the target when
            -- using the homing missiles and with a "hard" lock-on
            if weapon.lockOn and self:GetLockOnState() == 2 then
                target = self:GetLockOnTarget()
            end

            local pos = self:LocalToWorld( self.MissileOffsets[self.missileIndex] )
            self:FireMissile( pos, self:GetAngles(), attacker, target )
        end
    end

    function ENT:OnWeaponStop()
        self:SetFiringGun( false )
    end
end
