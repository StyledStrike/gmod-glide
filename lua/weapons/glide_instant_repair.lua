SWEP.Base = "glide_repair"

SWEP.PrintName = "#glide.swep.instant_repair"
SWEP.Instructions = "#glide.swep.repair.desc"
SWEP.Author = "StyledStrike"
SWEP.Category = "Glide"

SWEP.Slot = 0
SWEP.Spawnable = true
SWEP.AdminOnly = true

if CLIENT then
    SWEP.WepSelectIcon = surface.GetTextureID( "glide/vgui/glide_repair_wrench_icon" )
    SWEP.IconOverride = "glide/vgui/glide_repair_wrench_admin.png"
end

function SWEP:PrimaryAttack()
    local user = self:GetOwner()
    if not IsValid( user ) then return end

    self:SetNextPrimaryFire( CurTime() + 0.1 )

    if not SERVER then return end

    local ent = self.repairTarget
    if not ent then return end

    local wasHealthIncreased, hasFinished = Glide.PartialRepair( ent, 99999, 1.0, user )

    if wasHealthIncreased then
        if user.ViewPunch then
            user:ViewPunch( Angle( -5, 0, 0 ) )
        end

        self:SendWeaponAnim( ACT_VM_PRIMARYATTACK )
        user:SetAnimation( PLAYER_ATTACK1 )

        local trace = self.repairTrace

        if trace then
            local data = EffectData()
            data:SetOrigin( trace.HitPos + trace.HitNormal * 5 )
            data:SetNormal( trace.HitNormal )
            data:SetScale( 1 )
            data:SetMagnitude( 1 )
            data:SetRadius( 10 )
            util.Effect( "cball_bounce", data, false, true )
        end
    end

    if hasFinished then
        user:EmitSound( "buttons/lever6.wav", 75, math.random( 70, 80 ), 0.5 )
    end
end
