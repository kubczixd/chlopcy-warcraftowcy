-- Ekipa Challenge - mapa: pozycje we wspolrzednych swiata gry (jardy, wspolne dla calego kontynentu).
--   TRASA  co ~15 s punkt trasy (gdy postac sie przesunela), paczka co 5 min / zmiana kontynentu / zapis gry
--   MAPA   raz na wersje addonu: kontynenty i krainy z granicami we wspolrzednych swiata (strona rysuje z tego mape)
--   poz    przy smierci, bossie, awansie, quescie, lootcie, PvP i zabitym mobie: { k = kontynent, x, y, m = kraina }
--          (w lochu pozycji nie ma - wtedy ostatnia pozycja sprzed wejscia, czyli wejscie do lochu, i inst = true)

local ADDON, ns = ...

local hasMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos
local function round(v) return math.floor(v + 0.5) end

-- kontynent (id swiata), x, y (jardy), kraina (uiMapID); nil w lochu albo gdy gra nie podaje pozycji
local function worldPos()
  if not hasMap then return nil end
  local m = C_Map.GetBestMapForUnit("player")
  if not m or ns.Hidden(m) then return nil end
  local p = C_Map.GetPlayerMapPosition(m, "player")
  if not p then return nil end
  local px, py = p:GetXY()
  if ns.Hidden(px) or not px or (px == 0 and py == 0) then return nil end
  local k, w = C_Map.GetWorldPosFromMapPos(m, p)
  if not k or not w then return nil end
  local wx, wy = w:GetXY()
  if ns.Hidden(wx) or not wx then return nil end
  return k, round(wx), round(wy), m
end
function ns.WorldPos()
  local ok, k, x, y, m = pcall(worldPos)
  if ok and k then
    ns.state.lastPos = { k = k, x = x, y = y, m = m }
    return k, x, y, m
  end
  return nil
end

-- pozycja do zdarzen (Core.lua: ns.Log)
local WITH_POS = { SMIERC = true, BOSS = true, LVL = true, QUEST = true, LOOT = true, PVP_ZAB = true, PVP_SMIERC = true, MOB = true }
function ns.AttachPos(e, d)
  if not WITH_POS[e] or type(d) ~= "table" or d.poz then return end
  local k, x, y, m = ns.WorldPos()
  if k then
    d.poz = { k = k, x = x, y = y, m = m }
  elseif ns.state.lastPos then
    local p = ns.state.lastPos
    d.poz = { k = p.k, x = p.x, y = p.y, m = p.m, inst = true }
  end
end

-------------------------------------------------------------------------------
-- Trasa
-------------------------------------------------------------------------------
local trail -- { k, t0, p = { dt, x, y, ... } }
local lastX, lastY
local MIN_STEP = 25 -- jardy

local function flush()
  if trail and #trail.p >= 3 then ns.Log("TRASA", trail) end
  trail = nil
end

local function sample()
  if not ns.state.ready then return end
  local k, x, y = ns.WorldPos()
  if not k then return end
  if trail and trail.k ~= k then flush() end
  if trail and lastX and math.abs(x - lastX) + math.abs(y - lastY) < MIN_STEP then return end
  local t = ns.now()
  if not trail then trail = { k = k, t0 = t, p = {} } end
  local p = trail.p
  p[#p + 1] = t - trail.t0
  p[#p + 1] = x
  p[#p + 1] = y
  if UnitOnTaxi and UnitOnTaxi("player") then trail.lot = true end
  lastX, lastY = x, y
  if #p >= 3 * 60 or t - trail.t0 >= 300 then flush() end
end

if C_Timer and C_Timer.NewTicker then
  C_Timer.NewTicker(15, function() pcall(sample) end)
end
ns.Hook("logout", function() pcall(sample); flush() end)
ns.On("PLAYER_CONTROL_LOST", function() pcall(sample) end) -- start lotu
ns.On("PLAYER_CONTROL_GAINED", function() pcall(sample) end) -- koniec lotu

-------------------------------------------------------------------------------
-- Uklad mapy (raz na wersje addonu)
-------------------------------------------------------------------------------
local function rectOf(mapID)
  local ok, k1, a = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 0))
  local ok2, k2, b = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(1, 1))
  if not (ok and ok2 and k1 and a and b) or k1 ~= k2 then return nil end
  local x1, y1 = a:GetXY()
  local x2, y2 = b:GetXY()
  return k1, { round(x1), round(y1), round(x2), round(y2) }
end

local function layout()
  if not (hasMap and C_Map.GetMapChildrenInfo and C_Map.GetMapInfo and Enum and Enum.UIMapType and CreateVector2D) then return nil end
  local T = Enum.UIMapType
  -- kontynenty: dzieci mapy swiata (i kosmosu - na wypadek innych ukladow)
  local seen, conts = {}, {}
  for _, root in ipairs({ 947, 946 }) do
    for _, info in ipairs(C_Map.GetMapChildrenInfo(root, T.Continent, true) or {}) do
      if not seen[info.mapID] then
        seen[info.mapID] = true
        local k, r = rectOf(info.mapID)
        if k then
          local zones = {}
          for _, z in ipairs(C_Map.GetMapChildrenInfo(info.mapID, T.Zone, false) or {}) do
            local zk, zr = rectOf(z.mapID)
            if zk == k then zones[#zones + 1] = { id = z.mapID, nazwa = ns.Safe(z.name), r = zr } end
          end
          conts[#conts + 1] = { id = info.mapID, k = k, nazwa = ns.Safe(info.name), r = r, strefy = zones }
        end
      end
    end
  end
  return #conts > 0 and conts or nil
end

ns.Hook("start", function()
  C_Timer.After(20, function()
    pcall(sample)
    if ns.DB and ns.DB.meta.mapa ~= ns.VERSION then
      local ok, conts = pcall(layout)
      if ok and conts then
        ns.Log("MAPA", { kontynenty = conts })
        ns.DB.meta.mapa = ns.VERSION
      end
    end
  end)
end)

-- do /ekipa sonda
function ns.MapProbe()
  local k, x, y, m = ns.WorldPos()
  local ok, conts = pcall(layout)
  local nz = 0
  for _, c in ipairs(ok and conts or {}) do nz = nz + #c.strefy end
  return k and string.format("tak (kontynent %s, x %d, y %d, kraina %s)", tostring(k), x, y, tostring(m)) or "nie (loch albo gra nie podaje)",
    ok and conts and string.format("%d kontynenty, %d krain", #conts, nz) or "nie"
end
