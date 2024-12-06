do
    -- Code provided by Wiremod.
    local minForce, maxForce = -100000, 100000

    -- Timer resolves issue with table not existing until next tick on Linux.
    hook.Add( "InitPostEntity", "Glide.GetForceLimit", function()
        timer.Simple( 0, function()
            maxForce = 100000 * physenv.GetPerformanceSettings().MaxVelocity
            minForce = -maxForce
        end )
    end )

    local Clamp = math.Clamp

    --- Ensures that the force is within the range
    --- of a float, to prevent physics engine crashes.
    function Glide.ClampForce( v )
        v[1] = v[1] == v[1] and Clamp( v[1], minForce, maxForce ) or 0
        v[2] = v[2] == v[2] and Clamp( v[2], minForce, maxForce ) or 0
        v[3] = v[3] == v[3] and Clamp( v[3], minForce, maxForce ) or 0
    end
end

do
    -- Filter entity duplication data
    local REQUIRED_KEYS = {
        ["DT"] = true,
        ["Pos"] = true,
        ["Angle"] = true,
        ["Mins"] = true,
        ["Maxs"] = true,
        ["Base"] = true,
        ["Class"] = true,
        ["BaseClass"] = true,
        ["PhysicsObjects"] = true,
        ["Model"] = true,
        ["EntityMods"] = true -- Entity modifiers (colors, materials, etc.)
    }

    function Glide.FilterEntityCopyTable( data, nwFields, entFields )
        nwFields = nwFields or {}
        entFields = entFields or {}

        for k, v in pairs( data ) do
            if k == "DT" then
                for name, _ in pairs( v ) do
                    if not nwFields[name] then
                        v[name] = nil -- We do not want to save this
                    end
                end

            elseif not REQUIRED_KEYS[k] and not entFields[k] then
                data[k] = nil -- We do not want to save this
            end
        end
    end
end

do
    -- Slip curve logic
    local Pow = math.pow
    local ay, bx, by = 1.0, 0.5, 0.25

    function Glide.SetupSlipParams( t )
        ay, bx, by = t.extremumValue, t.asymptoteSlip, t.asymptoteValue
    end

    function Glide.SlipCurve( x )
        return x > bx and by or ( 3 * Pow( x / bx, 2 ) - 2 * Pow( x / bx, 3 ) ) * ( by - ay ) + ay
    end
end

local IsValid = IsValid

function Glide.CanSpawnVehicle( ply )
    if not IsValid( ply ) then return false end
    if not ply:CheckLimit( "glide_vehicles" ) then return false end

    return true
end

--- On children classes, you can use this function on
--- `duplicator.RegisterEntityClass` if you want to share
--- the spawn limit with other Glide vehicles.
function Glide.VehicleFactory( ply, data )
    if not Glide.CanSpawnVehicle( ply ) then return end

    local ent = ents.Create( data.Class )
    if not IsValid( ent ) then return end

    ent:SetPos( data.Pos )
    ent:SetAngles( data.Angle )
    ent:SetCreator( ply )
    ent:Spawn()
    ent:Activate()

    ply:AddCount( "glide_vehicles", ent )

    return ent
end

--- Make a player switch to another seat
--- while inside a Glide vehicle.
function Glide.SwitchSeat( ply, seatIndex )
    local vehicle = ply:GlideGetVehicle()
    if not IsValid( vehicle ) then return end

    local seat = vehicle.seats[seatIndex]
    if not IsValid( seat ) then
        ply:EmitSound( "player/suit_denydevice.wav", 50, 100, 1.0, 6, 0, 0 )
        return
    end

    if IsValid( seat:GetDriver() ) then
        ply:EmitSound( "player/suit_denydevice.wav", 50, 100, 1.0, 6, 0, 0 )
        return
    end

    ply:ExitVehicle()
    ply:SetAllowWeaponsInVehicle( false )
    ply:EnterVehicle( seat )
end

local GetHumans = player.GetHumans

--- Finds and returns all human players near a certain position.
function Glide.GetNearbyPlayers( pos, radius )
    radius = radius * radius

    local found, count = {}, 0

    for _, ply in ipairs( GetHumans() ) do
        local dist = pos:DistToSqr( ply:GetPos() )

        if dist < radius then
            count = count + 1
            found[count] = ply
        end
    end

    return found, count
end
