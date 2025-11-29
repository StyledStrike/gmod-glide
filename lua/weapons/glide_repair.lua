local repairSpeedMulCvar = CreateConVar( "glide_repairswep_speedmul", 1, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Changes the repair speed of the glide Vehicle Repair SWEP", 0, 100 )

SWEP.PrintName = "#glide.swep.repair"
SWEP.Instructions = "#glide.swep.repair.desc"
SWEP.Author = "StyledStrike"
SWEP.Category = "Glide"

SWEP.Slot = 0
SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.UseHands = true
SWEP.ViewModelFOV = 60
SWEP.BobScale = 0.5
SWEP.SwayScale = 1.0

SWEP.ViewModel = "models/weapons/v_physcannon.mdl"
SWEP.WorldModel = "models/weapons/w_physics.mdl"

if CLIENT then
    SWEP.DrawCrosshair = false
    SWEP.BounceWeaponIcon = false
    SWEP.WepSelectIcon = surface.GetTextureID( "glide/vgui/glide_repair_wrench_icon" )
    SWEP.IconOverride = "glide/vgui/glide_repair_wrench.png"
end

SWEP.DrawAmmo = false
SWEP.HoldType = "physgun"

SWEP.Primary.Ammo = "none"
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = 0
SWEP.Primary.Automatic = true

SWEP.Secondary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = 0
SWEP.Secondary.Automatic = false

function SWEP:Initialize()
    self:SetHoldType( self.HoldType )
    self:SetDeploySpeed( 1.5 )
end

function SWEP:Deploy()
    self:SetHoldType( self.HoldType )
    self:SetDeploySpeed( 1.5 )
    self:SetNextPrimaryFire( CurTime() + 0.5 )

    self.repairTarget = NULL
    self.repairTrace = nil

    return true
end

function SWEP:Holster()
    self.repairTarget = NULL
    self.repairTrace = nil

    return true
end

function SWEP:GetVehicleFromTrace( trace, user )
    if user:EyePos():DistToSqr( trace.HitPos ) > 8000 then
        return
    end

    local ent = trace.Entity

    if IsValid( ent ) and ent.IsGlideVehicle and ent:WaterLevel() < 3 then
        return ent, trace
    end
end

function SWEP:Think()
    local user = self:GetOwner()

    if IsValid( user ) then
        self.repairTarget, self.repairTrace = self:GetVehicleFromTrace( user:GetEyeTraceNoCursor(), user )
    end
end

function SWEP:PrimaryAttack()
    local user = self:GetOwner()
    if not IsValid( user ) then return end

    self:SetNextPrimaryFire( CurTime() + 0.1 )

    if not SERVER then return end

    local ent = self.repairTarget
    if not ent then return end

    local repairMul = repairSpeedMulCvar:GetFloat()
    local wasHealthIncreased, hasFinished = Glide.PartialRepair( ent, 20 * repairMul, 0.03 * repairMul, user )

    if wasHealthIncreased then
        user:EmitSound( ( "glide/train/track_clank_%d.wav" ):format( math.random( 6 ) ), 75, 150, 0.2 )

        if user.ViewPunch then
            user:ViewPunch( Angle( -0.2, 0, 0 ) )
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
            data:SetRadius( 3 )
            util.Effect( "cball_bounce", data, false, true )
        end
    end

    if hasFinished then
        user:EmitSound( "buttons/lever6.wav", 75, math.random( 110, 120 ), 0.5 )
    end
end

function SWEP:SecondaryAttack()
end

if not CLIENT then return end

function SWEP:DrawHUD()
    if not self:IsWeaponVisible() then return end

    local ent = self.repairTarget
    if not IsValid( ent ) then return end

    local x, y = ScrW() * 0.5, ScrH() * 0.5

    Glide.DrawWeaponCrosshair( x, y, "glide/aim_dot.png", 0.05, Color( 255, 255, 255, 255 ) )

    local w = math.floor( ScrH() * 0.4 )
    local h = math.floor( ScrH() * 0.03 )

    x = x - w * 0.5
    y = y + h * 2

    Glide.DrawVehicleHealth( x, y, w, h, ent.VehicleType, ent:GetChassisHealth() / ent.MaxChassisHealth, ent:GetEngineHealth() )

    return true
end
