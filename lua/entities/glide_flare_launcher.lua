AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Flare Launcher"
ENT.Category = "Glide"

ENT.Spawnable = false
ENT.AdminOnly = false
ENT.AutomaticFrameAdvance = true

if not SERVER then return end

local ENT_VARS = {
    ["reloadDelay"] = true,
    ["launchForce"] = true
}

function ENT:OnEntityCopyTableFinish( data )
    Glide.FilterEntityCopyTable( data, nil, ENT_VARS )
end

function ENT:PreEntityCopy()
    Glide.PreEntityCopy( self )
end

function ENT:PostEntityPaste( ply, ent, createdEntities )
    Glide.PostEntityPaste( ply, ent, createdEntities )

    -- Update parameters in case the limits/console variables
    -- are different compared to when this entity was duped.
    self:SetReloadDelay( self.reloadDelay )
    self:SetLaunchForce( self.launchForce )
end

local function MakeSpawner( ply, data )
    if IsValid( ply ) and not ply:CheckLimit( "glide_flare_launchers" ) then return end

    local ent = ents.Create( data.Class )
    if not IsValid( ent ) then return end

    ent:SetPos( data.Pos )
    ent:SetAngles( data.Angle )
    ent:SetCreator( ply )
    ent:Spawn()
    ent:Activate()

    ply:AddCount( "glide_flare_launchers", ent )
    cleanup.Add( ply, "glide_flare_launchers", ent )

    for k, v in pairs( data ) do
        if ENT_VARS[k] then ent[k] = v end
    end

    return ent
end

duplicator.RegisterEntityClass( "glide_flare_launcher", MakeSpawner, "Data" )

function ENT:SpawnFunction( ply, tr )
    if tr.Hit then
        return MakeSpawner( ply, {
            Pos = tr.HitPos,
            Angle = Angle(),
            Class = self.ClassName
        } )
    end
end

function ENT:Initialize()
    self:SetModel( "models/props_junk/PopCan01a.mdl" )
    self:SetSolid( SOLID_VPHYSICS )
    self:SetMoveType( MOVETYPE_VPHYSICS )
    self:PhysicsInit( SOLID_VPHYSICS )
    self:SetCollisionGroup( COLLISION_GROUP_WEAPON )
    self:DrawShadow( false )

    self.reloadDelay = 0.5
    self.launchForce = 1000

    self.isFiring = false
    self.nextShoot = 0

    if WireLib then
        WireLib.CreateSpecialInputs( self,
            { "Fire", "Delay", "Force" },
            { "NORMAL", "NORMAL", "NORMAL" }
        )
    end
end

local CurTime = CurTime
local PlaySoundSet = Glide.PlaySoundSet

function ENT:Think()
    local t = CurTime()

    if self.isFiring and t > self.nextShoot then
        self.nextShoot = t + self.reloadDelay

        local dir = self:GetUp()

        local flare = ents.Create( "glide_flare" )
        flare:SetPos( self:GetPos() + dir * 10 )
        flare:SetAngles( dir:Angle() )
        flare:SetOwner( self:GetCreator() )
        flare:Spawn()

        local phys = flare:GetPhysicsObject()

        if IsValid( phys ) then
            phys:SetVelocityInstantaneous( dir * self.launchForce )
        end

        Glide.CopyEntityCreator( self, flare )
        PlaySoundSet( "Glide.FlareLaunch", self, 1 )
    end

    self:NextThink( t )

    return true
end

local cvarMinDelay = GetConVar( "glide_flare_launcher_min_delay" )
local cvarMaxForce = GetConVar( "glide_flare_launcher_max_force" )

function ENT:SetReloadDelay( delay )
    self.reloadDelay = math.Clamp( delay, cvarMinDelay and cvarMinDelay:GetFloat() or 0.1, 5 )
end

function ENT:SetLaunchForce( force )
    self.launchForce = math.Clamp( force, 100, cvarMaxForce and cvarMaxForce:GetFloat() or 3000 )
end

function ENT:TriggerInput( name, value )
    if name == "Fire" then
        self.isFiring = value > 0

    elseif name == "Delay" then
        self:SetReloadDelay( value )

    elseif name == "Force" then
        self:SetLaunchForce( value )
    end
end