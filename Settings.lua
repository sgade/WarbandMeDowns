--[[----------------------------------------------------------------------------

  WarbandMeDowns/Settings.lua
  A read-only settings page: explains what the addon does and visualizes the
  warband priority order used internally to decide who gets an item next.
  Holds no state of its own - everything is read live from DataStore via
  WarbandMeDowns.Characters. See docs/UI_DESIGN.md for the UI conventions
  followed here, and WarbandMeDowns.lua for the license header covering the
  whole addon.

----------------------------------------------------------------------------]]--

WarbandMeDowns.Settings = WarbandMeDowns.Settings or {}
-- Not aliased to a local `Settings` like other modules alias their table -
-- that name is Blizzard's global Settings API (Settings.RegisterCanvasLayoutCategory
-- etc.), used throughout this file, and a same-named local would shadow it.
local SettingsPage = WarbandMeDowns.Settings
local Characters = WarbandMeDowns.Characters

-- *** Layout constants (see docs/UI_DESIGN.md)

local PANEL_PADDING = 12
local ROW_HEIGHT = 22
local SECTION_HEADER_HEIGHT = 24

-- The table's columns, in display order. One list rather than a widths table
-- plus two creation chains plus a styling list: those four used to be kept in
-- sync by hand, and adding a column meant editing all of them.
--
-- `key` names both the row frame's fontstring (`key .. "Text"`) and the field
-- GetRowData puts the cell's text in, so a column is added here and nowhere
-- else. Nine of them have to fit the width the Settings window gives a canvas
-- panel, so the widths are tighter than they would otherwise need to be: 528px
-- of columns plus eight 4px gaps = 560px.
local Columns = {
    { key = "rank", header = "#", width = 24 },
    { key = "name", header = "Character", width = 110 },
    { key = "realm", header = "Realm", width = 74 },
    { key = "level", header = "Level", width = 40 },
    { key = "itemLevel", header = "iLvl", width = 44 },
    { key = "maxItemLevel", header = "Max iLvl", width = 52 },
    { key = "theoreticalItemLevel", header = "Theo. iLvl", width = 60 },
    { key = "bagsBank", header = "Bags/Bank", width = 66 },
    { key = "mail", header = "Mail", width = 58 },
}

local ColorGold = { 1, 0.82, 0 }
local ColorMuted = { 0.6, 0.6, 0.6 }
local ColorBody = { 0.85, 0.85, 0.85 }
local ColorActionable = { 0.45, 0.75, 0.45 }

---@type Frame?
local Panel

-- *** Last-scanned times
--
-- DataStore's core module stamps a `lastUpdate` time() on every character
-- table it writes, exposed generically via DataStore:GetModuleLastUpdateByKey
-- (see Thaoky/DataStore, DataStore/API/Core.lua). Note DataStore_Containers
-- shares ONE combined timestamp for bags and bank - every bag- or bank-slot
-- scan stamps the same field - so "last bags check" and "last bank check"
-- cannot be told apart; DataStore_Mails does track its own separately.

local WarnedMissingLastUpdateAPI = false

---@param moduleName string
---@param character string
---@return number? epochSeconds
local function GetModuleLastUpdate(moduleName, character)
    if type(DataStore.GetModuleLastUpdateByKey) ~= "function" then
        --@alpha@
        if not WarnedMissingLastUpdateAPI then
            WarnedMissingLastUpdateAPI = true
            WarbandMeDowns:Print("warn: DataStore.GetModuleLastUpdateByKey not available.")
        end
        --@end-alpha@
        return nil
    end

    local success, lastUpdate = pcall(DataStore.GetModuleLastUpdateByKey, DataStore, moduleName, character)
    if not success or not lastUpdate or lastUpdate == 0 then
        return nil
    end
    return lastUpdate
end

---Formats an epoch-seconds timestamp as a short "time ago" string.
---@param epochSeconds number?
---@return string
local function FormatElapsed(epochSeconds)
    if not epochSeconds then
        return "—"
    end

    local elapsed = time() - epochSeconds
    if elapsed < 60 then
        return "just now"
    elseif elapsed < 3600 then
        return math.floor(elapsed / 60) .. "m ago"
    elseif elapsed < 86400 then
        return math.floor(elapsed / 3600) .. "h ago"
    else
        return math.floor(elapsed / 86400) .. "d ago"
    end
end

-- *** Row data

---@param itemLevel number?
---@return string
local function FormatItemLevel(itemLevel)
    if not itemLevel or itemLevel <= 0 then
        return "—"
    end
    return string.format("%.0f", itemLevel)
end

---Formats one warband character's row from the shared ranking record, adding
---the two things only this panel shows: the class colour and the per-module
---last-scanned times.
---
---Every field named `<column key>Text` is what that column renders; see
---`Columns` above.
---@param entry WarbandMeDownsRankedCharacter # see WarbandMeDowns.Characters.GetWarbandRanking
---@return table
local function GetRowData(entry)
    local server = Characters.CharacterServerAndNameFromKey(entry.character)

    local classSuccess, _, classToken = pcall(
        DataStore.GetCharacterClass, DataStore, entry.character)

    return {
        rankText = tostring(entry.rank),
        nameText = entry.displayName .. (entry.isCurrent and " (You)" or ""),
        realmText = (server and server ~= "") and server or "—",
        levelText = entry.level and tostring(entry.level) or "—",
        itemLevelText = FormatItemLevel(entry.itemLevel),
        maxItemLevelText = FormatItemLevel(entry.maxItemLevel),
        theoreticalItemLevelText = FormatItemLevel(entry.theoreticalItemLevel),
        -- Rendered green only when the projection is actually an improvement,
        -- so a row where nothing is waiting to be equipped stays quiet.
        maxIsUpgrade = (entry.maxItemLevel and entry.itemLevel
            and entry.maxItemLevel - entry.itemLevel >= 0.5) or false,
        theoreticalIsUpgrade = (entry.theoreticalItemLevel and entry.maxItemLevel
            and entry.theoreticalItemLevel - entry.maxItemLevel >= 0.5) or false,
        projectionUnresolved = entry.unresolved,
        classToken = classSuccess and classToken or nil,
        bagsBankText = FormatElapsed(GetModuleLastUpdate("DataStore_Containers", entry.character)),
        mailText = FormatElapsed(GetModuleLastUpdate("DataStore_Mails", entry.character)),
    }
end

-- *** Panel construction

---Creates one column's fontstring, chained off the previous column so
---headers and rows always line up.
---@param parent Frame
---@param relativeTo Frame?
---@param width number
---@return FontString
local function CreateColumn(parent, relativeTo, width)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if relativeTo then
        text:SetPoint("LEFT", relativeTo, "RIGHT", 4, 0)
    else
        text:SetPoint("LEFT", parent, "LEFT", 0, 0)
    end
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return text
end

---Colors one of the two projected item level cells. Rows are pooled, so this
---always sets a color rather than leaving the previous row's one behind.
---@param text FontString
---@param unresolved boolean
---@param isUpgrade boolean
local function SetProjectionColor(text, unresolved, isUpgrade)
    if unresolved then
        text:SetTextColor(unpack(ColorMuted))
    elseif isUpgrade then
        text:SetTextColor(unpack(ColorActionable))
    else
        text:SetTextColor(1, 1, 1)
    end
end

---Lazily builds a row's column fontstrings on first use, then always
---overwrites their values - rows are pooled and reused by the ScrollView, so
---nothing here may assume a clean frame.
---@param row Frame
---@param data table
local function InitializeRow(row, data)
    if not row[Columns[1].key .. "Text"] then
        local previous = nil
        for _, column in ipairs(Columns) do
            local text = CreateColumn(row, previous, column.width)
            row[column.key .. "Text"] = text
            previous = text
        end
    end

    for _, column in ipairs(Columns) do
        local field = column.key .. "Text"
        row[field]:SetText(data[field] or "")
        -- Unconditional: rows are pooled, so a cell that skipped setting its
        -- colour would keep the previous row's.
        row[field]:SetTextColor(unpack(ColorMuted))
    end

    local classColor = data.classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.classToken]
    if classColor then
        row.nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
    else
        row.nameText:SetTextColor(1, 1, 1)
    end

    row.levelText:SetTextColor(1, 1, 1)
    row.itemLevelText:SetTextColor(1, 1, 1)

    -- Muted whenever some of this character's item data still isn't cached:
    -- the numbers are the best answer available right now, not the final one.
    SetProjectionColor(row.maxItemLevelText, data.projectionUnresolved, data.maxIsUpgrade)
    SetProjectionColor(row.theoreticalItemLevelText, data.projectionUnresolved, data.theoreticalIsUpgrade)
end

---Builds a header row from the same `Columns` list InitializeRow lays out, so
---headers and cells cannot drift apart.
---@param parent Frame
---@return Frame
local function CreateHeaderRow(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(SECTION_HEADER_HEIGHT)

    local previous = nil
    for _, column in ipairs(Columns) do
        local text = CreateColumn(header, previous, column.width)
        text:SetText(column.header)
        text:SetFontObject("GameFontNormalSmall")
        text:SetTextColor(unpack(ColorMuted))
        previous = text
    end

    return header
end

---Builds the static chrome once: title, explanation, column headers, and the
---scrollable priority table. Idempotent - safe to call multiple times.
---@return Frame
local function BuildPanel()
    if Panel then
        return Panel
    end

    Panel = CreateFrame("Frame")

    local title = Panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", Panel, "TOPLEFT", PANEL_PADDING, -PANEL_PADDING)
    title:SetText("WarbandMeDowns")
    title:SetTextColor(unpack(ColorGold))

    local explanation = Panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    explanation:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    explanation:SetPoint("RIGHT", Panel, "RIGHT", -PANEL_PADDING, 0)
    explanation:SetJustifyH("LEFT")
    explanation:SetWordWrap(true)
    explanation:SetTextColor(unpack(ColorBody))
    explanation:SetText(
        "WarbandMeDowns ranks your warband to decide who should get each piece of warbound gear. " ..
        "Characters are ordered by current level first, then by the Max iLvl column below - what they " ..
        "would be at having equipped everything usable they already carry, rather than what they happen " ..
        "to be wearing. This is the exact order used everywhere the addon makes a recommendation. " ..
        "Pawn, if installed, decides which of two items is better for a given character's spec, but it " ..
        "never changes this ranking. Use /wmd why <item link> to see how a particular item was assigned."
    )

    local columnLegend = Panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    columnLegend:SetPoint("TOPLEFT", explanation, "BOTTOMLEFT", 0, -8)
    columnLegend:SetPoint("RIGHT", Panel, "RIGHT", -PANEL_PADDING, 0)
    columnLegend:SetJustifyH("LEFT")
    columnLegend:SetWordWrap(true)
    columnLegend:SetText(
        "iLvl is what a character has equipped right now. Max iLvl is where they would land if they " ..
        "equipped everything usable already sitting in their bags, bank and mail - level requirements " ..
        "ignored. Theo. iLvl additionally counts the gear this addon would send them from the rest of " ..
        "the warband. Greyed-out values mean some of that item data hasn't loaded yet."
    )

    local divider = Panel:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", columnLegend, "BOTTOMLEFT", 0, -12)
    divider:SetPoint("RIGHT", Panel, "RIGHT", -PANEL_PADDING, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(0.3, 0.3, 0.3, 0.6)

    local sectionLabel = Panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sectionLabel:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -8)
    sectionLabel:SetText("Warband Priority Order")
    sectionLabel:SetTextColor(unpack(ColorGold))

    local headerRow = CreateHeaderRow(Panel)
    headerRow:SetPoint("TOPLEFT", sectionLabel, "BOTTOMLEFT", 0, -8)
    headerRow:SetPoint("RIGHT", Panel, "RIGHT", -PANEL_PADDING, 0)

    local scrollBox = CreateFrame("Frame", nil, Panel, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", Panel, "BOTTOMRIGHT", -(PANEL_PADDING + 20), PANEL_PADDING)

    local scrollBar = CreateFrame("EventFrame", nil, Panel, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT")
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT")

    local scrollView = CreateScrollBoxListLinearView()
    scrollView:SetElementExtent(ROW_HEIGHT)
    scrollView:SetElementInitializer("Frame", InitializeRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, scrollView)

    Panel.scrollView = scrollView
    Panel:SetScript("OnShow", SettingsPage.RefreshTable)

    return Panel
end

-- *** Refresh

---Rebuilds the priority table from Characters.GetWarbandRanking().
---Called whenever the settings page is shown, since DataStore state (levels,
---item levels, which characters have been scanned) can change between
---visits. Recomputing on every show is cheap - a small warband and a
---handful of DataStore reads per character - so no caching is needed here.
function SettingsPage.RefreshTable()
    if not Panel or not Panel.scrollView then
        return
    end

    -- The one ranking the whole addon shares - same order and same numbers
    -- /wmd ranks prints, and the order the engine actually settled under.
    -- Failing to build it must not take the panel down with it, so a failure
    -- leaves an empty table rather than erroring out of OnShow.
    local success, ranking = pcall(Characters.GetWarbandRanking)
    if not success then
        WarbandMeDowns:Print("warn: could not rank the warband: " .. tostring(ranking))
        ranking = {}
    end

    local dataProvider = CreateDataProvider()
    for _, entry in ipairs(ranking) do
        dataProvider:Insert(GetRowData(entry))
    end

    Panel.scrollView:SetDataProvider(dataProvider)
end

-- *** Registration

---Builds and registers the WarbandMeDowns settings category. Safe to call
---once from OnInitialize. Never throws: a Settings API failure is printed as
---a warning instead of breaking the rest of the addon's startup.
function SettingsPage:Initialize()
    local success, errorMessage = pcall(function()
        local panel = BuildPanel()
        local category = Settings.RegisterCanvasLayoutCategory(panel, "WarbandMeDowns")
        Settings.RegisterAddOnCategory(category)
    end)

    if not success then
        WarbandMeDowns:Print("warn: could not register settings page: " .. tostring(errorMessage))
    end
end
