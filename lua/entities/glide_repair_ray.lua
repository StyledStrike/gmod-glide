AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "#tool.glide_repair_ray.name"
ENT.Category = "Glide"

ENT.Spawnable = false
ENT.AdminOnly = false
ENT.AutomaticFrameAdvance = true
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

function ENT:SetupDataTables()
    self:NetworkVar( "Float", "RepairCapacity" )
    self:NetworkVar( "Float", "RepairDistance" )
    self:NetworkVar( "Bool", "IsRepairBlocked" )
end

do
    local ray = {}

    local traceData = {
        output = ray,
        filter = { NULL, "player" },
        mask = MASK_PLAYERSOLID
    }

    function ENT:GetRepairRay()
        traceData.start = self:GetPos()
        traceData.endpos = traceData.start + self:GetUp() * self:GetRepairDistance()
        traceData.filter[1] = self

        util.TraceLine( traceData )

        return ray
    end
end

local cvarMaxCapacity = GetConVar( "glide_repair_ray_max_capacity" )

if CLIENT then
    function ENT:Initialize()
        self:SetRenderBounds( Vector( -10, -10, -10 ), Vector( 10, 10, 600 ) )
    end

    local matBeam = Material( "tripmine_laser" )
    local strInfo = "%s\n%d / %d"

    function ENT:Draw()
        self:DrawModel()

        local ply = LocalPlayer()
        local myPos = self:GetPos()

        if myPos:DistToSqr( ply:GetPos() ) < 500000 and not self:GetIsRepairBlocked() then
            local ray = self:GetRepairRay()

            render.SetMaterial( matBeam )
            render.DrawBeam( myPos, ray.HitPos, 6, 0, 10, self:GetColor() )

            if ply:GetEyeTrace().Entity == self then
                AddWorldTip( nil, string.format( strInfo, language.GetPhrase( "tool.glide_repair_ray.name" ),
                    self:GetRepairCapacity(), cvarMaxCapacity:GetInt() ), nil, myPos, nil )
            end
        end
    end
end

if not SERVER then return end

function ENT:OnEntityCopyTableFinish( data )
    Glide.FilterEntityCopyTable( data, {
        RepairDistance = true -- Only save this
    } )
end

function ENT:PreEntityCopy()
    Glide.PreEntityCopy( self )
end

function ENT:PostEntityPaste( ply, ent, createdEntities )
    Glide.PostEntityPaste( ply, ent, createdEntities )
end

local function MakeSpawner( ply, data )
    if IsValid( ply ) and not ply:CheckLimit( "glide_repair_rays" ) then return end

    local ent = ents.Create( data.Class )
    if not IsValid( ent ) then return end

    ent:SetPos( data.Pos )
    ent:SetAngles( data.Angle )
    ent:SetCreator( ply )
    ent:Spawn()
    ent:Activate()

    ply:AddCount( "glide_repair_rays", ent )
    cleanup.Add( ply, "glide_repair_rays", ent )

    return ent
end

duplicator.RegisterEntityClass( "glide_repair_ray", MakeSpawner, "Data" )

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

    self.isActive = false
    self.lastThinkT = CurTime()
    self.lastPos = self:GetPos()

    self:SetRepairCapacity( 0 )
    self:SetRepairDistance( 100 )

    if WireLib then
        WireLib.CreateSpecialInputs( self,
            { "Activate", "Distance" },
            { "NORMAL", "NORMAL" }
        )

        WireLib.CreateSpecialOutputs( self, { "Capacity" }, { "NORMAL" } )
    end
end

local CurTime = CurTime
local TriggerOutput = WireLib and WireLib.TriggerOutput or nil

local cvarRefillSpeed = GetConVar( "glide_repair_ray_refill_per_second" )
local cvarOutputSpeed = GetConVar( "glide_repair_ray_output_per_second" )

function ENT:Think()
    local t = CurTime()
    local dt = t - self.lastThinkT

    self.lastThinkT = t

    local repairCapacity = self:GetRepairCapacity()

    if TriggerOutput then
        TriggerOutput( self, "Capacity", repairCapacity )
    end

    local myPos = self:GetPos()
    local moveSpeed = ( ( self.lastPos - myPos ) / dt ):LengthSqr()
    self.lastPos = myPos

    local isRepairBlocked = moveSpeed > 1000
    self:SetIsRepairBlocked( isRepairBlocked )

    local wasHealthIncreased, hasFinished = false, false

    if self.isActive and not isRepairBlocked and repairCapacity > 0 then
        local ray = self:GetRepairRay()
        local ent = ray.Entity

        if IsValid( ent ) and ent.IsGlideVehicle and ent:WaterLevel() < 3 then
            local repairAmount = math.Clamp( cvarOutputSpeed:GetInt() * dt, 0, repairCapacity )

            wasHealthIncreased, hasFinished = Glide.PartialRepair( ent, repairAmount, repairAmount * 0.002 )

            if wasHealthIncreased then
                repairCapacity = repairCapacity - repairAmount
                self:SetRepairCapacity( repairCapacity )
            end

            if hasFinished then
                self:EmitSound( "buttons/lever6.wav", 75, math.random( 70, 80 ), 0.8 )

            elseif wasHealthIncreased then
                self:EmitSound( ( "glide/train/track_clank_%d.wav" ):format( math.random( 6 ) ), 75, 150, 0.4 )

                local data = EffectData()
                data:SetOrigin( ray.HitPos + ray.HitNormal * 5 )
                data:SetNormal( ray.HitNormal )
                data:SetScale( 1 )
                data:SetMagnitude( 1 )
                data:SetRadius( 10 )
                util.Effect( "cball_bounce", data, false, true )
            end
        end
    end

    if not wasHealthIncreased and not isRepairBlocked then
        self:SetRepairCapacity( math.Clamp( repairCapacity + cvarRefillSpeed:GetInt() * dt, 0, cvarMaxCapacity:GetInt() ) )
    end

    self:NextThink( t + 0.1 )

    return true
end

function ENT:TriggerInput( name, value )
    if name == "Activate" then
        self.isActive = value > 0

    elseif name == "Distance" then
        self:SetRepairDistance( math.Clamp( value, 10, 200 ) )
    end
end
