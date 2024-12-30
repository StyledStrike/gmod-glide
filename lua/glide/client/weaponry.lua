killicon.Add( "glide_missile", "glide/killicons/glide_missile", color_white )
killicon.Add( "glide_rotor", "glide/killicons/glide_rotor", color_white )

local EXPLOSION_TYPE = Glide.EXPLOSION_TYPE

local EyePos = EyePos
local Effect = util.Effect
local EffectData = EffectData
local EmitSound = EmitSound

local GetVolume = Glide.Config.GetVolume
local PlaySoundSet = Glide.PlaySoundSet
local IsUnderWater = Glide.IsUnderWater

local MAX_DETAIL_DISTANCE = 4000 * 4000

function Glide.CreateExplosion( pos, normal, explosionType )
    local volume = GetVolume( "explosionVolume" )
    local isTurret = explosionType == EXPLOSION_TYPE.TURRET
    local isUnderWater = IsUnderWater( pos )

    if pos:DistToSqr( EyePos() ) < MAX_DETAIL_DISTANCE then
        if not isTurret then
            PlaySoundSet( "Glide.Explosion.Impact", pos, volume )
        end

        if explosionType == EXPLOSION_TYPE.VEHICLE then
            PlaySoundSet( "Glide.Explosion.Metal", pos, volume )
        end

        if isUnderWater then
            EmitSound( "WaterExplosionEffect.Sound", pos, 0, 6, volume, 100 )
        else
            if not isTurret then
                EmitSound( "glide/explosions/impact_fire.mp3", pos, 0, 6, volume * 0.8, 95 )
            end

            PlaySoundSet( "Glide.Explosion.PreImpact", pos, isTurret and volume * 0.4 or volume )
        end
    end

    if isUnderWater then
        local eff = EffectData()
        eff:SetOrigin( pos )
        eff:SetScale( 100 )
        eff:SetFlags( 2 )
        eff:SetNormal( normal )
        Effect( "WaterSplash", eff, true, true )
    else
        local eff = EffectData()
        eff:SetOrigin( pos )
        eff:SetNormal( normal )
        eff:SetScale( explosionType == EXPLOSION_TYPE.MISSILE and 0.7 or ( isTurret and 0.4 or 1 ) )
        Effect( "glide_explosion", eff )
    end

    if not isTurret then
        PlaySoundSet( "Glide.Explosion.Distant", pos, volume )
    end
end
