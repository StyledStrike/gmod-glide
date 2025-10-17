ENT.Type = "anim"
ENT.Base = "base_glide_plane"

ENT.PrintName = "Glide VTOL Plane"
ENT.Author = "StyledStrike"
ENT.AdminOnly = false
ENT.AutomaticFrameAdvance = true

-- How long does it take to transition from/to vertical flight mode?
ENT.VTOLTransitionTime = 4

DEFINE_BASECLASS( "base_glide_plane" )

--- Override this base class function.
function ENT:SetupDataTables()
    BaseClass.SetupDataTables( self )

    self:NetworkVar( "Float", "VerticalFlight" )
end

if SERVER then
    ENT.CollisionDamageMultiplier = 6

    -- Sounds to play when the VTOL state changes
    ENT.VTOLStateSounds = {
        -- Sound path (empty to not play), volume, pitch
        [0] = { "physics/metal/metal_barrel_impact_soft4.wav", 1.0, 40 },
        [1] = { "glide/aircraft/gear_down.wav", 0.9, 50 },
        [2] = { "physics/metal/metal_barrel_impact_soft4.wav", 0.9, 38 },
        [3] = { "glide/aircraft/gear_down.wav", 0.9, 45 }
    }

    -- VTOL aircraft also requires this table.
    -- On children classes, you don't have to override
    -- the whole table, just the values you want to change.
    ENT.HelicopterParams = {
        drag = Vector( 0.3, 0.5, 0.5 ),     -- Forward, right, up
        maxForwardDrag = 200,               -- Limit "forward" drag force
        maxSideDrag = 300,                  -- Limit "right" drag force

        turbulanceForce = 50,   -- Force to wobble the helicopter
        pushUpForce = 250,      -- Up input force
        pitchForce = 700,       -- Pitch input force
        yawForce = 700,         -- Yaw input force
        rollForce = 700,        -- Roll input force

        pushForwardForce = 10,  -- Forward input force
        maxSpeed = 2000,        -- `PushForwardForce` won't apply when going faster than this

        uprightForce = 1000,    -- Force that tries to keep the helicopter upright
        maxPitch = 70,          -- Don't let the helicopter pitch more than this
        maxRoll = 85            -- Don't let the helicopter roll more than this
    }

    -- You can safely override this on child classes.
    function ENT:UpdateRotorPositions( _verticalTransition ) end
end
