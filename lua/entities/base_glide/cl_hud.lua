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
            self.lockOnSound = CreateSound( self, state == 1 and "glide/weapons/lockstart.wav" or "glide/weapons/locktone.wav" )
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
        EmitSound( "glide/ui/hud_switch.wav", Vector(), -2, nil, 1.0, nil, nil, 100 )

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

local Config = Glide.Config
local PacificMode = GetConVar( "glide_pacific_mode" )
local DrawWeaponCrosshair = Glide.DrawWeaponCrosshair
local DrawWeaponSelection = Glide.DrawWeaponSelection

function ENT:DrawVehicleHUD( screenW, screenH )
    local playerListWidth = 0

    if Config.showPassengerList and hook.Run( "Glide_CanDrawHUDSeats", self ) ~= false then
        playerListWidth = self:DrawPlayerListHUD( screenW, screenH )
    end

    local crosshair = self.crosshair

    if crosshair.enabled and not PacificMode:GetBool() then
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

    return playerListWidth
end

local FrameTime = FrameTime
local LocalPlayer = LocalPlayer

local Floor = math.floor
local ExpDecay = Glide.ExpDecay

local SetColor = surface.SetDrawColor
local DrawRect = surface.DrawRect
local DrawSimpleText = draw.SimpleText

local colors = {
    bgAlpha = 255,
    seat = Color( 255, 255, 255 ),
    nick = Color( 240, 240, 240 ),
    accent = Glide.THEME_COLOR
}

local expanded = 0
local expandTimer = 0

function ENT:DrawPlayerListHUD( screenW, screenH )
    local seats = self.seats
    if not seats then return 0 end

    local t = RealTime()
    local localPly = LocalPlayer()

    expanded = ExpDecay( expanded, t > expandTimer and 0 or 1, 6, FrameTime() )

    colors.bgAlpha = 180 + 40 * expanded
    colors.nick.a = 255 * ( expanded - 0.5 ) * 2
    colors.accent.a = 150 + 40 * expanded

    local margin = Floor( screenH * 0.03 )
    local padding = Floor( screenH * 0.006 )
    local spacing = Floor( screenH * 0.004 )
    local w, h = screenH * 0.3, Floor( screenH * 0.03 )

    w = Floor( ( w * 0.15 ) + ( w * 0.85 * expanded ) )

    local x = screenW - w
    local y = screenH - margin - h

    local nickOffset = w - padding
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

        SetColor( 30, 30, 30, colors.bgAlpha )
        DrawRect( x, y, w, h )

        if driver == localPly then
            SetColor( colors.accent:Unpack() )
            DrawRect( x + 1, y + 1, w - 2, h - 2 )
        end

        DrawSimpleText( "#" .. i, "GlideHUD", x + padding, y + h * 0.5, colors.seat, 0, 1 )

        if expanded > 0.5 then
            DrawSimpleText( nick, "GlideHUD", x + nickOffset, y + h * 0.5, colors.nick, 2, 1 )
        end

        y = y - h - spacing
    end

    return w
end
