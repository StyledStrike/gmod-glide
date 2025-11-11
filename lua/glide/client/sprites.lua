local lights = {}
local lightCount = 0

function Glide.DrawLight( pos, color, size, brightness )
    lightCount = lightCount + 1
    lights[lightCount] = { pos, color.r, color.g, color.b, size or 70, brightness or 5 }
end

local CurTime = CurTime
local DynamicLight = DynamicLight

hook.Add( "Think", "Glide.DrawLights", function()
    if lightCount < 1 then return end

    local t = CurTime()
    local data, light

    for i = 1, lightCount do
        data = lights[i]
        light = DynamicLight( i )

        if light then
            light.pos = data[1]
            light.r = data[2]
            light.g = data[3]
            light.b = data[4]
            light.dietime = t + 0.25
            light.decay = 5000
            light.size = data[5]
            light.brightness = data[6]
        end
    end

    lightCount = 0
end )

local sprites = {}
local spriteCount = 0

function Glide.DrawLightSprite( pos, dir, size, color, material )
    spriteCount = spriteCount + 1
    sprites[spriteCount] = { pos, size, dir, material, color.r, color.g, color.b, color.a }
end

local Max = math.max
local Clamp = math.Clamp

local SetMaterial = render.SetMaterial
local DrawSprite = render.DrawSprite
local DepthRange = render.DepthRange

local GetLocalViewLocation = Glide.GetLocalViewLocation
local DEFAULT_MAT = Material( "glide/effects/light_glow" )
local spriteColor = Color( 255, 255, 255 )

hook.Add( "PreDrawEffects", "Glide.DrawSprites", function()
    if spriteCount < 1 then return end

    local pos, ang = GetLocalViewLocation()
    local dir = -ang:Forward()
    local s, dot

    for i = 1, spriteCount do
        s = sprites[i]

        -- Make so the sprite draws over things that are right on top of it,
        -- but does not draw over walls when viewed from far away.
        -- Due to the exponential nature of a depth buffer,
        -- this requires some really small numbers, and it's not ideal.
        DepthRange( 0.0, Clamp( pos:DistToSqr( s[1] ) / 200000, 0.999, 1 ) )

        -- Make the sprite smaller as the viewer points away from it
        dot = s[3] and dir:Dot( s[3] ) or 1
        dot = ( dot - 0.5 ) * 2
        s[2] = s[2] * Max( 0, dot )

        spriteColor.r = s[5]
        spriteColor.g = s[6]
        spriteColor.b = s[7]
        spriteColor.a = s[8]

        SetMaterial( s[4] or DEFAULT_MAT )
        DrawSprite( s[1], s[2], s[2], spriteColor )

        sprites[i] = nil
    end

    spriteCount = 0
    DepthRange( 0.0, 1.0 )
end )
