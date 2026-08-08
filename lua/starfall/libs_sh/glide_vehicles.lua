return function( instance )

local ents_methods, unwrap = instance.Types.Entity.Methods, instance.Types.Entity.Unwrap

--- Returns whether the entity is a glide vehicle
-- @return boolean True if the entity is a glide vehicle
function ents_methods:isGlideVehicle()
	return unwrap( self ).IsGlideVehicle and true or false
end

end
