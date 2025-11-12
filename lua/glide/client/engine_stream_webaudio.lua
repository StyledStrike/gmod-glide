local WebAudio = Glide.WebAudio

WebAudio.MAX_STREAMS = 32
WebAudio.HTML_FILE = "data_static/glide/web_audio_html.xml"

CreateClientConVar( "glide_webaudio_debug", "0", false, false, "", 0, 1 )

local function Print( str, ... )
    Glide.Print( "[WebAudio] " .. str, ... )
end

function WebAudio:Restart()
    self:Disable()

    timer.Simple( 0.5, function()
        self:Enable()
    end )
end

function WebAudio:Enable()
    local panel = self.panel

    if IsValid( panel ) then
        return
    end

    self.isReady = false
    Print( "Preparing..." )

    assert( file.Exists( self.HTML_FILE, "GAME" ), "The Web Audio HTML file does not exist!" )

    panel = vgui.Create( "HTML", GetHUDPanel() )
    panel:Dock( FILL )
    self.panel = panel

    panel.OnFinishLoadingDocument = function()
        self:OnHTMLReady()
    end

    panel.OnCallback = function( _, obj, func, args )
        if obj ~= "webaudio" then return end

        if self[func] then
            self[func]( self, unpack( args ) )
        end
    end

    panel.ConsoleMessage = function( _, msg, _, line, _ )
        if not isstring( msg ) then
            msg = tostring( msg )
        end

        if isnumber( line ) then
            Print( ( "[JS:%d]: %s" ):format( line, msg )  )
        else
            Print( ( "[JS]: %s" ):format( msg )  )
        end
    end

    panel:OpenURL( "asset://garrysmod/" .. self.HTML_FILE )
end

function WebAudio:Disable()
    hook.Remove( "Think", "Glide.WebAudio.Think" )

    local panel = self.panel

    if IsValid( panel ) then
        panel:Remove()
        Print( "Disabled!" )
        Glide.DestroyAllEngineStreams()
    end

    self.panel = nil
    self.isReady = false

    self.streams = nil
    self.streamCount = 0
    self.busParameters = nil
    self.room = nil
    self.lastImpulseResponseAudio = nil
end

function WebAudio:SetDebugEnabled( enabled )
    self.debugEnabled = enabled

    if IsValid( self.panel ) then
        self.panel:RunJavascript( ( "debug.setEnabled(%s);" ):format( enabled and "true" or "false" ) )
    end
end

function WebAudio:OnHTMLReady()
    local panel = self.panel

    panel:NewObject( "webaudio" )
    panel:NewObjectCallback( "webaudio", "OnStreamCreated" )

    panel:RunJavascript( ( "DEFAULT_STREAM_PARAMETERS = JSON.parse(`%s`);" ):format(
        Glide.ToJSON( Glide.DEFAULT_STREAM_PARAMS, false )
    ) )

    self:SetDebugEnabled( GetConVar( "glide_webaudio_debug" ):GetInt() > 0 )

    self.isReady = true
    self.streams = {}
    self.streamCount = 0

    self.busParameters = {
        ["preGainVolume"] = { 1.0, true },
        ["postFilterBandGain"] = { 0.0, true },
        ["dryVolume"] = { 1.0, true },
        ["wetVolume"] = { 1.0, true },
        ["delayTime"] = { 0.1, true },
        ["delayFeedback"] = { 0.1, true },
        ["postFilterQ"] = { 0.0, true },
    }

    self.room = {
        hSize = 1.0,
        vSize = 1.0,
        targetHSize = 1.0,
        targetVSize = 1.0
    }

    Print( "Ready!" )

    -- Remove existing bass Engine Streams, so that
    -- they get re-created with WebAudio enabled.
    Glide.DestroyAllEngineStreams()

    local RealTime = RealTime
    local nextThink, lastThink = RealTime(), RealTime()

    hook.Add( "Think", "Glide.WebAudio.Think", function()
        local time = RealTime()

        -- Update the listener/engine stream positions
        -- 40 times per second at most.
        if time > nextThink then
            self:Think( time - lastThink )

            nextThink = time + 0.025
            lastThink = time
        end
    end )
end

function WebAudio:OnStreamCreated( id )
    id = tonumber( id )

    local stream = self.streams[id]

    if stream then
        stream.isReady = true
    else
        -- Remove the stream from the JS side
        -- if it no longer exists on the Lua side.
        self:RequestStreamDeletion( id )
    end
end

function WebAudio:RequestStreamCreation( stream )
    if not self.isReady then return end
    if self.streamCount >= self.MAX_STREAMS then return end

    local id = stream.id
    if self.streams[id] then return end

    stream.isWebAudio = true
    stream.isReady = false
    stream.isWebPlaying = false
    stream.position = Vector()

    self.streams[id] = stream
    self.streamCount = self.streamCount + 1
    self.panel:RunJavascript( ( "manager.createStream('%s');" ):format( tostring( id ) ) )
end

function WebAudio:RequestStreamDeletion( id )
    if not self.isReady then return end

    if self.streams[id] then
        self.streams[id] = nil
        self.streamCount = self.streamCount - 1
    end

    self.panel:RunJavascript( ( "manager.destroyStream('%s');" ):format( tostring( id ) ) )
end

-- Set which audio file will be used to apply effects with the ConvolverNode.
-- Just the file name is needed here, you can find them in `sound/glide/webaudio`.
function WebAudio:SetConvolverInpulseResponseAudio( fileName )
    if self.isReady then
        self.panel:RunJavascript( ( "manager.setConvolverInpulseResponseAudio(%s);" ):format(
            fileName == nil and "undefined" or "'" .. fileName .. "'"
        ) )
    end
end

function WebAudio:SetDebugValue( id, value )
    if self.isReady then
        self.panel:RunJavascript( ( "debug.setValue('%s', '%s');" ):format( id, tostring( value ) ) )
    end
end

do
    -- Utilitiy to build one big JS string efficiently
    local lines = {}
    local lineIndex = 0

    function WebAudio.AddLine( str, ... )
        lineIndex = lineIndex + 1
        lines[lineIndex] = str:format( ... )
    end

    function WebAudio.ClearLines()
        lineIndex = 0
        table.Empty( lines )
    end

    function WebAudio.RunLines( panel )
        panel:RunJavascript( table.concat( lines, "\n" ) )
    end
end

local Clamp = math.Clamp
local ExpDecay = Glide.ExpDecay

do
    local ROOM_INPULSE_RESPONSES = {
        -- Room size, Audio (closed ceiling), Audio (open ceiling)
        { 0.3, "1.8s_99w_900hz_30m.wav", "1.8s_99w_100hz_30m.wav" },
        { 0.6, "2.8s_99w_900hz_30m.wav", "2.8s_99w_100hz_30m.wav" },
        { 0.8, "3.8s_99w_900hz_30m.wav", "3.8s_99w_100hz_30m.wav" },
        { 1.0, "4.8s_99w_900hz_30m.wav", "4.8s_99w_100hz_30m.wav" }
    }

    local ROOM_ECHO_DELAYS = {
        -- Room size, Echo delay
        { 0.05, 0.02 },
        { 0.2, 0.04 },
        { 0.3, 0.1 },
        { 0.6, 0.2 },
        { 1.0, 0.3 }
    }

    local TRACE_DIRECTIONS = {
        Vector( 5000, 0, 0 ), -- North
        Vector( -5000, 0, 0 ), -- South
        Vector( 0, 5000, 0 ), -- West
        Vector( 0, -5000, 0 ), -- East
        Vector( 0, 0, 3000 ) -- Up
    }

    local ray = {}

    local traceData = {
        output = ray,
        mask = MASK_NPCWORLDSTATIC,
        collisiongroup = COLLISION_GROUP_WORLD
    }

    local Camera = Glide.Camera
    local TraceLine = util.TraceLine
    local dirIndex, hSize, vSize = 0, 0, 0

    --- Update the room size properties.
    ---
    --- To check the room size, perform just one
    --- trace every time this function is called.
    --- Only after we've done traces in all directions,
    --- we update the target room properties.
    function WebAudio:UpdateRoom( dt, eyePos )
        local room = self.room

        dirIndex = dirIndex + 1

        if dirIndex > 5 then
            room.targetHSize = hSize / 4
            room.targetVSize = vSize

            dirIndex = 1
            hSize = 0
            vSize = 0

            -- Update room delay parameters now
            local delayTime = 0.4
            local delayFeedback = Clamp( ( 1 - room.hSize ) * ( 1 - room.vSize ) * 0.9, 0.05, 0.6 )

            if Camera.muffleSound then
                delayTime = 0.03
                delayFeedback = 0.5
            else
                for _, v in ipairs( ROOM_ECHO_DELAYS ) do
                    if room.hSize < v[1] then
                        delayTime = v[2]
                        break
                    end
                end
            end

            self:SetBusParameter( "delayTime", delayTime )
            self:SetBusParameter( "delayFeedback", delayFeedback )
            self:SetBusParameter( "postFilterBandGain", Camera.muffleSound and -9.0 or 1.0 )
            self:SetBusParameter( "postFilterQ", Camera.muffleSound and 0.4 or 0.0 )

            local impulseResponseAudio = ROOM_INPULSE_RESPONSES[1][2]

            for _, v in ipairs( ROOM_INPULSE_RESPONSES ) do
                if room.hSize < v[1] then
                    impulseResponseAudio = v[room.vSize < 0.6 and 2 or 3]
                    break
                end
            end

            if self.lastImpulseResponseAudio ~= impulseResponseAudio then
                self.lastImpulseResponseAudio = impulseResponseAudio
                self:SetConvolverInpulseResponseAudio( impulseResponseAudio )
            end
        end

        -- Update room values
        room.hSize = ExpDecay( room.hSize, room.targetHSize, 20, dt )
        room.vSize = ExpDecay( room.vSize, room.targetVSize, 10, dt )

        -- Do one trace at a time
        traceData.start = eyePos
        traceData.endpos = eyePos + TRACE_DIRECTIONS[dirIndex]

        TraceLine( traceData )

        local isAir = ray.HitSky or not ray.Hit

        if dirIndex > 4 then
            vSize = isAir and 1 or ray.Fraction
        else
            hSize = hSize + ( isAir and 1 or ray.Fraction )
        end
    end
end

local Round = math.Round

function WebAudio:SetBusParameter( id, value )
    value = Round( value, 3 )

    local param = self.busParameters[id]

    if param and value ~= param[1] then
        param[1] = value -- New value
        param[2] = true -- Update JS next tick
    end
end

local JS_SET_BUS_PARAM = "manager.setBusParameter('%s', %f);"
local JS_UPDATE_LISTENER = "manager.updateListener(%.2f, %.2f, %.2f, %.2f, %.2f, %.2f, %.2f, %.2f, %.2f);"
local JS_UPDATE_STREAM = "manager.setStreamData('%s', %.2f, %.2f, %.2f, %.2f, %.2f, %.1f, %s);"

local AddLine = WebAudio.AddLine
local GetVolume = Glide.Config.GetVolume
local GetLocalViewLocation = Glide.GetLocalViewLocation

function WebAudio:Think( dt )
    local eyePos, eyeAng = GetLocalViewLocation()
    self:UpdateRoom( dt, eyePos )

    local room = self.room

    if self.debugEnabled then
        self:SetDebugValue( "streamCount", self.streamCount )
        self:SetDebugValue( "room.hSize", room.hSize )
        self:SetDebugValue( "room.vSize", room.vSize )
    end

    local wetMultiplier = ( 1 - room.hSize ) * ( 0.5 + ( 0.4 - room.vSize * 0.6 ) )

    self:SetBusParameter( "preGainVolume", GetVolume( "carVolume" ) )
    self:SetBusParameter( "dryVolume", Round( Clamp( 1 - wetMultiplier * 0.1, 0.5, 1.0 ), 2 ) )
    self:SetBusParameter( "wetVolume", Round( Clamp( wetMultiplier * 2.5, 0.1, 1.3 ), 2 ) )

    --[[
        Create one big Javascript snippet, which will:
        - Update the listener position
        - Update bus parameters
        - Update all active stream parameters
    ]]
    self.ClearLines()

    -- Update listener position and orientation
    local fw = eyeAng:Forward()
    local up = eyeAng:Up()

    AddLine( JS_UPDATE_LISTENER,
        eyePos[1], eyePos[2], eyePos[3],
        fw[1], fw[2], fw[3],
        up[1], up[2], up[3]
    )

    -- Update audio bus parameters that have changed
    for name, data in pairs( self.busParameters ) do
        if data[2] then
            data[2] = false
            AddLine( JS_SET_BUS_PARAM, name, data[1] )
        end
    end

    -- Update all streams
    for id, stream in pairs( self.streams ) do
        if stream.isReady then
            -- If the stream preset has changed,
            -- send the full preset JSON to JS once.
            if stream.updateWebJSON then
                self.panel:RunJavascript( ( "manager.setStreamJSON('%s', `%s`);" ):format( id, stream.updateWebJSON ) )
                stream.updateWebJSON = nil
            end

            if stream.isWebPlaying ~= stream.isPlaying then
                stream.isWebPlaying = stream.isPlaying
                self.panel:RunJavascript( ( "manager.setStreamPlaying('%s', %s);" ):format( id, stream.isPlaying and "true" or "false" ) )
            end

            local position = stream.position
            local inputs = stream.inputs

            AddLine( JS_UPDATE_STREAM, id,
                position[1], position[2], position[3],
                inputs.throttle, inputs.rpmFraction, inputs.redline, stream.isRedlining
            )

            if stream.wobbleTime > 0 then
                AddLine( "manager.setStreamWobbleTime('%s', %.2f);", id, stream.wobbleTime )
                stream.wobbleTime = 0
            end
        end
    end

    self.RunLines( self.panel )
end

hook.Add( "Glide_OnConfigChange", "WebAudio.RestartOnConfigChange", function()
    if WebAudio.engineStreamBackend ~= Glide.Config.engineStreamBackend then
        WebAudio.engineStreamBackend = Glide.Config.engineStreamBackend

        if WebAudio.engineStreamBackend == 2 then
            WebAudio:Restart()
        else
            WebAudio:Disable()
        end
    end
end )

cvars.RemoveChangeCallback( "glide_webaudio_debug_toggle" )
cvars.AddChangeCallback( "glide_webaudio_debug", function( _, _, value )
    WebAudio:SetDebugEnabled( tonumber( value ) > 0 )
end, "glide_webaudio_debug_toggle" )

concommand.Add( "glide_webaudio_restart", function()
    if Glide.Config.engineStreamBackend == 2 then
        WebAudio:Restart()
    end
end )
