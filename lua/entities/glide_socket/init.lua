AddCSLuaFile( "shared.lua" )

include( "shared.lua" )

local SOLID_FLAGS = bit.bor( FSOLID_TRIGGER, FSOLID_TRIGGER_TOUCH_DEBRIS, FSOLID_USE_TRIGGER_BOUNDS )
function ENT:Initialize()
    self:SetModel( "models/hunter/blocks/cube025x025x025.mdl" )
    self:SetMoveType( MOVETYPE_NONE )
    self:SetSolid( SOLID_BBOX )
    self:SetSolidFlags( SOLID_FLAGS )
    self:SetCollisionGroup( COLLISION_GROUP_WORLD )
    self:SetNoDraw( true )

    self.radius = self.radius or 80
    local vecRadius = Vector( self.radius, self.radius, self.radius )
    self:SetCollisionBounds( -vecRadius, vecRadius )
end

function ENT:InitializeSockets( socket )
    self.id = socket.id
    self.isReceptacle = socket.isReceptacle
    self.radius = socket.radius or 80
    self.radiussqrt = self.radius * self.radius
    self.vecOffset = socket.offset or Vector()

    if socket.isReceptacle then
        self.forceLimit = socket.forceLimit or 80000
    else
        self.connectForce = socket.connectForce or 700
        self.connectDrag = socket.connectDrag or 15
    end
end

function ENT:GetIsReceptable()
    return self.isReceptacle
end

local IsValid = IsValid
local GetClass = FindMetaTable( "Entity" ).GetClass
local GetParent = FindMetaTable( "Entity" ).GetParent

local function AttemptConnection( socketPlug, socketReceptacle, phys, dt )
    local receptacleVeh = GetParent( socketReceptacle )

    -- Make sure the the other vehicle is still valid,
    -- otherwise stop the attempt.
    if not IsValid( receptacleVeh ) then
        return
    end

    -- Make sure the plug is still in range of the receptacle,
    -- otherwise stop the attempt.
    local plugPos = socketPlug:GetPos()
    local receptaclePos = socketReceptacle:GetPos()
    local distFactor = receptaclePos:Distance( plugPos ) / 80

    if distFactor > 1 then
        return
    end

    -- If we're close enough, connect now
    if distFactor < 0.02 then
        Glide.SocketConnect( socketPlug, socketReceptacle, socketReceptacle.forceLimit or 80000 )
        return
    end

    -- Try to push the plug towards the receptacle
    local dir = receptaclePos - plugPos
    dir:Normalize()

    local force = dir * ( socketPlug.connectForce or 700 )

    force = force - phys:GetVelocityAtPoint( plugPos ) * ( socketPlug.connectDrag or 15 )
    distFactor = 1 - distFactor

    phys:ApplyForceOffset( force * distFactor * phys:GetMass() * dt, plugPos )
end

local CurTime = CurTime
local TickInterval = engine.TickInterval

function ENT:Touch( ent )
    if GetClass( ent ) ~= "glide_socket" then return end
    if not self.isReceptacle or self.id ~= ent.id then return end
    if self.constraint or ent.constraint then return end

    local eVehicleTarget = GetParent( ent )
    local eVehicle = GetParent( self )
    if not IsValid( eVehicle ) or not IsValid( eVehicleTarget ) then return end
    if eVehicle == eVehicleTarget then return end

    local socketPlug = self.isReceptacle and ent or self
    if socketPlug.nextAttemptTime and CurTime() < socketPlug.nextAttemptTime then return end
    local socketReceptacle = self.isReceptacle and self or ent

    AttemptConnection( socketPlug, socketReceptacle, eVehicleTarget:GetPhysicsObject(), TickInterval() )
end

local GetDevMode = Glide.GetDevMode
function ENT:Think()
    self:NextThink( CurTime() + 0.1 )

    if not GetDevMode() then return end

    debugoverlay.Cross( self:GetPos(), 8, 0.1, Color( 255, 145, 0 ), true )
    debugoverlay.Text( self:GetPos(), ( "%s | isReceptacle: %s" ):format( self.id, tostring( self.isReceptacle ) ), 0.1, false )
end

function ENT:Disconnect()
    if IsValid( self.constraint ) then
        self.constraint:Remove()
    end

    self.constraint = nil
end

function ENT:CanTool()
    return false
end