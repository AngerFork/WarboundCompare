-- Options.lua
-- Settings panel: lists saved characters with class-colored names and lets
-- you toggle each one in or out of the tooltip comparison, or remove it.

local ADDON_NAME, ns = ...
local L = ns.L

local GRAY = GRAY_FONT_COLOR or CreateColor(0.6, 0.6, 0.6)

-- ---------------------------------------------------------------------------
-- Panel scaffolding
-- ---------------------------------------------------------------------------

local panel = CreateFrame("Frame")
panel.name = L["Warbound Compare"]

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText(L["Warbound Compare"])

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetPoint("RIGHT", panel, "RIGHT", -32, 0)
subtitle:SetJustifyH("LEFT")
subtitle:SetText(L["Choose which characters appear in the Warbound item tooltip comparison."])

local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 16)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(1, 1) -- real size is set during refresh / on size change
scrollFrame:SetScrollChild(content)
scrollFrame:SetScript("OnSizeChanged", function(self, width)
    content:SetWidth(width)
end)

local emptyText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableLarge")
emptyText:SetPoint("TOPLEFT", 4, -8)
emptyText:SetText(L["No characters saved yet. Log in to a character to record it."])
emptyText:Hide()

-- ---------------------------------------------------------------------------
-- Bind-category filters
-- ---------------------------------------------------------------------------

local filterLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
filterLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -14)
filterLabel:SetText(L["Show comparisons for items that are:"])

local filterCharLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
filterCharLabel:SetText(L["Show comparisons for these characters:"])

-- Labels come from Blizzard's globals so they're localized for free.
local BIND_FILTERS = {
    { key = "warbound", label = ITEM_BNETACCOUNTBOUND or ITEM_ACCOUNTBOUND or "Warbound" },
    { key = "wue",      label = ITEM_ACCOUNTBOUND_UNTIL_EQUIP or "Warbound until equipped" },
    { key = "boe",      label = ITEM_BIND_ON_EQUIP or "Binds when equipped" },
}

local filterChecks = {}
do
    local anchor = filterLabel
    for index, filter in ipairs(BIND_FILTERS) do
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetSize(26, 26)
        if index == 1 then
            check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        else
            check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0)
        end
        if check.Text then
            check.Text:SetText(filter.label)
        end
        check:SetScript("OnClick", function(self)
            if ns.db and ns.db.bindFilters then
                ns.db.bindFilters[filter.key] = self:GetChecked() and true or false
            end
        end)
        filterChecks[filter.key] = check
        anchor = check
    end
	
	-- Add in the Character Filter Label
	filterCharLabel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
	anchor = filterCharLabel

	-- Set up the scroll box
    local scrollAnchor = anchor
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", scrollAnchor, "BOTTOMLEFT", 0, -12)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 16)
end



StaticPopupDialogs["WARBOUNDCOMPARE_REMOVE"] = {
    text = L["Remove %s from saved characters?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        if ns.db and data and data.key then
            ns.db.characters[data.key] = nil
            panel.Refresh()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ---------------------------------------------------------------------------
-- Row pool
-- ---------------------------------------------------------------------------

local ROW_HEIGHT = 44
local rows = {}

local function AcquireRow(index)
    local row = rows[index]
    if row then
        row:Show()
        return row
    end

    row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("LEFT", content, "LEFT", 0, 0)
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    row:SetPoint("TOP", content, "TOP", 0, -((index - 1) * ROW_HEIGHT))

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(28, 28)
    row.check:SetPoint("LEFT", 4, 0)
    row.check:SetScript("OnClick", function(self)
        if self.entry then
            self.entry.enabled = self:GetChecked() and true or false
        end
    end)

    row.nameText = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.nameText:SetPoint("TOPLEFT", row.check, "TOPRIGHT", 6, -2)
    row.nameText:SetJustifyH("LEFT")

    row.infoText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.infoText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -3)
    row.infoText:SetJustifyH("LEFT")

    row.removeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.removeButton:SetSize(80, 22)
    row.removeButton:SetPoint("RIGHT", -8, 0)
    row.removeButton:SetText(L["Remove"])
    row.removeButton:SetScript("OnClick", function(self)
        if self.entry then
            local dialog = StaticPopup_Show("WARBOUNDCOMPARE_REMOVE", self.entry.name)
            if dialog then
                dialog.data = { key = self.entry.key }
            end
        end
    end)

    rows[index] = row
    return row
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

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------

function panel.Refresh()
    local width = scrollFrame:GetWidth()
    if width and width > 1 then
        content:SetWidth(width)
    end

    local filters = ns.db and ns.db.bindFilters or {}
    for key, check in pairs(filterChecks) do
        check:SetChecked(filters[key] ~= false)
    end

    local characters = ns.GetSortedCharacters()

    for _, row in ipairs(rows) do
        row:Hide()
    end

    if #characters == 0 then
        emptyText:Show()
        content:SetHeight(40)
        return
    end
    emptyText:Hide()

    for index, entry in ipairs(characters) do
        local row = AcquireRow(index)
        row.check.entry = entry
        row.removeButton.entry = entry
        row.check:SetChecked(entry.enabled and true or false)

        local nameText = GetClassColoredName(entry)
        if entry.realm and entry.realm ~= GetRealmName() then
            nameText = nameText .. GRAY:WrapTextInColorCode(" - " .. entry.realm)
        end
        row.nameText:SetText(nameText)

        row.infoText:SetText(GRAY:WrapTextInColorCode(string.format(
            L["Level %d %s %s"],
            entry.level or 0,
            entry.race or "",
            entry.className or "")))
    end

    content:SetHeight(#characters * ROW_HEIGHT)
end

panel:SetScript("OnShow", panel.Refresh)

-- ---------------------------------------------------------------------------
-- Registration and slash command
-- ---------------------------------------------------------------------------

local category = Settings.RegisterCanvasLayoutCategory(panel, L["Warbound Compare"])
Settings.RegisterAddOnCategory(category)
ns.settingsCategory = category

SLASH_WARBOUNDCOMPARE1 = "/wbc"
SLASH_WARBOUNDCOMPARE2 = "/warboundcompare"
SlashCmdList.WARBOUNDCOMPARE = function(msg)
    local command = (msg or ""):match("^%s*(%S*)"):lower()
    if command == "debug" then
        if ns.db then
            ns.db.debug = not ns.db.debug
            ns.Print("Debug output " .. (ns.db.debug and "enabled" or "disabled") .. ".")
        end
    elseif command == "scan" then
        ns.DebugScan()
    else
        Settings.OpenToCategory(category:GetID())
    end
end
