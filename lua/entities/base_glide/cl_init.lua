include( "shared.lua" )

ENT.RenderGroup = RENDERGROUP_OPAQUE
ENT.AutomaticFrameAdvance = true

function ENT:Initialize()
    self.sounds = {}
    self.isLocalPlayerInFirstPerson = false

    self.crosshair = {
        enabled = false
    }

    -- Create a RangedFeature to handle engine sounds
    self.rfSounds = Glide.CreateRangedFeature( self, self.MaxSoundDistance )
    self.rfSounds:SetTestCallback( "ShouldActivateSounds" )
    self.rfSounds:SetActivateCallback( "OnActivateSounds" )
    self.rfSounds:SetDeactivateCallback( "DeactivateSounds" )
    self.rfSounds:SetUpdateCallback( "OnUpdateSounds" )

    -- Create a RangedFeature to handle misc. features, such as particles and animations
    self.rfMisc = Glide.CreateRangedFeature( self, self.MaxMiscDistance )
    self.rfMisc:SetActivateCallback( "ActivateMisc" )
    self.rfMisc:SetDeactivateCallback( "DeactivateMisc" )
    self.rfMisc:SetUpdateCallback( "UpdateMisc" )

    self:OnPostInitialize()
end

function ENT:OnRemove( fullUpdate )
    if self.lockOnSound then
        self.lockOnSound:Stop()
        self.lockOnSound = nil
    end

    if fullUpdate then return end

    if self.rfSounds then
        self.rfSounds:Destroy()
        self.rfSounds = nil
    end

    if self.rfMisc then
        self.rfMisc:Destroy()
        self.rfMisc = nil
    end
end

function ENT:OnEngineStateChange( _, _, state )
    if state > 0 then
        self:OnTurnOn()
    else
        self:OnTurnOff()
    end
end

local IsValid = IsValid

function ENT:GetWheelSpin( index )
    local wheel = self.wheels and self.wheels[index]

    if IsValid( wheel ) then
        return wheel:GetLastSpin()
    end

    return 0
end

function ENT:GetWheelOffset( index )
    local wheel = self.wheels and self.wheels[index]

    if IsValid( wheel ) then
        return wheel:GetLastOffset()
    end

    return 0
end

--- Create a new looping sound and store it on the slot `id`.
--- This sound will automatically be stopped when the
--- `rfSounds` RangedFeature is deactivated.
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

    self.wheels = table.Reverse( wheels )
    self.seats = table.Reverse( seats )
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

function ENT:UpdateMisc()
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
    self:OnUpdateMisc()
end

function ENT:Think()
    -- Run again next frame
    self:SetNextClientThink( CurTime() )

    if self.rfSounds then
        self.rfSounds:Think()
    end

    if self.rfMisc then
        self.rfMisc:Think()
    end

    if self.crosshair.enabled then
        self:UpdateCrosshairPosition()
    end

    return true
end

function ENT:OnLocalPlayerEnter( seatIndex )
    self:DisableCrosshair()

    if seatIndex > 1 then return end

    -- Setup the default crosshair
    local info = self.CrosshairInfo[self:GetWeaponIndex()]

    if info then
        self:EnableCrosshair( info )
    end
end

function ENT:OnLocalPlayerExit()
    self:DisableCrosshair()
end

local IsValid = IsValid

do
    local TraceLine = util.TraceLine
    local ZERO_VEC = Vector()
    local ZERO_ANG = Angle()

    local crosshairTraceData = {
        filter = { NULL, "glide_missile", "glide_projectile" }
    }

    function ENT:UpdateCrosshairPosition()
        local target = self:GetLockOnTarget()

        if IsValid( target ) then
            self.crosshair.origin = target:GetPos()
            return
        end

        -- Use this weapon's crosshair position and angle offset, if set
        local info = self.CrosshairInfo[self:GetWeaponIndex()]

        if info then
            local pos = self:LocalToWorld( info.traceOrigin or ZERO_VEC )
            local ang = self:LocalToWorldAngles( info.traceAngle or ZERO_ANG )

            crosshairTraceData.start = pos
            crosshairTraceData.endpos = pos + ang:Forward() * 10000
            crosshairTraceData.filter[1] = self

            self.crosshair.origin = TraceLine( crosshairTraceData ).HitPos
        end
    end
end

do
    local CROSSHAIR_ICONS = {
        ["dot"] = "glide/aim_dot.png",
        ["tank"] = "glide/aim_tank.png",
        ["square"] = "glide/aim_square.png"
    }

    local LOCKON_STATE_COLORS = {
        [0] = Color( 255, 255, 255 ),
        [1] = Color( 100, 255, 100 ),
        [2] = Color( 255, 0, 0 ),
    }

    function ENT:EnableCrosshair( params )
        params = params or {}

        local crosshair = self.crosshair

        crosshair.enabled = true
        crosshair.origin = Vector()
        crosshair.icon = CROSSHAIR_ICONS[params.iconType or "dot"]

        crosshair.size = params.size or 0.05
        crosshair.color = params.color or LOCKON_STATE_COLORS[0]
    end

    function ENT:DisableCrosshair()
        local crosshair = self.crosshair

        crosshair.enabled = false
        crosshair.origin = nil
        crosshair.icon = nil
        crosshair.size = nil
        crosshair.color = nil
    end

    function ENT:OnLockOnStateChange( _, _, state )
        if self:GetDriver() ~= LocalPlayer() then return end

        if self.crosshair.enabled then
            self.crosshair.color = LOCKON_STATE_COLORS[state]
        end

        if self.lockOnSound then
            self.lockOnSound:Stop()
            self.lockOnSound = nil
        end

        if state > 0 then
            self.lockOnSound = CreateSound( self, state == 1 and "glide/weapons/lockstart.mp3" or "glide/weapons/locktone.mp3" )
            self.lockOnSound:SetSoundLevel( 90 )
            self.lockOnSound:PlayEx( 1.0, 98 )
        end
    end
end

local RealTime = RealTime
local LocalPlayer = LocalPlayer

function ENT:OnWeaponIndexChange( _, _, index )
    local driver = self:GetDriver()

    if driver == LocalPlayer() then
        -- Show the weapon switch notification
        self.weaponNotifyTimer = RealTime() + 1.5
        EmitSound( "glide/ui/hud_switch.mp3", Vector(), -2, nil, 1.0, nil, nil, 100 )

        -- Change the crosshair
        local info = self.CrosshairInfo[index]

        if info then
            self:EnableCrosshair( info )
        end
    end

    self:OnSwitchWeapon( index )
end

function ENT:OnDriverChange( _, _, _ )
    if self.lockOnSound then
        self.lockOnSound:Stop()
        self.lockOnSound = nil
    end
end

do
    local Config = Glide.Config
    local DrawWeaponCrosshair = Glide.DrawWeaponCrosshair
    local DrawWeaponSelection = Glide.DrawWeaponSelection

    function ENT:DrawVehicleHUD( screenW, screenH )
        if Config.showPassengerList then
            self:DrawHUDSeats( screenW, screenH )
        end

        local crosshair = self.crosshair

        if crosshair.enabled then
            local data = crosshair.origin:ToScreen()
            if data.visible then
                DrawWeaponCrosshair( data.x, data.y, crosshair.icon, crosshair.size, crosshair.color )
            end
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

    function ENT:DrawHUDSeats( _screenW, screenH )
        local seats = self.seats
        if not seats then return end

        local t = RealTime()
        local localPly = LocalPlayer()

        expanded = ExpDecay( expanded, t > expandTimer and 0 or 1, 6, FrameTime() )

        COLORS.nick.a = 255 * ( expanded - 0.5 ) * 2
        COLORS.bg.a = 210 + 30 * expanded
        COLORS.accent.a = 180 + 40 * expanded

        local margin = Floor( screenH * 0.03 )
        local padding = Floor( screenH * 0.006 )
        local spacing = Floor( screenH * 0.004 )

        local w, h = Floor( screenH * 0.3 ), Floor( screenH * 0.035 )
        local nickOffset = w - padding
        local cornerRadius = Floor( h * 0.15 )

        w = ( w * 0.15 ) + ( w * 0.85 * expanded )

        local y = screenH - margin - h

        local lastNick = self.lastNick
        local count = #seats
        local driver, nick

        for i = count, 1, -1 do
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

            DrawSimpleText( "#" .. i, "GlideHUD", padding, y + h * 0.5, COLORS.seat, 0, 1 )

            if expanded > 0.5 then
                DrawSimpleText( nick, "GlideHUD", nickOffset * expanded, y + h * 0.5, COLORS.nick, 2, 1 )
            end

            y = y - h - spacing
        end
    end
end
