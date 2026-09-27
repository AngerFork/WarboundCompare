-- Core.lua
-- Saved-variable management and character snapshots.

local ADDON_NAME, ns = ...

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

-- Armor proficiency by class file name (max-level proficiency; every class
-- can equip its listed type from level 1 in modern WoW).
ns.ARMOR_BY_CLASS = {
    WARRIOR     = Enum.ItemArmorSubclass.Plate,
    PALADIN     = Enum.ItemArmorSubclass.Plate,
    DEATHKNIGHT = Enum.ItemArmorSubclass.Plate,
    HUNTER      = Enum.ItemArmorSubclass.Mail,
    SHAMAN      = Enum.ItemArmorSubclass.Mail,
    EVOKER      = Enum.ItemArmorSubclass.Mail,
    ROGUE       = Enum.ItemArmorSubclass.Leather,
    MONK        = Enum.ItemArmorSubclass.Leather,
    DRUID       = Enum.ItemArmorSubclass.Leather,
    DEMONHUNTER = Enum.ItemArmorSubclass.Leather,
    MAGE        = Enum.ItemArmorSubclass.Cloth,
    PRIEST      = Enum.ItemArmorSubclass.Cloth,
    WARLOCK     = Enum.ItemArmorSubclass.Cloth,
}

-- Classes that can equip shields (Armor subclass Shield).
ns.SHIELD_CLASSES = {
    WARRIOR = true,
    PALADIN = true,
    SHAMAN  = true,
}

-- Equipment slots we snapshot. (4 = shirt and 19 = tabard are skipped.)
ns.TRACKED_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

function ns.Print(...)
    print("|cff82c5ffWarboundCompare:|r", ...)
end

function ns.IsDebug()
    return ns.db and ns.db.debug
end

-- ---------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------

local function InitDB()
    WarboundCompareDB = WarboundCompareDB or {}
    WarboundCompareDB.characters = WarboundCompareDB.characters or {}
    if WarboundCompareDB.bindFilters == nil then
        WarboundCompareDB.bindFilters = {
            warbound = true, -- Warbound / account-bound
            wue      = true, -- Warbound until equipped
            boe      = true, -- Binds when equipped
        }
    end
    ns.db = WarboundCompareDB
end

function ns.GetPlayerKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    if not name or not realm then return nil end
    return name .. "-" .. realm
end

-- ---------------------------------------------------------------------------
-- Snapshot
-- ---------------------------------------------------------------------------

-- Reads one equipped slot via the ItemLocation API, which works off the
-- live item instance rather than the item-info cache.
-- Returns: "empty"  - the slot positively has nothing in it
--          "ok"     - item found; link/ilvl returned
--          "nodata" - item data unavailable right now (keep old snapshot)
local function ReadSlot(slot)
    local loc = ItemLocation:CreateFromEquipmentSlot(slot)
    local okExists, exists = pcall(C_Item.DoesItemExist, loc)
    if not okExists then
        return "nodata"
    end
    if not exists then
        return "empty"
    end

    local okLink, link = pcall(C_Item.GetItemLink, loc)
    local okIlvl, ilvl = pcall(C_Item.GetCurrentItemLevel, loc)
    link = okLink and link or nil
    ilvl = okIlvl and ilvl or nil

    if link == nil and ilvl == nil then
        return "nodata"
    end
    return "ok", link, ilvl
end

-- Records (or refreshes) the current character. Called at login, at logout,
-- and whenever equipment changes.
--
-- conservative = true (used at logout, when the item system may already be
-- shutting down): update slots we can read, but never erase existing data
-- just because the API came back empty-handed.
function ns.SnapshotCharacter(conservative)
    if not ns.db then return end

    local key = ns.GetPlayerKey()
    if not key then return end

    local name = UnitName("player")
    local realm = GetRealmName()
    local level = UnitLevel("player")
    local raceName, raceFile = UnitRace("player")
    local className, classFile = UnitClass("player")

    local entry = ns.db.characters[key] or {}
    entry.name      = name
    entry.realm     = realm
    entry.level     = level
    entry.race      = raceName
    entry.raceFile  = raceFile
    entry.className = className
    entry.classFile = classFile
    entry.armorType = ns.ARMOR_BY_CLASS[classFile]
    entry.lastSeen  = time()

    if entry.enabled == nil then
        entry.enabled = true
    end

    entry.gear = entry.gear or {}
    for _, slot in ipairs(ns.TRACKED_SLOTS) do
        local state, link, ilvl = ReadSlot(slot)
        if state == "ok" then
            entry.gear[slot] = {
                ilvl = ilvl or 0,
                link = link,
            }
        elseif state == "empty" and not conservative then
            entry.gear[slot] = nil
        end
        -- "nodata" (or "empty" while conservative): keep whatever we had.
    end

    ns.db.characters[key] = entry
end

-- /wbc scan - force a snapshot and print what was captured per slot.
function ns.DebugScan()
    ns.SnapshotCharacter()
    local key = ns.GetPlayerKey()
    local entry = key and ns.db and ns.db.characters[key]
    if not entry then
        ns.Print("No entry could be created for this character.")
        return
    end
    ns.Print(string.format("Snapshot for %s:", key))
    for _, slot in ipairs(ns.TRACKED_SLOTS) do
        local gear = entry.gear and entry.gear[slot]
        if gear then
            ns.Print(string.format("  slot %d: ilvl %d %s", slot, gear.ilvl or 0, gear.link or "(no link)"))
        else
            ns.Print(string.format("  slot %d: empty", slot))
        end
    end
end

-- Sorted array of character entries for the options panel and tooltip.
function ns.GetSortedCharacters()
    local list = {}
    if ns.db then
        for key, entry in pairs(ns.db.characters) do
            entry.key = key
            list[#list + 1] = entry
        end
    end
    table.sort(list, function(a, b)
        if a.name == b.name then
            return (a.realm or "") < (b.realm or "")
        end
        return a.name < b.name
    end)
    return list
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            InitDB()
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- arg1 = isInitialLogin. Snapshot after a short delay so item data
        -- has finished streaming in; also covers /reload via the
        -- equipment-changed event during normal play.
        if arg1 then
            C_Timer.After(3, function() ns.SnapshotCharacter() end)
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        ns.SnapshotCharacter()
    elseif event == "PLAYER_LOGOUT" then
        -- Conservative: at logout the item system may already be partially
        -- torn down. Update what we can read, never erase what we can't.
        ns.SnapshotCharacter(true)
    end
end)
