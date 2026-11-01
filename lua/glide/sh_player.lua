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
        return GetNWInt( self, "GlideSeatIndex" )
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

    hook.Add( "SetupMove", "Glide.CacheCameraLocation", function( ply, _, cmd )
        local vehicle = ply:GlideGetVehicle()
        if not vehicle then return end

        local angles = cmd:GetViewAngles()
        local eyepos = angles:Forward()
        eyepos:Mul( cmd:GetUpMove() )
        eyepos:Add( EntEyePos( ply ) )

        ply.GlideCameraAngles = angles
        ply.GlideCameraAimPos = eyepos
    end, HOOK_HIGH )
end
