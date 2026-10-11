--[[----------------------------------------------------------------------------

  WarbandMeDowns/ItemLevel.lua
  Projected average item levels: where a character would land if they equipped
  everything they already carry ("max"), and where they would land once the
  assignment engine also sent them what it earmarked for them ("theoretical").
  Purely presentational - nothing here feeds a recommendation. See
  WarbandMeDowns.lua for the license header covering the whole addon.

  *** Why these are deltas on top of DataStore's average, not averages ***

  The obvious implementation - add up the sixteen slots and divide - would put
  a second, independently-derived number right next to DataStore's, and any
  disagreement between them reads as a bug. DataStore's GetAverageItemLevel is
  whatever Blizzard's own GetAverageItemLevel() said at the last scan, and
  Blizzard's rules for it are not fully reproducible from the outside (how a
  two-hander with an empty offhand is counted, for one).

  So both numbers are computed as `DataStore's average + gain / 16`, where
  `gain` only ever counts slots an unequipped item actually improves. That
  makes "carries nothing useful" render *exactly* equal to the equipped
  average, and keeps the three columns from ever inverting.

  The divisor and the treatment of empty slots are not guesses: across the 22
  characters in this account's DataStore_Inventory snapshot, every stored
  averageItemLvl is an exact multiple of 1/16, including on characters with
  several empty slots - so sixteen slots, empty ones contributing zero.

  *** One latent hazard in the equipped-slot data ***

  DataStore_Inventory's ScanInventorySlot only stores a full item link when
  IsEnchanted(link) matches; otherwise it stores a bare itemID, and
  C_Item.GetDetailedItemLevelInfo on a bare itemID answers with the item's
  *base* item level, no bonus-ID upgrade track applied. That would understate
  an equipped slot and so overstate the gain against it. In practice it does
  not currently bite: IsEnchanted's pattern does not match the modern link
  format, and all 352 stored equipment slots in this account are full links,
  zero bare itemIDs. It is documented here (and in docs/DATA_SOURCES.md)
  because it is a live code path that a link-format change could reactivate.

  *** Weapon slots are a pair, because Blizzard scores them as one ***

  A two-hander counts *twice* toward the average - once for each weapon slot -
  so a character wielding one has no empty offhand as far as the average is
  concerned. Treating that slot as empty (worth 0, and free for anything in the
  bags to fill) was worth roughly +19 on a character at 295, since it handed
  out an entire extra item's worth of gain.

  That the offhand is not simply zero is forced by the stored data: an
  averageItemLvl of 295.1875 is an exact multiple of 1/16 and not of 1/15, so
  there really are sixteen contributions - and if the offhand were one of them
  at zero, that character's fifteen equipped items would have to average 315
  while their character sheet reads 295. The two-hander supplies the sixteenth.

  So while a two-hander is equipped, the offhand's baseline is the main hand's
  item level, a better two-hander gains against *both* slots, and nothing may
  be dropped into the offhand on its own - putting a shield there really means
  also swapping the main hand, which this model does not attempt. That last
  rule under-counts rather than over-counts, which is the safe direction here.

  One further deliberate approximation: level requirements are ignored
  entirely - that is the whole point of the "max" column.

----------------------------------------------------------------------------]]--

WarbandMeDowns.ItemLevel = WarbandMeDowns.ItemLevel or {}
local ItemLevel = WarbandMeDowns.ItemLevel
local Data = WarbandMeDowns.Data
local Characters = WarbandMeDowns.Characters

-- The slots that count toward an average equipped item level. Note this is
-- deliberately NOT every key in Data.EquipLocToSlotID: the shirt
-- (INVSLOT_BODY) and tabard (INVSLOT_TABARD) are equipment but never count
-- toward an item level average, and INVSLOT_RANGED is vestigial in retail
-- (bows and guns equip to the main hand).
local AiLSlots = {
    INVSLOT_HEAD,
    INVSLOT_NECK,
    INVSLOT_SHOULDER,
    INVSLOT_CHEST,
    INVSLOT_WAIST,
    INVSLOT_LEGS,
    INVSLOT_FEET,
    INVSLOT_WRIST,
    INVSLOT_HAND,
    INVSLOT_FINGER1,
    INVSLOT_FINGER2,
    INVSLOT_TRINKET1,
    INVSLOT_TRINKET2,
    INVSLOT_BACK,
    INVSLOT_MAINHAND,
    INVSLOT_OFFHAND,
}

local AiLSlotCount = #AiLSlots

-- Equip locations that can land in more than one slot, mirroring exactly the
-- special cases WarbandMeDowns.Characters.GetEquippedItemsForEquipLocation
-- already makes. Everything else resolves through Data.EquipLocToSlotID.
local MultiSlotEquipLocations = {
    INVTYPE_FINGER = { INVSLOT_FINGER1, INVSLOT_FINGER2 },
    INVTYPE_TRINKET = { INVSLOT_TRINKET1, INVSLOT_TRINKET2 },
    INVTYPE_WEAPON = { INVSLOT_MAINHAND, INVSLOT_OFFHAND },
}

-- Everything that takes up both weapon slots. The ranged locations belong here
-- too: in retail a bow or a gun equips to the *main hand*, and INVSLOT_RANGED
-- is vestigial - it is empty on every character in the DataStore snapshot this
-- was checked against. Data.EquipLocToSlotID still points them at that dead
-- slot, which is why these are resolved here rather than through it.
local TwoHandedEquipLocations = {
    INVTYPE_2HWEAPON = true,
    INVTYPE_RANGED = true,
    INVTYPE_RANGEDRIGHT = true,
    INVTYPE_THROWN = true,
}

local MainHandOnly = { INVSLOT_MAINHAND }

---@class WarbandMeDownsProjectedItemLevels
---@field maxItemLevel number? # equipping everything they already carry
---@field theoreticalItemLevel number? # ...plus what the engine would send them
---@field unresolved boolean # some item involved could not be read yet

-- *** Reading what a character is wearing

---What the character has in every item-level-relevant slot right now.
---
---An empty slot is 0 - a real, known "nothing here". An item that is present
---but not cached yet is NOT 0: it stays at whatever it is and is reported as
---unresolved instead, so a cold cache can never make a fully geared alt look
---naked (the same rule Data.GetActualItemLevel documents).
---@param character string
---@return table<number, number> slotItemLevels # keyed by inventory slot id
---@return boolean unresolved
---@return boolean twoHanded # the main hand takes up the offhand slot as well
local function ReadEquippedItemLevels(character)
    local slotItemLevels = {}
    local unresolved = false
    local mainHandLink = nil

    for _, slotId in ipairs(AiLSlots) do
        local link = Characters.GetEquippedItemLink(character, slotId)
        if slotId == INVSLOT_MAINHAND then
            mainHandLink = link
        end
        if not link then
            slotItemLevels[slotId] = 0
        else
            local itemLevel = Data.GetActualItemLevel(link)
            if itemLevel then
                slotItemLevels[slotId] = itemLevel
            else
                -- Present but unreadable: block this slot from being "improved"
                -- by pretending it is worth more than anything can beat.
                slotItemLevels[slotId] = math.huge
                unresolved = true
            end
        end
    end

    -- A two-hander is counted for both weapon slots, so the offhand is not
    -- empty here even though nothing is in it. GetInstantEquipLocation reads
    -- the location straight off the link with no cache involved - going
    -- through C_Item.GetItemInfo instead would answer nil for an uncached
    -- weapon and silently put the offhand back to zero.
    local twoHanded = false
    if mainHandLink and slotItemLevels[INVSLOT_OFFHAND] == 0 then
        local mainHandLocation = Data.GetInstantEquipLocation(mainHandLink)
        if mainHandLocation and TwoHandedEquipLocations[mainHandLocation] then
            twoHanded = true
            slotItemLevels[INVSLOT_OFFHAND] = slotItemLevels[INVSLOT_MAINHAND]
        end
    end

    return slotItemLevels, unresolved, twoHanded
end

-- *** Candidates

---Every slot an item worn at this equip location could occupy, restricted to
---the slots that count toward the average.
---@param equipLocation string?
---@return number[]? slots
---@return boolean twoHanded # occupies both weapon slots once equipped
local function CandidateSlotsFor(equipLocation)
    if not equipLocation or equipLocation == "" then
        return nil, false
    end

    if TwoHandedEquipLocations[equipLocation] then
        return MainHandOnly, true
    end

    local multi = MultiSlotEquipLocations[equipLocation]
    if multi then
        return multi, false
    end

    local slotId = Data.EquipLocToSlotID[equipLocation]
    if not slotId then
        return nil, false
    end

    for _, aiLSlotId in ipairs(AiLSlots) do
        if aiLSlotId == slotId then
            return { slotId }, false
        end
    end

    -- A shirt or a tabard: real equipment, but it never moves an item level
    -- average.
    return nil, false
end

---Turns raw entries into the shape the fill below wants: item level, the
---slots it could go in, and nothing else. Items this character could never
---wear (wrong armor class, a weapon their spec does not favor) and items that
---cannot move an average are dropped here.
---@param character string
---@param entries table[] # Assignment pool/floorExtra entries
---@return table[] candidates # { itemLevel, slots }
---@return boolean unresolved
local function BuildCandidates(character, entries)
    local candidates = {}
    local unresolved = false

    for _, entry in ipairs(entries) do
        local itemLevel = Data.GetActualItemLevel(entry.link)
        local equipLocation = Data.GetItemEquipLocation(entry.link)

        if not itemLevel or not equipLocation then
            unresolved = true
        else
            local slots, twoHanded = CandidateSlotsFor(equipLocation)
            local classID, subclassID = Data.GetItemClassAndSubclass(entry.link)

            if slots and classID and subclassID
                and Characters.CanCharacterEquipItemClass(character, classID, subclassID) then
                table.insert(candidates, {
                    itemLevel = itemLevel,
                    slots = slots,
                    twoHanded = twoHanded,
                    link = entry.link,
                })
            end
        end
    end

    -- Best first, so the greedy fill below is optimal for independent slots:
    -- once an item is placed, nothing left can want that slot more. The link
    -- tiebreak keeps two equal-item-level candidates in a stable order.
    table.sort(candidates, function(left, right)
        if left.itemLevel ~= right.itemLevel then
            return left.itemLevel > right.itemLevel
        end
        return tostring(left.link) < tostring(right.link)
    end)

    return candidates, unresolved
end

-- *** Projection

---Total item level gained by equipping the best of `entries` into the slots
---they fit, on top of what the character is already wearing. Never negative:
---an item only ever goes in if it beats what is there.
---@param character string
---@param slotItemLevels table<number, number>
---@param entries table[]
---@param twoHandedBaseline boolean # the character currently wields a two-hander
---@return number gain
---@return boolean unresolved
---@return table<number, number> projected # resulting per-slot item levels
local function ProjectGain(character, slotItemLevels, entries, twoHandedBaseline)
    local candidates, unresolved = BuildCandidates(character, entries)

    -- Work on a copy: the caller runs this twice against the same equipped
    -- baseline, once for "max" and once for "theoretical".
    local projected = {}
    for slotId, itemLevel in pairs(slotItemLevels) do
        projected[slotId] = itemLevel
    end

    -- While a two-hander is equipped both weapon slots move together: the
    -- offhand is only ever written by replacing the two-hander, never on its
    -- own. See the file header for why filling it alone is not modelled.
    local paired = twoHandedBaseline
    local gain = 0

    for _, candidate in ipairs(candidates) do
        if candidate.twoHanded then
            -- Takes both weapon slots and is scored for both, so it has to be
            -- weighed against what the two of them contribute *together* -
            -- equipping it means giving up whatever is in the offhand as well.
            -- Judging it against the main hand alone would let a two-hander
            -- that is worse than an existing offhand look like an upgrade.
            local combined = projected[INVSLOT_MAINHAND] + projected[INVSLOT_OFFHAND]
            local candidateGain = candidate.itemLevel * 2 - combined
            if candidateGain > 0 then
                gain = gain + candidateGain
                projected[INVSLOT_MAINHAND] = candidate.itemLevel
                projected[INVSLOT_OFFHAND] = candidate.itemLevel
                paired = true
            end
        else
            local weakestSlot, weakestItemLevel = nil, nil
            for _, slotId in ipairs(candidate.slots) do
                -- While a two-hander holds both slots, the offhand can only be
                -- written by replacing it, never filled on its own.
                if not (paired and slotId == INVSLOT_OFFHAND) then
                    local current = projected[slotId]
                    if current and (not weakestItemLevel or current < weakestItemLevel) then
                        weakestSlot, weakestItemLevel = slotId, current
                    end
                end
            end

            if weakestSlot and candidate.itemLevel > weakestItemLevel then
                gain = gain + (candidate.itemLevel - weakestItemLevel)
                projected[weakestSlot] = candidate.itemLevel
            end
        end
    end

    return gain, unresolved, projected
end

-- *** The per-generation cache
--
-- Everything a character's "max" number needs - their equipped baseline and
-- the items they personally own - comes out of Assignment's scan, and none of
-- it depends on settlement. That matters because
-- Characters.CharacterPriorityComparator now reads this: the comparator runs
-- inside table.sort, O(n log n) times, *while* the priority order is being
-- decided, so nothing below may call Assignment:EnsureFresh (it would recurse
-- straight back into Recompute) or Assignment:SettleAllGroups (settlement
-- walks the very order being computed). It reads the pool exactly as it
-- currently stands and no more.
--
-- The whole warband is built in one pool walk on first request and thrown away
-- wholesale by ClearCaches() from Assignment:Recompute(), the same lifecycle
-- as Pawn.ClearCaches and Characters.ClearEligibilityCache.

---@class WarbandMeDownsItemLevelCacheEntry
---@field averageItemLevel number? # DataStore's equipped average; nil means never scanned
---@field slotItemLevels table<number, number>
---@field twoHanded boolean # the main hand takes up the offhand slot as well
---@field ownedEntries table[]
---@field maxItemLevel number?
---@field unresolved boolean

---@type table<string, WarbandMeDownsItemLevelCacheEntry>?
local CharacterCache

---Builds the per-character cache for the whole warband, if it isn't built yet.
---@return table<string, WarbandMeDownsItemLevelCacheEntry>
local function EnsureCharacterCache()
    if CharacterCache then
        return CharacterCache
    end

    local owned = {}
    WarbandMeDowns.Assignment:IterateOwnedEntries(function(entry)
        owned[entry.character] = owned[entry.character] or {}
        table.insert(owned[entry.character], entry)
    end)

    CharacterCache = {}
    for _, character in ipairs(Characters.GetWarbandCharacters()) do
        local ownedEntries = owned[character] or {}
        local averageItemLevel = DataStore:GetAverageItemLevel(character)
        if not averageItemLevel or averageItemLevel <= 0 then
            averageItemLevel = nil
        end

        local slotItemLevels, unresolved, twoHanded = ReadEquippedItemLevels(character)
        local gain, gainUnresolved = ProjectGain(character, slotItemLevels, ownedEntries, twoHanded)

        CharacterCache[character] = {
            averageItemLevel = averageItemLevel,
            slotItemLevels = slotItemLevels,
            twoHanded = twoHanded,
            ownedEntries = ownedEntries,
            maxItemLevel = averageItemLevel and (averageItemLevel + gain / AiLSlotCount) or nil,
            unresolved = unresolved or gainUnresolved,
        }
    end

    return CharacterCache
end

---Drops the per-generation cache. Called by WarbandMeDowns.Assignment's
---Recompute() and Reset(), alongside the other per-generation memos.
function ItemLevel.ClearCaches()
    CharacterCache = nil
end

-- *** Entry points

---Where this character would land if they equipped everything usable they
---already hold, or nil if they have never been scanned.
---
---This is the warband priority tiebreak (see
---WarbandMeDowns.Characters.CharacterPriorityComparator), so it is deliberately
---cheap and deliberately incurious: it reads whatever Assignment has scanned so
---far and never asks it to refresh or settle. Called before the first scan it
---simply finds no owned items and answers with the equipped average, which is
---the behavior the tiebreak had before this became a projection.
---@param character string
---@return number?
function ItemLevel.GetMaxItemLevel(character)
    local cached = EnsureCharacterCache()[character]
    return cached and cached.maxItemLevel
end

-- Names for the diagnostic breakdown below. Deliberately a plain table rather
-- than Blizzard's INVTYPE_* globals: this is the *slot* being reported, not an
-- item's equip location, and the two do not line up for weapons.
local SlotNames = {
    [INVSLOT_HEAD] = "Head", [INVSLOT_NECK] = "Neck", [INVSLOT_SHOULDER] = "Shoulder",
    [INVSLOT_CHEST] = "Chest", [INVSLOT_WAIST] = "Waist", [INVSLOT_LEGS] = "Legs",
    [INVSLOT_FEET] = "Feet", [INVSLOT_WRIST] = "Wrist", [INVSLOT_HAND] = "Hands",
    [INVSLOT_FINGER1] = "Finger 1", [INVSLOT_FINGER2] = "Finger 2",
    [INVSLOT_TRINKET1] = "Trinket 1", [INVSLOT_TRINKET2] = "Trinket 2",
    [INVSLOT_BACK] = "Back", [INVSLOT_MAINHAND] = "Main hand",
    [INVSLOT_OFFHAND] = "Off hand",
}

---A per-slot account of how one character's Max iLvl was arrived at, for
---/wmd ilvl. Read-only: it re-derives from the same cached baseline the column
---uses rather than forming a second opinion, so what it prints is what the
---column shows.
---
---This exists because the number is otherwise unauditable - a single figure
---with no way to see which slot produced it, which is exactly how an empty
---off-hand slot managed to inflate it by an entire item.
---@param character string
---@return table? breakdown # { rows = { {slot, name, baseline, projected, gain} }, ... }
function ItemLevel.ExplainMaxItemLevel(character)
    local cached = EnsureCharacterCache()[character]
    if not cached then
        return nil
    end

    local _, _, projected = ProjectGain(
        character, cached.slotItemLevels, cached.ownedEntries, cached.twoHanded)

    local rows = {}
    local gain = 0
    for _, slotId in ipairs(AiLSlots) do
        local baseline = cached.slotItemLevels[slotId]
        local after = projected[slotId]
        gain = gain + (after - baseline)
        table.insert(rows, {
            slot = slotId,
            name = SlotNames[slotId] or tostring(slotId),
            baseline = baseline,
            projected = after,
            gain = after - baseline,
        })
    end

    local _, overallItemLevel = DataStore:GetAverageItemLevel(character)

    return {
        rows = rows,
        twoHanded = cached.twoHanded,
        ownedCount = #cached.ownedEntries,
        averageItemLevel = cached.averageItemLevel,
        maxItemLevel = cached.maxItemLevel,
        -- Blizzard's own "best gear you own" figure. Not a target to match -
        -- Max iLvl also counts the bank and mail and ignores level
        -- requirements - but a Max iLvl far above this on a max-level
        -- character is the signature of a slot being scored wrong.
        overallItemLevel = overallItemLevel,
        gain = gain,
    }
end

---Projected item levels for the whole warband, keyed by character.
---
---Deliberately one call for the entire table rather than one per row: the
---engine only has to be brought up to date and fully settled once, and the
---pool is walked once instead of once per character.
---@return table<string, WarbandMeDownsProjectedItemLevels>
function ItemLevel.GetProjectedItemLevelsForWarband()
    local Assignment = WarbandMeDowns.Assignment

    Assignment:EnsureFresh()

    -- Recompute settles the whole warband, so entry.claimedBy is complete
    -- by the time EnsureFresh returns.
    local incoming = {}
    Assignment:IterateOwnedEntries(function(entry)
        -- An item the engine assigned to the character who already owns it is
        -- not incoming: it is already in that character's owned entries, and
        -- counting it twice would let one physical ring fill both ring slots.
        if entry.claimedBy and entry.claimedBy ~= entry.character then
            incoming[entry.claimedBy] = incoming[entry.claimedBy] or {}
            table.insert(incoming[entry.claimedBy], entry)
        end
    end)

    local projections = {}
    for character, cached in pairs(EnsureCharacterCache()) do
        if not cached.averageItemLevel then
            projections[character] = { unresolved = false }
        else
            -- The equipped baseline and the owned gain are already cached; only
            -- the incoming items are new, and they are projected against the
            -- same baseline rather than on top of the max result.
            local combined = {}
            for _, entry in ipairs(cached.ownedEntries) do
                table.insert(combined, entry)
            end
            for _, entry in ipairs(incoming[character] or {}) do
                table.insert(combined, entry)
            end

            local gain, gainUnresolved =
                ProjectGain(character, cached.slotItemLevels, combined, cached.twoHanded)

            projections[character] = {
                maxItemLevel = cached.maxItemLevel,
                theoreticalItemLevel = cached.averageItemLevel + gain / AiLSlotCount,
                unresolved = cached.unresolved or gainUnresolved
                    or Assignment:HasUnreadableItems(character),
            }
        end
    end

    return projections
end
