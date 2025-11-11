concommand.Add(
    "glide_sound_browser",
    function( _, _, args ) Glide.OpenSoundBrowser( args[1] ) end
)

function Glide.OpenSoundBrowser( onConfirmFile )
    local frame = Glide.frameSoundBrowser

    if IsValid( frame ) then
        frame:Close()
    end

    frame = vgui.Create( "Glide_SoundBrowser" )
    frame:Center()
    frame:MakePopup()
    frame.onConfirmCallback = onConfirmFile
    Glide.frameSoundBrowser = frame

    return frame
end

-- Credits to Wiremod sound browser for this snippet.
-- https://github.com/wiremod/wire/blob/7c7a69acf8588971eafbb3dea3fd288c6229e61b/lua/wire/client/sound_browser.lua#L33
local function NormalizeSoundFilePath( path )
    -- Return SoundScripts as-is
    if not string.match( path, "[%\\%/]" ) then
        return path
    end

    -- Normalize slashes
    path = string.gsub( path, "[%\\%/]+", "/" )

    -- Remove "special" flags used by some soundscripts
    if string.sub( path, 1, 6 ) == "sound/" then
        path = string.gsub( path, "^sound/%W*", "sound/" )
    end

    return string.Trim( path )
end

local function GetFileSource( path )
    path = NormalizeSoundFilePath( path )

    local games = engine.GetGames()

    for _, v in ipairs( games ) do
        if v.mounted and file.Exists( path, v.folder ) then
            return "mounted", v.title, v.folder
        end
    end

    local _, legacyAddons = file.Find( "garrysmod/addons/*", "BASE_PATH" )

    for _, folder in ipairs( legacyAddons ) do
        if file.Exists( "garrysmod/addons/" .. folder .. "/" .. path, "BASE_PATH" ) then
            return "legacy", "addons/" .. folder
        end
    end

    local addons = engine.GetAddons()

    for _, v in ipairs( addons ) do
        if v.mounted and file.Exists( path, v.title ) then
            return "addon", v.title
        end
    end

    if file.Exists( path, "DOWNLOAD" ) then
        return "download", "Download"
    end

    if file.Exists( path, "BSP" ) then
        return "map", game.GetMap()
    end

    if file.Exists( path, "GAME" ) then
        return "builtin", "Garry's Mod"
    end
end

local function OpenContextMenuForSound( path )
    if string.sub( path, 1, 6 ) == "sound/" then
        path = path:sub( 7 )
    end

    local menu = DermaMenu()

    menu:AddOption( "#glide.stream_editor.copy_clipboard", function()
        SetClipboardText( path )
    end ):SetImage( "icon16/page_paste.png" )

    menu:Open()
end

local ScaleSize = StyledTheme.ScaleSize
local L = StyledTheme.GetUpperLanguagePhrase

local PANEL = {}

function PANEL:Init()
    local frameW, frameH = ScaleSize( 1000 ), ScaleSize( 700 )

    self:SetTitle( "Sound Browser" )
    self:SetIcon( "icon16/sound.png" )
    self:SetSize( frameW, frameH )
    self:SetMinWidth( frameW )
    self:SetMinHeight( frameH )
    self:SetSizable( true )
    self:SetDraggable( true )
    self:SetDeleteOnClose( true )
    self:SetScreenLock( true )

    StyledTheme.Apply( self, "DFrame" )

    self.tabs = {}

    self.headerPanel = vgui.Create( "DPanel", self )
    self.headerPanel:SetTall( ScaleSize( 30 ) )
    self.headerPanel:SetPaintBackground( false )
    self.headerPanel:Dock( TOP )

    self.panelBody = vgui.Create( "DPanel", self )
    self.panelBody:SetPaintBackground( false )
    self.panelBody:Dock( FILL )

    self.panelBody.PerformLayout = function( s, w, h )
        for _, panel in ipairs( s:GetChildren() ) do
            panel:SetPos( 0, 0 )
            panel:SetSize( w, h )
        end
    end

    local panelFooter = vgui.Create( "DPanel", self )
    panelFooter:SetTall( ScaleSize( 40 ) )
    panelFooter:Dock( BOTTOM )
    panelFooter:DockMargin( 0, ScaleSize( 4 ), 0, 0 )
    panelFooter:DockPadding( ScaleSize( 4 ), ScaleSize( 4 ), ScaleSize( 4 ), ScaleSize( 4 ) )

    panelFooter.Paint = function( _, w, h )
        surface.SetDrawColor( 0, 0, 0, 255 )
        surface.DrawRect( 0, 0, w, h )
    end

    self.buttonSelect = vgui.Create( "DButton", panelFooter )
    self.buttonSelect:SetText( L"select" )
    self.buttonSelect:SizeToContentsX( ScaleSize( 60 ) )
    self.buttonSelect:SetEnabled( false )
    self.buttonSelect:Dock( RIGHT )

    StyledTheme.Apply( self.buttonSelect )

    self.buttonSelect.DoClick = function()
        self:OnConfirmSoundFile()
    end

    self.buttonTogglePreview = vgui.Create( "DImageButton", panelFooter )
    self.buttonTogglePreview:SetEnabled( false )
    self.buttonTogglePreview:SetWide( ScaleSize( 30 ) )
    self.buttonTogglePreview:Dock( RIGHT )
    self.buttonTogglePreview:DockMargin( 0, 0, ScaleSize( 2 ), 0 )

    self.buttonTogglePreview.PerformLayout = function( s, _, h )
        local margin = ScaleSize( s.m_bDepressImage and s.m_bImageDepressed and 16 or 14 )
        s.m_Image:SetSize( h - margin, h - margin )
        s.m_Image:Center()
    end

    StyledTheme.Apply( self.buttonTogglePreview, "DButton" )

    self.buttonTogglePreview.DoClick = function()
        self:SetIsPlayingPreview( self._previewSound == nil )
    end

    self.labelFileName = vgui.Create( "DLabel", panelFooter )
    self.labelFileName:SetContentAlignment( 4 )
    self.labelFileName:Dock( FILL )

    StyledTheme.Apply( self.labelFileName )
    self.labelFileName:SetFont( "StyledTheme_Tiny" )

    self.labelFileSource = vgui.Create( "DLabel", panelFooter )
    self.labelFileSource:SetContentAlignment( 4 )
    self.labelFileSource:SetWide( ScaleSize( 300 ) )
    self.labelFileSource:Dock( RIGHT )

    StyledTheme.Apply( self.labelFileSource )
    self.labelFileSource:SetFont( "StyledTheme_Tiny" )
    self.labelFileSource:SetColor( Color( 180, 180, 180 ) )

    self.iconFileSource = vgui.Create( "DImage", panelFooter )
    self.iconFileSource:SetWide( ScaleSize( 30 ) )
    self.iconFileSource:Dock( RIGHT )

    self.iconFileSource.Paint = function( s, w, h )
        local size = h * 0.5
        s:PaintAt( ( w * 0.5 ) - ( size * 0.5 ), ( h * 0.5 ) - ( size * 0.5 ), size, size )
    end

    self:SetSelectedFile( nil )
    self:SetIsPlayingPreview( false )

    -----

    local panelSoundFiles = self:AddTab( L"file", "icon16/folder.png" ).panel

    local browser = vgui.Create( "DFileBrowser", panelSoundFiles )
    browser:SetPath( "GAME" )
    browser:SetBaseFolder( "sound" )
    browser:SetCurrentFolder( "sound/" )
    browser:SetFileTypes( "*.wav *.mp3 *.ogg" )
    browser:SetOpen( true )
    browser:Dock( FILL )

    self.fileBrowser = browser

    browser.Divider:SetLeftWidth( ScaleSize( 200 ) )
    browser.Divider:SetDividerWidth( ScaleSize( 4 ) )

    browser.OnSelect = function( _, path, _ )
        self:SetSelectedFile( path )
        self:SetIsPlayingPreview( true )
    end

    browser.OnRightClick = function( _, path, _ )
        OpenContextMenuForSound( path )
    end

    -----

    local panelSoundScripts = self:AddTab( L"script", "icon16/table.png" ).panel

    local scriptsList = vgui.Create( "Glide_BigList", panelSoundScripts )
    scriptsList:SetItems( sound.GetTable() )
    scriptsList:Dock( FILL )

    scriptsList.DoClick = function( _, name, _ )
        self:SetSelectedFile( name )
        self:SetIsPlayingPreview( true )
    end

    scriptsList.DoRightClick = function( _, name, _ )
        OpenContextMenuForSound( name )
    end

    local scriptsFilter = vgui.Create( "DTextEntry", panelSoundScripts )
    scriptsFilter:SetPlaceholderText( L( "filter" ) .. "..." )
    scriptsFilter:Dock( TOP )

    StyledTheme.Apply( scriptsFilter )

    scriptsFilter.OnChange = function()
        scriptsList:SetItems( sound.GetTable(), string.Trim( scriptsFilter:GetValue() ) )
    end

    -----

    local panelGlideSoundScripts = self:AddTab( "Glide", "glide/icons/car.png" ).panel

    local sounds = {}
    local count = 0

    for id, _ in SortedPairs( Glide.soundSets ) do
        count = count + 1
        sounds[count] = id
    end

    local glideList = vgui.Create( "Glide_BigList", panelGlideSoundScripts )
    glideList:SetItems( sounds )
    glideList:Dock( FILL )

    glideList.DoClick = function( _, name, _ )
        self:SetSelectedFile( name )
        self:SetIsPlayingPreview( true )
    end

    glideList.DoRightClick = function( _, name, _ )
        OpenContextMenuForSound( name )
    end

    local glideFilter = vgui.Create( "DTextEntry", panelGlideSoundScripts )
    glideFilter:SetPlaceholderText( L( "filter" ) .. "..." )
    glideFilter:Dock( TOP )

    StyledTheme.Apply( glideFilter )

    glideFilter.OnChange = function()
        scriptsList:SetItems( sounds, string.Trim( glideFilter:GetValue() ) )
    end
end

function PANEL:OnRemove()
    self:StopPreviewSound()
end

function PANEL:OnConfirmSoundFile( path )
    self:Close()

    if path then
        path = self._previewSoundPath
    end

    if self.onConfirmCallback and self._previewSoundPath then
        self.onConfirmCallback( self._previewSoundPath )
    end
end

function PANEL:StopPreviewSound()
    if self._previewSound then
        self._previewSound:Stop()
        self._previewSound = nil
    end
end

local SOURCE_TYPE_ICONS = {
    ["mounted"] = "icon16/cd.png",
    ["legacy"] = "icon16/folder.png",
    ["addon"] = "icon16/brick.png",
    ["download"] = "icon16/page_world.png",
    ["map"] = "icon16/map.png",
    ["builtin"] = "games/16/garrysmod.png"
}

local function UpdateInfoFromSound( path, labelFileSource, iconFileSource )
    local sourceType, description, gameFolder = GetFileSource( "sound/" .. path )

    if gameFolder then
        local icon = "games/16/" .. gameFolder .. ".png"
        iconFileSource:SetImage( file.Exists( icon, "GAME" ) and icon or "games/16/all.png" )

    elseif sourceType and SOURCE_TYPE_ICONS[sourceType] then
        iconFileSource:SetImage( SOURCE_TYPE_ICONS[sourceType] )
    else
        iconFileSource:SetImage( "icon16/circlecross.png" )
    end

    labelFileSource:SetText( description or "-" )
end

function PANEL:SetCurrentPreviewSound( path )
    local isFilePath = false

    if path == "" then
        path = nil

    elseif path and string.sub( path, 1, 6 ) == "sound/" then
        isFilePath = true
        path = path:sub( 7 )
    end

    self._previewSoundPath = path
    self.buttonTogglePreview:SetEnabled( path ~= nil )
    self.buttonSelect:SetEnabled( self.onConfirmCallback ~= nil and path ~= nil )

    if path then
        local props = sound.GetProperties( path )

        self.labelFileName:SetText( path )

        if isFilePath then
            UpdateInfoFromSound( path, self.labelFileSource, self.iconFileSource )

        elseif Glide.soundSets[path] then
            path = Glide.soundSets[path].paths[1]
            UpdateInfoFromSound( path, self.labelFileSource, self.iconFileSource )

        elseif props then
            if type( props.sound ) == "string" then
                UpdateInfoFromSound( props.sound, self.labelFileSource, self.iconFileSource )

            elseif type( props.sound ) == "table" then
                UpdateInfoFromSound( props.sound[1], self.labelFileSource, self.iconFileSource )
            else
                self.labelFileSource:SetText( "-" )
                self.iconFileSource:SetImage( "icon16/cog.png" )
            end
        else
            self.labelFileSource:SetText( "-" )
            self.iconFileSource:SetImage( "icon16/cog.png" )
        end
    else
        self.labelFileName:SetText( "-" )
        self.labelFileSource:SetText( "-" )
        self.iconFileSource:SetImage( "icon16/cog.png" )
    end
end

local function CreatePreviewSound( path, pitch )
    local snd = CreateSound( LocalPlayer(), path )

    if snd then
        snd:PlayEx( 1.0, pitch )
    end

    return snd
end

function PANEL:SetIsPlayingPreview( isPlaying )
    self:StopPreviewSound()

    if not isPlaying or not self._previewSoundPath then
        self.buttonTogglePreview:SetIcon( "icon16/control_play_blue.png" )
        return
    end

    local path = NormalizeSoundFilePath( self._previewSoundPath )

    -- Convert Glide sound sets to a random file path, and apply it's properties
    local set = Glide.soundSets[path]

    if set then
        path = Glide.GetRandomSound( path )
        self._previewSound = CreatePreviewSound( path, math.Rand( set.minPitch, set.maxPitch ) )
    else
        self._previewSound = CreatePreviewSound( path, 100 )
    end

    if self._previewSound then
        self.buttonTogglePreview:SetIcon( "icon16/control_stop_blue.png" )
    end
end

function PANEL:SetSelectedFile( path )
    if type( path ) ~= "string" then
        path = nil
    end

    self:SetCurrentPreviewSound( path )
end

function PANEL:SetCurrentFolder( path )
    path = "sound/" .. path

    if string.Trim( path, "/" ) ~= self.fileBrowser:GetCurrentFolder() and file.IsDir( path, "GAME" ) then
        self.fileBrowser:SetCurrentFolder( path )
    end
end

function PANEL:SetFileTypes( fileTypes )
    self.fileBrowser:SetFileTypes( fileTypes )
end

local UpdateButtonColors = function( s )
    if s._tabIsSelected then
        s:SetTextStyleColor( Color( 100, 180, 255 ) )
    else
        s:SetTextStyleColor( Color( 150, 150, 150 ) )
    end
end

local OnClickTabButton = function( s )
    s._tabWindow:SetActiveByIndex( s._tabIndex )
end

function PANEL:AddTab( name, icon )
    local item = {}
    local index = #self.tabs + 1

    item.button = vgui.Create( "DButton", self.headerPanel )
    item.button:SetText( name )
    item.button:SetIcon( icon )

    StyledTheme.Apply( item.button )

    item.button:SizeToContentsX( ScaleSize( 16 ) )
    item.button:Dock( LEFT )
    item.button:DockMargin( 0, ScaleSize( 3 ), 0, 0 )
    item.button._tabIndex = index
    item.button._tabWindow = self
    item.button.DoClick = OnClickTabButton
    item.button.UpdateColours = UpdateButtonColors

    item.panel = vgui.Create( "DPanel", self.panelBody )
    item.panel:SetPaintBackground( false )
    item.panel:SetVisible( false )
    item.panel:DockMargin( 0, 0, 0, 0 )

    StyledTheme.Apply( item.panel )

    self.tabs[index] = item

    if index == 1 then
        self:SetActiveByIndex( 1 )
    end

    return item
end

function PANEL:SetActiveByIndex( index )
    for i, item in ipairs( self.tabs ) do
        item.panel:SetVisible( index == i )
        item.button._tabIsSelected = index == i
        item.button:DockMargin( 0, index == i and 0 or ScaleSize( 3 ), 0, 0 )
        item.button:ApplySchemeSettings()
    end

    self.headerPanel:InvalidateLayout()
end

function PANEL:SetTabIndexEnabled( index, enabled )
    local item = self.tabs[index]

    if item then
        item.button:SetEnabled( enabled )
    end
end

vgui.Register( "Glide_SoundBrowser", PANEL, "DFrame" )

--[[
    Simple list that can (theoretically) handle thousands of items.
]]

local BIGLIST = {}

function BIGLIST:Init()
    self:SetMouseInputEnabled( true )

    self.scrollBar = vgui.Create( "DVScrollBar", self )
    self.scrollBar:Dock( RIGHT )

    self.searchProgress = self:Add( "DProgress" )
    self.searchProgress:DockMargin( 0, 0, 0, 0 )
    self.searchProgress:SetTall( 20 )
    self.searchProgress:Dock( BOTTOM )
    self.searchProgress:SetVisible( false )

    self.items = {}
    self.itemCount = 0
    self.hoveredIndex = nil
    self.selectedIndex = nil

    self.view = {
        padding = ScaleSize( 4 ),
        fontName = "",
        itemHeight = 1,
        scrollY = 0
    }

    self:SetFont( "StyledTheme_Small" )
    self:SetItemHeight( ScaleSize( 22 ) )
end

function BIGLIST:SetFont( fontName )
    self.view.fontName = fontName
end

function BIGLIST:SetItemHeight( itemHeight )
    self.view.itemHeight = itemHeight
    self:InvalidateLayout()
end

local Find = string.find

function BIGLIST:SetItems( items, filter )
    if filter and filter ~= "" then
        filter = string.lower( filter )

        local filtered = {}
        local count = 0

        for i = 1, #items do
            if Find( string.lower( items[i] ), filter, 0, true ) then
                count = count + 1
                filtered[count] = items[i]
            end
        end

        items = filtered
    end

    self.items = items
    self.itemCount = #items
    self.view.scrollY = 0

    self:InvalidateLayout()
end

function BIGLIST:SetSelectedItemIndex( index )
    local item = self.items[index]
    if not item then
        self.selectedIndex = nil
        return
    end

    self.selectedIndex = index
    self:InvalidateLayout()
end

function BIGLIST:PerformLayout()
    local w, h = self:GetSize()
    local view = self.view

    self.scrollBar:SetPos( w - 16, 0 )
    self.scrollBar:SetSize( 16, h )
    self.scrollBar:SetUp( h, ( self.itemCount * self.view.itemHeight ) + ( view.padding * 2 ) )
end

local Floor = math.floor
local SetColor = surface.SetDrawColor
local SetTextPos = surface.SetTextPos
local DrawRect = surface.DrawRect
local DrawText = surface.DrawText

function BIGLIST:Paint( w, h )
    if self.scrollBar.Enabled then
        w = w - self.scrollBar:GetWide()
    end

    SetColor( 255, 255, 255, 255 )
    DrawRect( 0, 0, w, h )

    local view = self.view
    local itemH = view.itemHeight

    view.scrollY = Glide.ExpDecay( view.scrollY, math.abs( self.scrollBar:GetOffset() ), 20, FrameTime() )
    view.startIndex = 1 + Floor( view.scrollY / itemH )
    view.endIndex = math.Clamp( view.startIndex + Floor( h / itemH ) + 1, 0, self.itemCount )

    local hoveredIndex

    if vgui.GetHoveredPanel() == self then
        local _, y = self:ScreenToLocal( input.GetCursorPos() )
        hoveredIndex = 1 + Floor( ( y + view.scrollY - view.padding ) / itemH )
    end

    self.hoveredIndex = hoveredIndex

    surface.SetTextColor( 0, 0, 0, 255 )
    surface.SetFont( view.fontName )

    local _, textH = surface.GetTextSize( "A" )
    local textOffset = ( itemH * 0.5 ) - ( textH * 0.5 )

    local x, y = 0, view.padding - ( view.scrollY % itemH )
    local items = self.items
    local selectedIndex = self.selectedIndex

    for i = view.startIndex, view.endIndex do
        if i % 2 == 1 then
            SetColor( 0, 0, 0, 30 )
            DrawRect( x, y, w, itemH )
        end

        if i == selectedIndex then
            SetColor( 86, 135, 244, 255 )
            DrawRect( x, y, w, itemH )

        elseif i == hoveredIndex then
            SetColor( 208, 217, 250, 255 )
            DrawRect( x, y, w, itemH )
        end

        SetTextPos( x + view.padding, y + textOffset )
        DrawText( items[i] )

        y = y + itemH
    end
end

function BIGLIST:OnMouseWheeled( delta )
    return self.scrollBar:OnMouseWheeled( delta )
end

function BIGLIST:OnMousePressed( keyCode )
    if not self.hoveredIndex then return end

    local item = self.items[self.hoveredIndex]
    if not item then return end

    self:SetSelectedItemIndex( self.hoveredIndex )

    if keyCode == MOUSE_LEFT then
        self:DoClick( item, self.hoveredIndex )
    else
        self:DoRightClick( item, self.hoveredIndex )
    end
end

function BIGLIST:OnVScroll( _offset ) end
function BIGLIST:DoClick( _name, _index ) end
function BIGLIST:DoRightClick( _name, _index ) end

vgui.Register( "Glide_BigList", BIGLIST, "DPanel" )
