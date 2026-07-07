AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Socket"

ENT.Spawnable = true
ENT.AdminOnly = true

ENT.PhysgunDisabled = true
ENT.DoNotDuplicate = true
ENT.DisableDuplicator = true

-- TODO: Remove the radius NetworkVar and use the radius property instead
function ENT:SetupDataTables()
    self:NetworkVar( "Float", 0, "RadiusDev" )
end
