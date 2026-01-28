AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_glide"

ENT.PrintName = "Glide Trailer"
ENT.Author = "StyledStrike"
ENT.AdminOnly = false
ENT.AutomaticFrameAdvance = true

DEFINE_BASECLASS( "base_glide" )

--- Override this base class function.
function ENT:SetupDataTables()
    BaseClass.SetupDataTables( self )

    self:NetworkVar( "Bool", "IsAttached" )
    self:NetworkVar( "Bool", "IsVehicleReversing" )

    self:SetIsAttached( false )
    self:SetIsVehicleReversing( false )
end

--- Override this base class function.
function ENT:IsReversing()
    return self:GetIsVehicleReversing()
end

if CLIENT then
    ENT.TurnSignalVolume = 0
end

if not SERVER then return end

ENT.CanCatchOnFire = false
ENT.BlastDamageMultiplier = 3
ENT.BulletDamageMultiplier = 0
ENT.CollisionDamageMultiplier = 0

-- Trailer sounds
ENT.AttachSound = "buttons/lever3.wav"
ENT.AttachSoundPitch = 85
ENT.DetachSound = "buttons/lever5.wav"
ENT.DetachSoundPitch = 90

--- Implement this base class function.
function ENT:OnPostInitialize()
    -- Trigger wire outputs
    if WireLib then
        WireLib.TriggerOutput( self, "IsAttached", 0 )
    end
end

--- Override this base class function.
function ENT:SetupWiremodPorts( inputs, outputs )
    BaseClass.SetupWiremodPorts( self, inputs, outputs )

    outputs[#outputs + 1] = { "IsAttached", "NORMAL", "0: Detached\n1: Attached to a vehicle" }
end

function ENT:UpdateWiremodOutputs()
    if WireLib then
        WireLib.TriggerOutput( self, "IsAttached", self:GetIsAttached() and 1 or 0 )
    end
end

--- Override this base class function.
function ENT:OnSocketConnect( socket, otherVehicle )
    if not socket.isReceptacle then
        self.attachedVehicle = otherVehicle
        self:EmitSound( self.AttachSound, 80, self.AttachSoundPitch, 1.0 )
    end

    self:SetIsAttached( true )
    self:UpdateWiremodOutputs()
end

--- Override this base class function.
function ENT:OnSocketDisconnect( socket )
    if not socket.isReceptacle then
        self.attachedVehicle = nil
        self:EmitSound( self.DetachSound, 80, self.DetachSoundPitch, 0.9 )
    end

    self:SetIsAttached( false )
    self:UpdateWiremodOutputs()
end

--- Override this base class function.
function ENT:OnPostThink( _dt, selfTbl )
    local attachedVehicle = selfTbl.attachedVehicle

    if not IsValid( attachedVehicle ) then
        self:SetBrakeValue( 0 )
        self:SetHeadlightState( 0 )
        self:SetTurnSignalState( 0 )
        self:SetIsVehicleReversing( false )

        return
    end

    -- Copy lights from the attached vehicle
    self:SetBrakeValue( attachedVehicle:GetBrakeValue() )
    self:SetHeadlightState( attachedVehicle:GetHeadlightState() )
    self:SetTurnSignalState( attachedVehicle:GetTurnSignalState() )
    self:SetIsVehicleReversing( attachedVehicle:IsReversing() )
end

function ENT:AttachToVehicle( vehicle )
    if not IsValid( vehicle ) then return end

    constraint.Weld( self, vehicle, 0, 0, 0, true )
    constraint.NoCollide( self, vehicle, 0, 0 )
    self.listAttachedVehicle = self.listAttachedVehicle or {}
    self.listAttachedVehicle[vehicle] = true

    vehicle:TurnOff()
    vehicle:EnableEngine( false )
    vehicle:SetIsAttachedToTrailer( true )
    vehicle:CallOnRemove( "Glide_TrailerDetach_" .. tostring( self:EntIndex() ), function()
        if IsValid( self ) then
            self:DetachFromVehicle( vehicle )
        end
    end )
end

function ENT:DetachFromVehicle( vehicle )
    if not IsValid( vehicle ) then return end

    constraint.RemoveConstraints( vehicle, "Weld" )
    constraint.RemoveConstraints( vehicle, "NoCollide" )
    if self.listAttachedVehicle then
        self.listAttachedVehicle[vehicle] = nil
    end

    vehicle.AttachedTrailer = nil
    vehicle:TurnOff()
    vehicle:EnableEngine( true )
    vehicle:RemoveCallOnRemove( "Glide_TrailerDetach_" .. tostring( self:EntIndex() ) )
    vehicle:SetIsAttachedToTrailer( false )
end

function ENT:GetAttachedVehicles()
    return self.listAttachedVehicle or {}
end

function ENT:OnRemove()
    for vehicle, _ in pairs( self:GetAttachedVehicles() ) do
        self:DetachFromVehicle( vehicle )
    end
end