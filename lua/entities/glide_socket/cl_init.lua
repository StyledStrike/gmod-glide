include( "shared.lua" )

function ENT:Draw()
    self:DrawModel()

    render.SetColorMaterial()
    render.DrawWireframeSphere( self:GetPos(), self:GetRadiusDev(), 8, 8, Color( 255, 0, 0 ) )

    render.SetColorMaterial()
    local vPosMin, vPosMax = self:GetModelBounds()
    render.DrawWireframeBox( self:GetPos(), self:GetAngles(), vPosMin, vPosMax, Color( 4, 0, 255 ) )
end