--[[----------------------------------------------------------------------------

  WarbandMeDowns/WarbandMeDowns.lua
  Recommends twinks for warbound gear

  Copyright (c) 2025 Sören Gade

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>.

----------------------------------------------------------------------------]]--

-- *** Bootstrap
--
-- This file only creates the addon object. WoW addon files are separate Lua
-- chunks - `local`s never cross files - so anything that needs to be shared
-- lives as a namespaced field on this table instead (WarbandMeDowns.Data,
-- WarbandMeDowns.Characters, WarbandMeDowns.Pawn, WarbandMeDowns.Assignment). See
-- WarbandMeDowns.toc for load order: this file must load first.

-- AceConsole gives /wmd and the standard "|cff33ff99WarbandMeDowns|r:" print
-- prefix; AceEvent replaces a hand-rolled event frame. AceAddon calls each
-- embedded library's OnEmbedDisable on disable, which is what unregisters the
-- events - see OnDisable in Tooltip.lua.
WarbandMeDowns = LibStub("AceAddon-3.0"):NewAddon(
    "WarbandMeDowns", "AceConsole-3.0", "AceEvent-3.0")

-- There is deliberately no WarbandMeDowns.Util here. It used to hold
-- arrayContains and clearTable, which are Blizzard's own `tContains` and
-- `wipe` globals under different names.
