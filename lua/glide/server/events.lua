local IsValid = IsValid

hook.Add( "CanPlayerEnterVehicle", "Glide.CheckVehicleLock", function( ply, seat )
    if not IsValid( seat ) then return end
    if ply.GlideRagdoll then return false end

    -- Make sure this seat was created by Glide
    local seatIndex = seat.GlideSeatIndex
    if not seatIndex then return end

    -- Is this seat's parent a Glide vehicle?
    local parent = seat:GetParent()
    if not IsValid( parent ) then return end
    if not parent.IsGlideVehicle then return end

    if hook.Run( "Glide_CanEnterVehicle", ply, parent, seatIndex ) == false then return false end

    -- Check if this vehicle is locked
    if not parent:GetIsLocked() then return end

    if not Glide.CanEnterLockedVehicle( ply, parent ) then
        ply:EmitSound( "doors/latchlocked2.wav", 50, 100, 1.0, 6, 0, 0 )

        return false
    end
end )

-- Once a player enters a Glide vehicle, setup network variables
-- and trigger the `Glide_OnEnterVehicle` hook.
hook.Add( "PlayerEnteredVehicle", "Glide.OnEnterSeat", function( ply, seat )
    if not IsValid( seat ) then return end

    -- Make sure this seat was created by Glide
    local seatIndex = seat.GlideSeatIndex
    if not seatIndex then return end

    -- Is this seat's parent a Glide vehicle?
    local parent = seat:GetParent()
    if not IsValid( parent ) then return end
    if not parent.IsGlideVehicle then return end

    -- Holster held weapon
    local weapon = ply:GetActiveWeapon()

    if IsValid( weapon ) then
        ply.GlideLastWeaponClass = weapon:GetClass()
        ply:SetActiveWeapon( NULL )
    end

    -- Store some variables on this player
    ply.IsUsingGlideVehicle = true
    ply:SetNWEntity( "GlideVehicle", parent )
    ply:SetNWInt( "GlideSeatIndex", seatIndex )
    ply:DrawShadow( false )

    -- Make sure the player knows about their current vehicle/seat
    Glide.StartCommand( Glide.CMD_SET_CURRENT_VEHICLE, false )
    net.WriteEntity( parent )
    net.WriteUInt( seatIndex, 6 )
    net.Send( ply )

    -- Enable vehicle input
    Glide.ActivateInput( ply, parent, seatIndex )

    hook.Run( "Glide_OnEnterVehicle", ply, parent, seatIndex )
end )

-- Once a player leaves a Glide vehicle, cleanup network variables
-- and trigger the `Glide_OnExitVehicle` hook.
hook.Add( "PlayerLeaveVehicle", "Glide.OnExitSeat", function( ply )
    if not ply.IsUsingGlideVehicle then return end

    local vehicle = ply:GlideGetVehicle()
    local seatIndex = ply:GlideGetSeatIndex()

    -- Disable vehicle input
    Glide.DeactivateInput( ply )

    -- Cleanup variables
    ply.IsUsingGlideVehicle = false
    ply:SetNWEntity( "GlideVehicle", NULL )
    ply:SetNWInt( "GlideSeatIndex", 0 )
    ply:DrawShadow( true )

    -- Make sure the player knows that they aren't on a vehicle anymore
    Glide.StartCommand( Glide.CMD_SET_CURRENT_VEHICLE, false )
    net.WriteEntity( NULL )
    net.WriteUInt( 0, 6 )
    net.Send( ply )

    if IsValid( vehicle ) then
        ply:SetPos( vehicle:GetSeatExitPos( seatIndex ) )
        ply:SetVelocity( vehicle:GetPhysicsObject():GetVelocity() )
        ply:SetEyeAngles( Angle( 0, vehicle:GetAngles().y, 0 ) )
    end

    -- Restore previously held weapon
    local weaponClass = ply.GlideLastWeaponClass

    if weaponClass then
        ply.GlideLastWeaponClass = nil

        timer.Simple( 0, function()
            if IsValid( ply ) then ply:SelectWeapon( weaponClass ) end
        end )
    end

    hook.Run( "Glide_OnExitVehicle", ply, vehicle )
end )

hook.Add( "AcceptInput", "Glide.VehicleAcceptLockInputs", function( ent, inputName )
    if not IsValid( ent ) or not ent.IsGlideVehicle then return end

    if inputName == "unlock" then
        ent:SetLocked( false, true )
    elseif inputName == "lock" then
        ent:SetLocked( true, true )
    end
end )

-- Validate editable float variables and let the vehicle know they have changed.
hook.Add( "CanEditVariable", "Glide.ValidateEditVariables", function( ent, _, _, value, editor )
    if not ent.IsGlideVehicle then return end
    if not editor.min or not editor.max then return end

    value = tonumber( value )
    if not value then return false end

    if value < editor.min then return false end
    if value > editor.max then return false end

    ent.shouldUpdateWheelParams = true

    local phys = ent:GetPhysicsObject()

    if IsValid( phys ) then
        phys:Wake()
    end
end )

-- Block "Disable Collisions" option on tanks
hook.Add( "CanProperty", "Glide.BlockCollisionProperty", function( ply, property, ent )
    if not ply:IsAdmin() and property == "collision" and ent.VehicleType == Glide.VEHICLE_TYPE.TANK then
        return false
    end
end )

hook.Add( "CanTool", "Glide.BlockSomeTools", function( _ply, tr, toolname, _tool, button )
    local ent = tr.Entity
    if not IsValid( ent ) then return end
    if not ent.IsGlideVehicle then return end

    -- Block collide with world only
    if toolname == "nocollide" and button == 2 then return false end

    -- Block Fading Door
    if toolname == "fading_door" then return false end
end )

hook.Add( "EntityTakeDamage", "Glide.OverrideDamage", function( target, dmginfo )
    local inflictor = dmginfo:GetInflictor()

    if IsValid( inflictor ) and inflictor:GetClass() == "glide_missile" then
        -- Don't let missiles deal crush damage
        if dmginfo:IsDamageType( 1 ) then
            return true
        end

        if target.VehicleType == 5 then -- Glide.VEHICLE_TYPE.TANK
            -- Let missiles deal more damage to tanks
            dmginfo:SetDamage( dmginfo:GetDamage() * 5 )

        elseif target.IsArmored then
            -- Let missiles deal more damage to armored Simfphys vehicles
            dmginfo:SetDamage( dmginfo:GetDamage() * 50 )
        end
    end

    if IsValid( inflictor ) and inflictor.IsGlideVehicle and dmginfo:IsDamageType( 1 ) then -- DMG_CRUSH
        -- Set the vehicle's driver/creator as the attacker 
        local driver = inflictor:GetDriver()

        if not IsValid( driver ) then
            driver = inflictor.lastDriver
        end

        if not IsValid( driver ) then
            driver = inflictor:GetCreator()
        end

        if IsValid( driver ) then
            dmginfo:SetAttacker( driver )
        end

        if target:IsPlayer() then
            Glide.PlaySoundSet( "Glide.Collision.AgainstPlayer", target )
        end
    end

    if not target:IsPlayer() then return end

    if dmginfo:IsDamageType( 64 ) then -- DMG_BLAST
        local vehicle = target:GlideGetVehicle()

        -- Don't damage players inside of Glide vehicles
        if IsValid( vehicle ) then
            dmginfo:SetDamage( 0 )
        end
    end
end, HOOK_HIGH )

-- Mute the ringing sound effect while inside a Glide vehicle.
hook.Add( "OnDamagedByExplosion", "Glide.DisableRingingSound", function( ply, _ )
    if IsValid( ply:GlideGetVehicle() ) then
        return true
    end
end )

-- Make sure all Glide vehicles are delete-able on map cleanup.
hook.Add( "PreCleanupMap", "Glide.ClearEntityPersistFlag", function()
    local IsBasedOn = scripted_ents.IsBasedOn

    for _, e in ents.Iterator() do
        if IsValid( e ) and e.GetClass and IsBasedOn( e:GetClass(), "base_glide" ) then
            e:RemoveEFlags( EFL_KEEP_ON_RECREATE_ENTITIES )
        end
    end
end )

do
    -- Make sure some physics performance settings are
    -- at least equal to or higher than these values.
    local minimumValues = {
        MaxVelocity = 2000,
        MaxAngularVelocity = 3636,
        MinFrictionMass = 10,
        MaxFrictionMass = 2500
    }

    hook.Add( "InitPostEntity", "Glide.CheckPhysicsSettings", function()
        local settings = physenv.GetPerformanceSettings()

        for k, min in pairs( minimumValues ) do
            if settings[k] < min then
                settings[k] = min
            end
        end

        physenv.SetPerformanceSettings( settings )
    end )
end

-- The spawnmenu is configured to recognize it as a vehicle,
-- so we should run spawn hooks that are for vehicles too.
hook.Add( "PlayerSpawnSENT", "Glide.RunVehiclePreSpawnHook", function( ply, entClass )
    local entTable = scripted_ents.GetStored( entClass )
    if not entTable then return end

    local vehicleTable = entTable["t"]
    if not vehicleTable or not isstring( vehicleTable["GlideCategory"] ) then return end

    local bAllow = hook.Run( "PlayerSpawnVehicle", ply, vehicleTable["ChassisModel"], vehicleTable["PrintName"], vehicleTable )
    return bAllow ~= false
end )

hook.Add( "PlayerSpawnedSENT", "Glide.RunVehiclePostSpawnHook", function( ply, ent )
    if not IsValid( ent ) then return end
    if not ent.IsGlideVehicle then return end

    hook.Run( "PlayerSpawnedVehicle", ply, ent )

    return true
end )

local allVehicle = {}
local istable = istable
local interactPlayer = CreateConVar( "glide_interact_player", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Whether players can interact with entities while inside Glide vehicles." )

-- Clear players from all trace filters when the convar is disabled to prevent any potential issues with players getting stuck in vehicles or having collision issues after exiting.
local function clearFilterPlayers( filter )
    for i = #filter, 1, -1 do
        local entFilter = filter[i]
        if IsValid( entFilter ) and entFilter:IsPlayer() then
            if entFilter:GetCollisionGroup() == COLLISION_GROUP_WEAPON then
                entFilter:SetCollisionGroup( COLLISION_GROUP_IN_VEHICLE )
            end

            table.remove( filter, i )
        end
    end
end

cvars.AddChangeCallback( "glide_interact_player", function( _, oldValue, newValue )
    if newValue == oldValue then return end
    if newValue ~= "0" then return end

    for vehicle, _ in pairs( allVehicle ) do
        if not IsValid( vehicle ) then continue end

        for _, rotor in Glide.EntityPairs( vehicle.rotors ) do
            if IsValid( rotor ) and rotor.traceData and rotor.traceData.filter then
                clearFilterPlayers( rotor.traceData.filter )
            end
        end

        if istable( vehicle.selfTraceFilter ) then
            clearFilterPlayers( vehicle.selfTraceFilter )
        end
    end

    allVehicle = {}
end )

local function isRotorAndSeatsValid( vehicle )
    if not IsValid( vehicle ) then return false end
    if not istable( vehicle.rotors ) then return false end
    if not istable( vehicle.seats ) or #vehicle.seats == 0 then return false end

    return true
end

local function removeFilter( filter, ent, vehicleMain )
    local foundPlayer = nil
    for i = 1, #filter do
        local entFilter = filter[i]
        if entFilter == ent then
            table.remove( filter, i )
            break
        end

        if IsValid( vehicleMain ) and foundPlayer == nil and entFilter ~= ent and entFilter:IsPlayer() then
            foundPlayer = true
        end 
    end

    if IsValid( vehicleMain ) and not foundPlayer then
        allVehicle[vehicleMain] = nil
        vehicleMain:RemoveCallOnRemove( "Glide_RemoveFromVehicleList" )
    end

end

hook.Add( "Glide_OnEnterVehicle", "Glide.UpdateFilter", function( ply, vehicle )
    if not interactPlayer:GetBool() then return end

    if istable( vehicle.selfTraceFilter ) then
        table.insert( vehicle.selfTraceFilter, ply )
    end

    ply:SetCollisionGroup( COLLISION_GROUP_WEAPON )

    if not allVehicle[vehicle] then
        allVehicle[vehicle] = true
        vehicle:CallOnRemove( "Glide_RemoveFromVehicleList", function()
            allVehicle[vehicle] = nil
        end )
    end

    if not isRotorAndSeatsValid( vehicle ) then return end

    for _, rotor in Glide.EntityPairs( vehicle.rotors ) do
        if IsValid( rotor ) and rotor.traceData and rotor.traceData.filter then
            table.insert( rotor.traceData.filter, ply )
        end
    end
end )

hook.Add( "Glide_OnExitVehicle", "Glide.UpdateFilter", function( ply, vehicle )
    if not interactPlayer:GetBool() then return end

    if istable( vehicle.selfTraceFilter ) then
        removeFilter( vehicle.selfTraceFilter, ply, vehicle )
    end

    if not isRotorAndSeatsValid( vehicle ) then return end

    for _, rotor in Glide.EntityPairs( vehicle.rotors ) do
        if IsValid( rotor ) and rotor.traceData and rotor.traceData.filter then
            removeFilter( rotor.traceData.filter, ply )
        end
    end
end )

hook.Add( "PhysgunPickup", "Glide.BlockPhysgunPickup", function( _, ent )
    if not interactPlayer:GetBool() then return end
    if not IsValid( ent ) or not ent:IsPlayer() or not ent.IsUsingGlideVehicle then return end

    return false
end )

if not game.SinglePlayer() then return end

local function ResetVehicle( vehicle )
    vehicle:ResetInputs( 1 )
    vehicle:SetDriver( NULL )
    vehicle.autoTurnOffLights = false
    vehicle:TurnOff()
    vehicle:SetEngineState( 0 )

    -- Reset weapon timings
    if vehicle.weaponCount > 0 then
        for _, weapon in ipairs( vehicle.weapons ) do
            -- Reassign the VSWEP metatable
            local class = Glide.WeaponRegistry[weapon.ClassName]

            if class then
                setmetatable( weapon, { __index = class } )
            end

            weapon.nextFire = 0
            weapon.nextReload = 0
        end
    end
end

local function ResetAll()
    -- Reset solid state for all Glide seats
    for _, seat in ipairs( ents.FindByClass( "prop_vehicle_prisoner_pod" ) ) do
        local seatIndex = seat.GlideSeatIndex

        if seatIndex then
            seat:SetMoveType( MOVETYPE_NONE )
            seat:SetNotSolid( true )
            seat:DrawShadow( false )
            seat:PhysicsDestroy()
        end
    end

    -- Reset all Glide vehicles
    local classes = {
        ["base_glide"] = true,
        ["base_glide_car"] = true,
        ["base_glide_tank"] = true,
        ["base_glide_aircraft"] = true,
        ["base_glide_heli"] = true,
        ["base_glide_plane"] = true,
        ["base_glide_motorcycle"] = true,
        ["base_glide_trailer"] = true,
        ["base_glide_plane_vtol"] = true
    }

    for _, e in ents.Iterator() do
        if classes[e:GetClass()] or ( e.BaseClass and classes[e.BaseClass.ClassName] ) then
            ResetVehicle( e )
        end
    end

    -- Reset the player's current vehicle
    local ply = Entity( 1 )
    if not IsValid( ply ) then return end

    local seat = ply:GetVehicle()
    if not IsValid( seat ) then return end

    local seatIndex = seat.GlideSeatIndex
    if not seatIndex then return end

    local parent = seat:GetParent()
    if not IsValid( parent ) then return end
    if not parent.IsGlideVehicle then return end

    parent.autoTurnOffLights = false
    ply:ExitVehicle()

    timer.Simple( 0, function()
        if IsValid( seat ) then
            ply:EnterVehicle( seat )
        end
    end )
end

-- Restore state if the player was on a Glide vehicle during a Source Engine save or map transition.
hook.Add( "ClientSignOnStateChanged", "Glide.RestoreVehicle", function( _, _, newState )
    if newState == SIGNONSTATE_FULL then
        timer.Simple( 0.2, ResetAll )
    end
end )
