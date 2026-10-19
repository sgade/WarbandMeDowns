# Data sources for spec preferences

WarbandMeDowns hardcodes one kind of per-spec preference data in
`Data.lua`: which weapon/shield subclasses a spec actually uses. It
drifts with patches - this doc records where it came from and how to
refresh it. Secondary stat preferences (Crit/Haste/Mastery/Versatility) are
**not** hardcoded; that comparison is delegated to the optional Pawn addon
when it's installed - see the second section below.

## Weapon and shield preferences (`SpecWeaponSubclasses`, `SpecUsesShield`)

**Source**: Blizzard's own `ChrSpecialization` game-data table, the
`Description_lang` field ("Preferred Weapon(s): ..."), queried from the
[wago.tools DB2 export](https://wago.tools/db2/ChrSpecialization). This is
mechanical, Blizzard-authored data, not theorycrafting - it only changes
when Blizzard changes which weapon types a spec can use.

Last fetched 2026-08-18, against live WoW patch 12.1 ("Midnight"),
including Devourer (spec id 1480), the third Demon Hunter spec added in
Midnight.

**To refresh**: re-fetch that same export (or an equivalent DBC/DB2 dump
from wowhead/wago after a future patch) and re-read each spec row's
`Description_lang` "Preferred Weapon" clause. The mapping from that text to
`WeaponSubclass`/`ArmorSubclass` constants is mechanical:
- "Two-Handed X" -> `X2H`
- a bare weapon name -> its 1H constant
- "Shield" -> `ArmorSubclass.Shield`
- inherently-2H types (Staff/Polearm/Bow/Gun/Crossbow/Warglaive) map
  directly, since `WeaponSubclass` only carries one entry for each

Cross-check every entry against the class-level `WeaponSubclassClasses` /
`ArmorSubclassClasses` tables in the same file, so nothing ends up
unreachable (the class-level check always runs first).

A few entries deliberately go beyond the official flavor text - these are
flagged inline in the source comments above `SetSpecWeaponSubclasses` calls
(e.g. Outlaw's off-hand dagger, Windwalker's Polearm/Staff pick). Re-verify
those still hold true each time this is refreshed; they can go stale
independently of the DB2 data.

## Item comparison (delegated to Pawn, via `Assignment:_BuildScorerForCharacter`)

WarbandMeDowns used to hardcode a per-spec table of secondary stat priorities,
hand-transcribed from Wowhead's guides. That table is gone. Item comparison
is instead delegated live to the optional
[Pawn](https://github.com/VgerMods/Pawn) addon, if the player has it
installed - Pawn's entire purpose is scoring items against per-spec stat
weights (including main stat), so WarbandMeDowns just asks it rather than
maintaining its own, inherently-theorycrafted copy of the same data.

An item is only ever an upgrade for a character if its item level is
strictly higher than the item it would replace; Pawn has no say in that.
When Pawn is installed and a scale resolves for a character (see "Why a
scale is always available" below), its score decides *which* of several
such upgrades the character gets - that matters because item level alone
can't tell a same-slot Intellect item from a Strength one. Item level is
only used for that ranking as a fallback: when Pawn isn't installed, the
spec is unknown, or Pawn can't produce a score for one of the candidates.
See `IsItemLevelUpgrade` and `Assignment:_ClaimBestCandidate` in
`Assignment.lua`.

**Why this is possible**: Pawn exposes genuine global Lua functions other
addons can call - this isn't reverse-engineering. Pawn's own
ArkInventory-rule integration (`GetPawnStatusForArkInventoryRule` in
`Pawn.lua`) calls the exact same functions WarbandMeDowns uses, confirming
they're meant for cross-addon use. Verified by reading Pawn's actual source
(not a summarized/fetched version - see the "verification method" note
below) at `github.com/VgerMods/Pawn`, `master` branch, **Pawn version
2.13.16**, same `## Interface: 120100` as WarbandMeDowns, on 2026-08-19.

**Functions relied on** (all in `Pawn.lua`):
- `PawnGetItemData(itemLink)` - parses an item link into a table with
  `.Stats`, `.Level`, `.SocketBonusStats`. Link-based, so it works for any
  item link regardless of which character owns it, same as the WoW APIs
  WarbandMeDowns already calls directly (`C_Item.GetItemInfo` etc.).
- `PawnFindScaleForSpec(classID, specIndex)` - returns the name of a
  plugin-provided scale for a class+spec, or `nil`. **`classID` is
  Blizzard's numeric class ID (1-13)**; **the second argument is the local
  1-4 spec index** (`GetSpecializationInfoForClassID`'s convention -
  confirmed against `ScaleTemplates.lua`'s own template entries, e.g. Druid
  Feral is listed as `ClassID 11, SpecID 2`), **not** a global spec ID.
  `Characters.GetKnownSpecIndex` returns exactly that local index, so
  `Pawn.GetPawnScaleNameForCharacter` passes it straight through with no
  conversion - see the warning below.
- `PawnGetSingleValueFromItem(item, scaleName)` - returns a single numeric
  score for that item against that scale (gems, sockets, and normalization
  handled internally by Pawn).

**Why a scale is always available**: `Pawn.toc` loads `AskMrRobot.lua`
unconditionally on retail (`[AllowLoadGameType mainline]`, not an optional
module or user-imported string). That file registers a `"MrRobot"`-provider
scale for every class+spec combination at login, so `PawnFindScaleForSpec`
resolves for any alt's class/spec the moment Pawn is installed, with no
per-user setup.

### Spec identity: local index vs global spec ID

Two different numbers are called a "spec" in this codebase, and confusing
them silently disables things rather than erroring:

- the **local spec index**, 1-4, Blizzard's position in
  `GetSpecializationInfoForClassID` / `C_SpecializationInfo.GetSpecialization`.
  This is what Pawn's `PawnFindScaleForSpec` wants.
- the **global spec ID**, 62-1480, the values in `Data.Spec`. This is what
  `Data.SpecClass`, `Data.SpecUsesShield` and `Data.SpecWeaponSubclasses` are
  keyed by.

**`DataStore:GetActiveSpecInfo(character)` returns the *local index* as its
second value, not the global ID.** DataStore_Talents packs it into three bits
(`bit64:GetBits(info, 0, 3)` in `API/Specialization.lua`, written from
`C_SpecializationInfo.GetSpecialization()`), so it can only ever be 1-4.

This bit an earlier version badly. It treated that value as a global spec ID,
then tried to convert it *back* to a local index by searching `SpecsByClass`
for it - a search that could never match, since global IDs start at 62. The
result was that `PawnFindScaleForSpec` was never called for **any** character,
so Pawn contributed nothing at all and every recommendation fell back to raw
item level; and `IsItemSubclassFavoredBySpec`'s spec branch was equally
unreachable, so weapon filtering silently used the class-wide union instead of
the character's actual spec. Neither failure produced an error or a warning.

`Characters.GetKnownSpecIndex` (local index, straight from DataStore) and
`Characters.GetKnownSpecID` (global ID, mapped through `Data.SpecsByClass`)
now keep the two apart. If Pawn ever appears to stop contributing, check this
first: `/wmd ranks` prints the resolved Pawn scale per character, and a
warband where every row says "no Pawn scale" while Pawn is installed is this
bug returning.

**`SpecsByClass` ordering matters and does not always follow the IDs.** The
index-to-global-ID mapping is just `SpecsByClass[class][index]`, so those
lists must be in Blizzard's *index* order. That usually coincides with spec-ID
order, but not always - Monk's index order is Brewmaster, **Mistweaver**,
Windwalker, while the IDs run Brewmaster(268), Windwalker(269),
Mistweaver(270). Verify against the client rather than assuming.

**This is not a documented or versioned API contract.** Every call in
`Pawn.lua` (`GetPawnScaleNameForCharacter`,
`GetPawnItemValue`) is defensive on purpose: it checks `type(...) ==
"function"` before calling anything, wraps every call in `pcall`, and
validates the type of whatever comes back before trusting it. Any failure
at any step - Pawn not installed, a renamed/removed function, an unexpected
return shape, an internal Pawn error - degrades silently to "no opinion",
identical to today's "spec unknown" fallback (item level becomes the
comparison, and an exact tie means neither item is recommended over the
other). Nothing here should ever be able to produce a visible error for a
player who simply doesn't have Pawn installed.

**Verification method note, for future reference**: a generic
fetch-and-summarize web tool *hallucinated* plausible-looking function
bodies for `Pawn.lua`/`Core.lua` that don't exist in the real files -this
was only caught by downloading the raw source directly (`curl` the
`raw.githubusercontent.com` URLs) and reading it. Don't trust a summarized
read of a large Lua file when re-verifying this integration; fetch and read
the actual source.

**To refresh**: if a future Pawn update renames or reshapes these functions
and WarbandMeDowns' Pawn integration silently stops contributing scores
(it will not error - see above), re-fetch Pawn's current source the same
way and re-check `PawnFindScaleForSpec`, `PawnGetItemData`, and
`PawnGetSingleValueFromItem` still exist with the same parameter order and
return shape.

## What DataStore does and does not see

The engine is only ever as good as DataStore's stored snapshots, and two gaps
are worth knowing about before treating a recommendation as complete.

**The warband (account) bank is invisible.** DataStore_Containers deliberately
skips it: `OnBagUpdate` returns early for any `bag >= MIN_ACCOUNTBANK_TAB`
(`Enum.BagIndex.AccountBankTab_1`), and `OnBankFrameOpened` only scans the
character bank tabs. Nothing else writes those container IDs, so account bank
tabs never reach `DataStore:GetContainers` and warbound gear parked there is
simply not a candidate. Verified against DataStore_Containers 2026.08.x.

**Other characters' data is a snapshot, and their mail is only as fresh as the
last time that character opened a mailbox.** The settings page shows the
per-module "last scanned" times for exactly this reason.

**Stored equipped items *can* be a bare itemID rather than a link.**
DataStore_Inventory's `ScanInventorySlot` only stores the full item link when
`IsEnchanted(link)` is true (a pattern match on the link's enchant/gem
fields); otherwise it stores just `tonumber(link:match("item:(%d+)"))`.
`C_Item.GetDetailedItemLevelInfo` accepts an itemID happily but then answers
with the item's *base* item level, with no bonus-ID upgrade track applied - so
such a slot would read several tiers below what the character actually wears.

Measured against this account's `DataStore_Inventory.lua` SavedVariables
(2026-08-24, 22 characters, 352 item-level-relevant equipment slots): **zero**
bare itemIDs, all full links. `IsEnchanted`'s pattern
(`item:%d+:0:0:0:0:0:0:%d+:%d+:0:0`) does not match the modern link format, so
the itemID branch is effectively dead today. Treat it as a latent hazard that
a link-format change could reactivate, not as a current source of error, and
re-measure before relying on either statement.

**Two equipment-slot facts the average depends on.** A **two-handed weapon is
counted twice**, once for each weapon slot - so a character wielding one has no
empty off hand as far as the average is concerned. Scoring that slot as empty
inflated `Max iLvl` by roughly +19 on a character at 295 (an entire extra
item), which is what `ItemLevel.lua`'s paired weapon-slot handling exists to
prevent. The snapshot forces this reading: `averageItemLvl` 295.1875 is an
exact multiple of 1/16 and not of 1/15, so there really are sixteen
contributions - and if the off hand were one of them at zero, that character's
fifteen equipped items would have to average 315 while the character sheet
reads 295.

Second, **`INVSLOT_RANGED` (18) is dead in retail** - a bow or gun equips to the
main hand, and slot 18 is empty on all 22 characters. `Data.EquipLocToSlotID`
still maps `INVTYPE_RANGED` / `INVTYPE_RANGEDRIGHT` / `INVTYPE_THROWN` to it,
which means `Characters.GetEquippedItemsForEquipLocation` hands the assignment
engine an empty slot for a hunter's bow. `ItemLevel.lua` routes around this
locally; the engine side is untouched and worth a separate look.

`DataStore:GetAverageItemLevel` returns Blizzard's **overall** item level - best
gear you own, bags included - as its *second* value. `/wmd ilvl` prints it
beside the projection as a sanity check. It is not a target to match (the
projection also counts bank and mail and ignores level requirements) but a
projection far above it on a max-level character means a slot is scored wrong.

The same snapshot pins down two things `ItemLevel.lua` depends on: every
stored `averageItemLvl` is an exact multiple of 1/16 (so the divisor is 16),
and characters with empty slots follow the same rule (so an empty slot
contributes zero rather than shrinking the divisor). Slots 4 (shirt) and 19
(tabard) are populated but excluded from it; slot 18 (ranged) is never
populated at all in retail.


Neither of these makes the answer *inconsistent* between characters - both are
account-wide stored state, identical whoever is logged in - they just make it
incomplete. Consistency is a separate concern, handled in `Assignment.lua`;
see the header comment there for the three things that used to break it.
