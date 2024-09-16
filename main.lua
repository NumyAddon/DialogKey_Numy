local name = ...
--- @class DialogKeyNS
local ns = select(2, ...)

local GetMouseFoci = GetMouseFoci or function() return { GetMouseFocus() } end
local GetFrameMetatable = _G.GetFrameMetatable or function() return getmetatable(CreateFrame('FRAME')) end

_G.DialogKeyNS = ns -- expose ourselves to the world :)

--- @class DialogKey: AceAddon, AceEvent-3.0, AceHook-3.0
local DialogKey = LibStub("AceAddon-3.0"):NewAddon(name, "AceEvent-3.0", "AceHook-3.0")
ns.Core = DialogKey

local defaultPopupBlacklist = { -- If a confirmation dialog contains one of these strings, don't accept it
    --"Are you sure you want to go back to Shal'Aran?", -- Withered Training Scenario -- why exclude this?
    --"Are you sure you want to return to your current timeline?", -- Leave Chromie Time -- why exclude this?
    --"You will be removed from Timewalking Campaigns once you use this scroll.", -- "A New Adventure Awaits" Chromie Time scroll -- why exclude this?
    AREA_SPIRIT_HEAL, -- Prevents cancelling the resurrection
    TOO_MANY_LUA_ERRORS,
    END_BOUND_TRADEABLE,
    ADDON_ACTION_FORBIDDEN,
}

local function callFrameMethod(frame, method, ...)
    local functionRef = frame[method] or GetFrameMetatable().__index[method] or nop;
    local ok, result = pcall(functionRef, frame, ...);

    return ok and result or false
end
--- @return string?
local function getFrameName(frame)
    return callFrameMethod(frame, 'GetDebugName') ---@diagnostic disable-line: return-type-mismatch
        or callFrameMethod(frame, 'GetName')
end
---@return Frame?
function DialogKey:GetFrameByName(frameName)
    local frameTable = _G;

    for keyName in string.gmatch(frameName, "([^.]+)") do
        if not frameTable[keyName] then return nil; end

        frameTable = frameTable[keyName];
    end

    return frameTable;
end

DialogKey.playerChoiceButtons = {}
DialogKey.handledCustomFrames = {}
DialogKey.ignoreCheckCustomFrames = false
DialogKey.proxyFrames = {}
DialogKey.proxyFrameNamePrefix = "DialogKeyNumy_ProxyFrame_"
DialogKey.proxyFrameIndex = 0
DialogKey.activeOverrideBindings = {}

function DialogKey:OnInitialize()
    DialogKeyNumyDB = DialogKeyNumyDB or {}
    self.db = DialogKeyNumyDB
    for k, v in pairs(ns.defaultOptions) do
        if self.db[k] == nil then self.db[k] = v end
    end

    self:InitGlowFrame()

    self:RegisterEvent("GOSSIP_SHOW")
    self:RegisterEvent("QUEST_GREETING")
    self:RegisterEvent("QUEST_COMPLETE")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("ADDON_LOADED")

    self:SecureHook("CreateFrame", "CheckCustomFrames")

    self.frame = CreateFrame("Frame", nil, UIParent)
    self.frame:SetScript("OnKeyDown", function(_, ...) self:HandleKey(...) end)
    self.frame:SetFrameStrata("TOOLTIP") -- Ensure we receive keyboard events first
    self.frame:EnableKeyboard(true)
    self.frame:SetPropagateKeyboardInput(true)

    for i = 1, 4 do
        self:SecureHookScript(_G["StaticPopup" .. i], "OnShow", "OnPopupShow")
        self:SecureHookScript(_G["StaticPopup" .. i], "OnUpdate", "OnPopupUpdate")
        self:SecureHookScript(_G["StaticPopup" .. i], "OnHide", "OnPopupHide")
    end

    self:SecureHook("QuestInfoItem_OnClick", "SelectItemReward")
    self:SecureHook(GossipFrame, "Update", "OnGossipFrameUpdate")

    -- interfaceOptions defined in `options.lua`
    LibStub("AceConfig-3.0"):RegisterOptionsTable(name, ns.interfaceOptions)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(name)

    _G.SLASH_DIALOGKEY1 = '/dialogkey'
    _G.SLASH_DIALOGKEY2 = '/dkey'
    _G.SLASH_DIALOGKEY3 = '/dk'
    SlashCmdList['DIALOGKEY'] = function(msg)
        local func, args = strsplit(" ", msg, 2)
        if func == 'add' then
            self:AddFrame(args)
        elseif func == 'remove' then
            self:RemoveFrame(args)
        else
            Settings.OpenToCategory(name)
        end
    end
end

function DialogKey:ADDON_LOADED(_, addon)
    if addon == 'Blizzard_PlayerChoice' then
        self:SecureHook(PlayerChoiceFrame, "TryShow", "OnPlayerChoiceShow")
        self:SecureHookScript(PlayerChoiceFrame, "OnHide", "OnPlayerChoiceHide")
    end
    self:CheckCustomFrames()
end

function DialogKey:QUEST_COMPLETE()
    self.itemChoice = (GetNumQuestChoices() > 1 and -1 or 1)
end

function DialogKey:GOSSIP_SHOW()
    RunNextFrame(function() self:EnumerateGossips(true) end)
end

function DialogKey:QUEST_GREETING()
    RunNextFrame(function() self:EnumerateGossips(false) end)
end

function DialogKey:PLAYER_REGEN_DISABLED()
    -- Disable DialogKey fully upon entering combat
    self.frame:SetPropagateKeyboardInput(true)
    self:ClearOverrideBindings()
end

function DialogKey:InitGlowFrame()
    self.glowFrame = CreateFrame("Frame", nil, UIParent)
    self.glowFrame:SetPoint("CENTER", 0, 0)
    self.glowFrame:SetFrameStrata("TOOLTIP")
    self.glowFrame:SetSize(50,50)
    self.glowFrame:SetScript("OnUpdate", function(...) self:GlowFrameUpdate(...) end)
    self.glowFrame:Hide()
    self.glowFrame.tex = self.glowFrame:CreateTexture()
    self.glowFrame.tex:SetAllPoints()
    self.glowFrame.tex:SetColorTexture(1,1,0,0.5)
end

function DialogKey:OnPlayerChoiceShow()
    if not self.db.handlePlayerChoice then return end
    local frame = PlayerChoiceFrame;
    if not frame or not frame:IsVisible() then return end

    local choiceInfo = C_PlayerChoice.GetCurrentPlayerChoiceInfo()
    if not choiceInfo then return end
    local buttons = {}
    local i = 0
    for _, option in ipairs(choiceInfo.options) do
        for _, button in ipairs(option.buttons) do
            i = i + 1
            buttons[button.id] = i
        end
    end

    for option in frame.optionPools:EnumerateActive() do
        for button in option.buttons.buttonPool:EnumerateActive() do
            local key = buttons[button.buttonID]
            if self.db.numKeysForPlayerChoice then
                button.Text:SetText(key .. ' ' .. button.Text:GetText())
            end
            self.playerChoiceButtons[key] = button
        end
    end
end

function DialogKey:OnPlayerChoiceHide()
    self.playerChoiceButtons = {}
end

-- Prefix list of GossipFrame options with 1., 2., 3. etc.
--- @param gossipFrame GossipFrame
function DialogKey:OnGossipFrameUpdate(gossipFrame)
    if not self.db.numKeysForGossip then return end
    local scrollbox = gossipFrame.GreetingPanel.ScrollBox

    local n = 1
    for _, frame in scrollbox:EnumerateFrames() do
        local data = frame.GetElementData and frame.GetElementData()
        local tag
        if data.buttonType == GOSSIP_BUTTON_TYPE_OPTION then
            tag = "name"
        elseif data.buttonType == GOSSIP_BUTTON_TYPE_ACTIVE_QUEST or data.buttonType == GOSSIP_BUTTON_TYPE_AVAILABLE_QUEST then
            tag = "title"
        end
        if tag then
            frame:SetText((n % 10) .. ". " .. data.info[tag])
            frame:SetHeight(frame:GetFontString():GetHeight() + 2)
            n = n + 1
        end
        if n > 10 then break end
    end
    scrollbox:OnSizeChanged()
end

--- @return StaticPopupTemplate|nil
function DialogKey:GetFirstVisiblePopup()
    for i = 1, 4 do
        local popup = _G["StaticPopup"..i]
        if popup and popup:IsVisible() then
            return popup
        end
    end
end

--- @param frame Button
function DialogKey:GuardDisabled(frame)
    if not self.db.ignoreDisabledButtons then return true; end

    return frame:IsEnabled() and frame:IsMouseClickEnabled();
end

--- @return Button|nil
function DialogKey:GetFirstVisibleCustomFrame()
    for frameName, _ in pairs(self.db.customFrames) do
        local frame = self:GetFrameByName(frameName)
        if frame and frame:IsVisible() and frame:IsObjectType('Button') and self:GuardDisabled(frame) then
            return frame ---@diagnostic disable-line: return-type-mismatch
        end
    end
end

--- @return Button|nil
function DialogKey:GetFirstVisibleCraftingOrderFrame()
    if not self.db.handleCraftingOrders then return; end
    local frames = {
        "ProfessionsFrame.OrdersPage.OrderView.OrderInfo.StartOrderButton",
        "ProfessionsFrame.OrdersPage.OrderView.CreateButton",
        "ProfessionsFrame.OrdersPage.OrderView.CompleteOrderButton",
    };
    for _, frameName in ipairs(frames) do
        --- @type Button?
        local frame = self:GetFrameByName(frameName) ---@diagnostic disable-line: assign-type-mismatch
        if frame and frame:IsVisible() and self:GuardDisabled(frame) then
            return frame
        end
    end
end

function DialogKey:ShouldIgnoreInput()
    if InCombatLockdown() then return true end
    self.frame:SetPropagateKeyboardInput(true)

    if self.db.ignoreWithModifier and (IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()) then return true end
    -- Ignore input while typing, unless at the Send Mail confirmation while typing into it!
    local focus = GetCurrentKeyBoardFocus()
    if focus and not (self:GetFirstVisiblePopup() and (focus:GetName() == "SendMailNameEditBox" or focus:GetName() == "SendMailSubjectEditBox")) then return true end

    if
        -- Ignore input if there's nothing for DialogKey to click
        not GossipFrame:IsVisible() and not QuestFrame:IsVisible() and not self:GetFirstVisiblePopup()
        -- Ignore input if the Auction House sell frame is not open
        and (not AuctionHouseFrame or not AuctionHouseFrame:IsVisible())
        and not self:GetFirstVisibleCraftingOrderFrame()
        -- Ignore input if no custom frames are visible
        and not self:GetFirstVisibleCustomFrame()
        -- Ignore input if no player choice buttons are visible
        and not next(self.playerChoiceButtons)
    then
        return true
    end

    return false
end

-- Primary functions --

-- Takes a global string like '%s has challenged you to a duel.' and converts it to a format suitable for string.find
local summon_match = CONFIRM_SUMMON:gsub("%%d", ".+"):format(".+", ".+", ".+")
local duel_match = DUEL_REQUESTED:format(".+")
local resurrect_match = RESURRECT_REQUEST_NO_SICKNESS:format(".+")
local groupinvite_match = INVITATION:format(".+")

--- @param popupFrame StaticPopupTemplate # One of the StaticPopup1-4 frames
--- @return Frame|nil|false # The button to click, nil if no button should be clicked, false if the text is empty and should be checked again later
function DialogKey:GetPopupButton(popupFrame)
    local text = popupFrame.text:GetText()

    -- Some popups have no text when they initially show, and instead get text applied OnUpdate (summons are an example)
    -- False is returned in that case, so we know to keep checking OnUpdate
    if not text or text == " " or text == "" then return false end

    -- Don't accept group invitations if the option is enabled
    if self.db.dontAcceptInvite and text:find(groupinvite_match) then return end

    -- Don't accept summons/duels/resurrects if the options are enabled
    if self.db.dontClickSummons and text:find(summon_match) then return end
    if self.db.dontClickDuels and text:find(duel_match) then return end

    -- If resurrect dialog has three buttons, and the option is enabled, use the middle one instead of the first one (soulstone, etc.)
    -- Located before resurrect/release checks/returns so it happens even if you have releases/revives disabled
    -- Also, Check if Button2 is visible instead of Button3 since Recap is always 3; 2 is hidden if you can't soulstone rez

    -- the ordering here means that a revive will be taken before a battle rez before a release.
    -- if revives are disabled but soulstone battlerezzes *aren't*, nothing will happen if both are available!
    local canRelease = popupFrame.button1:GetText() == DEATH_RELEASE
    if self.db.useSoulstoneRez and canRelease and popupFrame.button2:IsVisible() then
        return popupFrame.button2
    end

    if self.db.dontClickRevives and (text == RECOVER_CORPSE or text:find(resurrect_match)) then return end
    if self.db.dontClickReleases and canRelease then return end

    -- Ignore blacklisted popup dialogs!
    local lowerCaseText = text:lower()
    for blacklistText, _ in pairs(self.db.dialogBlacklist) do
        -- Prepend non-alphabetical characters with '%' to escape them
        blacklistText = blacklistText:gsub("%W", "%%%0"):gsub("%%%%s", ".+")
        if lowerCaseText:find(blacklistText:lower()) then return end
    end

    for _, blacklistText in pairs(defaultPopupBlacklist) do
        -- Prepend non-alphabetical characters with '%' to escape them
        -- Replace %s and %d with .+ to match any string or number
        -- Trim whitespaces
        blacklistText = blacklistText:gsub("%W", "%%%0"):gsub("%%%%s", ".+"):gsub("%%%%d", ".+"):gsub("^%s*(.-)%s*$", "%1")
        if lowerCaseText:find(blacklistText:lower()) then
            return
        end
    end

    return popupFrame.button1
end

-- Clears all override bindings associated with an owner, clears all override bindings if no owner is passed
--- @param owner Frame?
function DialogKey:ClearOverrideBindings(owner)
    if InCombatLockdown() then return end
    if not owner then
        for owner, _ in pairs(self.activeOverrideBindings) do
            self:ClearOverrideBindings(owner)
        end
        return
    end
    if not self.activeOverrideBindings[owner] then return end
    for key in pairs(self.activeOverrideBindings[owner]) do
        SetOverrideBinding(owner, false, key, nil)
    end
    self.activeOverrideBindings[owner] = nil
end

-- Set an override click binding, these bindings can safely perform secure actions
-- Override bindings, are temporary keybinds, which can only be modified out of combat; they are tied to an owner, and need to be cleared when the target is hidden
--- @param owner Frame
--- @param targetName string
--- @param keys string[]
function DialogKey:SetOverrideBindings(owner, targetName, keys)
    if InCombatLockdown() then return end
    self.activeOverrideBindings[owner] = {}
    for _, key in pairs(keys) do
        self.activeOverrideBindings[owner][key] = owner;
        SetOverrideBindingClick(owner, false, key, targetName, 'LeftButton');
    end
end

function DialogKey:CheckCustomFrames()
    if self.ignoreCheckCustomFrames then return end
    for frameName, _ in pairs(self.db.customFrames) do
        local frame = self:GetFrameByName(frameName)
        if frame and not self.handledCustomFrames[frame] then
            self.handledCustomFrames[frame] = frameName
            self:SecureHookScript(frame, "OnShow", "OnCustomFrameShow")
            self:SecureHookScript(frame, "OnHide", "OnCustomFrameHide")
            if frame:IsVisible() then
                self:OnCustomFrameShow(frame)
            end
        end
    end
end

--- @param frame Frame
--- @return Button, string
function DialogKey:AcquireProxyButton(frame)
    local proxyButton = self.proxyFrames[frame]
    if not proxyButton then
        self.proxyFrameIndex = self.proxyFrameIndex + 1
        local proxyName = self.proxyFrameNamePrefix .. self.proxyFrameIndex
        self.ignoreCheckCustomFrames = true
        proxyButton = CreateFrame("Button", proxyName, nil, "SecureActionButtonTemplate")
        self.ignoreCheckCustomFrames = false
        proxyButton:SetAttribute("type", "click")
        proxyButton:SetAttribute("typerelease", "click")
        proxyButton:SetAttribute("clickbutton", frame)
        proxyButton:RegisterForClicks("AnyUp", "AnyDown")
        proxyButton:SetAttribute("pressAndHoldAction", "1")
        proxyButton:HookScript("OnClick", function() self:Glow(frame) end)
        proxyButton.name = proxyName
        proxyButton.target = frame
        self.proxyFrames[frame] = proxyButton
    end
    return proxyButton, proxyButton.name
end

function DialogKey:OnCustomFrameShow(frame)
    if InCombatLockdown() or not self.db.customFrames[self.handledCustomFrames[frame]] then return end

    local proxyButton, proxyName = self:AcquireProxyButton(frame)

    self:SetOverrideBindings(proxyButton, proxyName, self.db.keys)
end

function DialogKey:OnCustomFrameHide(frame)
    if InCombatLockdown() then return end

    local proxyButton = self:AcquireProxyButton(frame)

    self:ClearOverrideBindings(proxyButton)
end

DialogKey.checkOnUpdate = {}
--- @param popupFrame StaticPopupTemplate # One of the StaticPopup1-4 frames
function DialogKey:OnPopupShow(popupFrame)
    -- Todo: consider supporting DialogKey.db.ignoreDisabledButtons option
    -- right now disabled buttons *are* clicked, but clicking them does nothing (although the key press is still eaten regardless)
    self.checkOnUpdate[popupFrame] = false
    -- only act if the popup is both visible, and the first visible one
    if InCombatLockdown() or popupFrame ~= self:GetFirstVisiblePopup() then return end

    local button = self:GetPopupButton(popupFrame)
    self:ClearOverrideBindings(popupFrame)
    if button == false then
        -- false means that the text is empty, and we should check again OnUpdate, for the text to be filled
        self.checkOnUpdate[popupFrame] = true
        return
    end
    if not button then return end

    self:SetOverrideBindings(popupFrame, button:GetName(), self.db.keys)
end

--- @param popupFrame StaticPopupTemplate # One of the StaticPopup1-4 frames
function DialogKey:OnPopupUpdate(popupFrame)
    if not self.checkOnUpdate[popupFrame] then return end

    self:OnPopupShow(popupFrame)
end

--- @param popupFrame StaticPopupTemplate # One of the StaticPopup1-4 frames
function DialogKey:OnPopupHide(popupFrame)
    if InCombatLockdown() then return end

    self:ClearOverrideBindings(popupFrame)
end

function DialogKey:HandleKey(key)
    if self:ShouldIgnoreInput() then return end

    local doAction = (key == self.db.keys[1] or key == self.db.keys[2])
    local keynum = doAction and 1 or tonumber(key)
    if key == "0" then
        keynum = 10
    end
    -- DialogKey pressed, interact with popups, accepts..
    if doAction then

        -- Click Popup - the actual click is performed via OverrideBindings
        local popupFrame = self:GetFirstVisiblePopup()
        local popupButton = popupFrame and self:GetPopupButton(popupFrame)
        if popupButton then
            self.frame:SetPropagateKeyboardInput(true)
            self:Glow(popupButton)
            return
        end

        -- Crafting Orders
        local craftingOrderFrame = self:GetFirstVisibleCraftingOrderFrame()
        if craftingOrderFrame then
            self.frame:SetPropagateKeyboardInput(false)
            self:Glow(craftingOrderFrame)
            craftingOrderFrame:Click()
            return
        end

        -- Custom Frames
        local customFrame = self:GetFirstVisibleCustomFrame()
        if customFrame then
            self.frame:SetPropagateKeyboardInput(true)
            return
        end

        -- Auction House
        if self.db.postAuctions and AuctionHouseFrame and AuctionHouseFrame:IsVisible() then
            if AuctionHouseFrame.displayMode == AuctionHouseFrameDisplayMode.CommoditiesSell then
                self.frame:SetPropagateKeyboardInput(false)
                self:Glow(AuctionHouseFrame.CommoditiesSellFrame.PostButton)
                AuctionHouseFrame.CommoditiesSellFrame:PostItem()
                return
            elseif AuctionHouseFrame.displayMode == AuctionHouseFrameDisplayMode.ItemSell then
                self.frame:SetPropagateKeyboardInput(false)
                self:Glow(AuctionHouseFrame.ItemSellFrame.PostButton)
                AuctionHouseFrame.ItemSellFrame:PostItem()
                return
            end
        end

        -- Complete Quest
        if QuestFrameProgressPanel:IsVisible() then
            self.frame:SetPropagateKeyboardInput(false)
            if not QuestFrameCompleteButton:IsEnabled() and self.db.ignoreDisabledButtons then
                -- click "Cencel" button when "Complete" is disabled on progress panel
                self:Glow(QuestFrameGoodbyeButton)
                CloseQuest()
            else
                self:Glow(QuestFrameCompleteButton)
                CompleteQuest()
            end
            return
        -- Accept Quest
        elseif QuestFrameDetailPanel:IsVisible() then
            self.frame:SetPropagateKeyboardInput(false)
            self:Glow(QuestFrameAcceptButton)
            AcceptQuest()
            return
        -- Take Quest Reward
        elseif QuestFrameRewardPanel:IsVisible() then
            self.frame:SetPropagateKeyboardInput(false)
            if self.itemChoice == -1 and GetNumQuestChoices() > 1 then
                QuestChooseRewardError()
            else
                self:Glow(QuestFrameCompleteQuestButton)
                GetQuestReward(self.itemChoice)
            end
            return
        end
    end

    -- Player Choice
    if self.db.handlePlayerChoice and next(self.playerChoiceButtons) and (doAction or self.db.numKeysForPlayerChoice) then
        local button = self.playerChoiceButtons[keynum]
        if button then
            self.frame:SetPropagateKeyboardInput(false)
            self:Glow(button)
            button:Click()
            return
        end
    end

    -- GossipFrame
    if (doAction or self.db.numKeysForGossip) and GossipFrame.GreetingPanel:IsVisible() then
        while keynum and keynum > 0 and keynum <= #self.frames do
            local choice = self.frames[keynum] and self.frames[keynum].GetElementData and self.frames[keynum].GetElementData()
            -- Skip grey quest (active but not completed) when pressing DialogKey
            if doAction and choice and choice.info and choice.info.questID and choice.activeQuestButton and not choice.info.isComplete and self.db.ignoreDisabledButtons then
                keynum = keynum + 1
            else
                self.frame:SetPropagateKeyboardInput(false)
                self:Glow(self.frames[keynum])
                self.frames[keynum]:Click()
                return
            end
        end
    end

    -- QuestFrame
    if (doAction or self.db.numKeysForGossip) and QuestFrameGreetingPanel:IsVisible() and self.frame then
        while keynum and keynum > 0 and keynum <= #self.frames do
            local _, is_complete = GetActiveTitle(keynum)
            if doAction and not is_complete and self.frames[keynum].isActive == 1 and self.db.ignoreDisabledButtons then
                keynum = keynum + 1
                if keynum > #self.frames then
                    doAction = false
                    keynum = 1
                end
            else
                self.frame:SetPropagateKeyboardInput(false)
                self:Glow(self.frames[keynum])
                self.frames[keynum]:Click()
                return
            end
        end
    end

    -- QuestReward Frame (select item)
    if self.db.numKeysForQuestRewards and keynum and keynum <= GetNumQuestChoices() and QuestFrameRewardPanel:IsVisible() then
        self.frame:SetPropagateKeyboardInput(false)
        self.itemChoice = keynum
        GetClickFrame("QuestInfoRewardsFrameQuestInfoItem" .. key):Click()
    end
end

-- QuestInfoItem_OnClick secure handler
-- allows DialogKey to update the selected quest reward when clicked as opposed to using a keybind.
function DialogKey:SelectItemReward()
    for i = 1, GetNumQuestChoices() do
        if GetClickFrame("QuestInfoRewardsFrameQuestInfoItem" .. i):IsMouseOver() then
            self.itemChoice = i
            break
        end
    end
end

-- Prefix list of QuestGreetingFrame(!!) options with 1., 2., 3. etc.
-- Also builds DialogKey.frames, used to click said options
function DialogKey:EnumerateGossips(isGossipFrame)
    if not ( QuestFrameGreetingPanel:IsVisible() or GossipFrame.GreetingPanel:IsVisible() ) then return end

    self.frames = {}
    if isGossipFrame then
        for _, child in pairs{ GossipFrame.GreetingPanel.ScrollBox.ScrollTarget:GetChildren() } do
            if child:GetObjectType() == "Button" and child:IsVisible() then
                table.insert(self.frames, child)
            end
        end
    else
        if QuestFrameGreetingPanel and QuestFrameGreetingPanel.titleButtonPool then
            for tab in QuestFrameGreetingPanel.titleButtonPool:EnumerateActive() do
                if tab:GetObjectType() == "Button" then
                    table.insert(self.frames, tab)
                end
            end
        elseif QuestFrameGreetingPanel and not QuestFrameGreetingPanel.titleButtonPool then
            for _, child in ipairs({ QuestGreetingScrollChildFrame:GetChildren() }) do
                if child:GetObjectType() == "Button" and child:IsVisible() then
                    table.insert(self.frames, child)
                end
            end
        else
            return
        end
    end

    table.sort(self.frames, function(a,b)
        if a.GetOrderIndex then
            return a:GetOrderIndex() < b:GetOrderIndex()
        else
            return a:GetTop() > b:GetTop()
        end
    end)

    if self.db.numKeysForGossip and not isGossipFrame then
        for i, frame in ipairs(self.frames) do
            if i > 10 then break end
            frame:SetText((i % 10) .. ". " .. frame:GetText())

            -- Make the button taller if the text inside is wrapped to multiple lines
            frame:SetHeight(frame:GetFontString():GetHeight() + 2)
        end
    end
end

-- Glow Functions --
function DialogKey:Glow(frame, speedModifier, forceShow)
    if self.db.showGlow or forceShow then
        self.glowFrame:SetAllPoints(frame)
        self.glowFrame.tex:SetColorTexture(1,1,0,0.5)
        self.glowFrame:Show()
        self.glowFrame:SetAlpha(1)
        self.glowFrame.speedModifier = speedModifier or 1
    end
end

-- Fades out the glow frame
function DialogKey:GlowFrameUpdate(frame, delta)
    local alpha = frame:GetAlpha() - (delta * 3 * frame.speedModifier)
    if alpha < 0 then
        alpha = 0
    end
    frame:SetAlpha(alpha)
    if frame:GetAlpha() <= 0 then frame:Hide() end
end

function DialogKey:print(...)
    print("|cffd2b48c[DialogKey]|r ", ...)
end

function DialogKey:AddFrame(frameName)
    local frame
    if not frameName then
        frame, frameName = self:GetFrameUnderCursor()
    else
        frame = self:GetFrameByName(frameName)
    end

    if not frame then
        self:print("No clickable frame found under your mouse. Try /fstack and find the name of the frame, and add it manually with /dialogkey add <frameName>")
        return
    end

    self.db.customFrames[frameName] = true
    self:Glow(frame, 0.25, true)
    self:print("Added frame:", frameName, ". Remove it again with /dialogkey remove; or in the options UI.")
    self:CheckCustomFrames()
    if frame:IsVisible() then
        self:OnCustomFrameShow(frame)
    end
end

function DialogKey:RemoveFrame(frameName)
    local frame
    if not frameName then
        frame, frameName = self:GetFrameUnderCursor()
    else
        frame = self:GetFrameByName(frameName)
    end

    if not frame then
        self:print("No clickable frame found under your mouse. Try /fstack and find the name of the frame, and remove it manually with /dialogkey remove <frameName>")
        return
    end

    self.db.customFrames[frameName] = nil
    self:Glow(frame, 0.25, true)
    self:print("Removed frame:", frameName)
    self:OnCustomFrameHide(frame)
end

--- Returns the first clickable frame that has mouse focus
--- @return ScriptRegion?, string? # The frame under the cursor, and its name; or nil
function DialogKey:GetFrameUnderCursor()
    for _, frame in ipairs(GetMouseFoci()) do
        if
            frame ~= WorldFrame
            and frame ~= UIParent
            and not callFrameMethod(frame, 'IsForbidden')
            and callFrameMethod(frame, 'HasScript', 'OnClick')
            and getFrameName(frame)
            and self:GetFrameByName(getFrameName(frame))
        then
            return frame, getFrameName(frame);
        end
    end
end
