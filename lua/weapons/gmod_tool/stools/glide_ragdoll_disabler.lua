TOOL.Category = "Glide"
TOOL.Name = "#tool.glide_ragdoll_disabler.name"

TOOL.Information = {
    { name = "left" },
    { name = "right" }
}

local function IsGlideVehicle( ent )
    return IsValid( ent ) and ent.IsGlideVehicle
end

local function GetGlideVehicle( trace )
    local ent = trace.Entity

    if IsGlideVehicle( ent ) then
        return ent
    end

    return false
end

local ApplyRagdollDisabler

if SERVER then
    ApplyRagdollDisabler = function( _ply, ent, data )
        if not IsGlideVehicle( ent ) then return false end

        duplicator.ClearEntityModifier( ent, "glide_ragdoll_disabler" )

        local enableFall = type( data == "table" ) and data.enableFall == true
        ent.FallOnCollision = enableFall

        duplicator.StoreEntityModifier( ent, "glide_ragdoll_disabler", {
            enableFall = enableFall
        } )

        return true
    end

    duplicator.RegisterEntityModifier( "glide_ragdoll_disabler", ApplyRagdollDisabler )
end

function TOOL:LeftClick( trace )
    local veh = GetGlideVehicle( trace )
    if not veh then return false end

    if SERVER then
        local owner = self:GetOwner()
        if not IsValid( owner ) then return end

        ApplyRagdollDisabler( owner, veh, { enableFall = false } )
    end

    return true
end

function TOOL:RightClick( trace )
    local veh = GetGlideVehicle( trace )
    if not veh then return false end

    if SERVER then
        ApplyRagdollDisabler( owner, veh, { enableFall = true } )
    end

    return true
end

function TOOL.BuildCPanel( panel )
    panel:Help( "#tool.glide_ragdoll_disabler.desc" )
end
