local ENT_META = FindMetaTable( "Entity" )

return function( instance )

local Ent_IsValid, Ent_IsWorld = ENT_META.IsValid, ENT_META.IsWorld
local ents_methods, ent_meta = instance.Types.Entity.Methods, instance.Types.Entity

local function getent( self )
	local ent = ent_meta.sf2sensitive[self]
	if Ent_IsValid( ent ) or Ent_IsWorld( ent ) then
		return ent
	else
		SF.Throw( "Entity is not valid.", 3 )
	end
end

--- Returns whether the entity is a glide vehicle
-- @return boolean True if the entity is a glide vehicle
function ents_methods:isGlideVehicle()
	return getent( self ).IsGlideVehicle and true or false
end

end
