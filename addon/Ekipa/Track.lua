-- Ekipa Challenge - co zbieramy:
--   LVL     awans (z czasem /played w chwili awansu)
--   QUEST   oddany quest (exp, zloto)
--   MOB     zabity mob (nazwa, exp, czy moj cios, czy w grupie)
--   SMIERC  smierc (zabojca, czar, poziom, strefa; Forever - z podsumowania smierci gry)
--   LOOT    przedmiot niebieski lub lepszy (liczniki wszystkich jakosci w STAN)
--   PVP_ZAB / PVP_SMIERC  zabity gracz / smierc od gracza (poza BG i arenami)
--   STREFA  zmiana strefy, BOSS koniec walki z bossem (wynik)
--   AUKCJA  sprzedany przedmiot (pieniadze z poczty) albo wygrana aukcja
--   LOGIN / LOGOUT / STAN (Core.lua)
-- Liczniki (exp wg zrodla, zloto zarobione/wydane, moby, smierci...) sa w EkipaDB i w zdarzeniu STAN.

local ADDON, ns = ...
local Log, Add, now = ns.Log, ns.Add, ns.now

-------------------------------------------------------------------------------
-- Exp i awanse
-------------------------------------------------------------------------------
local last = {}
local lastQuest = { gt = -100, xp = 0 }
local lastMobXp -- { mob, xp, gt }

local function snapXP()
  last.lvl, last.xp, last.max = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
  if last.max and last.max > 0 then ns.state.xp, ns.state.xpMax = last.xp, last.max end
end

ns.On("PLAYER_XP_UPDATE", function(unit)
  if unit and unit ~= "player" then return end
  if not last.lvl then snapXP() return end
  local lvl, xp, max = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
  local gain = 0
  if lvl == last.lvl and xp >= last.xp then
    gain = xp - last.xp
  elseif lvl > last.lvl or xp < last.xp then -- awans (poziom moze jeszcze nie dotrzec)
    gain = ((last.max or last.xp) - last.xp) + xp
    if lvl == last.lvl then lvl, max = lvl + 1, nil end
  end
  last.lvl, last.xp = lvl, xp
  if max then last.max = max end
  if max and max > 0 then ns.state.xp, ns.state.xpMax = xp, max end
  if gain <= 0 then return end
  Add("exp", gain)
  local gt = GetTime()
  if gt - lastQuest.gt < 1.5 and gain == lastQuest.xp then
    Add("exp_questy", gain)
  elseif lastMobXp and gt - lastMobXp.gt < 2 then
    Add("exp_moby", gain)
  else
    Add("exp_inne", gain) -- odkrywanie, kara za mob w grupie itp.
  end
end)

ns.On("PLAYER_LEVEL_UP", function(newLevel)
  local lvl = tonumber(newLevel) or (UnitLevel("player") + 1)
  ns.state.lvl = lvl
  Add("awanse", 1)
  local t = now()
  -- nowy poziom = czas na poziomie od zera (gdyby /reload przyszedl przed odpowiedzia serwera,
  -- STAN mialby czas starego poziomu i strona policzylaby zly czas wejscia na poziom)
  local est = ns.Played()
  if est and ns.CH then ns.CH.played, ns.CH.played_lvl = est, 0; ns.state.playedGT = GetTime() end
  -- /played w chwili awansu: czekamy na odpowiedz serwera (najwyzej 10 s), inaczej szacunek
  ns.RequestPlayed(function(total)
    local zone = ns.Zone()
    Log("LVL", { lvl = lvl, played = total or est, strefa = zone }, t)
  end)
  ns.msg(string.format("Poziom %d zapisany dla ekipy. Gratulacje!", lvl))
end)

-------------------------------------------------------------------------------
-- Questy
-------------------------------------------------------------------------------
local function questTitle(qid)
  if not qid then return nil end
  if C_QuestLog and C_QuestLog.GetTitleForQuestID then
    local ok, t = pcall(C_QuestLog.GetTitleForQuestID, qid)
    if ok and type(t) == "string" and not ns.Hidden(t) then return t end
  end
  if C_QuestLog and C_QuestLog.GetQuestInfo then
    local ok, t = pcall(C_QuestLog.GetQuestInfo, qid)
    if ok and type(t) == "string" and not ns.Hidden(t) then return t end
  end
  return nil
end

ns.On("QUEST_ACCEPTED", function(a, b)
  local qid = tonumber(b) or tonumber(a)
  local title = questTitle(qid)
  if (not title) and b and GetQuestLogTitle then
    local ok, t = pcall(GetQuestLogTitle, tonumber(a))
    if ok and type(t) == "string" then title = t end
  end
  if qid and title and ns.CH then ns.CH.questy[qid] = title end
end)

ns.On("QUEST_TURNED_IN", function(questID, xpReward, moneyReward)
  local qid = tonumber(questID)
  local xp, money = tonumber(xpReward) or 0, tonumber(moneyReward) or 0
  local title = (ns.CH and qid and ns.CH.questy[qid]) or questTitle(qid)
  if ns.CH and qid then ns.CH.questy[qid] = nil end
  lastQuest.gt, lastQuest.xp = GetTime(), xp
  Add("questy", 1)
  if money > 0 then Add("zloto_questy", money) end
  Log("QUEST", { id = qid, nazwa = title, exp = xp, zloto = money, lvl = UnitLevel("player") })
end)

-------------------------------------------------------------------------------
-- Zloto
-------------------------------------------------------------------------------
ns.On("PLAYER_MONEY", function()
  local m = GetMoney()
  if ns.state.money then
    local d = m - ns.state.money
    if d > 0 then Add("zloto_plus", d) elseif d < 0 then Add("zloto_minus", -d) end
  end
  ns.state.money = m
end)

local moneyPats
local function parseMoney(msg)
  if not moneyPats then
    moneyPats = {
      { (GOLD_AMOUNT or "%d Gold"):gsub("%%d", "(%%d+)"), 10000 },
      { (SILVER_AMOUNT or "%d Silver"):gsub("%%d", "(%%d+)"), 100 },
      { (COPPER_AMOUNT or "%d Copper"):gsub("%%d", "(%%d+)"), 1 },
    }
  end
  local total = 0
  for _, p in ipairs(moneyPats) do
    local v = msg:match(p[1])
    if v then total = total + tonumber(v) * p[2] end
  end
  return total
end
ns.On("CHAT_MSG_MONEY", function(msg)
  if type(msg) ~= "string" or ns.Hidden(msg) then return end
  local c = parseMoney(msg)
  if c > 0 then Add("zloto_loot", c) end
end)

-- naprawa: wytrzymalosc wyraznie wzrosla
local function durability()
  local cur, max = 0, 0
  for slot = 1, 18 do
    local c, m = GetInventoryItemDurability(slot)
    if c and m and not ns.Hidden(c) then cur, max = cur + c, max + m end
  end
  if max == 0 then return nil end
  return math.floor(cur / max * 100 + 0.5)
end
local dur
ns.On("UPDATE_INVENTORY_DURABILITY", function()
  local d = durability()
  if d and dur and d >= dur + 5 then Add("naprawy", 1) end
  dur = d
end)

-------------------------------------------------------------------------------
-- Loot
-------------------------------------------------------------------------------
local QUAL = { ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5 }
local selfPats
ns.On("CHAT_MSG_LOOT", function(msg, who)
  if type(msg) ~= "string" or ns.Hidden(msg) then return end
  if not selfPats then
    selfPats = {}
    for _, k in ipairs({ "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF",
      "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_CREATED_SELF_MULTIPLE" }) do
      local p = ns.FmtToPattern(_G[k])
      if p then selfPats[#selfPats + 1] = p end
    end
  end
  local mine = false
  for _, p in ipairs(selfPats) do if msg:match(p) then mine = true break end end
  if not mine and ns.Short(who) ~= UnitName("player") then return end
  local link = msg:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)")
  if not link then return end
  local hex = link:match("|c%x%x(%x%x%x%x%x%x)")
  local q = hex and QUAL[hex:lower()]
  if not q then return end
  local qty = tonumber(msg:match("|rx(%d+)")) or 1
  Add("loot" .. q, qty)
  if q >= 3 then
    local zone = ns.Zone()
    Log("LOOT", { id = tonumber(link:match("item:(%d+)")), nazwa = link:match("%[(.-)%]"), q = q, ile = qty, strefa = zone })
  end
end)

-------------------------------------------------------------------------------
-- Moby: PARTY_KILL (Forever w swiecie) + komunikat o expie ("X dies, you gain N experience")
-------------------------------------------------------------------------------
local seen, nseen = {}, 0 -- [guid] = nazwa (moby widziane w celu / pod myszka / z tabliczka)
local function note(unit)
  local guid = UnitGUID(unit)
  if ns.Hidden(guid) or type(guid) ~= "string" or seen[guid] then return end
  local name = ns.Safe(UnitName(unit))
  if not name then return end
  if nseen > 400 then wipe(seen); nseen = 0 end
  seen[guid] = name
  nseen = nseen + 1
end
ns.On("PLAYER_TARGET_CHANGED", function() note("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() note("mouseover") end)
ns.On("NAME_PLATE_UNIT_ADDED", function(unit) if unit then note(unit) end end)

local pending = {} -- zabite, czekaja chwile na komunikat o expie
local function flush(k)
  if k.done then return end
  k.done = true
  for i, x in ipairs(pending) do if x == k then table.remove(pending, i) break end end
  Add("moby", 1)
  if k.moj then Add("moby_moje", 1) end
  local zone, inst = ns.Zone()
  Log("MOB", { m = k.nazwa, id = k.npc, x = k.exp, moj = k.moj or nil, gr = IsInGroup() or nil, inst = inst, lvl = UnitLevel("player") }, k.t)
end

local function newKill(k)
  k.t, k.gt = now(), GetTime()
  table.insert(pending, k)
  C_Timer.After(1.5, function() flush(k) end)
end

ns.On("PARTY_KILL", function(attackerGUID, targetGUID)
  if ns.Hidden(targetGUID) or not targetGUID then return end -- w instancji: zabicie przyjdzie z komunikatu o expie
  local mine = not ns.Hidden(attackerGUID) and (attackerGUID == ns.state.myGUID or attackerGUID == ns.state.petGUID)
  if ns.IsPlayerGUID(targetGUID) then
    if ns.PvpKill then ns.PvpKill(targetGUID, mine) end
    return
  end
  newKill({ nazwa = seen[targetGUID], npc = ns.NpcID(targetGUID), moj = mine })
  seen[targetGUID] = nil
end)

local xpPats
ns.On("CHAT_MSG_COMBAT_XP_GAIN", function(msg)
  if type(msg) ~= "string" or ns.Hidden(msg) then return end
  if not xpPats then
    xpPats = {}
    for _, k in ipairs({ "COMBATLOG_XPGAIN_FIRSTPERSON", "COMBATLOG_XPGAIN_FIRSTPERSON_GROUP", "COMBATLOG_XPGAIN_FIRSTPERSON_RAID" }) do
      local f = _G[k]
      if type(f) == "string" then
        local p = ns.FmtToPattern((f:gsub("%s*%(.*$", "")))
        if p then xpPats[#xpPats + 1] = (p:gsub("%$$", "")) end
      end
    end
    if #xpPats == 0 then xpPats[1] = "^(.+) dies, you gain (%d+) experience" end
  end
  for _, p in ipairs(xpPats) do
    local mob, xp = msg:match(p)
    if mob and tonumber(xp) then
      xp = tonumber(xp)
      lastMobXp = { mob = mob, xp = xp, gt = GetTime() }
      -- dopisz exp do swiezego zabojstwa (z PARTY_KILL) albo utworz nowe
      local best
      for _, k in ipairs(pending) do
        if not k.exp and (k.nazwa == nil or k.nazwa == mob) and GetTime() - k.gt < 1.5 then best = k break end
      end
      if best then
        best.exp, best.nazwa = xp, best.nazwa or mob
      else
        newKill({ nazwa = mob, exp = xp })
      end
      return
    end
  end
end)

-------------------------------------------------------------------------------
-- PvP: wrogowie widziani (do opisu zabitego / zabojcy), zabojstwa i smierci od graczy
-------------------------------------------------------------------------------
local enemies, nenemies = {}, 0
local function noteEnemy(unit)
  local ok, isPlayer = pcall(UnitIsPlayer, unit)
  if not ok or ns.Hidden(isPlayer) or not isPlayer then return end
  local guid = UnitGUID(unit)
  if not ns.IsPlayerGUID(guid) then return end
  local f = ns.Safe(UnitFactionGroup(unit))
  if not f or f == UnitFactionGroup("player") then return end
  if nenemies > 500 then wipe(enemies); nenemies = 0 end
  if not enemies[guid] then nenemies = nenemies + 1 end
  local _, cls = UnitClass(unit)
  enemies[guid] = {
    nazwa = ns.Safe(UnitName(unit)), lvl = ns.Safe(UnitLevel(unit)), klasa = ns.Safe(cls),
    rasa = ns.Safe(UnitRace(unit)), gildia = ns.Safe(GetGuildInfo(unit)),
  }
end
ns.On("PLAYER_TARGET_CHANGED", function() noteEnemy("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() noteEnemy("mouseover") end)
ns.On("NAME_PLATE_UNIT_ADDED", function(unit) if unit then noteEnemy(unit) end end)

local function inBattle()
  local inInst, t = IsInInstance()
  return inInst and (t == "pvp" or t == "arena") or false
end

local function enemyInfo(guid, fallbackName)
  local d = {}
  local e = guid and enemies[guid]
  if e then
    for k, v in pairs(e) do d[k] = v end
  elseif guid and GetPlayerInfoByGUID then
    local ok, _, cls, _, race, _, name = pcall(GetPlayerInfoByGUID, guid)
    if ok then d.nazwa, d.klasa, d.rasa = ns.Safe(name), ns.Safe(cls), ns.Safe(race) end
  end
  if not d.nazwa and fallbackName and not ns.Hidden(fallbackName) then d.nazwa = fallbackName end
  return d
end

local recentPvp = {}
function ns.PvpKill(guid, mine)
  if inBattle() then return end
  if recentPvp[guid] and GetTime() - recentPvp[guid] < 10 then return end
  recentPvp[guid] = GetTime()
  local d = enemyInfo(guid)
  d.moj = mine or nil
  d.strefa = ns.Zone()
  d.moj_lvl = UnitLevel("player")
  Add("pvp_zab", 1)
  Log("PVP_ZAB", d)
end

-------------------------------------------------------------------------------
-- Smierc
-------------------------------------------------------------------------------
-- Classic: ostatnie trafienia z combat logu (w Forever combat log jest zablokowany)
local hits = {}
if ns.isClassic then
  ns.On("COMBAT_LOG_EVENT_UNFILTERED", function()
    local _, sub, _, srcGUID, srcName, _, _, dstGUID = CombatLogGetCurrentEventInfo()
    if dstGUID ~= ns.state.myGUID then return end
    local spell, amount
    if sub == "SWING_DAMAGE" then
      amount = select(12, CombatLogGetCurrentEventInfo())
      spell = "Atak"
    elseif sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" or sub == "RANGE_DAMAGE" then
      local _, name, _, amt = select(12, CombatLogGetCurrentEventInfo())
      spell, amount = name, amt
    elseif sub == "ENVIRONMENTAL_DAMAGE" then
      local envType, amt = select(12, CombatLogGetCurrentEventInfo())
      srcName, spell, amount = "Otoczenie", envType, amt
    else
      return
    end
    hits[#hits + 1] = { gt = GetTime(), kto = srcName, guid = srcGUID, czar = spell, ile = amount }
    if #hits > 20 then table.remove(hits, 1) end
  end)
end

local function killerClassic()
  for i = #hits, 1, -1 do
    local h = hits[i]
    if GetTime() - h.gt <= 10 then return h.kto, h.czar, h.ile, h.guid end
  end
end

local function killerRecap()
  if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return end
  local ok, ev = pcall(C_DeathRecap.GetRecapEvents)
  if not ok or type(ev) ~= "table" or ns.Hidden(ev) then return end
  local k = ev[1]
  if not k then return end
  local who = ns.Safe(k.sourceName) or (ns.Safe(k.environmentalType) and "Otoczenie")
  return who, ns.Safe(k.spellName) or ns.Safe(k.environmentalType), ns.Safe(k.amount), ns.Safe(k.sourceGUID)
end

ns.On("PLAYER_DEAD", function()
  if UnitIsFeignDeath and UnitIsFeignDeath("player") then return end
  local t = now()
  local lvl = UnitLevel("player")
  local zone, inst = ns.Zone()
  local function write()
    local who, spell, amount, guid
    if ns.isClassic then who, spell, amount, guid = killerClassic() else who, spell, amount, guid = killerRecap() end
    local pvp = ns.IsPlayerGUID(guid)
    local d = { lvl = lvl, strefa = zone, instancja = inst, zabojca = who or "nieznany", czar = spell, obrazenia = amount,
      zabojca_id = ns.NpcID(guid), pvp = pvp or nil, grupa = IsInGroup() and GetNumGroupMembers() or nil }
    Add("smierci", 1)
    Log("SMIERC", d, t)
    if pvp and not inBattle() then
      local e = enemyInfo(guid, who)
      e.czar, e.strefa, e.moj_lvl = spell, zone, lvl
      Add("pvp_smierci", 1)
      Log("PVP_SMIERC", e, t)
    end
    hits = {}
    ns.msg(string.format("Smierc zapisana: %s%s. Ekipa sie dowie...", tostring(who or "nieznany"), spell and (" (" .. spell .. ")") or ""))
  end
  if ns.isClassic then write() else C_Timer.After(1, write) end -- podsumowanie smierci gra uzupelnia chwile po
end)

-------------------------------------------------------------------------------
-- Strefy, loty (przypomnienie o zapisie), bossy
-------------------------------------------------------------------------------
local lastZone
ns.On("ZONE_CHANGED_NEW_AREA", function()
  local zone, inst = ns.Zone()
  if not zone or zone == "" or zone == lastZone then return end
  lastZone = zone
  Log("STREFA", { strefa = zone, instancja = inst, lvl = UnitLevel("player") })
end)

ns.On("PLAYER_CONTROL_LOST", function()
  C_Timer.After(1, function()
    if UnitOnTaxi and UnitOnTaxi("player") then ns.Remind("Lecisz") end
  end)
end)
ns.Hook("loading", function() C_Timer.After(5, function() ns.Remind("Po ekranie ladowania") end) end)

ns.On("ENCOUNTER_END", function(id, name, difficulty, size, success)
  local ok = success == 1 or success == true
  if ok then Add("bossy", 1) end
  local zone = ns.Zone()
  Log("BOSS", { id = id, nazwa = ns.Safe(name), trudnosc = difficulty, osob = size, wynik = ok, strefa = zone })
end)

-------------------------------------------------------------------------------
-- Start i koniec
-------------------------------------------------------------------------------
ns.Hook("start", function()
  snapXP()
  lastZone = ns.Zone()
  dur = durability()
  ns.state.rested = GetXPExhaustion() or 0
end)
-- AFK: czas liczony do licznika sesji (strona pokazuje czas sesji i ile z tego AFK)
ns.On("PLAYER_FLAGS_CHANGED", function(unit)
  if unit and unit ~= "player" then return end
  local afk = UnitIsAFK("player")
  if afk and not ns.state.afkSince then
    ns.state.afkSince = now()
  elseif not afk and ns.state.afkSince then
    Add("afk_sek", now() - ns.state.afkSince)
    ns.state.afkSince = nil
  end
end)

ns.On("UPDATE_EXHAUSTION", function() ns.state.rested = GetXPExhaustion() or 0 end)
ns.Hook("logout", function()
  for _, k in ipairs({ unpack(pending) }) do flush(k) end -- zabojstwa czekajace na komunikat o expie
end)

-------------------------------------------------------------------------------
-- Dom aukcyjny: pieniadze ze sprzedanych aukcji (poczta) i wygrane aukcje
-------------------------------------------------------------------------------
-- Temat listu z formatu gry (np. "Auction successful: %s") -> wzorzec Lua; dziala w kazdym jezyku gry.
local function subjectPattern(fmt)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)"):gsub("%%d", "%%d+")
  return "^" .. p .. "$"
end
local SOLD, WON = subjectPattern(AUCTION_SOLD_MAIL_SUBJECT), subjectPattern(AUCTION_WON_MAIL_SUBJECT)

-- stan listow sprzed klikniecia (dane zmieniaja sie dopiero po odpowiedzi serwera)
local mails = {}
local function scanMail()
  wipe(mails)
  local n = GetInboxNumItems and GetInboxNumItems() or 0
  for i = 1, n do
    local _, _, _, subject, money, _, _, items = GetInboxHeaderInfo(i)
    local inv, item, who, bid
    if GetInboxInvoiceInfo then inv, item, who, bid = GetInboxInvoiceInfo(i) end
    local kind
    if inv == "seller" or (SOLD and type(subject) == "string" and subject:match(SOLD)) then kind = "sprzedaz"
    elseif inv == "buyer" or (WON and type(subject) == "string" and subject:match(WON)) then kind = "zakup" end
    if kind then
      local name = item
      if not name and type(subject) == "string" then name = subject:match(kind == "sprzedaz" and SOLD or WON) end
      mails[i] = { kind = kind, money = money or 0, items = items or 0, name = ns.Safe(name), who = ns.Safe(who), bid = ns.Safe(bid) }
    end
  end
end
ns.On("MAIL_INBOX_UPDATE", scanMail)
ns.On("MAIL_SHOW", scanMail)

local function takeMoney(i)
  local m = mails[i]
  if not m or m.kind ~= "sprzedaz" or m.money <= 0 then return end
  Add("aukcje_zysk", m.money)
  Add("aukcje_sprzedane", 1)
  Log("AUKCJA", { typ = "sprzedaz", nazwa = m.name, kwota = m.money, cena = m.bid, kupiec = m.who })
  m.money = 0
end
local function takeItem(i)
  local m = mails[i]
  if not m or m.kind ~= "zakup" or m.items <= 0 or m.counted then return end
  m.counted = true
  Add("aukcje_kupione", 1)
  if m.bid and m.bid > 0 then Add("aukcje_wydane", m.bid) end
  Log("AUKCJA", { typ = "zakup", nazwa = m.name, kwota = m.bid, sprzedawca = m.who })
end
if TakeInboxMoney then hooksecurefunc("TakeInboxMoney", function(i) pcall(takeMoney, i) end) end
if TakeInboxItem then hooksecurefunc("TakeInboxItem", function(i) pcall(takeItem, i) end) end
if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", function(i) pcall(takeMoney, i); pcall(takeItem, i) end) end
