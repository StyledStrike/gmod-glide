include( "shared.lua" )

ENT.RenderGroup = RENDERGROUP_OPAQUE
ENT.AutomaticFrameAdvance = true

function ENT:Initialize()
    self.sounds = {}

    -- Create a RangedFeature to handle engine sounds
    self.engineSounds = Glide.CreateRangedFeature( self, self.MaxSoundDistance )
    self.engineSounds:SetTestCallback( "ShouldActivateSounds" )
    self.engineSounds:SetActivateCallback( "OnActivateSounds" )
    self.engineSounds:SetDeactivateCallback( "DeactivateSounds" )
    self.engineSounds:SetUpdateCallback( "OnUpdateSounds" )

    -- Create a RangedFeature to handle misc. features, such as particles and animations
    self.miscFeatures = Glide.CreateRangedFeature( self, self.MaxMiscDistance )
    self.miscFeatures:SetActivateCallback( "ActivateMisc" )
    self.miscFeatures:SetDeactivateCallback( "DeactivateMisc" )
    self.miscFeatures:SetUpdateCallback( "UpdateMisc" )

    self:OnPostInitialize()
end

function ENT:OnRemove( fullUpdate )
    if self.lockOnSound then
        self.lockOnSound:Stop()
        self.lockOnSound = nil
    end

    if fullUpdate then return end

    if self.engineSounds then
        self.engineSounds:Destroy()
        self.engineSounds = nil
    end

    if self.miscFeatures then
        self.miscFeatures:Destroy()
        self.miscFeatures = nil
    end
end

function ENT:OnEngineStateChange( _, _, state )
    if state > 0 then
        self:OnTurnOn()
    else
        self:OnTurnOff()
    end
end

--- Create a new looping sound and store it on the slot `id`.
function ENT:CreateLoopingSound( id, path, level, parent )
    local snd = self.sounds[id]

    if not snd then
        snd = CreateSound( parent or self, path )
        snd:SetSoundLevel( level )
        self.sounds[id] = snd
    end

    return snd
end

function ENT:DeactivateSounds()
    -- Remove all sounds we've created so far
    local sounds = self.sounds

    for k, snd in pairs( sounds ) do
        snd:Stop()
        sounds[k] = nil
    end

    -- Let children classes cleanup their own sounds
    self:OnDeactivateSounds()
end

function ENT:ActivateMisc()
    -- Find and store the wheel and seat entities we have
    local wheels = {}
    local seats = {}

    for _, ent in ipairs( self:GetChildren() ) do
        if ent:GetClass() == "glide_wheel" then
            wheels[#wheels + 1] = ent

        elseif ent:IsVehicle() then
            seats[#seats + 1] = ent
        end
    end

    self.wheels = wheels
    self.seats = seats
    self.lastNick = {}
    self.particleCD = 0

    -- Let children classes create their own stuff
    self:OnActivateMisc()
end

function ENT:DeactivateMisc()
    if self.wheels then
        for _, w in ipairs( self.wheels ) do
            if IsValid( w ) then
                w:CleanupSounds()
            end
        end
    end

    if self.engineFireSound then
        self.engineFireSound:Stop()
        self.engineFireSound = nil
    end

    self.wheels = nil
    self.seats = nil
    self.lastNick = nil

    -- Let children classes cleanup their own stuff
    self:OnDeactivateMisc()
end

local Effect = util.Effect
local DEFAULT_FLAME_ANGLE = Angle()

function ENT:UpdateMisc( distanceFraction )
    local t = RealTime()

    -- Keep particles consistent even at high FPS
    if t > self.particleCD and self:WaterLevel() < 3 then
        self.particleCD = t + 0.03
        self:OnUpdateParticles()

        if self:GetIsEngineOnFire() then
            local velocity = self:GetVelocity()
            local eff = EffectData()

            for _, v in ipairs( self.EngineFireOffsets ) do
                eff:SetStart( velocity )
                eff:SetOrigin( self:LocalToWorld( v.offset ) )
                eff:SetAngles( self:LocalToWorldAngles( v.angle or DEFAULT_FLAME_ANGLE ) )
                eff:SetScale( v.scale or 1 )
                Effect( "glide_fire", eff, true, true )
            end
        end
    end

    -- Engine fire sound
    if self:GetIsEngineOnFire() then
        if not self.engineFireSound then
            self.engineFireSound = CreateSound( self, "glide/fire/fire_loop_1.wav" )
            self.engineFireSound:SetSoundLevel( 80 )
            self.engineFireSound:PlayEx( 0.9, 100 )
        end

    elseif self.engineFireSound then
        self.engineFireSound:Stop()
        self.engineFireSound = nil
    end

    -- Let children classes do their own stuff
    self:OnUpdateMisc( distanceFraction )
end

local IsValid = IsValid
local TraceLine = util.TraceLine

local ZERO_VEC = Vector()
local ZERO_ANG = Angle()

local traceData = {
    filter = {
        [1] = NULL,
        [2] = "glide_missile"
    }
}

function ENT:Think()
    -- Run again next frame
    self:SetNextClientThink( CurTime() )

    if self.engineSounds then
        self.engineSounds:Think()
    end

    if self.miscFeatures then
        self.miscFeatures:Think()
    end

    -- Update the crosshair position
    if self.crosshairAutoUpdate then
        local target = self:GetLockOnTarget()

        if IsValid( target ) then
            self.crosshairPos = target:GetPos()
        else
            -- Use this weapon's position and angle offset, if set
            local info = self.WeaponInfo[self:GetWeaponIndex()]
            local pos = self:LocalToWorld( info.crosshairOrigin or ZERO_VEC )
            local ang = self:LocalToWorldAngles( info.crosshairAngle or ZERO_ANG )

            traceData.start = pos
            traceData.endpos = pos + ang:Forward() * 10000
            traceData.filter[1] = self

            self.crosshairPos = TraceLine( traceData ).HitPos
        end
    end

    return true
end

local RealTime = RealTime
local LocalPlayer = LocalPlayer

function ENT:OnWeaponIndexChange( _, _, index )
    if self:GetDriver() == LocalPlayer() then
        -- Show the weapon switch notification
        self.weaponNotifyTimer = RealTime() + 1.5

        -- Change the crosshair
        local weapon = self.WeaponInfo[index]
        if weapon then
            self:SetupCrosshair( weapon.crosshairType )
            self:SetCrosshairAutoUpdate( true )
        end

        EmitSound( "glide/ui/hud_switch.wav", Vector(), -2, nil, 1.0, nil, nil, 100 )
    end

    self:OnSwitchWeapon( index )
end

function ENT:OnDriverChange( _, _, driver )
    self:RemoveCrosshair()

    if driver == LocalPlayer() then
        local weapon = self.WeaponInfo[self:GetWeaponIndex()]
        if weapon then
            self:SetupCrosshair( weapon.crosshairType )
            self:SetCrosshairAutoUpdate( true )
        end
    end

    if self.lockOnSound then
        self.lockOnSound:Stop()
        self.lockOnSound = nil
    end
end

do
    local DrawWeaponCrosshair = Glide.DrawWeaponCrosshair
    local DrawWeaponSelection = Glide.DrawWeaponSelection

    function ENT:DrawVehicleHUD()
        self:DrawHUDSeats()

        -- TODO: glide.hud.health=Health

        if self.crosshairPos then
            DrawWeaponCrosshair( self.crosshairPos, self.crosshairIcon, self.crosshairSize, self.crosshairColor )
        end

        if self.weaponNotifyTimer then
            local info = self.WeaponInfo[self:GetWeaponIndex()] or {}

            DrawWeaponSelection( info.name or "MISSING", info.icon or "glide/aim_dot.png" )

            if RealTime() > self.weaponNotifyTimer then
                self.weaponNotifyTimer = nil
            end
        end
    end
end

do
    local FrameTime = FrameTime
    local LocalPlayer = LocalPlayer

    local ScrH = ScrH
    local Floor = math.floor
    local ExpDecay = Glide.ExpDecay

    local RoundedBoxEx = draw.RoundedBoxEx
    local DrawSimpleText = draw.SimpleText

    local COLORS = {
        bg = Color( 20, 20, 20, 255 ),
        seat = Color( 255, 255, 255 ),
        nick = Color( 240, 240, 240 ),
        accent = Glide.THEME_COLOR
    }

    local expanded = 0
    local expandTimer = 0

    function ENT:DrawHUDSeats()
        local seats = self.seats
        if not seats then return end

        local t = RealTime()
        local localPly = LocalPlayer()

        expanded = ExpDecay( expanded, t > expandTimer and 0 or 1, 6, FrameTime() )

        COLORS.nick.a = 255 * ( expanded - 0.5 ) * 2
        COLORS.bg.a = 210 + 30 * expanded
        COLORS.accent.a = 180 + 40 * expanded

        local scrH = ScrH()
        local margin = Floor( scrH * 0.03 )
        local padding = Floor( scrH * 0.006 )
        local spacing = Floor( scrH * 0.004 )

        local w, h = Floor( scrH * 0.3 ), Floor( scrH * 0.035 )
        local nickOffset = w - padding
        local cornerRadius = Floor( h * 0.15 )

        w = ( w * 0.15 ) + ( w * 0.85 * expanded )

        local y = scrH - margin - h

        local lastNick = self.lastNick
        local count = #seats
        local driver, nick

        for i = 1, count do
            driver = IsValid( seats[i] ) and seats[i]:GetDriver()
            nick = IsValid( driver ) and driver:Nick() or "#glide.hud.empty"

            if lastNick[i] ~= nick then
                lastNick[i] = nick
                expandTimer = t + 4
            end

            if nick:len() > 25 then
                nick = nick:sub( 1, 22 ) .. "..."
            end

            RoundedBoxEx( cornerRadius, 0, y, w, h, COLORS.bg, false, true, false, true )

            if driver == localPly then
                RoundedBoxEx( cornerRadius, 1, y + 1, w - 2, h - 2, COLORS.accent, false, true, false, true )
            end

            DrawSimpleText( "#" .. ( count - i + 1 ), "GlideHUD", padding, y + h * 0.5, COLORS.seat, 0, 1 )

            if expanded > 0.5 then
                DrawSimpleText( nick, "GlideHUD", nickOffset * expanded, y + h * 0.5, COLORS.nick, 2, 1 )
            end

            y = y - h - spacing
        end
    end
end

local CROSSHAIR_ICONS = {
    ["dot"] = "glide/aim_dot.png",
    ["square"] = "glide/aim_square.png"
}

local LOCKON_STATE_COLORS = {
    [0] = Color( 255, 255, 255 ),
    [1] = Color( 100, 255, 100 ),
    [2] = Color( 255, 0, 0 ),
}

--- Should this entity update the crosshair position automatically?
function ENT:SetCrosshairAutoUpdate( enable )
    self.crosshairAutoUpdate = enable
end

function ENT:SetupCrosshair( iconType, size, color )
    self.crosshairPos = Vector()
    self.crosshairIcon = CROSSHAIR_ICONS[iconType or "dot"]
    self.crosshairSize = size or 0.05
    self.crosshairColor = color or LOCKON_STATE_COLORS[0]
end

function ENT:RemoveCrosshair()
    self.crosshairPos = nil
    self.crosshairAutoUpdate = false
end

function ENT:OnLockOnStateChange( _, _, state )
    if self:GetDriver() ~= LocalPlayer() then return end

    self.crosshairColor = LOCKON_STATE_COLORS[state]

    if self.lockOnSound then
        self.lockOnSound:Stop()
        self.lockOnSound = nil
    end

    if state > 0 then
        self.lockOnSound = CreateSound( self, state == 1 and "glide/weapons/lockstart.wav" or "glide/weapons/locktone.wav" )
        self.lockOnSound:SetSoundLevel( 90 )
        self.lockOnSound:PlayEx( 1.0, 98 )
    end
end
