local name = ...
--- @class DialogKeyNS
local ns = select(2, ...)

local GetFrameMetatable = _G.GetFrameMetatable or function() return getmetatable(CreateFrame('FRAME')) end

_G.DialogKeyNS = ns -- expose ourselves to the world :)

--- @class DialogKey: AceAddon, AceEvent-3.0, AceHook-3.0
local DialogKey = LibStub("AceAddon-3.0"):NewAddon(name, "AceEvent-3.0", "AceHook-3.0")
ns.Core = DialogKey

local defaultPopupBlacklist = { -- If a popup dialog contains one of these strings, don't click it
    AREA_SPIRIT_HEAL, -- Prevents cancelling the resurrection
    TOO_MANY_LUA_ERRORS,
    END_BOUND_TRADEABLE, -- Probably quite reasonable to make the user click on this one
    ADDON_ACTION_FORBIDDEN, -- Don't disable and reload UI on errors
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

--- @type Button[]
DialogKey.playerChoiceButtons = {}
--- @type Button[]
DialogKey.specButtons = {}
DialogKey.activeOverrideBindings = {}

DialogKey.dummyButton = CreateFrame("Button")

function DialogKey:OnInitialize()
    DialogKeyNumyDB = DialogKeyNumyDB or {}
    --- @type DialogKeyDB
    self.db = DialogKeyNumyDB
    ns:InitDB(self)

    self:InitGlowFrame()

    self:RegisterEvent("QUEST_GREETING")
    self:RegisterEvent("QUEST_LOG_UPDATE")
    self:RegisterEvent("QUEST_COMPLETE")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("ADDON_LOADED")

    self:InitMainProxyFrame()

    self:SecureHook("QuestInfoItem_OnClick", "SelectItemReward")
    self:SecureHook(GossipFrame, "Update", "OnGossipFrameUpdate")

    ns:RegisterOptions()

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
            Settings.OpenToCategory(ns.configPanelName)
        end
    end
end

function DialogKey:ADDON_LOADED(_, addon)
    if addon == 'Blizzard_PlayerChoice' then
        self:SecureHook(PlayerChoiceFrame, "TryShow", "OnPlayerChoiceShow")
        self:SecureHookScript(PlayerChoiceFrame, "OnHide", "OnPlayerChoiceHide")
    elseif addon == 'Blizzard_PlayerSpells' then
        self:SecureHookScript(PlayerSpellsFrame.SpecFrame, "OnShow", "OnSpecFrameShow")
        self:SecureHookScript(PlayerSpellsFrame.SpecFrame, "OnHide", "OnSpecFrameHide")
    end
end

function DialogKey:QUEST_COMPLETE()
    self.itemChoice = (GetNumQuestChoices() > 1 and -1 or 1)
end

function DialogKey:QUEST_GREETING()
    RunNextFrame(function() self:EnumerateGossips() end)
end

function DialogKey:QUEST_LOG_UPDATE()
    RunNextFrame(function() self:EnumerateGossips() end)
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

function DialogKey:InitMainProxyFrame()
    local frame = CreateFrame("Button", "DialogKey_Numy_MainClickProxyFrame", UIParent, "InsecureActionButtonTemplate")
    frame:RegisterForClicks("AnyUp", "AnyDown")
    frame:SetAttribute("type", "click")
    frame:SetAttribute("typerelease", "click")
    frame:SetAttribute("pressAndHoldAction", "1")
    frame:SetScript("PreClick", function()
        if InCombatLockdown() then return end
        self:ClearOverrideBindings(frame)
        local clickButton = frame:GetAttribute("clickbutton")
        self:Glow(clickButton)
    end)
    frame:HookScript("OnClick", function()
        if InCombatLockdown() then return end
        frame:SetAttribute("clickbutton", nil)
        frame:SetPropagateKeyboardInput(true)
    end)
    frame:SetScript("OnKeyDown", function(_, ...) self:HandleKey(...) end)
    frame:SetFrameStrata("TOOLTIP") -- Ensure we receive keyboard events first
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)

    self.frame = frame
end

function DialogKey:OnPlayerChoiceShow()
    if not self.db.handlePlayerChoice and not self.db.numKeysForPlayerChoice then return end
    local frame = PlayerChoiceFrame;
    if not frame or not frame:IsVisible() then return end

    local choiceInfo = C_PlayerChoice.GetCurrentPlayerChoiceInfo()
    if not choiceInfo then return end
    local buttons = {}
    local i = 0
    for _, option in ipairs(choiceInfo.options) do
        for _, button in ipairs(option.buttons) do
            if not button.hideButtonShowText or not button.text then
                i = i + 1
                buttons[button.id] = i
            end
        end
    end

    for option in frame.optionPools:EnumerateActive() do
        if option.buttons.buttonFramePool then
            for buttonFrame in option.buttons.buttonFramePool:EnumerateActive() do
                local button = buttonFrame.Button
                local key = buttons[button.buttonID]
                if key then
                    if self.db.numKeysForPlayerChoice then
                        button.Text:SetText(key .. ' ' .. button.Text:GetText())
                    end
                    self.playerChoiceButtons[key] = button
                end
            end
        end
    end
end

function DialogKey:OnPlayerChoiceHide()
    self.playerChoiceButtons = {}
end

function DialogKey:OnSpecFrameShow()
    --- @type FramePool<Frame, ClassSpecContentFrameTemplate>
    local framePool = PlayerSpellsFrame.SpecFrame.SpecContentFramePool

    self.specButtons = {}
    for specContentFrame in framePool:EnumerateActive() do
        --- @type ClassSpecContentFrameTemplate
        local specContentFrame = specContentFrame
        self.specButtons[specContentFrame.specIndex] = specContentFrame.ActivateButton
        local text = self.db.handleSpecFrame and (specContentFrame.specIndex .. ' ' .. TALENT_SPEC_ACTIVATE) or TALENT_SPEC_ACTIVATE
        specContentFrame.ActivateButton:SetText(text)
    end
end

function DialogKey:OnSpecFrameHide()
    self.specButtons = {}
end

--- @param GossipFrame GossipFrame
function DialogKey:OnGossipFrameUpdate(GossipFrame)
    local scrollbox = GossipFrame.GreetingPanel.ScrollBox

    self.frames = {};
    local n = 1
    for _, frame in scrollbox:EnumerateFrames() do
        local data = frame.GetElementData and frame:GetElementData()
        local tag
        if GOSSIP_BUTTON_TYPE_OPTION == data.buttonType then
            tag = "name"
        elseif GOSSIP_BUTTON_TYPE_AVAILABLE_QUEST == data.buttonType then
            tag = "title"
        elseif GOSSIP_BUTTON_TYPE_ACTIVE_QUEST == data.buttonType and (data.info.isComplete or not self.db.ignoreInProgressQuests) then
            tag = "title"
        end
        if tag then
            if self.db.numKeysForGossip then
                local oldText = data.info[tag]
                if data.info.flags and FlagsUtil.IsSet(data.info.flags, Enum.GossipOptionRecFlags.QuestLabelPrepend) then
                    oldText = GOSSIP_QUEST_OPTION_PREPEND:format(oldText);
                end
                local newText = (n % 10) .. ". " .. (oldText:match("^%d. (.+)$") or oldText)
                if self.db.riskyNumKeysForGossip then
                    data.info[tag] = newText -- this may not be safe, but it looks like the only somewhat reliable way to ensure the scrollbar is enabled when needed
                end
                frame:SetText(newText)
                frame:SetHeight(frame:GetFontString():GetHeight() + 2)
            end
            self.frames[n] = frame
            n = n + 1
        end
        if n > 10 then break end
    end
    --- @type ScrollBoxListLinearViewMixin
    local view = scrollbox:GetView()
    view:Layout()
    if self.db.riskyNumKeysForGossip then
        scrollbox:ScrollIncrease() -- force the scrollbar to show if needed
    end
end

--- @return Button[]|nil
function DialogKey:GetValidPopupButtons()
    local buttons = {}
    local popupFrames = {}
    for i = 1, 4 do
        local popup = _G["StaticPopup"..i]
        if popup and popup:IsVisible() then
            table.insert(popupFrames, popup)
        end
    end
    table.sort(popupFrames, function(a, b) return a:GetTop() > b:GetTop() end)
    for _, popupFrame in ipairs(popupFrames) do
        local button = self:GetPopupButton(popupFrame)
        if button then
            table.insert(buttons, button)
        end
    end

    return next(buttons) and buttons or nil
end

-- Takes a global string like '%s has challenged you to a duel.' and converts it to a format suitable for string.find
local summonMatch = CONFIRM_SUMMON:gsub("%%d", ".+"):format(".+", ".+", ".+")
local duelMatch = DUEL_REQUESTED:format(".+")
local resurrectMatch = RESURRECT_REQUEST_NO_SICKNESS:format(".+")
local groupinviteMatch = INVITATION:format(".+")
local instanceLogMatches = {
    INSTANCE_LOCK_TIMER:format(".+", ".+"),
    INSTANCE_LOCK_TIMER_PREVIOUSLY_SAVED:format(".+", ".+"),
    INSTANCE_LOCK_WARNING:format(".+"),
    INSTANCE_LOCK_WARNING_PREVIOUSLY_SAVED:format(".+"),
}

--- @param popupFrame StaticPopupTemplate # One of the StaticPopup1-4 frames
--- @return Frame|nil|false # The button to click, nil if no button should be clicked, false if the text is empty and should be checked again later
function DialogKey:GetPopupButton(popupFrame)
    local text = popupFrame.text:GetText()

    -- Some popups have no text when they initially show, and instead get text applied OnUpdate (summons are an example)
    -- False is returned in that case, so we know to keep checking OnUpdate
    if not text or text == " " or text == "" then return false end

    -- Don't accept group invitations if the option is enabled
    if self.db.dontAcceptInvite and text:find(groupinviteMatch) then return end

    -- Don't accept summons/duels/resurrects if the options are enabled
    if self.db.dontClickSummons and text:find(summonMatch) then return end
    if self.db.dontClickDuels and text:find(duelMatch) then return end
    if self.db.dontAcceptInstanceLocks then
        for _, match in pairs(instanceLogMatches) do
            if text:find(match) then return end
        end
    end

    -- If resurrect dialog has three buttons, and the option is enabled, use the middle one instead of the first one (soulstone, etc.)
    -- Located before resurrect/release checks/returns so it happens even if you have releases/revives disabled
    -- Also, Check if Button2 is visible instead of Button3 since Recap is always 3; 2 is hidden if you can't soulstone rez

    -- the ordering here means that a revive will be taken before a battle rez before a release.
    -- if revives are disabled but soulstone battlerezzes *aren't*, nothing will happen if both are available!
    local canRelease = popupFrame.button1:GetText() == DEATH_RELEASE
    if self.db.useSoulstoneRez and canRelease and popupFrame.button2:IsVisible() then
        return popupFrame.button2
    end

    if self.db.dontClickRevives and (text == RECOVER_CORPSE or text:find(resurrectMatch)) then return end
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

    return popupFrame.button1:IsVisible() and popupFrame.button1 or nil
end

--- @param frame Button
function DialogKey:GuardDisabled(frame)
    if not self.db.ignoreDisabledButtons then return true; end

    return frame:IsEnabled() and frame:IsMouseClickEnabled();
end

--- @return Button|nil
function DialogKey:GetFirstVisibleCustomFrame()
    for _, frameName in ipairs(ns.orderedCustomFrames) do
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

    if self.db.ignoreWithModifier and (IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()) then return true end
    -- Ignore input while typing, unless at the Send Mail confirmation while typing into it!
    local focus = GetCurrentKeyBoardFocus()
    if focus and not (self:GetValidPopupButtons() and (focus:GetName() == "SendMailNameEditBox" or focus:GetName() == "SendMailSubjectEditBox")) then return true end

    if
        -- Ignore input if there's nothing for DialogKey to click
        not GossipFrame:IsVisible() and not QuestFrame:IsVisible() and not self:GetValidPopupButtons()
        -- Ignore input if the Auction House sell frame is not open
        and (not AuctionHouseFrame or not AuctionHouseFrame:IsVisible())
        and not self:GetFirstVisibleCraftingOrderFrame()
        -- Ignore input if no custom frames are visible
        and not self:GetFirstVisibleCustomFrame()
        -- Ignore input if no player choice buttons are visible
        and not next(self.playerChoiceButtons)
        -- Ignore input if no spec buttons are visible
        and not next(self.specButtons)
    then
        return true
    end

    return false
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
        SetOverrideBinding(owner, true, key, nil)
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
        SetOverrideBindingClick(owner, true, key, targetName, 'LeftButton');
    end
end

function DialogKey:SetClickbuttonBinding(frame, key)
    if InCombatLockdown() then return end
    self.frame:SetAttribute("clickbutton", frame)
    self:SetOverrideBindings(self.frame, self.frame:GetName(), { key })

    -- just in case something goes horribly wrong, we do NOT want to get the user stuck in a situation where the keyboard stops working
    RunNextFrame(function() self:ClearOverrideBindings(self.frame) end)
end

function DialogKey:HandleKey(key)
    if not InCombatLockdown() then self.frame:SetPropagateKeyboardInput(true) end
    local doAction = (key == self.db.keys[1] or key == self.db.keys[2])
    local keynum = doAction and 1 or tonumber(key)
    if key == "0" then
        keynum = 10
    end
    if not doAction and not keynum then return end
    if self:ShouldIgnoreInput() then return end
    -- DialogKey pressed, interact with popups, accepts..
    if doAction then
        -- Popups
        local popupButtons = self:GetValidPopupButtons()
        if popupButtons then
            -- todo: set a binding for each popup button?
            self:SetClickbuttonBinding(popupButtons[1], key)
            return
        end

        -- Crafting Orders
        local craftingOrderFrame = self:GetFirstVisibleCraftingOrderFrame()
        if craftingOrderFrame then
            self:SetClickbuttonBinding(craftingOrderFrame, key)
            return
        end

        -- Custom Frames
        local customFrame = self:GetFirstVisibleCustomFrame()
        if customFrame then
            self:SetClickbuttonBinding(customFrame, key)
            return
        end

        -- Auction House
        if self.db.postAuctions and AuctionHouseFrame and AuctionHouseFrame:IsVisible() then
            if AuctionHouseFrame.displayMode == AuctionHouseFrameDisplayMode.CommoditiesSell then
                self:SetClickbuttonBinding(AuctionHouseFrame.CommoditiesSellFrame.PostButton, key)
                return
            elseif AuctionHouseFrame.displayMode == AuctionHouseFrameDisplayMode.ItemSell then
                self:SetClickbuttonBinding(AuctionHouseFrame.ItemSellFrame.PostButton, key)
                return
            end
        end

        -- Complete Quest
        if QuestFrameProgressPanel:IsVisible() then
            if not QuestFrameCompleteButton:IsEnabled() and self.db.ignoreDisabledButtons then
                -- click "Cencel" button when "Complete" is disabled on progress panel
                self:SetClickbuttonBinding(QuestFrameGoodbyeButton, key)
            else
                self:SetClickbuttonBinding(QuestFrameCompleteButton, key)
            end
            return
        -- Accept Quest
        elseif QuestFrameDetailPanel:IsVisible() then
            self:SetClickbuttonBinding(QuestFrameAcceptButton, key)
            return
        -- Take Quest Reward - using manual API
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
    if
        ((self.db.handlePlayerChoice and doAction) or (self.db.numKeysForPlayerChoice and not doAction))
        and next(self.playerChoiceButtons)
    then
        local button = self.playerChoiceButtons[keynum]
        if button and (not self.db.ignoreDisabledButtons or button:IsEnabled()) then
            self:SetClickbuttonBinding(button, key)
            return
        end
    end

    -- Spec Frame
    if self.db.handleSpecFrame and next(self.specButtons) then
        local button = self.specButtons[keynum]
        if button then
            -- blocks keybind for currently selected spec index
            if not button:IsVisible() then button = self.dummyButton end
            self:SetClickbuttonBinding(button, key)
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
                self:SetClickbuttonBinding(self.frames[keynum], key)
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
                self:SetClickbuttonBinding(self.frames[keynum], key)
                return
            end
        end
    end

    -- QuestReward Frame (select item)
    if self.db.numKeysForQuestRewards and keynum and keynum <= GetNumQuestChoices() and QuestFrameRewardPanel:IsVisible() then
        self.itemChoice = keynum
        self:SetClickbuttonBinding(GetClickFrame("QuestInfoRewardsFrameQuestInfoItem" .. key), key)
        return
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

-- Prefix list of QuestGreetingFrame options with 1., 2., 3. etc.
-- Also builds DialogKey.frames, used to click said options
function DialogKey:EnumerateGossips()
    if not QuestFrameGreetingPanel:IsVisible() then return end

    local checkQuestsToHandle = false
    local questsToHandle = {}

    if self.db.ignoreInProgressQuests then
        checkQuestsToHandle = true
        local numActiveQuests = GetNumActiveQuests()
        local numAvailableQuests = GetNumAvailableQuests()
        for i = 1, numActiveQuests do
            local _, isComplete = GetActiveTitle(i)
            questsToHandle[i] = isComplete
        end
        for i = (numActiveQuests + 1), (numActiveQuests + numAvailableQuests) do
            questsToHandle[i] = true
        end
    end

    local frames = {}
    self.frames = {}
    if QuestFrameGreetingPanel and QuestFrameGreetingPanel.titleButtonPool then
        --- @type FramePool<Button, QuestTitleButtonTemplate>
        local pool = QuestFrameGreetingPanel.titleButtonPool
        for tab in (pool:EnumerateActive()) do
            if tab:GetObjectType() == "Button" then
                table.insert(frames, tab)
            end
        end
    elseif QuestFrameGreetingPanel and not QuestFrameGreetingPanel.titleButtonPool then
        --- @type ScriptRegion[]
        local children = { QuestGreetingScrollChildFrame:GetChildren() }
        for _, child in ipairs(children) do
            if child:GetObjectType() == "Button" and child:IsVisible() then
                table.insert(frames, child)
            end
        end
    else
        return
    end

    table.sort(frames, function(a,b)
        if a.GetOrderIndex then
            return a:GetOrderIndex() < b:GetOrderIndex()
        else
            return a:GetTop() > b:GetTop()
        end
    end)

    if self.db.numKeysForGossip then
        local n = 1
        for i, frame in ipairs(frames) do
            if not checkQuestsToHandle or questsToHandle[i] then
                if n > 10 then break end
                local oldText = frame:GetText()
                local newText = (n % 10) .. ". " .. (oldText:match("^%d. (.+)$") or oldText)
                frame:SetText(newText)

                -- Make the button taller if the text inside is wrapped to multiple lines
                frame:SetHeight(frame:GetFontString():GetHeight() + 2)
                n = n + 1
            end
        end
    end
    for i, frame in ipairs(frames) do
        if not checkQuestsToHandle or questsToHandle[i] then
            table.insert(self.frames, frame)
        end
    end
end

-- Glow Functions --
--- @param frame Frame
--- @param speedModifier number # increasing this number will speed up the fade out of the glow
--- @param forceShow boolean # if true, the glow will be shown regardless of the showGlow setting
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

    if self.db.customFrames[frameName] then
        self:print("Frame is already on the watchlist:", frameName)
        self:Glow(frame, 0.25, true)
        return
    end
    ns:AddToWatchlist(frameName)
    self:Glow(frame, 0.25, true)
    self:print("Added frame:", frameName, ". Remove it again with /dialogkey remove; or in the options UI.")
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
    local index = self.db.customFrames[frameName]
    if not index then
        self:print("The clickable frame under your mouse isn't on the custom watchlist:", frameName)
        self:Glow(frame, 0.25, true)
        return
    end

    ns:RemoveFromWatchlist(frameName)
    self:Glow(frame, 0.25, true)
    self:print("Removed frame:", frameName)
end

--- Returns the first clickable frame that has mouse focus
--- @return Frame?, string? # The frame under the cursor, and its name; or nil
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
