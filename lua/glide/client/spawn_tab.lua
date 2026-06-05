local function GetCategoryVehicles( category )
    local filtered = {}
    local i = 0

    for class, data in pairs( list.Get( "GlideVehicles" ) or {} ) do
        if data.Category == category then
            i = i + 1
            filtered[i] = {
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
