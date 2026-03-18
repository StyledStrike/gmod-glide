if SERVER then
    util.AddNetworkString( "glide.command" )
    util.AddNetworkString( "glide.sync_weapon_data" )
end

-- Size limit for user JSON data
Glide.MAX_JSON_SIZE = 3072 -- 3 kibibytes

-- Used on net.WriteUInt for the command ID
Glide.CMD_SIZE = 4

-- Command IDs (Max. ID when CMD_SIZE == 4 is 15)
Glide.CMD_INPUT_SETTINGS = 0
Glide.CMD_CREATE_EXPLOSION = 1
Glide.CMD_SWITCH_SEATS = 2
Glide.CMD_INCOMING_DANGER = 3
Glide.CMD_LAST_AIM_ENTITY = 4
Glide.CMD_VIEW_PUNCH = 5
Glide.CMD_SET_HEADLIGHTS = 6
Glide.CMD_NOTIFY = 7
Glide.CMD_SHOW_KEY_NOTIFICATION = 8
Glide.CMD_SET_CURRENT_VEHICLE = 9
Glide.CMD_UPLOAD_ENGINE_STREAM_PRESET = 10
Glide.CMD_UPLOAD_MISC_SOUNDS_PRESET = 11
Glide.CMD_RELOAD_VSWEP = 13
Glide.CMD_IS_USING_CAM_CONTROLLER = 14
Glide.CMD_FORCE_THIRDPERSON = 15

function Glide.StartCommand( id, unreliable )
    net.Start( "glide.command", unreliable or false )
    net.WriteUInt( id, Glide.CMD_SIZE )
end

function Glide.WriteTable( t )
    local json = Glide.ToJSON( t )

    if #json > Glide.MAX_JSON_SIZE then
        Glide.Print( "The JSON data length that was too big! (%d/%d)", #json, Glide.MAX_JSON_SIZE )
        net.WriteUInt( 0, 16 )
        return
    end

    local data = util.Compress( json )
    local len = #data

    if len > Glide.MAX_JSON_SIZE then
        net.WriteUInt( 0, 16 )
        Glide.Print( "Tried to write data that was too big! (%d/%d)", len, Glide.MAX_JSON_SIZE )
        return
    end

    net.WriteUInt( len, 16 )
    net.WriteData( data )
end

function Glide.ReadTable()
    local len = net.ReadUInt( 16 )

    if len < 1 then
        return {}
    end

    if len > Glide.MAX_JSON_SIZE then
        Glide.Print( "The reported JSON data length that was too big! (%d/%d)", len, Glide.MAX_JSON_SIZE )
        return {}
    end

    local data = net.ReadData( len )

    if not data then
        Glide.Print( "Failed to read JSON data!" )
        return {}
    end

    data = util.Decompress( data )

    if not data then
        Glide.Print( "Failed to decompress JSON data!" )
        return {}
    end

    if #data > Glide.MAX_JSON_SIZE then
        Glide.Print( "Tried to read data that was too big! (%d/%d)", #data, Glide.MAX_JSON_SIZE )
        return {}
    end

    return Glide.FromJSON( data )
end
