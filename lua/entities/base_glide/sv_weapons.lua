--- Reset the lock-on state
function ENT:ClearLockOnTarget()
    self:SetLockOnTarget( NULL )
    self:SetLockOnState( 0 )
end

function ENT:WeaponInit()
    self.weapons = {}
    self.weaponCount = #self.WeaponSlots
    self.turretCount = 0

    self.lockOnThinkCD = 0
    self.lockOnStateCD = 0

    if self.weaponCount == 0 then return end

    for i, data in ipairs( self.WeaponSlots ) do
        local weapon = {
            ammo = data.maxAmmo or 0,
            nextFire = 0,
            nextReload = 0
        }

        -- This value can be any string/number. All this does when set is,
        -- when switching to this weapon, it copies the ammo and cooldown
        -- timings from the previous weapon if it has the same ammo type.
        weapon.ammoType = data.ammoType

        -- Set to 0 for unlimited clip ammo
        weapon.maxAmmo = data.maxAmmo or 0

        -- How often can this weapon fire?
        weapon.fireRate = data.fireRate or 0.5

        -- How long does it take to reload?
        weapon.replenishDelay = data.replenishDelay or 1

        -- Enable the lock-on system while using this weapon
        weapon.lockOn = data.lockOn or false

        self.weapons[i] = weapon
    end
end

--- Returns the total count of weapons on this vehicle.
--- This includes both weapons from `ENT.WeaponSlots`
--- and turrets parented to this vehicle.
function ENT:GetWeaponCount()
    return self.weaponCount + self.turretCount
end

local PacificMode = GetConVar( "glide_pacific_mode" )

--- Switch the current active weapon.
function ENT:SelectWeaponIndex( index )
    if self.weaponCount == 0 or PacificMode:GetBool() then return end

    -- Wrap the index around if outside limits
    if index > self.weaponCount then
        index = 1

    elseif index < 1 then
        index = self.weaponCount
    end

    local weapon = self.weapons[index]
    if not weapon then return end

    -- Trigger the "stop fire" event from the current weapon
    local lastWeaponIndex = self:GetWeaponIndex()
    local lastWeapon = self.weapons[lastWeaponIndex]

    if lastWeapon and lastWeapon.isFiring then
        self:OnWeaponStop( lastWeapon, lastWeaponIndex )
    end

    -- Share the ammo count, reload and fire cooldowns
    -- between all other weapons with the same ammo type
    for i, otherWeapon in ipairs( self.weapons ) do
        if i ~= lastWeaponIndex and lastWeapon.ammoType == otherWeapon.ammoType then
            otherWeapon.ammo = lastWeapon.ammo
            otherWeapon.nextFire = lastWeapon.nextFire
            otherWeapon.nextReload = lastWeapon.nextReload
        end
    end

    -- Set active weapon
    self:SetWeaponIndex( index )
    self:OnSwitchWeapon( index )
    self:ClearLockOnTarget()
end

local IsValid = IsValid

--- Utility function to create a missile.
function ENT:FireMissile( pos, ang, attacker, target )
    Glide.PlaySoundSet( "Glide.MissileLaunch", self, 1.0 )

    local missile = Glide.FireMissile( pos, ang, attacker, self, target )

    if IsValid( missile ) then
        local phys = missile:GetPhysicsObject()

        if IsValid( phys ) then
            phys:SetVelocityInstantaneous( self:GetVelocity() )
        end
    end

    return missile
end

local FireBullet = Glide.FireBullet

--- Utility function to fire a bullet.
function ENT:FireBullet( params )
    params = params or {}
    params.inflictor = self

    if not IsValid( params.attacker ) then
        params.attacker = self:GetCreator()
    end

    if not params.shellDirection then
        params.shellDirection = params.pos - self:GetPos()
        params.shellDirection:Normalize()
    end

    FireBullet( params, self.selfTraceFilter )
end

local CanLockOnEntity = Glide.CanLockOnEntity
local FindLockOnTarget = Glide.FindLockOnTarget

function ENT:WeaponThink()
    local weaponIndex = self:GetWeaponIndex()
    local weapon = self.weapons[weaponIndex]
    if not weapon then return end

    local t = CurTime()

    -- Reload if it is the time to do so
    if weapon.ammo < 1 and t > weapon.nextReload then
        weapon.ammo = weapon.maxAmmo
    end

    local isFiring = not PacificMode:GetBool() and self:GetInputBool( 1, "attack" )

    if isFiring and t > weapon.nextFire and ( weapon.ammo > 0 or weapon.maxAmmo == 0 ) then
        weapon.ammo = weapon.ammo - 1
        weapon.nextFire = t + weapon.fireRate

        self:OnWeaponFire( weapon, weaponIndex )

        if weapon.ammo < 1 and weapon.maxAmmo > 0 then
            weapon.nextReload = t + weapon.replenishDelay
        end
    end

    -- Trigger `OnWeaponStop` once the weapon runs out of ammo or
    -- the driver is no longer pressing the attack button
    isFiring = isFiring and ( weapon.maxAmmo == 0 or weapon.ammo > 0 )

    if weapon.isFiring ~= isFiring then
        weapon.isFiring = isFiring

        if isFiring then
            self:OnWeaponStart( weapon, weaponIndex )
        else
            self:OnWeaponStop( weapon, weaponIndex )
        end
    end

    -- Lock-on targets
    if not weapon.lockOn or t < self.lockOnThinkCD then return end

    self.lockOnThinkCD = t + 0.2

    local driver = self:GetSeatDriver( 1 )
    if not IsValid( driver ) then return end

    local target = self:GetLockOnTarget()
    local myPos = self:GetPos()
    local myDir = self:GetForward()

    if IsValid( target ) then
        local targetPos = target:GetPos()
        local targetDir = targetPos - myPos
        targetDir:Normalize()

        if t > self.lockOnStateCD then
            self:SetLockOnState( 2 ) -- Hard lock
        end

        -- Stick to the same target for as long as possible
        if CanLockOnEntity( target, myPos, myDir, self.LockOnThreshold, self.LockOnMaxDistance, driver, true, self.selfTraceFilter ) then
            return
        end
    end

    -- Find a new target
    target = FindLockOnTarget( myPos, myDir, self.LockOnThreshold, self.LockOnMaxDistance, driver, self.selfTraceFilter, self.seats )

    if target ~= self:GetLockOnTarget() then
        self:SetLockOnTarget( target )

        if IsValid( target ) then
            self:SetLockOnState( 1 ) -- Soft lock
            self.lockOnStateCD = t + 0.4

            if target.IsGlideVehicle then
                -- If the target is a Glide vehicle, notify the passengers
                Glide.SendLockOnDanger( target:GetAllPlayers() )

            elseif target.GetDriver then
                -- If the target is another type of vehicle, notify the driver
                local ply = target:GetDriver()

                if IsValid( ply ) then
                    Glide.SendLockOnDanger( ply )
                end
            end
        else
            self:SetLockOnState( 0 )
            self.lockOnStateCD = 0
        end
    end
end
