-- Ekipa Challenge - rdzen: baza, sesje, dziennik zdarzen, zdarzenia gry, komendy, przypomnienie o zapisie.
--
-- Dane trafiaja do dwoch zmiennych zapisywanych przez gre (WTF\Account\<KONTO>\SavedVariables\Ekipa.lua):
--   EkipaDB  - stan: id konta, licznik zdarzen, liczniki postaci (moby, smierci, zloto...)
--   EkipaLog - lista zdarzen; kazde to gotowy tekst JSON zaczynajacy sie od {"n":<numer>,...}
-- Gra zapisuje plik tylko przy /reload, wylogowaniu i wyjsciu z gry. Uploader (program na komputerze)
-- czyta plik po kazdym zapisie i wysyla na challenge.kubczi.pl zdarzenia o numerach wiekszych niz
-- ostatni, ktory strona juz ma. Teksty w grze bez polskich znakow (czcionki WoW moga ich nie miec).

local ADDON, ns = ...
ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version") or "?"

local MAX_LOG = 30000      -- najwiecej zdarzen w pliku (starsze i tak sa juz na stronie)
local RESUME_GAP = 600     -- po /reload ta sama sesja, jesli ostatnie zdarzenie bylo < 10 min temu

do
  local ok, _, _, _, iface = pcall(GetBuildInfo)
  iface = (ok and tonumber(iface)) or 0
  ns.IFACE = iface
  ns.isForever = iface > 16000 and iface < 20000
  ns.isClassic = (CombatLogGetCurrentEventInfo ~= nil) and not ns.isForever and iface < 100000
  ns.GRA = ns.isForever and "forever" or (iface >= 100000 and "retail" or "classic")
end

local TAG = "|cfff8b700Ekipa|r "
function ns.msg(text) DEFAULT_CHAT_FRAME:AddMessage(TAG .. text) end
ns.now = GetServerTime
ns.state = {}

local DB, CH

-------------------------------------------------------------------------------
-- Pomocnicze
-------------------------------------------------------------------------------
function ns.Money(c)
  c = math.floor(tonumber(c) or 0)
  local g, s, m = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
  if g > 0 then return string.format("%dg %ds %dm", g, s, m) end
  if s > 0 then return string.format("%ds %dm", s, m) end
  return m .. "m"
end

function ns.Dur(sec)
  sec = math.max(0, math.floor(tonumber(sec) or 0))
  local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
  if h > 0 then return string.format("%d h %02d min", h, m) end
  return string.format("%d min", m)
end

-- format z GlobalStrings (np. "%s dies, you gain %d experience.") -> wzorzec Lua
function ns.FmtToPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%%%%d%%%$s", "(.+)"):gsub("%%%%%d%%%$d", "(%%d+)")
  p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
  return "^" .. p .. "$"
end

function ns.Short(name)
  if not name or ns.Hidden(name) then return nil end
  return (name:gsub("%-.*$", ""))
end

function ns.Zone()
  local z = ns.Safe(GetZoneText())
  local _, inst = IsInInstance()
  return z, inst ~= "none" and inst or nil
end

-- ID moba z GUID ("Creature-0-4372-0-11-1234-0000ABCD" -> 1234)
function ns.NpcID(guid)
  if ns.Hidden(guid) or type(guid) ~= "string" then return nil end
  local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
  return nil
end

function ns.IsPlayerGUID(guid)
  return not ns.Hidden(guid) and type(guid) == "string" and guid:sub(1, 7) == "Player-"
end

-------------------------------------------------------------------------------
-- Baza
-------------------------------------------------------------------------------
local function newId()
  local t = {}
  for i = 1, 4 do t[i] = string.format("%04x", math.random(0, 65535)) end
  return string.format("%x", time()) .. table.concat(t)
end

local function initDB()
  if type(EkipaDB) ~= "table" then EkipaDB = {} end
  if type(EkipaLog) ~= "table" then EkipaLog = {} end
  DB = EkipaDB
  DB.meta = DB.meta or {}
  DB.meta.konto = DB.meta.konto or newId()
  DB.meta.n = DB.meta.n or 0
  DB.meta.wersja = ns.VERSION
  DB.meta.gra = ns.GRA
  DB.postacie = DB.postacie or {}
  -- przyciecie starego dziennika (strona ma juz te zdarzenia)
  if #EkipaLog > MAX_LOG + 1000 then
    local keep, from = {}, #EkipaLog - MAX_LOG + 1
    for i = from, #EkipaLog do keep[#keep + 1] = EkipaLog[i] end
    EkipaLog = keep
  end
  ns.DB = DB
end

local function charKey()
  local guid = UnitGUID("player")
  if guid and not ns.Hidden(guid) then return guid end
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local STAT_KEYS = { "moby", "moby_moje", "smierci", "questy", "exp", "exp_moby", "exp_questy", "exp_inne",
  "zloto_plus", "zloto_minus", "zloto_loot", "zloto_questy", "pvp_zab", "pvp_smierci", "bossy", "awanse",
  "loot0", "loot1", "loot2", "loot3", "loot4", "loot5", "naprawy", "afk_sek",
  "aukcje_zysk", "aukcje_sprzedane", "aukcje_wydane", "aukcje_kupione" }

local function zeroStats()
  local t = {}
  for _, k in ipairs(STAT_KEYS) do t[k] = 0 end
  return t
end

local function initChar()
  local k = charKey()
  DB.postacie[k] = DB.postacie[k] or {}
  CH = DB.postacie[k]
  CH.staty = CH.staty or zeroStats()
  for _, s in ipairs(STAT_KEYS) do CH.staty[s] = CH.staty[s] or 0 end
  CH.questy = CH.questy or {}
  ns.CH = CH
end

-- licznik: calosc postaci + biezaca sesja
function ns.Add(key, v)
  if not CH then return end
  v = tonumber(v) or 1
  CH.staty[key] = (CH.staty[key] or 0) + v
  local ss = CH.sesja and CH.sesja.staty
  if ss then ss[key] = (ss[key] or 0) + v end
end

-------------------------------------------------------------------------------
-- Dziennik
-------------------------------------------------------------------------------
local function enc(s) return ns.Json(s) end

-- e = kod zdarzenia, d = dane (tabela), t = czas (domyslnie teraz)
function ns.Log(e, d, t)
  if not DB or not CH or not CH.sesja then return end
  DB.meta.n = DB.meta.n + 1
  t = t or ns.now()
  if ns.AttachPos then pcall(ns.AttachPos, e, d) end -- miejsce na mapie (Map.lua)
  local line = '{"n":' .. DB.meta.n .. ',"t":' .. t .. ',"s":' .. CH.sesja.s .. ',"c":' .. enc(CH.klucz or "?")
    .. ',"e":' .. enc(e) .. ',"d":' .. ns.Json(d or {}) .. '}'
  EkipaLog[#EkipaLog + 1] = line
  CH.sesja.ostatnie = t
  ns.state.unsaved = (ns.state.unsaved or 0) + 1
  if DB.meta.debug then ns.msg("|cff888888" .. e .. "|r " .. ns.Json(d or {})) end
end

-------------------------------------------------------------------------------
-- Zdarzenia gry (bezpiecznik: obsluga, ktora 5 razy zglosi blad, wylacza sie)
-------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers, failures = {}, {}
function ns.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    pcall(frame.RegisterEvent, frame, event) -- zdarzenie moze nie istniec w danej wersji gry
  end
  table.insert(handlers[event], fn)
end
frame:SetScript("OnEvent", function(_, event, ...)
  for i, fn in ipairs(handlers[event] or {}) do
    local key = event .. "#" .. i
    if (failures[key] or 0) < 5 then
      local ok, err = pcall(fn, ...)
      if not ok then
        failures[key] = (failures[key] or 0) + 1
        if DB and DB.meta.debug then ns.msg("blad (" .. event .. "): " .. tostring(err)) end
      end
    end
  end
end)

local hooks = {}
function ns.Hook(kind, fn) hooks[kind] = hooks[kind] or {}; table.insert(hooks[kind], fn) end
function ns.Fire(kind, ...)
  for _, fn in ipairs(hooks[kind] or {}) do pcall(fn, ...) end
end

-------------------------------------------------------------------------------
-- Stan postaci (wysylany przy kazdym zapisie)
-------------------------------------------------------------------------------
local REGIONS = { [1] = "us", [2] = "kr", [3] = "eu", [4] = "tw", [5] = "cn" }

function ns.Played()
  if not CH or not CH.played then return nil, nil end
  local extra = math.floor(GetTime() - (ns.state.playedGT or GetTime()))
  return CH.played + extra, (CH.played_lvl or 0) + extra
end

local function snapshot(powod)
  local name = ns.Safe(UnitName("player"))
  local race = ns.Safe(UnitRace("player"))
  local _, cls = UnitClass("player")
  local guild, guildRank = GetGuildInfo("player")
  local region = GetCurrentRegion and REGIONS[GetCurrentRegion()] or nil
  local bnet
  if BNGetInfo then
    local ok, _, tag = pcall(BNGetInfo)
    if ok then bnet = ns.Safe(tag) end
  end
  local hk
  if GetPVPLifetimeStats then
    local ok, h = pcall(GetPVPLifetimeStats)
    if ok then hk = ns.Safe(h) end
  end
  local hc
  if C_GameRules and C_GameRules.IsHardcoreActive then
    local ok, v = pcall(C_GameRules.IsHardcoreActive)
    if ok then hc = ns.Safe(v) end
  end
  local money = GetMoney()
  if (not money or money == 0) and ns.state.money then money = ns.state.money end
  local ilvl, points
  if GetAverageItemLevel then
    local ok, overall, equipped = pcall(GetAverageItemLevel)
    if ok then ilvl = ns.Safe(equipped) or ns.Safe(overall) end
  end
  if GetTotalAchievementPoints then
    local ok, p = pcall(GetTotalAchievementPoints)
    if ok then points = ns.Safe(p) end
  end
  local played, playedLvl = ns.Played()
  local zone, inst = ns.Zone()
  -- przy wylogowaniu gra zwraca exp 0/0 - wtedy ostatni znany stan
  local xp, xpMax = UnitXP("player"), UnitXPMax("player")
  if (not xpMax or xpMax == 0) and ns.state.xpMax then xp, xpMax = ns.state.xp, ns.state.xpMax end
  return {
    powod = powod,
    imie = name, realm = ns.Safe(GetRealmName()), pvp_name = ns.Safe(UnitPVPName and UnitPVPName("player")),
    klasa = ns.Safe(cls), rasa = race, frakcja = ns.Safe(UnitFactionGroup("player")),
    plec = ns.Safe(UnitSex("player")), region = region, bnet = bnet, hardcore = hc,
    gildia = ns.Safe(guild), gildia_ranga = ns.Safe(guildRank),
    lvl = ns.state.lvl or UnitLevel("player"), xp = xp, xp_max = xpMax,
    rested = GetXPExhaustion() or ns.state.rested or 0, zloto = money,
    played = played, played_lvl = playedLvl, hk = hk, ilvl = ilvl and math.floor(ilvl + 0.5) or nil, punkty = points, strefa = zone, instancja = inst,
    gra = ns.GRA, wersja = ns.VERSION,
    staty = CH.staty, sesja = CH.sesja and CH.sesja.staty or nil,
    sesja_sek = CH.sesja and (ns.now() - CH.sesja.s) or nil,
    wszech = ns.LifetimeStats and ns.LifetimeStats() or nil,
  }
end
ns.Snapshot = snapshot

-------------------------------------------------------------------------------
-- Sesje
-------------------------------------------------------------------------------
local function startSession()
  CH.sesja = { s = ns.now(), staty = zeroStats(), ostatnie = ns.now(), reloady = 0 }
end

ns.On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  initDB()
end)

ns.On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
  ns.state.myGUID = UnitGUID("player")
  ns.state.petGUID = UnitGUID("pet")
  if ns.state.ready then ns.Fire("loading"); return end -- ekran ladowania w trakcie gry
  if not DB then initDB() end
  initChar()
  CH.klucz = charKey()
  CH.imie = ns.Safe(UnitName("player"))
  local resumed = isReload and CH.sesja and (ns.now() - (CH.sesja.ostatnie or 0)) < RESUME_GAP
  if resumed then
    CH.sesja.reloady = (CH.sesja.reloady or 0) + 1
  else
    startSession()
  end
  ns.state.ready = true
  ns.state.unsaved = 0
  ns.state.loadTime = ns.now()
  ns.state.lvl = UnitLevel("player")
  ns.state.money = GetMoney()
  ns.Fire("start", resumed)
  if not resumed then
    local zone, inst = ns.Zone()
    local _, cls = UnitClass("player")
    ns.Log("LOGIN", { lvl = UnitLevel("player"), strefa = zone, instancja = inst, imie = CH.imie, realm = ns.Safe(GetRealmName()),
      klasa = ns.Safe(cls), rasa = ns.Safe(UnitRace("player")), frakcja = ns.Safe(UnitFactionGroup("player")),
      region = GetCurrentRegion and REGIONS[GetCurrentRegion()] or nil, zloto = GetMoney() })
  end
  ns.RequestPlayed()
  ns.msg(string.format("v%s wczytany%s. Dane zbieraja sie same - wpisz /ekipa, zeby zobaczyc stan.",
    ns.VERSION, resumed and " (po /reload)" or ""))
end)

ns.state.reloading = false
hooksecurefunc("ReloadUI", function() ns.state.reloading = true end)
if C_UI and C_UI.Reload then pcall(hooksecurefunc, C_UI, "Reload", function() ns.state.reloading = true end) end

ns.On("PLAYER_LOGOUT", function()
  if not CH or not CH.sesja then return end
  ns.Fire("logout")
  if ns.state.afkSince then ns.Add("afk_sek", ns.now() - ns.state.afkSince); ns.state.afkSince = ns.now() end
  local reload = ns.state.reloading
  if not reload then
    local zone, inst = ns.Zone()
    ns.Log("LOGOUT", { lvl = ns.state.lvl or UnitLevel("player"), strefa = zone, instancja = inst, sek = ns.now() - CH.sesja.s })
  end
  ns.Log("STAN", snapshot(reload and "reload" or "wylogowanie"))
  DB.meta.ostatni_zapis = ns.now()
  if not reload then CH.sesja = nil end
end)

-------------------------------------------------------------------------------
-- /played bez wypisywania na czat
-------------------------------------------------------------------------------
local playedCallbacks = {}
local function restoreChat()
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local cf = _G["ChatFrame" .. i]
    if cf and cf.ekipaPlayed then cf:RegisterEvent("TIME_PLAYED_MSG"); cf.ekipaPlayed = nil end
  end
end
function ns.RequestPlayed(cb)
  if cb then table.insert(playedCallbacks, cb) end
  if ns.state.playedPending then return end
  ns.state.playedPending = true
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local cf = _G["ChatFrame" .. i]
    if cf and cf:IsEventRegistered("TIME_PLAYED_MSG") then cf:UnregisterEvent("TIME_PLAYED_MSG"); cf.ekipaPlayed = true end
  end
  RequestTimePlayed()
  C_Timer.After(10, function()
    restoreChat()
    if ns.state.playedPending then
      ns.state.playedPending = false
      local cbs = playedCallbacks; playedCallbacks = {}
      for _, f in ipairs(cbs) do pcall(f, nil) end
    end
  end)
end
ns.On("TIME_PLAYED_MSG", function(total, levelTime)
  restoreChat()
  ns.state.playedPending = false
  total, levelTime = ns.Safe(total), ns.Safe(levelTime)
  if CH and total then
    CH.played, CH.played_lvl = total, levelTime
    ns.state.playedGT = GetTime()
  end
  local cbs = playedCallbacks; playedCallbacks = {}
  for _, f in ipairs(cbs) do pcall(f, total) end
end)

-------------------------------------------------------------------------------
-- Przypomnienie o zapisie: podczas lotu taksowka / zmiany kontynentu, najwyzej co 15 min
-------------------------------------------------------------------------------
function ns.SinceSave()
  return ns.now() - math.max(DB.meta.ostatni_zapis or 0, ns.state.loadTime or 0)
end

function ns.Remind(where)
  if not DB or (ns.state.unsaved or 0) == 0 then return end
  if DB.meta.bez_przypomnien then return end
  if ns.SinceSave() < 600 then return end
  if ns.state.lastRemind and ns.now() - ns.state.lastRemind < 900 then return end
  if InCombatLockdown() then return end
  ns.state.lastRemind = ns.now()
  ns.msg(string.format("%s - dobry moment na |cffffd100/reload|r: od %s nic nie jest zapisane (%d zdarzen). Crash gry = utrata tych danych.",
    where, ns.Dur(ns.SinceSave()), ns.state.unsaved or 0))
end

-------------------------------------------------------------------------------
-- Komendy
-------------------------------------------------------------------------------
local function status()
  if not CH or not CH.sesja then ns.msg("Brak aktywnej sesji.") return end
  local s, st = CH.sesja, CH.sesja.staty
  ns.msg(string.format("v%s, sesja od %s (%s). Czeka na zapis: %d zdarzen, ostatni zapis %s temu.",
    ns.VERSION, date("%H:%M", s.s), ns.Dur(ns.now() - s.s), ns.state.unsaved or 0, ns.Dur(ns.SinceSave())))
  ns.msg(string.format("Ta sesja: exp %d, moby %d, questy %d, smierci %d, zloto +%s.",
    st.exp or 0, st.moby or 0, st.questy or 0, st.smierci or 0, ns.Money(st.zloto_plus or 0)))
  local a = CH.staty
  ns.msg(string.format("Lacznie (od instalacji): moby %d, questy %d, smierci %d, PvP %d/%d.",
    a.moby or 0, a.questy or 0, a.smierci or 0, a.pvp_zab or 0, a.pvp_smierci or 0))
  ns.msg("Dane wysyla na strone program Ekipa Uploader po kazdym /reload i wyjsciu z gry.")
end

SLASH_EKIPA1 = "/ekipa"
SlashCmdList.EKIPA = function(arg)
  arg = ((arg or ""):match("^%s*(.-)%s*$") or ""):lower()
  if not DB then return end
  if arg == "zapisz" or arg == "reload" then
    ReloadUI()
  elseif arg == "debug" then
    DB.meta.debug = not DB.meta.debug
    ns.msg("Debug: " .. (DB.meta.debug and "wlaczony" or "wylaczony"))
  elseif arg == "cicho" then
    DB.meta.bez_przypomnien = not DB.meta.bez_przypomnien
    ns.msg("Przypomnienia o /reload: " .. (DB.meta.bez_przypomnien and "wylaczone" or "wlaczone"))
  elseif arg == "sonda" then
    ns.Probe()
  elseif arg == "historia" then
    ns.SendHistory("komenda")
  elseif arg == "mapa" or arg:match("^mapa ") then
    if ns.CleanMap then ns.CleanMap(arg:match("^mapa%s+(.+)$")) end
  elseif arg == "pomoc" or arg == "help" then
    ns.msg("/ekipa - stan zbierania danych")
    ns.msg("/ekipa zapisz - zapis danych (/reload)")
    ns.msg("/ekipa cicho - wylacz / wlacz przypomnienia o /reload")
    ns.msg("/ekipa sonda - co gra udostepnia addonom (do sprawdzenia, nic nie zapisuje)")
    ns.msg("/ekipa historia - wyslij jeszcze raz dane wstecz (questy, statystyki, osiagniecia)")
    ns.msg("/ekipa mapa - czysta mapa krainy do zrzutu (kraina otwarta na mapie swiata albo ta, w ktorej jestes); Esc zamyka")
    ns.msg("/ekipa mapa kontynent - to samo dla calego kontynentu")
    ns.msg("/ekipa mapa <nazwa> - wybrana kraina albo kontynent, np. /ekipa mapa duskwood, /ekipa mapa kalimdor")
    ns.msg("/ekipa debug - pokazuj na czacie kazde zapisane zdarzenie")
  else
    status()
  end
end
