--[[----------------------------------------------------------------------------

  WarbandMeDowns/Data.lua
  Item taxonomy: class/spec/weapon/armor eligibility data, plus pure
  item-info helpers that need no DataStore calls and hold no addon state.
  See WarbandMeDowns.lua for the license header covering the whole addon.

----------------------------------------------------------------------------]]--

WarbandMeDowns.Data = WarbandMeDowns.Data or {}
local Data = WarbandMeDowns.Data

local ItemClassArmor = (Enum and Enum.ItemClass and Enum.ItemClass.Armor) or LE_ITEM_CLASS_ARMOR or 4
local ItemClassWeapon = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or LE_ITEM_CLASS_WEAPON or 2
Data.ItemClassArmor = ItemClassArmor
Data.ItemClassWeapon = ItemClassWeapon

local ArmorSubclass = {
    Generic = (Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Generic) or LE_ITEM_ARMOR_GENERIC or 0,
    Cloth = (Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Cloth) or LE_ITEM_ARMOR_CLOTH or 1,
    Leather = (Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Leather) or LE_ITEM_ARMOR_LEATHER or 2,
    Mail = (Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Mail) or LE_ITEM_ARMOR_MAIL or 3,
    Plate = (Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Plate) or LE_ITEM_ARMOR_PLATE or 4,
    Cosmetic = (Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Cosmetic) or 5,
    Shield = (Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Shield) or LE_ITEM_ARMOR_SHIELD or 6,
}
Data.ArmorSubclass = ArmorSubclass

local WeaponSubclass = {
    Axe = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Axe) or LE_ITEM_WEAPON_AXE1H or 0,
    Axe2H = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Axe2H) or LE_ITEM_WEAPON_AXE2H or 1,
    Bow = (Enum and Enum.ItemWeaponSubclass and (Enum.ItemWeaponSubclass.Bow or Enum.ItemWeaponSubclass.Bows)) or LE_ITEM_WEAPON_BOWS or 2,
    Gun = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Gun) or LE_ITEM_WEAPON_GUNS or 3,
    Mace = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Mace) or LE_ITEM_WEAPON_MACE1H or 4,
    Mace2H = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Mace2H) or LE_ITEM_WEAPON_MACE2H or 5,
    Polearm = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Polearm) or LE_ITEM_WEAPON_POLEARM or 6,
    Sword = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Sword) or LE_ITEM_WEAPON_SWORD1H or 7,
    Sword2H = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Sword2H) or LE_ITEM_WEAPON_SWORD2H or 8,
    Warglaive = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Warglaive) or LE_ITEM_WEAPON_WARGLAIVE or 9,
    Staff = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Staff) or LE_ITEM_WEAPON_STAFF or 10,
    Fist = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fist) or LE_ITEM_WEAPON_UNARMED or 13,
    Generic = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Generic) or 14,
    Dagger = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Dagger) or LE_ITEM_WEAPON_DAGGER or 15,
    Crossbow = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Crossbow) or LE_ITEM_WEAPON_CROSSBOW or 18,
    Wand = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Wand) or LE_ITEM_WEAPON_WAND or 19,
    FishingPole = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.FishingPole) or LE_ITEM_WEAPON_FISHINGPOLE or 20,
}
Data.WeaponSubclass = WeaponSubclass

local ArmorSubclassClasses = {}
local WeaponSubclassClasses = {}
Data.ArmorSubclassClasses = ArmorSubclassClasses
Data.WeaponSubclassClasses = WeaponSubclassClasses

local function SetArmorSubclassClasses(subclassID, classes)
    if subclassID then
        ArmorSubclassClasses[subclassID] = classes
    end
end

local function SetWeaponSubclassClasses(subclassID, classes)
    if subclassID then
        WeaponSubclassClasses[subclassID] = classes
    end
end

SetArmorSubclassClasses(ArmorSubclass.Cloth, {"PRIEST", "MAGE", "WARLOCK"})
SetArmorSubclassClasses(ArmorSubclass.Leather, {"ROGUE", "MONK", "DRUID", "DEMONHUNTER"})
SetArmorSubclassClasses(ArmorSubclass.Mail, {"HUNTER", "SHAMAN", "EVOKER"})
SetArmorSubclassClasses(ArmorSubclass.Plate, {"WARRIOR", "PALADIN", "DEATHKNIGHT"})
SetArmorSubclassClasses(ArmorSubclass.Shield, {"WARRIOR", "PALADIN", "SHAMAN"})
SetArmorSubclassClasses(ArmorSubclass.Generic, {"WARRIOR", "PALADIN", "DEATHKNIGHT", "HUNTER", "SHAMAN", "EVOKER", "ROGUE", "MONK", "DRUID", "DEMONHUNTER", "PRIEST", "MAGE", "WARLOCK"})

-- Equippable, but never gear.
--
-- Cosmetic armor is transmog-only, and the Weapon "Generic" subclass is the
-- Miscellaneous auction category - mining picks, blacksmith hammers and other
-- equippable oddities. Both are genuine Armor/Weapon items with an equip
-- location, so they reach the eligibility check like anything else; no class
-- should ever be handed one as an upgrade.
--
-- Listed explicitly rather than left out of the tables: a *missing* subclass
-- means "this addon has not been taught about it yet" and warns accordingly,
-- which is a different statement from "nobody wears this for stats".
local NoClassWantsThis = {}
SetArmorSubclassClasses(ArmorSubclass.Cosmetic, NoClassWantsThis)
SetWeaponSubclassClasses(WeaponSubclass.Generic, NoClassWantsThis)

SetWeaponSubclassClasses(WeaponSubclass.Axe, {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "SHAMAN", "MONK", "DEMONHUNTER", "DEATHKNIGHT", "EVOKER"})
SetWeaponSubclassClasses(WeaponSubclass.Axe2H, {"WARRIOR", "PALADIN", "HUNTER", "DEATHKNIGHT", "EVOKER"})
SetWeaponSubclassClasses(WeaponSubclass.Bow, {"HUNTER"})
SetWeaponSubclassClasses(WeaponSubclass.Gun, {"HUNTER"})
SetWeaponSubclassClasses(WeaponSubclass.Mace, {"WARRIOR", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "MONK", "DRUID", "DEATHKNIGHT", "EVOKER"})
SetWeaponSubclassClasses(WeaponSubclass.Mace2H, {"WARRIOR", "PALADIN", "DRUID", "DEATHKNIGHT", "EVOKER"})
SetWeaponSubclassClasses(WeaponSubclass.Polearm, {"WARRIOR", "PALADIN", "HUNTER", "MONK", "DRUID", "DEATHKNIGHT"})
SetWeaponSubclassClasses(WeaponSubclass.Sword, {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "MONK", "MAGE", "WARLOCK", "DEMONHUNTER", "DEATHKNIGHT", "EVOKER"})
SetWeaponSubclassClasses(WeaponSubclass.Sword2H, {"WARRIOR", "PALADIN", "HUNTER", "DEATHKNIGHT", "EVOKER"})
SetWeaponSubclassClasses(WeaponSubclass.Warglaive, {"DEMONHUNTER"})
SetWeaponSubclassClasses(WeaponSubclass.Staff, {"WARRIOR", "HUNTER", "SHAMAN", "MONK", "DRUID", "PRIEST", "MAGE", "WARLOCK", "EVOKER"})
SetWeaponSubclassClasses(WeaponSubclass.Fist, {"WARRIOR", "HUNTER", "ROGUE", "SHAMAN", "MONK", "DRUID", "DEMONHUNTER", "EVOKER"})
SetWeaponSubclassClasses(WeaponSubclass.Dagger, {"WARRIOR", "HUNTER", "ROGUE", "SHAMAN", "DRUID", "PRIEST", "MAGE", "WARLOCK", "DEMONHUNTER", "EVOKER"})
SetWeaponSubclassClasses(WeaponSubclass.Crossbow, {"HUNTER"})
SetWeaponSubclassClasses(WeaponSubclass.Wand, {"PRIEST", "MAGE", "WARLOCK"})
SetWeaponSubclassClasses(WeaponSubclass.FishingPole, {"WARRIOR", "PALADIN", "DEATHKNIGHT", "HUNTER", "SHAMAN", "EVOKER", "ROGUE", "MONK", "DRUID", "DEMONHUNTER", "PRIEST", "MAGE", "WARLOCK"})

-- Specialization-level weapon/shield preferences.
--
-- These narrow the class-level tables above: the class-level tables answer
-- "could this class ever equip this?", these answer "would this spec ever want it?".
-- Every subclass listed here must also appear in that class' entry above,
-- because the class-level check always runs first (see
-- WarbandMeDowns.Characters.CanCharacterEquipItemClass).
local SpecsByClass = {}
local SpecClass = {}
local SpecWeaponSubclasses = {}
local SpecUsesShield = {}
local ClassFavoriteWeaponSubclasses = {}
local ClassUsesShield = {}
Data.SpecsByClass = SpecsByClass
Data.SpecClass = SpecClass
Data.SpecWeaponSubclasses = SpecWeaponSubclasses
Data.SpecUsesShield = SpecUsesShield
Data.ClassFavoriteWeaponSubclasses = ClassFavoriteWeaponSubclasses
Data.ClassUsesShield = ClassUsesShield

local function SetClassSpecs(class, specIDs)
    SpecsByClass[class] = specIDs
end

local function SetSpecWeaponSubclasses(specID, subclassIDs)
    if not specID then
        return
    end

    local subclasses = {}
    for _, subclassID in ipairs(subclassIDs) do
        subclasses[subclassID] = true
    end
    SpecWeaponSubclasses[specID] = subclasses
end

local function SetSpecUsesShield(specID)
    if not specID then
        return
    end

    SpecUsesShield[specID] = true
end

-- Well-known, stable, locale-independent Blizzard specialization IDs.
local Spec = {
    Arms = 71, Fury = 72, ProtectionWarrior = 73,
    HolyPaladin = 65, ProtectionPaladin = 66, Retribution = 70,
    BeastMastery = 253, Marksmanship = 254, Survival = 255,
    Assassination = 259, Outlaw = 260, Subtlety = 261,
    Discipline = 256, HolyPriest = 257, Shadow = 258,
    Blood = 250, FrostDeathKnight = 251, Unholy = 252,
    Elemental = 262, Enhancement = 263, RestorationShaman = 264,
    Arcane = 62, Fire = 63, FrostMage = 64,
    Affliction = 265, Demonology = 266, Destruction = 267,
    Brewmaster = 268, Windwalker = 269, Mistweaver = 270,
    Balance = 102, Feral = 103, Guardian = 104, RestorationDruid = 105,
    Havoc = 577, Vengeance = 581, Devourer = 1480,
    Devastation = 1467, Preservation = 1468, Augmentation = 1473,
}
Data.Spec = Spec

-- IMPORTANT: these lists are in Blizzard's *specialization index* order (the
-- 1-4 index GetSpecializationInfoForClassID / C_SpecializationInfo.GetSpecialization
-- use), NOT in spec-ID order. The two usually coincide, but not always: Monk's
-- index order is Brewmaster, Mistweaver, Windwalker even though the spec IDs
-- run Brewmaster(268), Windwalker(269), Mistweaver(270). Both
-- WarbandMeDowns.Characters.GetKnownSpecID (index -> global spec ID) and
-- WarbandMeDowns.Pawn.GetPawnScaleNameForCharacter (index -> Pawn scale)
-- depend on this order being right, so verify it against the client rather
-- than assuming it follows the IDs.
SetClassSpecs("WARRIOR",     {Spec.Arms, Spec.Fury, Spec.ProtectionWarrior})
SetClassSpecs("PALADIN",     {Spec.HolyPaladin, Spec.ProtectionPaladin, Spec.Retribution})
SetClassSpecs("HUNTER",      {Spec.BeastMastery, Spec.Marksmanship, Spec.Survival})
SetClassSpecs("ROGUE",       {Spec.Assassination, Spec.Outlaw, Spec.Subtlety})
SetClassSpecs("PRIEST",      {Spec.Discipline, Spec.HolyPriest, Spec.Shadow})
SetClassSpecs("DEATHKNIGHT", {Spec.Blood, Spec.FrostDeathKnight, Spec.Unholy})
SetClassSpecs("SHAMAN",      {Spec.Elemental, Spec.Enhancement, Spec.RestorationShaman})
SetClassSpecs("MAGE",        {Spec.Arcane, Spec.Fire, Spec.FrostMage})
SetClassSpecs("WARLOCK",     {Spec.Affliction, Spec.Demonology, Spec.Destruction})
SetClassSpecs("MONK",        {Spec.Brewmaster, Spec.Mistweaver, Spec.Windwalker})  -- index order != ID order, see above
SetClassSpecs("DRUID",       {Spec.Balance, Spec.Feral, Spec.Guardian, Spec.RestorationDruid})
SetClassSpecs("DEMONHUNTER", {Spec.Havoc, Spec.Vengeance, Spec.Devourer})
SetClassSpecs("EVOKER",      {Spec.Devastation, Spec.Preservation, Spec.Augmentation})

-- Per-spec favored weapon subclasses / shield usage.
--
-- Source: Blizzard's own ChrSpecialization game-data table, Description_lang
-- field ("Preferred Weapon(s): ..."), queried from the wago.tools DB2 export
-- (https://wago.tools/db2/ChrSpecialization) on 2026-08-18 against live WoW
-- patch 12.1 ("Midnight") data - including Devourer (id 1480), the new third
-- Demon Hunter spec added in Midnight.
--
-- To refresh this table later, re-fetch that same export (or the equivalent
-- DBC/DB2 dump from wowhead/wago after a future patch) and re-read each spec
-- row's Description_lang "Preferred Weapon" clause - the mapping from that
-- text to WeaponSubclass/ArmorSubclass constants is mechanical: "Two-Handed
-- X" -> X2H, a bare weapon name -> its 1H constant, "Shield" ->
-- ArmorSubclass.Shield, and inherently-2H types (Staff/Polearm/Bow/Gun/
-- Crossbow/Warglaive) map directly since WeaponSubclass only carries one
-- entry for each of those. Every entry below was cross-checked against the
-- class-level WeaponSubclassClasses/ArmorSubclassClasses tables above so
-- nothing here is ever unreachable.
--
-- A few entries deliberately go beyond the official text, flagged inline:
-- Outlaw's Dagger (current guides mandate one in the off-hand for a spec
-- mechanic) and Windwalker's Polearm/Staff (a balance change made
-- two-handed weapons this season's top pick, ahead of the flavor text).
--
-- See docs/DATA_SOURCES.md for the full refresh method.

-- Warrior - "Two-Handed Axe, Mace, Sword" / "Dual Two-Handed Axes, Maces, Swords" / "Axe, Mace, Sword, and Shield"
SetSpecWeaponSubclasses(Spec.Arms,              {WeaponSubclass.Axe2H, WeaponSubclass.Mace2H, WeaponSubclass.Sword2H})
SetSpecWeaponSubclasses(Spec.Fury,              {WeaponSubclass.Axe2H, WeaponSubclass.Mace2H, WeaponSubclass.Sword2H})
SetSpecWeaponSubclasses(Spec.ProtectionWarrior, {WeaponSubclass.Axe, WeaponSubclass.Mace, WeaponSubclass.Sword})

-- Paladin - "Sword, Mace, and Shield" / "Sword, Mace, Axe, and Shield" / "Two-Handed Sword, Mace, Axe"
SetSpecWeaponSubclasses(Spec.HolyPaladin,       {WeaponSubclass.Sword, WeaponSubclass.Mace})
SetSpecWeaponSubclasses(Spec.ProtectionPaladin, {WeaponSubclass.Sword, WeaponSubclass.Mace, WeaponSubclass.Axe})
SetSpecWeaponSubclasses(Spec.Retribution,       {WeaponSubclass.Sword2H, WeaponSubclass.Mace2H, WeaponSubclass.Axe2H})

-- Hunter - "Bow, Crossbow, Gun" (x2) / "Polearm, Staff, Axe, Dagger, Sword"
SetSpecWeaponSubclasses(Spec.BeastMastery,      {WeaponSubclass.Bow, WeaponSubclass.Crossbow, WeaponSubclass.Gun})
SetSpecWeaponSubclasses(Spec.Marksmanship,      {WeaponSubclass.Bow, WeaponSubclass.Crossbow, WeaponSubclass.Gun})
SetSpecWeaponSubclasses(Spec.Survival,          {WeaponSubclass.Polearm, WeaponSubclass.Staff, WeaponSubclass.Axe, WeaponSubclass.Dagger, WeaponSubclass.Sword})

-- Rogue - "Daggers" / "Axes, Maces, Swords, Fist Weapons" / "Daggers"
SetSpecWeaponSubclasses(Spec.Assassination,     {WeaponSubclass.Dagger})
SetSpecWeaponSubclasses(Spec.Outlaw,            {WeaponSubclass.Axe, WeaponSubclass.Mace, WeaponSubclass.Sword, WeaponSubclass.Fist, WeaponSubclass.Dagger})
SetSpecWeaponSubclasses(Spec.Subtlety,          {WeaponSubclass.Dagger})

-- Priest - "Staff, Wand, Dagger, Mace" (all 3 specs identical)
SetSpecWeaponSubclasses(Spec.Discipline,        {WeaponSubclass.Staff, WeaponSubclass.Wand, WeaponSubclass.Dagger, WeaponSubclass.Mace})
SetSpecWeaponSubclasses(Spec.HolyPriest,        {WeaponSubclass.Staff, WeaponSubclass.Wand, WeaponSubclass.Dagger, WeaponSubclass.Mace})
SetSpecWeaponSubclasses(Spec.Shadow,            {WeaponSubclass.Staff, WeaponSubclass.Wand, WeaponSubclass.Dagger, WeaponSubclass.Mace})

-- Death Knight - "Two-Handed Axe, Mace, Sword" / "Dual Axes, Maces, Swords" / "Two-Handed Axe, Mace, Sword"
SetSpecWeaponSubclasses(Spec.Blood,             {WeaponSubclass.Axe2H, WeaponSubclass.Mace2H, WeaponSubclass.Sword2H})
SetSpecWeaponSubclasses(Spec.FrostDeathKnight,  {WeaponSubclass.Axe, WeaponSubclass.Mace, WeaponSubclass.Sword})
SetSpecWeaponSubclasses(Spec.Unholy,            {WeaponSubclass.Axe2H, WeaponSubclass.Mace2H, WeaponSubclass.Sword2H})

-- Shaman - "Mace, Dagger, and Shield" / "Dual Axes, Maces, Fist Weapons" / "Mace, Dagger, and Shield"
SetSpecWeaponSubclasses(Spec.Elemental,         {WeaponSubclass.Mace, WeaponSubclass.Dagger})
SetSpecWeaponSubclasses(Spec.Enhancement,       {WeaponSubclass.Axe, WeaponSubclass.Mace, WeaponSubclass.Fist})
SetSpecWeaponSubclasses(Spec.RestorationShaman, {WeaponSubclass.Mace, WeaponSubclass.Dagger})

-- Mage - "Staff, Wand, Dagger, Sword" (all 3 specs identical)
SetSpecWeaponSubclasses(Spec.Arcane,            {WeaponSubclass.Staff, WeaponSubclass.Wand, WeaponSubclass.Dagger, WeaponSubclass.Sword})
SetSpecWeaponSubclasses(Spec.Fire,              {WeaponSubclass.Staff, WeaponSubclass.Wand, WeaponSubclass.Dagger, WeaponSubclass.Sword})
SetSpecWeaponSubclasses(Spec.FrostMage,         {WeaponSubclass.Staff, WeaponSubclass.Wand, WeaponSubclass.Dagger, WeaponSubclass.Sword})

-- Warlock - "Staff, Wand, Dagger, Sword" (all 3 specs identical)
SetSpecWeaponSubclasses(Spec.Affliction,        {WeaponSubclass.Staff, WeaponSubclass.Wand, WeaponSubclass.Dagger, WeaponSubclass.Sword})
SetSpecWeaponSubclasses(Spec.Demonology,        {WeaponSubclass.Staff, WeaponSubclass.Wand, WeaponSubclass.Dagger, WeaponSubclass.Sword})
SetSpecWeaponSubclasses(Spec.Destruction,       {WeaponSubclass.Staff, WeaponSubclass.Wand, WeaponSubclass.Dagger, WeaponSubclass.Sword})

-- Monk - "Staff, Polearm" / "Fist Weapons, Axes, Maces, Swords" / "Staff, Mace, Sword"
SetSpecWeaponSubclasses(Spec.Brewmaster,        {WeaponSubclass.Staff, WeaponSubclass.Polearm})
SetSpecWeaponSubclasses(Spec.Windwalker,        {WeaponSubclass.Fist, WeaponSubclass.Axe, WeaponSubclass.Mace, WeaponSubclass.Sword, WeaponSubclass.Polearm, WeaponSubclass.Staff})
SetSpecWeaponSubclasses(Spec.Mistweaver,        {WeaponSubclass.Staff, WeaponSubclass.Mace, WeaponSubclass.Sword})

-- Druid - "Staff, Dagger, Mace" / "Staff, Polearm" / "Staff, Polearm" / "Staff, Dagger, Mace"
SetSpecWeaponSubclasses(Spec.Balance,           {WeaponSubclass.Staff, WeaponSubclass.Dagger, WeaponSubclass.Mace})
SetSpecWeaponSubclasses(Spec.Feral,             {WeaponSubclass.Staff, WeaponSubclass.Polearm})
SetSpecWeaponSubclasses(Spec.Guardian,          {WeaponSubclass.Staff, WeaponSubclass.Polearm})
SetSpecWeaponSubclasses(Spec.RestorationDruid,  {WeaponSubclass.Staff, WeaponSubclass.Dagger, WeaponSubclass.Mace})

-- Demon Hunter - "Warglaives, Swords, Axes, Fist Weapons" (x2) / "Warglaives, Swords, Axes, Fist Weapons, Daggers"
SetSpecWeaponSubclasses(Spec.Havoc,             {WeaponSubclass.Warglaive, WeaponSubclass.Sword, WeaponSubclass.Axe, WeaponSubclass.Fist})
SetSpecWeaponSubclasses(Spec.Vengeance,         {WeaponSubclass.Warglaive, WeaponSubclass.Sword, WeaponSubclass.Axe, WeaponSubclass.Fist})
SetSpecWeaponSubclasses(Spec.Devourer,          {WeaponSubclass.Warglaive, WeaponSubclass.Sword, WeaponSubclass.Axe, WeaponSubclass.Fist, WeaponSubclass.Dagger})

-- Evoker - "Staff, Sword, Dagger, Mace" (all 3 specs identical)
SetSpecWeaponSubclasses(Spec.Devastation,       {WeaponSubclass.Staff, WeaponSubclass.Sword, WeaponSubclass.Dagger, WeaponSubclass.Mace})
SetSpecWeaponSubclasses(Spec.Preservation,      {WeaponSubclass.Staff, WeaponSubclass.Sword, WeaponSubclass.Dagger, WeaponSubclass.Mace})
SetSpecWeaponSubclasses(Spec.Augmentation,      {WeaponSubclass.Staff, WeaponSubclass.Sword, WeaponSubclass.Dagger, WeaponSubclass.Mace})

SetSpecUsesShield(Spec.ProtectionWarrior)
SetSpecUsesShield(Spec.HolyPaladin)
SetSpecUsesShield(Spec.ProtectionPaladin)
SetSpecUsesShield(Spec.Elemental)
SetSpecUsesShield(Spec.RestorationShaman)

-- Union of every spec's preferences, used when a character's spec is unknown.
for class, specIDs in pairs(SpecsByClass) do
    local weaponSubclasses = {}
    local usesShield = false

    for _, specID in ipairs(specIDs) do
        SpecClass[specID] = class

        for subclassID in pairs(SpecWeaponSubclasses[specID] or {}) do
            weaponSubclasses[subclassID] = true
        end

        if SpecUsesShield[specID] then
            usesShield = true
        end
    end

    ClassFavoriteWeaponSubclasses[class] = weaponSubclasses
    ClassUsesShield[class] = usesShield
end

-- Numeric class IDs, Blizzard-stable, used only to talk to Pawn (see
-- WarbandMeDowns.Pawn.GetPawnScaleNameForCharacter) - Pawn's scale-lookup
-- functions take these instead of the classFile strings DataStore uses.
Data.ClassID = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
    DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8, WARLOCK = 9, MONK = 10,
    DRUID = 11, DEMONHUNTER = 12, EVOKER = 13,
}

-- *** Per-generation item metadata cache
--
-- Everything below is a property of the item *link*, which never changes, yet
-- the engine asks for the same handful of facts about the same links over and
-- over - one warband refresh used to make ~8000 C_Item calls against ~1400
-- distinct links.
--
-- THE RULE: only resolved items are ever cached. When C_Item.GetItemInfo
-- answers nil the result falls straight through, because asking is what queues
-- the client's async load, and "unknown" is a transient state the whole engine
-- depends on re-checking once GET_ITEM_INFO_RECEIVED arrives (see
-- Data.GetActualItemLevel's contract below and the Assignment.lua header).
-- Caching a nil would freeze an alt's gear as permanently unreadable.
--
-- Dropped per generation rather than kept for the session: an heirloom's item
-- level scales with the level of the character doing the looking, and
-- PLAYER_LEVEL_UP already drives a recompute.

---@type table<string, table>
local ItemInfoCache = {}

---@type table<string, table>
local InstantInfoCache = {}

---Drops the item metadata memo. Called by WarbandMeDowns.Assignment's
---Recompute() and Reset(), alongside the other per-generation memos.
function Data.ClearItemCache()
    wipe(ItemInfoCache)
    wipe(InstantInfoCache)
end

---C_Item.GetItemInfoInstant's results for a link, memoized. Served off the link
---with no cache involved, so unlike GetItemInfo it cannot fail transiently and
---is always safe to remember.
---@param link ItemInfo
---@return table
local function InstantInfo(link)
    local cached = InstantInfoCache[link]
    if cached then
        return cached
    end

    local itemID, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
    cached = { itemID = itemID, equipLoc = equipLoc, classID = classID, subclassID = subclassID }
    InstantInfoCache[link] = cached
    return cached
end

---C_Item.GetItemInfo's results for a link, memoized - but only once the client
---actually has them. Returns nil while the item is uncached, which is a real
---answer callers must handle, not a failure.
---@param link ItemInfo?
---@return table?
local function ItemInfo(link)
    if not link then
        return nil
    end

    local cached = ItemInfoCache[link]
    if cached then
        return cached
    end

    local name, _, quality, _, _, _, _, _, equipLoc, _, _, _, _, bindType = C_Item.GetItemInfo(link)
    if not name then
        -- Not cached client-side yet. Asking was the point - it queues the
        -- load - but the nil must not be remembered.
        return nil
    end

    -- GetItemInfo answering is not the same question as the item being fully
    -- loaded: for a level-scaling item (Timewalking, some leveling-zone
    -- rewards) GetDetailedItemLevelInfo can return a real, non-nil number
    -- off incomplete data - not this item's actual level, just whatever the
    -- client has resolved so far. That number would sail past the `if
    -- itemLevel` check below and be cached as final. IsItemDataCachedByID is
    -- the real "is this done loading" signal; treat "not yet" exactly like
    -- the uncached-name case above and let the normal GET_ITEM_INFO_RECEIVED
    -- retry pick it up once it's actually ready.
    local itemID = InstantInfo(link).itemID
    if not itemID or not C_Item.IsItemDataCachedByID(itemID) then
        return nil
    end

    local itemLevel = C_Item.GetDetailedItemLevelInfo(link)
    local info = { quality = quality, equipLoc = equipLoc, bindType = bindType, itemLevel = itemLevel }

    -- Remembered only when *complete*. GetItemInfo can answer while the
    -- detailed item level has not arrived; that item is still served from this
    -- table now, so bind type and quality work, but it is re-asked next time
    -- instead of being frozen as unreadable.
    if itemLevel then
        ItemInfoCache[link] = info
    end
    return info
end

---@param link ItemInfo
---@return Enum.ItemBind bindType
function Data.GetItemBind(link)
    local info = ItemInfo(link)
    return info and info.bindType
end

---@param link ItemInfo
function Data.GetItemClassAndSubclass(link)
    local info = InstantInfo(link)
    return info.classID, info.subclassID
end

---The item's equip location read from GetItemInfoInstant, which is served
---straight off the link and works even for an item the client has not cached
---- unlike Data.GetItemEquipLocation, which goes through C_Item.GetItemInfo
---and returns nil until the item loads. Only used to work out *which slot* an
---unreadable item would compete for, so it can be excluded from just that
---slot's decisions instead of poisoning everything the character owns.
---@param link ItemInfo
---@return string?
function Data.GetInstantEquipLocation(link)
    return InstantInfo(link).equipLoc
end

---@param itemLink ItemInfo
---@param compareItemLink ItemInfo
---@return boolean
function Data.AreComparableItemTypes(itemLink, compareItemLink)
    local itemClassID, itemSubclassID = Data.GetItemClassAndSubclass(itemLink)
    local compareItemClassID, compareItemSubclassID = Data.GetItemClassAndSubclass(compareItemLink)

    if itemClassID ~= compareItemClassID then
        return false
    end

    if itemClassID == ItemClassWeapon then
        return itemSubclassID == compareItemSubclassID
    end

    return true
end

---The item's real, bonus-ID-adjusted item level, or nil when the client has
---not cached this item yet.
---
---Callers must NOT coerce a nil result to 0: "unknown" and "item level 0" are
---very different answers, and treating the first as the second makes an alt
---whose gear simply is not cached yet look like they have an empty slot - see
---WarbandMeDowns.Data.IsItemInfoResolved and the scorer in Assignment.lua.
---@param link ItemInfo
---@return number?
function Data.GetActualItemLevel(link)
    local info = ItemInfo(link)
    return info and info.itemLevel
end

---Whether the client has everything WarbandMeDowns needs about an item.
---
---C_Item.GetItemInfo returns nil for any item not in the client's cache, and
---bind type, quality and equip location all come out of that one call - so
---right after a login an alt's stored gear is routinely unreadable. Asking
---for it is also what queues the async load, so calling this doubles as the
---request: GET_ITEM_INFO_RECEIVED then marks the engine dirty (see
---Tooltip.lua's invalidation events) and the next recompute sees real data.
---@param link ItemInfo?
---@return boolean
function Data.IsItemInfoResolved(link)
    local info = ItemInfo(link)
    return info ~= nil and info.itemLevel ~= nil
end

---@param link ItemInfo
function Data.GetItemEquipLocation(link)
    local info = ItemInfo(link)
    return info and info.equipLoc
end

local OneHandWeaponEquipLocations = {
    INVTYPE_WEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true,
}

---Whether an item at `candidateEquipLocation` is a valid stand-in for
---something worn at `targetEquipLocation`. Deliberately asymmetric: an
---ambidextrous one-hander (INVTYPE_WEAPON) matches either hand, but a
---mainhand-only or offhand-only weapon only matches the plain ambidextrous
---target, never each other. Everything else (two-handers, rings, trinkets,
---armor, shields/holdables, ranged, tabards, ...) requires an exact match.
---@param candidateEquipLocation string
---@param targetEquipLocation string
---@return boolean
function Data.EquipLocationsMatch(candidateEquipLocation, targetEquipLocation)
    if candidateEquipLocation == targetEquipLocation then
        return true
    end

    if targetEquipLocation == "INVTYPE_WEAPON" then
        return OneHandWeaponEquipLocations[candidateEquipLocation]
    elseif targetEquipLocation == "INVTYPE_WEAPONMAINHAND" then
        return candidateEquipLocation == "INVTYPE_WEAPON"
    elseif targetEquipLocation == "INVTYPE_WEAPONOFFHAND" then
        return candidateEquipLocation == "INVTYPE_WEAPON"
    end

    return false
end

Data.EquipLocToSlotID = {
    INVTYPE_HEAD       = INVSLOT_HEAD,       -- 1
    INVTYPE_NECK       = INVSLOT_NECK,       -- 2
    INVTYPE_SHOULDER   = INVSLOT_SHOULDER,   -- 3
    INVTYPE_BODY       = INVSLOT_BODY,       -- 4 (shirt)
    INVTYPE_CHEST      = INVSLOT_CHEST,      -- 5
    INVTYPE_ROBE       = INVSLOT_CHEST,      -- 5
    INVTYPE_WAIST      = INVSLOT_WAIST,      -- 6
    INVTYPE_LEGS       = INVSLOT_LEGS,       -- 7
    INVTYPE_FEET       = INVSLOT_FEET,       -- 8
    INVTYPE_WRIST      = INVSLOT_WRIST,      -- 9
    INVTYPE_HAND       = INVSLOT_HAND,       -- 10
    INVTYPE_FINGER     = INVSLOT_FINGER1,    -- needs special handling
    INVTYPE_TRINKET    = INVSLOT_TRINKET1,   -- needs special handling
    INVTYPE_CLOAK      = INVSLOT_BACK,       -- 15
    INVTYPE_WEAPON     = INVSLOT_MAINHAND,   -- needs dual-wield handling
    INVTYPE_2HWEAPON   = INVSLOT_MAINHAND,
    INVTYPE_WEAPONMAINHAND = INVSLOT_MAINHAND,
    INVTYPE_WEAPONOFFHAND  = INVSLOT_OFFHAND,
    INVTYPE_SHIELD     = INVSLOT_OFFHAND,
    INVTYPE_HOLDABLE   = INVSLOT_OFFHAND,
    INVTYPE_RANGED     = INVSLOT_RANGED,
    INVTYPE_RANGEDRIGHT = INVSLOT_RANGED,
    INVTYPE_THROWN     = INVSLOT_RANGED,
    INVTYPE_RELIC      = INVSLOT_RANGED,
    INVTYPE_TABARD     = INVSLOT_TABARD,     -- 19
}

---@param bindType Enum.ItemBind
---@return boolean
function Data.CanItemBeSentToTwink(bindType)
    ---@type Enum.ItemBind[]
    local relevantForTwinks = {
        Enum.ItemBind.OnEquip,
        Enum.ItemBind.ToWoWAccount,
        Enum.ItemBind.ToBnetAccount,
        Enum.ItemBind.ToBnetAccountUntilEquipped
    }
    -- Coerced, not returned raw: Blizzard's tContains has historically answered
    -- 1/nil rather than true/false, and this function's result is stored and
    -- returned rather than only branched on.
    return not not tContains(relevantForTwinks, bindType)
end

local MinRecommendableQuality = (Enum and Enum.ItemQuality and Enum.ItemQuality.Uncommon) or LE_ITEM_QUALITY_UNCOMMON or 2

---@param link ItemInfo
---@return number quality
function Data.GetItemQuality(link)
    local info = ItemInfo(link)
    return info and info.quality
end

---Grey/white items are never worth recommending, regardless of bind type.
---@param quality number?
---@return boolean
function Data.IsQualityEligible(quality)
    return quality ~= nil and quality >= MinRecommendableQuality
end

---Bind types where equipping the item converts it to Soulbound - unlike
---ToWoWAccount/ToBnetAccount, which stay account-bound (sendable) forever
---regardless of equip history.
---@type Enum.ItemBind[]
local ConvertsToSoulboundOnEquip = {
    Enum.ItemBind.OnEquip,
    Enum.ItemBind.ToBnetAccountUntilEquipped,
}

---Whether a specific item instance is currently actually Soulbound, as
---opposed to Data.GetItemBind's static classification (e.g. "Bind on
---Equip"), which never changes once an instance actually binds.
---
---itemLocation - only ever obtainable for the currently logged-in
---character's own reachable items (bags/bank/equipped) - gives an
---authoritative live answer via C_Item.IsBound. Without one (any other
---warband character, read from DataStore's stored, possibly-stale
---snapshots, which never carry live bind state), the rule is simply:
---equipped means Soulbound (equipping always binds it), anything sitting in
---bags/bank/mail is assumed not yet bound.
---@param bindType Enum.ItemBind
---@param isEquipped boolean
---@param itemLocation ItemLocation?
---@return boolean
function Data.IsActuallySoulbound(bindType, isEquipped, itemLocation)
    if not tContains(ConvertsToSoulboundOnEquip, bindType) then
        return false
    end

    if itemLocation then
        return C_Item.IsBound(itemLocation) == true
    end

    return isEquipped == true
end

---Live ItemLocation for a real bag/bank slot - only ever valid for the
---currently logged-in character (ItemLocation cannot reference another
---character's items). Returns nil if unavailable or invalid.
---@param bagID number
---@param slotID number
---@return ItemLocation?
function Data.GetLiveBagItemLocation(bagID, slotID)
    if not ItemLocation or not ItemLocation.CreateFromBagAndSlot then
        return nil
    end

    local location = ItemLocation:CreateFromBagAndSlot(bagID, slotID)
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

---Groups items the way WarbandMeDowns.Data.AreComparableItemTypes does: two
---items are only ever comparable within the same slot-class. Used to bucket
---warband items in WarbandMeDowns.Assignment without repeating this pairing
---logic there.
---@param classID number
---@param subclassID number?
---@return string
function Data.SlotClassKey(classID, subclassID)
    if classID == ItemClassWeapon then
        return classID .. "." .. tostring(subclassID)
    end
    return tostring(classID)
end
