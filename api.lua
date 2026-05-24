--- @class DialogKeyNS
local ns = select(2, ...);

_G.DialogKeyAPI = {};

--- @class DialogKeyAPI
local DialogKeyAPI = _G.DialogKeyAPI;
ns.API = DialogKeyAPI;

DialogKeyAPI.Enum = {}

--- @enum DialogKeyAPI.Enum.FrameType
DialogKeyAPI.Enum.FrameType = {
    Popup = "Popup",
    CraftingOrder = "CraftingOrder",
    CustomFrame = "CustomFrame",
    AuctionHouse = "AuctionHouse",
    PlayerChoice = "PlayerChoice",
    SpecFrame = "SpecFrame",
    Quest = "Quest",
    Gossip = "Gossip",
};

--- Register a custom button for
--- @param frameType DialogKeyAPI.Enum.FrameType
--- @param button Button|fun():Button|nil
function DialogKeyAPI:RegisterAddonFrame(frameType, button)
    if (not self.Enum.FrameType[frameType]) then
        error('Invalid frame type: ' .. tostring(frameType));
    end

    if (not button or (type(button) ~= "function" and not button:IsObjectType("Button"))) then
        error("'button' must be a Button object or a function that returns a Button or nil.");
    end

    ns.Core:RegisterAddonFrame(frameType, button);
end

--- @param frameType DialogKeyAPI.Enum.FrameType
--- @param button Button|fun():Button|nil
function DialogKeyAPI:UnregisterAddonFrame(frameType, button)
    if (not self.Enum.FrameType[frameType]) then
        error('Invalid frame type: ' .. tostring(frameType));
    end

    if (not button or (type(button) ~= "function" and not button:IsObjectType("Button"))) then
        error("'button' must be a Button object or a function that returns a Button or nil.");
    end

    ns.Core:UnregisterAddonFrame(frameType, button);
end

