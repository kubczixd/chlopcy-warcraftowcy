-- Ekipa Challenge - dane wstecz (sprzed instalacji addonu) i sonda.
--   HISTORIA  raz na postac (i na zadanie: /ekipa historia): ukonczone questy, statystyki postaci
--             (okno Statystyki, jesli gra je ma), zdobyte osiagniecia z datami (np. "Level 10" -> data awansu),
--             profesje. Do tego liczniki addonu w tej chwili, zeby strona nie liczyla niczego dwa razy.
--   STAN.wszech  przy kazdym zapisie: najwazniejsze statystyki od poczatku gry (jesli gra je podaje).
--   /ekipa sonda  na czacie: co z tego gra udostepnia (nic nie zapisuje).

local ADDON, ns = ...
local Log = ns.Log

local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local r = { pcall(f, ...) }
  if not r[1] then return nil end
  for i = 2, #r do if ns.Hidden(r[i]) then r[i] = nil end end
  return unpack(r, 2)
end

-- ukonczone questy (od poczatku gry)
function ns.CompletedQuests()
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    local ids = try(C_QuestLog.GetAllCompletedQuestIDs)
    if type(ids) == "table" then return #ids end
  end
  if GetQuestsCompleted then
    local t = try(GetQuestsCompleted)
    if type(t) == "table" then
      local n = 0
      for _ in pairs(t) do n = n + 1 end
      return n
    end
  end
  return nil
end

-- statystyka (okno Statystyki): liczba albo tekst ze zlotem (ikony monet)
local function money(s)
  local total, found = 0, false
  for num, kind in s:gmatch("([%d%.,%s]+)|T[^|]-(%a+)Icon") do
    local v = tonumber((num:gsub("[^%d]", "")))
    local mult = (kind:find("Gold") and 10000) or (kind:find("Silver") and 100) or 1
    if v then total, found = total + v * mult, true end
  end
  return found and total or nil
end
local function statValue(id)
  if not GetStatistic then return nil end
  local s = try(GetStatistic, id)
  if type(s) ~= "string" or s == "" or s == "--" then return nil end
  local m = money(s)
  if m then return m end
  local digits = s:gsub("|T.-|t", ""):gsub("[^%d]", "")
  return tonumber(digits)
end

-- najwazniejsze statystyki (ID z gry; jesli gra ich nie ma, po prostu ich nie bedzie)
local KEY_STATS = {
  smierci = 60, moby = 1197, moby_exp = 1198, questy = 98, zloto = 328, zloto_loot = 333, zloto_questy = 326,
  pvp_smierci = 1501, loty = 349, lochy = 932,
}
function ns.LifetimeStats()
  local t, any = {}, false
  for k, id in pairs(KEY_STATS) do
    local v = statValue(id)
    if v then t[k], any = v, true end
  end
  local q = ns.CompletedQuests()
  if q then t.questy_lista, any = q, true end
  return any and t or nil
end

-- wszystkie statystyki z okna Statystyki (niezerowe)
local function allStats()
  if not (GetStatisticsCategoryList and GetCategoryNumAchievements and GetAchievementInfo) then return nil end
  local cats = try(GetStatisticsCategoryList)
  if type(cats) ~= "table" then return nil end
  local out, n = {}, 0
  for _, cat in ipairs(cats) do
    local num = try(GetCategoryNumAchievements, cat) or 0
    for i = 1, num do
      local id, name = try(GetAchievementInfo, cat, i)
      if id then
        local v = statValue(id)
        if v and v > 0 and n < 600 then out[tostring(id)] = { name, v }; n = n + 1 end
      end
    end
  end
  return n > 0 and out or nil
end

-- zdobyte osiagniecia z datami
local function achievements()
  if not (GetCategoryList and GetCategoryNumAchievements and GetAchievementInfo) then return nil end
  local cats = try(GetCategoryList)
  if type(cats) ~= "table" then return nil end
  local out = {}
  for _, cat in ipairs(cats) do
    local num = try(GetCategoryNumAchievements, cat) or 0
    for i = 1, num do
      local id, name, points, completed, month, day, year, _, _, _, _, _, wasEarnedByMe = try(GetAchievementInfo, cat, i)
      if id and completed and #out < 1500 then
        local d = (year and month and day) and string.format("20%02d-%02d-%02d", year % 100, month, day) or nil
        out[#out + 1] = { id, name, d, points, wasEarnedByMe == false and 0 or nil }
      end
    end
  end
  return #out > 0 and out or nil
end

local function professions()
  local t = {}
  if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
    for i = 1, (try(C_SkillInfo.GetNumSkillLines) or 0) do
      local a = try(C_SkillInfo.GetSkillLineInfo, i)
      if type(a) == "table" and a.name and not a.isHeader then t[#t + 1] = { a.name, a.rank or 0, a.maxRank or 0 } end
    end
  elseif GetNumSkillLines and GetSkillLineInfo then
    for i = 1, (try(GetNumSkillLines) or 0) do
      local name, isHeader, _, rank, _, _, maxRank = try(GetSkillLineInfo, i)
      if name and not isHeader then t[#t + 1] = { name, rank or 0, maxRank or 0 } end
    end
  elseif GetProfessions and GetProfessionInfo then
    for _, idx in ipairs({ try(GetProfessions) }) do
      local name, _, rank, maxRank = try(GetProfessionInfo, idx)
      if name then t[#t + 1] = { name, rank or 0, maxRank or 0 } end
    end
  end
  return #t > 0 and t or nil
end

function ns.SendHistory(reason)
  if not ns.CH then return end
  local d = {
    powod = reason,
    questy = ns.CompletedQuests(),
    wszech = ns.LifetimeStats(),
    statystyki = allStats(),
    osiagniecia = achievements(),
    punkty = try(GetTotalAchievementPoints),
    profesje = professions(),
    played = ns.Played(),
    lvl = UnitLevel("player"),
    staty_wtedy = ns.CH.staty, -- liczniki addonu w tej chwili (strona doda tylko to, co przybedzie potem)
  }
  Log("HISTORIA", d)
  ns.CH.historia = ns.now()
  local a = d.osiagniecia and #d.osiagniecia or 0
  ns.msg(string.format("Dane wstecz zapisane: questy %s, statystyki %s, osiagniecia %d. Pojda na strone po /reload.",
    d.questy and tostring(d.questy) or "brak", d.statystyki and "tak" or "brak", a))
end

-- raz na postac, chwile po wejsciu (gra dociaga osiagniecia i questy)
ns.Hook("start", function()
  if ns.CH and not ns.CH.historia then
    C_Timer.After(15, function() if ns.CH and not ns.CH.historia then ns.SendHistory("pierwsze uruchomienie") end end)
  end
end)

-------------------------------------------------------------------------------
-- Sonda: co gra udostepnia
-------------------------------------------------------------------------------
local function yn(v) return v and "|cff22c55etak|r" or "|cffef4444nie|r" end

function ns.Probe()
  local ok, _, _, _, iface = pcall(GetBuildInfo)
  ns.msg(string.format("Sonda - gra %s (interface %s), addon v%s", ns.GRA, tostring(iface), ns.VERSION))
  local q = ns.CompletedQuests()
  ns.msg("Ukonczone questy od poczatku: " .. (q and ("|cff22c55e" .. q .. "|r") or yn(false)))
  local st = ns.LifetimeStats()
  if st then
    local parts = {}
    for k, v in pairs(st) do parts[#parts + 1] = k .. "=" .. tostring(v) end
    table.sort(parts)
    ns.msg("Statystyki od poczatku: " .. table.concat(parts, ", "))
  else
    ns.msg("Statystyki postaci (okno Statystyki): " .. yn(false))
  end
  local ach = achievements()
  local lvls = {}
  for _, a in ipairs(ach or {}) do
    if type(a[2]) == "string" and a[2]:match("^Level %d+$") then lvls[#lvls + 1] = a[2]:match("%d+") .. ":" .. tostring(a[3]) end
  end
  ns.msg(string.format("Osiagniecia: %s (zdobyte: %d)%s", yn(ach), ach and #ach or 0,
    #lvls > 0 and (", poziomy z datami: " .. table.concat(lvls, " ")) or ""))
  ns.msg("Podsumowanie smierci (Death Recap): " .. yn(C_DeathRecap and C_DeathRecap.GetRecapEvents)
    .. ", combat log: " .. yn(ns.isClassic) .. ", HK od poczatku: " .. tostring(try(GetPVPLifetimeStats) or "nie"))
  local played = ns.Played()
  ns.msg("Czas gry (/played): " .. (played and ns.Dur(played) or "czekam na serwer") .. ". Profesje: " .. yn(professions()))
  if ns.MapProbe then
    local pos, lay = ns.MapProbe()
    ns.msg("Pozycja na mapie: " .. pos .. ". Uklad mapy: " .. lay)
  end
  ns.msg("Skopiuj albo zrob zrzut ekranu tych linii i wyslij Kubie :)")
end
