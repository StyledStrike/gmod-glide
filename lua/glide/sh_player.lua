local PlayerMeta = FindMetaTable( "Player" )
local EntityMeta = FindMetaTable( "Entity" )
local GetNWEntity = EntityMeta.GetNWEntity

do
    local GetNWInt = EntityMeta.GetNWInt

    function PlayerMeta:GlideGetVehicle()
        return GetNWEntity( self, "GlideVehicle", NULL )
    end

    function PlayerMeta:GlideGetSeatIndex()
        return GetNWInt( self, "GlideSeatIndex", 0 )
    end
end

if SERVER then
    function PlayerMeta:GlideGetAimAngles()
        return self.GlideCameraAngles or Angle()
    end

    function PlayerMeta:GlideGetAimPos()
        return self.GlideCameraAimPos or Vector()
    end

    --- This function is deprecated, it has been
    --- replaced by Player:GlideGetAimAngles.
    function PlayerMeta:GlideGetCameraAngles()
        return self.GlideCameraAngles or Angle()
    end

    --- Utility function to get the entity creator
    --- or CPPI owner from a entity.
    function Glide.GetEntityCreator( source )
        local ply

        if source.CPPIGetOwner then
            ply = source:CPPIGetOwner()
        end

        if type( ply ) == "number" then
            ply = nil
        end

        if not IsValid( ply ) then
            ply = source:GetCreator()
        end

        return ply
    end

    --- Utility function to set the entity creator
    --- or CPPI owner for a entity.
    function Glide.SetEntityCreator( target, ply )
        target:SetCreator( ply or NULL )

        if target.CPPISetOwner then
            target:CPPISetOwner( ply )
        end
    end

    --- Utility function to copy the entity creator
    --- or CPPI owner from one entity to another.
    function Glide.CopyEntityCreator( source, target )
        local ply = Glide.GetEntityCreator( source )
        Glide.SetEntityCreator( target, ply )
    end

    local IsValid = IsValid
    local EntEyePos = EntityMeta.EyePos

    hook.Add( "SetupMove", "Glide.CacheCameraLocation", function( ply, _, cmd )
        local vehicle = GetNWEntity( ply, "GlideVehicle", NULL )
        if not IsValid( vehicle ) then return end

        local angles = cmd:GetViewAngles()

        ply.GlideCameraAngles = angles
        ply.GlideCameraAimPos = EntEyePos( ply ) + angles:Forward() * cmd:GetUpMove()
    end, HOOK_HIGH )
end
