--- @class DialogKeyNS
local ns = select(2, ...)

ns.defaultOptions = {
    keys = {
        "SPACE",
    },
    ignoreDisabledButtons = false,
    ignoreWithModifier = false,
    showGlow = true,
    dialogBlacklist = {},
    customFrames = {},
    numKeysForGossip = true,
    numKeysForQuestRewards = true,
    dontClickSummons = true,
    dontClickDuels = true,
    dontClickRevives = true,
    dontClickReleases = true,
    dontAcceptInvite = true,
    useSoulstoneRez = true,
    handleCraftingOrders = true,
    handlePlayerChoice = true,
    numKeysForPlayerChoice = true,
    postAuctions = false,
}

-- Using #info here so that the option toggles/buttons/etc can be placed anywhere in the tree below and correctly update the option above via name matching.
local function optionSetter(info, val) ns.Core.db[info[#info]] = val end
local function optionGetter(info) return ns.Core.db[info[#info]] end

-- only want this for toggles
local function wrapName(name)
    return "|cffffd100" .. name .. "|r"
end

local increment = CreateCounter()

ns.interfaceOptions = {
    type = "group",
    set = optionSetter,
    get = optionGetter,
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
            set = (function(info, val) ns.Core.db.keys[1] = val end),
            get = (function(info) return ns.Core.db.keys[1] end),
        },
        key2 = {
            order = increment(),
            name = "",
            type = "keybinding",
            set = (function(_, val) ns.Core.db.keys[2] = val end),
            get = (function(_) return ns.Core.db.keys[2] end),
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
                numKeysForGossip = {
                    order = increment(),
                    name = wrapName("Number keys for Gossip"),
                    desc = "Use the number keys (1 -> 0) to select Gossip options or Quests from an NPC dialog window",
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
                    disabled = function() return not ns.Core.db.handlePlayerChoice end,
                    descStyle = "inline", width = "full", type = "toggle",
                },
            },
        },
        --priorityGroup = {
        --    order = increment(),
        --    name = "Priority",
        --    desc = "Advanced Options to control DialogKey button priority",
        --    type = "group",
        --    set = optionSetter,
        --    get = optionGetter,
        --    args = {
        --        temp = {
        --            order = increment(),
        --            name = "=== Advanced Priority Customization NYI ===",
        --            type = "description",
        --            fontSize = "medium",
        --        },
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
                        ns.Core.db.customFrames[value] = true
                    end,
                },
                removeFrame = {
                    order = increment(),
                    type = "select",
                    style = "dropdown",
                    name = "Remove Frame",
                    width = "full",
                    values = function()
                        local tempTable = {}
                        if not next(ns.Core.db.customFrames) then
                            return { [''] = ' * No frames are currently watched *' }
                        end
                        for frame, _ in pairs(ns.Core.db.customFrames) do
                            tempTable[frame] = frame
                        end
                        return tempTable
                    end,
                    get = function(_, _) return false end,
                    set = function(_, index, ...)
                        ns.Core.db.customFrames[index] = nil
                    end,
                },
                listOfFrames = {
                    order = increment(),
                    type = "description",
                    name = function()
                        local text = wrapName("Currently watched frames:") .. "\n"
                        for k, _ in pairs(ns.Core.db.customFrames) do
                            local frame = ns.Core:GetFrameByName(k)
                            local context = frame and " (exists)" or " (not found, might not be loaded yet)"
                            text = text .. " - " .. k .. context .. "\n"
                        end
                        return text
                    end,
                },
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
                        ns.Core.db.dialogBlacklist[value] = true
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
                        if not next(ns.Core.db.dialogBlacklist) then
                            return { [''] = ' * No texts are currently ignored *' }
                        end
                        for text, _ in pairs(ns.Core.db.dialogBlacklist) do
                            tempTable[text] = text
                        end
                        return tempTable
                    end,
                    get = function(_, _) return false end,
                    set = function(_, index, ...)
                        ns.Core.db.dialogBlacklist[index] = nil
                    end,
                },
                listOfTexts = {
                    order = increment(),
                    type = "description",
                    name = function()
                        local text = wrapName("Currently ignored texts:") .. "\n"
                        for k, _ in pairs(ns.Core.db.dialogBlacklist) do
                            text = text .. " - " .. k .. "\n"
                        end
                        return text
                    end,
                },
            },
        },
    },
}
