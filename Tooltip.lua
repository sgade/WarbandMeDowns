--[[----------------------------------------------------------------------------

  WarbandMeDowns/Tooltip.lua
  Addon lifecycle, the GameTooltip hook, and cache-invalidation event wiring.
  See WarbandMeDowns.lua for the license header covering the whole addon.

----------------------------------------------------------------------------]]--

local Characters = WarbandMeDowns.Characters
local Data = WarbandMeDowns.Data

-- *** Lifecycle

function WarbandMeDowns:OnInitialize()
    WarbandMeDowns.Settings:Initialize()
    WarbandMeDowns.Diagnostics:Initialize()
end

function WarbandMeDowns:OnEnable()
    WarbandMeDowns:HookItemTooltips()
    WarbandMeDowns:RegisterCacheInvalidationEvents()

    --@debug@
    WarbandMeDowns:Print("Hooked and ready.")
    --@end-debug@
end

function WarbandMeDowns:OnDisable()
    -- The events registered below are dropped for us: AceAddon calls
    -- OnEmbedDisable on every embedded library, and AceEvent's unregisters
    -- everything.
    WarbandMeDowns.Assignment:Reset()

    --@debug@
    WarbandMeDowns:Print("Disabled.")
    --@end-debug@
end

function WarbandMeDowns:HookItemTooltips()
    if WarbandMeDowns.tooltipHooksRegistered then
        return
    end

    WarbandMeDowns.tooltipHooksRegistered = true

    local function onTooltipSetItem(frame, ...)
        local success, errorMessage = pcall(WarbandMeDowns.OnTooltipSetItem, WarbandMeDowns, frame, ...)
        if not success then
            WarbandMeDowns:Print("tooltip error: " .. tostring(errorMessage))
        end
    end

    if TooltipDataProcessor then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(frame, ...)
            if frame == GameTooltip and WarbandMeDowns:IsEnabled() then
                return onTooltipSetItem(frame, ...)
            end
        end)
    else
        -- legacy
        GameTooltip:HookScript('OnTooltipSetItem', function (...)
            onTooltipSetItem(GameTooltip, ...)
        end)
    end
end

---Any of these means something the engine reads may have changed. They all
---land on the same MarkDirty - which event it was never matters, only that
---the answer might be stale now. That only sets a flag; the recompute waits
---for the next tooltip that needs it.
function WarbandMeDowns:OnCacheInvalidated()
    WarbandMeDowns.Assignment:MarkDirty()
end

---Fires for every item anything in the client loads - chat links, loot,
---other addons. Only an item the last recompute was still waiting for can
---change an answer.
---@param itemID number
function WarbandMeDowns:OnItemInfoReceived(_, itemID)
    if WarbandMeDowns.Data.IsAwaitedItem(itemID) then
        WarbandMeDowns.Assignment:MarkDirty()
    end
end

---An heirloom's item level follows the level of the character looking at it,
---so the per-link item cache is stale once the level changes.
function WarbandMeDowns:OnPlayerLevelUp()
    WarbandMeDowns.Data.ClearItemCache()
    WarbandMeDowns.Assignment:MarkDirty()
end

function WarbandMeDowns:RegisterCacheInvalidationEvents()
    local events = {
        "BAG_UPDATE_DELAYED",
        "BANKFRAME_CLOSED",
        "MAIL_CLOSED",
        "MAIL_INBOX_UPDATE",
        "MAIL_SEND_SUCCESS",
        "MAIL_SUCCESS",
        "PLAYER_AVG_ITEM_LEVEL_UPDATE",
        "PLAYER_EQUIPMENT_CHANGED",
        "PLAYER_SPECIALIZATION_CHANGED",
        "PLAYERBANKSLOTS_CHANGED",
        "PLAYERREAGENTBANKSLOTS_CHANGED",
    }

    -- Still wrapped in pcall despite going through AceEvent: AceEvent routes to
    -- the same frame:RegisterEvent underneath, so an event name this client
    -- does not know still raises. One unsupported event must not take the rest
    -- of the list with it.
    for _, eventName in ipairs(events) do
        pcall(self.RegisterEvent, self, eventName, "OnCacheInvalidated")
    end
    pcall(self.RegisterEvent, self, "GET_ITEM_INFO_RECEIVED", "OnItemInfoReceived")
    pcall(self.RegisterEvent, self, "PLAYER_LEVEL_UP", "OnPlayerLevelUp")
end

-- *** Setting the tooltip

---Live ItemLocation for whatever real item instance the tooltip is
---currently displaying (bags/bank/equipped/mail/trade/AH/...) - nil for
---anything without a live backing instance (a bare chat item link, ...) or
---on clients predating this API.
---@param frame GameTooltip
---@return ItemLocation?
local function GetHoveredItemLocation(frame)
    if not frame.GetPrimaryTooltipData or not C_Item.GetItemLocation then
        return nil
    end

    local tooltipData = frame:GetPrimaryTooltipData()
    local guid = tooltipData and tooltipData.guid
    if not guid then
        return nil
    end

    local location = C_Item.GetItemLocation(guid)
    if not location then
        return nil
    end

    -- IsValid() is C_Item.DoesItemExist(self) under the hood, which throws
    -- rather than returning false for a location that isn't a valid
    -- "emptiable" kind at this instant - real during rapid item-instance
    -- churn (e.g. an item-level upgrade recreating the item in its slot).
    local success, isValid = pcall(location.IsValid, location)
    if success and isValid then
        return location
    end

    return nil
end

---Hooks the tooltip
---@param frame GameTooltip
function WarbandMeDowns:OnTooltipSetItem(frame, ...)
    ---@type string, ItemInfo
    ---@diagnostic disable-next-line: assign-type-mismatch
    local _, itemLink = frame:GetItem()
    if not itemLink then
        return
    end

    local itemLocation = GetHoveredItemLocation(frame)
    local result = WarbandMeDowns.Assignment:GetBestCharacterForItem(itemLink, itemLocation)
    if not result then
        return
    end

    -- The answer depends on item data the client hasn't cached yet. Say
    -- nothing rather than guess: asking for that data is what queues the load,
    -- GET_ITEM_INFO_RECEIVED then marks the engine dirty, and the line shows
    -- up on the next hover a moment later. A wrong character - or a premature
    -- "sell it" - is far worse than a line that arrives late.
    if result == WarbandMeDowns.Assignment.Pending then
        return
    end

    if result == WarbandMeDowns.Assignment.Sell then
        frame:AddLine("WarbandMeDowns! No character can use this - sell it.", 0, 0.75, 0.33, false)
        return
    end

    local upgradeInfo = result

    local distributionInfo = (function()
        if upgradeInfo[1] == DataStore.ThisCharKey then
            -- Required level is not checked when assigning, so the item can
            -- go to the character who will grow into it - including this one.
            local requiredLevel = Data.GetItemRequiredLevel(itemLink)
            if requiredLevel and requiredLevel > UnitLevel("player") then
                return "Save here for later!"
            end
            return "Use here!"
        else
            return "WarbandMeDowns! Send this to " .. Characters.GetDisplayName(upgradeInfo[1]) .. "."
        end
    end)()

    local upgradeDescription = "Upgrade from " .. upgradeInfo[2] .. " to " .. upgradeInfo[3]
    -- Only for an alt: on this character, Pawn's own tooltip lines already
    -- say how much better it is.
    local pawnPercent = upgradeInfo[4]
    if upgradeInfo[1] ~= DataStore.ThisCharKey and pawnPercent then
        upgradeDescription = upgradeDescription .. " (" .. pawnPercent .. "% improvement)"
    end
    upgradeDescription = upgradeDescription .. "."

    frame:AddLine(distributionInfo .. " " .. upgradeDescription, 0, 0.75, 0.33, false)
end
