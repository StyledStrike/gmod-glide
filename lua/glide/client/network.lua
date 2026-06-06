local commands = {}

commands[Glide.CMD_CREATE_EXPLOSION] = function()
    local pos = net.ReadVector()
    local normal = net.ReadVector()
    local explosionType = net.ReadUInt( 2 )

    Glide.CreateExplosion( pos, normal, explosionType )
end

commands[Glide.CMD_INCOMING_DANGER] = function()
    local dangerType = net.ReadUInt( 3 )

    if dangerType == Glide.DANGER_TYPE.LOCK_ON then
        Glide.LockOnHandler:OnIncomingLockOn()

    elseif dangerType == Glide.DANGER_TYPE.MISSILE then
        Glide.LockOnHandler:OnIncomingMissile( net.ReadUInt( 32 ) )

        if IsValid( Glide.currentVehicle ) and Glide.IsAircraft( Glide.currentVehicle ) then
            Glide.ShowKeyTip(
                "#glide.notify.tip.countermeasures",
                Glide.Config.binds["aircraft_controls"]["countermeasures"],
                "materials/glide/icons/rocket.png"
            )
        end
    end
end

commands[Glide.CMD_VIEW_PUNCH] = function()
    Glide.Camera:ViewPunch( net.ReadFloat() )
end

commands[Glide.CMD_NOTIFY] = function()
    local data = Glide.ReadTable()

    if string.sub( data.text, 1, 1 ) == "#" then
        data.text = language.GetPhrase( data.text )
    end

    Glide.Notify( data )
end

commands[Glide.CMD_SHOW_KEY_NOTIFICATION] = function()
    local text = net.ReadString()
    local icon = net.ReadString()
    local inputGroup = net.ReadString()
    local inputAction = net.ReadString()
    local button = Glide.Config:GetInputActionButton( inputAction, inputGroup )

    if button then
        Glide.ShowKeyTip( text, button, icon, true )
    end
end

commands[Glide.CMD_RELOAD_VSWEP] = function()
    Glide.ReloadWeaponScript( net.ReadString() )
end

commands[Glide.CMD_IS_USING_CAM_CONTROLLER] = function()
    Glide.Camera.isPlayerUsingCamController = net.ReadBool()
end

commands[Glide.CMD_FORCE_THIRDPERSON] = function()
    local useThirdPerson = net.ReadBool()
    Glide.Camera:SetFirstPerson( not useThirdPerson )
end

net.Receive( "glide.command", function()
    local cmd = net.ReadUInt( Glide.CMD_SIZE )

    if commands[cmd] then
        commands[cmd]()
    end
end )

-- This net event can run frequently, so it was
-- separated from the `glide.command` event.
net.Receive( "glide.sync_weapon_data", function()
    local vehicle = Glide.currentVehicle

    if IsValid( vehicle ) then
        vehicle:OnSyncWeaponData()
    end
end )
