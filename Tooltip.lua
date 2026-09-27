-- Tooltip.lua
-- Adds a "Warband Comparison" section to the tooltip of Warbound armor.

local ADDON_NAME, ns = ...
local L = ns.L

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

-- GetItemInfo bind values mapped to filter categories. WuE items often
-- report the base item's bind (2 = BoE) because WuE is applied per-drop via
-- bonus IDs, so the rendered bind line takes priority over these.
local BINDTYPE_CATEGORY = {}
do
    local e = Enum.ItemBind or {}
    BINDTYPE_CATEGORY[e.OnEquip or 2]                     = "boe"
    BINDTYPE_CATEGORY[e.ToWoWAccount or 7]                = "warbound"
    BINDTYPE_CATEGORY[e.ToBnetAccount or 8]               = "warbound"
    BINDTYPE_CATEGORY[e.ToBnetAccountUntilEquipped or 9]  = "wue"
end

-- Blizzard's own localized bind-line strings, mapped to categories, so the
-- comparison is locale-independent. "soulbound" is a sentinel meaning the
-- item is already stuck on one character and can't be shared.
local LINE_CATEGORY = {}
do
    local function Add(globalName, category)
        local text = _G[globalName]
        if type(text) == "string" then
            LINE_CATEGORY[text] = category
        end
    end
    Add("ITEM_ACCOUNTBOUND_UNTIL_EQUIP", "wue")
    Add("ITEM_BIND_TO_BNETACCOUNT_UNTIL_EQUIP", "wue")
    Add("ITEM_ACCOUNTBOUND", "warbound")
    Add("ITEM_BNETACCOUNTBOUND", "warbound")
    Add("ITEM_BIND_TO_ACCOUNT", "warbound")
    Add("ITEM_BIND_TO_BNETACCOUNT", "warbound")
    Add("ITEM_BIND_ON_EQUIP", "boe")
    Add("ITEM_SOULBOUND", "soulbound")
end

local ARMOR_CLASS_ID = Enum.ItemClass.Armor
local WEAPON_CLASS_ID = Enum.ItemClass.Weapon
local SUBCLASS_GENERIC = Enum.ItemArmorSubclass.Generic   -- necks, rings, trinkets
local SUBCLASS_SHIELD = Enum.ItemArmorSubclass.Shield
local SUBCLASS_COSMETIC = Enum.ItemArmorSubclass.Cosmetic

-- Per-class weapon proficiencies (current retail). Values are
-- Enum.ItemWeaponSubclass with numeric fallbacks.
local W = Enum.ItemWeaponSubclass or {}
local AXE1   = W.Axe1H or 0
local AXE2   = W.Axe2H or 1
local BOW    = W.Bows or 2
local GUN    = W.Guns or 3
local MACE1  = W.Mace1H or 4
local MACE2  = W.Mace2H or 5
local POLE   = W.Polearm or 6
local SWORD1 = W.Sword1H or 7
local SWORD2 = W.Sword2H or 8
local GLAIVE = W.Warglaive or 9
local STAFF  = W.Staff or 10
local FIST   = W.Unarmed or 13
local DAGGER = W.Dagger or 15
local XBOW   = W.Crossbow or 18
local WAND   = W.Wand or 19
local FISHING = W.Fishingpole or 20

local function Set(...)
    local set = {}
    for i = 1, select("#", ...) do
        set[select(i, ...)] = true
    end
    return set
end

local WEAPON_PROFICIENCIES = {
    DEATHKNIGHT = Set(AXE1, AXE2, MACE1, MACE2, SWORD1, SWORD2, POLE),
    DEMONHUNTER = Set(GLAIVE, FIST, AXE1, SWORD1),
    DRUID       = Set(STAFF, POLE, DAGGER, FIST, MACE1, MACE2),
    EVOKER      = Set(STAFF, DAGGER, FIST, AXE1, AXE2, MACE1, MACE2, SWORD1, SWORD2),
    HUNTER      = Set(BOW, GUN, XBOW, POLE, STAFF, DAGGER, FIST, AXE1, AXE2, SWORD1, SWORD2),
    MAGE        = Set(STAFF, WAND, DAGGER, SWORD1),
    MONK        = Set(STAFF, POLE, FIST, AXE1, MACE1, SWORD1),
    PALADIN     = Set(AXE1, AXE2, MACE1, MACE2, SWORD1, SWORD2, POLE),
    PRIEST      = Set(STAFF, WAND, DAGGER, MACE1),
    ROGUE       = Set(DAGGER, FIST, AXE1, MACE1, SWORD1, BOW, GUN, XBOW),
    SHAMAN      = Set(STAFF, DAGGER, FIST, AXE1, AXE2, MACE1, MACE2),
    WARLOCK     = Set(STAFF, WAND, DAGGER, SWORD1),
    WARRIOR     = Set(DAGGER, FIST, AXE1, AXE2, MACE1, MACE2, SWORD1, SWORD2, POLE, STAFF, BOW, GUN, XBOW),
}

local ARMOR_TYPE_SUBCLASSES = {
    [Enum.ItemArmorSubclass.Cloth]   = true,
    [Enum.ItemArmorSubclass.Leather] = true,
    [Enum.ItemArmorSubclass.Mail]    = true,
    [Enum.ItemArmorSubclass.Plate]   = true,
}

-- Which inventory slot(s) an equip location maps to. Multi-slot entries
-- (rings, trinkets) compare against whichever slot holds the weaker item,
-- since that is the piece the new item would replace.
local EQUIPLOC_TO_SLOTS = {
    INVTYPE_HEAD     = { 1 },
    INVTYPE_NECK     = { 2 },
    INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST    = { 5 },
    INVTYPE_ROBE     = { 5 },
    INVTYPE_WAIST    = { 6 },
    INVTYPE_LEGS     = { 7 },
    INVTYPE_FEET     = { 8 },
    INVTYPE_WRIST    = { 9 },
    INVTYPE_HAND     = { 10 },
    INVTYPE_FINGER   = { 11, 12 },
    INVTYPE_TRINKET  = { 13, 14 },
    INVTYPE_CLOAK    = { 15 },
    INVTYPE_SHIELD   = { 17 },
    INVTYPE_HOLDABLE = { 17 },
    -- Weapons. One-handers and two-handers compare against the main hand;
    -- explicit off-hand weapons compare against the off-hand.
    INVTYPE_WEAPON         = { 16 },
    INVTYPE_2HWEAPON       = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND  = { 17 },
    INVTYPE_RANGED         = { 16 },
    INVTYPE_RANGEDRIGHT    = { 16 },
}

local HEADER_COLOR = BATTLENET_FONT_COLOR or CreateColor(0.51, 0.77, 1.0)
local GRAY = GRAY_FONT_COLOR or CreateColor(0.6, 0.6, 0.6)
local GREEN = GREEN_FONT_COLOR or CreateColor(0.1, 1.0, 0.1)
local RED = RED_FONT_COLOR or CreateColor(1.0, 0.1, 0.1)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function Debug(...)
    if ns.IsDebug() then
        ns.Print("[tooltip]", ...)
    end
end

-- Safe check for Midnight's restricted ("secret") values.
local function IsPlainString(value)
    if issecretvalue and issecretvalue(value) then
        return false
    end
    return type(value) == "string"
end

local function GetClassColoredName(entry)
    local color
    if entry.classFile and C_ClassColor and C_ClassColor.GetClassColor then
        color = C_ClassColor.GetClassColor(entry.classFile)
    end
    color = color or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classFile])
    if color then
        return color:WrapTextInColorCode(entry.name)
    end
    return entry.name
end

-- Can this saved character wear an item of this class/subclass/equip loc?
local function CharacterCanEquip(entry, classID, subclassID, equipLoc)
    if classID == WEAPON_CLASS_ID then
        if subclassID == FISHING then
            return true
        end
        local prof = WEAPON_PROFICIENCIES[entry.classFile]
        return prof ~= nil and prof[subclassID] == true
    end

    -- Armor. Rings, necks, trinkets, cloaks, cosmetics: everyone.
    if subclassID == SUBCLASS_GENERIC or subclassID == SUBCLASS_COSMETIC then
        return true
    end
    if equipLoc == "INVTYPE_CLOAK" or equipLoc == "INVTYPE_HOLDABLE" then
        return true
    end
    if subclassID == SUBCLASS_SHIELD then
        return ns.SHIELD_CLASSES[entry.classFile] == true
    end
    if ARMOR_TYPE_SUBCLASSES[subclassID] then
        return entry.armorType == subclassID
    end
    return false
end

-- Returns the equipped ilvl to compare against: the weakest of the
-- candidate slots (nil if nothing is equipped in any of them).
local function GetComparisonIlvl(entry, slots)
    local lowest
    for _, slot in ipairs(slots) do
        local gear = entry.gear and entry.gear[slot]
        local ilvl = gear and gear.ilvl or 0
        if lowest == nil or ilvl < lowest then
            lowest = ilvl
        end
    end
    if lowest == nil or lowest == 0 then
        return nil
    end
    return lowest
end

local function FormatDelta(itemIlvl, equippedIlvl)
    local delta = itemIlvl - equippedIlvl
    if delta > 0 then
        return GREEN:WrapTextInColorCode(string.format("(+%d)", delta))
    elseif delta < 0 then
        return RED:WrapTextInColorCode(string.format("(%d)", delta))
    end
    return GRAY:WrapTextInColorCode("(=)")
end

-- Item link: prefer the hyperlink handed to the post-call, then fall back
-- to TooltipUtil, then the classic GetItem method.
local function GetTooltipItemLink(tooltip, data)
    local link = data and data.hyperlink
    if IsPlainString(link) then
        return link
    end
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        local ok, _, utilLink = pcall(TooltipUtil.GetDisplayedItem, tooltip)
        if ok and IsPlainString(utilLink) then
            return utilLink
        end
    end
    if tooltip.GetItem then
        local ok, _, getLink = pcall(tooltip.GetItem, tooltip)
        if ok and IsPlainString(getLink) then
            return getLink
        end
    end
    return nil
end

-- Reads the bind line off the tooltip: first from the data lines, then from
-- the rendered font strings (the post-call runs after the tooltip is drawn,
-- so anything visible on screen is readable here).
local function ScanBindLines(tooltip, data)
    if data and data.lines then
        local maxLine = math.min(#data.lines, 8)
        for i = 2, maxLine do
            local line = data.lines[i]
            local text = line and line.leftText
            if IsPlainString(text) and LINE_CATEGORY[text] then
                return LINE_CATEGORY[text]
            end
        end
    end

    local tooltipName = tooltip:GetName()
    if tooltipName then
        local maxLine = math.min(tooltip:NumLines() or 0, 8)
        for i = 2, maxLine do
            local fontString = _G[tooltipName .. "TextLeft" .. i]
            local text = fontString and fontString:GetText()
            if IsPlainString(text) and LINE_CATEGORY[text] then
                return LINE_CATEGORY[text]
            end
        end
    end
    return nil
end

-- Returns "warbound", "wue", "boe", or nil for anything that can't move
-- between characters (soulbound, BoP, non-binding).
local function ClassifyBind(bindType, tooltip, data)
    local lineCategory = ScanBindLines(tooltip, data)
    if lineCategory == "soulbound" then
        -- e.g. a BoE you've already equipped: bindType still says 2, but
        -- it's not going anywhere.
        return nil
    end
    if lineCategory then
        return lineCategory
    end
    return BINDTYPE_CATEGORY[bindType]
end

-- ---------------------------------------------------------------------------
-- Tooltip processing
-- ---------------------------------------------------------------------------

local function ProcessItemTooltip(tooltip, data)
    if not ns.db then return end

    local link = GetTooltipItemLink(tooltip, data)
    if not link then
        Debug("no usable item link on this tooltip")
        return
    end

    local _, _, _, _, itemMinLevel, _, _, _, itemEquipLoc, _, _,
        classID, subclassID, bindType = C_Item.GetItemInfo(link)

    if classID ~= ARMOR_CLASS_ID and classID ~= WEAPON_CLASS_ID then
        Debug("not armor or a weapon (classID=" .. tostring(classID) .. ")")
        return
    end
    local bindCategory = ClassifyBind(bindType, tooltip, data)
    if not bindCategory then
        Debug("no shareable bind (bindType=" .. tostring(bindType) .. ")")
        return
    end
    local filters = ns.db.bindFilters
    if filters and filters[bindCategory] == false then
        Debug("bind category '" .. bindCategory .. "' is disabled in options")
        return
    end

    local slots = EQUIPLOC_TO_SLOTS[itemEquipLoc]
    if not slots then
        Debug("unhandled equip location: " .. tostring(itemEquipLoc))
        return
    end

    local itemIlvl = C_Item.GetDetailedItemLevelInfo(link)
    if not itemIlvl then
        Debug("no item level available yet for " .. link)
        return
    end

    -- Build the list of eligible, enabled characters.
    local lines = {}
    for _, entry in ipairs(ns.GetSortedCharacters()) do
        if entry.enabled and CharacterCanEquip(entry, classID, subclassID, itemEquipLoc) then
            local left = string.format("%s %s",
                GetClassColoredName(entry),
                GRAY:WrapTextInColorCode(string.format("(%d)", entry.level or 0)))

            local right
            local equippedIlvl = GetComparisonIlvl(entry, slots)
            if equippedIlvl then
                right = string.format("%d -> %d %s",
                    equippedIlvl, itemIlvl, FormatDelta(itemIlvl, equippedIlvl))
            else
                right = string.format("%s %s",
                    GRAY:WrapTextInColorCode(L["Nothing equipped"]),
                    GREEN:WrapTextInColorCode(string.format("(+%d)", itemIlvl)))
            end

            if itemMinLevel and entry.level and itemMinLevel > entry.level then
                right = right .. "  " .. RED:WrapTextInColorCode(
                    string.format(L["Requires level %d"], itemMinLevel))
            end

            lines[#lines + 1] = { left = left, right = right }
        end
    end

    if #lines == 0 then
        Debug("no enabled characters can equip this item")
        return
    end

    tooltip:AddLine(" ")
    tooltip:AddLine(HEADER_COLOR:WrapTextInColorCode(L["Warband Comparison"]))
    for _, line in ipairs(lines) do
        tooltip:AddDoubleLine(line.left, line.right)
    end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local ok, err = pcall(ProcessItemTooltip, tooltip, data)
    if not ok and ns.IsDebug() then
        ns.Print("[tooltip error]", tostring(err))
    end
end)
