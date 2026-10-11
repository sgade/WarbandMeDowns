--[[----------------------------------------------------------------------------

  WarbandMeDowns/Assignment.lua
  The global warband assignment engine.

  Instead of answering "is this hovered item an upgrade?" from scratch on
  every tooltip, this precomputes, per warband character and per equipment
  slot, which item they should end up with - considering every equipped,
  bagged, banked, and mailed item across the whole warband at once, so a
  spare in one character's bag can cascade down to a lower-priority
  character instead of being invisible to the recommendation. See
  WarbandMeDowns.lua for the license header covering the whole addon.

  Every item instance in the warband falls into exactly one bucket, decided
  once per recompute in ScanWarband:
    1. Equipped (any bind type) - always a floor a candidate must beat for
       that character/slot. Never reassigned to anyone else.
    2. Bag/bank/mail, NOT sendable to a twink (soulbound, actually already
       Soulbound despite a sendable-looking bind type, or below Uncommon
       quality) - also a floor, but can never be claimed by another
       character.
    3. Bag/bank/mail, sendable to a twink - the only items ever reassigned;
       up for grabs by any eligible character in the warband, including
       their current owner.

  A bind type like "Bind on Equip" or "Warbound until equipped" only
  describes what an item *will* do, not whether a specific instance has
  already bound - see Data.IsActuallySoulbound for how that's resolved.

  Everything - the full warband scan and the settlement of every
  (slot-class, target equip location) pair - happens once per recompute, in
  one fixed order. Tooltips then only read the result. Settling lazily, a
  group at a time as items were hovered, made the answer depend on what was
  hovered first: a claim in one group removes the item from every other group
  it could satisfy (an ambidextrous one-hander feeds both weapon hands).

  *** The answer must not depend on who is logged in ***

  The engine reads stored, account-wide DataStore snapshots, so the same
  item must produce the same recommendation from every character. Three
  things used to break that invariant, and the design below exists to keep
  them fixed:

    - Unreadable items are a distinct state, never a zero. C_Item.GetItemInfo
      and C_Item.GetDetailedItemLevelInfo both return nil for an item the
      client has not cached, which is routine for an alt's stored gear right
      after login. Scoring that as "item level 0" made the alt look like they
      had an empty slot and hand them the item - and since cache warmth
      differs every session, the winner moved around. Anything unreadable now
      yields Assignment.Pending and no tooltip line until the data arrives.

    - Comparisons are transitive. A single *basis* (Pawn score, or item level)
      is chosen once per character per settlement and used for every
      comparison in it, instead of falling back per pair. Mixing two orderings
      in one chain made the greedy winner depend on scan order.

    - A hovered item is matched to its scanned instance by bag and slot
      first, and by a normalized link only after that. The tooltip's link and
      the one DataStore stored need not be the same string (an empty name
      when the item was scanned uncached, the level and spec fields), and an
      owned item that failed to match fell through to the foreign path, tied
      with itself there, and read "sell it".

    - Iteration is deterministic. Characters are walked in priority order and
      every candidate bucket is sorted on a stable key, so Lua's `pairs`
      ordering over DataStore's container tables can never leak into the
      result. Priority order itself is a total order down to the character
      key, since table.sort is not stable and would otherwise let the input
      order decide between equally-ranked characters.

  Note Recompute() runs the scan *before* it computes the priority order, not
  after: the order ranks characters on what they own, which only exists once
  the scan has run. See the comment there for why scanning under a provisional
  order is safe.

----------------------------------------------------------------------------]]--

WarbandMeDowns.Assignment = WarbandMeDowns.Assignment or {}
local Assignment = WarbandMeDowns.Assignment
local Data = WarbandMeDowns.Data
local Characters = WarbandMeDowns.Characters
local Pawn = WarbandMeDowns.Pawn

-- Sentinels, mirroring the old CacheMiss idiom.
Assignment.Sell = {}         -- confirmed upgrade for nobody: drives the tooltip's sell line
Assignment.Pending = {}      -- the answer depends on item data the client has not cached yet

-- Where a pool/floorExtra entry was found. Only used to order entries
-- deterministically and to match a hovered item back to its exact instance.
local SourceContainer = 1
local SourceMail = 2

-- Bucket for an unreadable item whose equip location we could not determine
-- either; it has to count against every slot of its class.
local AnyEquipLocation = "*"

-- The targets one pool item can be claimed for besides its own location -
-- see Data.EquipLocationsMatch and Assignment:_SettleableGroups.
local OneHandWeaponTargets = { "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND" }

-- Per-generation state, wiped wholesale by Recompute()/Reset() - see below.
Assignment.dirty = true
Assignment.pool = {}              -- pool[slotClassKey][rawEquipLoc] = { entry, ... }       (sendable bag/bank/mail items)
Assignment.floorExtra = {}        -- floorExtra[slotClassKey][rawEquipLoc] = { entry, ... }  (unsendable bag/bank/mail items)
Assignment.entriesByLink = {}     -- entriesByLink[linkKey] = { entry, ... }                 (every pool entry sharing a normalized link)
Assignment.entriesBySlot = {}     -- entriesBySlot[containerId][slotId] = entry              (the current character's own pool entries)
Assignment.settledCache = {}      -- settledCache[slotClassKey][targetEquipLoc][character] = { claims = { entry, ... }, held = { itemLink, ... }, slotCount = n }
Assignment.unresolvedCache = {}   -- unresolvedCache[slotClassKey][targetEquipLoc][character] = true
Assignment.unresolvedOwners = {}  -- unresolvedOwners[slotClassKey][equipLoc][character] = true (owns an unreadable item competing there)
Assignment._sortedCharacters = {}
Assignment._debounceTimer = nil

-- *** Scoring
--
-- A "scorer" fixes one comparison basis for one character for the duration of
-- one decision. Pawn's score is authoritative whenever a scale resolves for
-- the character AND Pawn can score every item involved; otherwise item level
-- is used for all of them. Committing to a single basis up front is what makes
-- the comparison a total order, which _ClaimBestCandidate's greedy scan relies
-- on. Falling back per pair - Pawn for A vs B, item level for B vs C - is not
-- transitive and made the winner depend on iteration order.

---@class WarbandMeDownsScorer
---@field basis string # "pawn" or "itemlevel"
---@field scaleName string? # the resolved Pawn scale, when basis is "pawn"
---@field resolved boolean # false when some item involved could not be read at all
---@field scoreOf fun(itemLink: ItemInfo?): number?

---@param character string
---@param items ItemInfo[] # every item this decision depends on
---@return WarbandMeDownsScorer
function Assignment:_BuildScorerForCharacter(character, items)
    local scaleName = Pawn.GetPawnScaleNameForCharacter(character)

    if scaleName then
        local scores = {}
        local scoredEverything = true

        for _, itemLink in ipairs(items) do
            if scores[itemLink] == nil then
                local value = Pawn.GetPawnItemValue(itemLink, scaleName)
                if not value then
                    scoredEverything = false
                    break
                end
                scores[itemLink] = value
            end
        end

        if scoredEverything then
            return {
                basis = "pawn",
                scaleName = scaleName,
                -- Pawn can only score an item it was able to parse, so a
                -- complete Pawn pass implies every item was readable.
                resolved = true,
                scoreOf = function(itemLink)
                    if not itemLink then
                        return nil
                    end
                    return scores[itemLink]
                end,
            }
        end
    end

    local resolved = true
    for _, itemLink in ipairs(items) do
        if not Data.IsItemInfoResolved(itemLink) then
            resolved = false
        end
    end

    return {
        basis = "itemlevel",
        scaleName = nil,
        resolved = resolved,
        scoreOf = function(itemLink)
            if not itemLink then
                return nil
            end
            return Data.GetActualItemLevel(itemLink)
        end,
    }
end

---Compares two items on a scorer's single basis. A missing item (nil/false,
---an empty slot) always loses to a present, scoreable one and ties against
---another missing item - but an item that is *present and unreadable* is not
---a loss, it is an unanswered question, and returns nil so the caller can
---decline to decide rather than silently treating it as worthless.
---@param scorer WarbandMeDownsScorer
---@param itemLinkA ItemInfo?
---@param itemLinkB ItemInfo?
---@return integer? # 1 if A is preferred, -1 if B is preferred, 0 if tied, nil if undecidable
local function CompareWithScorer(scorer, itemLinkA, itemLinkB)
    if not itemLinkA and not itemLinkB then
        return 0
    end

    local scoreA = itemLinkA and scorer.scoreOf(itemLinkA)
    local scoreB = itemLinkB and scorer.scoreOf(itemLinkB)
    if (itemLinkA and not scoreA) or (itemLinkB and not scoreB) then
        return nil
    end

    scoreA = scoreA or -math.huge
    scoreB = scoreB or -math.huge
    if scoreA == scoreB then
        return 0
    end

    return scoreA > scoreB and 1 or -1
end
Assignment.CompareWithScorer = CompareWithScorer

---Compares two items of the same slot-class for a character. Convenience
---wrapper that builds a throwaway scorer for just this pair; the settlement
---path builds one scorer per character instead, so every comparison inside a
---settlement shares one basis.
---@param character string
---@param itemLinkA ItemInfo?
---@param itemLinkB ItemInfo?
---@return integer? # 1 if A is preferred, -1 if B is preferred, 0 if tied, nil if undecidable
function Assignment.CompareItemsForCharacter(character, itemLinkA, itemLinkB)
    local items = {}
    if itemLinkA then
        table.insert(items, itemLinkA)
    end
    if itemLinkB then
        table.insert(items, itemLinkB)
    end

    local scorer = Assignment:_BuildScorerForCharacter(character, items)
    return CompareWithScorer(scorer, itemLinkA, itemLinkB)
end

-- *** Phase A: single full pass over every character's bag/bank/mail items

local WarnedMissingMailAPI = false

---Total order over entries, so the candidate list never depends on Lua's
---`pairs` ordering over DataStore's container tables (which is arbitrary and
---differs between sessions).
---@param left table
---@param right table
---@return boolean
local function CompareEntries(left, right)
    if left.character ~= right.character then
        return left.character < right.character
    end
    if left.source ~= right.source then
        return left.source < right.source
    end
    if left.containerId ~= right.containerId then
        return left.containerId < right.containerId
    end
    if left.slotId ~= right.slotId then
        return left.slotId < right.slotId
    end
    return tostring(left.link) < tostring(right.link)
end

---A table's keys in sorted order. Every walk over the bucket tables goes
---through this: `pairs` order over them is arbitrary and differs between
---sessions, and the whole engine rests on that never reaching a result.
---@param source table
---@return string[]
local function SortedKeys(source)
    local keys = {}
    for key in pairs(source) do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

---Buckets one bag/bank/mail item into the pool (sendable) or floorExtra
---(unsendable) table for its slot-class, keyed by its own equip location.
---@param character string
---@param itemLink ItemInfo?
---@param itemLocation ItemLocation? # live location, only ever set for the current character's own bag/bank items
---@param source integer # SourceContainer or SourceMail
---@param containerId number
---@param slotId number
function Assignment:_ClassifyItem(character, itemLink, itemLocation, source, containerId, slotId)
    if not itemLink then
        return
    end

    -- GetItemInfoInstant works straight off the link with no cache involved,
    -- so this cheap filter runs before anything that can fail.
    local classID, subclassID = Data.GetItemClassAndSubclass(itemLink)
    if classID ~= Data.ItemClassArmor and classID ~= Data.ItemClassWeapon then
        return
    end

    local slotClassKey = Data.SlotClassKey(classID, subclassID)

    -- Everything below needs the client's item cache. Remember that this
    -- character has something unreadable, so any recommendation that would
    -- depend on them is withheld rather than being made on partial data.
    --
    -- Record it against the exact slot it would compete for, so an unreadable
    -- helm cannot suppress an answer about rings. Both halves of that key come
    -- from GetItemInfoInstant, which is served off the link and needs no
    -- cache; note the slot-class alone is far too coarse, since
    -- Data.SlotClassKey deliberately collapses every kind of armour into one
    -- bucket and leaves the equip location to tell a helm from a ring. An
    -- unknown location falls back to the AnyEquipLocation wildcard.
    --
    -- The IsItemInfoResolved call itself queues the async load, and
    -- GET_ITEM_INFO_RECEIVED brings us back for another pass.
    if not Data.IsItemInfoResolved(itemLink) then
        local instantEquipLoc = Data.GetInstantEquipLocation(itemLink)
        if not instantEquipLoc or instantEquipLoc == "" then
            instantEquipLoc = AnyEquipLocation
        end

        local byLocation = self.unresolvedOwners[slotClassKey]
        if not byLocation then
            byLocation = {}
            self.unresolvedOwners[slotClassKey] = byLocation
        end

        local owners = byLocation[instantEquipLoc]
        if not owners then
            owners = {}
            byLocation[instantEquipLoc] = owners
        end
        owners[character] = true
        return
    end

    local equipLoc = Data.GetItemEquipLocation(itemLink)
    if not equipLoc or equipLoc == "" then
        return
    end

    local bind = Data.GetItemBind(itemLink)
    local quality = Data.GetItemQuality(itemLink)
    local sendable = bind and Data.CanItemBeSentToTwink(bind)
        and Data.IsQualityEligible(quality)
        and not Data.IsActuallySoulbound(bind, false, itemLocation)

    local entry = {
        link = itemLink,
        character = character,
        source = source,
        containerId = containerId,
        slotId = slotId,
    }

    local bucketTable = sendable and self.pool or self.floorExtra
    bucketTable[slotClassKey] = bucketTable[slotClassKey] or {}
    bucketTable[slotClassKey][equipLoc] = bucketTable[slotClassKey][equipLoc] or {}
    table.insert(bucketTable[slotClassKey][equipLoc], entry)

    if sendable then
        local linkKey = Data.NormalizedLinkKey(itemLink)
        local entries = self.entriesByLink[linkKey]
        if not entries then
            entries = {}
            self.entriesByLink[linkKey] = entries
        end
        table.insert(entries, entry)

        if source == SourceContainer and character == DataStore.ThisCharKey then
            self.entriesBySlot[containerId] = self.entriesBySlot[containerId] or {}
            self.entriesBySlot[containerId][slotId] = entry
        end
    end
end

---One pass over every character's bags, bank, and mail. Equipped items are
---deliberately not scanned here: they're read on demand from DataStore (a
---handful of O(1) slot lookups) inside SettleGroup, since they're
---never reassignable and don't need bulk bucketing.
---
---Requires self._sortedCharacters to already be populated - Recompute() sorts
---before scanning so this walk is in a stable order.
function Assignment:ScanWarband()
    self.pool = {}
    self.floorExtra = {}
    self.entriesByLink = {}
    self.entriesBySlot = {}
    self.settledCache = {}
    self.unresolvedCache = {}
    self.unresolvedOwners = {}

    for _, character in ipairs(self._sortedCharacters) do
        local isCurrentCharacter = character == DataStore.ThisCharKey

        Characters.IterateStoredContainerItems(character, function(containerId, _, slotId, _, itemLink)
            local itemLocation = isCurrentCharacter and Data.GetLiveBagItemLocation(containerId, slotId) or nil
            self:_ClassifyItem(character, itemLink, itemLocation, SourceContainer, containerId, slotId)
        end)

        if DataStore.IterateMails then
            local mailIndex = 0
            DataStore:IterateMails(character, function(_, _, mailItemLink)
                mailIndex = mailIndex + 1
                -- no ItemLocation for mail, and no container to key on
                self:_ClassifyItem(character, mailItemLink, nil, SourceMail, 0, mailIndex)
            end)
        elseif not WarnedMissingMailAPI then
            WarnedMissingMailAPI = true
            --@alpha@
            WarbandMeDowns:Print("warn: DataStore.IterateMails not available.")
            --@end-alpha@
        end
    end

    self:_SortBuckets()
end

---Puts every bucket into CompareEntries order once, after the scan, so the
---arbitrary `pairs` order DataStore's container tables are iterated in cannot
---influence which candidate a character claims.
function Assignment:_SortBuckets()
    for _, bucketsBySlotClass in ipairs({ self.pool, self.floorExtra }) do
        for _, buckets in pairs(bucketsBySlotClass) do
            for _, entries in pairs(buckets) do
                table.sort(entries, CompareEntries)
            end
        end
    end

    for _, entries in pairs(self.entriesByLink) do
        table.sort(entries, CompareEntries)
    end
end

-- *** Phase C: lazy, memoized cascading assignment per (slot-class, target equip location)

---@param itemLink ItemInfo
---@param slotClassKey string
---@return boolean
local function IsSameSlotClass(itemLink, slotClassKey)
    local classID, subclassID = Data.GetItemClassAndSubclass(itemLink)
    return Data.SlotClassKey(classID, subclassID) == slotClassKey
end

---Everything this character already has for this location: the equipped
---slots, plus the unsendable bag/bank/mail items they could put on instead.
---
---A slot contributes nothing when it is empty, or when it holds an item of a
---different slot-class. GetEquippedItemsForEquipLocation resolves purely by
---inventory slot (both offhand-slot types for INVTYPE_SHIELD/INVTYPE_HOLDABLE,
---both hands for a dual-wielder's INVTYPE_WEAPON), so it can hand back an item
---that is not comparable at all - a Sword next to an equipped Dagger, a Shield
---where a Holdable is worn. Such an item cannot serve as the bar, and the slot
---is going to be taken over anyway, so it counts as empty.
---
---Unsendable bag/bank/mail items are not slots but alternatives: if the
---character already owns a better ring they cannot send away, they would wear
---that instead of receiving this one.
---@param character string
---@param slotClassKey string
---@param floorExtra table[] # unsendable bag/bank/mail entries relevant to this target
---@param equipped ItemInfo[]
---@param slotCount number
---@return ItemInfo[]
local function HeldItems(character, slotClassKey, floorExtra, equipped, slotCount)
    local held = {}

    for index = 1, slotCount do
        local equippedLink = equipped[index]
        if equippedLink and IsSameSlotClass(equippedLink, slotClassKey) then
            table.insert(held, equippedLink)
        end
    end

    for _, entry in ipairs(floorExtra) do
        if entry.character == character then
            table.insert(held, entry.link)
        end
    end

    return held
end

---The bar a new item has to beat: the worst item the character would still be
---wearing, i.e. the `slotCount`-th best of everything they hold. nil when they
---do not hold enough to fill every slot - an empty slot takes anything.
---
---For a location with more than one slot (two rings, two trinkets, a
---dual-wielder's hands) a new item displaces the *worst* of them, so the worst
---is the bar. Using the best instead - as an earlier version did - meant a
---character with one good ring rejected every ring, and the item cascaded down
---the warband to someone who needed it less.
---
---An item the scorer cannot read sorts as if it were the best, so a cold cache
---can never make a slot look free; the settlement is flagged unresolved in that
---case anyway.
---@param scorer WarbandMeDownsScorer
---@param held ItemInfo[]
---@param slotCount number
---@return ItemInfo?
local function HeldFloor(scorer, held, slotCount)
    if slotCount < 1 or #held < slotCount then
        return nil
    end

    local sorted = {}
    for _, link in ipairs(held) do
        table.insert(sorted, link)
    end

    table.sort(sorted, function(left, right)
        local leftScore = scorer.scoreOf(left) or math.huge
        local rightScore = scorer.scoreOf(right) or math.huge
        if leftScore ~= rightScore then
            return leftScore > rightScore
        end
        return tostring(left) < tostring(right)
    end)

    return sorted[slotCount]
end

---Unions every pool/floorExtra bucket whose own equip location satisfies
---Data.EquipLocationsMatch(candidateLoc, targetEquipLoc) against targetEquipLoc -
---reusing that predicate exactly as-is, including its asymmetry. The result is
---re-sorted because the buckets are visited in `pairs` order.
---@param bucketsBySlotClass table
---@param slotClassKey string
---@param targetEquipLoc string
---@return table[]
local function UnionMatchingBuckets(bucketsBySlotClass, slotClassKey, targetEquipLoc)
    local result = {}
    local buckets = bucketsBySlotClass[slotClassKey]
    if not buckets then
        return result
    end

    for loc, entries in pairs(buckets) do
        if Data.EquipLocationsMatch(loc, targetEquipLoc) then
            for _, entry in ipairs(entries) do
                table.insert(result, entry)
            end
        end
    end

    table.sort(result, CompareEntries)
    return result
end

---The entries this character could actually wear.
---
---Necessary because a slot-class is coarser than equippability: Data.SlotClassKey
---collapses *all* armor into one key, so the candidate union for a plate chest
---also contains the cloth, leather and cosmetic chests sitting in the warband's
---bags. SettleGroup's group-level check only vets the representative subclass,
---which is not the same question as "can this character wear this particular
---item".
---
---Without this a plate wearer claims the higher-item-level cloth chest, and the
---plate upgrade they should have received is left unclaimed and reported as
---vendor trash - a wrong answer, not just a wasted comparison.
---@param character string
---@param entries table[]
---@return table[]
local function EquippableEntries(character, entries)
    local result = {}
    for _, entry in ipairs(entries) do
        if Characters.CanCharacterEquipItem(character, entry.link) then
            table.insert(result, entry)
        end
    end
    return result
end

---Every item one character's decision in this group depends on, so the scorer
---can commit to a basis that covers all of them at once.
---@param character string
---@param equipped ItemInfo[]
---@param slotCount number
---@param floorExtra table[]
---@param candidates table[]
---@return ItemInfo[]
local function CollectRelevantItems(character, equipped, slotCount, floorExtra, candidates)
    local items = {}

    for index = 1, slotCount do
        if equipped[index] then
            table.insert(items, equipped[index])
        end
    end

    for _, entry in ipairs(floorExtra) do
        if entry.character == character then
            table.insert(items, entry.link)
        end
    end

    for _, entry in ipairs(candidates) do
        if not entry.claimedBy then
            table.insert(items, entry.link)
        end
    end

    return items
end

---Everyone who owns an unreadable item that would compete for this exact
---target slot, and so cannot be judged for it yet. Uses the same
---Data.EquipLocationsMatch predicate the candidate buckets do, so an
---unreadable ambidextrous one-hander counts against both weapon hands
---exactly like a readable one would.
---@param slotClassKey string
---@param targetEquipLoc string
---@return table<string, boolean>
function Assignment:_UnreadableOwnersFor(slotClassKey, targetEquipLoc)
    local result = {}

    local byLocation = self.unresolvedOwners[slotClassKey]
    if not byLocation then
        return result
    end

    for equipLoc, owners in pairs(byLocation) do
        if equipLoc == AnyEquipLocation or Data.EquipLocationsMatch(equipLoc, targetEquipLoc) then
            for character in pairs(owners) do
                result[character] = true
            end
        end
    end

    return result
end

---Scans the whole unclaimed candidate pool for the single best entry that
---beats the character's floor, claiming it if found. Unlike a plain
---item-level ordering, a lower-ilvl entry can still win once Pawn score is
---authoritative, so this can't stop early the way an item-level-sorted scan
---could - it has to consider every unclaimed candidate. Correct despite
---comparing entries pairwise against a moving `best` rather than against
---`floor` every time, because a scorer is a single total order: once `best`
---already beats `floor`, anything that beats `best` also beats `floor`.
---@param character string
---@param candidates table[]
---@param floor ItemInfo?
---@param scorer WarbandMeDownsScorer
---@return table? claimedEntry
function Assignment:_ClaimBestCandidate(character, candidates, floor, scorer)
    local best = nil

    for _, entry in ipairs(candidates) do
        if not entry.claimedBy then
            local reference = best and best.link or floor
            if CompareWithScorer(scorer, entry.link, reference) == 1 then
                best = entry
            end
        end
    end

    return best
end

---Settles one (slot-class, target equip location) pair: walks the warband
---in priority order, greedily giving each character the best still-unclaimed
---pool candidate they can wear that beats their floor - once per slot the
---location has, so a dual-wielder can take a pair of one-handers and anyone
---can take two rings. Giving out only one item per character used to leave
---the second warglaive of a pair with nobody to go to. A claimed pool entry
---is removed from play for every other target group it could also have
---satisfied (e.g. an ambidextrous one-hander claimed while settling
---INVTYPE_WEAPON is no longer available when INVTYPE_WEAPONMAINHAND is
---settled later), which is why SettleAllGroups fixes the order. No-ops if
---already settled this generation.
---
---There is no group-level "can this character use this at all" check: for
---armor the slot-class spans cloth to plate, so any one item standing in for
---the group decided the answer for all of them. Eligibility is per entry here
---(EquippableEntries) and per hovered item in GetBestCharacterForItem.
---@param slotClassKey string
---@param targetEquipLoc string
function Assignment:SettleGroup(slotClassKey, targetEquipLoc)
    self.settledCache[slotClassKey] = self.settledCache[slotClassKey] or {}
    self.unresolvedCache[slotClassKey] = self.unresolvedCache[slotClassKey] or {}
    if self.settledCache[slotClassKey][targetEquipLoc] then
        return
    end

    local candidates = UnionMatchingBuckets(self.pool, slotClassKey, targetEquipLoc)
    local floorExtra = UnionMatchingBuckets(self.floorExtra, slotClassKey, targetEquipLoc)
    local unreadableOwners = self:_UnreadableOwnersFor(slotClassKey, targetEquipLoc)

    local settled = {}
    local unresolved = {}

    for _, character in ipairs(self._sortedCharacters) do
        local equipped, slotCount = Characters.GetEquippedItemsForEquipLocation(character, targetEquipLoc)

        -- Narrowed to what this character can actually wear before anything
        -- is scored or claimed - see EquippableEntries. The entry tables are
        -- the same objects, so claims still propagate to every other group
        -- the entry could have satisfied.
        local ownCandidates = EquippableEntries(character, candidates)
        local ownFloorExtra = EquippableEntries(character, floorExtra)

        local held = HeldItems(character, slotClassKey, ownFloorExtra, equipped, slotCount)
        local claims = {}

        -- Nothing to claim means nothing to score: the held set is all a
        -- foreign item is compared with later, and that comparison builds its
        -- own scorer.
        local hasCandidate = false
        for _, entry in ipairs(ownCandidates) do
            if not entry.claimedBy then
                hasCandidate = true
                break
            end
        end

        if hasCandidate then
            local scorer = self:_BuildScorerForCharacter(
                character,
                CollectRelevantItems(character, equipped, slotCount, ownFloorExtra, ownCandidates)
            )

            -- Each claim joins what the character holds, raising the floor the
            -- next one has to beat.
            for _ = 1, slotCount do
                local floor = HeldFloor(scorer, held, slotCount)
                local claimed = self:_ClaimBestCandidate(character, ownCandidates, floor, scorer)
                if not claimed then
                    break
                end

                claimed.claimedBy = character
                claimed.claimedOverFloor = floor
                table.insert(claims, claimed)
                table.insert(held, claimed.link)
            end

            if not scorer.resolved then
                unresolved[character] = true
            end
        end

        if unreadableOwners[character] then
            unresolved[character] = true
        end

        settled[character] = {
            claims = claims,
            held = held,
            slotCount = slotCount,
        }
    end

    self.settledCache[slotClassKey][targetEquipLoc] = settled
    self.unresolvedCache[slotClassKey][targetEquipLoc] = unresolved
end

---The bar a further item has to beat for this character once their claims in
---this group are worn, and the scorer it was decided with.
---@param character string
---@param result table # one settledCache character entry
---@param itemLink ItemInfo # the item being judged, so the scorer covers it
---@return ItemInfo? floor
---@return WarbandMeDownsScorer scorer
function Assignment:_SettledFloor(character, result, itemLink)
    local items = { itemLink }
    for _, link in ipairs(result.held) do
        table.insert(items, link)
    end

    local scorer = self:_BuildScorerForCharacter(character, items)
    return HeldFloor(scorer, result.held, result.slotCount), scorer
end

-- *** Phase D: exposing results

---@param character string
---@param itemLink ItemInfo
---@param compareItem ItemInfo?
---@return [string, number, number, boolean] upgradeInfo character, compareItemLevel, itemLevel, statOnlyUpgrade
function Assignment:BuildUpgradeInfo(character, itemLink, compareItem)
    local itemLevel = Data.GetActualItemLevel(itemLink) or 0
    local compareItemLevel = (compareItem and Data.GetActualItemLevel(compareItem)) or 0
    -- Not a strict item-level increase: either an equal-ilvl stat-only pick,
    -- or - now that Pawn score can be authoritative - a lower-ilvl item Pawn
    -- prefers anyway. Tooltip.lua distinguishes the two by re-comparing
    -- itemLevel to compareItemLevel itself.
    local statOnlyUpgrade = itemLevel <= compareItemLevel
    return { character, compareItemLevel, itemLevel, statOnlyUpgrade }
end

---@param itemLocation ItemLocation?
---@return number?, number?
local function GetBagAndSlot(itemLocation)
    if not itemLocation or not itemLocation.IsBagAndSlot or not itemLocation:IsBagAndSlot() then
        return nil, nil
    end
    return itemLocation:GetBagAndSlot()
end

---Finds the pool entry for the exact item instance the tooltip is showing.
---
---Two physically distinct items can share one item link (a second copy of the
---same ring), and they are claimed independently, so answering with whichever
---entry happened to be recorded first can name the character who received the
---*other* copy. Pin the real instance down by bag and slot when the tooltip
---gives us a live location - before looking at the link at all, since the
---tooltip's link and the stored one can differ as strings (see
---Data.NormalizedLinkKey) - then match on the normalized link, prefer the
---current character's own copy, and only then fall back to the first entry in
---the (deterministic) order.
---@param itemLink ItemInfo
---@param itemLocation ItemLocation?
---@return table?
function Assignment:_FindEntryForHoveredItem(itemLink, itemLocation)
    local bagID, slotID = GetBagAndSlot(itemLocation)
    if bagID then
        local entry = self.entriesBySlot[bagID] and self.entriesBySlot[bagID][slotID]
        -- The same item, not just the same slot: the scan can be a moment
        -- behind the bags, and the slot may hold something else by now.
        if entry and Data.GetItemID(entry.link) == Data.GetItemID(itemLink) then
            return entry
        end
    end

    local entries = self.entriesByLink[Data.NormalizedLinkKey(itemLink)]
    if not entries then
        return nil
    end

    for _, entry in ipairs(entries) do
        if entry.character == DataStore.ThisCharKey then
            return entry
        end
    end

    return entries[1]
end

---Whether any character the answer depends on is still missing item data.
---Walking only as far as the character who would win keeps this precise: a
---cold item on some low-priority alt cannot suppress an answer that was
---already decided above them, and one permanently unreadable link cannot
---silence the addon for good.
---@param unresolved table<string, boolean>
---@param stopCharacter string? # inclusive; nil checks the whole warband
---@return boolean
function Assignment:_AnyUnresolvedUpTo(unresolved, stopCharacter)
    for _, character in ipairs(self._sortedCharacters) do
        if unresolved[character] then
            return true
        end
        if stopCharacter and character == stopCharacter then
            return false
        end
    end

    return false
end

---Finds the destination for a given item: the character who should keep or
---receive it, WarbandMeDowns.Assignment.Sell if it's confirmed to be an
---upgrade for nobody, WarbandMeDowns.Assignment.Pending if the answer depends
---on item data the client hasn't cached yet, or nil if it was never eligible
---to be sent to a twink at all (wrong bind type, already Soulbound, below
---Uncommon quality, not armor/weapon, or not equippable).
---
---Already-owned items resolve in O(1) once their slot-class/target group is
---settled. Items nobody in the warband owns yet (loot window, vendor,
---trade, chat links) fall back to an O(#characters) walk against each
---character's already-settled best - no warband rescan needed.
---@param itemLink ItemInfo
---@param itemLocation ItemLocation? # live location of the hovered item, when available (see Data.IsActuallySoulbound)
---@return string|table|nil
function Assignment:GetBestCharacterForItem(itemLink, itemLocation)
    -- Nothing below can be trusted until the client has cached this item:
    -- bind type, quality and equip location all come out of C_Item.GetItemInfo
    -- and are nil for an uncached link, which would look exactly like "not
    -- eligible". Asking queues the load and GET_ITEM_INFO_RECEIVED brings us
    -- back, so this resolves itself a moment later.
    if not Data.IsItemInfoResolved(itemLink) then
        return self.Pending
    end

    local bind = Data.GetItemBind(itemLink)
    if not bind or not Data.CanItemBeSentToTwink(bind) then
        return nil
    end

    if Data.IsActuallySoulbound(bind, false, itemLocation) then
        return nil
    end

    local quality = Data.GetItemQuality(itemLink)
    if not Data.IsQualityEligible(quality) then
        return nil
    end

    local classID, subclassID = Data.GetItemClassAndSubclass(itemLink)
    if classID ~= Data.ItemClassArmor and classID ~= Data.ItemClassWeapon then
        return nil
    end

    local targetEquipLoc = Data.GetItemEquipLocation(itemLink)
    if not targetEquipLoc or targetEquipLoc == "" then
        return nil
    end

    self:EnsureFresh()

    -- Already settled by Recompute whenever the pool has a candidate for this
    -- target. Otherwise this settles an empty group, which claims nothing and
    -- so cannot change any other group's answer.
    local slotClassKey = Data.SlotClassKey(classID, subclassID)
    self:SettleGroup(slotClassKey, targetEquipLoc)
    local unresolved = self.unresolvedCache[slotClassKey][targetEquipLoc]

    -- Owned path: this exact item was seen during the warband scan.
    local entry = self:_FindEntryForHoveredItem(itemLink, itemLocation)
    if entry then
        if entry.claimedBy then
            if self:_AnyUnresolvedUpTo(unresolved, entry.claimedBy) then
                return self.Pending
            end
            return self:BuildUpgradeInfo(entry.claimedBy, itemLink, entry.claimedOverFloor)
        end

        -- "Nobody wants it" is only safe to say once everybody could be asked.
        if self:_AnyUnresolvedUpTo(unresolved, nil) then
            return self.Pending
        end
        return self.Sell
    end

    -- Foreign path: not part of the precomputed pool - compare against the
    -- floor every character who can wear it is left with once their claims
    -- are worn, instead of rescanning the warband. The floor is the slot this
    -- item would actually replace.
    local settled = self.settledCache[slotClassKey][targetEquipLoc]
    for _, character in ipairs(self._sortedCharacters) do
        if unresolved[character] then
            return self.Pending
        end

        if Characters.CanCharacterEquipItem(character, itemLink) then
            local floor, scorer = self:_SettledFloor(character, settled[character], itemLink)
            local comparison = CompareWithScorer(scorer, itemLink, floor)
            if comparison == nil or not scorer.resolved then
                return self.Pending
            elseif comparison == 1 then
                return self:BuildUpgradeInfo(character, itemLink, floor)
            end
        end
    end

    return self.Sell
end

-- *** Bulk settlement
--
-- Recompute settles every group up front, in one fixed order, so the claims -
-- and with them every tooltip, the settings page's projected item levels and
-- /wmd - are the same no matter what is looked at first.

---Every (slot-class, target equip location) pair a pool candidate could be
---claimed for, in a stable order.
---
---Each pool item's own location, plus every other target it satisfies under
---Data.EquipLocationsMatch: an ambidextrous one-hander also competes for the
---main-hand-only and off-hand-only targets. Leaving those out would let a
---later hover settle them lazily and claim one-handers the earlier pass had
---left free, so the answer would again depend on what was hovered first. Any
---target not listed here has no candidates, and settling it claims nothing.
---
---Order matters and is not cosmetic: claims are cross-group stateful, so
---settling in `pairs` order would make the result differ between sessions.
---Walking the keys in sorted order pins it down.
---@return table[] # { slotClassKey, equipLoc }
function Assignment:_SettleableGroups()
    local groups = {}

    for _, slotClassKey in ipairs(SortedKeys(self.pool)) do
        local targets = {}
        for equipLoc, entries in pairs(self.pool[slotClassKey]) do
            if entries[1] then
                targets[equipLoc] = true
                for _, target in ipairs(OneHandWeaponTargets) do
                    if Data.EquipLocationsMatch(equipLoc, target) then
                        targets[target] = true
                    end
                end
            end
        end

        for _, equipLoc in ipairs(SortedKeys(targets)) do
            table.insert(groups, { slotClassKey = slotClassKey, equipLoc = equipLoc })
        end
    end

    return groups
end

---Settles every group that has a candidate in it, so `entry.claimedBy` is
---complete across the whole pool. Called once per generation by Recompute.
function Assignment:SettleAllGroups()
    for _, group in ipairs(self:_SettleableGroups()) do
        self:SettleGroup(group.slotClassKey, group.equipLoc)
    end
end

---Every bag/bank/mail entry the last scan produced - sendable pool entries
---first, then unsendable floorExtra ones - in a deterministic order, so
---callers outside this module never have to know the bucket table shapes.
---Equipped items are not entries and are therefore not visited.
---@param callback fun(entry: table, isSendable: boolean)
function Assignment:IterateOwnedEntries(callback)
    for _, bucketsBySlotClass in ipairs({ self.pool, self.floorExtra }) do
        local isSendable = bucketsBySlotClass == self.pool

        for _, slotClassKey in ipairs(SortedKeys(bucketsBySlotClass)) do
            local buckets = bucketsBySlotClass[slotClassKey]

            for _, equipLoc in ipairs(SortedKeys(buckets)) do
                for _, entry in ipairs(buckets[equipLoc]) do
                    callback(entry, isSendable)
                end
            end
        end
    end
end

---Whether this character owns at least one bag/bank/mail item the client
---could not read during the last scan, so anything derived from their
---inventory is necessarily incomplete.
---@param character string
---@return boolean
function Assignment:HasUnreadableItems(character)
    for _, byLocation in pairs(self.unresolvedOwners) do
        for _, owners in pairs(byLocation) do
            if owners[character] then
                return true
            end
        end
    end

    return false
end

-- *** Explaining a result
--
-- Read-only re-derivation of one decision, for the /wmd why command. It
-- re-runs the same scorer and floor logic against the already-settled
-- generation instead of mutating any claims, so what it prints is what the
-- engine actually decided rather than a second, independent opinion.

---@param itemLink ItemInfo
---@return table
function Assignment:ExplainItem(itemLink)
    local explanation = {
        link = itemLink,
        resolved = Data.IsItemInfoResolved(itemLink),
        rows = {},
    }

    if not explanation.resolved then
        explanation.rejection = "the client has not cached this item yet"
        return explanation
    end

    explanation.bind = Data.GetItemBind(itemLink)
    explanation.quality = Data.GetItemQuality(itemLink)
    explanation.equipLoc = Data.GetItemEquipLocation(itemLink)
    explanation.itemLevel = Data.GetActualItemLevel(itemLink)

    local classID, subclassID = Data.GetItemClassAndSubclass(itemLink)
    explanation.classID = classID
    explanation.subclassID = subclassID

    if not explanation.bind or not Data.CanItemBeSentToTwink(explanation.bind) then
        explanation.rejection = "bind type cannot be sent to a twink"
        return explanation
    end
    if not Data.IsQualityEligible(explanation.quality) then
        explanation.rejection = "below Uncommon quality"
        return explanation
    end
    if classID ~= Data.ItemClassArmor and classID ~= Data.ItemClassWeapon then
        explanation.rejection = "not armor or a weapon"
        return explanation
    end
    if not explanation.equipLoc or explanation.equipLoc == "" then
        explanation.rejection = "not equippable"
        return explanation
    end

    self:EnsureFresh()

    local slotClassKey = Data.SlotClassKey(classID, subclassID)
    explanation.slotClassKey = slotClassKey
    self:SettleGroup(slotClassKey, explanation.equipLoc)

    local settled = self.settledCache[slotClassKey][explanation.equipLoc]
    local unresolved = self.unresolvedCache[slotClassKey][explanation.equipLoc]
    local candidates = UnionMatchingBuckets(self.pool, slotClassKey, explanation.equipLoc)
    local floorExtra = UnionMatchingBuckets(self.floorExtra, slotClassKey, explanation.equipLoc)

    -- Judged by instance, not by link: two copies of the same item share one
    -- link but are claimed independently, so "someone claimed this link" says
    -- nothing about the copy being asked about.
    local hoveredEntry = self:_FindEntryForHoveredItem(itemLink, nil)

    for rank, character in ipairs(self._sortedCharacters) do
        local result = settled[character]
        local row = {
            rank = rank,
            character = character,
            displayName = Characters.GetDisplayName(character),
            isCurrent = character == DataStore.ThisCharKey,
            unresolved = unresolved[character] == true,
            settled = result,
        }

        if not Characters.CanCharacterEquipItem(character, itemLink) then
            row.eligible = false
        else
            row.eligible = true

            local equipped, slotCount = Characters.GetEquippedItemsForEquipLocation(character, explanation.equipLoc)
            local relevant = CollectRelevantItems(character, equipped, slotCount, floorExtra, candidates)
            for _, link in ipairs(result.held) do
                table.insert(relevant, link)
            end
            table.insert(relevant, itemLink)

            local scorer = self:_BuildScorerForCharacter(character, relevant)
            row.basis = scorer.basis
            row.scaleName = scorer.scaleName

            row.isWinner = hoveredEntry ~= nil and hoveredEntry.claimedBy == character
            if row.isWinner then
                row.floor = hoveredEntry.claimedOverFloor
            else
                row.floor = HeldFloor(scorer, result.held, result.slotCount)
            end
            row.floorScore = row.floor and scorer.scoreOf(row.floor)
            row.itemScore = scorer.scoreOf(itemLink)
            row.beatsFloor = CompareWithScorer(scorer, itemLink, row.floor)
        end

        table.insert(explanation.rows, row)
    end

    return explanation
end

-- *** Dirty-flag orchestration
--
-- Invalidation events mark the engine dirty and (re)arm a debounce instead
-- of eagerly recomputing - recomputing right after looting mid-combat is
-- exactly the wrong moment, since nobody's looking at a tooltip yet. Once
-- the debounce fires, an out-of-combat background recompute keeps the
-- engine warm; but correctness never depends on that firing; EnsureFresh()
-- always recomputes synchronously if still dirty, and is called before
-- every lookup.

function Assignment:EnsureFresh()
    if self.dirty then
        self:Recompute()
    end
end

---*The* warband order: the one the engine settled under this generation.
---
---Everything that displays a ranking - the settings table, /wmd ranks - must
---read it from here rather than sorting for itself, so what is shown is always
---the order the recommendations were computed with. Characters.GetSortedWarbandCharacters
---does the sorting and is called only by Recompute, once per generation.
---
---This is the engine's own array, not a copy - iterate it, never sort or
---otherwise mutate it, or the generation's settlement order goes with it.
---@return string[]
function Assignment:GetRankedCharacters()
    self:EnsureFresh()
    return self._sortedCharacters
end

---@param userRequested boolean? # true when a player action asked for this
---directly (/wmd refresh), as opposed to an invalidation event triggering it
function Assignment:Recompute(userRequested)
    -- Not inside an @debug@ block: the elapsed time is reported to the player
    -- too when they asked for the recompute themselves. debugprofilestop is a
    -- normal retail API, present in every build despite the name.
    local startTime = debugprofilestop()

    Data.ClearItemCache()
    Characters.ClearWarbandCache()
    Characters.ClearEligibilityCache()
    Characters.ClearSpecCache()
    Pawn.ClearCaches()
    WarbandMeDowns.ItemLevel.ClearCaches()

    -- Two passes, because the priority order is now derived from the scan.
    --
    -- Pass 1 scans under a plain character-key order. That is safe precisely
    -- because ScanWarband's *output* does not depend on the order it walks:
    -- _SortBuckets re-sorts every bucket and every entriesByLink list on
    -- CompareEntries afterwards, so the walk order only ever affects insertion
    -- order, which is then normalized away. It still has to be a *stable*
    -- order rather than DataStore's `pairs`, so nothing session-specific can
    -- leak in before that normalization.
    self._sortedCharacters = Characters.GetWarbandCharacters()
    self:ScanWarband()

    -- Pass 2 is the real priority order. It has to come after the scan -
    -- CharacterPriorityComparator ranks on what each character owns - and
    -- before anything settles, since SettleGroup walks _sortedCharacters.
    self._sortedCharacters = Characters.GetSortedWarbandCharacters()
    self:SettleAllGroups()
    self.dirty = false

    -- A recompute the player asked for always reports back - it is the only
    -- feedback /wmd refresh gives. The automatic ones, which fire on every bag
    -- update and equipment change, would be chat spam, so they are announced
    -- only in a development build: the packager strips the block below out of
    -- everything it builds, leaving `announce` as `userRequested` alone.
    local announce = userRequested
    --@debug@
    announce = true
    --@end-debug@

    if announce then
        WarbandMeDowns:Printf(
            "recomputed warband with %d characters in %.3fms.",
            #(self._sortedCharacters),
            debugprofilestop() - startTime
        )
    end
end

---Marks the engine dirty and arms a debounced background recompute attempt.
---Safe to call repeatedly in a burst (e.g. several bag-update events in a
---row): each call cancels the previous timer, so only the last one fires.
---
---Note the timer methods are called on the addon object rather than on this
---one: AceTimer is mixed into WarbandMeDowns by NewAddon, and Assignment is a
---plain namespace table, not an AceAddon module. Cancelling on disable is
---handled for us through AceTimer's OnEmbedDisable - see OnDisable in
---Tooltip.lua.
function Assignment:MarkDirty()
    self.dirty = true

    if self._debounceTimer then
        WarbandMeDowns:CancelTimer(self._debounceTimer)
    end

    self._debounceTimer = WarbandMeDowns:ScheduleTimer(function()
        self._debounceTimer = nil
        self:TryBackgroundRecompute()
    end, 0.5)
end

function Assignment:TryBackgroundRecompute()
    if not self.dirty then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        return -- try again on the next debounce; EnsureFresh() is the guaranteed fallback
    end

    self:Recompute()
end

---Drops all engine state. Called on OnDisable so a re-enable starts clean.
function Assignment:Reset()
    self.pool = {}
    self.floorExtra = {}
    self.entriesByLink = {}
    self.entriesBySlot = {}
    self.settledCache = {}
    self.unresolvedCache = {}
    self.unresolvedOwners = {}
    self._sortedCharacters = {}
    self._debounceTimer = nil
    self.dirty = true

    Data.ClearItemCache()
    Characters.ClearWarbandCache()
    Characters.ClearEligibilityCache()
    Characters.ClearSpecCache()
    Pawn.ClearCaches()
    WarbandMeDowns.ItemLevel.ClearCaches()
end
