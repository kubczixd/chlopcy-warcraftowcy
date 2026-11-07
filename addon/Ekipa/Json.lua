-- Ekipa - minimalny koder JSON (tylko zapis). Kazde zdarzenie zapisujemy jako gotowy tekst JSON,
-- dzieki czemu uploader nie musi rozumiec formatu plikow Lua - wyciaga linie i wysyla je na strone.

local ADDON, ns = ...

local isSecret = issecretvalue or function() return false end

-- wartosc ukryta przez gre (Forever / retail): nie wolno jej porownac ani zapisac
function ns.Hidden(v)
  if isSecret(v) then return true end
  if issecrettable and type(v) == "table" then
    local ok, r = pcall(issecrettable, v)
    return ok and r or false
  end
  return false
end

-- wartosc bezpieczna do zapisu (ukryta -> nil)
function ns.Safe(v)
  if ns.Hidden(v) then return nil end
  return v
end

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function escStr(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return ESC[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function isArray(t)
  local n = #t
  if n == 0 then return false end
  local count = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then return false end
    count = count + 1
  end
  return count == n
end

local encode
encode = function(v, depth)
  if ns.Hidden(v) then return "null" end
  local t = type(v)
  if t == "string" then return escStr(v) end
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if v % 1 == 0 and v > -1e15 and v < 1e15 then return string.format("%d", v) end
    return (string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", ""))
  end
  if t == "boolean" then return v and "true" or "false" end
  if t ~= "table" or depth > 6 then return "null" end
  local out = {}
  if isArray(v) then
    for i = 1, #v do out[i] = encode(v[i], depth + 1) end
    return "[" .. table.concat(out, ",") .. "]"
  end
  local keys = {}
  for k in pairs(v) do
    if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = tostring(k) end
  end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local x = v[k]
    if x == nil then x = v[tonumber(k)] end
    if x ~= nil and not ns.Hidden(x) then out[#out + 1] = escStr(k) .. ":" .. encode(x, depth + 1) end
  end
  return "{" .. table.concat(out, ",") .. "}"
end

function ns.Json(v) return encode(v, 0) end
