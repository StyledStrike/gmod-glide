TOOL.Category = "Glide"
TOOL.Name = "#tool.glide_bullet_proof_tires.name"

TOOL.Information = {
    { name = "left" },
    { name = "reload" }
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

local ApplyVehicleBulletproof

if SERVER then
    ApplyVehicleBulletproof = function( _ply, vehicle, data )
        if not IsGlideVehicle( vehicle ) then
            return false
        end

        duplicator.ClearEntityModifier( vehicle, "glide_wheel_bulletproof" )

        local wheels = vehicle.wheels

        if type( wheels ) ~= "table" then
            return false
        end

        local isBulletProof = data.isBulletProof == true

        for _, wheel in Glide.EntityPairs( wheels ) do
            wheel.params.isBulletProof = isBulletProof
        end

        duplicator.StoreEntityModifier( vehicle, "glide_wheel_bulletproof", { isBulletProof = isBulletProof } )

        return true
    end

    duplicator.RegisterEntityModifier( "glide_wheel_bulletproof", ApplyVehicleBulletproof )
end

function TOOL:LeftClick( trace )
    local veh = GetGlideVehicle( trace )
    if not veh then return false end

    if SERVER then
        local ply = self:GetOwner()

        if veh.wheelCount < 1 then
            Glide.SendNotification( ply, {
                text = "#tool.glide_water_driving.no_wheels",
                icon = "materials/icon16/cancel.png",
                sound = "glide/ui/radar_alert.wav",
                immediate = true
            } )

            return false
        end

        for _, wheel in Glide.EntityPairs( veh.wheels ) do
            wheel:Repair()
        end

        return ApplyVehicleBulletproof( ply, veh, { isBulletProof = true } )
    end

    return true
end

function TOOL:RightClick( _trace )
    return false
end

function TOOL:Reload( trace )
    local veh = GetGlideVehicle( trace )
    if not veh then return false end

    if SERVER then
        local ply = self:GetOwner()

        if veh.wheelCount < 1 then
            Glide.SendNotification( ply, {
                text = "#tool.glide_water_driving.no_wheels",
                icon = "materials/icon16/cancel.png",
                sound = "glide/ui/radar_alert.wav",
                immediate = true
            } )

            return false
        end

        return ApplyVehicleBulletproof( ply, veh, { isBulletProof = false } )
    end

    return true
end

function TOOL.BuildCPanel( panel )
    panel:Help( "#tool.glide_bullet_proof_tires.desc" )
end
