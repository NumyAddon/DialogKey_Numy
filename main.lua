local name = ...
--- @class DialogKeyNS
local ns = select(2, ...)
_G.DialogKeyNS = ns

--- @class DialogKey: AceAddon, AceEvent-3.0, AceHook-3.0
local DialogKey = LibStub("AceAddon-3.0"):NewAddon(name, "AceEvent-3.0", "AceHook-3.0")
ns.Core = DialogKey

local defaultPopupBlacklist = { -- If a confirmation dialog contains one of these strings, don't accept it
    "Are you sure you want to go back to Shal'Aran?", -- Withered Training Scenario
    "Are you sure you want to return to your current timeline?", -- Leave Chromie Time
    "You will be removed from Timewalking Campaigns once you use this scroll.", -- "A New Adventure Awaits" Chromie Time scroll
    AREA_SPIRIT_HEAL, -- Prevents cancelling the resurrection
    TOO_MANY_LUA_ERRORS,
    END_BOUND_TRADEABLE,
    ADDON_ACTION_FORBIDDEN,
}

local GetMouseFoci = GetMouseFoci or function() return {GetMouseFocus()} end
local GetFrameMetatable = _G.GetFrameMetatable or function() return getmetatable(CreateFrame('FRAME')) end
local function callFrameMethod(frame, method, ...)
    local functionRef = frame[method] or GetFrameMetatable().__index[method] or nop;
    local ok, result = pcall(functionRef, frame, ...);

    return ok and result or false
end
--- @return string?
local function getFrameName(frame)
    return callFrameMethod(frame, 'GetDebugName')
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

function DialogKey:OnInitialize()
    if C_AddOns.IsAddOnLoaded("Immersion") then
        self:print("Immersion AddOn detected.")
        self:print("The Immersion addon is known to conflict with DialogKey!")
        self:print("Please check your addon settings before reporting bugs.")
    end
    DialogKeyNumyDB = DialogKeyNumyDB or {}
    self.db = DialogKeyNumyDB
    for k, v in pairs(ns.defaultOptions) do
        if self.db[k] == nil then self.db[k] = v end
    end

    self.glowFrame = CreateFrame("Frame", nil, UIParent)
    self.glowFrame:SetPoint("CENTER", 0, 0)
    self.glowFrame:SetFrameStrata("TOOLTIP")
    self.glowFrame:SetSize(50,50)
    self.glowFrame:SetScript("OnUpdate", function(...) self:GlowFrameUpdate(...) end)
    self.glowFrame:Hide()
    self.glowFrame.tex = self.glowFrame:CreateTexture()
    self.glowFrame.tex:SetAllPoints()
    self.glowFrame.tex:SetColorTexture(1,1,0,0.5)

    self:RegisterEvent("GOSSIP_SHOW")
    self:RegisterEvent("QUEST_GREETING")
    self:RegisterEvent("QUEST_COMPLETE")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")

    self.frame = CreateFrame("Frame", "DialogKeyFrame", UIParent)
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

-- Thanks, [github]@mbattersby
-- Prefix list of GossipFrame options with 1., 2., 3. etc.
function DialogKey:OnGossipFrameUpdate(frame)
    local dp = frame.GreetingPanel.ScrollBox:GetDataProvider()

    if DialogKey.db.numKeysForGossip then
        local n = 1
        for _, item in ipairs(dp.collection) do
            local tag
            if item.buttonType == GOSSIP_BUTTON_TYPE_OPTION then
                tag = "name"
            elseif item.buttonType == GOSSIP_BUTTON_TYPE_ACTIVE_QUEST or
                   item.buttonType == GOSSIP_BUTTON_TYPE_AVAILABLE_QUEST then
                tag = "title"
            end

            if tag then
                local dedup = item.info[tag]:match("^%d+%. (.+)") or item.info[tag]
                item.info[tag] = n%10 .. ". " .. dedup
                n = n + 1
            end
            if n > 10 then break end
        end
    end

    frame.GreetingPanel.ScrollBox:SetDataProvider(dp)
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

--- @return Button|nil
function DialogKey:GetFirstVisibleCustomFrame()
    for frameName, _ in pairs(self.db.customFrames) do
        local frame = self:GetFrameByName(frameName)
        if frame and frame:IsVisible() and frame:IsObjectType('Button') then
            return frame ---@diagnostic disable-line: return-type-mismatch
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
        -- Ignore input if no custom frames are visible
        and not self:GetFirstVisibleCustomFrame()
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

DialogKey.activeOverrideBindings = {}
-- Clears all override bindings associated with an owner, clears all override bindings if no owner is passed
function DialogKey:ClearOverrideBindings(owner)
    if InCombatLockdown() then return end
    if not owner then
        for owner, _ in pairs(self.activeOverrideBindings) do
            self:ClearOverrideBindings(owner)
        end
    end
    if not self.activeOverrideBindings[owner] then return end
    for key in pairs(self.activeOverrideBindings[owner]) do
        SetOverrideBinding(owner, false, key, nil)
    end
    self.activeOverrideBindings[owner] = nil
end

-- Set an override click binding, these bindings can safely perform secure actions
-- Override bindings, are temporary keybinds, which can only be modified out of combat; they are tied to an owner, and need to be cleared when the target is hidden
function DialogKey:SetOverrideBindings(owner, targetName, keys)
    if InCombatLockdown() then return end
    self.activeOverrideBindings[owner] = {}
    for _, key in pairs(keys) do
        self.activeOverrideBindings[owner][key] = owner;
        SetOverrideBindingClick(owner, false, key, targetName);
    end
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

    local doAction = (key == DialogKey.db.keys[1] or key == DialogKey.db.keys[2])
    local keynum = doAction and 1 or tonumber(key)
    if key == "0" then
        keynum = 10
    end
    -- DialogKey pressed, interact with popups, accepts..
    if doAction then

        -- Click Popup - the actual click is performed via OverrideBindings
        if self:GetFirstVisiblePopup() and self:GetPopupButton(self:GetFirstVisiblePopup()) then
            DialogKey.frame:SetPropagateKeyboardInput(true)
            return
        end

        -- Custom Frames
        local customFrame = self:GetFirstVisibleCustomFrame()
        if customFrame then
            DialogKey.frame:SetPropagateKeyboardInput(false)
            self:Glow(customFrame)
            customFrame:Click()
            return
        end

        -- Auction House
        if DialogKey.db.postAuctions and AuctionHouseFrame and AuctionHouseFrame:IsVisible() then
            if AuctionHouseFrame.displayMode == AuctionHouseFrameDisplayMode.CommoditiesSell then
                DialogKey.frame:SetPropagateKeyboardInput(false)
                DialogKey:Glow(AuctionHouseFrame.CommoditiesSellFrame.PostButton)
                AuctionHouseFrame.CommoditiesSellFrame:PostItem()
                return
            elseif AuctionHouseFrame.displayMode == AuctionHouseFrameDisplayMode.ItemSell then
                DialogKey.frame:SetPropagateKeyboardInput(false)
                DialogKey:Glow(AuctionHouseFrame.ItemSellFrame.PostButton)
                AuctionHouseFrame.ItemSellFrame:PostItem()
                return
            end
        end

        -- Complete Quest
        if QuestFrameProgressPanel:IsVisible() then
            DialogKey.frame:SetPropagateKeyboardInput(false)
            if not QuestFrameCompleteButton:IsEnabled() and DialogKey.db.ignoreDisabledButtons then
                -- click "Cencel" button when "Complete" is disabled on progress panel
                DialogKey:Glow(QuestFrameGoodbyeButton)
                CloseQuest()
            else
                DialogKey:Glow(QuestFrameCompleteButton)
                CompleteQuest()
            end
            return
        -- Accept Quest
        elseif QuestFrameDetailPanel:IsVisible() then
            DialogKey.frame:SetPropagateKeyboardInput(false)
            DialogKey:Glow(QuestFrameAcceptButton)
            AcceptQuest()
            return
        -- Take Quest Reward
        elseif QuestFrameRewardPanel:IsVisible() then
            DialogKey.frame:SetPropagateKeyboardInput(false)
            if DialogKey.itemChoice == -1 and GetNumQuestChoices() > 1 then
                QuestChooseRewardError()
            else
                DialogKey:Glow(QuestFrameCompleteQuestButton)
                GetQuestReward(DialogKey.itemChoice)
            end
            return
        end
    end

    -- GossipFrame
    if (doAction or DialogKey.db.numKeysForGossip) and GossipFrame.GreetingPanel:IsVisible() then
        while keynum and keynum > 0 and keynum <= #DialogKey.frames do
            choice = DialogKey.frames[keynum] and DialogKey.frames[keynum].GetElementData and DialogKey.frames[keynum].GetElementData()
            -- Skip grey quest (active but not completed) when pressing DialogKey
            if doAction and choice and choice.info and choice.info.questID and choice.activeQuestButton and not choice.info.isComplete and DialogKey.db.ignoreDisabledButtons then
                keynum = keynum + 1
            else
                DialogKey.frame:SetPropagateKeyboardInput(false)
                DialogKey:Glow(DialogKey.frames[keynum])
                DialogKey.frames[keynum]:Click()
                return
            end
        end
    end

    -- QuestFrame
    if (doAction or DialogKey.db.numKeysForGossip) and QuestFrameGreetingPanel:IsVisible() and DialogKey.frame then
        while keynum and keynum > 0 and keynum <= #DialogKey.frames do
            local title, is_complete = GetActiveTitle(keynum)
            if doAction and not is_complete and DialogKey.frames[keynum].isActive == 1 and DialogKey.db.ignoreDisabledButtons then
                keynum = keynum + 1
                if keynum > #DialogKey.frames then
                    doAction = false
                    keynum = 1
                end
            else
                DialogKey.frame:SetPropagateKeyboardInput(false)
                DialogKey:Glow(DialogKey.frames[keynum])
                DialogKey.frames[keynum]:Click()
                return
            end
        end
    end

    -- QuestReward Frame (select item)
    if DialogKey.db.numKeysForQuestRewards and keynum and keynum <= GetNumQuestChoices() and QuestFrameRewardPanel:IsVisible() then
        DialogKey.frame:SetPropagateKeyboardInput(false)
        DialogKey.itemChoice = keynum
        GetClickFrame("QuestInfoRewardsFrameQuestInfoItem" .. key):Click()
    end
end

-- QuestInfoItem_OnClick secure handler
-- allows DialogKey to update the selected quest reward when clicked as opposed to using a keybind.
function DialogKey:SelectItemReward()
    for i = 1, GetNumQuestChoices() do
        if GetClickFrame("QuestInfoRewardsFrameQuestInfoItem" .. i):IsMouseOver() then
            DialogKey.itemChoice = i
            break
        end
    end
end

-- Prefix list of QuestGreetingFrame(!!) options with 1., 2., 3. etc.
-- Also builds DialogKey.frames, used to click said options
function DialogKey:EnumerateGossips(isGossipFrame)
    if not ( QuestFrameGreetingPanel:IsVisible() or GossipFrame.GreetingPanel:IsVisible() ) then return end

    -- If anyone reading this comment is or knows someone on the WoW UI team, please send them this Addon and
    --   show them this function and then please ask them to (politely) slap whoever decided that:
    --   (1) ObjectPool's `activeObjects` *had* to be a dictionary
    --   (2) :GetChildren() should return an unpacked list of the sub-objects instead of, you know, a Table.
    --   :)
    -- FuriousProgrammer
    local tab = {}
    DialogKey.frames = {}
    if isGossipFrame then
        for _, v in pairs{ GossipFrame.GreetingPanel.ScrollBox.ScrollTarget:GetChildren() } do
            if v:GetObjectType() == "Button" and v:IsVisible() then
                table.insert(DialogKey.frames, v)
            end
        end
    else
        if QuestFrameGreetingPanel and QuestFrameGreetingPanel.titleButtonPool then
            for tab in QuestFrameGreetingPanel.titleButtonPool:EnumerateActive() do
                if tab:GetObjectType() == "Button" then
                    table.insert(DialogKey.frames, tab)
                end
            end
        elseif QuestFrameGreetingPanel and not QuestFrameGreetingPanel.titleButtonPool then
            local children = {QuestGreetingScrollChildFrame:GetChildren()}
            for i, c in ipairs(children) do
                if c:GetObjectType() == "Button" and c:IsVisible() then
                    table.insert(DialogKey.frames, c)
                end
            end
        else
            return
        end
    end

    table.sort(DialogKey.frames, function(a,b)
        if a.GetOrderIndex then
            return a:GetOrderIndex() < b:GetOrderIndex()
        else
            return a:GetTop() > b:GetTop()
        end
    end)

    if DialogKey.db.numKeysForGossip and not isGossipFrame then
        for i, frame in ipairs(DialogKey.frames) do
            if i > 10 then break end
            frame:SetText(i%10 .. ". " .. frame:GetText())

            -- Make the button taller if the text inside is wrapped to multiple lines
            frame:SetHeight(frame:GetFontString():GetHeight()+2)
        end
    end
end

-- Glow Functions --
function DialogKey:Glow(frame, speedModifier, forceShow)
    if DialogKey.db.showGlow or forceShow then
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
    self:print("Added frame: ", frameName, '. Remove it again with /dialogkey remove; or in the options UI.')
    -- todo: consider making it always a secure click
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
    self:print("Removed frame: ", frameName)
    -- todo: if handled by magic secure click code, unregister it
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
