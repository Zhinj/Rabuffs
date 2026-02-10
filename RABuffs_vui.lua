-- RABuffs_vui.lua
--  Handles the visual user interface as well as event-triggered routines.
-- Version 0.10.1

-- [REFACTOR] Frame reference cache to avoid repeated getglobal() + string concatenation
RABui_FrameCache = {};
local function RABui_GetFrame(name)
	local f = RABui_FrameCache[name];
	if (f == nil) then
		f = getglobal(name);
		RABui_FrameCache[name] = f;
	end
	return f;
end

RABui_BarCount = 0;
RABui_Settings_TabCount = 4;

RABui_ccBar = 0;        -- Bar ID of the change color dialog bar
RABui_MenuBar = nil;    -- Bar ID of the bar menu bar.

RABui_LastBuffEvent = 0;
RABui_UpdateId = 0;
RABui_NextUpdate = 0;
RABui_LastShiftState = 0; -- Shift*1+Alt*2

RAB_BarDetail_SelectedGroups = { true, true, true, true, true, true, true, true };
RAB_BarDetail_SelectedClasses = {
	m = true,
	l = true,
	p = true,
	r = true,
	d = true,
	h = true,
	s = true,
	w = true,
	a = true
};
RAB_BarDetail_SelectedType = ""; -- AddBar Bar Type
RAB_BarDetail_SelectedBuffKeys = {}; -- Multiple buff keys for multi-query support
RAB_BarDetail_SelectedBuffKeysOrder = {}; -- Tracks the order of selection
RAB_BarDetail_Output = "";
RAB_BarDetail_FillStyleValue = "Segments"; -- "Segments", "Fill on any", or "Exclusive"
RAB_BarDetail_EditBarId = 0;     -- 0 = new bar

RAB_LoadShow = "";
RABui_IsUIShown = true;

StaticPopupDialogs["RAB_BARDETAIL_OUT_WHISPERTARGET"] = {
	button1 = TEXT(ACCEPT),
	button2 = TEXT(CANCEL),
	hasEditBox = 1,
	maxLetters = 30,
	whileDead = 1,
	timeout = 0,
	hideOnEscape = 1
};


-- Loading Sequence
function RABui_OnLoad()
	this:RegisterEvent("PLAYER_ENTERING_WORLD");
	this:RegisterEvent("LEARNED_SPELL_IN_TAB");

	-- StaticPopup
	StaticPopupDialogs["RAB_BARDETAIL_OUT_WHISPERTARGET"].EditBoxOnEnterPressed = RABui_BarDetail_WhisperAccept;
	StaticPopupDialogs["RAB_BARDETAIL_OUT_WHISPERTARGET"].OnAccept = RABui_BarDetail_WhisperAccept;
end

function RABui_OnEvent()
	local i, j;

	if (event == "PLAYER_ENTERING_WORLD") then
		if (RAB_Lock ~= 0) then
			RAB_Lock = 0;
			RABui_UpdateBars();
			sRAB_Localize(false, true);
		end

		RABui_Settings_SelectUTab(1);
		if (RAB_LoadShow == "welcome") then
			ShowUIPanel(RAB_SettingsFrame);
			RABui_Settings_SelectTab(1);
			RABui_Settings_SelectUTab(2);
			RABui_IsUIShown = true;
			RABFrame:Show();
		elseif (RAB_LoadShow == "changelog") then
			ShowUIPanel(RAB_SettingsFrame);
			RABui_Settings_SelectTab(1);
			RABui_Settings_SelectUTab(3);
		elseif (RAB_LoadShow == "versionwarn") then
			StaticPopup_Show("RAB_MSG");
		end
		RAB_LoadShow = "";
		this:UnregisterEvent("PLAYER_ENTERING_WORLD");
	elseif (event == "LEARNED_SPELL_IN_TAB") then
		sRAB_Localize(false, true);
	end
end

function RABui_UpdateVisibility(currentGroupStatus, previousGroupStatus)
	if (previousGroupStatus == -1 and RABui_IsUIShown) then
		RABFrame:Show();
	elseif (previousGroupStatus == -1 and not RABui_IsUIShown) then
		RABFrame:Hide();
	elseif ((currentGroupStatus == 0 and RABui_Settings.showsolo) or
			(currentGroupStatus == 1 and RABui_Settings.showparty) or
			(currentGroupStatus == 2 and RABui_Settings.showraid)) then
		RABFrame:Show();
	else
		RABFrame:Hide();
	end
end

function RABui_HideInCombat()
	if (RABui_Settings.hideincombat and UnitAffectingCombat("player")) then
		RABFrame:Hide();
	end
end

function RABui_ShowAfterCombat()
	if (RABui_Settings.hideincombat and not UnitAffectingCombat("player")) then
		-- trigger UpdateVisibility to check for other conditions
		RABui_UpdateVisibility(RAB_CurrentGroupStatus, RAB_CurrentGroupStatus);
		RAB_Core_Raise("RAB_GROUPSTATUS", RAB_CurrentGroupStatus, RAB_CurrentGroupStatus);
	end
end

function RABui_Hide()
	RABFrame:Hide();
end

function RABui_Load()
	sRAB_Localize(true, false);
	if (RAB_ChatFrame_OnEvent ~= nil) then
		RAB_RealChatFrame_OnEvent = ChatFrame_OnEvent;
		ChatFrame_OnEvent = RAB_ChatFrame_OnEvent;
	end

	RABui_SyncBars();
	if (RABui_Settings.enableGreeting) then
		RAB_Print(string.format(sRAB_Greeting, RABuffs_Version), "ok");
	end

	RAB_Settings_BL_Update();
	if (RABui_IsUIShown == false) then
		RABui_Hide();
	end

	GameTooltip.SetUnitBuffOrig = GameTooltip.SetUnitBuff;
	GameTooltip.SetUnitBuff = RABui_GameTooltip_SetUnitBuff;

	return "remove";
end

function RABui_SyncBars()
	-- create bars if necessary
	for i = 1, table.getn(RABui_Bars) do
		if (i > RABui_BarCount) then
			RABui_CreateBar(i);
			RABui_BarCount = i;
		end
	end

	local barsToShow = {};
	local shownBarCount = 0;

	-- check if bar should be hidden/unhidden
	if RABui_Settings.hideactive then
		barsToShow = {}; -- make separate list of bars to show
		shownBarCount = 0;
		for j = 1, RABui_BarCount do
			-- only show bars that aren't complete
			if (RABui_CompleteBars[j] == nil) then
				shownBarCount = shownBarCount + 1;
				table.insert(barsToShow, RABui_Bars[j]);
			else
				table.insert(barsToShow, nil);
			end
		end
	else
		barsToShow = RABui_Bars;
		shownBarCount = RABui_BarCount;
	end

	local shownBars = 0;
	for i = 1, RABui_BarCount do
		local showBar = barsToShow[i];
		local bar = RABui_GetFrame("RAB_Bar" .. i)
		if (showBar == nil) then
			bar:Hide();
		else
			shownBars = shownBars + 1;
			RABui_ShowBarAtIndex(bar, shownBars);
			
			-- Determine number of queries for this bar
			local buffKeys = showBar.buffKeys or showBar.buffKey;
			local numQueries = 1;
			if (type(buffKeys) == "table") then
				numQueries = table.getn(buffKeys);
			end
			
			-- Ensure textures exist
			RABui_EnsureBarTextures(i, numQueries);
			
			-- Set colors and visibility for bars
			if (numQueries == 1) then
				-- Single-query mode: use legacy Tex and Tex2
				local tex = RABui_GetFrame("RAB_Bar" .. i .. "Tex");
				local tex2 = RABui_GetFrame("RAB_Bar" .. i .. "Tex2");
				if (tex) then
					tex:SetTexture("Interface\\AddOns\\RABuffs\\bar.tga");
					tex:SetVertexColor(showBar.color[1], showBar.color[2], showBar.color[3]);
					tex:Show();
				end
				if (tex2) then
					tex2:SetTexture("Interface\\AddOns\\RABuffs\\bar.tga");
					tex2:SetVertexColor(showBar.color[1], showBar.color[2], showBar.color[3]);
					tex2:Show();
				end
				-- Hide extra textures if they exist
				for j = 3, 8 do
					local extraTex = RABui_GetFrame("RAB_Bar" .. i .. "Tex" .. j);
					if (extraTex) then
						extraTex:Hide();
					end
				end
			else
				-- Multi-query mode: textures will be managed by SetMultiBarValues
				-- Just ensure they're initialized
				for j = 1, numQueries do
					local texName;
					if (j == 1) then
						texName = "RAB_Bar" .. i .. "Tex";
					elseif (j == 2) then
						texName = "RAB_Bar" .. i .. "Tex2";
					else
						texName = "RAB_Bar" .. i .. "Tex" .. j;
					end
					local tex = RABui_GetFrame(texName);
					if (tex) then
						tex:SetTexture("Interface\\AddOns\\RABuffs\\bar.tga");
					end
				end
			end
			
			RABui_SetBarText(i, showBar.label .. (showBar.extralabel == nil and "" or showBar.extralabel));
		end
	end

	RABFrame:SetHeight(10 + shownBars * 12);
	RABui_Settings_Layout_SyncList();
end

function RABui_UpdateBars()
	for i = 1, table.getn(RABui_Bars) do
		RABui_UpdateBar(i);
	end
	RABui_SyncBars();
end

function RABui_CompleteBar(barid)
	if not RABui_CompleteBars[barid] then
		RABui_CompleteBars[barid] = true;
		if RABui_Settings.hideactive then
			RABui_SyncBars();
		end
	end
end

function RABui_UncompleteBar(barid)
	if RABui_CompleteBars[barid] then
		RABui_CompleteBars[barid] = nil;
		if RABui_Settings.hideactive then
			RABui_SyncBars();
		end
	end
end

function RABui_SetBarValue(barid, cur, fade, max)
	if (max == nil) then
		max = tonumber(fade);
		fade = 0;
	end
	if (tonumber(cur) > tonumber(max)) then
		max = tonumber(cur);
	end

	local userData = RABui_Bars[barid];
	local buffData = RAB_Buffs[userData.buffKey];
	local isDebuff = false
	if buffData ~= nil then
		isDebuff = buffData.type == "debuff"
	end
	if cur - fade >= math.max(max, 1) then
		if isDebuff then
			RABui_UncompleteBar(barid)
		else
			RABui_CompleteBar(barid)
		end
	else
		if isDebuff then
			RABui_CompleteBar(barid)
		else
			RABui_UncompleteBar(barid)
		end
	end

	local bar = RABui_GetFrame("RAB_Bar" .. barid);
	
	-- Always clear multi-query textures when in single-query mode
	-- (this ensures they're hidden even if buffered values haven't changed)
	-- Hide all extra textures (3-8) that may have been used for multi-query
	for i = 3, 8 do
		local extraTex = RABui_GetFrame("RAB_Bar" .. barid .. "Tex" .. i);
		if (extraTex) then
			extraTex:Hide();
		end
	end
	
	if (bar ~= nil and (cur ~= bar.cur or max ~= bar.max or fade ~= bar.fade)) then
		bar.cur, bar.max, bar.fade = cur, max, fade;
		bar.isMultiQuery = false; -- Clear multi-query flag for single-query rendering
		bar.multiQueryFading = nil; -- Clear multi-query fading data
		
		-- Reset texture alphas for single-query mode
		local tex1 = RABui_GetFrame("RAB_Bar" .. barid .. "Tex");
		local tex2 = RABui_GetFrame("RAB_Bar" .. barid .. "Tex2");
		tex1:SetAlpha(1.0);
		tex2:SetAlpha(1.0);
		
		-- Reset texture anchors (clear multi-query positioning)
		tex1:ClearAllPoints();
		tex1:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0);
		tex2:ClearAllPoints();
		tex2:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0);
		
		if (cur - fade > 0) then
			tex1:SetWidth(bar:GetWidth() * (cur - fade) / max);
		else
			tex1:SetWidth(0.01);
		end
		if (cur > 0) then
			tex2:SetWidth(bar:GetWidth() * cur / max);
		else
			tex2:SetWidth(0.01);
		end
	end
end

function RABui_SetMultiBarValues(barid, queryValues)
	-- queryValues is a table: { {cur=x, fade=y, max=z, color={r,g,b}}, ... }
	local bar = RABui_GetFrame("RAB_Bar" .. barid);
	if (bar == nil) then
		return;
	end
	
	local numQueries = table.getn(queryValues);
	if (numQueries == 0) then
		return;
	end
	
	-- Ensure enough textures exist
	RABui_EnsureBarTextures(barid, numQueries);
	
	-- Hide all textures first (up to 8)
	for i = 1, 8 do
		local texName;
		if (i == 1) then
			texName = "RAB_Bar" .. barid .. "Tex";
		elseif (i == 2) then
			texName = "RAB_Bar" .. barid .. "Tex2";
		else
			texName = "RAB_Bar" .. barid .. "Tex" .. i;
		end
		local hideTex = RABui_GetFrame(texName);
		if (hideTex) then
			hideTex:Hide();
		end
	end
	
	-- Calculate total max and current
	local totalMax = 0;
	local totalCur = 0;
	local isComplete = true;
	
	for i, qv in ipairs(queryValues) do
		totalMax = totalMax + (qv.max or 0);
		totalCur = totalCur + (qv.cur or 0);
		if (qv.cur or 0) < (qv.max or 0) then
			isComplete = false;
		end
	end
	
	-- Update completion status
	if isComplete and totalMax > 0 then
		RABui_CompleteBar(barid);
	else
		RABui_UncompleteBar(barid);
	end
	
	-- Guard against invalid bar width
	local barWidth = bar:GetWidth();
	if (barWidth == nil or barWidth == 0) then
		barWidth = 120; -- Default bar width
	end
	
	-- Get the bar's color if set
	local barColor = RABui_Bars[barid].color or { 1, 1, 1 };
	
	-- Track fading information for each query (for flashing effect)
	bar.multiQueryFading = {};
	bar.isMultiQuery = true;
	
	-- Position and fill each texture proportionally
	local startOffset = 0;
	
	for i, qv in ipairs(queryValues) do
		-- Use legacy naming for first two textures
		local texName;
		if (i == 1) then
			texName = "RAB_Bar" .. barid .. "Tex";
		elseif (i == 2) then
			texName = "RAB_Bar" .. barid .. "Tex2";
		else
			texName = "RAB_Bar" .. barid .. "Tex" .. i;
		end
		
		local tex = RABui_GetFrame(texName);
		if (tex ~= nil) then
			-- Calculate proportional segment width
			local segmentRatio = (qv.max and totalMax > 0) and (qv.max / totalMax) or 0;
			local segmentWidth = barWidth * segmentRatio;
			
			-- Calculate fill width for this segment
			local fillRatio = (qv.max and qv.max > 0) and ((qv.cur or 0) / qv.max) or 0;
			local fillWidth = segmentWidth * fillRatio;
			
			-- Ensure minimum visible width
			if (fillWidth < 0.01) then
				fillWidth = 0.01;
			end
			
			-- Set color: use query color directly (not multiplied by bar color which darkens it)
			if (qv.color) then
				tex:SetVertexColor(qv.color[1], qv.color[2], qv.color[3]);
			else
				-- If no query color, use bar color
				tex:SetVertexColor(barColor[1], barColor[2], barColor[3]);
			end
			
			-- Reset anchoring - clear and re-anchor for this segment
			tex:ClearAllPoints();
			tex:SetPoint("TOPLEFT", bar, "TOPLEFT", startOffset, 0);
			
			-- Set texture dimensions
			tex:SetWidth(fillWidth);
			tex:SetHeight(12);
			
			-- Show the texture
			tex:Show();
			
			-- Reset alpha to full (will be modified by flashing if needed)
			tex:SetAlpha(1.0);
			
			-- Store fading value for this query for flashing effect
			bar.multiQueryFading[i] = qv.fade or 0;
			
			-- Move offset for next segment
			startOffset = startOffset + segmentWidth;
		end
	end
end

function RABui_EnsureBarTextures(barid, numTextures)
	local bar = RABui_GetFrame("RAB_Bar" .. barid);
	if (bar == nil) then
		return;
	end
	
	-- Default to 2 if not specified
	numTextures = numTextures or 2;
	
	-- Create textures as needed (up to 8 per bar for multi-query support)
	for i = 1, math.min(numTextures, 8) do
		-- Use legacy naming for first two (Tex, Tex2), then indexed (Tex3, Tex4, etc)
		local texName;
		if (i == 1) then
			texName = "RAB_Bar" .. barid .. "Tex";
		elseif (i == 2) then
			texName = "RAB_Bar" .. barid .. "Tex2";
		else
			texName = "RAB_Bar" .. barid .. "Tex" .. i;
		end
		
		local tex = RABui_GetFrame(texName);
		
		if (tex == nil) then
			-- Create new texture and cache it
			tex = nil;
			-- Attempt to create a named texture; if that fails, create an unnamed one
			if (bar.CreateTexture) then
				tex = bar:CreateTexture(texName, "BACKGROUND");
				if (not tex) then
					tex = bar:CreateTexture(nil, "BACKGROUND");
				end
			end
			if (tex) then
				if (tex.SetTexture) then tex:SetTexture("Interface\\AddOns\\RABuffs\\bar.tga") end
				if (tex.SetSize) then tex:SetSize(120, 12) elseif (tex.SetWidth and tex.SetHeight) then tex:SetWidth(120); tex:SetHeight(12); end
				if (tex.SetAlpha) then tex:SetAlpha(1.0) end
				RABui_FrameCache[texName] = tex;
			else
				-- Creation failed; log a warning and skip this texture
				RAB_Print("Failed to create texture " .. texName .. " for bar " .. tostring(barid), "warn");
			end
		else
			-- Reinitialize existing texture to ensure it has proper settings
			if (tex and tex.GetTexture and not tex:GetTexture()) and tex.SetTexture then
				tex:SetTexture("Interface\\AddOns\\RABuffs\\bar.tga");
			end
			if (tex and tex.SetAlpha) then tex:SetAlpha(1.0) end
		end
	end
end

function RABui_SetBarText(barid, text)
	local bar = RABui_GetFrame("RAB_Bar" .. barid);
	if bar then
		bar:SetText(text);
	end
end

function RABui_GetBarValue(barid)
	local bar = RABui_GetFrame("RAB_Bar" .. barid);
	return tonumber(bar.cur), tonumber(bar.max);
end

-- Menus
function RABui_Menu_OnLoad()
	UIDropDownMenu_Initialize(this, RABui_Menu_Initialize, "MENU");
end

function RABui_Menu_Initialize()
	UIDropDownMenu_AddButton({ text = sRAB_Settings_UIHeader, isTitle = 1 }, UIDROPDOWNMENU_MENU_LEVEL);
	UIDropDownMenu_AddButton({
		text = sRAB_Menu_HideWindow,
		notCheckable = 1,
		func = function()
			RABFrame:Hide();
			RAB_Print(sRAB_Menu_HiddenWindow);
		end
	});
	UIDropDownMenu_AddButton({
		text = sRAB_Menu_Settings,
		notCheckable = 1,
		func = function()
			RABui_Settings_SelectTab(1);
			ShowUIPanel(RAB_SettingsFrame);
		end
	});
	UIDropDownMenu_AddButton({ text = "", disabled = 1, notCheckable = 1 });
	UIDropDownMenu_AddButton({
		text = "Current Profile: " .. (RAB_GetCurrentProfile()),
		isTitle = 1
	});
	UIDropDownMenu_AddButton({
		text = "Create New Profile...",
		notCheckable = 1,
		func = function()
			StaticPopup_Show("RAB_PROFILE_CREATE_PROMPT");
		end
	});
	UIDropDownMenu_AddButton({
		text = "Save New Profile...",
		notCheckable = 1,
		func = function()
			StaticPopup_Show("RAB_PROFILE_SAVE_PROMPT");
		end
	});
	UIDropDownMenu_AddButton({
		text = "Export Profile...",
		notCheckable = 1,
		func = function()
			RAB_ExportedProfileData = RAB_ExportProfile();
			if RAB_ExportedProfileData then
				StaticPopup_Show("RAB_PROFILE_EXPORT");
			end
		end
	});
	UIDropDownMenu_AddButton({
		text = "Import Profile...",
		notCheckable = 1,
		func = function()
			StaticPopup_Show("RAB_PROFILE_IMPORT_DATA");
		end
	});

	-- Add delete current profile option
	local profiles = RAB_GetAllProfiles();
	local current = RAB_GetCurrentProfile();
	local profileCount = table.getn(profiles);

	-- Add default if not in list for counting
	local hasDefault = false;
	for i, profile in ipairs(profiles) do
		if profile == "Default" then
			hasDefault = true;
			break ;
		end
	end
	if not hasDefault then
		profileCount = profileCount + 1;
	end

	-- Only show delete option if more than 1 profile exists and current profile is not Default
	if profileCount > 1 and current ~= "Default" then
		UIDropDownMenu_AddButton({
			text = "Delete Current Profile (" .. current .. ")",
			notCheckable = 1,
			func = function()
				RAB_ProfileToDelete = current;
				StaticPopup_Show("RAB_PROFILE_DELETE_CONFIRM", current);
			end
		});
	end

	-- Add profile load options directly
	profiles = RAB_GetAllProfiles();
	current = RAB_GetCurrentProfile();

	-- Always include Default
	local hasDefault = false;
	for i, profile in ipairs(profiles) do
		if profile == "Default" then
			hasDefault = true;
			break ;
		end
	end
	if not hasDefault then
		table.insert(profiles, 1, "Default");
	end

	for i, profile in ipairs(profiles) do
		local isChecked = (profile == current);
		local profileName = profile; -- Capture the profile name for the closure
		UIDropDownMenu_AddButton({
			text = "Load: " .. profile .. (isChecked and " (current)" or ""),
			checked = isChecked,
			func = function()
				if RAB_LoadProfile(profileName) then
					CloseDropDownMenus();
				end
			end
		});
	end

	UIDropDownMenu_SetWidth(150, RAB_Menu);
end

function RABui_MoveBar(barid, direction)
	local abuff = RABui_Bars[barid + direction];
	RABui_Bars[barid + direction] = RABui_Bars[barid];
	RABui_Bars[barid] = abuff;
	RABui_SyncBars();
end

function RABui_OnUpdate(elapsed)
	local i;

	if (RABui_NextUpdate < RAB_CachedTime) then
		RABui_UpdateId = (RABui_UpdateId > 10 and 0 or RABui_UpdateId) + 1;
		for i = 1, table.getn(RABui_Bars) do
			if (math.mod(RABui_UpdateId, RABui_Bars[i].priority) == 0 or RABui_TooltipBar == i) then
				RABui_UpdateBar(i);
			end
		end
		RABui_NextUpdate = RAB_CachedTime + RABui_Settings.updateInterval;
	end
	-- local shiftstate = (IsShiftKeyDown() and 1 or 0) + (IsAltKeyDown() and 2 or 0);
	-- if (shiftstate ~= RABui_LastShiftState) then
	-- 	RABui_LastShiftState = shiftstate;
	-- 	if (RABui_TooltipBar ~= nil and RABui_TooltipBar ~= 0) then
	-- 		RABui_UpdateTooltip(RABui_TooltipBar);
	-- 	end
	-- end
end

function RABui_UpdateBar(barid)
	local i, line, cl;
	
	-- Support for multiple buffKeys
	local userData = RABui_Bars[barid];
	local buffKeys = userData.buffKeys or userData.buffKey;
	
	-- If single buffKey, convert to array for uniform processing
	if (type(buffKeys) == "string") then
		buffKeys = { buffKeys };
	end
	
	-- If multiple queries, handle multi-bar display
	if (table.getn(buffKeys) > 1) then
		RABui_UpdateMultiBar(barid, buffKeys);
		return;
	end
	
	-- Single query (legacy behavior)
	local buffed, fading, total, misc = RAB_CallRaidBuffCheck(RABui_Bars[barid], false, false);

	RABui_SetBarValue(barid, buffed, fading, total);

	RABui_Bars[barid].extralabel = (misc == nil and "" or misc);

	local bartext = RABui_Bars[barid].label .. RABui_Bars[barid].extralabel;
	if (RABui_TooltipBar == barid) then
		bartext = buffed .. " / " .. total .. (total > 0 and " (" .. floor(buffed * 100 / total) .. "%)" or "");
		RABui_UpdateTooltip(barid);
	end
	RABui_SetBarText(barid, bartext);
end

function RABui_UpdateMultiBar(barid, buffKeys)
	-- Update a bar with multiple queries
	local fillStyle = RABui_Bars[barid].fillStyle or "Segments";
	
	-- "Fill on any" and "Exclusive" modes both use OR logic; they differ in casting behavior
	if (fillStyle == "Fill on any" or fillStyle == "Exclusive") then
		-- FILL ON ANY MODE: Count unique players who have ANY of the buffs
		local playerHasAnyBuff = {}; -- Track which players have at least one buff
		local playerFadeTimes = {}; -- Track fade times for players
		local totalPlayers = 0;
		local playersWithAnyBuff = 0;
		local minFadeTime = nil;
		local firstBuffColor = nil;
		
		for i, buffKey in ipairs(buffKeys) do
			-- Create temporary userData for this buffKey
			local tempUserData = {};
			for k, v in RABui_Bars[barid] do
				tempUserData[k] = v;
			end
			tempUserData.buffKey = buffKey;
			
			-- Get raw data for this query to check individual players
			local buffed, fading, total, misc, txthead, hashead, txt, hastxt, invert, raw = 
				RAB_CallRaidBuffCheck(tempUserData, true, false);
			
			-- Use the first query's total as the authoritative player count
			if (i == 1) then
				totalPlayers = total or 0;
			end
			
			local buffData = RAB_Buffs[buffKey];
			if (i == 1 and buffData) then
				firstBuffColor = buffData.color or { 0.5, 0.5, 0.5 };
			end
			
			if (raw) then
				for j, playerData in ipairs(raw) do
					local playerName = playerData.name;
					
					-- Check if this player has this buff
					if (playerData.buffed) then
						if (not playerHasAnyBuff[playerName]) then
							playerHasAnyBuff[playerName] = true;
							playersWithAnyBuff = playersWithAnyBuff + 1;
						end
						
						-- Track the minimum fade time across all buffs for this player
						if (playerData.fade and playerData.fade > 0) then
							if (not playerFadeTimes[playerName] or playerData.fade < playerFadeTimes[playerName]) then
								playerFadeTimes[playerName] = playerData.fade;
							end
						end
					end
				end
			end
		end
		
		-- Calculate how many players are fading (have at least one buff fading)
		local fadingCount = 0;
		for playerName, fadeTime in pairs(playerFadeTimes) do
			if (fadeTime > 0) then
				fadingCount = fadingCount + 1;
			end
		end
		
		-- Find minimum fade time for flashing effect
		for playerName, fadeTime in pairs(playerFadeTimes) do
			if (fadeTime > 0) then
				if (not minFadeTime or fadeTime < minFadeTime) then
					minFadeTime = fadeTime;
				end
			end
		end
		
		-- Create a single query value for the combined result
		local queryValues = {
			{
				cur = playersWithAnyBuff,
				fade = minFadeTime or 0,
				max = totalPlayers,
				color = (RABui_Bars[barid].queryColors and RABui_Bars[barid].queryColors[1]) or firstBuffColor
			}
		};
		
		-- Update multi-bar display with the combined result
		RABui_SetMultiBarValues(barid, queryValues);
		
		-- Update label
		RABui_Bars[barid].extralabel = "";
		
		local bartext = RABui_Bars[barid].label;
		if (RABui_TooltipBar == barid) then
			bartext = playersWithAnyBuff .. " / " .. totalPlayers .. 
				(totalPlayers > 0 and " (" .. floor(playersWithAnyBuff * 100 / totalPlayers) .. "%)" or "");
		end
		RABui_SetBarText(barid, bartext);
	else
		-- NORMAL SEGMENTED MODE: Original logic
		local queryValues = {};
		local totalBuffed = 0;
		local totalFading = 0;
		local totalPeople = 0;
		
		for i, buffKey in ipairs(buffKeys) do
			-- Create temporary userData for this buffKey
			local tempUserData = {};
			for k, v in RABui_Bars[barid] do
				tempUserData[k] = v;
			end
			tempUserData.buffKey = buffKey;
			
			-- Get buff check for this query
			local buffed, fading, total, misc = RAB_CallRaidBuffCheck(tempUserData, false, false);
			
			local buffData = RAB_Buffs[buffKey];
			if (buffData) then
				local colorToUse = (RABui_Bars[barid].queryColors and RABui_Bars[barid].queryColors[i]) or { 0.5, 0.5, 0.5 };
				table.insert(queryValues, {
					cur = buffed,
					fade = fading,
					max = total,
					color = colorToUse
				});
				totalBuffed = totalBuffed + buffed;
				totalFading = totalFading + fading;
				totalPeople = totalPeople + total;
			end
		end
		
		-- Update multi-bar display
		RABui_SetMultiBarValues(barid, queryValues);
		
		-- Update label with total counts
		RABui_Bars[barid].extralabel = "";
		
		local bartext = RABui_Bars[barid].label;
		if (RABui_TooltipBar == barid) then
			bartext = totalBuffed .. " / " .. totalPeople .. (totalPeople > 0 and " (" .. floor(totalBuffed * 100 / totalPeople) .. "%)" or "");
		end
		RABui_SetBarText(barid, bartext);
	end
end

function RABui_ChangeBarColor_Done()
	if (RABui_ccBar ~= 0) then
		local r, g, b = ColorPickerFrame:GetColorRGB();
		local buffKeys = RABui_Bars[RABui_ccBar].buffKeys or RABui_Bars[RABui_ccBar].buffKey;
		if (type(buffKeys) == "string") then
			buffKeys = { buffKeys };
		end
		
		-- Always save to main color
		RABui_Bars[RABui_ccBar].color = { r, g, b };
		
		-- For multi-query bars, apply color to all segments
		if (table.getn(buffKeys) > 1) then
			if not RABui_Bars[RABui_ccBar].queryColors then
				RABui_Bars[RABui_ccBar].queryColors = {};
			end
			for i = 1, table.getn(buffKeys) do
				RABui_Bars[RABui_ccBar].queryColors[i] = { r, g, b };
			end
		end
		
		RABui_SyncBars();
	end
end

function RABui_ChangeBarColor_Cancel(prev)
	if (RABui_ccBar ~= 0) then
		local buffKeys = RABui_Bars[RABui_ccBar].buffKeys or RABui_Bars[RABui_ccBar].buffKey;
		if (type(buffKeys) == "string") then
			buffKeys = { buffKeys };
		end
		
		-- For multi-query bars, restore all segment colors
		if (table.getn(buffKeys) > 1 and prev) then
			RABui_Bars[RABui_ccBar].queryColors = prev;
		else
			-- Single-query bar: restore main color
			RABui_Bars[RABui_ccBar].color = prev;
		end
		RABui_SyncBars();
	end
end

-- Helper functions for multiple query support
function RABui_ConvertToBuffKeys(barData)
	-- Normalize buffKey/buffKeys to always be a table
	if (not barData.buffKeys) then
		if (type(barData.buffKey) == "table") then
			barData.buffKeys = barData.buffKey;
		else
			barData.buffKeys = { barData.buffKey };
		end
		-- Keep legacy buffKey for backward compatibility
		barData.buffKey = barData.buffKeys[1];
	end
	return barData.buffKeys;
end

function RABui_SetBarBuffKeys(barid, buffKeys)
	-- Set multiple buff keys for a bar
	if (type(buffKeys) == "string") then
		buffKeys = { buffKeys };
	end
	RABui_Bars[barid].buffKeys = buffKeys;
	RABui_Bars[barid].buffKey = buffKeys[1]; -- Keep legacy support
end

function RABui_AddBuffKeyToBar(barid, buffKey)
	-- Add a single buff key to a bar's multi-query list
	local buffKeys = RABui_ConvertToBuffKeys(RABui_Bars[barid]);
	
	-- Check if already exists
	for _, bk in ipairs(buffKeys) do
		if (bk == buffKey) then
			return; -- Already in list
		end
	end
	
	table.insert(buffKeys, buffKey);
	RABui_Bars[barid].buffKeys = buffKeys;
end

function RABui_RemoveBuffKeyFromBar(barid, buffKey)
	-- Remove a buff key from a bar's multi-query list
	local buffKeys = RABui_ConvertToBuffKeys(RABui_Bars[barid]);
	
	for i, bk in ipairs(buffKeys) do
		if (bk == buffKey) then
			table.remove(buffKeys, i);
			RABui_Bars[barid].buffKeys = buffKeys;
			if (table.getn(buffKeys) > 0) then
				RABui_Bars[barid].buffKey = buffKeys[1]; -- Update legacy support
			end
			return;
		end
	end
end

function RABui_GetBuffKeysFromBar(barid)
	-- Get the list of buff keys for a bar
	return RABui_ConvertToBuffKeys(RABui_Bars[barid]);
end

-- Handles Bar Events
function RABui_BarOnEnter()
	RABui_UpdateTooltip(this:GetID());
end

function RABui_UpdateTooltip(id)
	RAB_Tooltip:SetOwner(RABFrame, "ANCHOR_LEFT");
	RABui_TooltipBar = id;

	local index, info, l;
	local info;

	-- Get all buff keys for this bar (supports both single and multi-query)
	local buffKeys = RABui_GetBuffKeysFromBar(id);
	
	-- Collect data from all queries
	local allResults = {}; -- Array of {buffKey, buffData, buffed, raw, invert, ...}
	local aggregateRaw = {}; -- Merged raw data across all queries
	
	for _, buffKey in ipairs(buffKeys) do
		local buffData = RAB_Buffs[buffKey];
		if (buffData ~= nil) then
			-- Create a temporary userData with this specific buffKey
			local tempUserData = {};
			for k, v in pairs(RABui_Bars[id]) do
				tempUserData[k] = v;
			end
			tempUserData.buffKey = buffKey;
			
			local buffed, fading, total, misc, mhead, hhead, mtext, htext, invert, raw, rawsort, rawgroup = 
				RAB_CallRaidBuffCheck(tempUserData, true, false);
			
			table.insert(allResults, {
				buffKey = buffKey,
				buffData = buffData,
				buffed = buffed,
				raw = raw,
				invert = invert,
				mhead = mhead,
				hhead = hhead,
				rawsort = rawsort,
				rawgroup = rawgroup,
				fading = fading
			});
			
			-- Merge raw data
			if (raw ~= nil) then
				for i = 1, table.getn(raw) do
					if (raw[i] ~= nil) then
						aggregateRaw[raw[i].unit] = aggregateRaw[raw[i].unit] or {};
						aggregateRaw[raw[i].unit][buffKey] = raw[i];
					end
				end
			end
		end
	end
	
	-- If no results, bail out
	if (table.getn(allResults) == 0) then
		RABui_TooltipBar = nil;
		return ;
	end
	
	-- Handle multi-query vs single-query display
	if (table.getn(buffKeys) > 1) then
		-- MULTI-QUERY DISPLAY
		for queryIdx, result in ipairs(allResults) do
			local showwhat = (result.invert == true);
			if (IsShiftKeyDown()) then
				showwhat = not showwhat;
			end
			
			-- Add buff name header
			local queryName = result.buffData.name or "Unknown";
			RAB_Tooltip:AddLine(queryName .. " " .. (showwhat and result.hhead or result.mhead));
			
			local og, cg, pline, linepeoplecount = 0, "", "", 0;
			local displayCount = 0;
			
			if (result.raw ~= nil) then
				for i = 1, table.getn(result.raw) do
					if (result.raw[i] ~= nil and result.raw[i].class ~= nil and result.raw[i].buffed == showwhat) then
						local line = result.raw[i];
						displayCount = displayCount + 1;
						line.append = line.append ~= nil and line.append or "";
						cg = result.rawgroup and string.format(result.rawgroup, line[result.rawsort]) or
								string.format(sRAB_Core_GroupFormat, line.group);
						linepeoplecount = linepeoplecount + 1;
						if ((og ~= cg or result.rawgroup == false or result.rawgroup == nil) and og ~= 0 or linepeoplecount > 5) then
							RAB_Tooltip:AddDoubleLine(pline, og);
							pline = "";
							linepeoplecount = 1;
						end
						og = cg;
						pline = pline ..
								(pline == "" and "" or ", ") ..
								RABui_Tooltip_FormatNick(line.name, line.class, line.unit, line.append) ..
								(line.fade ~= nil and " (" .. RAB_TimeFormatOffset(line.fade) .. ")" or "");
					end
				end
				if (og ~= 0) then
					RAB_Tooltip:AddDoubleLine(pline, og);
				end
				if (displayCount == 0) then
					RAB_Tooltip:AddLine(sRAB_Tooltip_NoOne);
				end
			end
			
			-- Add spacing between query sections (except after last)
			if (queryIdx < table.getn(allResults)) then
				RAB_Tooltip:AddLine(" ");
			end
		end
	else
		-- SINGLE-QUERY DISPLAY (original code path)
		local result = allResults[1];
		local buffData = result.buffData;
		local raw = result.raw;
		local invert = result.invert;
		
		local og, cg, pline, linepeoplecount = 0, "", "", 0;
		if (raw ~= nil) then
			l = 0;
			local showwhat = (invert == true);
			if (IsShiftKeyDown()) then
				showwhat = not showwhat;
			end
			RAB_Tooltip:AddLine(showwhat and result.hhead or result.mhead);
			for i = 1, table.getn(raw) do
				if (raw[i] ~= nil and raw[i].class ~= nil and raw[i].buffed == showwhat) then
					line = raw[i];
					l = l + 1;
					line.append = line.append ~= nil and line.append or "";
					cg = result.rawgroup and string.format(result.rawgroup, line[result.rawsort]) or
							string.format(sRAB_Core_GroupFormat, line.group);
					linepeoplecount = linepeoplecount + 1;
					if ((og ~= cg or result.rawgroup == false or result.rawgroup == nil) and og ~= 0 or linepeoplecount > 5) then
						RAB_Tooltip:AddDoubleLine(pline, og);
						pline = "";
						linepeoplecount = 1;
					end
					og = cg;
					pline = pline ..
							(pline == "" and "" or ", ") ..
							RABui_Tooltip_FormatNick(line.name, line.class, line.unit, line.append) ..
							(line.fade ~= nil and " (" .. RAB_TimeFormatOffset(line.fade) .. ")" or "");
				end
			end
			if (og ~= 0) then
				RAB_Tooltip:AddDoubleLine(pline, og);
			end
			if (l == 0) then
				RAB_Tooltip:AddLine(sRAB_Tooltip_NoOne);
				if (showwhat == false and result.buffed > 0 and buffData.recast ~= nil) then
					table.sort(raw,
							function(a, b)
								return tonumber(tostring(a.fade) == "nil" and 9999 or tostring(a.fade)) <
										tonumber(tostring(b.fade) == "nil" and 9999 or tostring(b.fade));
							end);
					if (raw[1].fade ~= nil and raw[1].fade < buffData.recast * 60) then
						RAB_Tooltip:SetOwner(RABFrame, "ANCHOR_LEFT");
						RAB_Tooltip:AddLine(string.format(sRAB_Tooltip_FadeSoon, buffData.name));
						for i = 1, 10 do
							if (raw[i] ~= nil and raw[i].fade ~= nil and raw[i].fade < buffData.recast * 60) then
								RAB_Tooltip:AddDoubleLine(
										RABui_Tooltip_FormatNick(raw[i].name, raw[i].class, raw[i].unit, raw[i].append),
										RAB_TimeFormatOffset(raw[i].fade));
							end
						end
					end
				end
			end
		else
			RABui_TooltipBar = nil;
			return ;
		end
	end
	
	local shiftnote = (IsShiftKeyDown() and sRAB_Tooltip_ReleaseToInvert or sRAB_Tooltip_HoldToInvert);
	local outTarget, n = "";
	if (RABui_Bars[id].out == "RAID" and UnitInRaid("player")) then
		outTarget = strlower(CHAT_MSG_RAID);
	elseif ((RABui_Bars[id].out == "RAID" or RABui_Bars[id].out == "PARTY" or RABui_Bars[id].out == nil) and GetNumPartyMembers() > 0) then
		outTarget = strlower(CHAT_MSG_PARTY);
	elseif (RABui_Bars[id].out == "OFFICER") then
		outTarget = sRAB_Settings_BarDetail_Output_Officer;
	elseif (string.find(tostring(RABui_Bars[id].out), "^CHANNEL:") ~= nil) then
		_, _, n = string.find(RABui_Bars[id].out, "^CHANNEL:(.+)");
		outTarget = n;
	elseif (string.find(tostring(RABui_Bars[id].out), "^WHISPER:") ~= nil) then
		_, _, n = string.find(RABui_Bars[id].out, "^WHISPER:(.+)");
		outTarget = n ..
				sRAB_Settings_BarDetail_Output_WhisperSuffix;
	end
	if (outTarget ~= "") then
		outTarget = string.format(sRAB_Tooltip_ClickToOutput, outTarget) .. " ";
	end
	
	-- For multi-query, show casting tips from first buff
	-- For single-query, show casting tip from that buff
	local primaryResult = allResults[1];
	if ((primaryResult.buffData.grouping == RAB_UnitClass("player") and sRAB_SpellNames[primaryResult.buffKey] ~= nil) or primaryResult.buffData.buffFunc ~= nil) then
		local tip = "";
		if (primaryResult.buffData.buffFunc == nil) then
			tip = RAB_DefaultCastingHandler("tip", RABui_Bars[id]);
		else
			tip = primaryResult.buffData.buffFunc("tip", RABui_Bars[id]);
		end
		if (type(tip) == "string" and tip ~= "") then
			RAB_Tooltip:AddLine(tip);
		end
	end
	if (RABui_Settings.dummymode) then
		RAB_Tooltip:AddLine(outTarget .. shiftnote);
	end
	RAB_Tooltip:Show();

	RAB_Tooltip:ClearAllPoints();
	local anchorPoint = "RIGHT";
	local relativePoint = "LEFT";
	local xOffset = -4;

	local x, y = RABFrame:GetCenter();
	local screenWidth = UIParent:GetWidth();
	if (x ~= nil and screenWidth ~= nil) then
		if (x < (screenWidth / 2)) then
			anchorPoint = "LEFT";
			relativePoint = "RIGHT";
			xOffset = 4;
		end
	end

	RAB_Tooltip:SetPoint(anchorPoint, "RAB_Bar" .. id, relativePoint, xOffset, 0);

	local vcur, vmax = RABui_GetBarValue(id);
	if vcur and vmax then
		RABui_SetBarText(id, vcur .. " / " .. vmax .. (vmax > 0 and " (" .. floor(vcur * 100 / vmax) .. "%)" or ""));
	end
end

function RABui_Tooltip_FormatNick(name, c, u, append)
	local nick = "";
	if (not UnitIsVisible(u)) then
		nick = "|cffaaaaaa" .. name .. "|r";
	elseif (not RAB_IsSanePvP(u)) then
		nick = "|cff00ff33" .. name .. "|r";
	else
		nick = RAB_Chat_Colors[c] .. name .. "|r";
	end
	return nick .. (append ~= nil and RAB_Chat_Colors[c] .. append .. "|r" or "");
end

function RABui_BarOnLeave()
	local id = this:GetID();
	RABui_TooltipBar = 0;
	RABui_SetBarText(id, RABui_Bars[id].label .. RABui_Bars[id].extralabel);
	RAB_Tooltip:Hide();
end

function RABui_BarOnClick()
	local id = this:GetID();

	local buffKeys = RABui_GetBuffKeysFromBar(id);
	
	if (arg1 == "LeftButton" and IsControlKeyDown()) then
		RAB_BuffCheckOutput(RABui_Bars[id], RABui_Bars[id].out ~= nil and RABui_Bars[id].out or "RAID", IsShiftKeyDown());
	elseif (arg1 == "LeftButton" and RABui_Bars[id].useOnClick) then
		-- For multi-query bars, iterate through all buff keys to find and cast any missing buff
		local doOut = true;
		local castSuccessful = false;
		
		-- Check for Exclusive mode: if the fill condition is already met, don't try casting
		local fillStyle = RABui_Bars[id].fillStyle or "Segments";
		if (fillStyle == "Exclusive") then
			-- In Exclusive mode, check if the "Fill on any" condition is already met
			-- (i.e., everyone is covered by at least one of the buff queries)
			local playerHasAnyBuff = {}; -- Track which players have at least one buff
			local totalPlayers = 0;
			
			for i, buffKey in ipairs(buffKeys) do
				local buffData = RAB_Buffs[buffKey];
				if (buffData ~= nil) then
					local tempUserData = {};
					for k, v in pairs(RABui_Bars[id]) do
						tempUserData[k] = v;
					end
					tempUserData.buffKey = buffKey;
					
					local buffed, fading, total, misc, txthead, hashead, txt, hastxt, invert, raw = 
						RAB_CallRaidBuffCheck(tempUserData, true, false);
					
					-- Track total players (use first query's count)
					if (i == 1) then
						totalPlayers = total or 0;
					end
					
					if (raw) then
						for j, playerData in ipairs(raw) do
							if (playerData.buffed) then
								playerHasAnyBuff[playerData.name] = true;
							end
						end
					end
				end
			end
			
			-- If everyone is covered, don't allow casting (prevent cascade)
			local coveredCount = 0;
			for playerName, hasBuff in pairs(playerHasAnyBuff) do
				if (hasBuff) then
					coveredCount = coveredCount + 1;
				end
			end
			
			if (coveredCount >= totalPlayers and totalPlayers > 0) then
				-- Bar is already full/satisfied, don't cast anything (exclusive to existing buffs)
				if (RABui_Settings.showsampleoutputonclick) then
					RAB_BuffCheckOutput(RABui_Bars[id], "CONSOLE", IsShiftKeyDown());
				end
				return;
			end
		end
		
		-- Try each buff key in order
		for _, buffKey in ipairs(buffKeys) do
			local buffData = RAB_Buffs[buffKey];
			if (buffData ~= nil) then
				-- Create temporary userData with this specific buffKey
				local tempUserData = {};
				for k, v in pairs(RABui_Bars[id]) do
					tempUserData[k] = v;
				end
				tempUserData.buffKey = buffKey;
				
				-- Check if anyone is missing this buff
				local buffed, fading, total = RAB_CallRaidBuffCheck(tempUserData, false, false);
				
				-- If not everyone has this buff, try to cast it
				if (buffed < total) then
					-- Try to cast this buff
					if (buffData.buffFunc ~= nil) then
						doOut = not buffData.buffFunc("cast", tempUserData);
					else
						doOut = not RAB_DefaultCastingHandler("cast", tempUserData);
					end
					castSuccessful = true;
					-- If cast was successful, stop trying other buffs
					if (doOut == false) then
						break;
					end
				end
			end
		end
		
		-- Show output if requested and cast wasn't successful
		if (doOut and RABui_Settings.showsampleoutputonclick) then
			RAB_BuffCheckOutput(RABui_Bars[id], "CONSOLE", IsShiftKeyDown());
		end
	end
end

function RABui_BarDetail_SetBarData(id)
	local buffKey, priority, groups, classes, label, excludeNames = "", 5, "", "", "", "";

	if (id == 0) then
		RAB_BarDetail_Header:SetText(sRAB_AddBarFrame_AddBar);
		RAB_BarDetail_Accept:SetText(sRAB_AddBarFrame_Add);
		RAB_BarDetail_Remove:Hide();
		RAB_BarDetail_Output = "RAID";
		RAB_BarDetail_UseOnClick:SetChecked(true);
		RAB_BarDetail_SelfLimit:SetChecked(false);
		RAB_BarDetail_FillStyleValue = "Segments"; -- Initialize to default
		if (RAB_BarDetail_FillStyle) then
			UIDropDownMenu_SetText(sRAB_Settings_BarDetail_FillStyle_Segments, RAB_BarDetail_FillStyle);
		end
		RAB_BarDetail_SelectedBuffKeys = {}; -- Initialize empty for new bars
		RAB_BarDetail_SelectedBuffKeysOrder = {}; -- Clear order tracking
	else
		RAB_BarDetail_Header:SetText(sRAB_AddBarFrame_EditBar);
		RAB_BarDetail_Accept:SetText(sRAB_AddBarFrame_Edit);
		RAB_BarDetail_Remove:Show();

		-- Get buffKeys (could be single or multiple)
		local buffKeys = RABui_GetBuffKeysFromBar(id);
		RAB_BarDetail_SelectedBuffKeys = {};
		RAB_BarDetail_SelectedBuffKeysOrder = {}; -- Restore order from buffKeys
		for _, bk in ipairs(buffKeys) do
			RAB_BarDetail_SelectedBuffKeys[bk] = true;
			table.insert(RAB_BarDetail_SelectedBuffKeysOrder, bk);
		end
		
		buffKey = RABui_Bars[id].buffKey; -- For legacy support
		groups = RABui_Bars[id].groups;
		classes = RABui_Bars[id].classes;
		label = RABui_Bars[id].label;
		priority = RABui_Bars[id].priority;
		RAB_BarDetail_Output = RABui_Bars[id].out;

		RAB_BarDetail_SelfLimit:SetChecked(RABui_Bars[id].selfLimit);

		local buffData = RAB_Buffs[buffKey];

		-- if type is selfbuffonly/wepbuffonly disable the checkbutton
		if buffData and buffData.type == 'selfbuffonly' or buffData.type == 'wepbuffonly' then
			RAB_BarDetail_SelfLimit:Disable();
		end

		RAB_BarDetail_UseOnClick:SetChecked(RABui_Bars[id].useOnClick);
		
		-- Handle fillStyle dropdown
		local fillStyle = RABui_Bars[id].fillStyle or "Segments";
		RAB_BarDetail_FillStyleValue = fillStyle;
		if (RAB_BarDetail_FillStyle) then
			local displayText = "";
			if (fillStyle == "Segments") then
				displayText = sRAB_Settings_BarDetail_FillStyle_Segments;
			elseif (fillStyle == "Fill on any") then
				displayText = sRAB_Settings_BarDetail_FillStyle_FillOnAny;
			elseif (fillStyle == "Exclusive") then
				displayText = sRAB_Settings_BarDetail_FillStyle_Exclusive;
			else
				displayText = sRAB_Settings_BarDetail_FillStyle_Segments; -- Default
			end
			UIDropDownMenu_SetText(displayText, RAB_BarDetail_FillStyle);
		end

		-- check for excludeNames not being nil or empty list
		if (RABui_Bars[id].excludeNames ~= nil) then
			--  join as comma separated list
			excludeNames = table.concat(RABui_Bars[id].excludeNames, ",");
		end
	end

	if (groups == "" or groups == nil) then
		RAB_BarDetail_SelectedGroups = { true, true, true, true, true, true, true, true };
	else
		RAB_BarDetail_SelectedGroups = { false, false, false, false, false, false, false, false };
		for grp in string.gfind(groups, "(%d)") do
			RAB_BarDetail_SelectedGroups[tonumber(grp)] = true;
		end
	end
	if (classes == "" or classes == nil) then
		RAB_BarDetail_SelectedClasses = { m = true, l = true, p = true, r = true, d = true, h = true, s = true, w = true, a = true };
	else
		RAB_BarDetail_SelectedClasses = { m = false, l = false, p = false, r = false, d = false, h = false, s = false, w = false, a = false };
		for grp in string.gfind(classes, "(%a)") do
			RAB_BarDetail_SelectedClasses[grp] = true;
		end
	end

	RAB_BarDetail_Label:SetText(label);
	RAB_BarDetail_PlayerExcludes:SetText(excludeNames);

	RAB_BarDetail_SelectedType = buffKey;
	-- Initialize selected buff keys display
	RABui_BarDetail_BuffType_UpdateText();

	UIDropDownMenu_SetSelectedValue(RAB_BarDetail_OutputTarget, RAB_BarDetail_Output);
	local outtext = sRAB_Settings_BarDetail_Output_RaidParty;
	if (RAB_BarDetail_Output == "PARTY") then
		outtext = sRAB_Settings_BarDetail_Output_Party;
	elseif (RAB_BarDetail_Output == "OFFICER") then
		outtext = sRAB_Settings_BarDetail_Output_Officer;
	elseif (string.find(RAB_BarDetail_Output, "^CHANNEL:") ~= nil) then
		_, _, n = string.find(RAB_BarDetail_Output, "^CHANNEL:(.+)");
		outtext = n;
	elseif (string.find(RAB_BarDetail_Output, "^WHISPER:") ~= nil) then
		_, _, n = string.find(RAB_BarDetail_Output, "^WHISPER:(.+)");
		outtext = n ..
				sRAB_Settings_BarDetail_Output_WhisperSuffix;
		UIDropDownMenu_SetSelectedValue(RAB_BarDetail_OutputTarget,
				"WHISPER");
	end
	UIDropDownMenu_SetText(outtext, RAB_BarDetail_OutputTarget);

	RAB_BarDetail_Priority:SetValue(11 - (priority == nil and 1 or priority));

	RABui_BarDetail_BarGroups_UpdateText();
	RABui_BarDetail_BarClasses_UpdateText();

	RAB_BarDetail_EditBarId = id;
end

function RABui_BarDetail_Priority_SetTooltip()
	if (RABui_Settings ~= nil and RABui_Settings.updateInterval ~= nil) then
		GameTooltip:SetOwner(getglobal(this:GetName() .. "Thumb"), "ANCHOR_BOTTOMLEFT", 40, 5);
		GameTooltip:AddLine(string.format(sRAB_Settings_BarDetail_PriorityTip,
				RABui_Settings.updateInterval * (11 - this:GetValue())));
		if (RAB_BarDetail_Priority.shouldShowTip) then
			GameTooltip:Show();
		end
	end
end

function RABui_BarDetail_BarGroups_ToggleGroup()
	local grp = tonumber(this.value);
	RAB_BarDetail_SelectedGroups[grp] = not RAB_BarDetail_SelectedGroups[grp];
	RABui_BarDetail_BarGroups_UpdateText();
end

function RABui_BarDetail_BarGroups_ToggleAll()
	local i;
	for i = 2, 8 do
		RAB_BarDetail_SelectedGroups[i] = not RAB_BarDetail_SelectedGroups[1];
	end
	RAB_BarDetail_SelectedGroups[1] = not RAB_BarDetail_SelectedGroups[1];
	RABui_BarDetail_BarGroups_UpdateText();
end

function RABui_BarDetail_BarGroups_UpdateText()
	local i, sb, gc = 0, "", 0;
	for i = 1, 8 do
		if (RAB_BarDetail_SelectedGroups[i]) then
			sb = (sb == "" and "" or (sb .. ", ")) .. i;
			gc = gc + 1;
		end
	end
	if (gc == 8) then
		UIDropDownMenu_SetText(sRAB_Settings_BarDetail_GroupsAll, RAB_BarDetail_Groups);
	elseif (gc >= 1) then
		UIDropDownMenu_SetText(string.format(sRAB_Settings_BarDetail_GroupsSome, sb), RAB_BarDetail_Groups);
	else
		UIDropDownMenu_SetText(sRAB_Settings_BarDetail_GroupsAll, RAB_BarDetail_Groups);
	end
end

function RABui_BarDetail_BarGroups_OnLoad()
	UIDropDownMenu_Initialize(this, RABui_BarDetail_BarGroups_Initialize);
	UIDropDownMenu_SetWidth(175, RAB_BarDetail_Groups);
end

function RABui_BarDetail_BarGroups_Initialize()
	local i, alltrue = 1, true;
	for i = 1, 8 do
		alltrue = alltrue and RAB_BarDetail_SelectedGroups[i];
	end
	for i = 1, 8 do
		UIDropDownMenu_AddButton({
			text = "Group " .. i,
			value = i,
			checked = (RAB_BarDetail_SelectedGroups[i] == true),
			func = RABui_BarDetail_BarGroups_ToggleGroup,
			keepShownOnClick = 1,
			justifyH = "CENTER"
		});
	end
	DropDownList1.maxWidth = 170;
	UIDropDownMenu_AddButton({
		text = sRAB_AddBar_ToggleAll,
		notCheckable = 1,
		func = RABui_BarDetail_BarGroups_ToggleAll,
		justifyH = "CENTER"
	});
end

function RABui_BarDetail_BarClasses_ToggleClass()
	RAB_BarDetail_SelectedClasses[this.value] = not RAB_BarDetail_SelectedClasses[this.value];
	RABui_BarDetail_BarClasses_UpdateText();
end

function RABui_BarDetail_BarClasses_ToggleAll()
	local key, st, val = "", not RAB_BarDetail_SelectedClasses["m"];

	for key, val in RAB_BarDetail_SelectedClasses do
		RAB_BarDetail_SelectedClasses[key] = st;
	end
	RABui_BarDetail_BarClasses_UpdateText();
end

function RABui_BarDetail_BarClasses_UpdateText()
	local sb, gc, fgc, key, val = "", 0, 0;
	local ignoreString = "-";
	local buffSelected = RAB_BarDetail_SelectedType ~= "" and RAB_BarDetail_SelectedType ~= nil and RAB_Buffs[RAB_BarDetail_SelectedType] ~= nil;
	if (buffSelected and RAB_Buffs[RAB_BarDetail_SelectedType].ignoreClass ~= nil) then
		ignoreString = RAB_Buffs[RAB_BarDetail_SelectedType].ignoreClass;
	end

	if buffSelected and RAB_Buffs[RAB_BarDetail_SelectedType].class then
		local fullClass = RAB_Buffs[RAB_BarDetail_SelectedType].class
		local shortClass = RAB_ClassShort[fullClass];
		fgc = 1;
		if (RAB_BarDetail_SelectedClasses[shortClass]) then
			sb = (sb == "" and "" or (sb .. ", ")) .. fullClass;
			gc = gc + 1;
		end
	else
		for key, val in RAB_ClassShort do
			--if ((val ~= "s" or UnitFactionGroup("player") == "Horde") and (val ~= "a" or UnitFactionGroup("player") == "Alliance")) then
			if (string.find(ignoreString, val) == nil) then
				fgc = fgc + 1;
				if (RAB_BarDetail_SelectedClasses[val]) then
					sb = (sb == "" and "" or (sb .. ", ")) .. key;
					gc = gc + 1;
				end
			end
		end
	end

	if (gc == fgc or gc == 0) then
		UIDropDownMenu_SetText(sRAB_Settings_BarDetail_ClassesAll, RAB_BarDetail_Classes);
	elseif (fgc >= 1) then
		UIDropDownMenu_SetText(string.format(sRAB_Settings_BarDetail_ClassesSome, sb), RAB_BarDetail_Classes);
	else
		UIDropDownMenu_SetText(sRAB_Settings_BarDetail_ClassesAll, RAB_BarDetail_Classes);
	end
end

function RABui_BarDetail_BarClasses_OnLoad()
	UIDropDownMenu_Initialize(this, RABui_BarDetail_BarClasses_Initialize);
	UIDropDownMenu_SetWidth(175, RAB_BarDetail_Classes);
end

function RABui_BarDetail_BarClasses_Initialize()
	local key, val;
	local buffSelected = RAB_BarDetail_SelectedType ~= "" and RAB_BarDetail_SelectedType ~= nil and RAB_Buffs[RAB_BarDetail_SelectedType] ~= nil;
	for key, val in RAB_ClassShort do
		local addClass = true;
		-- check for ignored classes
		if (buffSelected and
				RAB_Buffs[RAB_BarDetail_SelectedType].ignoreClass and
				string.find(RAB_Buffs[RAB_BarDetail_SelectedType].ignoreClass, val)) then
			-- skip ignored classes
			addClass = nil;
		elseif buffSelected and RAB_Buffs[RAB_BarDetail_SelectedType].class then
			-- ignore all classes except the one specified
			local shortClass = RAB_ClassShort[RAB_Buffs[RAB_BarDetail_SelectedType].class];
			if shortClass and shortClass ~= val then
				addClass = nil;
			end
		end

		if addClass then
			UIDropDownMenu_AddButton({
				text = key .. "s",
				value = val,
				checked = (RAB_BarDetail_SelectedClasses[val] == true),
				func = RABui_BarDetail_BarClasses_ToggleClass,
				keepShownOnClick = 1,
				justifyH = "CENTER"
			});
		end
	end
	DropDownList1.maxWidth = 170;
	UIDropDownMenu_AddButton({
		text = sRAB_AddBar_ToggleAll,
		func = RABui_BarDetail_BarClasses_ToggleAll,
		notCheckable = 1,
		justifyH = "CENTER"
	});
end

function RABui_BarDetail_OutputTarget_OnLoad()
	UIDropDownMenu_Initialize(this, RABui_BarDetail_OutputTarget_Initialize);
	UIDropDownMenu_SetWidth(125, this);
end

function RABui_BarDetail_OutputTarget_Initialize()
	local key, val, i;
	if (UIDROPDOWNMENU_MENU_LEVEL == 1) then
		UIDropDownMenu_AddButton({
			text = sRAB_Settings_BarDetail_Output_RaidParty,
			value = "RAID",
			func = RABui_BarDetail_OutputTarget_OnClick,
			checked = (RAB_BarDetail_Output == "RAID")
		});
		UIDropDownMenu_AddButton({
			text = sRAB_Settings_BarDetail_Output_Party,
			value = "PARTY",
			func = RABui_BarDetail_OutputTarget_OnClick,
			checked = (RAB_BarDetail_Output == "PARTY")
		});
		UIDropDownMenu_AddButton({
			text = sRAB_Settings_BarDetail_Output_Officer,
			value = "OFFICER",
			func = RABui_BarDetail_OutputTarget_OnClick,
			checked = (RAB_BarDetail_Output == "OFFICER")
		});
		UIDropDownMenu_AddButton({ text = sRAB_Settings_BarDetail_Output_Channel, value = "CHANNEL", hasArrow = 1 });
		UIDropDownMenu_AddButton({
			text = sRAB_Settings_BarDetail_Output_Whisper,
			value = "WHISPER",
			func = RABui_BarDetail_OutputTarget_OnClick,
			checked = (string.find(RAB_BarDetail_Output, "WHISPER:") ~= nil)
		});
	elseif (UIDROPDOWNMENU_MENU_VALUE == "CHANNEL") then
		for i = 1, 10 do
			id, name = GetChannelName(i);
			if (name ~= nil and name ~= RAB_gSync_Channel and name ~= CT_RA_Channel and name ~= DamageMeters_syncChannel and string.find(name, " ") == nil) then
				UIDropDownMenu_AddButton({
					text = name,
					value = "CHANNEL:" .. name,
					func = RABui_BarDetail_OutputTarget_OnClick
				}, 2);
			end
		end
	end
end

function RABui_BarDetail_OutputTarget_OnClick()
	if (this.value ~= "WHISPER") then
		UIDropDownMenu_SetSelectedValue(RAB_BarDetail_OutputTarget, this.value);
		RAB_BarDetail_Output = this.value;
		ToggleDropDownMenu(1, nil, RAB_BarDetail_OutputTarget);
	elseif (this.value == "WHISPER") then
		StaticPopup_Show("RAB_BARDETAIL_OUT_WHISPERTARGET");
	end
end

function RABui_BarDetail_WhisperAccept(pa1, pa2, pa3)
	local wtNick = getglobal(this:GetParent():GetName() .. "EditBox"):GetText();
	if (string.find(wtNick, "[ !@#$%^&*()_+-=\|;':\",./<>?]") == nil) then
		UIDropDownMenu_SetSelectedValue(RAB_BarDetail_OutputTarget, "WHISPER");
		UIDropDownMenu_SetText(wtNick .. sRAB_Settings_BarDetail_Output_WhisperSuffix, RAB_BarDetail_OutputTarget);
		RAB_BarDetail_Output = "WHISPER:" .. wtNick;
	end
end

function RABui_BarDetail_FillStyle_OnLoad()
	UIDropDownMenu_Initialize(this, RABui_BarDetail_FillStyle_Initialize);
	UIDropDownMenu_SetWidth(125, this);
end

function RABui_BarDetail_FillStyle_Initialize()
	local key, val, i;
	if (UIDROPDOWNMENU_MENU_LEVEL == 1) then
		UIDropDownMenu_AddButton({
			text = sRAB_Settings_BarDetail_FillStyle_Segments,
			value = "Segments",
			func = RABui_BarDetail_FillStyle_OnClick,
			checked = (RAB_BarDetail_FillStyleValue == "Segments")
		});
		UIDropDownMenu_AddButton({
			text = sRAB_Settings_BarDetail_FillStyle_FillOnAny,
			value = "Fill on any",
			func = RABui_BarDetail_FillStyle_OnClick,
			checked = (RAB_BarDetail_FillStyleValue == "Fill on any")
		});
		UIDropDownMenu_AddButton({
			text = sRAB_Settings_BarDetail_FillStyle_Exclusive,
			value = "Exclusive",
			func = RABui_BarDetail_FillStyle_OnClick,
			checked = (RAB_BarDetail_FillStyleValue == "Exclusive")
		});
	end
end

function RABui_BarDetail_FillStyle_OnClick()
	UIDropDownMenu_SetSelectedValue(RAB_BarDetail_FillStyle, this.value);
	RAB_BarDetail_FillStyleValue = this.value;
	ToggleDropDownMenu(1, nil, RAB_BarDetail_FillStyle);
end

function RABui_GameTooltip_SetUnitBuff(obj, unit, bId)
	obj.SetUnitBuffOrig(obj, unit, bId);
	local tex = tostring(RAB_TextureToBuff(tostring(UnitBuff(unit, bId))));
	if (RAB_BuffTimers ~= nil and RAB_BuffTimers[UnitName(unit) .. "." .. tex] ~= nil) then
		local tLeft = RAB_BuffTimers[UnitName(unit) .. "." .. tex] - GetTime();
		if (tLeft > 0) then
			obj:AddLine(string.format(sRAB_Tooltip_TimeLeft, RAB_TimeFormatOffset(tLeft)));
		end
	end
end

function RABui_BarDetail_BuffType_OnLoad()
	RABui_AddFrameDropDown_Prepare();
	UIDropDownMenu_Initialize(this, RABui_BarDetail_BuffType_Initialize);
	UIDropDownMenu_SetWidth(125, RAB_BarDetail_Type);
end

function RABui_AddFrameDropDown_Prepare()
	local buffs = {};
	local id = 1;
	for key, val in RAB_Buffs do
		if (val.name ~= nil and val.noUI == nil and val.type ~= "dummy") then
			buffs[id] = { name = val.name, grouping = "Miscellaneous", key = key }
			if (val.grouping ~= nil) then
				buffs[id].grouping = val.grouping;
			end
			if (val.type == "special") then
				buffs[id].tooltip = val.description;
				buffs[id].tooltitle = val.name;
			elseif (val.type == "debuff") then
				buffs[id].grouping = "Debuff";
			end
			id = id + 1;
		end
	end
	table.sort(buffs, function(a, b)
		return (a.name < b.name)
	end);
	RAB_ADFDD_Buffs = buffs;
	RAB_ADFDD_Categories = {};
	for key, val in buffs do
		local grp = val.grouping;
		if not RAB_ClassShort[grp] then
			grp = "z" .. grp; -- sort to the end
		end

		if (RAB_ADFDD_Categories[grp] == nil) then
			tinsert(RAB_ADFDD_Categories, grp);
		end
	end
	table.sort(RAB_ADFDD_Categories);
	local obuff = "";
	for key, val in RAB_ADFDD_Categories do
		if (val ~= obuff) then
			obuff = val;
			if (strsub(val, 1, 1) == "z") then
				RAB_ADFDD_Categories[key] = strsub(val, 2);
			end
		else
			RAB_ADFDD_Categories[key] = nil;
		end
	end
end

function RABui_BarDetail_BuffType_Initialize()
	local key, val, i;
	i = 1;
	if (UIDROPDOWNMENU_MENU_LEVEL == 1) then
		for key, val in RAB_ADFDD_Categories do
			UIDropDownMenu_AddButton({ text = val, value = val, hasArrow = 1, notCheckable = 1 });
		end
	else
		for key, val in RAB_ADFDD_Buffs do
			if (val.grouping == UIDROPDOWNMENU_MENU_VALUE) then
				-- Check if this buff is selected in multi-query
				local ischeck = RAB_BarDetail_SelectedBuffKeys[val.key] or (val.key == RAB_BarDetail_SelectedType);
				
				UIDropDownMenu_AddButton(
						{
							text = val.name,
							value = val.key,
							func = RABui_AddFrameDropDown_OnClick,
							checked = ischeck,
							keepShownOnClick = 1,  -- Keep dropdown open for multi-select
							tooltipText = val.tooltip,
							tooltipTitle = val.tooltitle
						}, 2);
				i = i + 1;
			end
		end
	end
end

function RABui_AddFrameDropDown_OnClick()
	-- Support Ctrl+Click for multi-select
	if (IsControlKeyDown()) then
		-- Multi-select mode: toggle the buff in the selection
		if (RAB_BarDetail_SelectedBuffKeys[this.value]) then
			RAB_BarDetail_SelectedBuffKeys[this.value] = nil;
			-- Remove from order tracking
			for i, buffKey in ipairs(RAB_BarDetail_SelectedBuffKeysOrder) do
				if (buffKey == this.value) then
					table.remove(RAB_BarDetail_SelectedBuffKeysOrder, i);
					break;
				end
			end
		else
			RAB_BarDetail_SelectedBuffKeys[this.value] = true;
			-- Add to order tracking
			table.insert(RAB_BarDetail_SelectedBuffKeysOrder, this.value);
		end
		-- Also set as primary type
		if (table.getn(RAB_BarDetail_SelectedBuffKeys) > 0) then
			RAB_BarDetail_SelectedType = this.value;  -- Use last selected as primary
		end
	else
		-- Single-select mode: replace selection
		RAB_BarDetail_SelectedBuffKeys = { [this.value] = true };
		RAB_BarDetail_SelectedBuffKeysOrder = { this.value }; -- Single selection
		RAB_BarDetail_SelectedType = this.value;
		-- Close dropdown on regular click
		ToggleDropDownMenu(1, nil, RAB_BarDetail_Type);
	end
	
	-- Update display text
	RABui_BarDetail_BuffType_UpdateText();
end

function RABui_BarDetail_BuffType_UpdateText()
	-- Display all selected buffs or just the primary one
	local selectedCount = 0;
	local displayText = "";
	
	for buffKey, selected in RAB_BarDetail_SelectedBuffKeys do
		if (selected and RAB_Buffs[buffKey] ~= nil) then
			selectedCount = selectedCount + 1;
			if (displayText == "") then
				displayText = RAB_Buffs[buffKey].name;
			else
				displayText = displayText .. ", " .. RAB_Buffs[buffKey].name;
			end
		end
	end
	
	if (displayText == "") then
		displayText = (RAB_BarDetail_SelectedType ~= nil and RAB_Buffs[RAB_BarDetail_SelectedType] ~= nil) 
			and RAB_Buffs[RAB_BarDetail_SelectedType].name or "";
	end
	
	-- Add count indicator if multiple selected
	if (selectedCount > 1) then
		displayText = displayText .. " (" .. selectedCount .. ")";
	end
	
	UIDropDownMenu_SetText(displayText, RAB_BarDetail_Type);
end

function RABui_AddBar_Accept()
	local i, groups, classes, alltrue, key, val = 0, "", "", true;
	for i = 1, 8 do
		alltrue = alltrue and RAB_BarDetail_SelectedGroups[i];
		if (RAB_BarDetail_SelectedGroups[i] == true) then
			groups = (groups == "" and " " or groups) .. i;
		end
	end
	if (alltrue) then
		groups = "";
	end
	alltrue = true;
	for key, val in RAB_ClassShort do
		alltrue = alltrue and RAB_BarDetail_SelectedClasses[val];
		if (RAB_BarDetail_SelectedClasses[val] == true) then
			classes = (classes == "" and " " or classes) .. val;
		end
	end
	if (alltrue) then
		classes = "";
	end

	-- Gather selected buff keys in the order they were selected
	local selectedBuffKeys = {};
	for _, buffKey in ipairs(RAB_BarDetail_SelectedBuffKeysOrder) do
		if (RAB_BarDetail_SelectedBuffKeys[buffKey] and RAB_Buffs[buffKey] ~= nil) then
			table.insert(selectedBuffKeys, buffKey);
		end
	end
	
	-- Fallback to primary type if no multi-select keys chosen
	if (table.getn(selectedBuffKeys) == 0 and RAB_BarDetail_SelectedType ~= nil and RAB_BarDetail_SelectedType ~= "") then
		selectedBuffKeys = { RAB_BarDetail_SelectedType };
	end

	if (table.getn(selectedBuffKeys) > 0) then
		-- Apply ignoreClass filter to all selected buffs
		local classes_copy = classes;
		for _, buffKey in ipairs(selectedBuffKeys) do
			if (RAB_Buffs[buffKey] and RAB_Buffs[buffKey].ignoreClass ~= nil) then
				classes = string.gsub(classes, "[" .. RAB_Buffs[buffKey].ignoreClass .. "]", "");
			end
		end

		-- Get fillStyle from dropdown
		local fillStyle = RAB_BarDetail_FillStyleValue or "Segments";
		
		RABui_AddBar(
				selectedBuffKeys,
				RAB_BarDetail_SelfLimit:GetChecked(),
				groups,
				classes,
				RAB_BarDetail_Label:GetText(),
				11 - RAB_BarDetail_Priority:GetValue(),
				RAB_BarDetail_Output,
				RAB_BarDetail_PlayerExcludes:GetText(),
				RAB_BarDetail_UseOnClick:GetChecked(),
				fillStyle);
	end
end

function split(str, delimiter)
	local result = {}
	for token in string.gfind(str, "([^" .. delimiter .. "]+)") do
		table.insert(result, token)
	end
	return result
end

function RABui_AddBar(buffKey, selfLimit, groups, classes, barlabel, barpriority, outputTarget, excludeNamesStr, useOnClick, fillStyle)
	local excludeNames = {};
	if (excludeNamesStr ~= nil and excludeNamesStr ~= "") then
		excludeNames = split(excludeNamesStr, ",")
	end

	if not useOnClick then
		useOnClick = false;
	elseif type(useOnClick) == "number" then
		useOnClick = useOnClick == 1;
	end

	-- Handle fillStyle: convert legacy boolean to string, default to "Segments"
	if not fillStyle then
		fillStyle = "Segments";
	elseif type(fillStyle) == "boolean" then
		-- Legacy support: convert boolean to string
		fillStyle = fillStyle and "Fill on any" or "Segments";
	elseif type(fillStyle) == "number" then
		-- Legacy support: convert number to string
		fillStyle = fillStyle == 1 and "Fill on any" or "Segments";
	end
	-- If fillStyle is already a string, use it as-is

	-- Support both single buffKey (string) and multiple buffKeys (table)
	local buffKeys = buffKey;
	if (type(buffKey) == "string") then
		buffKeys = { buffKey };
	end
	
	-- Primary buffKey for legacy support
	local primaryBuffKey = buffKeys[1];
	
	if (RAB_BarDetail_EditBarId == 0) then
		-- check for nil values before adding
		if (barlabel == nil) then
			RAB_Print("Bar label cannot be nil.", "warn");
			return ;
		end
		if (primaryBuffKey == nil) then
			RAB_Print("Buff key cannot be nil.", "warn");
			return ;
		end
		tinsert(RABui_Bars,
				{
					label = barlabel,
					buffKey = primaryBuffKey,  -- Legacy: single buff key
					buffKeys = buffKeys,       -- Multiple buff keys
					selfLimit = selfLimit,
					groups = groups,
					classes = classes,
					color = { 1, 1, 1 },
					priority = barpriority,
					extralabel = "",
					out = outputTarget,
					excludeNames = excludeNames,
					useOnClick = useOnClick,
					fillStyle = fillStyle,
					queryColors = {} -- Colors for each query
				});
		-- Initialize queryColors for multi-query bars
		if (table.getn(buffKeys) > 1) then
			for i = 1, table.getn(buffKeys) do
				RABui_Bars[table.getn(RABui_Bars)].queryColors[i] = { 1, 1, 1 }; -- Initialize to white (bar's default color)
			end
		end
		RABui_SyncBars();
	else
		RABui_Bars[RAB_BarDetail_EditBarId].buffKey = primaryBuffKey;
		RABui_Bars[RAB_BarDetail_EditBarId].buffKeys = buffKeys;
		-- Initialize queryColors for multi-query bars
		if (table.getn(buffKeys) > 1) then
			-- Check if we need to resize queryColors (only reinit if count changed)
			local existingColors = RABui_Bars[RAB_BarDetail_EditBarId].queryColors;
			if (not existingColors or table.getn(existingColors) ~= table.getn(buffKeys)) then
				-- Buff count changed, reset colors to white
				RABui_Bars[RAB_BarDetail_EditBarId].queryColors = {};
				for i = 1, table.getn(buffKeys) do
					RABui_Bars[RAB_BarDetail_EditBarId].queryColors[i] = { 1, 1, 1 }; -- Initialize to white
				end
			else
				-- Keep existing colors if count is the same
			end
		else
			RABui_Bars[RAB_BarDetail_EditBarId].queryColors = {};
		end
		RABui_Bars[RAB_BarDetail_EditBarId].selfLimit = selfLimit;
		RABui_Bars[RAB_BarDetail_EditBarId].groups = groups;
		RABui_Bars[RAB_BarDetail_EditBarId].classes = classes;
		RABui_Bars[RAB_BarDetail_EditBarId].label = barlabel;
		RABui_Bars[RAB_BarDetail_EditBarId].priority = barpriority;
		RABui_Bars[RAB_BarDetail_EditBarId].out = outputTarget;
		RABui_Bars[RAB_BarDetail_EditBarId].excludeNames = excludeNames;
		RABui_Bars[RAB_BarDetail_EditBarId].useOnClick = useOnClick;
		RABui_Bars[RAB_BarDetail_EditBarId].fillStyle = fillStyle;
		RABui_SyncBars();
	end
end

function RABui_SSH_Color(val)
	val = string.gsub(val, "(%b[])",
			function(a)
				return strsub(a, 2, 1) == "|" and a or
						(HIGHLIGHT_FONT_COLOR_CODE .. "[" .. strsub(a, 2, -2) .. "]" .. FONT_COLOR_CODE_CLOSE)
			end);
	val = string.gsub(val, "(%b{})",
			function(a)
				return strsub(a, 2, 1) == "|" and a or
						("|cffC0C0C0" .. "[" .. strsub(a, 2, -2) .. "]" .. FONT_COLOR_CODE_CLOSE)
			end);
	val = string.gsub(val, "(%b_=)",
			function(a)
				return strsub(a, 2, 1) == "|" and a or
						(HIGHLIGHT_FONT_COLOR_CODE .. strsub(a, 2, -2) .. FONT_COLOR_CODE_CLOSE)
			end);
	val = string.gsub(val, "(%b-+)",
			function(a)
				return strsub(a, 2, 1) == "|" and a or
						(GREEN_FONT_COLOR_CODE .. strsub(a, 2, -2) .. FONT_COLOR_CODE_CLOSE)
			end);
	return val;
end

function RABui_Settings_SelectTab(id)
	local obj = PanelTemplates_GetSelectedTab(RAB_SettingsFrame);
	for i = 1, 4 do
		if (i == id) then
			getglobal("RAB_Settings_TabFrame" .. i):Show();
			PanelTemplates_SelectTab(getglobal("RAB_SettingsFrameTab" .. i));
		else
			getglobal("RAB_Settings_TabFrame" .. i):Hide();
			PanelTemplates_DeselectTab(getglobal("RAB_SettingsFrameTab" .. i));
		end
	end
end

function RABui_Settings_SelectUTab(id)
	RAB_Settings_TabFrame1.selectedTab = id;
	PanelTemplates_SelectTab(getglobal("RAB_Settings_TabFrame1Tab" .. id));
	PanelTemplates_UpdateTabs(RAB_Settings_TabFrame1);
	if (id == 1) then
		RAB_Settings_Tab1HTML:SetText("<html><body><h1 align=\"center\">" ..
				sRAB_Settings_UIHeader ..
				"</h1>" ..
				sRAB_Settings_Welcome ..
				"<br/><br/>" .. sRAB_Settings_ReleaseNotes .. sRAB_Settings_Version .. "</body></html>");
	elseif (id == 2) then
		RAB_Settings_Tab1HTML:SetText(sRAB_IntroText);
	elseif (id == 3) then
		RAB_Settings_Tab1HTML:SetText(sRAB_ChangeLog2);
	end
	RAB_Settings_Tab1ScrollFrame:UpdateScrollChildRect();
	RAB_Settings_Tab1ScrollFrame:SetVerticalScroll(0);
end

function RABui_Settings_ToggleOption(option)
	if (RABui_Settings[option] ~= nil) then
		RABui_Settings[option] = not RABui_Settings[option];
	else
		RAB_Print("ASSERT: Option '" .. option .. "' not set.", "warn");
	end
end

function RABui_Settings_InitOption()
	this.name = strsub(this:GetName(), strlen("RAB_Settings_") + 1);
	getglobal(this:GetName() .. "Text"):SetText(getglobal("sRAB_Settings_Option_" .. this.name));
	this.tooltipText = getglobal("sRAB_Settings_Option_" .. this.name .. "_Description");
	this:SetChecked(RABui_Settings[this.name] and 1 or 0);
end

function RAB_Settings_BL_Init()
	local key, val, i, sort;
	RAB_BL_Buffs = {};
	for key, val in RAB_Buffs do
		if (val.grouping ~= nil) then
			sort = ((val.grouping == "Item" or val.grouping == "Item2") and "zItem" or (val.grouping == "Monster" and "zMonster" or val.grouping));
		elseif (val.type == "special") then
			sort = "zSpecial";
		elseif (val.type == "debuff") then
			sort = "zDebuff";
		else
			sort = "zMisc";
		end
		if (val.notInList == nil) then
			tinsert(RAB_BL_Buffs, { key = key, sort = sort, sort2 = sort .. ":" .. tostring(val.name) });
		end
	end
	table.sort(RAB_BL_Buffs, function(a, b)
		return a.sort2 < b.sort2
	end);
	os = "";
	i = 0;
	while (i < table.getn(RAB_BL_Buffs)) do
		i = i + 1;
		if (RAB_BL_Buffs[i].sort ~= os) then
			os = RAB_BL_Buffs[i].sort;
			tinsert(RAB_BL_Buffs, i, "header:" .. os);
		else
			RAB_BL_Buffs[i] = RAB_BL_Buffs[i].key;
		end
	end
end

function RAB_Settings_BL_Update()
	if (RAB_BL_Buffs == nil) then
		RAB_Settings_BL_Init();
	end
	FauxScrollFrame_Update(RAB_Settings_BuffListScrollBar, table.getn(RAB_BL_Buffs), RAB_BL_Count, 14);
	local offset, i = FauxScrollFrame_GetOffset(RAB_Settings_BuffListScrollBar), 0;

	for i = offset + 1, offset + RAB_BL_Count do
		if (RAB_BL_Buffs[i] ~= nil) then
			RAB_Settings_BL_ShowBuff(i - offset, RAB_BL_Buffs[i]);
		end
	end
end

function RAB_Settings_BL_ShowBuff(line, bkey)
	local obj = "RAB_Settings_BuffList" .. line;
	if (string.find(bkey, "header:(%w+)")) then
		_, _, bkey = string.find(bkey, "header:z?(.+)");
		getglobal(obj .. "Name"):SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b);
		getglobal(obj .. "Name"):SetText(bkey);
		getglobal(obj .. "Query"):SetText("");
		getglobal(obj .. "Type"):SetText("");
		getglobal(obj):Disable();
	else
		getglobal(obj):Enable();
		getglobal(obj .. "Name"):SetTextColor(1, 1, 1);
		getglobal(obj .. "Name"):SetText(RAB_Buffs[bkey].name);
		getglobal(obj .. "Query"):SetText(bkey);
		getglobal(obj .. "Type"):SetText(RAB_Settings_BL_BuffType(bkey));
	end
	if (RABui_Settings_BL_LockHighlightOn == bkey) then
		getglobal(obj):LockHighlight();
	else
		getglobal(obj):UnlockHighlight();
	end
end

function RAB_Settings_BL_BuffType(bkey)
	local btype = sRAB_Settings_BuffList_Buff;
	if (RAB_Buffs[bkey].bigcast ~= nil) then
		btype = sRAB_Settings_BuffList_Groupbuff;
	elseif (RAB_Buffs[bkey].type ~= nil and getglobal("sRAB_Settings_BuffList_" .. RAB_Buffs[bkey].type) ~= nil) then
		btype = getglobal("sRAB_Settings_BuffList_" .. RAB_Buffs[bkey].type);
	elseif (RAB_Buffs[bkey].sfunc ~= nil) then
		btype = sRAB_Settings_BuffList_Dunno;
	end
	return btype;
end

function RAB_Settings_BL_Click()
	local _, _, id = string.find(this:GetName(), "(%d+)$")
	id = tonumber(id);
	bkey = RAB_BL_Buffs[FauxScrollFrame_GetOffset(RAB_Settings_BuffListScrollBar) + id];
	RABui_Settings_BL_LockHighlightOn = bkey;
	RAB_Settings_BL_Update();
	RABui_Settings_BL_DetailFrame_SetBuff(bkey);
end

function RABui_Settings_BL_DetailFrame_SetBuff(buffKey)
	local key, val, usedTextureSlots;
	local buffData = RAB_Buffs[buffKey];
	RAB_BuffDetail_Header:SetText(buffData.name);
	RAB_BuffDetail_SummaryText:SetText(RAB_Settings_BL_BuffType(bkey) ..
			" " ..
			(RAB_Buffs[bkey].grouping ~= nil and string.format(sRAB_Settings_BuffList_ToolTip_CastBy, (RAB_Chat_Colors[RAB_Buffs[bkey].grouping] ~= nil and RAB_Chat_Colors[RAB_Buffs[bkey].grouping] or NORMAL_FONT_COLOR_CODE) .. RAB_Buffs[bkey].grouping .. "|r") or ""));
	usedTextureSlots = 0;
	for _, identifier in ipairs(buffData.identifiers) do
		if (identifier.texture) then
			usedTextureSlots = usedTextureSlots + 1;
			if (usedTextureSlots < 4) then
				getglobal("RAB_BuffDetail_TexBut" .. usedTextureSlots .. "Tex"):SetTexture("Interface\\Icons\\" .. identifier.texture);
				getglobal("RAB_BuffDetail_TexBut" .. usedTextureSlots).spellId = sRAB_SpellIDs
				[(usedTextureSlots == 1 and buffKey or (buffData.bigcast ~= nil and buffData.bigcast or "dummy"))];
			end
		end
	end
	for i = 1, 3 do
		if (i > usedTextureSlots) then
			getglobal("RAB_BuffDetail_TexBut" .. i):Hide();
		else
			getglobal("RAB_BuffDetail_TexBut" .. i):Show();
		end
	end
	local detail = (buffData.description ~= nil and "\n" .. buffData.description or "") ..
			(buffData.type == "dummy" and sRAB_Settings_BuffList_DummyDesc .. "\n" or "") ..
			(buffData.noUI ~= nil and "\n" .. sRAB_Settings_BuffList_NoUI or "");
	if (buffData.priority ~= nil) then
		local priarr = {};
		for key, val in buffData.priority do
			tinsert(priarr, { c = strupper(strsub(key, 1, 1)) .. strsub(key, 2), p = val });
		end
		table.sort(priarr, function(a, b)
			return a.p > b.p
		end)
		local pribuff, prilast = "", -999;
		for i = 1, table.getn(priarr) do
			if (priarr[i].p == prilast) then
				pribuff = pribuff ..
						(pribuff ~= "" and NORMAL_FONT_COLOR_CODE .. ", |r" or "") ..
						RAB_Chat_Colors[priarr[i].c] .. priarr[i].c .. "|r";
			else
				pribuff = pribuff ..
						(pribuff ~= "" and NORMAL_FONT_COLOR_CODE .. " > |r" or "") ..
						RAB_Chat_Colors[priarr[i].c] .. priarr[i].c .. "|r";
			end
			prilast = priarr[i].p;
		end
		detail = detail .. "\n\n" .. string.format(sRAB_Settings_BuffList_Detail_Priority, pribuff);
	end
	if (buffData.bigcast ~= "") then
		if (buffData.bigsort == "group") then
			detail = detail .. "\n\n" .. string.format(sRAB_Settings_BuffList_Detail_Group, buffData.bigthreshold);
		elseif (buffData.bigsort == "class") then
			detail = detail .. "\n\n" .. string.format(sRAB_Settings_BuffList_Detail_Class, buffData.bigthreshold);
		end
	end
	RAB_BuffDetail_DetailText:SetText(detail);
	RAB_BuffDetailFrame:Show();
end

function RABui_Settings_BL_DetailFrame_OnHide()
	RABui_Settings_BL_LockHighlightOn = "";
	RAB_Settings_BL_Update();
	RAB_BuffDetailFrame:Hide();
end

-- Note: Those things need to be rewritten to account for the faux offset if we're going to be supporting more bars than we can display at once.
-- Just change the way barid resolves to the bar you're moving (locking and unlocking highlight, though, is a problem. Disable moving until edit is done?)
function RABui_Settings_Layout_MoveBarUp(barid)
	if (RAB_BarDetailFrame:IsShown()) then
		RAB_BarDetailFrame:Hide()
	end
	RABui_MoveBar(barid + FauxScrollFrame_GetOffset(RAB_Settings_LayoutScrollBar), -1);
end

function RABui_Settings_Layout_MoveBarDown(barid)
	if (RAB_BarDetailFrame:IsShown()) then
		RAB_BarDetailFrame:Hide()
	end
	RABui_MoveBar(barid + FauxScrollFrame_GetOffset(RAB_Settings_LayoutScrollBar), 1);
end

function RABui_Settings_Layout_SelectBar(barid)
	if (barid == 20) then
		RABui_BarDetail_SetBarData(0);
		RABui_MenuBar = -1;
	else
		barid = barid + FauxScrollFrame_GetOffset(RAB_Settings_LayoutScrollBar);
		RABui_MenuBar = barid;
		RABui_BarDetail_SetBarData(barid);
	end
	RAB_BarDetailFrame:Show();
	RABui_Settings_Layout_SyncList();
end

function RABui_Settings_Layout_DetailFrame_OnHide()
	RABui_MenuBar = 0;
	RABui_Settings_Layout_SyncList();
	RAB_BarDetailFrame:Hide(); -- OnHide fires when tab/window is closed, the detailframe itself isn't flagged as hidden in those cases.
end

function RABui_Settings_BarLine_SwatchOnClick(id)
	id = id + FauxScrollFrame_GetOffset(RAB_Settings_LayoutScrollBar);
	RABui_ccBar = id;
	
	-- Store previous colors for undo
	local buffKeys = RABui_Bars[id].buffKeys or RABui_Bars[id].buffKey;
	if (type(buffKeys) == "string") then
		buffKeys = { buffKeys };
	end
	
	-- For multi-query bars, store queryColors; for single-query, store main color
	if (table.getn(buffKeys) > 1) then
		ColorPickerFrame.previousValues = RABui_Bars[id].queryColors or {};
	else
		ColorPickerFrame.previousValues = RABui_Bars[id].color;
	end
	
	-- Set up color picker callbacks
	ColorPickerFrame.func = RABui_ChangeBarColor_Done;
	ColorPickerFrame.cancelFunc = RABui_ChangeBarColor_Cancel;
	
	-- Display current color
	ColorSwatch:SetTexture(RABui_Bars[id].color[1], RABui_Bars[id].color[2], RABui_Bars[id].color[3]);
	ColorPickerFrame:SetColorRGB(RABui_Bars[id].color[1], RABui_Bars[id].color[2], RABui_Bars[id].color[3]);
	
	ColorPickerFrame:Show();
end

function RABui_Settings_Layout_SetBar(ui, id)
	if (id == -1) then
		getglobal("RAB_Settings_BarLine" .. ui):Hide();
	else
		local userData = RABui_Bars[id];
		getglobal("RAB_Settings_BarLine" .. ui):Show();
		getglobal("RAB_Settings_BarLine" .. ui .. "Name"):SetText(userData.label);
		
		-- Display the bar color (for multi-query bars, all segments use the same color now)
		getglobal("RAB_Settings_BarLine" .. ui .. "SwatchNormalTexture"):SetVertexColor(userData.color[1],
				userData.color[2], userData.color[3]);
		
		-- Display buff names - comma separated list for multi-query bars
		local buffKeys = userData.buffKeys or userData.buffKey;
		if (type(buffKeys) == "string") then
			buffKeys = { buffKeys };
		end
		
		local displayText = "";
		local maxWidth = 150; -- Maximum display width in pixels (approximate)
		
		if (table.getn(buffKeys) > 1) then
			-- Multi-query: show comma-separated list
			for i, buffKey in ipairs(buffKeys) do
				local buffName = RAB_Buffs[buffKey] ~= nil and RAB_Buffs[buffKey].name or buffKey;
				if (displayText == "") then
					displayText = buffName;
				else
					local testText = displayText .. ", " .. buffName;
					-- Truncate at 30 characters
					if (string.len(testText) > 30) then
						displayText = displayText .. "...";
						break;
					else
						displayText = testText;
					end
				end
			end
		else
			-- Single query
			displayText = RAB_Buffs[userData.buffKey] ~= nil and RAB_Buffs[userData.buffKey].name or userData.buffKey;
		end
		
		getglobal("RAB_Settings_BarLine" .. ui .. "Query"):SetText(displayText);
		if (id == table.getn(RABui_Bars)) then
			getglobal("RAB_Settings_BarLine" .. ui .. "MoveDown"):Disable();
		else
			getglobal("RAB_Settings_BarLine" .. ui .. "MoveDown"):Enable();
		end
		if (id == 1) then
			getglobal("RAB_Settings_BarLine" .. ui .. "MoveUp"):Disable();
		else
			getglobal("RAB_Settings_BarLine" .. ui .. "MoveUp"):Enable();
		end
		if (id == RABui_MenuBar) then
			getglobal("RAB_Settings_BarLine" .. ui):LockHighlight();
		else
			getglobal("RAB_Settings_BarLine" .. ui):UnlockHighlight();
		end
	end
end

function RABui_Settings_Layout_SyncList()
	FauxScrollFrame_Update(RAB_Settings_LayoutScrollBar, table.getn(RABui_Bars) + 1, RAB_BarList_Count, 14);
	local offset, i = FauxScrollFrame_GetOffset(RAB_Settings_LayoutScrollBar), 0;

	for i = offset + 1, offset + RAB_BarList_Count do
		if (RABui_Bars[i] ~= nil) then
			RABui_Settings_Layout_SetBar(i - offset, i);
		else
			RABui_Settings_Layout_SetBar(i - offset, -1);
		end
	end
	if (offset + RAB_BarList_Count > table.getn(RABui_Bars)) then
		RAB_Settings_BarLine20:SetPoint("TOP", getglobal("RAB_Settings_BarLine" .. (table.getn(RABui_Bars) - offset)),
				"BOTTOM");
		RAB_Settings_BarLine20:Show();
		if (RABui_MenuBar == -1) then
			RAB_Settings_BarLine20:LockHighlight();
		else
			RAB_Settings_BarLine20:UnlockHighlight();
		end
	else
		RAB_Settings_BarLine20:Hide();
	end
end

function RABui_BarDetail_RemoveBar()
	tremove(RABui_Bars, RABui_MenuBar);
	RABui_SyncBars();
	RAB_BarDetailFrame:Hide();
end

function RABui_Settings_Layout_ClearAllBars()
	local currentProfile = RAB_GetCurrentProfile();
	StaticPopup_Show("RAB_CLEAR_ALL_BARS_CONFIRM", currentProfile);
end

function RABui_Settings_Layout_ClearAllBars_Confirmed()
	RABui_Bars = {};
	RABui_SyncBars();
	RABui_Settings_Layout_SyncList();
	if (RAB_BarDetailFrame:IsVisible()) then
		RAB_BarDetailFrame:Hide();
	end
end

function RABui_Settings_localizationSelector_OnLoad()
	UIDropDownMenu_Initialize(this, RABui_Settings_localizationSelector_Menu);
	UIDropDownMenu_SetWidth(250, this);
end

function RABui_Settings_localizationSelector_Menu(level, key)
	if (not level) then
		level = 1;
	end
	if (level == 1) then
		UIDropDownMenu_AddButton(
				{ text = sRAB_Settings_Localization_vui, notCheckable = 1, value = "vui", hasArrow = 1 },
				level);
		UIDropDownMenu_AddButton(
				{ text = sRAB_Settings_Localization_out, notCheckable = 1, value = "out", hasArrow = 1 },
				level);
	elseif (this.value == "vui" or this.value == "out") then
		for key, val in sRAB_LOCALIZATION do
			local s = strupper(key);
			local uses, lang, author, desc = getglobal("sRAB_Localization_" .. s .. "_CAPABILITIES"),
			getglobal("sRAB_Localization_" .. s .. "_NATIVE"), getglobal("sRAB_Localization_" .. s .. "_AUTHOR"),
			getglobal("sRAB_Localization_" .. s .. "_DESCRIPTION");
			if (string.find(uses, "|" .. this.value .. "|") ~= nil) then
				UIDropDownMenu_AddButton(
						{
							text = lang,
							value = key,
							tooltipTitle = lang,
							tooltipText = desc,
							checked = (key == getglobal("sRAB_LOCALIZATION_" .. this.value) and 1 or 0),
							arg1 = this.value,
							arg2 = key,
							func = RABui_Settings_localizationSelector_SetLocale
						}, level);
			end
		end
	end
end

function RABui_Settings_localizationSelector_SetLocale(element, locale)
	if (element == "vui") then
		RABui_Settings.uilocale = locale;
	elseif (element == "out") then
		RABui_Settings.outlocale = locale;
	end
	sRAB_Localize(true, false);
	RABui_Settings_localizationSelector_UpdateText();
	ToggleDropDownMenu(1, nil, RAB_Settings_localizationSelector);
end

function RABui_Settings_localizationSelector_UpdateText()
	local a1, a2 = getglobal("sRAB_Localization_" .. strupper(sRAB_LOCALIZATION_vui) .. "_NATIVE"),
	getglobal("sRAB_Localization_" .. strupper(sRAB_LOCALIZATION_out) .. "_NATIVE");
	UIDropDownMenu_SetText(string.format(sRAB_Settings_Localization_TextFormat, a1, a2),
			RAB_Settings_localizationSelector);
end

function RABui_UpdateTitle()
	local currentProfile = RAB_GetCurrentProfile();
	RAB_Title:SetText(sRAB_Settings_UIHeader .. ": " .. currentProfile .. "");
end

function RABui_Localize()
	RAB_Settings_BuffList0Name:SetText(sRAB_Settings_BuffList_Name);
	RAB_Settings_BuffList0Query:SetText(sRAB_Settings_BuffList_Query);
	RAB_Settings_BuffList0Type:SetText(sRAB_Settings_BuffList_Type);
	RAB_Settings_BarLine0Name:SetText(sRAB_Settings_BuffList_Name);
	RAB_Settings_BarLine0Query:SetText(sRAB_Settings_BuffList_Query);
	RAB_Settings_BarLine0Position:SetText(sRAB_Settings_BarList_Position);
	RAB_SettingsTitleText:SetText(sRAB_Settings_UIHeader);
	RAB_SettingsFrameTab1:SetText(sRAB_Settings_Tab1Overview);
	RAB_SettingsFrameTab2:SetText(sRAB_Settings_TabBuffs);
	RAB_SettingsFrameTab3:SetText(sRAB_Settings_TabLayout);
	RAB_SettingsFrameTab4:SetText(sRAB_Settings_TabSettings);
	RAB_Settings_TabFrame1Tab1:SetText(sRAB_Settings_Tab1Overview);
	RAB_Settings_TabFrame1Tab2:SetText(sRAB_Settings_Tab1Welcome);
	RAB_Settings_TabFrame1Tab3:SetText(sRAB_Settings_Tab1Changelog);
	RAB_Settings_TabFrame2Header:SetText(sRAB_Settings_BuffList_Header);
	RAB_Settings_TabFrame2Description:SetText(sRAB_Settings_BuffList_Description);
	RAB_Settings_TabFrame3Header:SetText(sRAB_Settings_Layout_Header);
	RAB_Settings_TabFrame3Description:SetText(sRAB_Settings_Layout_Description);
	RAB_Settings_BarLine20:SetText(sRAB_Settings_Layout_AddNewBar);
	RAB_Settings_ClearAllBars:SetText(sRAB_Settings_Layout_ClearAllBars);
	RAB_Settings_TabFrame4Header:SetText(sRAB_Settings_Settings_Header);
	RAB_Settings_TabFrame4Description:SetText(sRAB_Settings_Settings_Description);
	RAB_Settings_Buffing:SetText(sRAB_Settings_Settings_Buffing);
	RAB_Settings_VUIConfig:SetText(sRAB_Settings_Settings_VUIConfig);
	RAB_BarDetail_LabelText:SetText(sRAB_Settings_BarDetail_Label);
	RAB_BarDetail_QueryText:SetText(sRAB_Settings_BarDetail_Query);
	RAB_BarDetail_OutputText:SetText(sRAB_Settings_BarDetail_OutputTarget);
	RAB_BarDetail_LimitsText:SetText(sRAB_Settings_BarDetail_Limits);
	RAB_BarDetail_Remove:SetText(sRAB_Settings_BarDetail_Remove);
	RAB_BarDetail_PriorityText:SetText(sRAB_Settings_BarDetail_Priority);
	RAB_BarDetail_PriorityLow:SetText(sRAB_Settings_BarDetail_PriorityLess);
	RAB_BarDetail_PriorityHigh:SetText(sRAB_Settings_BarDetail_PriorityMore);
	RAB_BarDetail_PlayerExcludesLabel:SetText(sRAB_Settings_BarDetail_PlayerExcludesLabel);
	RAB_BarDetail_UseOnClickLabel:SetText(sRAB_Settings_BarDetail_UseOnClickLabel);
	if (RAB_BarDetail_FillOnAnyLabel) then
		RAB_BarDetail_FillOnAnyLabel:SetText(sRAB_Settings_BarDetail_FillOnAnyLabel);
	end
	RAB_BarDetail_SelfLimitLabel:SetText(sRAB_Settings_BarDetail_SelfLimitLabel);

	RABui_UpdateTitle();
	StaticPopupDialogs["RAB_BARDETAIL_OUT_WHISPERTARGET"].text = sRAB_Settings_BarDetail_WhisperPrompt;

	PanelTemplates_UpdateTabs(RAB_Settings_TabFrame1);
	PanelTemplates_UpdateTabs(RAB_SettingsFrame);
	for i = 1, 4 do
		if (i < 4) then
			PanelTemplates_TabResize(0, getglobal("RAB_Settings_TabFrame1Tab" .. i));
		end
		PanelTemplates_TabResize(0, getglobal("RAB_SettingsFrameTab" .. i));
	end
	RABui_Settings_localizationSelector_UpdateText();
end

function RABui_BarRedraw()
	this.fadetime = this.fadetime and this.fadetime or 0;
	local barid = this:GetID();
	local bar = RABui_Bars[barid];
	local now = RAB_CachedTime;
	
	-- Check if this is a multi-query bar with flashing
	if (this.isMultiQuery and this.multiQueryFading) then
		local hasFlashing = false;
		for queryIdx, fadeVal in ipairs(this.multiQueryFading) do
			if (fadeVal and fadeVal > 0) then
				hasFlashing = true;
				break;
			end
		end
		
		if (hasFlashing and this.fadetime < now) then
			this.fadetime = now + 0.04;
			local alpha = cos(now * 180) * 0.2 + 0.5;
			
			-- Apply flashing to all fading textures
			for queryIdx, fadeVal in ipairs(this.multiQueryFading) do
				if (fadeVal and fadeVal > 0) then
					local texName;
					if (queryIdx == 1) then
						texName = this:GetName() .. "Tex";
					elseif (queryIdx == 2) then
						texName = this:GetName() .. "Tex2";
					else
						texName = this:GetName() .. "Tex" .. queryIdx;
					end
					local tex = RABui_GetFrame(texName);
					if (tex) then
						tex:SetAlpha(alpha);
					end
				end
			end
		end
	-- Single-query bar flashing (legacy)
	elseif (this.fade ~= nil and this.fade > 0 and this.fadetime < now) then
		this.fadetime = now + 0.04;
		RABui_GetFrame(this:GetName() .. "Tex2"):SetAlpha(cos(now * 180) * 0.2 + 0.5);
	end
end

function RABui_CreateBar(id)
	local ptr = CreateFrame("Button", "RAB_Bar" .. id, RABFrame, "RAB_Bar");
	ptr:SetID(id);
	return ptr;
end

function RABui_ShowBarAtIndex(bar, index)
	bar:SetPoint("TOPLEFT", RABFrame, "TOPLEFT", 4, -12 * (index - 1) - 5);
	bar:Show();
end

function RAB_TimeFormatOffset(tmr)
	if (tmr > 60) then
		return ceil(tmr / 60) .. "m";
	else
		return ceil(tmr) .. "s";
	end
end

RAB_Core_Register("PLAYER_LOGIN", "loadui", RABui_Load);
RAB_Core_Register("PLAYER_REGEN_DISABLED", "combatStarted", RABui_HideInCombat);
RAB_Core_Register("PLAYER_REGEN_ENABLED", "combatStopped", RABui_ShowAfterCombat);

