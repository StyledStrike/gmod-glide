--[[
    Keep track of all vehicles with sockets
    for the trailer attachment system.

    This file also has logic to detect
    when two sockets are close to eachother.
]]

--- Utility function to connect two vehicle sockets together.
function Glide.SocketConnect( socketPlug, socketReceptacle, forceLimit )
    local plugVeh = socketPlug:GetParent()
    local receptacleVeh = socketReceptacle:GetParent()

    -- Make sure both vehicles are valid
    if not IsValid( plugVeh ) then return end
    if not IsValid( receptacleVeh ) then return end

    -- Remove existing plug constaint
    if IsValid( socketPlug.constraint ) then
        socketPlug.constraint:Remove()
    end

    -- Remove existing receptacle constaint
    if IsValid( socketReceptacle.constraint ) then
        socketReceptacle.constraint:Remove()
    end

    -- Try to create a ballsocket constaint
    local constr = constraint.Ballsocket( plugVeh, receptacleVeh, 0, 0, socketReceptacle.vecOffset, forceLimit, 0, 0 )
    if not IsValid( constr ) then return end

    constr.DoNotDuplicate = true
    constr.DisableDuplicator = true

    constr:CallOnRemove( "Glide.SocketDisconnect", function()
        if IsValid( socketReceptacle ) then
            socketReceptacle.constraint = nil
        end

        if IsValid( plugVeh ) then
            plugVeh:UpdateSocketCount()
            plugVeh:OnSocketDisconnect( socketPlug )
        end

        if IsValid( socketPlug ) then
            socketPlug.constraint = nil
            socketPlug.nextAttemptTime = CurTime() + 3
        end

        if IsValid( receptacleVeh ) then
            receptacleVeh:UpdateSocketCount()
            receptacleVeh:OnSocketDisconnect( socketReceptacle )
        end
    end )

    -- Store constraint on both sockets
    socketPlug.constraint = constr
    socketReceptacle.constraint = constr

    -- Call events on both vehicles
    plugVeh:UpdateSocketCount()
    receptacleVeh:UpdateSocketCount()

    plugVeh:OnSocketConnect( socketPlug, receptacleVeh )
    receptacleVeh:OnSocketConnect( socketReceptacle, plugVeh )
end

-- Backward compatibility: this might be useful for other add-ons, but it is not necessary for Glide.
local vehiclesWithSockets = Glide.vehiclesWithSockets or {}
Glide.vehiclesWithSockets = vehiclesWithSockets

function Glide.TrackVehicleSockets( vehicle )
    if vehicle.socketCount > 0 then
        vehiclesWithSockets[#vehiclesWithSockets + 1] = vehicle
    end
end

local IsValid = IsValid
local IsVehicle = FindMetaTable( "Entity" ).IsVehicle
local Remove = table.remove
hook.Add( "EntityRemoved", "Glide.UntrackVehicleSockets", function( vehicle )
    if not IsValid( vehicle ) or not IsVehicle( vehicle ) then return end
    if vehicle.socketCount == 0 then return end

    for i = #vehiclesWithSockets, 1, -1 do
        if vehiclesWithSockets[i] == vehicle then
            Remove( vehiclesWithSockets, i )
            break
        end
    end
end )

-- Utility function to find the closest socket to `pos` from a table.
do
    local dist, closestDist, closestSocket

    function Glide.FindClosestSocket( pos, radius, idFilter, tbl )
        closestDist = radius * radius
        closestSocket = nil

        for _, socket in ipairs( tbl ) do
            dist = pos:DistToSqr( socket.pos )

            if dist < closestDist and socket.id == idFilter then
                closestDist = dist
                closestSocket = socket
            end
        end

        return closestSocket, closestDist
    end
end