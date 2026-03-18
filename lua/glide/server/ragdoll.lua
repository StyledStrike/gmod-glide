local IsValid = IsValid

--- Stores necessary data to respawn a player later,
--- and to restore the health, armor and inventory.
function Glide.StoreSpawnInfo( ply )
    local data = {
        health = ply:Health(),
        armor = ply:Armor(),
        god = ply:HasGodMode()
    }

    -- Store inventory
    data.weapons = {}

    for _, weapon in ipairs( ply:GetWeapons() ) do
        data.weapons[weapon:GetClass()] = {
            clip1 = weapon:Clip1(),
            clip2 = weapon:Clip2(),
            ammo1 = ply:GetAmmoCount( weapon:GetPrimaryAmmoType() ),
            ammo2 = ply:GetAmmoCount( weapon:GetSecondaryAmmoType() )
        }
    end

    -- Store current held weapon class
    local weapon = ply:GetActiveWeapon()

    if IsValid( weapon ) then
        data.weaponClass = weapon:GetClass()
    end

    ply.GlideSpawnData = data
end

do
    local function RestoreWeapons( ply, spawnData )
        ply:StripWeapons()
        ply:RemoveAllAmmo()

        for class, data in pairs( spawnData.weapons ) do
            local weapon = ply:Give( class )

            if IsValid( weapon ) then
                if weapon.SetClip1 then
                    weapon:SetClip1( data.clip1 )
                end

                if weapon.SetClip2 then
                    weapon:SetClip2( data.clip2 )
                end

                ply:SetAmmo( data.ammo1, weapon:GetPrimaryAmmoType() )
                ply:SetAmmo( data.ammo2, weapon:GetSecondaryAmmoType() )
            end
        end

        if spawnData.weaponClass then
            ply:SelectWeapon( spawnData.weaponClass )
        end
    end

    --- Restores health, armor and inventory previously stored on
    --- `Glide.StoreSpawnInfo`. Does nothing if there is no data from that function.
    function Glide.RestoreSpawnInfo( ply, restoreCallback )
        ply:Spawn()

        local spawnData = ply.GlideSpawnData
        if not spawnData then return end

        ply.GlideSpawnData = nil
        ply:SetHealth( spawnData.health )
        ply:SetArmor( spawnData.armor )

        if spawnData.god then
            ply:GodEnable()
        end

        timer.Simple( 0.1, function()
            if not IsValid( ply ) then return end
            if not ply:Alive() then return end

            if spawnData.health > 0 then
                RestoreWeapons( ply, spawnData )
            end

            if restoreCallback then
                restoreCallback( ply )
            end
        end )
    end
end

--- Returns a list of all bone positions/rotations from a player,
--- while making sure those are relative to the world even while inside a vehicle.
local function GetAllBones( ply )
    local veh = ply:GetVehicle()
    local rotation, upAxis

    if IsValid( veh ) then
        rotation = Angle( 0, 270, 0 )
        upAxis = veh:GetUp()
    end

    local max = ply:GetBoneCount() - 1
    local bones = {}
    local pos, ang

    for i = 0, max do
        pos, ang = ply:GetBonePosition( i )

        if pos then
            if rotation then
                pos = veh:WorldToLocal( pos )
                ang = veh:WorldToLocalAngles( ang )

                pos:Rotate( rotation )
                ang:RotateAroundAxis( upAxis, rotation[2] )

                pos = veh:LocalToWorld( pos )
                ang = veh:LocalToWorldAngles( ang )
            end

            bones[i] = { pos, ang }
        end
    end

    return bones
end

--- Apply bone positions obtained from the function above to a ragdoll.
local function PoseRagdollBones( ragdoll, bones, velocity )
    local max = ragdoll:GetPhysicsObjectCount() - 1
    local boneId, bone

    for i = 0, max do
        local phys = ragdoll:GetPhysicsObjectNum( i )

        if IsValid( phys ) then
            phys:SetDamping( 0.3, 10 )
            phys:Wake()

            boneId = ragdoll:TranslatePhysBoneToBone( i )

            if boneId and bones[boneId] then
                bone = bones[boneId]

                phys:SetPos( bone[1], true )
                phys:SetAngles( bone[2] )
            end

            phys:SetVelocity( velocity )
        end
    end
end

function Glide.RagdollPlayer( ply, velocity, unragdollTime )
    local success, velocityOverride, unragdollTimeOverride = hook.Run( "Glide_CanRagdollPlayer", ply, velocity, unragdollTime )
    if success == false then return end

    velocity = velocityOverride or velocity
    unragdollTime = unragdollTimeOverride or unragdollTime

    if ply.GlideRagdoll then return end

    local bones = GetAllBones( ply )

    -- Let RagMod Reworked deal with this, if it is installed
    if ragmod then
        if not ragmod:IsRagdoll( ply ) then
            local ragdoll = ragmod:TryToRagdoll( ply )

            if IsValid( ragdoll ) then
                PoseRagdollBones( ragdoll, bones, velocity )
            end
        end

        return
    end

    hook.Run( "Glide_PrePlayerRagdoll", ply )

    -- Create ragdoll
    local ragdoll = ents.Create( "prop_ragdoll" )
    if not IsValid( ragdoll ) then return end

    -- Store where the player started ragdolling
    ply.GlideRagdollStartPos = ply:GetPos()

    -- Setup ragdoll, disable grabbing/duplication
    ragdoll:SetPos( ply.GlideRagdollStartPos )
    ragdoll:SetModel( ply:GetModel() )
    ragdoll:Spawn()
    ragdoll:Activate()

    ragdoll.PhysgunDisabled = true
    ragdoll.DoNotDuplicate = true
    ragdoll.DisableDuplicator = true
    ragdoll.IsGlideRagdoll = true
    ragdoll.GlideRagdollPlayer = ply

    -- Get current player pose
    local bodygroups = {}

    for _, v in ipairs( ply:GetBodyGroups() ) do
        bodygroups[v.id] = ply:GetBodygroup( v.id )
    end

    -- Use the pose data on the ragdoll
    PoseRagdollBones( ragdoll, bones, velocity )

    -- Copy the player's appearance to the ragdoll
    ragdoll:SetSkin( ply:GetSkin() )

    for id, submodel in ipairs( bodygroups ) do
        ragdoll:SetBodygroup( id, submodel )
    end

    if ply:InVehicle() then
        ply:ExitVehicle()
    end

    -- Store health, armor and inventory
    Glide.StoreSpawnInfo( ply )

    -- Make the player spectate the ragdoll
    ply:SetActiveWeapon( NULL )
    ply:SetVelocity( Vector() )
    ply:Spectate( OBS_MODE_CHASE )
    ply:SpectateEntity( ragdoll )

    ply.GlideRagdoll = ragdoll
    ply.GlideRagdollTimeout = CurTime() + 1

    -- Automatically unragdoll after some time
    if unragdollTime and unragdollTime > 0 then
        timer.Create( "Glide_Ragdoll_" .. ply:EntIndex(), unragdollTime, 1, function()
            Glide.UnRagdollPlayer( ply )
        end )
    end

    hook.Run( "Glide_PostPlayerRagdoll", ply )
end

do
    local GetDevMode = Glide.GetDevMode
    local TraceLine = util.TraceLine
    local TraceHull = util.TraceHull

    local ray = {}

    --- Check if a vehicle exit position/ragdoll respawn point is unobstructed.
    function Glide.ValidateExitPos( origin, pos, traceData )
        traceData = traceData or {}

        traceData.mins = traceData.mins or Vector( -20, -20, 0 )
        traceData.maxs = traceData.maxs or Vector( 20, 20, 50 )

        -- First, make sure there's nothing in between `origin` and `pos`
        traceData.start = origin
        traceData.endpos = pos
        traceData.output = ray -- Output TraceResult to this table

        TraceLine( traceData )

        if ray.Hit then
            if GetDevMode() then
                debugoverlay.Line( origin, traceData.endpos, 8, Color( 255, 0, 0 ), true )
                debugoverlay.EntityTextAtPosition( traceData.endpos, 0, "<blocked>", 8, Color( 255, 0, 0 ) )
            end

            return true, pos
        end

        -- Second, make sure the player's hitbox can fit on `pos`
        traceData.start = pos
        traceData.endpos = pos

        TraceHull( traceData )

        if ray.StartSolid then
            if GetDevMode() then
                debugoverlay.Line( origin, traceData.endpos, 8, Color( 255, 100, 0 ), true )
                debugoverlay.EntityTextAtPosition( traceData.endpos, 0, "<too small>", 8, Color( 255, 100, 0 ) )
            end

            return true, pos
        end

        if GetDevMode() then
            debugoverlay.Line( origin, pos, 8, Color( 0, 255, 0 ), true )
            debugoverlay.Box( pos, traceData.mins, traceData.maxs, 8, Color( 255, 255, 255, 20 ) )
        end

        return false, pos
    end

    --- Attempt to find and place `origin` into a
    --- unobstructed spot suitable for a player.
    function Glide.GetFreeSpaceForPlayer( ply, origin, range )
        range = range or 80

        local traceData = {
            mask = MASK_SHOT_HULL - MASK_WATER, -- Ignore water
            collisiongroup = COLLISION_GROUP_VEHICLE
        }

        traceData.mins, traceData.maxs = ply:GetHull()

        -- Check if the `origin` is unobstructed
        local offset = Vector( 0, 0, 5 )
        local blocked, endPos = Glide.ValidateExitPos( origin, origin + offset, traceData )

        if not blocked then
            return endPos
        end

        -- Check for unobstructed positions around `origin`
        local rad

        for ang = 0, 360, 30 do
            rad = math.rad( ang )

            offset[1] = math.cos( rad ) * range
            offset[2] = math.sin( rad ) * range

            blocked, endPos = Glide.ValidateExitPos( origin, origin + offset, traceData )

            if not blocked then
                return endPos
            end
        end

        return origin
    end
end

function Glide.UnRagdollPlayer( ply, restoreCallback )
    if not IsValid( ply ) then return end

    hook.Run( "Glide_PrePlayerUnRagdoll", ply )

    timer.Remove( "Glide_Ragdoll_" .. ply:EntIndex() )

    -- Make sure this player is still ragdolled
    local ragdoll = ply.GlideRagdoll
    if not ragdoll then return end

    local pos = ply.GlideRagdollStartPos
    local velocity = Vector()

    -- Get final position/velocity from the ragdoll
    if IsValid( ragdoll ) then
        velocity = ragdoll:GetVelocity()
        pos = ragdoll:GetPos()

        ragdoll:Remove()
    end

    -- Cleanup ragdoll data from the player
    ply.GlideRagdoll = nil
    ply.GlideRagdollStartPos = nil
    ply.GlideRagdollTimeout = nil
    ply:UnSpectate()

    if not ply:Alive() then return end

    local ang = Angle( 0, ply:GetAngles()[2], 0 )
    local bed = ply.SpawnBed

    ply.SpawnBed = nil -- Spawn Beds workaround
    ply.GlideBlockLoadout = true -- Custom Loadout workaround

    -- Restore health, armor and inventory
    Glide.RestoreSpawnInfo( ply, function( restoredPly )
        restoredPly:SetPos( Glide.GetFreeSpaceForPlayer( restoredPly, pos ) )
        restoredPly:SetEyeAngles( ang )
        restoredPly:SetVelocity( velocity )

        -- Reset Spawn Beds workaround
        if IsValid( bed ) then
            restoredPly.SpawnBed = bed
        end

        if restoreCallback then
            restoreCallback( restoredPly )
        end
    end )

    -- Immediately put the player close to where they will be
    -- after the callback on `RestoreSpawnInfo` runs.
    ply:SetPos( pos )
    ply:SetEyeAngles( ang )

    -- Reset Custom Loadout workaround
    ply.GlideBlockLoadout = nil

    hook.Run( "Glide_PostPlayerUnRagdoll", ply )
end

hook.Add( "CanTool", "Glide.BlockPlayerRagdolls", function( _, tr )
    if IsValid( tr.Entity ) and tr.Entity.IsGlideRagdoll then
        return false
    end
end )

hook.Add( "CanProperty", "Glide.BlockPlayerRagdolls", function( _, _, ent )
    if ent.IsGlideRagdoll then
        return false
    end
end )

hook.Add( "PlayerDeath", "Glide.CleanupPlayerRagdolls", function( victim )
    if victim.GlideRagdoll then
        Glide.UnRagdollPlayer( victim )
    end
end )

hook.Add( "PlayerDisconnected", "Glide.CleanupPlayerRagdolls", function( ply )
    if ply.GlideRagdoll then
        Glide.UnRagdollPlayer( ply )
    end
end )

hook.Add( "PreCleanupMap", "Glide.CleanupPlayerRagdolls", function()
    for _, ply in ipairs( player.GetAll() ) do
        Glide.UnRagdollPlayer( ply )
    end
end )

hook.Add( "EntityTakeDamage", "Glide.RagdollDamage", function( ent, dmginfo )
    if not ent.IsGlideRagdoll then return end

    local ply = ent.GlideRagdollPlayer
    if not IsValid( ply ) then return end

    local spawnData = ply.GlideSpawnData
    if not spawnData then return end

    if spawnData.god then return end
    if spawnData.health < 1 then return end

    if dmginfo:IsDamageType( 1 ) then
        dmginfo:SetDamage( math.ceil( dmginfo:GetDamage() * 0.1 ) )
    end

    local ignore = hook.Run( "EntityTakeDamage", ply, dmginfo )
    if ignore then return end

    local damage = dmginfo:GetDamage()
    if damage < 1 then return end

    spawnData.health = spawnData.health - damage

    if spawnData.health < 1 then
        local attacker = dmginfo:GetAttacker()
        local inflictor = dmginfo:GetInflictor()

        Glide.UnRagdollPlayer( ply, function( restoredPly )
            attacker = IsValid( attacker ) and attacker or restoredPly
            inflictor = IsValid( inflictor ) and inflictor or restoredPly

            restoredPly:SetHealth( 1 )
            restoredPly:TakeDamage( 999, attacker, inflictor )
        end )
    end
end )

hook.Add( "CLoadoutCanGiveWeapons", "Glide.BlockRagdollLoadout", function( ply )
    if ply.GlideBlockLoadout then return false end
end )

hook.Add( "KeyPress", "Glide.LeaveRagdoll", function( ply, key )
    if ply.GlideRagdoll and CurTime() > ply.GlideRagdollTimeout and key ~= IN_USE then
        Glide.UnRagdollPlayer( ply )
    end
end )
