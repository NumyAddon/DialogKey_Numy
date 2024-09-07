--- @class DialogKeyNS
local ns = select(2, ...)

ns.defaultOptions = {
    keys = {
        "SPACE",
    },
    ignoreDisabledButtons = false,
    showGlow = true,
    dialogBlacklist = {},
    customFrames = {},
    numKeysForGossip = true,
    numKeysForQuestRewards = true,
    dontClickSummons = false,
    dontClickDuels = false,
    dontClickRevives = false,
    dontClickReleases = false,
    useSoulstoneRez = true,
    dontAcceptInvite = false,
    postAuctions = false,
    ignoreWithModifier = false,
}

-- Using #info here so that the option toggles/buttons/etc can be placed anywhere in the tree below and correctly update the option above via name matching.
local function optionSetter(info, val) ns.Core.db[info[#info]] = val end
local function optionGetter(info) return ns.Core.db[info[#info]] end
local function refreshPopupBlacklist()
    for i = 1, 4 do
        local popup = _G["StaticPopup" .. i]
        ns.Core:OnPopupShow(popup)
    end
end

local increment = CreateCounter();

ns.interfaceOptions = {
    type = "group",
    args = {
        header1 = {
            order = increment(),
            name = "Primary Keybinds",
            type = "header",
        };
        key1 = {
            order = increment(),
            name = "",
            type = "keybinding",
            set = (function(info, val) ns.Core.db.keys[1] = val end),
            get = (function(info) return ns.Core.db.keys[1] end),
        };
        key2 = {
            order = increment(),
            name = "",
            type = "keybinding",
            set = (function(_, val) ns.Core.db.keys[2] = val end),
            get = (function(_) return ns.Core.db.keys[2] end),
        };
        header2 = {
            order = increment(),
            name = "Options",
            type = "header",
        };
        generalGroup = {
            order = increment(),
            name = "General",
            desc = "Basic Options for personal preferences",
            type = "group",
            set = optionSetter,
            get = optionGetter,
            args = {
                showGlow = {
                    order = increment(),
                    name = "|cffffd100Enable Glow|r",
                    desc = "Show the glow effect when DialogKey clicks a button",
                    descStyle = "inline", width = "full", type = "toggle",
                };
                numKeysForGossip = {
                    order = increment(),
                    name = "|cffffd100Number keys for Gossip|r",
                    desc = "Use the number keys (1 -> 0) to select Gossip options or Quests from an NPC dialog window",
                    descStyle = "inline", width = "full", type = "toggle",
                };
                numKeysForQuestRewards = {
                    order = increment(),
                    name = "|cffffd100Number keys for Quest Rewards|r",
                    desc = "Use the number keys (1 -> 0) to select Quest rewards when multiple are available",
                    descStyle = "inline", width = "full", type = "toggle",
                };
                postAuctions = {
                    order = increment(),
                    name = "|cffffd100Post Auctions|r",
                    desc = "Allow DialogKey to Post Auctions",
                    descStyle = "inline", width = "full", type = "toggle",
                };
                dontAcceptInvite = {
                    order = increment(),
                    name = "|cffffd100Don't Accept Group Invites|r",
                    desc = "Don't allow DialogKey to accept Raid/Party Invitations",
                    descStyle = "inline", width = "full", type = "toggle",
                };
                dontClickSummons = {
                    order = increment(),
                    name = "|cffffd100Don't Accept Summons|r",
                    desc = "Don't allow DialogKey to accept Summon Requests",
                    descStyle = "inline", width = "full", type = "toggle",
                };
                dontClickDuels = {
                    order = increment(),
                    name = "|cffffd100Don't Accept Duels|r",
                    desc = "Don't allow DialogKey to accept Duel Requests",
                    descStyle = "inline", width = "full", type = "toggle",
                };
                dontClickRevives = {
                    order = increment(),
                    name = "|cffffd100Don't Accept Revives|r",
                    desc = "Don't allow DialogKey to accept Resurrections",
                    descStyle = "inline", width = "full", type = "toggle",
                };
                dontClickReleases = {
                    order = increment(),
                    name = "|cffffd100Don't Release Spirit|r",
                    desc = "Don't allow DialogKey to Release Spirit",
                    descStyle = "inline", width = "full", type = "toggle",
                };
                useSoulstoneRez = {
                    order = increment(),
                    name = "|cffffd100Use Class-specific Revive|r",
                    desc = "Use Soulstone/Ankh/etc. resurrection option when one is available and a normal/battle resurrection is not\n\nThis option |cffff0000ignores|r the |cffffd100Don't Accept Revives|r option!",
                    descStyle = "inline", width = "full", type = "toggle",
                };
            },
        };
        priorityGroup = {
            order = increment(),
            name = "Priority",
            desc = "Advanced Options to control DialogKey button priority",
            type = "group",
            set = optionSetter,
            get = optionGetter,
            args = {
                ignoreWithModifier = {
                    order = increment(),
                    name = "|cffffd100Ignore DialogKey with Modifiers|r",
                    desc = "Disable DialogKey while any modifier key is held (Shift, Alt, Ctrl)",
                    descStyle = "inline", width = "full", type = "toggle",
                };
                ignoreDisabledButtons = {
                    order = increment(),
                    name = "|cffffd100Ignore Disabled Buttons|r",
                    desc = "Don't allow DialogKey to click on disabled (greyed out) buttons",
                    descStyle = "inline", width = "full", type = "toggle",
                };
                temp = {
                    order = increment(),
                    name = "=== Advanced Priority Customization NYI ===",
                    type = "description",
                    fontSize = "medium",
                };
            },
        };
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
                };
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
                            return { [''] = ' * No frames are currently watched *' };
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
                        local text = "Currently watched frames:\n"
                        for k, _ in pairs(ns.Core.db.customFrames) do
                            local frame = ns.Core:GetFrameByName(k);
                            local context = frame and " (exists)" or " (not found, might not be loaded yet)";
                            text = text .. " - " .. k .. context .. "\n"
                        end
                        return text
                    end,
                },
            },
        };
        popupBlacklistGroup = {
            order = increment(),
            name = "Popup Blacklist",
            desc = "List of popup dialogs for DialogKey to completely ignore",
            type = "group",
            args = {
                -- fill db.dialogBlacklist
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
                        refreshPopupBlacklist()
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
                            return { [''] = ' * No texts are currently ignored *' };
                        end
                        for text, _ in pairs(ns.Core.db.dialogBlacklist) do
                            tempTable[text] = text
                        end
                        return tempTable
                    end,
                    get = function(_, _) return false end,
                    set = function(_, index, ...)
                        ns.Core.db.dialogBlacklist[index] = nil
                        refreshPopupBlacklist()
                    end,
                },
                listOfTexts = {
                    order = increment(),
                    type = "description",
                    name = function()
                        local text = "Currently ignored texts:\n"
                        for k, _ in pairs(ns.Core.db.dialogBlacklist) do
                            text = text .. " - " .. k .. "\n"
                        end
                        return text
                    end,
                },
            },
        };
    },
}
