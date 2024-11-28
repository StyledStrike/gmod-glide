AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Wheel"

ENT.Spawnable = false
ENT.AdminOnly = false

ENT.PhysgunDisabled = true
ENT.DoNotDuplicate = true
ENT.DisableDuplicator = true

function ENT:SetupDataTables()
    self:NetworkVar( "Angle", "ModelAngle" )
    self:NetworkVar( "Vector", "ModelScale2" )

    self:NetworkVar( "Float", "Spin" )
    self:NetworkVar( "Float", "Radius" )
    self:NetworkVar( "Float", "SideSlip" )
    self:NetworkVar( "Float", "ForwardSlip" )
    self:NetworkVar( "Int", "ContactSurface" )
end