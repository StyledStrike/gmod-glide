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

local IsTable = istable
local IsString = isstring
local Find = string.find

local function DoesVehicleMatchSearch( data, className, searchString )
    if not IsTable( data ) then
        return false
    end

    local name = data.PrintName or data.Name

    if IsString( name ) and Find( name:lower(), searchString, nil, true ) then
        return true
    end

    if IsString( className ) and Find( className:lower(), searchString, nil, true ) then
        return true
    end

    return false
end

search.AddProvider( function( searchString )
    -- Get the search results limit.
    -- As the convar itself describes it, this value is not a "hard limit" on the
    -- total amount of results, instead it's used to limit different types of search results.
    -- "Model amount limited to 1/2 of this value, entities are limited to 1/4".
    -- We use the "entities" limit for Glide vehicles.
    local maxSearchResults = GetConVar( "sbox_search_maxresults" ):GetInt() / 4

    local results = {}
    local count = 0

    for className, data in pairs( list.Get( "GlideVehicles" ) ) do
        if count > maxSearchResults then
            break
        end

        if DoesVehicleMatchSearch( data, className, searchString ) then
            local niceName = data.PrintName or data.Name or className

            local contentIconData = {
                nicename = niceName,
                spawnname = className,
                material = "entities/" .. className .. ".png",
                admin = data.AdminOnly
            }

            count = count + 1
            results[count] = {
                text = className, -- Text to "Copy to clipboard"
                icon = spawnmenu.CreateContentIcon( "entity", nil, contentIconData ),
                words = { niceName, className }
            }
        end
    end

    table.SortByMember( results, "text", true )

    return results
end, "glide_vehicles_provider" )
