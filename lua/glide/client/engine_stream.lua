--[[
    Utility class to handle engine sounds with the BASS library.

    Allows the manipulation of the pitch/volume of many sound
    layers using a combination of "controllers".

    Handles the math to make 2D sounds behave like 3D on demand,
    to prevent sounds "lagging behind" fast-moving entities.
]]

local IsValid = IsValid
local DEFAULT_STREAM_PARAMS = Glide.DEFAULT_STREAM_PARAMS

local EngineStream = Glide.EngineStream or {}
EngineStream.__index = EngineStream
Glide.EngineStream = EngineStream

local streamInstances = Glide.streamInstances or {}
Glide.streamInstances = streamInstances

function Glide.DestroyAllEngineStreams()
    local IsBasedOn = scripted_ents.IsBasedOn

    for _, e in ents.Iterator() do
        if IsValid( e ) and e.GetClass and IsBasedOn( e:GetClass(), "base_glide" ) and e.stream then
            e.stream:Destroy()
            e.stream = nil
        end
    end
end

function Glide.CreateEngineStream( parent, doNotUseWebAudio )
    local id = ( Glide.lastStreamInstanceID or 0 ) + 1
    Glide.lastStreamInstanceID = id

    local stream = {
        -- Internal parameters
        id = id,
        parent = parent,
        offset = Vector( 0, 0, parent:OBBCenter()[3] ),
        layers = {},

        wobbleTime = 0,
        isPlaying = false,
        isRedlining = false,
        redlineTime = 0,
        firstPerson = false,
        volumeMultiplier = 0,

        inputs = {
            throttle = 0,
            rpmFraction = 0,
            redline = 0
        }
    }

    -- Customizable parameters
    for k, v in pairs( DEFAULT_STREAM_PARAMS ) do
        stream[k] = v
    end

    local WebAudio = Glide.WebAudio

    -- Use the Web Audio API. This does nothing if this
    -- feature is disabled, or the streamCount limit has been reached.
    if not doNotUseWebAudio then
        WebAudio:RequestStreamCreation( stream )
    end

    streamInstances[id] = stream
    Glide.PrintDev( "Stream instance #%s has been created.", id )

    return setmetatable( stream, EngineStream )
end

function EngineStream:Destroy()
    if self.isWebAudio then
        Glide.WebAudio:RequestStreamDeletion( self.id )
    end

    self:RemoveAllLayers()
    self.layers = nil
    self.parent = nil

    streamInstances[self.id] = nil
    Glide.PrintDev( "Stream instance #%s has been destroyed.", self.id )

    setmetatable( self, nil )
end

function EngineStream:RemoveAllLayers()
    for id, _ in pairs( self.layers ) do
        self:RemoveLayer( id )
    end
end

--- Convenience function to parse and load a JSON preset file
--- from `garrysmod/data_static/glide/stream_presets/`.
function EngineStream:LoadPreset( name )
    local path = "data_static/glide/stream_presets/" .. name .. ".json"
    local data = file.Read( path, "GAME" )

    if data then
        self:LoadJSON( data )
    else
        Glide.Print( "Engine stream preset not found: %s", path )
    end
end

function EngineStream:LoadJSON( data )
    data = Glide.FromJSON( data )

    local success, errorMessage = Glide.ValidateStreamData( data )

    if not success then
        Glide.Print( errorMessage )
        return
    end

    if data.kv then
        for k, v in pairs( data.kv ) do
            self[k] = v
        end
    end

    for id, layer in SortedPairs( data.layers ) do
        self:AddLayer( id, layer.path, layer.controllers, layer.redline == true )
    end

    if self.isWebAudio then
        -- Upload the (now sanitized) properties of this stream to the Web Audio Bridge
        data = {
            kv = data.kv,
            layers = {}
        }

        for id, layer in pairs( self.layers ) do
            data.layers[id] = {
                path = layer.path,
                redline = layer.redline,
                controllers = layer.controllers
            }
        end

        self.updateWebJSON = Glide.ToJSON( data, false )
    end
end

--- Builds json for the Web Audio Bridge for streams added via Lua (AddLayer vs LoadJSON).
--- Called automatically by Play() for streams configured via AddLayer().
--- Does nothing if not using WebAudio or already finalized via LoadJSON().
function EngineStream:CheckWebAudioJSON()
    if not self.isWebAudio then return end
    if self.updateWebJSON then return end

    local data = {
        kv = {},
        layers = {},
    }

    -- Copy customizable parameters
    for k, v in pairs( DEFAULT_STREAM_PARAMS ) do
        if self[k] ~= v then
            data.kv[k] = self[k]
        end
    end

    -- Copy layer data
    for id, layer in pairs( self.layers ) do
        data.layers[id] = {
            path = layer.path,
            redline = layer.redline,
            controllers = layer.controllers,
        }
    end

    self.updateWebJSON = Glide.ToJSON( data, false )
end

local outputs = {
    volume = 0,
    pitch = 0
}

do
    local VALIDATION_MSG = "Layer '%s', controller #%d: %s"

    local function Validate( controller, controllerId, layerId, stream )
        if not stream.inputs[controller[1]] then
            return false, VALIDATION_MSG:format( layerId, controllerId, "Invalid input type!" )
        end

        if type( controller[2] ) ~= "number" then
            return false, VALIDATION_MSG:format( layerId, controllerId, "Min. input value must be a number!" )
        end

        if type( controller[3] ) ~= "number" then
            return false, VALIDATION_MSG:format( layerId, controllerId, "Max. input value must be a number!" )
        end

        if not outputs[controller[4]] then
            return false, VALIDATION_MSG:format( layerId, controllerId, "Invalid output type!" )
        end

        if type( controller[5] ) ~= "number" then
            return false, VALIDATION_MSG:format( layerId, controllerId, "Min. output value must be a number!" )
        end

        if type( controller[6] ) ~= "number" then
            return false, VALIDATION_MSG:format( layerId, controllerId, "Max. output value must be a number!" )
        end

        return true
    end

    function EngineStream:AddLayer( id, path, controllers, redline )
        if self.layers[id] then
            Glide.Print( "Layer '%s' already exists!", id )
            return
        end

        if not table.IsSequential( controllers ) then
            Glide.Print( "Controllers for the layer '%s' must be a sequential table!", id )
            return
        end

        for i, c in ipairs( controllers ) do
            local valid, msg = Validate( c, i, id, self )

            if not valid then
                Glide.Print( msg )
                return
            end
        end

        self.layers[id] = {
            path = path,
            redline = redline,
            controllers = controllers,

            -- Load sound one by one to prevent random `FILEFORM` errors
            isLoaded = false,

            -- Used by the Engine Stream editor
            isMuted = false,

            -- Outputs generated by our controllers
            volume = 0,
            pitch = 0
        }
    end
end

function EngineStream:RemoveLayer( id )
    local layer = self.layers[id]
    if not layer then return end

    if IsValid( layer.channel ) then
        layer.channel:Stop()
    end

    layer.channel = nil
    self.layers[id] = nil
end

function EngineStream:SetLayerOffset( id, offset )
    local layer = self.layers[id]
    if layer then
        layer.offset = offset
    end
end

function EngineStream:Play()
    self.isPlaying = true
    self.volumeMultiplier = 0

    -- Ensure WebAudio bridge has the stream data if layers were added directly
    self:CheckWebAudioJSON()

    for _, layer in pairs( self.layers ) do
        if IsValid( layer.channel ) then
            layer.channel:Play()
        end
    end
end

function EngineStream:Pause()
    self.isPlaying = false
    self.volumeMultiplier = 0

    for _, layer in pairs( self.layers ) do
        if IsValid( layer.channel ) then
            layer.channel:Pause()
        end
    end
end

local Clamp = math.Clamp

local function FakeSpatialSound( parent, offset, fadeDist, firstPerson, eyePos, eyeRight )
    -- Calculate direction and distance from the camera
    local origin = parent:LocalToWorld( offset )
    local dir = origin - eyePos
    local dist = dir:Length()

    -- Attenuate depending on distance
    local vol = 1 - Clamp( dist / fadeDist, 0, 1 )

    -- Pan to simulate positioning the sound in the world
    dir:Normalize()
    local pan = firstPerson and 0 or eyeRight:Dot( dir )

    return vol, pan
end

local Cos = math.cos
local Remap = math.Remap
local Approach = math.Approach
local GetVolume = Glide.Config.GetVolume

local baseVol, pitch

function EngineStream:Think( dt, eyePos, eyeAng )
    if not self.isPlaying then return end

    local parent = self.parent
    if not IsValid( parent ) then return end

    if self.isWebAudio then
        -- If this stream is handled by the Web Audio Bridge,
        -- then only update the position - everything
        -- else is handled by the Web Audio Bridge logic.
        if self.firstPerson then
            self.position = eyePos + eyeAng:Forward() * 10
        else
            self.position = parent:LocalToWorld( self.offset )
        end

        return
    end

    if self.volumeMultiplier < 1 then
        self.volumeMultiplier = math.min( 1, Glide.ExpDecay( self.volumeMultiplier, 1.01, 4, dt ) )
    end

    baseVol = self.volume * self.volumeMultiplier * GetVolume( "carVolume" )
    pitch = 1

    local inputs = self.inputs

    -- Gear switch "wobble"
    if self.wobbleTime > 0 then
        self.wobbleTime = self.wobbleTime - dt * ( 0.1 + inputs.throttle )

        pitch = pitch + Cos( self.wobbleTime * self.wobbleFrequency ) * self.wobbleTime * self.wobbleStrength * 0.3
    end

    pitch = pitch * self.pitch

    -- Rapidly change volume to simulate hitting the rev limiter
    local redlineVol = 1

    if self.isRedlining then
        local strength = self.redlineStrength * 1.5
        local freq = self.redlineFrequency
        local time = self.redlineTime + dt
        self.redlineTime = time

        local stage = Cos( time * freq )
        redlineVol = 1 - strength * Clamp( 1 - stage * 2, 0, 1 )

        stage = Cos( ( time + freq * 0.2 ) * freq )
        pitch = pitch * ( 1 - ( 0.5 - stage * 0.5 ) * strength * 0.05 )
    else
        self.redlineTime = 0
    end

    inputs.redline = Approach( inputs.redline, self.isRedlining and 1 or 0, dt * 5 )

    local eyeRight = eyeAng:Right()
    local fadeDist = self.fadeDist
    local firstPerson = self.firstPerson
    local channel, value, vol, pan

    for _, layer in pairs( self.layers ) do
        channel = layer.channel

        if IsValid( channel ) then
            outputs.volume, outputs.pitch = 1, 1

            for _, c in ipairs( layer.controllers ) do
                value = Clamp( inputs[c[1]], c[2], c[3] )
                value = Remap( value, c[2], c[3], c[5], c[6] )

                -- If any previous controller(s) changed the
                -- same output type, mix their output with this one.
                outputs[c[4]] = outputs[c[4]] * value
            end

            layer.volume = outputs.volume * ( layer.redline and redlineVol or 1 )
            layer.pitch = outputs.pitch * pitch

            vol, pan = FakeSpatialSound( parent, layer.offset or self.offset, fadeDist, firstPerson, eyePos, eyeRight )

            channel:SetPlaybackRate( layer.pitch )
            channel:SetVolume( layer.isMuted and 0 or layer.volume * baseVol * vol )
            channel:SetPan( pan )

            if channel:GetState() < 1 then
                channel:Play()
            end
        end
    end
end

--[[
    Update existing stream instances, and handle
    loading `IGModAudioChannel`s one at a time.
]]

local function DestroyChannel( channel )
    if IsValid( channel ) then
        channel:Stop()
    end
end

-- Hold info about which stream and layer
-- we're loading a IGModAudioChannel for.
local loading = nil

local function LoadCallback( channel, _, errorName )
    -- Sanity check
    if loading == nil then
        DestroyChannel( channel )
        return
    end

    -- Make sure the stream instance still exists
    local stream = streamInstances[loading.streamId]

    if not stream then
        Glide.PrintDev( "Destroying channel, stream instance #%s no longer exists.", loading.streamId )
        DestroyChannel( channel )
        loading = nil
        return
    end

    -- Make sure the stream layer still exists
    local layer = stream.layers[loading.layerId]

    if not layer then
        Glide.PrintDev( "Destroying channel, stream #%s/layer #%s no longer exists.", loading.streamId, loading.layerId )
        DestroyChannel( channel )
        loading = nil
        return
    end

    -- Make sure the stream audio path has not changed
    if layer.path ~= loading.layerPath then
        Glide.PrintDev( "Destroying channel, stream #%s/layer #%s has a different path now.", loading.streamId, loading.layerId )
        DestroyChannel( channel )
        loading = nil
        return
    end

    -- Make sure the channel is valid
    if not IsValid( channel ) then
        Glide.Print( "Could not load audio for stream #%s/layer #%s: %s", loading.streamId, loading.layerId, errorName )
        loading = nil

        if stream.errorCallback then
            stream.errorCallback( layer.path, errorName )
        end

        return
    end

    loading = nil
    layer.channel = channel

    channel:EnableLooping( true )
    channel:SetPlaybackRate( 1.0 )
    channel:SetVolume( 0.0 )
    channel:SetPan( 0 )
end

local pairs = pairs
local FrameTime = FrameTime
local GetLocalViewLocation = Glide.GetLocalViewLocation

hook.Add( "Think", "Glide.ProcessEngineStreams", function()
    local dt = FrameTime()
    local eyePos, eyeAng = GetLocalViewLocation()

    for streamId, stream in pairs( streamInstances ) do
        -- Let the stream do it's thing
        stream:Think( dt, eyePos, eyeAng )

        for layerId, layer in pairs( stream.layers ) do
            -- If this layer has not loaded yet,
            -- and we are not busy loading another one...
            if not layer.isLoaded and not stream.isWebAudio and loading == nil then
                loading = {
                    streamId = streamId,
                    layerId = layerId,
                    layerPath = layer.path,
                }

                -- Prevent processing this layer again
                layer.isLoaded = true

                -- Try to create a IGModAudioChannel
                sound.PlayFile( "sound/" .. layer.path, "noplay noblock", LoadCallback )
            end
        end
    end
end )
