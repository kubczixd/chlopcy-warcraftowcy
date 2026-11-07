-- Symulacja addonu Ekipa poza gra (lua5.1): atrapy API WoW, kilka zdarzen, zapis SavedVariables
-- w formacie gry. Uzycie: lua5.1 tools/test/sim.lua addon/Ekipa out/Ekipa.lua
local dir, out = arg[1] or "addon/Ekipa", arg[2] or "Ekipa.lua"

-- atrapy ----------------------------------------------------------------------
local clock, gtime = 1762300000, 1000
local frames, timers = {}, {}
local S = { lvl = 5, xp = 100, xpmax = 1000, money = 500, taxi = false }

function GetServerTime() return clock end
function time() return clock end
function GetTime() return gtime end
function date(f, t) return os.date(f, t) end
function GetBuildInfo() return "1.16.1", "1", "Nov 2026", 16001 end
function GetAddOnMetadata() return "1.0.0" end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("[czat] " .. m:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end }
function CreateFrame()
  local f = { ev = {} }
  function f:RegisterEvent(e) self.ev[e] = true end
  function f:SetScript(_, fn) self.fn = fn end
  table.insert(frames, f)
  return f
end
local function fire(e, ...)
  for _, f in ipairs(frames) do if f.ev[e] and f.fn then f.fn(f, e, ...) end end
end
C_Timer = { After = function(s, fn) table.insert(timers, { at = gtime + s, fn = fn }) end }
local function advance(sec)
  gtime = gtime + sec; clock = clock + sec
  local i = 1
  while i <= #timers do
    if timers[i].at <= gtime then local t = table.remove(timers, i); t.fn() else i = i + 1 end
  end
end
function hooksecurefunc(a, b, c)
  if type(a) == "string" then local orig = _G[a]; _G[a] = function(...) b(...); if orig then return orig(...) end end
  else local orig = a[b]; a[b] = function(...) c(...); return orig(...) end end
end
function ReloadUI() end
function UnitGUID(u) if u == "player" then return "Player-1234-0ABCDEF" end return nil end
function UnitName(u) if u == "player" then return "Kubus" end return "Mob" end
function GetRealmName() return "Forever" end
function UnitRace() return "Human", "Human" end
function UnitClass() return "Paladin", "PALADIN" end
function UnitFactionGroup() return "Alliance" end
function UnitSex() return 2 end
function UnitPVPName() return "Kubus Paleta" end
function GetGuildInfo() return "Chlopcy", "Member" end
function GetCurrentRegion() return 3 end
function BNGetInfo() return 1, "ajmkuba#2718" end
function UnitLevel() return S.lvl end
function UnitXP() return S.xp end
function UnitXPMax() return S.xpmax end
function GetXPExhaustion() return 300 end
function GetMoney() return S.money end
function GetZoneText() return "Elwynn Forest" end
function IsInInstance() return false, "none" end
function IsInGroup() return false end
function GetNumGroupMembers() return 0 end
function UnitOnTaxi() return S.taxi end
function InCombatLockdown() return false end
function GetInventoryItemDurability() return 50, 100 end
function RequestTimePlayed() C_Timer.After(0.5, function() fire("TIME_PLAYED_MSG", 3600 + gtime - 1000, 600) end) end
NUM_CHAT_WINDOWS = 1
ChatFrame1 = { r = true, IsEventRegistered = function(s) return s.r end, UnregisterEvent = function(s) s.r = false end, RegisterEvent = function(s) s.r = true end }
COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
LOOT_ITEM_SELF = "You receive loot: %s."
GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT = "%d Gold", "%d Silver", "%d Copper"
C_DeathRecap = { GetRecapEvents = function() return { { sourceName = "Hogger", spellName = "Bash", amount = 42, sourceGUID = "Creature-0-1-0-1-448-0000AA" } } end }
SlashCmdList = {}
unpack = unpack or table.unpack
wipe = function(t) for k in pairs(t) do t[k] = nil end end

-- wczytanie addonu -----------------------------------------------------------
local ns = {}
for _, f in ipairs({ "Json.lua", "Core.lua", "Track.lua" }) do
  local chunk = assert(loadfile(dir .. "/" .. f))
  chunk("Ekipa", ns)
end

-- scenariusz -------------------------------------------------------------------
fire("ADDON_LOADED", "Ekipa")
fire("PLAYER_ENTERING_WORLD", true, false)
advance(1)
-- zabojstwo z PARTY_KILL + exp z czatu
fire("PLAYER_TARGET_CHANGED") -- (atrapa: cel bez GUID)
fire("PARTY_KILL", "Player-1234-0ABCDEF", "Creature-0-1-0-1-299-0000BB")
fire("CHAT_MSG_COMBAT_XP_GAIN", "Young Wolf dies, you gain 45 experience.")
S.xp = 145; fire("PLAYER_XP_UPDATE", "player")
advance(2)
-- zabojstwo tylko z czatu (instancja)
fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold \"Vermin\" dies, you gain 30 experience.")
advance(2)
-- quest
fire("QUEST_TURNED_IN", 7, 250, 1500)
S.xp = 395; fire("PLAYER_XP_UPDATE", "player")
S.money = 2000; fire("PLAYER_MONEY")
fire("CHAT_MSG_LOOT", "You receive loot: |cff0070dd|Hitem:1234::::::::5:::::::|h[Niebieski Miecz]|h|r.", "Kubus")
fire("CHAT_MSG_MONEY", "You loot 1 Silver 5 Copper")
-- awans
S.lvl = 6; S.xp = 20; fire("PLAYER_XP_UPDATE", "player"); fire("PLAYER_LEVEL_UP", 6)
advance(3)
-- smierc
fire("PLAYER_DEAD")
advance(2)
-- lot -> przypomnienie (po 10 min)
advance(700)
S.taxi = true; fire("PLAYER_CONTROL_LOST"); advance(2)
SlashCmdList.EKIPA("")
-- reload
ReloadUI(); fire("PLAYER_LOGOUT")

-- zapis w formacie gry -------------------------------------------------------
local function q(s) return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r") .. '"' end
local function ser(v, ind, buf)
  local t = type(v)
  if t == "string" then buf[#buf + 1] = q(v)
  elseif t == "number" or t == "boolean" then buf[#buf + 1] = tostring(v)
  elseif t == "table" then
    buf[#buf + 1] = "{\n"
    local n = #v
    for k, x in pairs(v) do
      if not (type(k) == "number" and k >= 1 and k <= n) then
        buf[#buf + 1] = ind .. "\t[" .. (type(k) == "string" and q(k) or tostring(k)) .. "] = "
        ser(x, ind .. "\t", buf); buf[#buf + 1] = ",\n"
      end
    end
    for i = 1, n do buf[#buf + 1] = ind .. "\t"; ser(v[i], ind .. "\t", buf); buf[#buf + 1] = ", -- [" .. i .. "]\n" end
    buf[#buf + 1] = ind .. "}"
  else buf[#buf + 1] = "nil" end
end
local buf = {}
for _, name in ipairs({ "EkipaDB", "EkipaLog" }) do
  buf[#buf + 1] = "\n" .. name .. " = "
  ser(_G[name], "", buf)
  buf[#buf + 1] = "\n"
end
local f = assert(io.open(out, "wb")); f:write(table.concat(buf)); f:close()
print(("zapisano %d zdarzen do %s"):format(#EkipaLog, out))
for _, l in ipairs(EkipaLog) do print(l) end
