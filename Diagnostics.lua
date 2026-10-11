--[[----------------------------------------------------------------------------

  WarbandMeDowns/Diagnostics.lua
  The /wmd slash command, for inspecting why the engine reached a given
  recommendation. See WarbandMeDowns.lua for the license header covering the
  whole addon.

  The recommendation is a global assignment over the whole warband, so "why
  did it pick that character?" is not answerable from the tooltip line alone -
  it depends on every other character's floor and on which comparison basis
  each of them ended up using. `/wmd why <item link>` prints that table.

  The most useful column is `basis`: "pawn" means Pawn's per-spec score
  decided it, "ilvl" means the addon fell back to raw item level for that
  character (Pawn not installed, spec unknown, or Pawn could not score one of
  the items involved). A warband where every row says "ilvl" while Pawn is
  installed means the spec lookup is broken again - that exact failure is what
  made every recommendation item-level-only for a long time.

----------------------------------------------------------------------------]]--

WarbandMeDowns.Diagnostics = WarbandMeDowns.Diagnostics or {}
local Diagnostics = WarbandMeDowns.Diagnostics
local Assignment = WarbandMeDowns.Assignment
local Characters = WarbandMeDowns.Characters

local ColorHeading = "|cffffd100"
local ColorMuted = "|cff909090"
local ColorGood = "|cff40d060"
local ColorWarn = "|cffff8040"
local ColorReset = "|r"

---Pads to `width` first and colours afterwards: colour escapes count toward
---string.format's field width but take up no space on screen, so colouring
---before padding silently breaks the column alignment.
---@param text string
---@param width number
---@param color string?
---@return string
local function Pad(text, width, color)
    local padded = string.format("%-" .. width .. "s", text)
    if not color then
        return padded
    end
    return color .. padded .. ColorReset
end

---@param score number?
---@return string
local function FormatScore(score)
    if not score then
        return ColorMuted .. "-" .. ColorReset
    end
    return string.format("%.1f", score)
end

---@param link ItemInfo?
---@return string
local function FormatItem(link)
    if not link then
        return ColorMuted .. "(none)" .. ColorReset
    end
    return link
end

---@param row table
---@return string
local function FormatVerdict(row)
    if not row.eligible then
        return ColorMuted .. "cannot use this item type" .. ColorReset
    end
    if row.unresolved then
        return ColorWarn .. "WAITING on item data" .. ColorReset
    end
    if row.isWinner then
        return ColorGood .. "CLAIMS IT" .. ColorReset
    end
    if row.beatsFloor == nil then
        return ColorWarn .. "undecidable" .. ColorReset
    end
    if row.beatsFloor == 1 then
        -- An upgrade for them, but they are not who it goes to: either a
        -- higher-priority character claimed this copy first, or the pool had
        -- something even better for them.
        return "an upgrade, but claimed elsewhere"
    end
    return "keeps what they have"
end

---@param explanation table
local function PrintExplanation(explanation)
    WarbandMeDowns:Print(ColorHeading .. "why" .. ColorReset .. " " .. tostring(explanation.link))

    if explanation.rejection then
        WarbandMeDowns:Print("  not recommendable: " .. explanation.rejection)
        return
    end

    WarbandMeDowns:Printf(
        "  ilvl %s, quality %s, %s, slot-class %s",
        tostring(explanation.itemLevel),
        tostring(explanation.quality),
        tostring(explanation.equipLoc),
        tostring(explanation.slotClassKey)
    )

    for _, row in ipairs(explanation.rows) do
        if not row.eligible then
            WarbandMeDowns:Printf(
                "  %s%2d%s %-18s %s",
                ColorMuted, row.rank, ColorReset,
                row.displayName .. (row.isCurrent and " (you)" or ""),
                FormatVerdict(row)
            )
        else
            local usesPawn = row.basis == "pawn"
            WarbandMeDowns:Printf(
                "  %s%2d%s %-18s %s %s floor %s (%s) vs item %s -- %s",
                ColorMuted, row.rank, ColorReset,
                row.displayName .. (row.isCurrent and " (you)" or ""),
                Pad(usesPawn and "pawn" or "ilvl", 4, not usesPawn and ColorWarn or nil),
                Pad(row.scaleName or "no scale", 22, not row.scaleName and ColorMuted or nil),
                FormatItem(row.floor),
                FormatScore(row.floorScore),
                FormatScore(row.itemScore),
                FormatVerdict(row)
            )
        end
    end
end

---@param itemLink string
local function ExplainAndPrint(itemLink)
    local success, explanation = pcall(Assignment.ExplainItem, Assignment, itemLink)
    if not success then
        WarbandMeDowns:Print("error: " .. tostring(explanation))
        return
    end

    PrintExplanation(explanation)
end

local function PrintUsage()
    WarbandMeDowns:Print("usage:")
    WarbandMeDowns:Print("  /wmd why <item link>  - explain who the engine gives this item to, and why")
    WarbandMeDowns:Print("  /wmd ranks            - print the warband priority order")
    WarbandMeDowns:Print("  /wmd ilvl [name]      - break down a character's projected item level")
    WarbandMeDowns:Print("  /wmd refresh          - force a full recompute now")
    WarbandMeDowns:Print("(shift-click an item into chat to paste its link)")
end

---Prints the warband priority order, reading the same ranking record the
---settings table renders (Characters.GetWarbandRanking) so the two can never
---disagree about the order or the numbers. Spec and Pawn scale are added on top
---here; they are diagnostic-only and the panel has no column for them.
local function PrintRanks()
    WarbandMeDowns:Print(ColorHeading .. "warband priority order" .. ColorReset)

    local ranking = Characters.GetWarbandRanking()

    for _, entry in ipairs(ranking) do
        local specIndex = Characters.GetKnownSpecIndex(entry.character)
        local scaleName = WarbandMeDowns.Pawn.GetPawnScaleNameForCharacter(entry.character)

        -- The max projection, not the equipped average, is what the order is
        -- actually sorted on - print all three so this command can explain a
        -- rank that looks wrong against the equipped numbers.
        WarbandMeDowns:Printf(
            "  %s%2d%s %-18s level %-3d ilvl %-6.1f max %-6.1f theo %-6.1f spec %-4s %s",
            ColorMuted, entry.rank, ColorReset,
            entry.displayName .. (entry.isCurrent and " (you)" or ""),
            entry.level or 0,
            entry.itemLevel or 0,
            entry.maxItemLevel or 0,
            entry.theoreticalItemLevel or 0,
            specIndex and tostring(specIndex) or "?",
            scaleName or (ColorWarn .. "no Pawn scale" .. ColorReset)
        )
    end
end

---Resolves a character name typed by the player to a warband character key,
---accepting a bare name or "Name@Realm", case-insensitively. Defaults to the
---current character.
---@param input string?
---@return string?
local function ResolveCharacterArgument(input)
    if not input or input == "" then
        return DataStore.ThisCharKey
    end

    local wanted = input:lower()
    for _, character in ipairs(Characters.GetWarbandCharacters()) do
        local server, name = Characters.CharacterServerAndNameFromKey(character)
        if name and (name:lower() == wanted
            or (name .. "@" .. (server or "")):lower() == wanted) then
            return character
        end
    end

    return nil
end

---Prints the per-slot account behind one character's Max iLvl.
---@param character string
local function PrintItemLevels(character)
    Assignment:EnsureFresh()

    local breakdown = WarbandMeDowns.ItemLevel.ExplainMaxItemLevel(character)
    if not breakdown then
        WarbandMeDowns:Print("no data for " .. Characters.GetDisplayName(character) .. ".")
        return
    end

    WarbandMeDowns:Printf(
        "%sprojected item level for %s%s",
        ColorHeading, Characters.GetDisplayName(character), ColorReset
    )

    for _, row in ipairs(breakdown.rows) do
        local suffix = ""
        if row.gain > 0 then
            suffix = string.format("  %s+%.0f%s", ColorGood, row.gain, ColorReset)
        end
        -- An unreadable slot is held at infinity so nothing can "improve" it;
        -- say so rather than printing inf.
        local baseline = (row.baseline == math.huge) and "?" or string.format("%.0f", row.baseline)
        WarbandMeDowns:Printf(
            "  %s%-10s%s %s -> %.0f%s",
            ColorMuted, row.name, ColorReset, baseline, row.projected, suffix
        )
    end

    if breakdown.twoHanded then
        WarbandMeDowns:Printf(
            "  %stwo-handed: the main hand is counted for the off hand too%s",
            ColorMuted, ColorReset
        )
    end

    WarbandMeDowns:Printf(
        "  equipped %.2f, max %.2f (+%.2f from %d owned item%s)",
        breakdown.averageItemLevel or 0,
        breakdown.maxItemLevel or 0,
        (breakdown.maxItemLevel or 0) - (breakdown.averageItemLevel or 0),
        breakdown.ownedCount,
        breakdown.ownedCount == 1 and "" or "s"
    )

    if breakdown.overallItemLevel then
        -- Blizzard's own best-gear-you-own number, as a sanity check. Max iLvl
        -- may legitimately exceed it (it also counts bank and mail, and
        -- ignores level requirements); far above it on a max-level character
        -- means a slot is being scored wrong.
        WarbandMeDowns:Printf(
            "  %sBlizzard's overall item level for comparison: %.2f%s",
            ColorMuted, breakdown.overallItemLevel, ColorReset
        )
    end
end

---AceConsole handler for /wmd.
---
---Arguments come from AceConsole:GetArgs rather than a hand-rolled split
---because a shift-clicked item link is not one word: GetArgs walks past
---`|H...|h...|h` hyperlinks and `|T...|t` textures and hands the whole link
---back as a single argument. It also trims for us, and returns nil - not an
---empty string - for an argument that isn't there.
---@param input string
function WarbandMeDowns:HandleChatCommand(input)
    input = input or ""

    local command, argumentPosition = self:GetArgs(input, 1)
    command = (command or ""):lower()

    if command == "why" then
        local itemLink = self:GetArgs(input, 1, argumentPosition)
        if not itemLink then
            WarbandMeDowns:Print("usage: /wmd why <item link>")
            return
        end
        ExplainAndPrint(itemLink)
    elseif command == "ranks" then
        PrintRanks()
    elseif command == "ilvl" then
        local name = self:GetArgs(input, 1, argumentPosition)
        local character = ResolveCharacterArgument(name)
        if not character then
            WarbandMeDowns:Print("no warband character named '" .. tostring(name) .. "'.")
            return
        end
        PrintItemLevels(character)
    elseif command == "refresh" then
        -- Straight to Recompute rather than MarkDirty + EnsureFresh: the point
        -- of the command is to do the work now, and this is what tells it the
        -- recompute was asked for, so it reports the timing even in a packaged
        -- build.
        Assignment:Recompute(true)
    else
        PrintUsage()
    end
end

function Diagnostics:Initialize()
    WarbandMeDowns:RegisterChatCommand("wmd", "HandleChatCommand")
end
