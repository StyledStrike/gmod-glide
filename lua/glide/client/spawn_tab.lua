local function GetCategoryVehicles( category )
    local filtered = {}

    for class, data in pairs( list.Get( "GlideVehicles" ) or {} ) do
        if data.Category == category then
            filtered[#filtered + 1] = {
                class = class,
                name = data.Name,
                icon = data.IconOverride or "entities/" .. class .. ".png",
                adminOnly = data.AdminOnly
            }
        end
    end

    return filtered
end

local function CreateCategory( parentNode, contentPanel, name, icon, category )
    local node = parentNode:AddNode( name, icon )

    node.DoPopulate = function( s )
        if s.itemsPanel then return end

        s.itemsPanel = vgui.Create( "ContentContainer", contentPanel )
        s.itemsPanel:SetVisible( false )
        s.itemsPanel:SetTriggerSpawnlistChange( false )

        local items = GetCategoryVehicles( category )

        for _, v in SortedPairsByMemberValue( items, "name" ) do
            spawnmenu.CreateContentIcon( "entity", s.itemsPanel, {
                nicename = v.name or v.class,
                spawnname = v.class,
                material = v.icon or icon or "icon16/car.png",
                admin = v.adminOnly
            } )
        end
    end

    node.DoClick = function( s )
        s:DoPopulate()
        contentPanel:SwitchPanel( s.itemsPanel )
    end

    return node
end

hook.Add( "PopulateVehicles", "Glide.PopulateVehicles", function( panel, tree )
    local categories = list.Get( "GlideCategories" )
    local node = CreateCategory( tree, panel, "Glide", "glide/icons/car.png", "Default" )

    for id, category in SortedPairs( categories ) do
        CreateCategory( node, panel, category.name, category.icon, id )
    end

    local nodeConfig = node:AddNode( "#glide.settings", "icon16/cog.png" )

    nodeConfig.DoClick = function()
        Glide.Config:OpenFrame()
    end
end )

-- Overwrite search Vehicles (https://github.com/Facepunch/garrysmod/blob/6d0b1b8937ae743147ddbb9744082dbdb1c35b17/garrysmod/gamemodes/sandbox/gamemode/cl_search_models.lua#L109-L168)
local sbox_search_maxresults = GetConVar( "sbox_search_maxresults" )
local isstring = isstring
local istable = istable
local function SearchVehicles( tResult, sType, sClass, tVehicle, sSearch )
    local sName = tVehicle.PrintName or tVehicle.Name
    if not isstring( sName ) and not isstring( sClass ) then return end

    if ( ( isstring( sName ) and sName:lower():find( sSearch, nil, true ) ) or ( isstring( sClass ) and sClass:lower():find( sSearch, nil, true ) ) ) then

        local sNiceName = sName or sClass
        local contentIconData = {
            nicename = sType == "entity" and ( "[Glide] %s" ):format( sNiceName ) or sNiceName,
            spawnname = sClass,
            material = "entities/" .. sClass .. ".png",
            admin = tVehicle.AdminOnly
        }

        table.insert( tResult, {
            text = sName or sClass,
            icon = spawnmenu.CreateContentIcon( sType, nil, contentIconData ),
            words = { tVehicle }
        } )
    end
end

search.AddProvider( function( str )
    local results = {}
    for sClass, tVehicle in pairs( list.Get( "Vehicles" ) ) do
        if not istable( tVehicle ) then continue end

        SearchVehicles( results, "vehicle", sClass, tVehicle, str )

        if ( #results >= sbox_search_maxresults:GetInt() / 4 ) then break end
    end

    for sClass, v in pairs( list.Get( "GlideVehicles" ) ) do
        if not istable( v ) then continue end

        SearchVehicles( results, "entity", sClass, v, str )

        if ( #results >= sbox_search_maxresults:GetInt() / 4 ) then break end
    end

    table.SortByMember( results, "text", true )
    return results
end, "vehicles" )
