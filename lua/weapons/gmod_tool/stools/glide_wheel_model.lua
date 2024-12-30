TOOL.Category = "Glide"
TOOL.Name = "#tool.glide_wheel_model.name"

TOOL.Information = {
    { name = "left" },
    { name = "right" }
}

TOOL.ClientConVar = {
    front = "models/props_vehicles/apc_tire001.mdl",
    front_scale_x = 1,
    front_scale_y = 1,
    front_scale_z = 1,

    rear = "models/props_vehicles/apc_tire001.mdl",
    rear_scale_x = 1,
    rear_scale_y = 1,
    rear_scale_z = 1
}

local function ValidateModel( model )
    if type( model ) ~= "string" then
        return false
    end

    if not file.Exists( model, "GAME" ) then
        return false
    end

    return true
end

local IsValid = IsValid

local function IsGlideVehicle( ent )
    return IsValid( ent ) and ent.IsGlideVehicle
end

local GetWheels, ApplyWheelMods

if SERVER then
    GetWheels = function( ent )
        if not IsGlideVehicle( ent ) then return false end

        local frontWheels, rearWheels = {}, {}
        local frontCount, rearCount = 0, 0
        local hiddenCount = 0

        if ent.wheels then
            for _, w in ipairs( ent.wheels ) do
                if IsValid( w ) then
                    if w.GlideIsHidden then
                        hiddenCount = hiddenCount + 1
                    end

                    if w.isFrontWheel then
                        frontCount = frontCount + 1
                        frontWheels[frontCount] = w
                    else
                        rearCount = rearCount + 1
                        rearWheels[rearCount] = w
                    end
                end
            end
        end

        return frontWheels, rearWheels, hiddenCount
    end

    local function ApplyToWheels( wheels, model, scale )
        local data = list.Get( "GlideWheelModels" )[model]
        if not data then return end

        scale = ( data.scale or Vector( 1, 1, 0.35 ) ) * scale

        local angle = data.angle or Angle( 0, 0, 270 )
        local offset = data.offset or Vector( 0, 0, 0 )

        for _, w in ipairs( wheels ) do
            if not w.GlideIsHidden then
                w.modelOverride = model
                w.modelScale = scale
                w:SetModel( model )
                w:ChangeRadius()

                if w.isOnRight then
                    w:SetModelOffset( -offset )
                    w:SetModelAngle( angle + Angle( 0, 180, 0 ) )
                else
                    w:SetModelOffset( offset )
                    w:SetModelAngle( angle )
                end
            end
        end
    end

    ApplyWheelMods = function( _ply, ent, data )
        if not IsGlideVehicle( ent ) then return false end

        local frontModel = data.FrontModel
        local rearModel = data.RearModel

        local frontScaleX = Glide.ValidateNumber( data.FrontScaleX, 0.1, 5, 1 )
        local frontScaleY = Glide.ValidateNumber( data.FrontScaleY, 0.1, 5, 1 )
        local frontScaleZ = Glide.ValidateNumber( data.FrontScaleZ, 0.1, 5, 1 )

        local rearScaleX = Glide.ValidateNumber( data.RearScaleX, 0.1, 5, 1 )
        local rearScaleY = Glide.ValidateNumber( data.RearScaleY, 0.1, 5, 1 )
        local rearScaleZ = Glide.ValidateNumber( data.RearScaleZ, 0.1, 5, 1 )

        if ValidateModel( frontModel ) and ValidateModel( rearModel ) then
            local frontWheels, rearWheels = GetWheels( ent )

            ApplyToWheels( frontWheels, frontModel, Vector( frontScaleX, frontScaleY, frontScaleZ ) )
            ApplyToWheels( rearWheels, rearModel, Vector( rearScaleX, rearScaleY, rearScaleZ ) )

            duplicator.StoreEntityModifier( ent, "glide_wheel_mods", data )

            return true
        end

        return false
    end

    duplicator.RegisterEntityModifier( "glide_wheel_mods", ApplyWheelMods )
end

function TOOL:GetTraceGlideEntities( trace )
    local ent = trace.Entity
    if not IsGlideVehicle( ent ) then return false end
    if not SERVER then return ent end

    local owner = self:GetOwner()
    local frontWheels, rearWheels, hiddenCount = GetWheels( ent )
    local frontCount = #frontWheels
    local rearCount = #rearWheels

    if hiddenCount == frontCount + rearCount then
        Glide.SendNotification( owner, {
            text = "#tool.glide_wheel_model.vehicle_model",
            icon = "materials/icon16/cancel.png",
            sound = "glide/ui/radar_alert.mp3",
            immediate = true
        } )

        return false
    end

    if frontCount + rearCount < 1 then
        Glide.SendNotification( owner, {
            text = "#tool.glide_water_driving.no_wheels",
            icon = "materials/icon16/cancel.png",
            sound = "glide/ui/radar_alert.mp3",
            immediate = true
        } )

        return false
    end

    return ent, frontWheels, rearWheels
end

function TOOL:LeftClick( trace )
    local vehicle = self:GetTraceGlideEntities( trace )
    if not vehicle then return false end

    if SERVER then
        ApplyWheelMods( self:GetOwner(), vehicle, {
            FrontModel = self:GetClientInfo( "front" ),
            RearModel = self:GetClientInfo( "rear" ),

            FrontScaleX = self:GetClientNumber( "front_scale_x", 1 ),
            FrontScaleY = self:GetClientNumber( "front_scale_y", 1 ),
            FrontScaleZ = self:GetClientNumber( "front_scale_z", 1 ),

            RearScaleX = self:GetClientNumber( "rear_scale_x", 1 ),
            RearScaleY = self:GetClientNumber( "rear_scale_y", 1 ),
            RearScaleZ = self:GetClientNumber( "rear_scale_z", 1 )
        } )
    end

    return true
end

function TOOL:RightClick( trace )
    local vehicle, frontWheels, rearWheels = self:GetTraceGlideEntities( trace )
    if not vehicle then return false end

    if SERVER then
        local ply = self:GetOwner()

        if #frontWheels > 0 then
            local frontModel = frontWheels[1]:GetModel()
            ply:ConCommand( "glide_wheel_model_front " .. frontModel )
        end

        if #rearWheels > 0 then
            local rearModel = rearWheels[1]:GetModel()
            ply:ConCommand( "glide_wheel_model_rear " .. rearModel )
        end
    end

    return true
end

function TOOL:Reload()
    return false
end

function TOOL.BuildCPanel( panel )
    local models = {}

    for path, _ in pairs( list.Get( "GlideWheelModels" ) ) do
        models[path] = { convar = path }
    end

    -- Front wheels
    panel:Help( "#tool.glide_wheel_model.front_scale" )

    panel:NumSlider( "X", "glide_wheel_model_front_scale_x", 0.1, 5, 2 )
    panel:NumSlider( "Y", "glide_wheel_model_front_scale_y", 0.1, 5, 2 )
    panel:NumSlider( "Z", "glide_wheel_model_front_scale_z", 0.1, 5, 2 )

    panel:PropSelect( "#tool.glide_wheel_model.front_model", "glide_wheel_model_front", models, 3 )

    -- Rear wheels
    panel:Help( "#tool.glide_wheel_model.rear_scale" )

    panel:NumSlider( "X", "glide_wheel_model_rear_scale_x", 0.1, 5, 2 )
    panel:NumSlider( "Y", "glide_wheel_model_rear_scale_y", 0.1, 5, 2 )
    panel:NumSlider( "Z", "glide_wheel_model_rear_scale_z", 0.1, 5, 2 )

    panel:PropSelect( "#tool.glide_wheel_model.rear_model", "glide_wheel_model_rear", models, 3 )
end

list.Set( "GlideWheelModels", "models/gta5/vehicles/airbus/wheel_front.mdl", { angle = angle_zero, scale = Vector( 1, 0.35, 1 ) } )
list.Set( "GlideWheelModels", "models/gta5/vehicles/airbus/wheel_rear.mdl", { angle = angle_zero, scale = Vector( 1, 0.35, 1 ) } )
list.Set( "GlideWheelModels", "models/gta5/vehicles/blazer/wheel.mdl", { angle = Angle( 0, 90, 0 ), scale = Vector( 0.5, 1, 1 ) } )
list.Set( "GlideWheelModels", "models/gta5/vehicles/dukes/wheel.mdl", { angle = Angle( 0, 90, 0 ), scale = Vector( 0.35, 1, 1 ) } )
list.Set( "GlideWheelModels", "models/gta5/vehicles/gauntlet_classic/wheel.mdl", { angle = Angle( 0, 90, 0 ), scale = Vector( 0.35, 1, 1 ) } )
list.Set( "GlideWheelModels", "models/gta5/vehicles/speedo/wheel.mdl", { angle = Angle( 0, 90, 0 ), scale = Vector( 0.35, 1, 1 ) } )
list.Set( "GlideWheelModels", "models/gta5/vehicles/stunt/stunt_wheel.mdl", { angle = Angle( 0, 180, 0 ), scale = Vector( 1, 0.6, 1 ) } )

list.Set( "GlideWheelModels", "models/mechanics/wheels/bmw.mdl", {} )
list.Set( "GlideWheelModels", "models/mechanics/wheels/rim_1.mdl", {} )
list.Set( "GlideWheelModels", "models/mechanics/wheels/tractors.mdl", {} )
list.Set( "GlideWheelModels", "models/mechanics/wheels/wheel_2.mdl", {} )
list.Set( "GlideWheelModels", "models/mechanics/wheels/wheel_extruded_48.mdl", {} )
list.Set( "GlideWheelModels", "models/mechanics/wheels/wheel_race.mdl", {} )
list.Set( "GlideWheelModels", "models/mechanics/wheels/wheel_rounded_36.mdl", {} )
list.Set( "GlideWheelModels", "models/mechanics/wheels/wheel_rugged_24.mdl", {} )
list.Set( "GlideWheelModels", "models/mechanics/wheels/wheel_spike_24.mdl", {} )
list.Set( "GlideWheelModels", "models/nateswheel/nateswheel.mdl", { angle = Angle( 0, 90, 0 ), scale = Vector( 0.4, 1, 1 ) } )
list.Set( "GlideWheelModels", "models/props_phx/normal_tire.mdl", { offset = Vector( 0, -4, 0 ) } )
list.Set( "GlideWheelModels", "models/props_phx/smallwheel.mdl", { offset = Vector( 0, -4, 0 ) } )
list.Set( "GlideWheelModels", "models/props_phx/wheels/747wheel.mdl", { offset = Vector( 0, -4, 0 ) } )
list.Set( "GlideWheelModels", "models/props_phx/wheels/breakable_tire.mdl", { offset = Vector( 0, -4, 0 ) } )
list.Set( "GlideWheelModels", "models/props_phx/wheels/drugster_back.mdl", { offset = Vector( 0, -4, 0 ) } )
list.Set( "GlideWheelModels", "models/props_phx/wheels/drugster_front.mdl", { offset = Vector( 0, -4, 0 ) } )
list.Set( "GlideWheelModels", "models/props_phx/wheels/magnetic_large.mdl", { offset = Vector( 0, -4, 0 ) } )
list.Set( "GlideWheelModels", "models/props_phx/wheels/monster_truck.mdl", { offset = Vector( 0, -3.5, 0 ) } )
list.Set( "GlideWheelModels", "models/props_phx/wheels/moped_tire.mdl", { offset = Vector( 0, -7, 0 ) } )
list.Set( "GlideWheelModels", "models/props_phx/wheels/trucktire.mdl", { offset = Vector( 0, -3.5, 0 ) } )
list.Set( "GlideWheelModels", "models/props_phx/wheels/trucktire2.mdl", { offset = Vector( 0, -3.5, 0 ) } )
list.Set( "GlideWheelModels", "models/props_vehicles/apc_tire001.mdl", { angle = Angle( 0, 90, 0 ), scale = Vector( 0.35, 1, 1 ) } )
list.Set( "GlideWheelModels", "models/xeon133/offroad/off-road-30.mdl", { angle = Angle( 0, 90, 0 ), scale = Vector( 0.4, 1, 1 ) } )
list.Set( "GlideWheelModels", "models/xeon133/racewheel/race-wheel-30.mdl", { angle = Angle( 90, 0, 0 ), scale = Vector( 1, 0.4, 1 ) } )
list.Set( "GlideWheelModels", "models/xqm/airplanewheel1medium.mdl", { angle = Angle( 0, 90, 0 ), scale = Vector( 0.35, 1, 1 ) } )
