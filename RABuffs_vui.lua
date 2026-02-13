-- RABuffs_vui.lua
--  Handles the visual user interface as well as event-triggered routines.
-- Version 0.10.1

RABui_FrameCache = {}; -- Cache for UI frames and textures to avoid repeated global lookups
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

RABui_ccBarColorId = 0; -- Bar ID of the change color dialog bar.
RABui_MenuBar = nil;    -- Bar ID of the bar menu bar.

RABui_LastBuffEvent = 0;
RABui_UpdateId = 0;
RABui_NextUpdate = 0;
RABui_LastShiftState = 0; -- Shift*1+Alt*2

-- Per-buffKey group/class restrictions for multi-query support
RAB_BarDetail_SelectedGroups = {}; -- { [buffKey] = { true, true, ... } }
RAB_BarDetail_SelectedClasses = {}; -- { [buffKey] = { m = true, l = true, ... } }
RAB_BarDetail_SelectedType = ""; -- AddBar Bar Type
RAB_BarDetail_SelectedBuffKeys = {}; -- Multiple buff keys for multi-query support
RAB_BarDetail_SelectedBuffKeysOrder = {}; -- Tracks the order of selection
RAB_BarDetail_Output = "";
RAB_BarDetail_FillStyleValue = "Total"; -- "Total", "Segments", "Fill on any", or "Exclusive"
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
	-- Create bars if necessary
	for i = 1, table.getn(RABui_Bars) do
		if (i > RABui_BarCount) then
			RABui_CreateBar(i);
			RABui_BarCount = i;
		end
	end

	-- Determine which bars to show
	local barsToShow = RABui_Bars;
	
	if RABui_Settings.hideactive then
		barsToShow = {};
		for j = 1, RABui_BarCount do
			if (RABui_CompleteBars[j] == nil) then
				table.insert(barsToShow, RABui_Bars[j]);
			else
				table.insert(barsToShow, nil);
			end
		end
	end

	local shownBars = 0;
	for i = 1, RABui_BarCount do
		local showBar = barsToShow[i];
		local bar = RABui_GetFrame("RAB_Bar" .. i)
		if not showBar then
			bar:Hide();
		else
			shownBars = shownBars + 1;
			RABui_ShowBarAtIndex(bar, shownBars);
			
			local buffKeys = showBar.buffKeys or showBar.buffKey;
			local numQueries = (type(buffKeys) == "table") and table.getn(buffKeys) or 1;
			
			RABui_EnsureBarTextures(i, numQueries);
			
			-- Setup textures for display
			local numTexturesToSetup = (numQueries == 1) and 2 or numQueries;
			for j = 1, numTexturesToSetup do
				local tex = RABui_GetFrame(RABui_GetTextureName(i, j));
				if tex then
					tex:SetVertexColor(showBar.color[1], showBar.color[2], showBar.color[3]);
					tex:Show();
				end
			end
			
			-- Hide unused textures
			for j = numTexturesToSetup + 1, 8 do
				local tex = RABui_GetFrame(RABui_GetTextureName(i, j));
				if tex then tex:Hide(); end
			end
			
			RABui_SetBarText(i, showBar.label .. (showBar.extralabel or ""));
		end
	end

	RABFrame:SetHeight(10 + shownBars * 12);
	RABui_Settings_Layout_SyncList();
end

function RABui_UpdateBars()
	RABui_SyncBars();
	for i = 1, table.getn(RABui_Bars) do
		RABui_UpdateBar(i);
	end
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
	for i = 3, 8 do
		local extraTex = RABui_GetFrame(RABui_GetTextureName(barid, i));
		if (extraTex) then
			extraTex:Hide();
		end
	end
	
	if (bar ~= nil and (cur ~= bar.cur or max ~= bar.max or fade ~= bar.fade)) then
		bar.cur, bar.max, bar.fade = cur, max, fade;
		bar.isMultiQuery = false;
		bar.multiQueryFading = nil;
		
		local tex1 = RABui_GetFrame(RABui_GetTextureName(barid, 1));
		local tex2 = RABui_GetFrame(RABui_GetTextureName(barid, 2));
		
		if (tex1 == nil or tex2 == nil) then
			return;
		end
		
		tex1:SetAlpha(1.0);
		tex2:SetAlpha(1.0);
		tex1:Show();
		tex2:Show();
		
		tex1:ClearAllPoints();
		tex1:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0);
		tex2:ClearAllPoints();
		tex2:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0);
		
		local barWidth = bar:GetWidth();
		if (barWidth == nil or barWidth == 0) then
			barWidth = 120;
		end
		
		if (cur - fade > 0) then
			tex1:SetWidth(barWidth * (cur - fade) / max);
		else
			tex1:SetWidth(0.01);
		end
		if (cur > 0) then
			tex2:SetWidth(barWidth * cur / max);
		else
			tex2:SetWidth(0.01);
		end
	end
end

function RABui_GetTextureName(barid, index)
	if (index == 1) then
		return "RAB_Bar" .. barid .. "Tex";
	elseif (index == 2) then
		return "RAB_Bar" .. barid .. "Tex2";
	else
		return "RAB_Bar" .. barid .. "Tex" .. index;
	end
end

function RABui_SetMultiBarValues(barid, queryValues)
	-- queryValues is a table: { {cur=x, fade=y, max=z, color={r,g,b}}, ... }
	local bar = RABui_GetFrame("RAB_Bar" .. barid);
	if not bar then return; end
	
	local numQueries = table.getn(queryValues);
	if numQueries == 0 then return; end
	
	RABui_EnsureBarTextures(barid, numQueries);
	
	-- Hide unused textures beyond numQueries
	for i = numQueries + 1, 8 do
		local tex = RABui_GetFrame(RABui_GetTextureName(barid, i));
		if tex then tex:Hide(); end
	end
	
	-- Calculate total max and completion status in single pass
	local totalMax, isComplete = 0, true;
	for i, qv in ipairs(queryValues) do
		local qmax, qcur = qv.max or 0, qv.cur or 0;
		totalMax = totalMax + qmax;
		if qcur < qmax then isComplete = false; end
	end
	
	-- Update completion status
	if isComplete and totalMax > 0 then RABui_CompleteBar(barid) else RABui_UncompleteBar(barid); end
	
	-- Cache bar properties
	local barWidth = bar:GetWidth() or 120;
	if barWidth == 0 then barWidth = 120; end
	local barColor = RABui_Bars[barid].color or { 1, 1, 1 };
	
	bar.multiQueryFading, bar.isMultiQuery = {}, true;
	
	local startOffset = 0;
	for i, qv in ipairs(queryValues) do
		local tex = RABui_GetFrame(RABui_GetTextureName(barid, i));
		if tex then
			local qmax, qcur = qv.max or 0, qv.cur or 0;
			local segmentWidth = totalMax > 0 and (barWidth * qmax / totalMax) or 0;
			local fillWidth = qmax > 0 and math.max(segmentWidth * qcur / qmax, 0.01) or 0.01;
			
			tex:SetVertexColor(barColor[1], barColor[2], barColor[3]);
			tex:ClearAllPoints();
			tex:SetPoint("TOPLEFT", bar, "TOPLEFT", startOffset, 0);
			tex:SetWidth(fillWidth);
			tex:SetHeight(12);
			tex:Show();
			tex:SetAlpha(1.0);
			
			bar.multiQueryFading[i] = qv.fade or 0;
			startOffset = startOffset + segmentWidth;
		end
	end
end

function RABui_EnsureBarTextures(barid, numTextures)
	local bar = RABui_GetFrame("RAB_Bar" .. barid);
	if not bar then return; end
	
	for i = 1, math.min(numTextures or 2, 8) do
		local texName = RABui_GetTextureName(barid, i);
		local tex = RABui_GetFrame(texName);
		
		if not tex then
			tex = bar:CreateTexture(texName, "BACKGROUND") or bar:CreateTexture(nil, "BACKGROUND");
			if tex then
				tex:SetTexture("Interface\\AddOns\\RABuffs\\bar.tga");
				if tex.SetSize then tex:SetSize(120, 12) else tex:SetWidth(120); tex:SetHeight(12); end
				RABui_FrameCache[texName] = tex;
			else
				RAB_Print("Failed to create texture " .. texName .. " for bar " .. tostring(barid), "warn");
			end
		else
			if not tex:GetTexture() then tex:SetTexture("Interface\\AddOns\\RABuffs\\bar.tga"); end
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
	-- Early exit if not time to update and no active tooltip
	local hasTooltip = (RABui_TooltipBar ~= nil and RABui_TooltipBar ~= 0);
	local needsUpdate = (RABui_NextUpdate < RAB_CachedTime);
	
	if (not needsUpdate and not hasTooltip) then
		return;
	end
	
	-- Only check modifier keys if we have an active tooltip (and data isn't being updated this frame)
	if (hasTooltip and not needsUpdate) then
		local shiftstate = (IsShiftKeyDown() and 1 or 0) + (IsAltKeyDown() and 2 or 0);
		if (shiftstate ~= RABui_LastShiftState) then
			RABui_LastShiftState = shiftstate;
			RABui_UpdateTooltip(RABui_TooltipBar);
		end
	end
	
	-- Perform scheduled bar updates
	if (needsUpdate) then
		RABui_UpdateId = (RABui_UpdateId > 10 and 0 or RABui_UpdateId) + 1;
		for i = 1, table.getn(RABui_Bars) do
			if (math.mod(RABui_UpdateId, RABui_Bars[i].priority) == 0 or RABui_TooltipBar == i) then
				RABui_UpdateBar(i);
			end
		end
		RABui_NextUpdate = RAB_CachedTime + RABui_Settings.updateInterval;
		
		-- Update tooltip after bar data refresh (but only once per update cycle)
		if (hasTooltip) then
			-- Also update shift state during data refresh
			RABui_LastShiftState = (IsShiftKeyDown() and 1 or 0) + (IsAltKeyDown() and 2 or 0);
			RABui_UpdateTooltip(RABui_TooltipBar);
		end
	end
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
	end
	RABui_SetBarText(barid, bartext);
end

function RABui_UpdateMultiBar(barid, buffKeys)
	local barData = RABui_Bars[barid];
	local fillStyle = barData.fillStyle or "Total";
	
	local function GetBuffCheckData(buffKey, getRaw)
		local userData = RABui_CreateTempUserData(barid, buffKey);
		return RAB_CallRaidBuffCheck(userData, getRaw, false);
	end
	
	local function UpdateBarLabel(cur, total)
		barData.extralabel = "";
		local bartext = barData.label;
		if (RABui_TooltipBar == barid) then
			bartext = cur .. " / " .. total .. (total > 0 and " (" .. floor(cur * 100 / total) .. "%)" or "");
		end
		RABui_SetBarText(barid, bartext);
	end
	
	if (fillStyle == "Total") then
		local totalBuffed, totalFading, totalMax = 0, 0, 0;
		
		for i, buffKey in ipairs(buffKeys) do
			local buffed, fading, total = GetBuffCheckData(buffKey, false);
			totalBuffed = totalBuffed + (buffed or 0);
			totalFading = totalFading + (fading or 0);
			totalMax = totalMax + (total or 0);
		end
		
		RABui_SetMultiBarValues(barid, { { cur = totalBuffed, fade = totalFading, max = totalMax } });
		UpdateBarLabel(totalBuffed, totalMax);
	
	elseif (fillStyle == "Fill on any" or fillStyle == "Exclusive") then
		local playerBuffed = {};
		local totalPlayers = 0;
		local minFadeTime;
		
		for i, buffKey in ipairs(buffKeys) do
			local buffed, fading, total, misc, _, _, _, _, _, raw = GetBuffCheckData(buffKey, true);
			if (i == 1) then totalPlayers = total or 0; end
			
			if (raw) then
				for j, playerData in ipairs(raw) do
					if (playerData.buffed) then
						playerBuffed[playerData.name] = true;
						if (playerData.fade and playerData.fade > 0 and (not minFadeTime or playerData.fade < minFadeTime)) then
							minFadeTime = playerData.fade;
						end
					end
				end
			end
		end
		
		local coveredCount = 0;
		for _ in pairs(playerBuffed) do coveredCount = coveredCount + 1; end
		
		RABui_SetMultiBarValues(barid, { { cur = coveredCount, fade = minFadeTime or 0, max = totalPlayers } });
		UpdateBarLabel(coveredCount, totalPlayers);
	else
		local queryValues = {};
		local totalBuffed, totalFading, totalPeople = 0, 0, 0;
		
		for i, buffKey in ipairs(buffKeys) do
			local buffed, fading, total = GetBuffCheckData(buffKey, false);
			if (RAB_Buffs[buffKey]) then
				table.insert(queryValues, { cur = buffed, fade = fading, max = total });
				totalBuffed = totalBuffed + buffed;
				totalFading = totalFading + fading;
				totalPeople = totalPeople + total;
			end
		end
		
		RABui_SetMultiBarValues(barid, queryValues);
		UpdateBarLabel(totalBuffed, totalPeople);
	end
end

function RABui_ChangeBarColor_Done()
	if (RABui_ccBarColorId ~= 0) then
		RABui_Bars[RABui_ccBarColorId].color = { ColorPickerFrame:GetColorRGB() };
		RABui_SyncBars();
	end
end

function RABui_ChangeBarColor_Cancel(prev)
	if (RABui_ccBarColorId ~= 0) then
		RABui_Bars[RABui_ccBarColorId].color = prev;
		RABui_SyncBars();
	end
end

-- Helper functions for multiple query support
function RABui_CreateTempUserData(barid, buffKey)
	local userData = {};
	for k, v in pairs(RABui_Bars[barid]) do
		userData[k] = v;
	end
	userData.buffKey = buffKey;
	
	-- Apply per-buffKey group/class restrictions if available
	if (RABui_Bars[barid].groupsByBuff and RABui_Bars[barid].groupsByBuff[buffKey]) then
		userData.groups = RABui_Bars[barid].groupsByBuff[buffKey];
	end
	if (RABui_Bars[barid].classesByBuff and RABui_Bars[barid].classesByBuff[buffKey]) then
		userData.classes = RABui_Bars[barid].classesByBuff[buffKey];
	end
	
	return userData;
end

function RABui_ConvertToBuffKeys(barData)
	if (not barData.buffKeys) then
		barData.buffKeys = (type(barData.buffKey) == "table") and barData.buffKey or { barData.buffKey };
		barData.buffKey = barData.buffKeys[1];
	end
	return barData.buffKeys;
end

function RABui_SetBarBuffKeys(barid, buffKeys)
	if (type(buffKeys) == "string") then buffKeys = { buffKeys }; end
	RABui_Bars[barid].buffKeys = buffKeys;
	RABui_Bars[barid].buffKey = buffKeys[1];
end

function RABui_AddBuffKeyToBar(barid, buffKey)
	local buffKeys = RABui_ConvertToBuffKeys(RABui_Bars[barid]);
	for _, bk in ipairs(buffKeys) do
		if (bk == buffKey) then return; end
	end
	table.insert(buffKeys, buffKey);
	RABui_Bars[barid].buffKeys = buffKeys;
end

function RABui_RemoveBuffKeyFromBar(barid, buffKey)
	local buffKeys = RABui_ConvertToBuffKeys(RABui_Bars[barid]);
	for i, bk in ipairs(buffKeys) do
		if (bk == buffKey) then
			table.remove(buffKeys, i);
			RABui_Bars[barid].buffKeys = buffKeys;
			if (table.getn(buffKeys) > 0) then
				RABui_Bars[barid].buffKey = buffKeys[1];
			end
			return;
		end
	end
end

function RABui_GetBuffKeysFromBar(barid)
	return RABui_ConvertToBuffKeys(RABui_Bars[barid]);
end

-- Handles Bar Events
function RABui_BarOnEnter()
	RABui_UpdateTooltip(this:GetID());
end

function RABui_UpdateTooltip(id)
	RAB_Tooltip:SetOwner(RABFrame, "ANCHOR_LEFT");
	RABui_TooltipBar = id;

	local buffKeys = RABui_GetBuffKeysFromBar(id);
	
	local allResults = {};
	local aggregateRaw = {};
	
	for _, buffKey in ipairs(buffKeys) do
		local buffData = RAB_Buffs[buffKey];
		if (buffData ~= nil) then
			local userData = RABui_CreateTempUserData(id, buffKey);
			local buffed, _, _, _, mhead, hhead, _, _, invert, raw, rawsort, rawgroup = 
				RAB_CallRaidBuffCheck(userData, true, false);
			
			table.insert(allResults, {
				buffKey = buffKey,
				buffData = buffData,
				buffed = buffed,
				raw = raw,
				invert = invert,
				mhead = mhead,
				hhead = hhead,
				rawsort = rawsort,
				rawgroup = rawgroup
			});
			
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
	
	if (table.getn(allResults) == 0) then
		RABui_TooltipBar = nil;
		return;
	end
	
	local function RenderTooltipLines(result, showMultiHeader)
		local showwhat = result.invert;
		if (IsShiftKeyDown()) then showwhat = not showwhat; end
		
		if (showMultiHeader) then
			RAB_Tooltip:AddLine(result.buffData.name .. " " .. (showwhat and result.hhead or result.mhead));
		else
			RAB_Tooltip:AddLine(showwhat and result.hhead or result.mhead);
		end
		
		if (not result.raw) then return 0; end
		
		local og, cg, pline, linepeoplecount, displayCount = 0, "", "", 0, 0;
		for i = 1, table.getn(result.raw) do
			local line = result.raw[i];
			if (line and line.class and line.buffed == showwhat) then
				displayCount = displayCount + 1;
				line.append = line.append or "";
				cg = result.rawgroup and string.format(result.rawgroup, line[result.rawsort]) or string.format(sRAB_Core_GroupFormat, line.group);
				linepeoplecount = linepeoplecount + 1;
				if ((og ~= cg or not result.rawgroup) and og ~= 0 or linepeoplecount > 5) then
					RAB_Tooltip:AddDoubleLine(pline, og);
					pline, linepeoplecount = "", 1;
				end
				og = cg;
				pline = pline .. (pline ~= "" and ", " or "") .. RABui_Tooltip_FormatNick(line.name, line.class, line.unit, line.append) .. 
				        (line.fade and " (" .. RAB_TimeFormatOffset(line.fade) .. ")" or "");
			end
		end
		if (og ~= 0) then RAB_Tooltip:AddDoubleLine(pline, og); end
		if (displayCount == 0) then RAB_Tooltip:AddLine(sRAB_Tooltip_NoOne); end
		
		return displayCount;
	end
	
	local function RenderExclusiveTooltip(allResults, barName)
		-- For exclusive fill style with multiple queries, show consolidated list
		-- Shift not pressed: show who's missing (has no buffs)
		-- Shift pressed: show who has (has at least one buff)
		local showwhat = IsShiftKeyDown() and true or false;
		local consolidatedPlayers = {};

		local headerText = showwhat and string.format(sRAB_BuffOutput_IsOn, barName) .. ":" or string.format(sRAB_BuffOutput_MissingOn, barName) .. ":";
		RAB_Tooltip:AddLine(headerText);
		
		-- First pass: collect all unique players and check if they have ANY buff
		local playerBuffStatus = {};
		for _, result in ipairs(allResults) do
			if (result.raw) then
				for i = 1, table.getn(result.raw) do
					local line = result.raw[i];
					if (line and line.class and line.unit) then
						local cleanName = UnitName(line.unit) or line.unit;
						-- Remove buff count suffix like " [2]"
						cleanName = string.gsub(cleanName, " %[%d+%]$", "");
						if (not playerBuffStatus[cleanName]) then
							playerBuffStatus[cleanName] = {
								hasAnyBuff = false,
								playerData = {
									name = cleanName,
									class = line.class,
									unit = line.unit,
									group = line.group,
									append = line.append or "",
									fade = line.fade,
									rawsort = result.rawsort,
									rawgroup = result.rawgroup
								}
							};
						end
						-- If this player has this specific buff, mark them as having at least one buff
						if (line.buffed) then
							playerBuffStatus[cleanName].hasAnyBuff = true;
						end
					end
				end
			end
		end
		
		-- Second pass: filter based on shift key state
		for name, status in pairs(playerBuffStatus) do
			if (status.hasAnyBuff == showwhat) then
				consolidatedPlayers[name] = status.playerData;
			end
		end
		
		-- Convert to array and sort by group
		local sortedPlayers = {};
		for _, playerData in pairs(consolidatedPlayers) do
			table.insert(sortedPlayers, playerData);
		end
		table.sort(sortedPlayers, function(a, b) return a.group < b.group; end);
		
		-- Display consolidated list
		local og, cg, pline, linepeoplecount, displayCount = 0, "", "", 0, 0;
		for i = 1, table.getn(sortedPlayers) do
			local line = sortedPlayers[i];
			displayCount = displayCount + 1;
			cg = line.rawgroup and string.format(line.rawgroup, line[line.rawsort]) or string.format(sRAB_Core_GroupFormat, line.group);
			linepeoplecount = linepeoplecount + 1;
			if ((og ~= cg or not line.rawgroup) and og ~= 0 or linepeoplecount > 5) then
				RAB_Tooltip:AddDoubleLine(pline, og);
				pline, linepeoplecount = "", 1;
			end
			og = cg;
			pline = pline .. (pline ~= "" and ", " or "") .. RABui_Tooltip_FormatNick(line.name, line.class, line.unit, line.append) .. 
			        (line.fade and " (" .. RAB_TimeFormatOffset(line.fade) .. ")" or "");
		end
		if (og ~= 0) then RAB_Tooltip:AddDoubleLine(pline, og); end
		if (displayCount == 0) then RAB_Tooltip:AddLine(sRAB_Tooltip_NoOne); end
		
		return displayCount;
	end
	
	local numResults = table.getn(allResults);
	local fillStyle = RABui_Bars[id].fillStyle or "Segments";
	
	if (numResults > 1 and fillStyle == "Exclusive") then
		-- Use exclusive tooltip rendering for multiple queries with exclusive fill style
		local displayCount = RenderExclusiveTooltip(allResults, RABui_Bars[id].label);
	elseif (numResults > 1) then
		for queryIdx, result in ipairs(allResults) do
			RenderTooltipLines(result, true);
			if (queryIdx < numResults) then RAB_Tooltip:AddLine(" "); end
		end
	else
		local result = allResults[1];
		local displayCount = RenderTooltipLines(result, false);
		
		if (displayCount == 0 and not result.invert and result.buffed > 0 and result.buffData.recast) then
			table.sort(result.raw, function(a, b)
				return (a.fade or 9999) < (b.fade or 9999);
			end);
			if (result.raw[1].fade and result.raw[1].fade < result.buffData.recast * 60) then
				RAB_Tooltip:SetOwner(RABFrame, "ANCHOR_LEFT");
				RAB_Tooltip:AddLine(string.format(sRAB_Tooltip_FadeSoon, result.buffData.name));
				for i = 1, 10 do
					local line = result.raw[i];
					if (line and line.fade and line.fade < result.buffData.recast * 60) then
						RAB_Tooltip:AddDoubleLine(RABui_Tooltip_FormatNick(line.name, line.class, line.unit, line.append), RAB_TimeFormatOffset(line.fade));
					end
				end
			end
		end
	end
	
	local shiftnote = (IsShiftKeyDown() and sRAB_Tooltip_ReleaseToInvert or sRAB_Tooltip_HoldToInvert);
	local outTarget = "";
	
	if (RABui_Bars[id].out == "RAID" and UnitInRaid("player")) then
		outTarget = strlower(CHAT_MSG_RAID);
	elseif ((RABui_Bars[id].out == "RAID" or RABui_Bars[id].out == "PARTY" or RABui_Bars[id].out == nil) and GetNumPartyMembers() > 0) then
		outTarget = strlower(CHAT_MSG_PARTY);
	elseif (RABui_Bars[id].out == "OFFICER") then
		outTarget = sRAB_Settings_BarDetail_Output_Officer;
	elseif (string.find(tostring(RABui_Bars[id].out), "^CHANNEL:") ~= nil) then
		local _, _, n = string.find(RABui_Bars[id].out, "^CHANNEL:(.+)");
		outTarget = n;
	elseif (string.find(tostring(RABui_Bars[id].out), "^WHISPER:") ~= nil) then
		local _, _, n = string.find(RABui_Bars[id].out, "^WHISPER:(.+)");
		outTarget = n .. sRAB_Settings_BarDetail_Output_WhisperSuffix;
	end
	
	if (outTarget ~= "") then
		outTarget = string.format(sRAB_Tooltip_ClickToOutput, outTarget) .. " ";
	end
	
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

	local x = RABFrame:GetCenter();
	if (x and x < (UIParent:GetWidth() / 2)) then
		anchorPoint = "LEFT";
		relativePoint = "RIGHT";
		xOffset = 4;
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

function RABui_BuffCheckOutputWrapper(barId, outputTo, invert)
	-- Wrapper for RAB_BuffCheckOutput that handles exclusive multi-query bars
	local barData = RABui_Bars[barId];
	local buffKeys = RABui_GetBuffKeysFromBar(barId);
	local fillStyle = barData.fillStyle or "Segments";
	
	if (table.getn(buffKeys) > 1 and fillStyle == "Exclusive") then
		-- Handle exclusive multi-query output with bar name
		local playerBuffStatus = {};
		local showwhat;
		local firstResult = nil;
		local rawsort = "group";
		local rawgroup = sRAB_Core_GroupFormat;
		local totalPlayers = 0;
		
		-- First pass: collect all unique players and check if they have ANY buff
		for i, buffKey in ipairs(buffKeys) do
			if (RAB_Buffs[buffKey]) then
				local userData = RABui_CreateTempUserData(barId, buffKey);
				local buffed, _, total, _, _, _, _, _, invertFlag, raw, sort, group = RAB_CallRaidBuffCheck(userData, true, true);
				
				if (i == 1) then
					firstResult = { invert = invertFlag, total = total };
					rawsort = sort or "group";
					rawgroup = group or sRAB_Core_GroupFormat;
				end
				
				if (raw) then
					for j, playerData in ipairs(raw) do
						local cleanName = playerData.unit and UnitName(playerData.unit) or playerData.name;
						-- Remove buff count suffix like " [2]"
						cleanName = string.gsub(cleanName, " %[%d+%]$", "");
						
						if (not playerBuffStatus[cleanName]) then
							playerBuffStatus[cleanName] = {
								hasAnyBuff = false,
								playerData = {
									unit = playerData.unit,
									name = cleanName,
									class = playerData.class,
									group = playerData.group,
									fade = playerData.fade,
									append = playerData.append or ""
								}
							};
						end
						-- If this player has this specific buff, mark them as having at least one buff
						if (playerData.buffed) then
							playerBuffStatus[cleanName].hasAnyBuff = true;
						end
					end
				end
			end
		end
		
		-- Use invert parameter (from Shift key) to determine what to show
		showwhat = invert and true or false;
		
		-- Calculate total as union of all players across queries
		totalPlayers = 0;
		for _ in pairs(playerBuffStatus) do
			totalPlayers = totalPlayers + 1;
		end
		
		-- Second pass: filter based on shift key state
		local consolidatedPlayers = {};
		for name, status in pairs(playerBuffStatus) do
			if (status.hasAnyBuff == showwhat) then
				consolidatedPlayers[name] = status.playerData;
			end
		end
		
		-- Build output text
		local output = (barData.groups ~= "" and barData.groups ~= "12345678") and ("[G" .. barData.groups .. "] ") or "";
		output = output .. (barData.classes ~= "" and strlen(barData.classes) < 8 and "[" .. barData.classes .. "] " or "");
		
		local header = showwhat and string.format(sRAB_BuffOutput_IsOn, barData.label) .. ":" or string.format(sRAB_BuffOutput_MissingOn, barData.label) .. ":";
		
		-- Convert to array and sort
		local sortedPlayers = {};
		for _, playerData in pairs(consolidatedPlayers) do
			table.insert(sortedPlayers, playerData);
		end
		
		if (rawsort == "class") then
			table.sort(sortedPlayers, function(a, b) return a.class < b.class end);
		else
			table.sort(sortedPlayers, function(a, b) return a.group < b.group end);
		end
		
		-- Format output similar to default query handler
		local txt = "";
		local ub, uc, ident = "", 0, false;
		
		for i = 1, table.getn(sortedPlayers) do
			local player = sortedPlayers[i];
			if (ident ~= player[rawsort] and ident ~= false) then
				if (uc > 1) then
					txt = txt .. (txt ~= "" and ", " or "") .. 
					      (rawsort == "group" and sRAB_BuffOutput_Group or "") .. 
					      ident .. (rawsort == "class" and "s" or "") .. " [" .. uc .. "]";
				elseif (uc == 1) then
					txt = txt .. (txt ~= "" and ", " or "") .. ub;
				end
				ub, uc = "", 0;
			end
			
			ident = player[rawsort];
			uc = uc + 1;
			ub = ub .. ((ub ~= "") and ", " or "") .. player.name .. " [" .. player.class .. "; G" .. player.group .. "]";
		end
		
		-- Add final group
		if (uc > 1) then
			txt = txt .. (txt ~= "" and ", " or "") .. 
			      (rawsort == "group" and sRAB_BuffOutput_Group or "") .. 
			      ident .. (rawsort == "class" and "s" or "") .. " [" .. uc .. "]";
		elseif (uc == 1) then
			txt = txt .. (txt ~= "" and ", " or "") .. ub;
		end
		
		-- Count players in consolidatedPlayers (already filtered)
		local matchedCount = 0;
		for _, player in pairs(consolidatedPlayers) do
			matchedCount = matchedCount + 1;
		end
		
		-- Match single-query format
		if (matchedCount == totalPlayers and totalPlayers > 0) then
			-- Everyone matches: either everyone has (showwhat=true) or everyone is missing (showwhat=false)
			txt = showwhat and string.format(sRAB_BuffOutput_EveryoneHas, barData.label) or string.format(sRAB_BuffOutput_EveryoneMissing, barData.label);
		elseif (matchedCount > 0) then
			-- Partial list
			txt = header .. " [" .. matchedCount .. " / " .. totalPlayers .. "] " .. txt .. ".";
		else
			-- Nobody matches: either nobody has (showwhat=true) or nobody is missing (showwhat=false)
			txt = showwhat and string.format(sRAB_BuffOutput_EveryoneMissing, barData.label) or string.format(sRAB_BuffOutput_EveryoneHas, barData.label);
		end
		
		output = output .. txt;
		
		if (outputTo == "RAID" and not UnitInRaid("player")) then
			outputTo = "PARTY";
		end
		output = sRAB_BuffOutputPrefix .. output;
		RAB_SendMessage(output, outputTo, sRAB_BuffOutputPrefix);
	elseif (table.getn(buffKeys) > 1) then
		-- Handle other multi-query fill styles by announcing each buff separately
		for i, buffKey in ipairs(buffKeys) do
			local userData = RABui_CreateTempUserData(barId, buffKey);
			RAB_BuffCheckOutput(userData, outputTo, invert);
		end
	else
		-- Single-query bar: use default output
		local userData = RABui_CreateTempUserData(barId, buffKeys[1]);
		RAB_BuffCheckOutput(userData, outputTo, invert);
	end
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
		RABui_BuffCheckOutputWrapper(id, RABui_Bars[id].out or "RAID", IsShiftKeyDown());
	elseif (arg1 == "LeftButton" and RABui_Bars[id].useOnClick) then
		local fillStyle = RABui_Bars[id].fillStyle or "Segments";
		
		if (fillStyle == "Exclusive") then
			local playerBuffed = {};
			local totalPlayers = 0;
			
			for i, buffKey in ipairs(buffKeys) do
				if (RAB_Buffs[buffKey]) then
					local userData = RABui_CreateTempUserData(id, buffKey);
					local buffed, fading, total, _, _, _, _, _, _, raw = RAB_CallRaidBuffCheck(userData, true, false);
					
					if (i == 1) then totalPlayers = total or 0; end
					if (raw) then
						for j, playerData in ipairs(raw) do
							if (playerData.buffed) then playerBuffed[playerData.name] = true; end
						end
					end
				end
			end
			
			local coveredCount = 0;
			for _ in pairs(playerBuffed) do coveredCount = coveredCount + 1; end
			
			if (coveredCount >= totalPlayers and totalPlayers > 0) then
				if (RABui_Settings.showsampleoutputonclick) then
					RABui_BuffCheckOutputWrapper(id, "CONSOLE", IsShiftKeyDown());
				end
				return;
			end
		end
		
		local showOutput = true;
		for _, buffKey in ipairs(buffKeys) do
			local buffData = RAB_Buffs[buffKey];
			if (buffData) then
				local userData = RABui_CreateTempUserData(id, buffKey);
				local buffed, fading, total = RAB_CallRaidBuffCheck(userData, false, false);
				
				if (buffed < total) then
					showOutput = (buffData.buffFunc and buffData.buffFunc("cast", userData)) or RAB_DefaultCastingHandler("cast", userData);
					if (not showOutput) then break; end
				end
			end
		end
		
		if (showOutput and RABui_Settings.showsampleoutputonclick) then
			RABui_BuffCheckOutputWrapper(id, "CONSOLE", IsShiftKeyDown());
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
		RAB_BarDetail_FillStyleValue = "Total"; -- Initialize to default
		if (RAB_BarDetail_FillStyle) then
			UIDropDownMenu_SetText(sRAB_Settings_BarDetail_FillStyle_Total, RAB_BarDetail_FillStyle);
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
			if (fillStyle == "Total") then
				displayText = sRAB_Settings_BarDetail_FillStyle_Total;
			elseif (fillStyle == "Segments") then
				displayText = sRAB_Settings_BarDetail_FillStyle_Segments;
			elseif (fillStyle == "Fill on any") then
				displayText = sRAB_Settings_BarDetail_FillStyle_FillOnAny;
			elseif (fillStyle == "Exclusive") then
				displayText = sRAB_Settings_BarDetail_FillStyle_Exclusive;
			else
				displayText = sRAB_Settings_BarDetail_FillStyle_Total; -- Default to Total
			end
			UIDropDownMenu_SetText(displayText, RAB_BarDetail_FillStyle);
		end

		-- check for excludeNames not being nil or empty list
		if (RABui_Bars[id].excludeNames ~= nil) then
			--  join as comma separated list
			excludeNames = table.concat(RABui_Bars[id].excludeNames, ",");
		end
	end

	-- Initialize per-buffKey group/class restrictions
	RAB_BarDetail_SelectedGroups = {};
	RAB_BarDetail_SelectedClasses = {};
	
	if (id == 0) then
		-- New bar: initialize with defaults for first selected buff
		for _, buffKey in ipairs(RAB_BarDetail_SelectedBuffKeysOrder) do
			RAB_BarDetail_SelectedGroups[buffKey] = { true, true, true, true, true, true, true, true };
			RAB_BarDetail_SelectedClasses[buffKey] = { m = true, l = true, p = true, r = true, d = true, h = true, s = true, w = true, a = true };
		end
	else
		-- Editing existing bar: load per-buffKey restrictions
		local buffKeys = RABui_GetBuffKeysFromBar(id);
		local barGroups = RABui_Bars[id].groupsByBuff;
		local barClasses = RABui_Bars[id].classesByBuff;
		
		for _, buffKey in ipairs(buffKeys) do
			-- Load groups for this buffKey
			local bgr = (barGroups and barGroups[buffKey]) or groups or "";
			if (bgr == "" or bgr == nil) then
				RAB_BarDetail_SelectedGroups[buffKey] = { true, true, true, true, true, true, true, true };
			else
				RAB_BarDetail_SelectedGroups[buffKey] = { false, false, false, false, false, false, false, false };
				for grp in string.gfind(bgr, "(%d)") do
					RAB_BarDetail_SelectedGroups[buffKey][tonumber(grp)] = true;
				end
			end
			
			-- Load classes for this buffKey
			local bcl = (barClasses and barClasses[buffKey]) or classes or "";
			if (bcl == "" or bcl == nil) then
				RAB_BarDetail_SelectedClasses[buffKey] = { m = true, l = true, p = true, r = true, d = true, h = true, s = true, w = true, a = true };
			else
				RAB_BarDetail_SelectedClasses[buffKey] = { m = false, l = false, p = false, r = false, d = false, h = false, s = false, w = false, a = false };
				for grp in string.gfind(bcl, "(%a)") do
					RAB_BarDetail_SelectedClasses[buffKey][grp] = true;
				end
			end
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

function RABui_BarDetail_BarGroups_UpdateText()
	local numBuffKeys = table.getn(RAB_BarDetail_SelectedBuffKeysOrder);
	if (numBuffKeys == 0) then
		UIDropDownMenu_SetText(sRAB_Settings_BarDetail_GroupsAll, RAB_BarDetail_Groups);
		return;
	end
	
	if (numBuffKeys == 1) then
		-- Single query: show simple text
		local buffKey = RAB_BarDetail_SelectedBuffKeysOrder[1];
		if (not RAB_BarDetail_SelectedGroups[buffKey]) then
			UIDropDownMenu_SetText(sRAB_Settings_BarDetail_GroupsAll, RAB_BarDetail_Groups);
			return;
		end
		local sb, gc = "", 0;
		for i = 1, 8 do
			if (RAB_BarDetail_SelectedGroups[buffKey][i]) then
				sb = (sb == "" and "" or (sb .. ", ")) .. i;
				gc = gc + 1;
			end
		end
		if (gc == 8) then
			UIDropDownMenu_SetText(sRAB_Settings_BarDetail_GroupsAll, RAB_BarDetail_Groups);
		else
			UIDropDownMenu_SetText(string.format(sRAB_Settings_BarDetail_GroupsSome, sb), RAB_BarDetail_Groups);
		end
	else
		-- Multi query: show summary
		UIDropDownMenu_SetText("Groups (per buff)", RAB_BarDetail_Groups);
	end
end

function RABui_BarDetail_BarGroups_OnLoad()
	UIDropDownMenu_Initialize(this, RABui_BarDetail_BarGroups_Initialize);
	UIDropDownMenu_SetWidth(175, RAB_BarDetail_Groups);
end

function RABui_BarDetail_BarGroups_Initialize()
	local numBuffKeys = table.getn(RAB_BarDetail_SelectedBuffKeysOrder);
	
	if (numBuffKeys == 0) then
		return;
	end
	
	if (numBuffKeys == 1) then
		-- Single query: show simple layout
		local buffKey = RAB_BarDetail_SelectedBuffKeysOrder[1];
		if (not RAB_BarDetail_SelectedGroups[buffKey]) then
			return;
		end
		for i = 1, 8 do
			local groupNum = i;
			local capturedBuffKey = buffKey;
			UIDropDownMenu_AddButton({
				text = "Group " .. i,
				value = i,
				checked = (RAB_BarDetail_SelectedGroups[buffKey][i] == true),
				func = function()
					if (RAB_BarDetail_SelectedGroups[capturedBuffKey]) then
						RAB_BarDetail_SelectedGroups[capturedBuffKey][groupNum] = not RAB_BarDetail_SelectedGroups[capturedBuffKey][groupNum];
					end
					RABui_BarDetail_BarGroups_UpdateText();
				end,
				keepShownOnClick = 1,
				justifyH = "CENTER"
			});
		end
		local capturedBuffKey = buffKey;
		UIDropDownMenu_AddButton({
			text = sRAB_AddBar_ToggleAll,
			notCheckable = 1,
			func = function()
				if (RAB_BarDetail_SelectedGroups[capturedBuffKey]) then
					local newState = not RAB_BarDetail_SelectedGroups[capturedBuffKey][1];
					for i = 1, 8 do
						RAB_BarDetail_SelectedGroups[capturedBuffKey][i] = newState;
					end
				end
				RABui_BarDetail_BarGroups_UpdateText();
			end,
			justifyH = "CENTER"
		});
	else
		-- Multi query: show hierarchical menu
		if (UIDROPDOWNMENU_MENU_LEVEL == 1) then
			-- Level 1: Show buff names
			for _, buffKey in ipairs(RAB_BarDetail_SelectedBuffKeysOrder) do
				local buffData = RAB_Buffs[buffKey];
				if (buffData and RAB_BarDetail_SelectedGroups[buffKey]) then
					UIDropDownMenu_AddButton({
						text = buffData.name,
						value = buffKey,
						hasArrow = 1,
						notCheckable = 1
					});
				end
			end
		else
			-- Level 2: Show groups for selected buff
			local buffKey = UIDROPDOWNMENU_MENU_VALUE;
			if (buffKey and RAB_BarDetail_SelectedGroups[buffKey]) then
				for i = 1, 8 do
					local groupNum = i;
					local capturedBuffKey = buffKey;
					UIDropDownMenu_AddButton({
						text = "Group " .. i,
						value = i,
						checked = (RAB_BarDetail_SelectedGroups[buffKey][i] == true),
						func = function()
							if (RAB_BarDetail_SelectedGroups[capturedBuffKey]) then
								RAB_BarDetail_SelectedGroups[capturedBuffKey][groupNum] = not RAB_BarDetail_SelectedGroups[capturedBuffKey][groupNum];
							end
							RABui_BarDetail_BarGroups_UpdateText();
						end,
						keepShownOnClick = 1
					}, 2);
				end
				local capturedBuffKey = buffKey;
				UIDropDownMenu_AddButton({
					text = sRAB_AddBar_ToggleAll,
					notCheckable = 1,
					func = function()
						if (RAB_BarDetail_SelectedGroups[capturedBuffKey]) then
							local newState = not RAB_BarDetail_SelectedGroups[capturedBuffKey][1];
							for i = 1, 8 do
								RAB_BarDetail_SelectedGroups[capturedBuffKey][i] = newState;
							end
						end
						RABui_BarDetail_BarGroups_UpdateText();
					end
				}, 2);
			end
		end
	end
	DropDownList1.maxWidth = 200;
end

function RABui_BarDetail_BarClasses_UpdateText()
	local numBuffKeys = table.getn(RAB_BarDetail_SelectedBuffKeysOrder);
	if (numBuffKeys == 0) then
		UIDropDownMenu_SetText(sRAB_Settings_BarDetail_ClassesAll, RAB_BarDetail_Classes);
		return;
	end
	
	if (numBuffKeys == 1) then
		-- Single query: show simple text
		local buffKey = RAB_BarDetail_SelectedBuffKeysOrder[1];
		if (not RAB_BarDetail_SelectedClasses[buffKey]) then
			UIDropDownMenu_SetText(sRAB_Settings_BarDetail_ClassesAll, RAB_BarDetail_Classes);
			return;
		end
		
		local sb, gc, fgc = "", 0, 0;
		local ignoreString = "-";
		local buffData = RAB_Buffs[buffKey];
		
		if (buffData and buffData.ignoreClass ~= nil) then
			ignoreString = buffData.ignoreClass;
		end

		if buffData and buffData.class then
			local fullClass = buffData.class;
			local shortClass = RAB_ClassShort[fullClass];
			fgc = 1;
			if (RAB_BarDetail_SelectedClasses[buffKey][shortClass]) then
				sb = (sb == "" and "" or (sb .. ", ")) .. fullClass;
				gc = gc + 1;
			end
		else
			for key, val in RAB_ClassShort do
				if (string.find(ignoreString, val) == nil) then
					fgc = fgc + 1;
					if (RAB_BarDetail_SelectedClasses[buffKey][val]) then
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
	else
		-- Multi query: show summary
		UIDropDownMenu_SetText("Classes (per buff)", RAB_BarDetail_Classes);
	end
end

function RABui_BarDetail_BarClasses_OnLoad()
	UIDropDownMenu_Initialize(this, RABui_BarDetail_BarClasses_Initialize);
	UIDropDownMenu_SetWidth(175, RAB_BarDetail_Classes);
end

function RABui_BarDetail_BarClasses_Initialize()
	local numBuffKeys = table.getn(RAB_BarDetail_SelectedBuffKeysOrder);
	
	if (numBuffKeys == 0) then
		return;
	end
	
	if (numBuffKeys == 1) then
		-- Single query: show simple layout
		local buffKey = RAB_BarDetail_SelectedBuffKeysOrder[1];
		if (not RAB_BarDetail_SelectedClasses[buffKey]) then
			return;
		end
		local buffData = RAB_Buffs[buffKey];
		for key, val in RAB_ClassShort do
			local addClass = true;
			-- check for ignored classes
			if (buffData and buffData.ignoreClass and string.find(buffData.ignoreClass, val)) then
				addClass = nil;
			elseif buffData and buffData.class then
				-- ignore all classes except the one specified
				local shortClass = RAB_ClassShort[buffData.class];
				if shortClass and shortClass ~= val then
					addClass = nil;
				end
			end

			if addClass then
				local classVal = val;
				local capturedBuffKey = buffKey;
				UIDropDownMenu_AddButton({
					text = key .. "s",
					value = val,
					checked = (RAB_BarDetail_SelectedClasses[buffKey][val] == true),
					func = function()
						if (RAB_BarDetail_SelectedClasses[capturedBuffKey]) then
							RAB_BarDetail_SelectedClasses[capturedBuffKey][classVal] = not RAB_BarDetail_SelectedClasses[capturedBuffKey][classVal];
						end
						RABui_BarDetail_BarClasses_UpdateText();
					end,
					keepShownOnClick = 1,
					justifyH = "CENTER"
				});
			end
		end
		local capturedBuffKey = buffKey;
		UIDropDownMenu_AddButton({
			text = sRAB_AddBar_ToggleAll,
			func = function()
				if (RAB_BarDetail_SelectedClasses[capturedBuffKey]) then
					local newState = not RAB_BarDetail_SelectedClasses[capturedBuffKey]["m"];
					for k, v in RAB_BarDetail_SelectedClasses[capturedBuffKey] do
						RAB_BarDetail_SelectedClasses[capturedBuffKey][k] = newState;
					end
				end
				RABui_BarDetail_BarClasses_UpdateText();
			end,
			notCheckable = 1,
			justifyH = "CENTER"
		});
	else
		-- Multi query: show hierarchical menu
		if (UIDROPDOWNMENU_MENU_LEVEL == 1) then
			-- Level 1: Show buff names
			for _, buffKey in ipairs(RAB_BarDetail_SelectedBuffKeysOrder) do
				local buffData = RAB_Buffs[buffKey];
				if (buffData and RAB_BarDetail_SelectedClasses[buffKey]) then
					UIDropDownMenu_AddButton({
						text = buffData.name,
						value = buffKey,
						hasArrow = 1,
						notCheckable = 1
					});
				end
			end
		else
			-- Level 2: Show classes for selected buff
			local buffKey = UIDROPDOWNMENU_MENU_VALUE;
			if (buffKey and RAB_BarDetail_SelectedClasses[buffKey]) then
				local buffData = RAB_Buffs[buffKey];
				for key, val in RAB_ClassShort do
					local addClass = true;
					-- check for ignored classes
					if (buffData and buffData.ignoreClass and string.find(buffData.ignoreClass, val)) then
						addClass = nil;
					elseif buffData and buffData.class then
						-- ignore all classes except the one specified
						local shortClass = RAB_ClassShort[buffData.class];
						if shortClass and shortClass ~= val then
							addClass = nil;
						end
					end

					if addClass then
						local classVal = val;
						local capturedBuffKey = buffKey;
						UIDropDownMenu_AddButton({
							text = key .. "s",
							value = val,
							checked = (RAB_BarDetail_SelectedClasses[buffKey][val] == true),
							func = function()
								if (RAB_BarDetail_SelectedClasses[capturedBuffKey]) then
									RAB_BarDetail_SelectedClasses[capturedBuffKey][classVal] = not RAB_BarDetail_SelectedClasses[capturedBuffKey][classVal];
								end
								RABui_BarDetail_BarClasses_UpdateText();
							end,
							keepShownOnClick = 1
						}, 2);
					end
				end
				local capturedBuffKey = buffKey;
				UIDropDownMenu_AddButton({
					text = sRAB_AddBar_ToggleAll,
					notCheckable = 1,
					func = function()
						if (RAB_BarDetail_SelectedClasses[capturedBuffKey]) then
							local newState = not RAB_BarDetail_SelectedClasses[capturedBuffKey]["m"];
							for k, v in RAB_BarDetail_SelectedClasses[capturedBuffKey] do
								RAB_BarDetail_SelectedClasses[capturedBuffKey][k] = newState;
							end
						end
						RABui_BarDetail_BarClasses_UpdateText();
					end
				}, 2);
			end
		end
	end
	DropDownList1.maxWidth = 200;
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
			text = sRAB_Settings_BarDetail_FillStyle_Total,
			value = "Total",
			func = RABui_BarDetail_FillStyle_OnClick,
			checked = (RAB_BarDetail_FillStyleValue == "Total")
		});
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
	if (IsControlKeyDown()) then
		if (RAB_BarDetail_SelectedBuffKeys[this.value]) then
			RAB_BarDetail_SelectedBuffKeys[this.value] = nil;
			for i = table.getn(RAB_BarDetail_SelectedBuffKeysOrder), 1, -1 do
				if (RAB_BarDetail_SelectedBuffKeysOrder[i] == this.value) then
					table.remove(RAB_BarDetail_SelectedBuffKeysOrder, i);
					break;
				end
			end
			-- Remove group/class data for deselected buff
			RAB_BarDetail_SelectedGroups[this.value] = nil;
			RAB_BarDetail_SelectedClasses[this.value] = nil;
		else
			RAB_BarDetail_SelectedBuffKeys[this.value] = true;
			table.insert(RAB_BarDetail_SelectedBuffKeysOrder, this.value);
			-- Initialize group/class data for newly selected buff
			RAB_BarDetail_SelectedGroups[this.value] = { true, true, true, true, true, true, true, true };
			RAB_BarDetail_SelectedClasses[this.value] = { m = true, l = true, p = true, r = true, d = true, h = true, s = true, w = true, a = true };
		end
		if (table.getn(RAB_BarDetail_SelectedBuffKeys) > 0) then
			RAB_BarDetail_SelectedType = this.value;
		end
	else
		RAB_BarDetail_SelectedBuffKeys = { [this.value] = true };
		RAB_BarDetail_SelectedBuffKeysOrder = { this.value };
		RAB_BarDetail_SelectedType = this.value;
		-- Initialize group/class data for single selected buff
		RAB_BarDetail_SelectedGroups = { [this.value] = { true, true, true, true, true, true, true, true } };
		RAB_BarDetail_SelectedClasses = { [this.value] = { m = true, l = true, p = true, r = true, d = true, h = true, s = true, w = true, a = true } };
		ToggleDropDownMenu(1, nil, RAB_BarDetail_Type);
	end
	
	RABui_BarDetail_BuffType_UpdateText();
	RABui_BarDetail_BarGroups_UpdateText();
	RABui_BarDetail_BarClasses_UpdateText();
end

function RABui_BarDetail_BuffType_UpdateText()
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
	
	if (displayText == "" and RAB_BarDetail_SelectedType ~= nil and RAB_Buffs[RAB_BarDetail_SelectedType] ~= nil) then
		displayText = RAB_Buffs[RAB_BarDetail_SelectedType].name;
	end
	
	if (selectedCount > 1) then
		displayText = displayText .. " (" .. selectedCount .. ")";
	end
	
	UIDropDownMenu_SetText(displayText, RAB_BarDetail_Type);
end

function RABui_AddBar_Accept()
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
		-- Build per-buffKey group/class restrictions
		local groupsByBuff = {};
		local classesByBuff = {};
		local legacyGroups, legacyClasses = "", "";
		
		for idx, buffKey in ipairs(selectedBuffKeys) do
			local groups, classes = "", "";
			local alltrue = true;
			
			-- Build groups string for this buffKey
			if (RAB_BarDetail_SelectedGroups[buffKey]) then
				for i = 1, 8 do
					alltrue = alltrue and RAB_BarDetail_SelectedGroups[buffKey][i];
					if (RAB_BarDetail_SelectedGroups[buffKey][i] == true) then
						groups = (groups == "" and " " or groups) .. i;
					end
				end
				if (alltrue) then
					groups = "";
				end
			end
			
			-- Build classes string for this buffKey
			alltrue = true;
			if (RAB_BarDetail_SelectedClasses[buffKey]) then
				for key, val in RAB_ClassShort do
					alltrue = alltrue and RAB_BarDetail_SelectedClasses[buffKey][val];
					if (RAB_BarDetail_SelectedClasses[buffKey][val] == true) then
						classes = (classes == "" and " " or classes) .. val;
					end
				end
				if (alltrue) then
					classes = "";
				end
				
				-- Apply ignoreClass filter
				if (RAB_Buffs[buffKey] and RAB_Buffs[buffKey].ignoreClass ~= nil) then
					classes = string.gsub(classes, "[" .. RAB_Buffs[buffKey].ignoreClass .. "]", "");
				end
			end
			
			groupsByBuff[buffKey] = groups;
			classesByBuff[buffKey] = classes;
			
			-- Use first buff's restrictions for legacy fields
			if (idx == 1) then
				legacyGroups = groups;
				legacyClasses = classes;
			end
		end

		-- Get fillStyle from dropdown
		local fillStyle = RAB_BarDetail_FillStyleValue or "Segments";
		
		RABui_AddBar(
				selectedBuffKeys,
				RAB_BarDetail_SelfLimit:GetChecked(),
				legacyGroups,
				legacyClasses,
				RAB_BarDetail_Label:GetText(),
				11 - RAB_BarDetail_Priority:GetValue(),
				RAB_BarDetail_Output,
				RAB_BarDetail_PlayerExcludes:GetText(),
				RAB_BarDetail_UseOnClick:GetChecked(),
				fillStyle,
				groupsByBuff,
				classesByBuff);
	end
end

function split(str, delimiter)
	local result = {}
	for token in string.gfind(str, "([^" .. delimiter .. "]+)") do
		table.insert(result, token)
	end
	return result
end

function RABui_AddBar(buffKey, selfLimit, groups, classes, barlabel, barpriority, outputTarget, excludeNamesStr, useOnClick, fillStyle, groupsByBuff, classesByBuff)
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
					groups = groups,           -- Legacy: single groups string
					classes = classes,         -- Legacy: single classes string
					groupsByBuff = groupsByBuff,  -- Per-buffKey groups
					classesByBuff = classesByBuff, -- Per-buffKey classes
					color = { 1, 1, 1 },
					priority = barpriority,
					extralabel = "",
					out = outputTarget,
					excludeNames = excludeNames,
					useOnClick = useOnClick,
					fillStyle = fillStyle
				});
		RABui_SyncBars();
	else
		RABui_Bars[RAB_BarDetail_EditBarId].buffKey = primaryBuffKey;
		RABui_Bars[RAB_BarDetail_EditBarId].buffKeys = buffKeys;
		RABui_Bars[RAB_BarDetail_EditBarId].selfLimit = selfLimit;
		RABui_Bars[RAB_BarDetail_EditBarId].groups = groups;
		RABui_Bars[RAB_BarDetail_EditBarId].classes = classes;
		RABui_Bars[RAB_BarDetail_EditBarId].groupsByBuff = groupsByBuff;
		RABui_Bars[RAB_BarDetail_EditBarId].classesByBuff = classesByBuff;
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
	RABui_ccBarColorId = id;
	
	-- Store previous colors for undo
	local buffKeys = RABui_Bars[id].buffKeys or RABui_Bars[id].buffKey;
	if (type(buffKeys) == "string") then
		buffKeys = { buffKeys };
	end
	
	-- Store main color for previous value in color picker
	ColorPickerFrame.previousValues = RABui_Bars[id].color or { 1, 1, 1 };
	
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
	if (this.isMultiQuery and this.multiQueryFading and this.fadetime < now) then
		local alpha = nil;
		for queryIdx, fadeVal in ipairs(this.multiQueryFading) do
			if (fadeVal and fadeVal > 0) then
				if not alpha then
					this.fadetime = now + 0.04;
					alpha = cos(now * 180) * 0.2 + 0.5;
				end
				local tex = RABui_GetFrame(RABui_GetTextureName(barid, queryIdx));
				if tex then tex:SetAlpha(alpha); end
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