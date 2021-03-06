local ROW_HEIGHT = 16;
local LIST_FULL_HEIGHT = 405;
local FAVORITES_CATEGORY_ID = -1;

TradeSkillRecipeListMixin = {};

local LEARNED_TAB = 1;
local UNLEARNED_TAB = 2;

function TradeSkillRecipeListMixin:OnLoad()
	HybridScrollFrame_CreateButtons(self, "TradeSkillRowButtonTemplate", 0, 0);
	self.update = self.RefreshDisplay;
	self.stepSize = ROW_HEIGHT * 2;

	self.dataList = {};

	PanelTemplates_SetNumTabs(self, 2);
	UIDropDownMenu_Initialize(self.RecipeOptionsMenu, function(...) self:InitRecipeOptionsMenu(...) end, "MENU");

	self:OnLearnedTabClicked();
end

function TradeSkillRecipeListMixin:InitRecipeOptionsMenu(dropdown, level)
	local info = UIDropDownMenu_CreateInfo();
	info.notCheckable = true;
	info.disabled = nil;

	local isFavorite = self.contextMenuRecipeID and C_TradeSkillUI.IsRecipeFavorite(self.contextMenuRecipeID);

	if isFavorite then
		info.text = BATTLE_PET_UNFAVORITE;
		info.func = function() 
			C_TradeSkillUI.SetRecipeFavorite(self.contextMenuRecipeID, false);
		end
	else
		info.text = BATTLE_PET_FAVORITE;
		info.func = function() 
			C_TradeSkillUI.SetRecipeFavorite(self.contextMenuRecipeID, true);
		end
	end

	UIDropDownMenu_AddButton(info, level);
	info.disabled = nil;
	
	info.text = CANCEL
	info.func = nil
	UIDropDownMenu_AddButton(info, level)
end

function TradeSkillRecipeListMixin:OnUpdate()
	if self.pendingRefresh then
		if self.tradeSkillChanged then
			self.collapsedCategories = {};
			self.tradeSkillChanged = nil;
		end

		if not C_TradeSkillUI.IsTradeSkillReady() then
			wipe(self.dataList);
			self:SetSelectedRecipeID(nil);
			self:RefreshDisplay();
			return;
		end

		self:RebuildDataList();
		if self:VerifySelection() then
			self:RefreshDisplay();
		end
		self.pendingRefresh = nil;
	end
end

function TradeSkillRecipeListMixin:OnDataSourceChanging()
	wipe(self.dataList);
	self:SetSelectedRecipeID(nil);
	for i, tradeSkillButton in ipairs(self.buttons) do
		tradeSkillButton:Clear();
	end
	self:Refresh();
end

function TradeSkillRecipeListMixin:OnDataSourceChanged(tradeSkillChanged)
	self.selectedRecipeID = nil;
	self.tradeSkillChanged = self.tradeSkillChanged or tradeSkillChanged;

	local isNPCCrafting = C_TradeSkillUI.IsNPCCrafting();

	self:OnLearnedTabClicked();

	self.LearnedTab:SetShown(not isNPCCrafting);
	self.UnlearnedTab:SetShown(not isNPCCrafting);

	self:Refresh();
end

function TradeSkillRecipeListMixin:OnHeaderButtonClicked(categoryButton, categoryInfo, mouseButton)
	self:SetCategoryCollapsed(categoryInfo.categoryID, not self:IsCategoryCollapsed(categoryInfo.categoryID));
end

function TradeSkillRecipeListMixin:SetCategoryCollapsed(categoryID, collapsed)
	if self.collapsedCategories[categoryID] ~= collapsed then
		self.collapsedCategories[categoryID] = collapsed;
		self:Refresh();
	end
end

function TradeSkillRecipeListMixin:IsCategoryCollapsed(categoryID)
	return self.collapsedCategories[categoryID] == true;
end

function TradeSkillRecipeListMixin:OnRecipeButtonClicked(recipeButton, recipeInfo, mouseButton)
	if mouseButton == "LeftButton" then
		self:SetSelectedRecipeID(recipeInfo.recipeID);
	elseif mouseButton == "RightButton" then
		if recipeInfo.learned and not C_TradeSkillUI.IsTradeSkillGuild() and not C_TradeSkillUI.IsNPCCrafting() and not C_TradeSkillUI.IsTradeSkillLinked() then
			self.contextMenuRecipeID = recipeInfo.recipeID;
			ToggleDropDownMenu(1, nil, self.RecipeOptionsMenu, recipeButton, 0, 0);
		end
	end
end

function TradeSkillRecipeListMixin:OnLearnedTabClicked()
	PanelTemplates_SetTab(self, LEARNED_TAB);
	C_TradeSkillUI.SetOnlyShowLearnedRecipes(true);
	C_TradeSkillUI.SetOnlyShowUnlearnedRecipes(false);
end

function TradeSkillRecipeListMixin:OnUnlearnedTabClicked()
	PanelTemplates_SetTab(self, UNLEARNED_TAB);
	C_TradeSkillUI.SetOnlyShowLearnedRecipes(false);
	C_TradeSkillUI.SetOnlyShowUnlearnedRecipes(true);
end

function TradeSkillRecipeListMixin:Refresh()
	self.pendingRefresh = true;
end

function TradeSkillRecipeListMixin:SetRecipeChangedCallback(recipeChangedCallback)
	self.recipeChangedCallback = recipeChangedCallback;
end

function TradeSkillRecipeListMixin:FindBestStarRankLinksForRecipe(recipeInfo)
	local startingRecipeInfo = recipeInfo;
	while startingRecipeInfo.previousRecipeInfo do
		startingRecipeInfo = startingRecipeInfo.previousRecipeInfo;
	end

	local bestRecipeInfo = startingRecipeInfo;
	while bestRecipeInfo.nextRecipeInfo and bestRecipeInfo.nextRecipeInfo.learned do
		bestRecipeInfo = bestRecipeInfo.nextRecipeInfo;
	end

	return bestRecipeInfo;
end

local function IsFavoriteRecipesCategoriesVisible(recipeInfo)
	local categoryData = C_TradeSkillUI.GetCategoryInfo(recipeInfo.categoryID);
	if categoryData.enabled then
		if categoryData.parentCategoryID then
			local parentCategoryData = C_TradeSkillUI.GetCategoryInfo(recipeInfo.categoryID);
			return parentCategoryData.enabled;
		end
		return true;
	end
	return false;
end

function TradeSkillRecipeListMixin:RebuildDataList()
	wipe(self.dataList);

	self.recipeIDs = C_TradeSkillUI.GetFilteredRecipeIDs(self.recipeIDs);
	local currentCategoryID, currentParentCategoryID;
	local isCurrentCategoryEnabled, isCurrentParentCategoryEnabled = true, true;
	local favoritesIndex = nil;
	local starRankLinks = {};

	for i, recipeID in ipairs(self.recipeIDs) do
		if not starRankLinks[recipeID] then
			local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID);
			TradeSkillFrame_GenerateRankLinks(recipeInfo, starRankLinks);

			recipeInfo = self:FindBestStarRankLinksForRecipe(recipeInfo);

			if recipeInfo.favorite then
				if IsFavoriteRecipesCategoriesVisible(recipeInfo) then
					if not favoritesIndex then
						-- Insert the special favorites category header
						favoritesIndex = 1;
						table.insert(self.dataList, favoritesIndex, { type = "header", numIndents = 0, name = FAVORITES, categoryID = FAVORITES_CATEGORY_ID, });
						favoritesIndex = favoritesIndex + 1; -- Start inserting new favorites here
					end
					if not self:IsCategoryCollapsed(FAVORITES_CATEGORY_ID) then
						recipeInfo.numIndents = 0; -- No subcategories under favorites, force no indents

						table.insert(self.dataList, favoritesIndex, recipeInfo);
						favoritesIndex = favoritesIndex + 1;
					end
				end
			else
				if recipeInfo.categoryID ~= currentCategoryID then
					local categoryData = C_TradeSkillUI.GetCategoryInfo(recipeInfo.categoryID);
					isCurrentCategoryEnabled = categoryData.enabled;

					if categoryData.parentCategoryID ~= currentParentCategoryID then
						currentParentCategoryID = categoryData.parentCategoryID;
						if currentParentCategoryID then
							local parentCategoryData = C_TradeSkillUI.GetCategoryInfo(currentParentCategoryID);
							isCurrentParentCategoryEnabled = parentCategoryData.enabled;
							if isCurrentParentCategoryEnabled then
								table.insert(self.dataList, parentCategoryData);
							end
						else
							isCurrentParentCategoryEnabled = true;
						end
					end

					if isCurrentCategoryEnabled and isCurrentParentCategoryEnabled and (not currentParentCategoryID or not self:IsCategoryCollapsed(currentParentCategoryID)) then
						table.insert(self.dataList, categoryData);
						currentCategoryID = recipeInfo.categoryID;
					end
				end

				if isCurrentCategoryEnabled and isCurrentParentCategoryEnabled and (not currentParentCategoryID or not self:IsCategoryCollapsed(currentParentCategoryID)) and not self:IsCategoryCollapsed(currentCategoryID) then
					table.insert(self.dataList, recipeInfo);
				end
			end
		end
	end
end

function TradeSkillRecipeListMixin:VerifySelection()
	local firstVisibleRecipeID = nil;

	if self.selectedRecipeID then
		for i, listData in ipairs(self.dataList) do
			if listData.type == "recipe" then
				if self.selectedRecipeID == listData.recipeID then
					-- Recipe is still valid, do nothing
					return true;
				end

				if not firstVisibleRecipeID then
					firstVisibleRecipeID = listData.recipeID;
				end

				local currentRecipeInfo = listData.previousRecipeInfo;
				while currentRecipeInfo do
					if self.selectedRecipeID == currentRecipeInfo.recipeID then
						-- Recipe rank changed, switch to the new rank
						return not self:SetSelectedRecipeID(listData.recipeID);
					end
					currentRecipeInfo = currentRecipeInfo.previousRecipeInfo;
				end

				local currentRecipeInfo = listData.nextRecipeInfo;
				while currentRecipeInfo do
					if self.selectedRecipeID == currentRecipeInfo.recipeID then
						-- Recipe rank changed, switch to the new rank
						return not self:SetSelectedRecipeID(listData.recipeID);
					end
					currentRecipeInfo = currentRecipeInfo.nextRecipeInfo;
				end
			end
		end
	else
		for i, listData in ipairs(self.dataList) do
			if listData.type == "recipe" then
				firstVisibleRecipeID = listData.recipeID;
				break;
			end
		end
	end

	-- Couldn't find recipe, probably filtered
	-- Try using the first visible recipe
	return not self:SetSelectedRecipeID(firstVisibleRecipeID);
end

local function GetUnfilteredSubCategoryName(categoryID, ...)
	local areAllUnfiltered = true;
	for i = 1, select("#", ...) do
		local subCategoryID = select(i, ...);
		if C_TradeSkillUI.IsRecipeCategoryFiltered(categoryID, subCategoryID) then
			areAllUnfiltered = false;
			break;
		end
	end

	if areAllUnfiltered then
		return nil;
	end

	for i = 1, select("#", ...) do
		local subCategoryID = select(i, ...);
		if not C_TradeSkillUI.IsRecipeCategoryFiltered(categoryID, subCategoryID) then
			local subCategoryData = C_TradeSkillUI.GetCategoryInfo(subCategoryID);
			return subCategoryData.name;
		end
	end
end

local function GetUnfilteredCategoryName(...)
	-- Try subCategories first
	for i = 1, select("#", ...) do
		local categoryID = select(i, ...);
		local subCategoryName = GetUnfilteredSubCategoryName(categoryID, C_TradeSkillUI.GetSubCategories(categoryID));
		if subCategoryName then
			return subCategoryName;
		end
	end

	for i = 1, select("#", ...) do
		local categoryID = select(i, ...);
		if not C_TradeSkillUI.IsRecipeCategoryFiltered(categoryID) then
			local categoryData = C_TradeSkillUI.GetCategoryInfo(categoryID);
			return categoryData.name;
		end
	end

	return nil;
end

local function GetUnfilteredInventorySlotName(...)
	for i = 1, select("#", ...) do
		if not C_TradeSkillUI.IsInventorySlotFiltered(i) then
			local inventorySlot = select(i, ...);
			return inventorySlot;
		end
	end
	return nil;
end

function TradeSkillRecipeListMixin:UpdateFilterBar()
	local filters = nil;
	if C_TradeSkillUI.GetOnlyShowMakeableRecipes() then
		filters = filters or {};
		filters[#filters + 1] = CRAFT_IS_MAKEABLE;
	end
	
	if C_TradeSkillUI.GetOnlyShowSkillUpRecipes() then 
		filters = filters or {};
		filters[#filters + 1] = TRADESKILL_FILTER_HAS_SKILL_UP;
	end

	if C_TradeSkillUI.AnyRecipeCategoriesFiltered() then
		local categoryName = GetUnfilteredCategoryName(C_TradeSkillUI.GetCategories());
		if categoryName then
			filters = filters or {};
			filters[#filters + 1] = categoryName;
		end
	end
	
	if C_TradeSkillUI.AreAnyInventorySlotsFiltered() then
		local inventorySlot = GetUnfilteredInventorySlotName(C_TradeSkillUI.GetAllFilterableInventorySlots());
		if inventorySlot then
			filters = filters or {};
			filters[#filters + 1] = inventorySlot;
		end
	end

	if C_TradeSkillUI.AreAnyRecipeSourceTypesFiltered() then
		local numSources = C_PetJournal.GetNumPetSources();
		for i = 1, numSources do
			if C_TradeSkillUI.IsAnyRecipeFromSource(i) then
				if not C_TradeSkillUI.IsRecipeSourceTypeFiltered(i) then
					filters = filters or {};
					filters[#filters + 1] = _G["BATTLE_PET_SOURCE_"..i];
				end
			end
		end
	end

	if filters == nil then
		self.FilterBar:Hide();
		self:SetHeight(LIST_FULL_HEIGHT);

		self:SetPoint("TOPLEFT", 7, -83);
		self.LearnedTab:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 18, 3);
		self.scrollBar:SetPoint("TOPLEFT", self, "TOPRIGHT", 1, -14);
	else
		self:SetHeight(LIST_FULL_HEIGHT - ROW_HEIGHT);
		self.FilterBar:Show();

		self:SetPoint("TOPLEFT", 7, -83 - ROW_HEIGHT);
		self.LearnedTab:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 18, 3 + ROW_HEIGHT);
		self.scrollBar:SetPoint("TOPLEFT", self, "TOPRIGHT", 1, -14 + ROW_HEIGHT);

		self.FilterBar.Text:SetFormattedText("%s: %s", FILTER, table.concat(filters, PLAYER_LIST_DELIMITER));
	end
end

function TradeSkillRecipeListMixin:RefreshDisplay()
	self:UpdateFilterBar();

	local offset = HybridScrollFrame_GetOffset(self);

	for i, tradeSkillButton in ipairs(self.buttons) do
		local dataIndex = offset + i;
		local tradeSkillInfo = self.dataList[dataIndex];
		if tradeSkillInfo then
			if tradeSkillInfo.type == "header" or tradeSkillInfo.type == "subheader" then
				tradeSkillInfo.collapsed = self:IsCategoryCollapsed(tradeSkillInfo.categoryID);
			end
					
			tradeSkillButton:SetUp(tradeSkillInfo);

			if tradeSkillInfo.type == "recipe" then
				tradeSkillButton:SetSelected(self.selectedRecipeID == tradeSkillInfo.recipeID);
			end
		else
			tradeSkillButton:Clear();
		end
	end

	HybridScrollFrame_Update(self, #self.dataList * ROW_HEIGHT, 405);
end

function TradeSkillRecipeListMixin:SetSelectedRecipeID(recipeID)
	if self.selectedRecipeID ~= recipeID then
		self.selectedRecipeID = recipeID;
		self:RefreshDisplay();
		if self.recipeChangedCallback then
			self.recipeChangedCallback(recipeID);
		end
		return true;
	end
	return false;
end

function TradeSkillRecipeListMixin:GetSelectedRecipeID()
	return self.selectedRecipeID;
end