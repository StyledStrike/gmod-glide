local PlayerMeta = FindMetaTable( "Player" )
local EntityMeta = FindMetaTable( "Entity" )

local GetTable = EntityMeta.GetTable
local IsValid = EntityMeta.IsValid

do
    local GetVehicle = PlayerMeta.GetVehicle
    local GetParent = EntityMeta.GetParent

    function PlayerMeta:GlideGetVehicle()
        local seat = GetVehicle( self )

        if IsValid( seat ) then
            local parent = GetParent( seat )
            local tab = GetTable( parent )

            if tab and tab.IsGlideVehicle then
               return parent
            end
        end
    end
end

do
    local GetNWInt = EntityMeta.GetNWInt

    function PlayerMeta:GlideGetSeatIndex()
        return GetNWInt( self, "GlideSeatIndex", 0 )
    end

    Glide._OriginalGetAimVector = Glide._OriginalGetAimVector or PlayerMeta.GetAimVector
    function PlayerMeta:GetAimVector()
        -- There is a significant risk or it may even be the case that the vector will always return the LocalPlayer's value instead of the intended player's if called on the client side.
        if self:GlideGetSeatIndex() ~= 0 then
            return ( ( CLIENT and Glide.GetCameraAimPos() or self:GlideGetAimPos() ) - self:EyePos() ):GetNormalized()
        end

        return Glide._OriginalGetAimVector( self )
    end

end

if SERVER then
    function PlayerMeta:GlideGetAimAngles()
        return GetTable( self ).GlideCameraAngles or Angle()
    end

    function PlayerMeta:GlideGetAimPos()
        return GetTable( self ).GlideCameraAimPos or Vector()
    end

    --- This function is deprecated, it has been
    --- replaced by Player:GlideGetAimAngles.
    PlayerMeta.GlideGetCameraAngles = PlayerMeta.GlideGetAimAngles

    do
        local EnterVehicle = Glide._OriginalEnterVehicle or PlayerMeta.EnterVehicle
        Glide._OriginalEnterVehicle = EnterVehicle

        function PlayerMeta:EnterVehicle( vehicle )
            local tab = GetTable( vehicle )

            if tab.IsGlideVehicle and isfunction( tab.GetFreeSeat ) then
                local seat = tab.GetFreeSeat( vehicle )

                if not seat or not IsValid( seat ) then
                    return
                end

                return EnterVehicle( self, seat )
            end

            return EnterVehicle( self, vehicle )
        end

        Glide._OriginalEyeAngles = Glide._OriginalEyeAngles or EntityMeta.EyeAngles
        local IsPlayer = PlayerMeta.IsPlayer
        function EntityMeta:EyeAngles()
            if IsPlayer( self ) and self.IsUsingGlideVehicle then
                return self:GlideGetAimAngles()
            end

            return Glide._OriginalEyeAngles( self )
        end

    end

    --- Utility function to get the entity creator
    --- or CPPI owner from a entity.
    function Glide.GetEntityCreator( source )
        local ply

        if source.CPPIGetOwner then
            ply = source:CPPIGetOwner()
        end

        if not ply or not IsValid( ply ) then
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

    local EntEyePos = EntityMeta.EyePos

    local SCALE = 8
    hook.Add( "SetupMove", "Glide.CacheCameraLocation", function( ply, _, cmd )
        local vehicle = ply:GlideGetVehicle()
        if not vehicle then return end

        local aimPos = Vector(
            cmd:GetForwardMove() * SCALE,
            cmd:GetSideMove() * SCALE,
            cmd:GetUpMove() * SCALE
        )

        ply.GlideCameraAimPos = aimPos
        ply.GlideCameraAngles = ( aimPos - EntEyePos( ply ) ):Angle()
    end, HOOK_HIGH )
end
