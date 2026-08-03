--[[
    A vehicle with nobody in it, standing still, does not need to think at the tick rate.

    ENT:Think returns true unconditionally, so it runs every tick for the lifetime of the
    entity. That is right for a vehicle someone is driving, and wasted for one parked with the
    engine off -- buoyancy sampling, light bodygroups, wheel networking and steering all run
    anyway. On a city map the parked ones outnumber the moving ones by a wide margin.

    Nothing physical is disabled here. The vehicle keeps its suspension, its collision and its
    mass, so it still reacts to a shove, a blast or an impact in the same tick as before; only
    Think work is deferred, by at most PARK_THINK_INTERVAL.

    That is also why polling the wake condition is enough. An earlier version that disabled the
    wheels did need a zero-latency wake -- and dropped every vehicle onto its chassis, since a
    Glide vehicle hangs from its wheel raycasts rather than resting on its collision hull.
]]

-- Speed below which a vehicle counts as standing still. What remains at rest is suspension
-- noise, measured between 0 and 1.2 u/s on settled vehicles.
local PARK_SPEED = 3

-- How long it must stand still first, so that a vehicle rolling to a halt or rebounding does
-- not park on its first quiet moment.
local PARK_DELAY = 3

-- Think interval once parked. This bounds only how long a driver sitting down, or a vehicle
-- being pushed, goes unnoticed -- not any physical reaction.
local PARK_THINK_INTERVAL = 0.25

local IsValid = IsValid

--- Leave the parked state and return to the normal think rate.
function ENT:GlideUnpark( selfTbl )
    selfTbl = selfTbl or self:GetTable()

    if not selfTbl.isParked then return end

    selfTbl.isParked = false
    selfTbl.parkStillSince = nil
end

--- Decide whether the vehicle should park, and drive the think rate.
---
--- Called at the end of ENT:Think. Returns the interval to pass to NextThink, or nil for the
--- normal rate.
function ENT:GlideParkingThink( time, selfTbl )
    local driverSeat = selfTbl.seats[1]
    local hasDriver = IsValid( driverSeat ) and IsValid( driverSeat:GetDriver() )
    local moving = selfTbl.totalSpeed > PARK_SPEED

    if hasDriver or moving then
        self:GlideUnpark( selfTbl )

        return nil
    end

    if selfTbl.isParked then return PARK_THINK_INTERVAL end

    local stillSince = selfTbl.parkStillSince

    if not stillSince then
        selfTbl.parkStillSince = time

        return nil
    end

    if time - stillSince < PARK_DELAY then return nil end

    selfTbl.isParked = true

    return PARK_THINK_INTERVAL
end
