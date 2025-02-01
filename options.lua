--- @class DialogKeyNS
local ns = select(2, ...)

ns.configPanelName = 'DialogKey - Numy Edition'
--- @class DialogKeyDB
ns.defaultOptions = {
    --- @type string[]
    keys = {
        "SPACE",
    },
    ignoreDisabledButtons = false,
    ignoreWithModifier = false,
    showGlow = true,
    --- @type table<string, boolean> # [text] = true
    dialogBlacklist = {},
    --- @type table<string, number> # [frameName] = priority
    customFrames = {},
    numKeysForGossip = true,
    riskyNumKeysForGossip = true,
    numKeysForQuestRewards = true,
    dontClickSummons = true,
    dontClickDuels = true,
    dontClickRevives = true,
    dontClickReleases = true,
    dontAcceptInvite = true,
    dontAcceptInstanceLocks = false,
    useSoulstoneRez = true,
    handleCraftingOrders = true,
    handlePlayerChoice = true,
    numKeysForPlayerChoice = true,
    postAuctions = false,
    ignoreInProgressQuests = true,
}

--- @param dialogKey DialogKey
function ns:InitDB(dialogKey)
    for k, v in pairs(self.defaultOptions) do
        if dialogKey.db[k] == nil then dialogKey.db[k] = v end
    end
    if select(2, next(dialogKey.db.customFrames)) == true then -- unordered list
        local i = 1
        for k, _ in pairs(dialogKey.db.customFrames) do
            dialogKey.db.customFrames[k] = i
            i = i + 1
        end
    end

    -- check for gaps
    self:GuardAgainstGaps()
end

function ns:GuardAgainstGaps()
    local db = self.Core.db
    local count = 0
    for _, _ in pairs(db.customFrames) do
        count = count + 1
    end
    ns.orderedCustomFrames = tInvert(db.customFrames)
    local orderedCount = 0
    for _, _ in ipairs(ns.orderedCustomFrames) do -- ipairs stops at the first gap
        orderedCount = orderedCount + 1
    end
    if count ~= orderedCount then
        for i = 1, count do
            if ns.orderedCustomFrames[i] == nil then
                local j = i + 1
                while j < i+100 do -- exit after 100, to avoid infinite loops in case of issues
                    if ns.orderedCustomFrames[j] then
                        ns.orderedCustomFrames[i] = ns.orderedCustomFrames[j]
                        ns.orderedCustomFrames[j] = nil
                        db.customFrames[ns.orderedCustomFrames[i]] = i
                        break
                    end
                    j = j + 1
                end
            end
        end
        ns.orderedCustomFrames = tInvert(db.customFrames)
    end
end

function ns:RemoveFromWatchlist(frameName)
    local db = self.Core.db
    local index = db.customFrames[frameName]
    if not index then return end
    tremove(self.orderedCustomFrames, index)
    db.customFrames[frameName] = nil

    for i = index, #self.orderedCustomFrames do
        db.customFrames[self.orderedCustomFrames[i]] = i
    end
    self:RegisterOptions()
end

function ns:AddToWatchlist(frameName)
    local db = self.Core.db
    if db.customFrames[frameName] then return end
    tinsert(self.orderedCustomFrames, frameName)
    db.customFrames[frameName] = #self.orderedCustomFrames
    self:RegisterOptions()
end

local arrowNext = C_Texture.GetAtlasInfo('common-dropdown-icon-next')
local arrowBack = C_Texture.GetAtlasInfo('common-dropdown-icon-back')
local cross = C_Texture.GetAtlasInfo('Radial_Wheel_Icon_Close')
local search = C_Texture.GetAtlasInfo('common-search-magnifyingglass')
local width_multiplier = 170

-- only want this for toggles
local function wrapName(name)
    return "|cffffd100" .. name .. "|r"
end

------- hack to allow tooltips to work on nameless execute icons
local MAGIC_TOOLTIP_TEXTS = {
    up = 'DialogKey_Numy_MagicTooltipUp',
    down = 'DialogKey_Numy_MagicTooltipDown',
    remove = 'DialogKey_Numy_MagicTooltipRemove',
    glow = 'DialogKey_Numy_MagicTooltipGlow',
}
do
    local lastSetOwnerCall
    local ACDTooltip = LibStub("AceConfigDialog-3.0").tooltip
    hooksecurefunc(ACDTooltip, 'SetOwner', function(_, ...)
        lastSetOwnerCall = {...}
    end)
    hooksecurefunc(ACDTooltip, 'AddLine', function(tooltip, text, r, g, b, wrap)
        local title, desc
        if text == MAGIC_TOOLTIP_TEXTS.up then
            title = "Move up"
            desc = "Move the frame higher in the priority list"
        elseif text == MAGIC_TOOLTIP_TEXTS.down then
            title = "Move down"
            desc = "Move the frame lower in the priority list"
        elseif text == MAGIC_TOOLTIP_TEXTS.remove then
            title = "Remove"
            desc = "Remove the frame from the custom watchlist"
        elseif text == MAGIC_TOOLTIP_TEXTS.glow then
            title = "Find"
            desc = "Show a short glow effect around the frame to make it easier to find"
        end
        if title then
            -- setting text to an empty string seems to clear the owner and effectively resets the tooltip :/
            tooltip:SetOwner(unpack(lastSetOwnerCall))
            tooltip:SetText(title, 1, .82, 0, true)
            tooltip:AddLine(desc, r, g, b, wrap)
        end
    end)
end

local initialized = false
function ns:RegisterOptions()
    if not initialized then
        initialized = true
        LibStub("AceConfig-3.0"):RegisterOptionsTable(self.configPanelName, function() return self:GetOptionsTable() end)
        LibStub("AceConfigDialog-3.0"):AddToBlizOptions(self.configPanelName)
    else
        LibStub("AceConfigRegistry-3.0"):NotifyChange(self.configPanelName)
    end
end

function ns:GetOptionsTable()
    local db = self.Core.db
    local function optionSetter(info, val) db[info[#info]] = val end
    local function optionGetter(info) return db[info[#info]] end
    local function swapWatchlistFrames(index1, index2)
        local frame1 = self.orderedCustomFrames[index1]
        local frame2 = self.orderedCustomFrames[index2]
        if not frame1 or not frame2 then return end

        self.orderedCustomFrames[index1] = frame2
        self.orderedCustomFrames[index2] = frame1
        db.customFrames[frame1] = index2
        db.customFrames[frame2] = index1

        self:RegisterOptions()
    end

    local increment = CreateCounter()
    local options = {
        type = "group",
        set = optionSetter,
        get = optionGetter,
        name = self.configPanelName,
        args = {
            header1 = {
                order = increment(),
                name = "Primary Keybinds",
                type = "header",
            },
            key1 = {
                order = increment(),
                name = "",
                type = "keybinding",
                set = (function(_, val) db.keys[1] = val end),
                get = (function(_) return db.keys[1] end),
            },
            key2 = {
                order = increment(),
                name = "",
                type = "keybinding",
                set = (function(_, val) db.keys[2] = val end),
                get = (function(_) return db.keys[2] end),
            },
            header2 = {
                order = increment(),
                name = "Options",
                type = "header",
            },
            generalGroup = {
                order = increment(),
                name = "General",
                desc = "Basic Options for personal preferences",
                type = "group",
                args = {
                    showGlow = {
                        order = increment(),
                        name = wrapName("Enable Glow"),
                        desc = "Show the glow effect when DialogKey clicks a button",
                        descStyle = "inline", width = "full", type = "toggle",
                    },
                    ignoreWithModifier = {
                        order = increment(),
                        name = wrapName("Ignore DialogKey with Modifiers"),
                        desc = "Disable DialogKey while any modifier key is held (Shift, Alt, Ctrl)",
                        descStyle = "inline", width = "full", type = "toggle",
                    },
                    ignoreDisabledButtons = {
                        order = increment(),
                        name = wrapName("Ignore Disabled Buttons"),
                        desc = "Don't allow DialogKey to click on disabled (greyed out) buttons",
                        descStyle = "inline", width = "full", type = "toggle",
                    },
                    ignoreInProgressQuests = {
                        order = increment(),
                        name = wrapName("Ignore In-Progress Quests"),
                        desc = "Gossip options for in-progress quests are ignored, and only completed or unaccepted quests are clicked",
                        descStyle = "inline", width = "full", type = "toggle",
                    },
                    numKeysForGossip = {
                        order = increment(),
                        name = wrapName("Number keys for Gossip"),
                        desc = "Use the number keys (1 -> 0) to select Gossip options or Quests from an NPC dialog window",
                        descStyle = "inline", width = "full", type = "toggle",
                    },
                    riskyNumKeysForGossip = {
                        order = increment(),
                        name = wrapName("Number keys for Gossip - Risky"),
                        disabled = function() return not db.numKeysForGossip end,
                        desc = "Ensure scrollbar is enabled if the text becomes too long. This may taint objective frame buttons, such as dropping candles in delves. If you encounter issues, just disable this option.",
                        descStyle = "inline", width = "full", type = "toggle",
                    },
                    numKeysForQuestRewards = {
                        order = increment(),
                        name = wrapName("Number keys for Quest Rewards"),
                        desc = "Use the number keys (1 -> 0) to select Quest rewards when multiple are available",
                        descStyle = "inline", width = "full", type = "toggle",
                    },
                    postAuctions = {
                        order = increment(),
                        name = wrapName("Post Auctions"),
                        desc = "Post Auctions",
                        descStyle = "inline", width = "full", type = "toggle",
                    },
                    handleCraftingOrders = {
                        order = increment(),
                        name = wrapName("Crafting Orders"),
                        desc = "Handle Crafting Orders: Start them, Craft them, Complete them",
                        descStyle = "inline", width = "full", type = "toggle",
                    },
                    handlePlayerChoice = {
                        order = increment(),
                        name = wrapName("Player Choice"),
                        desc = "Use keybinding to select the first Player Choice option",
                        descStyle = "inline", width = "full", type = "toggle",
                    },
                    numKeysForPlayerChoice = {
                        order = increment(),
                        name = wrapName("Number keys for Player Choice"),
                        desc = "Use the number keys (1 -> 0) to select Player Choices",
                        disabled = function() return not db.handlePlayerChoice end,
                        descStyle = "inline", width = "full", type = "toggle",
                    },
                },
            },
            --priorityGroup = {
            --    order = increment(),
            --    name = "Priority",
            --    desc = "Advanced Options to control DialogKey button priority",
            --    type = "group",
            --    args = {
            -- todo: some way to set priority between built-in frames, not sure whether I'd like a list of all custom frames
            --       and built-in frames intermixed in that list, or have <custom watchlist frames> as an item in a "master" list
            --       the 2nd option is far far simpler, but also less flexible. but then again, do we *need* so much flexibility?
            --    },
            --},
            watchlistGroup = {
                order = increment(),
                name = "Custom Watchlist",
                desc = "List of custom buttons for DialogKey to attempt to click",
                type = "group",
                args = {
                    desc = {
                        order = increment(),
                        name = [[
You can add custom frames to "click" with your keybinds here.
Simply enter the name of the frame to handle, or hover over the frame and write "/dialogkey add" to add the frame under your mouse.

If you have trouble finding the name, try "/fstack", pressing ALT until the frame you want is highlighted. If there are random letters and numbers in the name (e.g. "GameMenuFrame.2722d8f518"), then the frame cannot be clicked by DialogKey.
]],
                        type = "description",
                        fontSize = "medium",
                    },
                    addFrame = {
                        order = increment(),
                        type = "input",
                        name = "Add a Frame to watch",
                        width = "full",
                        set = function(_, value)
                            self:AddToWatchlist(value)
                        end,
                    },
                    priority = self:CreateCustomFramesPriorityListOptions(increment(), swapWatchlistFrames),
                },
            },
            popupBlacklistGroup = {
                order = increment(),
                name = "Popup Blacklist",
                desc = "List of popup dialogs for DialogKey to completely ignore",
                type = "group",
                args = {
                    dontAcceptInvite = {
                        order = increment(),
                        name = wrapName("Don't Accept Group Invites"),
                        desc = "Don't allow DialogKey to accept Raid/Party Invitations",
                        descStyle = "inline", width = "full", type = "toggle",
                    },
                    dontAcceptInstanceLocks = {
                        order = increment(),
                        name = wrapName("Don't Accept Instance Lockouts"),
                        desc = "Don't allow DialogKey to accept/\"save\" Instance Lockouts",
                        descStyle = "inline", width = "full", type = "toggle",
                    },
                    dontClickSummons = {
                        order = increment(),
                        name = wrapName("Don't Accept Summons"),
                        desc = "Don't allow DialogKey to accept Summon Requests",
                        descStyle = "inline", width = "full", type = "toggle",
                    },
                    dontClickDuels = {
                        order = increment(),
                        name = wrapName("Don't Accept Duels"),
                        desc = "Don't allow DialogKey to accept Duel Requests",
                        descStyle = "inline", width = "full", type = "toggle",
                    },
                    dontClickRevives = {
                        order = increment(),
                        name = wrapName("Don't Accept Revives"),
                        desc = "Don't allow DialogKey to accept Resurrections",
                        descStyle = "inline", width = "full", type = "toggle",
                    },
                    dontClickReleases = {
                        order = increment(),
                        name = wrapName("Don't Release Spirit"),
                        desc = "Don't allow DialogKey to Release Spirit",
                        descStyle = "inline", width = "full", type = "toggle",
                    },
                    useSoulstoneRez = {
                        order = increment(),
                        name = wrapName("Use Class-specific Revive"),
                        desc = "Use Soulstone/Ankh/etc. resurrection option when one is available and a normal/battle resurrection is not\n\nThis option |cffff0000ignores|r the |cffffd100Don't Accept Revives|r option!",
                        descStyle = "inline", width = "full", type = "toggle",
                    },
                    desc = {
                        order = increment(),
                        name = [[
Here you can create a custom list of popups that DialogKey should ignore.
Simply add (part of) the text that appears in the popup, and DialogKey will ignore it.
]],
                        type = "description",
                        fontSize = "medium",
                    },
                    addText = {
                        order = increment(),
                        type = "input",
                        name = "Add a text to ignore",
                        width = "full",
                        set = function(_, value)
                            db.dialogBlacklist[value] = true
                        end,
                    },
                    removeText = {
                        order = increment(),
                        type = "select",
                        style = "dropdown",
                        name = "Remove Ignored Text",
                        width = "full",
                        values = function()
                            local tempTable = {}
                            if not next(db.dialogBlacklist) then
                                return { [''] = ' * No texts are currently ignored *' }
                            end
                            for text, _ in pairs(db.dialogBlacklist) do
                                tempTable[text] = text
                            end
                            return tempTable
                        end,
                        get = function(_, _) return false end,
                        set = function(_, index, ...)
                            db.dialogBlacklist[index] = nil
                        end,
                    },
                    listOfTexts = {
                        order = increment(),
                        type = "description",
                        name = function()
                            local text = wrapName("Currently ignored texts:") .. "\n"
                            for k, _ in pairs(db.dialogBlacklist) do
                                text = text .. " - " .. k .. "\n"
                            end
                            return text
                        end,
                    },
                },
            },
        },
    }

    return options
end

function ns:CreateCustomFramesPriorityListOptions(order, swapWatchlistFrames)
    local increment = CreateCounter()
    local options = {
        order = order,
        name = "Manage currently watched frames",
        type = "group",
        inline = true,
        args = {
            header = {
                order = increment(),
                name = "If multiple frames are visible, the one highest on the list will be clicked.",
                type = "description",
                width = "full",
            },
        },
    };
    if #self.orderedCustomFrames == 0 then
        options.args.noFrames = {
            order = increment(),
            name = " * No frames are currently being watched * ",
            type = "description",
            fontSize = "medium",
            width = "full",
        };

        return options;
    end
    local numberOfIcons = 4;
    local iconWidth = 26;
    local groupWidth = 405; -- depends on whether there's a scrollbar
    for i, frame in ipairs(self.orderedCustomFrames) do
        options.args["glow" .. i] = {
            order = increment(),
            name = "",
            desc = MAGIC_TOOLTIP_TEXTS.glow,
            disabled = function() return not self.Core:GetFrameByName(frame) end,
            type = "execute",
            func = function()
                local frameRef = self.Core:GetFrameByName(frame)
                if not frameRef then return end
                self.Core:Glow(frameRef, 0.25, true)
            end,
            image = search.file,
            imageWidth = 16,
            imageHeight = 16,
            imageCoords = {
                search.leftTexCoord, search.rightTexCoord, search.topTexCoord, search.bottomTexCoord,
            },
            width = iconWidth / width_multiplier,
        };
        options.args["name" .. i] = {
            order = increment(),
            name = frame,
            type = "description",
            fontSize = "medium",
            width = (groupWidth - iconWidth * numberOfIcons) / width_multiplier,
        };
        options.args["up" .. i] = {
            order = increment(),
            name = "",
            desc = MAGIC_TOOLTIP_TEXTS.up,
            type = "execute",
            disabled = function() return i == 1 end,
            func = function()
                swapWatchlistFrames(i, i - 1)
            end,
            image = arrowBack.file,
            imageWidth = 16,
            imageHeight = 16,
            imageCoords = {
                arrowBack.leftTexCoord, arrowBack.bottomTexCoord, -- UL
                arrowBack.rightTexCoord, arrowBack.bottomTexCoord, -- LL
                arrowBack.leftTexCoord, arrowBack.topTexCoord, -- UR
                arrowBack.rightTexCoord, arrowBack.topTexCoord, -- LR
            },
            width = iconWidth / width_multiplier,
        };
        options.args["down" .. i] = {
            order = increment(),
            type = "execute",
            name = "",
            desc = MAGIC_TOOLTIP_TEXTS.down,
            disabled = function() return i == #self.orderedCustomFrames end,
            func = function()
                swapWatchlistFrames(i, i + 1)
            end,
            image = arrowNext.file,
            imageWidth = 16,
            imageHeight = 16,
            width = iconWidth / width_multiplier,
            imageCoords = {
                arrowNext.leftTexCoord, arrowNext.bottomTexCoord, -- UL
                arrowNext.rightTexCoord, arrowNext.bottomTexCoord, -- LL
                arrowNext.leftTexCoord, arrowNext.topTexCoord, -- UR
                arrowNext.rightTexCoord, arrowNext.topTexCoord, -- LR
            },
        };
        options.args["delete" .. i] = {
            order = increment(),
            name = "",
            desc = MAGIC_TOOLTIP_TEXTS.remove,
            type = "execute",
            func = function()
                self:RemoveFromWatchlist(frame)
            end,
            image = cross.file,
            imageWidth = 16,
            imageHeight = 16,
            imageCoords = {
                cross.leftTexCoord, cross.rightTexCoord, cross.topTexCoord, cross.bottomTexCoord,
            },
            width = iconWidth / width_multiplier,
        };
        options.args["spacer" .. i] = {
            order = increment(),
            name = "",
            type = "description",
            width = "full",
        };
    end

    return options;
end
