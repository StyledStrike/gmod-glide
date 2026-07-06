AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "cl_init.lua" )

include( "shared.lua" )

function ENT:Initialize()
    self:SetModel( "models/hunter/blocks/cube025x025x025.mdl" )
    self:SetMoveType( MOVETYPE_NONE )
    self:SetSolid( SOLID_BBOX )
    self:SetSolidFlags( bit.bor( FSOLID_TRIGGER, FSOLID_TRIGGER_TOUCH_DEBRIS, FSOLID_USE_TRIGGER_BOUNDS ) )
    self:SetCollisionGroup( COLLISION_GROUP_WORLD )
    self:SetNoDraw( true )

    self.radius = self.radius or 80
    local vecRadius = Vector( self.radius, self.radius, self.radius )
    self:SetCollisionBounds( -vecRadius, vecRadius )
end

function ENT:GetID()
    return self.id
end

function ENT:InitializeSockets( id, isReceptacle, radius )
    self.id = id
    self.isReceptacle = isReceptacle
    self.radius = radius or 80
    self.radiussqrt = self.radius * self.radius

    -- TODO: Remove the radius NetworkVar
    self:SetRadiusDev( self.radius )
end

function ENT:GetIsReceptable()
    return self.isReceptacle
end

function ENT:Touch()
    print( "TOUCH" )
end