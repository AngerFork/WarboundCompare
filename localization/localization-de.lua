-- Locales/deDE.lua
-- Example translation file. Copy this pattern for other locales
-- (frFR, esES, ruRU, zhCN, etc.) and add one file per locale to the TOC.

local ADDON_NAME, ns = ...
if GetLocale() ~= "deDE" then return end

local L = ns.L

L["Warband Comparison"] = "Kriegsmeute-Vergleich"
L["Requires level %d"] = "Benötigt Stufe %d"
L["Nothing equipped"] = "Nichts angelegt"
L["Warbound Compare"] = "Warbound Compare"
L["Choose which characters appear in the Warbound item tooltip comparison."] = "Wähle aus, welche Charaktere im Tooltip-Vergleich für kriegsmeutengebundene Gegenstände erscheinen."
L["Level %d %s %s"] = "Stufe %d %s %s"
L["No characters saved yet. Log in to a character to record it."] = "Noch keine Charaktere gespeichert. Melde dich mit einem Charakter an, um ihn zu erfassen."
L["Remove"] = "Entfernen"
L["Remove %s from saved characters?"] = "%s aus den gespeicherten Charakteren entfernen?"
L["Show comparisons for items that are:"] = "Vergleiche für gekennzeichnete Elemente anzeigen:"
L["Show comparisons for these characters:"] = "Zeige Vergleiche für diese Charaktere an:"
