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

-- Which game we're running in. Retail reports WOW_PROJECT_MAINLINE (1);
-- WoW Forever reports its own project ID (18). Anything that isn't retail
-- gets the Forever rules.
ns.IS_RETAIL = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
ns.IS_FOREVER = not ns.IS_RETAIL

-- Equipment slots we snapshot. (4 = shirt and 19 = tabard are skipped.)
-- Forever still has the dedicated ranged slot (18): bows, guns, wands,
-- thrown weapons, librams, idols, totems.
ns.TRACKED_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
if ns.IS_FOREVER then
    table.insert(ns.TRACKED_SLOTS, 18)
end

-- ---------------------------------------------------------------------------
-- Proficiency detection (Forever)
-- ---------------------------------------------------------------------------

-- In Forever, armor and weapon proficiencies are learned (plate/mail at 40,
-- weapon skills from trainers), so we record what each character actually
-- knows instead of trusting a static table.

local SPELL_PLATE_MAIL = 750
local SPELL_MAIL = 8737

-- Starting armor for classes that upgrade at 40.
local FOREVER_BASE_ARMOR = {
    WARRIOR = Enum.ItemArmorSubclass.Mail,
    PALADIN = Enum.ItemArmorSubclass.Mail,
    HUNTER  = Enum.ItemArmorSubclass.Leather,
    SHAMAN  = Enum.ItemArmorSubclass.Leather,
}

-- Weapon skill spell -> Enum.ItemWeaponSubclass value.
local W = Enum.ItemWeaponSubclass or {}
local WEAPON_SKILL_SPELLS = {
    [196]   = W.Axe1H or 0,
    [197]   = W.Axe2H or 1,
    [264]   = W.Bows or 2,
    [266]   = W.Guns or 3,
    [198]   = W.Mace1H or 4,
    [199]   = W.Mace2H or 5,
    [200]   = W.Polearm or 6,
    [201]   = W.Sword1H or 7,
    [202]   = W.Sword2H or 8,
    [227]   = W.Staff or 10,
    [15590] = W.Unarmed or 13,
    [1180]  = W.Dagger or 15,
    [2567]  = W.Thrown or 16,
    [5011]  = W.Crossbow or 18,
    [5009]  = W.Wand or 19,
}

local function KnowsSpell(spellID)
    local checks = {
        IsPlayerSpell,
        C_SpellBook and C_SpellBook.IsSpellKnown,
        IsSpellKnown,
    }
    for _, check in ipairs(checks) do
        if check then
            local ok, known = pcall(check, spellID)
            if ok and known then
                return true
            end
        end
    end
    return false
end

-- Returns the set of weapon subclasses this character has trained, or nil
-- if nothing at all was detected (which means detection isn't working, since
-- every class starts with at least one weapon skill).
local function DetectWeaponSkills()
    local skills = {}
    local found = false
    for spellID, subclassID in pairs(WEAPON_SKILL_SPELLS) do
        if KnowsSpell(spellID) then
            skills[subclassID] = true
            found = true
        end
    end
    return found and skills or nil
end

-- Best armor type this character can wear right now.
local function DetectArmorType(classFile, level, detectionWorks)
    local base = FOREVER_BASE_ARMOR[classFile]
    if not base then
        -- Cloth, leather-only classes: same as retail.
        return ns.ARMOR_BY_CLASS[classFile]
    end
    if detectionWorks then
        if KnowsSpell(SPELL_PLATE_MAIL) then
            return Enum.ItemArmorSubclass.Plate
        end
        if KnowsSpell(SPELL_MAIL) then
            return Enum.ItemArmorSubclass.Mail
        end
        return base
    end
    -- Spell checks unavailable: assume the upgrade was trained at 40.
    if (level or 0) >= 40 then
        return ns.ARMOR_BY_CLASS[classFile]
    end
    return base
end

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
    entry.lastSeen  = time()

    if ns.IS_FOREVER then
        local weapons = DetectWeaponSkills()
        entry.weapons   = weapons -- nil means "use the static table"
        entry.armorType = DetectArmorType(classFile, level, weapons ~= nil)
    else
        entry.weapons   = nil
        entry.armorType = ns.ARMOR_BY_CLASS[classFile]
    end

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
    ns.Print(string.format("Snapshot for %s (%s):", key, ns.IS_FOREVER and "Forever" or "Retail"))

    local armorName = entry.armorType
        and C_Item.GetItemSubClassInfo(Enum.ItemClass.Armor, entry.armorType)
    ns.Print("  armor type: " .. tostring(armorName or entry.armorType))

    if ns.IS_FOREVER then
        if entry.weapons then
            local names = {}
            for subclassID in pairs(entry.weapons) do
                names[#names + 1] = C_Item.GetItemSubClassInfo(Enum.ItemClass.Weapon, subclassID)
                    or tostring(subclassID)
            end
            table.sort(names)
            ns.Print("  weapon skills: " .. table.concat(names, ", "))
        else
            ns.Print("  weapon skills: not detected (using built-in class table)")
        end
    end

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
