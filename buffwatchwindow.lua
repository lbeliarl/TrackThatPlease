local api = require("api")
local BuffList = require("TrackThatPlease/buff_helper")
local helpers = require("TrackThatPlease/util/helpers")

local BuffWatchWindow = {}
BuffWatchWindow.settings = {}
local serializedSettings = {}

-- UI elements
local buffSelectionWindow
local buffScrollList
local searchEditBox
local categoryDropdown
local trackTypeDropdown
local filteredCountLabel
local selectAllButton
local refreshBuffsCanvasCallback

-- Settings
local playerWatchedBuffs = {}
local targetWatchedBuffs = {}

local filteredBuffs = {}
local currentTrackType = 1  -- 1 for Player, 2 for Target
local isSelectedAll = false
local maxBuffsOptions = {"3", "5", "7", "9", "11", "13"}
local iconSpacingOptions = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "10"}
local iconSizeOptions = {"25", "28", "30", "32", "34", "36", "38", "40", "42", "44", "46", "48", "50", "52", "54", "56", "58"}
local fontSizeOptions = {"10", "11", "12", "13", "14", "15", "16", "18", "20", "22", "24", "26", "28", "30", "32", "34", "36"}

-- Scroll and pagination
local pageSize = 50
local categories = {"All buffs", "Watched buffs"}
local trackTypes = {"Player", "Target"}
local TRACK_TYPE_PLAYER = 1
local TRACK_TYPE_TARGET = 2
local CATEGORY_TYPE_ALL = 1
local CATEGORY_TYPE_WATCHED = 2
local currentCategory = CATEGORY_TYPE_WATCHED  -- as default

-- Helper functions for number serialization
local function SerializeNumber(num)
    return string.format("%.0f", num)
end

local function DeserializeNumber(str)
    return tonumber(str)
end

local function PrintBuffWatchWindowSettings()
    api.Log:Info("|cFF00FFFF====== serializedSettings ======|r")
    
    if not serializedSettings then
        api.Log:Info("|cFFFF6347serializedSettings is nil!|r")
    else
        for key, value in pairs(serializedSettings) do
            if type(value) == "table" then
                local count = #value
                api.Log:Info(string.format("|cFFFFD700%s|r: |cFF98FB98(array with %d items)|r", key, count))
                
                local shown = 0
                for k, v in pairs(value) do
                    if shown < 3 then
                        api.Log:Info(string.format("  |cFFDDA0DD[%s]|r = |cFFFFFFFF%s|r", tostring(k), tostring(v)))
                        shown = shown + 1
                    else
                        api.Log:Info("  |cFF87CEEB... (more items)|r")
                        break
                    end
                end
            else
                api.Log:Info(string.format("|cFFFFD700%s|r: |cFFFFFFFF%s|r", key, tostring(value)))
            end
        end
    end
    
    api.Log:Info("|cFF00FFFF=== End Debug Output ===|r")
end

--============================ ### Settings section ### ==============================--
function BuffWatchWindow.SetRefreshBuffsCanvasCallback(callback)
    refreshBuffsCanvasCallback = callback
end


function BuffWatchWindow.SaveSettings()
    -- Convert hash tables to serialized arrays for storage
    local serializedPlayerBuffs = {}
    local serializedTargetBuffs = {}
    
    for buffId, _ in pairs(playerWatchedBuffs) do
        table.insert(serializedPlayerBuffs, SerializeNumber(buffId))
    end
    
    for buffId, _ in pairs(targetWatchedBuffs) do
        table.insert(serializedTargetBuffs, SerializeNumber(buffId))
    end

    -- Save serialized data to disk
    serializedSettings.playerWatchedBuffs = serializedPlayerBuffs
    serializedSettings.targetWatchedBuffs = serializedTargetBuffs
    -- All others settings
    for key, value in pairs(BuffWatchWindow.settings) do
        serializedSettings[key] = value
    end
    
    --PrintBuffWatchWindowSettings()

    -- Update main canvas
    if refreshBuffsCanvasCallback then
        refreshBuffsCanvasCallback()
    end

    -- Safely Save settings to file
    pcall(function()
        api.SaveSettings()
    end)
end

local function loadSettings()
    api.Log:Err("Start Loading settings for TrackThatPlease")
    local defaultX = (api.Interface:GetScreenWidth() / 2) -42 -- Center button (42 is half of button width)
    local defaultSettings = {
        UIScale = api.Interface:GetUIScale(),
        fontSize = 12,
        targetBuffVerticalOffset = -38,
        playerBuffVerticalOffset = -38,
        iconSize = 34,
        iconSpacing = 3,
        maxBuffsShown = 5,
        debuffWarnTime = 2000,
        buffWarnTime = 3000,
        btnSettingsPos = { defaultX, 25 },
    }
--[[     -- Expected keys
    local allowedKeys = {}
    for key, _ in pairs(defaultSettings) do
        allowedKeys[key] = true
    end
    allowedKeys.playerWatchedBuffs = true
    allowedKeys.targetWatchedBuffs = true
    allowedKeys.enabled = true -- VERY IMPORTANT KEY ]]

    -- Load Settings
    serializedSettings = api.GetSettings("TrackThatPlease") or {}
    -- Clear unexpected keys
--[[     for key in pairs(serializedSettings) do
        if not allowedKeys[key] then
            serializedSettings[key] = nil
        end
    end ]]

    api.Log:Info("TrackThatPlease settings loaded successfully. Addon is: " .. (serializedSettings.enabled and " (enabled)" or " (disabled)"))

    local function ensureType(value, defaultValue)
        if type(defaultValue) == "number" then
            -- numbers
            return tonumber(value) or defaultValue
        elseif type(defaultValue) == "boolean" then
            -- boolean
            if type(value) == "boolean" then return value end
            if type(value) == "string" then return value == "true" end
            return defaultValue
        else
            -- string and tables
            return type(value) == type(defaultValue) and value or defaultValue
        end
    end
    
    -- Safe initialization of settings
    BuffWatchWindow.settings = {}

    for k, defaultValue in pairs(defaultSettings) do
        BuffWatchWindow.settings[k] = ensureType(serializedSettings[k], defaultValue)
    end
    
    -- Load player buffs from serialized data
    local savedPlayerBuffs = serializedSettings.playerWatchedBuffs or {}
    playerWatchedBuffs = {}
    for _, idString in ipairs(savedPlayerBuffs) do
        local buffId = DeserializeNumber(idString)
        if buffId then
            playerWatchedBuffs[buffId] = true
        end
    end
    
    -- Load target buffs from serialized data
    local savedTargetBuffs = serializedSettings.targetWatchedBuffs or {}
    targetWatchedBuffs = {}
    for _, idString in ipairs(savedTargetBuffs) do
        local buffId = DeserializeNumber(idString)
        if buffId then
            targetWatchedBuffs[buffId] = true
        end
    end

    BuffList.InitializeAllBuffs()
end
--============================ ### End ### ==============================--

--============================ ### Scroll list functions ### ==============================--
local function updateSelectAllButton()
    if selectAllButton then
        local watchedBuffs = currentTrackType == TRACK_TYPE_PLAYER and playerWatchedBuffs or targetWatchedBuffs
        
        -- Check if there are too many buffs (performance protection)
        local tooManyBuffs = #filteredBuffs > 200
        
        if tooManyBuffs then
            -- Disable button when too many buffs
            selectAllButton:Enable(false)
            selectAllButton:SetText("Too many buffs")
            selectAllButton:SetTextColor(0.5, 0.5, 0.5, 1) -- Gray text
        else
            -- Enable button and check selection state
            selectAllButton:Enable(true)
            selectAllButton:SetTextColor(unpack(FONT_COLOR.DEFAULT)) -- Normal text color
            
            local allSelected = false
            if #filteredBuffs > 0 then
                allSelected = true 
                for _, buff in ipairs(filteredBuffs) do
                    if not watchedBuffs[buff.id] then
                        allSelected = false
                        break
                    end
                end
            end
            
            selectAllButton:SetText(allSelected and "Unselect All" or "Select All")
        end
    end
end

-- Update the appearance of a buff icon
local function UpdateIconAppearance(subItem, buffId)
    local isWatched = false
    
    if currentTrackType == TRACK_TYPE_PLAYER then -- Player
        isWatched = BuffWatchWindow.IsPlayerBuffWatched(buffId)
    else -- Target
        isWatched = BuffWatchWindow.IsTargetBuffWatched(buffId)
    end
    
    if isWatched then
        subItem.checkmarkIcon:SetCoords(852,49,15,15)
    else
        subItem.checkmarkIcon:SetCoords(832,49,15,15)
    end
    subItem.checkmarkIcon:Show(true)
end

local function updatePageCount(totalItems)
    local maxPages = math.ceil(totalItems / pageSize)
    buffScrollList:SetPageByItemCount(totalItems, pageSize)
    buffScrollList.pageControl:SetPageCount(maxPages)
    if buffScrollList.curPageIdx and buffScrollList.curPageIdx > maxPages then
        buffScrollList:SetCurrentPage(maxPages)
    end
end

-- Fill buff data for the scroll list
local function fillBuffData(buffScrollList, pageIndex, searchText)
    local startingIndex = ((pageIndex - 1) * pageSize) + 1 
    buffScrollList:DeleteAllDatas()
    
    local count = 1
    filteredBuffs = {}
    
    local function addBuff(buff)
        if searchText == "" or string.find(buff.name:lower(), searchText:lower()) then
            table.insert(filteredBuffs, buff)
        end
    end

    if currentCategory == CATEGORY_TYPE_ALL then
        for _, buff in ipairs(BuffList.AllBuffs) do
            addBuff(buff)
        end
    elseif currentCategory == CATEGORY_TYPE_WATCHED then
        local watchedBuffs = currentTrackType == TRACK_TYPE_PLAYER and playerWatchedBuffs or targetWatchedBuffs
        for buffId, _ in pairs(watchedBuffs) do
            local buff = BuffList.AllBuffsIndex[buffId]
            if buff then
                addBuff(buff)
            end
        end
    end
    
    api.Log:Info("Filtered buffs currentCategory: " .. currentCategory)   
    updatePageCount(#filteredBuffs)
    -- Update count label
    if filteredCountLabel then
        filteredCountLabel:SetText(string.format("Count: %d", #filteredBuffs))
    end
    
    -- Update select all button text
    updateSelectAllButton()

    for i = startingIndex, math.min(startingIndex + pageSize - 1, #filteredBuffs) do
        local buff = filteredBuffs[i]
        if buff then
            local buffData = {
                id = buff.id,
                name = buff.name,
                iconPath = buff.iconPath,
                isViewData = true,
                isAbstention = false
            }
            buffScrollList:InsertData(count, 1, buffData, false)
            count = count + 1
        end
    end
end

-- Set data for each buff item in the list
local function DataSetFunc(subItem, data, setValue)
    if setValue then
        local str = string.format("[%d] %s", data.id, data.name)
        local id = data.id
        subItem.id = id
        subItem.textbox:SetText(str)
        F_SLOT.SetIconBackGround(subItem.subItemIcon, data.iconPath)
        UpdateIconAppearance(subItem, id)
    end
end

-- Create layout for each buff item in the list
local function LayoutSetFunc(frame, rowIndex, colIndex, subItem)
    -- Add background
    local background = subItem:CreateImageDrawable(TEXTURE_PATH.HUD, "background")
    background:SetCoords(453, 145, 230, 23)
    background:AddAnchor("TOPLEFT", subItem, -70, 4)
    background:AddAnchor("BOTTOMRIGHT", subItem, -70, 4)

    local subItemIcon = CreateItemIconButton("subItemIcon", subItem)
    subItemIcon:SetExtent(30, 30)
    subItemIcon:Show(true)
    F_SLOT.ApplySlotSkin(subItemIcon, subItemIcon.back, SLOT_STYLE.BUFF)
    subItemIcon:AddAnchor("LEFT", subItem, 5, 2)
    subItem.subItemIcon = subItemIcon

    subItem:SetExtent(450, 30)
    local textbox = subItem:CreateChildWidget("textbox", "textbox", 0, true)
    textbox:AddAnchor("TOPLEFT", subItem, 43, 2)
    textbox:AddAnchor("BOTTOMRIGHT", subItem, 0, 0)
    textbox.style:SetAlign(ALIGN.LEFT)
    textbox.style:SetFontSize(FONT_SIZE.LARGE)
    ApplyTextColor(textbox, FONT_COLOR.WHITE)
    subItem.textbox = textbox

    -- checkmark config
    local checkmarkIcon = subItem:CreateImageDrawable(TEXTURE_PATH.HUD, "overlay")
    checkmarkIcon:SetExtent(14, 14)
    checkmarkIcon:AddAnchor("TOPRIGHT", subItemIcon, 320, 10)
    checkmarkIcon:Show(true)
    subItem.checkmarkIcon = checkmarkIcon

    local clickOverlay = subItem:CreateChildWidget("button", "clickOverlay", 0, true)
    clickOverlay:AddAnchor("TOPLEFT", subItem, 0, 0)
    clickOverlay:AddAnchor("BOTTOMRIGHT", subItem, 0, 0)

    function clickOverlay:OnClick()
        local buffId = subItem.id
        BuffWatchWindow.ToggleBuffWatch(buffId)
        UpdateIconAppearance(subItem, buffId)
        
        if currentCategory == CATEGORY_TYPE_WATCHED then
            local isWatched = false
            if currentTrackType == TRACK_TYPE_PLAYER then
                isWatched = BuffWatchWindow.IsPlayerBuffWatched(buffId)
            else
                isWatched = BuffWatchWindow.IsTargetBuffWatched(buffId)
            end
            -- Remove from Whached list if unwatched
            if not isWatched then
                fillBuffData(buffScrollList, buffScrollList.curPageIdx or 1, searchEditBox:GetText())
            else
                updateSelectAllButton()
            end
        else
            updateSelectAllButton()
        end
        
        BuffWatchWindow.SaveSettings()
    end 
    clickOverlay:SetHandler("OnClick", clickOverlay.OnClick)
end
--============================ ### End ### ==============================--

--============================ ### BuffWatchWindow external functions ### ==============================--
-- Toggle a buff's watched status based on current tracking type
function BuffWatchWindow.ToggleBuffWatch(buffId)
    buffId = DeserializeNumber(SerializeNumber(buffId))
    
    if currentTrackType == TRACK_TYPE_PLAYER then -- Player
        BuffWatchWindow.TogglePlayerBuffWatch(buffId)
    else -- Target
        BuffWatchWindow.ToggleTargetBuffWatch(buffId)
    end
end

-- Toggle a player buff's watched status
function BuffWatchWindow.TogglePlayerBuffWatch(buffId)
    buffId = DeserializeNumber(SerializeNumber(buffId))
    
    if playerWatchedBuffs[buffId] then
        playerWatchedBuffs[buffId] = nil
    else
        playerWatchedBuffs[buffId] = true
    end
end

-- Toggle a target buff's watched status
function BuffWatchWindow.ToggleTargetBuffWatch(buffId)
    buffId = DeserializeNumber(SerializeNumber(buffId))
    
    if targetWatchedBuffs[buffId] then
        targetWatchedBuffs[buffId] = nil
    else
        targetWatchedBuffs[buffId] = true
    end
end

-- Check if a player buff is being watched
function BuffWatchWindow.IsPlayerBuffWatched(buffId)
    -- not needed
    --buffId = DeserializeNumber(SerializeNumber(buffId))
    return playerWatchedBuffs[buffId] == true
end

-- Check if a target buff is being watched
function BuffWatchWindow.IsTargetBuffWatched(buffId)
    -- not needed
    --buffId = DeserializeNumber(SerializeNumber(buffId))
    return targetWatchedBuffs[buffId] == true
end

-- Toggle the buff selection window visibility
function BuffWatchWindow.ToggleBuffSelectionWindow()
    if buffSelectionWindow then
        local isVisible = buffSelectionWindow:IsVisible()
        buffSelectionWindow:Show(not isVisible)
        if not isVisible then
            fillBuffData(buffScrollList, 1, searchEditBox:GetText())
        end
    else
        api.Log:Err("Buff selection window does not exist")
    end
end

-- Check if the buff selection window is visible
function BuffWatchWindow.IsWindowVisible()
    return buffSelectionWindow and buffSelectionWindow:IsVisible() or false
end

-- Initialize the BuffWatchWindow
function BuffWatchWindow.Initialize()
    -- Load settings
    loadSettings()

   -- Layout variables
    local columnGap = 25
    local columnWidth = 80
    local rowHeight = 55
    local leftMargin = 50
    local topMargin = 50
    -- Column positions
    local x1 = leftMargin                                    -- 40
    local x2 = leftMargin + columnWidth + columnGap          -- 160
    local x3 = leftMargin + (columnWidth + columnGap) * 2    -- 280
    local x4 = leftMargin + (columnWidth + columnGap) * 3    -- 400
    -- Row positions
    local y1 = topMargin                                            -- Row 1
    local y2 = topMargin + rowHeight                                -- Row 2: 70
    local y3 = topMargin + rowHeight * 2                            -- Row 3: 100
    local y4 = topMargin + rowHeight * 3                            -- Row 4: 130
    local y5 = topMargin + rowHeight * 4 + 40                  -- Scroll area: 200
    
    
    --================= Create the main window =================--
    buffSelectionWindow = api.Interface:CreateWindow("buffSelectorWindow", "Track List")
    buffSelectionWindow:SetWidth(500)
    buffSelectionWindow:SetHeight(750)
    buffSelectionWindow:AddAnchor("CENTER", "UIParent", "CENTER", 0, 0)

    local function createAnchor(x, y)
        return {
            anchor = "TOPLEFT",
            target = buffSelectionWindow,
            relativeAnchor = "TOPLEFT",
            x = x,
            y = y
        }
    end

    local anchors = {
        maxBuffsDropdown = createAnchor(x1, y1),
        fontSizeDropdown = createAnchor(x2, y1),
        iconSizeDropdown = createAnchor(x3, y1),
        iconSpacingDropdown = createAnchor(x4, y1),
        trackTypeDropdown = createAnchor(x1, y3),
        categoryDropdown = createAnchor(x2, y3),
        searchEditBox = createAnchor(x1, y4),
        selectAllButton = createAnchor(x1 + 260 + columnGap, y4 + 18),
        buffScrollList = createAnchor(leftMargin, y5),
    }

    --================= Create trackTypeDropdown =================--
    local trackTypeLabel
    trackTypeDropdown, trackTypeLabel = helpers.CreateDropdownWithLabel(
        buffSelectionWindow,
        anchors.trackTypeDropdown,
        "Track type:",
        0, -- Width will be set automatically
        trackTypes,
        currentTrackType, -- "Player" as default
        function(selectedIndex, selectedValue)
            local newTrackType = selectedIndex
            if newTrackType ~= currentTrackType then
                currentTrackType = newTrackType
                searchEditBox:SetText("")
                fillBuffData(buffScrollList, 1, searchEditBox:GetText())
            end
            if selectedIndex == 1 then -- Player
                trackTypeDropdown:SetAllTextColor({0.0, 0.4, 0.0, 0.9})
            elseif selectedIndex == 2 then -- Target
                trackTypeDropdown:SetAllTextColor({0.5, 0.0, 0.0, 0.9})
            end
        end
    )
    trackTypeDropdown:SetAllTextColor({0.0, 0.4, 0.0, 0.9})

    --================= Create category dropdownn =================--
    local categoryLabel
    categoryDropdown, categoryLabel = helpers.CreateDropdownWithLabel(
        buffSelectionWindow,
        anchors.categoryDropdown,
        "Buff category:",
        130,
        categories,
        currentCategory, -- "Watched Buffs" as default
        function(selectedIndex, selectedValue)
            local newCategory = selectedIndex
            if newCategory ~= currentCategory then
                api.Log:Info("categoryDropdown. category changed: " .. selectedIndex)
                currentCategory = newCategory
                searchEditBox:SetText("")  -- Clear search text when changing category
                fillBuffData(buffScrollList, 1, searchEditBox:GetText())
            end
            categoryDropdown:UpdateTextColor(selectedIndex)
        end
    )
    function categoryDropdown:UpdateTextColor(selectedIndex)
        if selectedIndex == 1 then -- All Buffs
             api.Log:Info("categoryDropdown. self:SetAllTextColor(). selectedIndex: " .. selectedIndex)
            self:SetAllTextColor()
        elseif selectedIndex == 2 then -- Watched Buffs
             api.Log:Info("categoryDropdown. self:SetAllTextColor(). selectedIndex: " .. selectedIndex)
            self:SetAllTextColor({0.1, 0.2, 0.4, 0.9})
        end
    end
    categoryDropdown.UpdateTextColor(currentCategory)
    

    --================= Create max buffs dropdown =================--
    local maxBuffsLabel
    local maxBuffsIndex = 2 
    -- Set from loaded settings
    for i, value in ipairs(maxBuffsOptions) do
        if tonumber(value) == BuffWatchWindow.settings.maxBuffsShown then
            maxBuffsIndex = i   
            break
        end
    end
    local maxBuffsDropdown, maxBuffsLabel = helpers.CreateDropdownWithLabel(
        buffSelectionWindow,
        anchors.maxBuffsDropdown,
        "Max buffs:",
        0,
        maxBuffsOptions,
        maxBuffsIndex,
        function(selectedIndex, selectedValue)
            BuffWatchWindow.settings.maxBuffsShown = tonumber(selectedValue)
            BuffWatchWindow.SaveSettings()
        end,
        "Maximum number of tracked buffs to display"
    )

    --================= Create Icon Size dropdown =================--
    local iconSizeIndex = 5 -- Default 34
    -- Set from loaded settings
    for i, value in ipairs(iconSizeOptions) do
        if tonumber(value) == BuffWatchWindow.settings.iconSize then
            iconSizeIndex = i   
            break
        end
    end
    local iconSizeDropdown, iconSizeLabel = helpers.CreateDropdownWithLabel(
        buffSelectionWindow,
        anchors.iconSizeDropdown,
        "Icon size:",
        0,
        iconSizeOptions,
        iconSizeIndex,
        function(selectedIndex, selectedValue)
            BuffWatchWindow.settings.iconSize = tonumber(selectedValue)
            BuffWatchWindow.SaveSettings()
        end
    )

    --================= Create Icon Size dropdown =================--
    local iconSpacingIndex = 3 -- Default 3
    -- Set from loaded settings
    for i, value in ipairs(iconSpacingOptions) do
        if tonumber(value) == BuffWatchWindow.settings.iconSpacing then
            iconSpacingIndex = i   
            break
        end
    end
    local iconSpacingDropdown, iconSpacingLabel = helpers.CreateDropdownWithLabel(
        buffSelectionWindow,
        anchors.iconSpacingDropdown,
        "Icon spacing:",
        0,
        iconSpacingOptions,
        iconSpacingIndex,
        function(selectedIndex, selectedValue)
            BuffWatchWindow.settings.iconSpacing = tonumber(selectedValue)
            BuffWatchWindow.SaveSettings()
        end
    )

    --================= Create Font Size dropdown =================--
    local fontSizeIndex = 4 -- Default 12
    -- Set from loaded settings
    for i, value in ipairs(fontSizeOptions) do
        if tonumber(value) == BuffWatchWindow.settings.fontSize then
            fontSizeIndex = i   
            break
        end
    end
    local fontSizeDropdown, fontSizeLabel = helpers.CreateDropdownWithLabel(
        buffSelectionWindow,
        anchors.fontSizeDropdown,
        "Text size:",
        0,
        fontSizeOptions,
        fontSizeIndex,
        function(selectedIndex, selectedValue)
            BuffWatchWindow.settings.fontSize = tonumber(selectedValue)
            BuffWatchWindow.SaveSettings()
        end,
        "Size of buff timer text in pixels"
    )


    --================= Create search box =================--
    local searchLabel
    searchEditBox, searchLabel = helpers.CreateTextEditWithLabel(
        buffSelectionWindow,
        anchors.searchEditBox,
        "Search:",
        260,        -- width
        24,         -- height
        "",         -- defaultText
        false,      -- isDigitOnly
        nil,        -- minValue
        nil,        -- maxValue
        function(value, text)
            if text ~= "" and currentCategory ~= CATEGORY_TYPE_ALL then
                currentCategory = CATEGORY_TYPE_ALL
                categoryDropdown:Select(currentCategory)
                categoryDropdown:UpdateTextColor(currentCategory)
            end
            fillBuffData(buffScrollList, 1, text)
        end
    )

    --================= Create select all button =================--
    selectAllButton = buffSelectionWindow:CreateChildWidget("button", "selectAllButton", 0, true)
    selectAllButton:SetText("Select All")
    local saAnchor = anchors.selectAllButton
    selectAllButton:AddAnchor(saAnchor.anchor, saAnchor.target, saAnchor.relativeAnchor, saAnchor.x, saAnchor.y)
    ApplyButtonSkin(selectAllButton, BUTTON_BASIC.DEFAULT)
    selectAllButton:SetExtent(78, 25)
    selectAllButton.style:SetFontSize(11)
    selectAllButton:SetTextColor(unpack(FONT_COLOR.DEFAULT))
    selectAllButton:SetHighlightTextColor(unpack(FONT_COLOR.DEFAULT))
    selectAllButton:SetPushedTextColor(unpack(FONT_COLOR.DEFAULT))
    selectAllButton:SetDisabledTextColor(unpack(FONT_COLOR.DEFAULT))

    function selectAllButton:OnClick()
        local watchedBuffs = currentTrackType == TRACK_TYPE_PLAYER and playerWatchedBuffs or targetWatchedBuffs

        local allSelected = #filteredBuffs > 0
        for _, buff in ipairs(filteredBuffs) do
            if not watchedBuffs[buff.id] then
                allSelected = false
                break
            end
        end

        for _, buff in ipairs(filteredBuffs) do
            if allSelected then
                watchedBuffs[buff.id] = nil  -- Unselect all
            else
                watchedBuffs[buff.id] = true  -- Select all
            end
        end

        --  "Watched Buffs" switch to  "All Buffs"
        if currentCategory == CATEGORY_TYPE_WATCHED and allSelected then
            currentCategory = CATEGORY_TYPE_ALL
            categoryDropdown:Select(currentCategory)
            categoryDropdown.UpdateTextColor(currentCategory)
        end
        
        fillBuffData(buffScrollList, 1, searchEditBox:GetText())
        
        BuffWatchWindow.SaveSettings()
    end
    selectAllButton:SetHandler("OnClick", selectAllButton.OnClick)
    

    --================= Create the buff scroll lis =================--
    buffScrollList = W_CTRL.CreatePageScrollListCtrl("buffScrollList", buffSelectionWindow)
    buffScrollList:SetWidth(380)
    local scrlAnchor = anchors.buffScrollList
    buffScrollList:AddAnchor(scrlAnchor.anchor, buffSelectionWindow, scrlAnchor.relativeAnchor, scrlAnchor.x, scrlAnchor.y)
    buffScrollList:AddAnchor("BOTTOMRIGHT", buffSelectionWindow, -4, -70)
    buffScrollList:InsertColumn("", 445, 0, DataSetFunc, nil, nil, LayoutSetFunc)
    buffScrollList:InsertRows(10, false)
    buffScrollList:SetColumnHeight(-3)

    -- Filter count label
    filteredCountLabel = buffSelectionWindow:CreateChildWidget("label", "filteredCountLabel", 0, true)
    filteredCountLabel:SetText("Count: 0")
    ApplyTextColor(filteredCountLabel, FONT_COLOR.BLACK)
    filteredCountLabel.style:SetAlign(ALIGN.LEFT)
    filteredCountLabel.style:SetFontSize(13)
    filteredCountLabel:AddAnchor("TOPLEFT", buffScrollList, "BOTTOMLEFT", 0, 10) 
    
    function buffScrollList:OnPageChangedProc(curPageIdx)
        fillBuffData(buffScrollList, curPageIdx, searchEditBox:GetText())
    end
    
    fillBuffData(buffScrollList, 1, "")
    buffSelectionWindow:Show(false)

    -- OnHide handler
    function buffSelectionWindow:OnHide()
        buffScrollList:DeleteAllDatas()
        BuffWatchWindow.SaveSettings()
    end 
    buffSelectionWindow:SetHandler("OnHide", buffSelectionWindow.OnHide)
end

-- Cleanup function for when the addon is unloaded
function BuffWatchWindow.Cleanup()
    -- clear callback
    refreshBuffsCanvasCallback = nil

    -- Save settings before cleanup to preserve user changes
    BuffWatchWindow.SaveSettings()
    
    -- Clean up main UI window
    if buffSelectionWindow then
        -- Hide window if it's currently visible
        if buffSelectionWindow:IsVisible() then
            buffSelectionWindow:Show(false)
        end
        buffSelectionWindow = nil
    end

    api.Log:Info("BuffWatchWindow: Cleanup completed successfully")
end
--============================ ### End ### ==============================--

return BuffWatchWindow