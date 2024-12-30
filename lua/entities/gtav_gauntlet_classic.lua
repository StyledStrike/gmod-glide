-- Example car class
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_glide_car"
ENT.PrintName = "Gauntlet Classic"

ENT.GlideCategory = "Default"
ENT.ChassisModel = "models/gta5/vehicles/gauntlet_classic/chassis.mdl"

if CLIENT then
    ENT.CameraOffset = Vector( -240, 0, 60 )

    Glide.AddSoundSet( "Glide.GautletClassic.ExhaustPop", 75, 95, 105, {
        "glide/streams/gauntlet_classic/exhaust_pop_1.mp3",
        "glide/streams/gauntlet_classic/exhaust_pop_2.mp3",
        "glide/streams/gauntlet_classic/exhaust_pop_3.mp3"
    } )

    ENT.StartedSound = "glide/streams/gauntlet_classic/start.mp3"
    ENT.ExhaustPopSound = "Glide.GautletClassic.ExhaustPop"
    ENT.HornSound = "glide/horns/car_horn_med_9.wav"

    ENT.ExhaustOffsets = {
        { pos = Vector( -98, 13, 3 ) },
        { pos = Vector( -98, 19, 3 ) },
        { pos = Vector( -98, -13, 3 ) },
        { pos = Vector( -98, -19, 3 ) }
    }

    ENT.EngineSmokeStrips = {
        { offset = Vector( 108, 0, 12 ), angle = Angle(), width = 50 }
    }

    ENT.EngineFireOffsets = {
        { offset = Vector( 75, 0, 20 ), angle = Angle() }
    }

    ENT.Headlights = {
        { offset = Vector( 102, 25, 14 ), color = Glide.DEFAULT_HEADLIGHT_COLOR },
        { offset = Vector( 102, -25, 14 ), color = Glide.DEFAULT_HEADLIGHT_COLOR }
    }

    ENT.LightSprites = {
        { type = "headlight", offset = Vector( 104, 33, 13.5 ), dir = Vector( 1, 0, 0 ), color = Glide.DEFAULT_HEADLIGHT_COLOR },
        { type = "headlight", offset = Vector( 104, 25.5, 13.5 ), dir = Vector( 1, 0, 0 ), color = Glide.DEFAULT_HEADLIGHT_COLOR },
        { type = "headlight", offset = Vector( 104, -33, 13.5 ), dir = Vector( 1, 0, 0 ), color = Glide.DEFAULT_HEADLIGHT_COLOR },
        { type = "headlight", offset = Vector( 104, -25.5, 13.5 ), dir = Vector( 1, 0, 0 ), color = Glide.DEFAULT_HEADLIGHT_COLOR },
        { type = "brake", offset = Vector( -100, 19, 18 ), dir = Vector( -1, 0, 0 ) },
        { type = "brake", offset = Vector( -100, -19, 18 ), dir = Vector( -1, 0, 0 ) },
        { type = "reverse", offset = Vector( -99, 27, 6 ), dir = Vector( -1, 0, 0 ) },
        { type = "reverse", offset = Vector( -99, -27, 6 ), dir = Vector( -1, 0, 0 ) }
    }

    function ENT:OnCreateEngineStream( stream )
        stream:LoadPreset( "gauntlet_classic" )
    end
end

if SERVER then
    ENT.SpawnPositionOffset = Vector( 0, 0, 30 )
    ENT.BurnoutForce = 80

    function ENT:GetGears()
        return {
            [-1] = 2.9, -- Reverse
            [0] = 0, -- Neutral (this number has no effect)
            [1] = 2.8,
            [2] = 1.7,
            [3] = 1.25,
            [4] = 0.95,
            [5] = 0.8
        }
    end

    ENT.LightBodygroups = {
        { type = "brake", bodyGroupId = 17, subModelId = 1 },
        { type = "reverse", bodyGroupId = 19, subModelId = 1 },
        { type = "headlight", bodyGroupId = 20, subModelId = 1 }, -- Tail lights
        { type = "headlight", bodyGroupId = 18, subModelId = 1 }  -- Headlights
    }

    function ENT:CreateFeatures()
        self:SetDifferentialRatio( 1.9 )

        self:SetMaxRPM( 25000 )
        self:SetMinRPMTorque( 1300 )
        self:SetMaxRPMTorque( 1500 )

        self:SetForwardTractionMax( 2500 )

        self:CreateSeat( Vector( -22, 18, -3 ), Angle( 0, 270, -10 ), Vector( 40, 80, 0 ), true )
        self:CreateSeat( Vector( -8, -18, -3 ), Angle( 0, 270, 5 ), Vector( -40, -80, 0 ), true )

        -- Front left
        self:CreateWheel( Vector( 69, 36, 5 ), {
            model = "models/gta5/vehicles/gauntlet_classic/wheel.mdl",
            modelAngle = Angle( 0, 90, 0 ),
            steerMultiplier = 1
        } )

        -- Front right
        self:CreateWheel( Vector( 69, -36, 5 ), {
            model = "models/gta5/vehicles/gauntlet_classic/wheel.mdl",
            modelAngle = Angle( 0, -90, 0 ),
            steerMultiplier = 1
        } )

        -- Rear left
        self:CreateWheel( Vector( -58, 36, 5 ), {
            model = "models/gta5/vehicles/gauntlet_classic/wheel.mdl",
            modelAngle = Angle( 0, 90, 0 )
        } )

        -- Rear right
        self:CreateWheel( Vector( -58, -36, 5 ), {
            model = "models/gta5/vehicles/gauntlet_classic/wheel.mdl",
            modelAngle = Angle( 0, -90, 0 )
        } )

        self:ChangeWheelRadius( 15 )
    end
end
