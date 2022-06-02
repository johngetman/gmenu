
include( "background.lua" )
include( "cef_credits.lua" )
include( "openurl.lua" )
include( "ugcpublish.lua" )

pnlMainMenu = nil

local PANEL = {}

function PANEL:Init()
	self:Dock( FILL )
	self:SetKeyboardInputEnabled( true )
	self:SetMouseInputEnabled( true )

	self.Menu = self:Add("gmenu.ColumnSheet")
	self.Menu:Dock(FILL)

	for k, v in ipairs(gmenu.MenuTabs) do
		self.Menu:AddTab(v.icon, v.panel)
	end

	self.Menu:AddTab(Material("gmenu/terminal.png"), function()
		gui.ShowConsole()
	end)

	self.Menu:AddTab(Material("gmenu/settings.png"), function()
		RunGameUICommand("OpenOptionsDialog")
	end)

	self.Menu:AddTab(Material("gmenu/quit.png"), function()
		RunGameUICommand("Quit")
	end)

	self:MakePopup()
	self:SetPopupStayAtBack( true )

	if ( gui.IsConsoleVisible() ) then
		gui.ShowConsole()
	end
end

function PANEL:Notification(text, time)
	surface.SetFont("gmenu.18")
	local w = surface.GetTextSize(text)
	local width = w+20

	local panel = self:Add("DPanel")
	panel:SetSize(width, 28)
	panel:SetPos(-width-10, 10)
	panel:MoveTo(10, 10, 0.3, 0, -1)
	panel.Paint = function(self, w, h)
		draw.RoundedBox(gmenu_round, 0, 0, w, h, gmenu_prim)
		draw.SimpleText(text, "gmenu.18", w/2, h/2, gmenu_text, 1, 1)
	end
	
	timer.Simple(time or 2, function()
		if IsValid(panel) then
			panel:AlphaTo(0, 0.3, 0)
		end
	end)
end

function PANEL:ScreenshotScan( folder )

	local bReturn = false

	local Screenshots = file.Find( folder .. "*.*", "GAME" )
	for k, v in RandomPairs( Screenshots ) do

		AddBackgroundImage( folder .. v )
		bReturn = true

	end

	return bReturn

end

function PANEL:Paint()

	DrawBackground()

	if ( self.IsInGame != IsInGame() ) then

		self.IsInGame = IsInGame()

		if ( self.IsInGame ) then

			if ( IsValid( self.InnerPanel ) ) then self.InnerPanel:Remove() end
			self:Call( "SetInGame( true )" )

		else

			self:Call( "SetInGame( false )" )

		end
	end

	if ( !self.IsInGame ) then return end

	local canAdd = CanAddServerToFavorites()
	local isFav = serverlist.IsCurrentServerFavorite()
	if ( self.CanAddServerToFavorites != canAdd || self.IsCurrentServerFavorite != isFav ) then

		self.CanAddServerToFavorites = canAdd
		self.IsCurrentServerFavorite = isFav

		self:Call( "SetShowFavButton( " .. tostring( self.CanAddServerToFavorites ) ..", " .. tostring( self.IsCurrentServerFavorite ) .. " )" )

	end

end

function PANEL:RefreshContent()

	self:RefreshGamemodes()
	self:RefreshAddons()

end

function PANEL:RefreshGamemodes()

	local json = util.TableToJSON( engine.GetGamemodes() )

	self:Call( "UpdateGamemodes( " .. json .. " )" )
	self:UpdateBackgroundImages()
	self:Call( "UpdateCurrentGamemode( '" .. engine.ActiveGamemode():JavascriptSafe() .. "' )" )

end

function PANEL:RefreshAddons()

	-- TODO

end

function PANEL:UpdateBackgroundImages()

	ClearBackgroundImages()

	--
	-- If there's screenshots in gamemodes/<gamemode>/backgrounds/*.jpg use them
	--
	if ( !self:ScreenshotScan( "gamemodes/" .. engine.ActiveGamemode() .. "/backgrounds/" ) ) then

		--
		-- If there's no gamemode specific here we'll use the default backgrounds
		--
		self:ScreenshotScan( "backgrounds/" )

	end

	ChangeBackground( engine.ActiveGamemode() )

end

function PANEL:Call( js )
end

vgui.Register( "MainMenuPanel", PANEL, "EditablePanel" )

--
-- Called from JS when starting a new game
--
function UpdateServerSettings()

	local array = {
		hostname = GetConVarString( "hostname" ),
		sv_lan = GetConVarString( "sv_lan" ),
		p2p_enabled = GetConVarString( "p2p_enabled" )
	}

	local settings_file = file.Read( "gamemodes/" .. engine.ActiveGamemode() .. "/" .. engine.ActiveGamemode() .. ".txt", true )

	if ( settings_file ) then

		local Settings = util.KeyValuesToTable( settings_file )

		if ( istable( Settings.settings ) ) then

			array.settings = Settings.settings

			for k, v in pairs( array.settings ) do
				v.Value = GetConVarString( v.name )
				v.Singleplayer = v.singleplayer && true || false
			end

		end

	end

	local json = util.TableToJSON( array )
	pnlMainMenu:Call( "UpdateServerSettings(" .. json .. ")" )

end

--
-- Get the player list for this server
--
function GetPlayerList( serverip )

	serverlist.PlayerList( serverip, function( tbl )

		local json = util.TableToJSON( tbl )
		pnlMainMenu:Call( "SetPlayerList( '" .. serverip:JavascriptSafe() .. "', " .. json .. ")" )

	end )

end

local BlackList = {
	Addresses = {},
	Hostnames = {},
	Descripts = {},
	Gamemodes = {},
	Maps = {},
}

local NewsList = {}

GetAPIManifest( function( result )
	result = util.JSONToTable( result )
	if ( !result ) then return end

	NewsList = result.News and result.News.Blogs or {}
	LoadNewsList()

	for k, v in pairs( result.Servers and result.Servers.Banned or {} ) do
		if ( v:StartWith( "map:" ) ) then
			table.insert( BlackList.Maps, v:sub( 5 ) )
		elseif ( v:StartWith( "desc:" ) ) then
			table.insert( BlackList.Descripts, v:sub( 6 ) )
		elseif ( v:StartWith( "host:" ) ) then
			table.insert( BlackList.Hostnames, v:sub( 6 ) )
		elseif ( v:StartWith( "gm:" ) ) then
			table.insert( BlackList.Gamemodes, v:sub( 4 ) )
		else
			table.insert( BlackList.Addresses, v )
		end
	end
end )

function LoadNewsList()
	if ( !pnlMainMenu ) then return end

	local json = util.TableToJSON( NewsList )
	local bHide = cookie.GetString( "hide_newslist", "false" ) == "true"

	pnlMainMenu:Call( "UpdateNewsList(" .. json .. ", " .. tostring( bHide ) .. " )" )
end

function SaveHideNews( bHide )
	cookie.Set( "hide_newslist", tostring( bHide ) )
end

local function IsServerBlacklisted( address, hostname, description, gm, map )
	local addressNoPort = address:match( "[^:]*" )

	for k, v in ipairs( BlackList.Addresses ) do
		if ( address == v || addressNoPort == v ) then
			return v
		end

		if ( v:EndsWith( "*" ) && address:sub( 1, v:len() - 1 ) == v:sub( 1, v:len() - 1 ) ) then return v end
	end

	for k, v in ipairs( BlackList.Hostnames ) do
		if string.match( hostname, v ) || string.match( hostname:lower(), v ) then
			return v
		end
	end

	for k, v in ipairs( BlackList.Descripts ) do
		if string.match( description, v ) || string.match( description:lower(), v ) then
			return v
		end
	end

	for k, v in ipairs( BlackList.Gamemodes ) do
		if string.match( gm, v ) || string.match( gm:lower(), v ) then
			return v
		end
	end

	for k, v in ipairs( BlackList.Maps ) do
		if string.match( map, v ) || string.match( map:lower(), v ) then
			return v
		end
	end

	return nil
end

local Servers = {}
local ShouldStop = {}

function GetServers( category, id )

	category = string.JavascriptSafe( category )
	id = string.JavascriptSafe( id )

	ShouldStop[ category ] = false
	Servers[ category ] = {}

	local data = {
		Callback = function( ping, name, desc, map, players, maxplayers, botplayers, pass, lastplayed, address, gm, workshopid, isAnon, version, loc, gmcat )

			if ( Servers[ category ] && Servers[ category ][ address ] ) then print( "Server Browser Error!", address, category ) return end
			Servers[ category ][ address ] = true

			local blackListMatch = IsServerBlacklisted( address, name, desc, gm, map )
			if ( blackListMatch == nil ) then

				name = string.JavascriptSafe( name )
				desc = string.JavascriptSafe( desc )
				map = string.JavascriptSafe( map )
				address = string.JavascriptSafe( address )
				gm = string.JavascriptSafe( gm )
				workshopid = string.JavascriptSafe( workshopid )
				version = string.JavascriptSafe( tostring( version ) )
				loc = string.JavascriptSafe( loc )
				gmcat = string.JavascriptSafe( gmcat )

				pnlMainMenu:Call( string.format( 'AddServer( "%s", "%s", %i, "%s", "%s", "%s", %i, %i, %i, %s, %i, "%s", "%s", "%s", %s, "%s", "%s", "%s" , "%s" );',
					category, id, ping, name, desc, map, players, maxplayers, botplayers, tostring( pass ), lastplayed, address, gm, workshopid, tostring( isAnon ), version, tostring( serverlist.IsServerFavorite( address ) ), loc, gmcat ) )

			else

				Msg( "Ignoring server '", name, "' @ ", address, " - ", blackListMatch, " is blacklisted\n" )

			end

			return !ShouldStop[ category ]

		end,

		CallbackFailed = function( address )

			if ( Servers[ category ] && Servers[ category ][ address ] ) then print( "Server Browser Error!", address, category ) return end
			Servers[ category ][ address ] = true

			local version = string.JavascriptSafe( tostring( VERSION ) )

			pnlMainMenu:Call( string.format( 'AddServer( "%s", "%s", %i, "%s", "%s", "%s", %i, %i, %i, %s, %i, "%s", "%s", "%s", %s, "%s", "%s", "%s", "%s" );',
					category, id, 2000, "The server at address " .. address .. " failed to respond", "Unreachable Servers", "no_map", 0, 2, 0, 'false', 0, address, 'unkn', '0', 'true', version, tostring( serverlist.IsServerFavorite( address ) ), "", "" ) )

			return !ShouldStop[ category ]

		end,

		Finished = function()
			pnlMainMenu:Call( "FinishedServeres( '" .. category:JavascriptSafe() .. "' )" )
			Servers[ category ] = {}
		end,

		Type = category,
		GameDir = "garrysmod",
		AppID = 4000,
	}

	serverlist.Query( data )

end

function DoStopServers( category )
	pnlMainMenu:Call( "FinishedServeres( '" .. category:JavascriptSafe() .. "' )" )
	ShouldStop[ category ] = true
	Servers[ category ] = {}
end

--
-- Called from JS
--
function UpdateLanguages()

	local f = file.Find( "resource/localization/*.png", "MOD" )
	local json = util.TableToJSON( f )
	pnlMainMenu:Call( "UpdateLanguages(" .. json .. ")" )

end

--
-- Called from the engine any time the language changes
--
function LanguageChanged( lang )

	if ( !IsValid( pnlMainMenu ) ) then return end

	UpdateLanguages()
	pnlMainMenu:Call( "UpdateLanguage( \"" .. lang:JavascriptSafe() .. "\" )" )

end

function UpdateGames()

	local games = engine.GetGames()
	local json = util.TableToJSON( games )

	pnlMainMenu:Call( "UpdateGames( " .. json .. ")" )

end

function UpdateSubscribedAddons()

	local subscriptions = engine.GetAddons()
	local json = util.TableToJSON( subscriptions )
	pnlMainMenu:Call( "subscriptions.Update( " .. json .. " )" )

	local UGCsubs = engine.GetUserContent()
	local jsonUGC = util.TableToJSON( UGCsubs )
	pnlMainMenu:Call( "subscriptions.UpdateUGC( " .. jsonUGC .. " )" )

end

function UpdateAddonDisabledState()
	local noaddons, noworkshop = GetAddonStatus()
	pnlMainMenu:Call( "UpdateAddonDisabledState( " .. tostring( noaddons ) .. ", " .. tostring( noworkshop ) .. " )" )
end

function MenuGetAddonData( wsid )
	steamworks.FileInfo( wsid, function( data )
		local json = util.TableToJSON( data ) or ""
		pnlMainMenu:Call( "ReceivedChildAddonInfo( " .. json .. " )" )
	end )
end

local presetCache = {}
function CreateNewAddonPreset( data )
	if ( table.IsEmpty( presetCache ) ) then presetCache = util.JSONToTable( LoadAddonPresets() or "" ) or {} end

	local data = util.JSONToTable( data )
	presetCache[ data.name ] = data

	SaveAddonPresets( util.TableToJSON( presetCache ) )
end
function DeleteAddonPreset( name )
	if ( table.IsEmpty( presetCache ) ) then presetCache = util.JSONToTable( LoadAddonPresets() or "" ) or {} end

	presetCache[ name ] = {}
	presetCache[ name ] = nil

	SaveAddonPresets( util.TableToJSON( presetCache ) )

	ListAddonPresets()
end
function ListAddonPresets()
	if ( table.IsEmpty( presetCache ) ) then presetCache = util.JSONToTable( LoadAddonPresets() or "" ) or {} end

	pnlMainMenu:Call( "OnReceivePresetList(" .. util.TableToJSON( presetCache ) .. ")" )
end

-- Called when UGC subscription status changes
hook.Add( "WorkshopSubscriptionsChanged", "WorkshopSubscriptionsChanged", function( msg )

	UpdateSubscribedAddons()

end )

hook.Add("GameContentChanged", "RefreshMainMenu", function()

	if ( !IsValid( pnlMainMenu ) ) then return end

	pnlMainMenu:RefreshContent()

	UpdateGames()
	UpdateServerSettings()
	UpdateSubscribedAddons()

end)

hook.Add( "LoadGModSaveFailed", "LoadGModSaveFailed", function( str, wsid )
	local button2 = nil
	if ( wsid && wsid:len() > 0 ) then button2 = "Open map on Steam Workshop" end

	Derma_Query( str, "Failed to load save!", "OK", nil, button2, function() steamworks.ViewFile( wsid ) end )
end )

--
-- Initialize
--
timer.Simple(0, function()
	pnlMainMenu = vgui.Create( "MainMenuPanel" )

	local language = GetConVarString( "gmod_language" )
	LanguageChanged( language )

	hook.Run( "GameContentChanged" )

	timer.Simple(1, function()
		if file.Exists("gmenu/gmenu.txt", "DATA") then return end
		local welcomeFrame = vgui.Create("DFrame")
		welcomeFrame.SysTime = SysTime()
		welcomeFrame:SetSize(ScrW()*0.6, ScrH()*0.6)
		welcomeFrame:Center()
		welcomeFrame:SetTitle("")
		welcomeFrame:ShowCloseButton(false)
		welcomeFrame:MakePopup()
		welcomeFrame.Paint = function(self, w, h)
			Derma_DrawBackgroundBlur(self, self.SysTime)
			draw.RoundedBox(gmenu.Config.HasOffset and gmenu.Config.Rounding or 0, 0, 0, w, h, gmenu_prim)
		end

		welcomeFrame.closeBtn = welcomeFrame:Add("DButton")
		welcomeFrame.closeBtn:SetSize(24, 24)
		local ho = gmenu.Config.HasOffset
		local x, y = ho and welcomeFrame:GetWide()-24-12 or welcomeFrame:GetWide()-24, ho and 12 or 0
		welcomeFrame.closeBtn:SetPos(x, y)
		welcomeFrame.closeBtn:SetText("r")
		welcomeFrame.closeBtn:SetTextColor(color_white)
		welcomeFrame.closeBtn:SetFont("marlett")
		welcomeFrame.closeBtn.Paint = function(self, w, h)
			draw.RoundedBox(gmenu.Config.HasOffset and gmenu.Config.Rounding or 0, 0, 0, w, h, self:IsHovered() and gmenu_trit or gmenu_sec)
		end

		welcomeFrame.closeBtn.DoClick = function()
			welcomeFrame:AlphaTo(0, 0.3, 0, function()
				welcomeFrame:Remove()
			end)

			file.CreateDir("gmenu")
			file.Append("gmenu/gmenu.txt", "by johngetman<3")

			pnlMainMenu:Notification("gMenu alpha", 3)
		end

		welcomeFrame.Content = welcomeFrame:Add("Panel")
		welcomeFrame.Content:Dock(FILL)
		welcomeFrame.Content.Paint = function(self, w, h)
			draw.SimpleText("gMenu", "gmenu.24B", w/2, h/2-35, gmenu_text, 1)
			draw.SimpleText("A powerful solution for comfortable gaming.", "gmenu.18", w/2, h/2-10, gmenu_text, 1)
		end

		welcomeFrame.Content.Bottom = welcomeFrame.Content:Add("Panel")
		welcomeFrame.Content.Bottom:Dock(BOTTOM)
		welcomeFrame.Content.Bottom:SetTall(35)

		local buttons = {
			["Our Github"] = "https://github.com/johngetman/gmenu",
		}

		local createdButtons = {}
		for k, v in pairs(buttons) do
			local button = vgui.Create("DButton", welcomeFrame.Content.Bottom)
			button:Dock(LEFT)
			button:SetText(k)
			button:SetFont("gmenu.18B")
			button:SetTextColor(color_white)

			button.DoClick = function()
				gui.OpenURL(v)	
			end

			button.Paint = function(self, w, h)
				draw.RoundedBox(0, 0, 0, w, h, self:IsHovered() and gmenu_trit or gmenu_sec)
			end

			table.insert(createdButtons, button)
		end

		welcomeFrame.Content.Bottom.PerformLayout = function(self, w)
			for k, v in ipairs(createdButtons) do
				local wide = math.Round(w/table.Count(createdButtons))
	
				v:SetWide(wide)
			end
		end

		if ho then
			welcomeFrame.Content:DockMargin(0, 20, 0, 0)
		end
	end)
end)