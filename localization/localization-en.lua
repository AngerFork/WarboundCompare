-- Locales/enUS.lua
-- Base locale. The English strings double as the lookup keys, and the
-- metatable falls back to the key itself, so enUS needs no explicit
-- entries. Other locale files simply assign L["English key"] = "translation".

local ADDON_NAME, ns = ...

ns.L = setmetatable({}, {
    __index = function(t, key)
        rawset(t, key, key)
        return key
    end,
})

-- Nothing else is required for enUS. Keys used throughout the addon
-- (listed here as documentation for translators):
--
--   "Warband Comparison"
--   "Requires level %d"
--   "Nothing equipped"
--   "Warbound Compare"
--   "Choose which characters appear in the Warbound item tooltip comparison."
--   "Level %d %s %s"           -- level, race, class
--   "No characters saved yet. Log in to a character to record it."
--   "Remove"
--   "Remove %s from saved characters?"
--   "Show comparisons for:"
