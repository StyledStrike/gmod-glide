local IsValid = IsValid

function ENT:SocketInit()
    self.socketCount = #self.Sockets
    Glide.TrackVehicleSockets( self )
end

function ENT:DisconnectAllSockets()
    for _, socket in ipairs( self.Sockets ) do
        local eSocket = socket.entity
        if IsValid( eSocket ) and IsValid( eSocket.constraint ) then
            eSocket.constraint:Remove()
        end
    end
end

function ENT:UpdateSocketCount()
    local connectedReceptacles = 0

    for _, socket in ipairs( self.Sockets ) do
        local eSocket = socket.entity
        if socket.isReceptacle and IsValid( eSocket ) and IsValid( eSocket.constraint ) then
            connectedReceptacles = connectedReceptacles + 1
        end
    end

    self:SetConnectedReceptacleCount( connectedReceptacles )
end
