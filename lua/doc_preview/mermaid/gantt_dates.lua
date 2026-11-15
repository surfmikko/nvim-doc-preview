-- Pure date arithmetic for gantt charts (no os.date, no external process).
-- A moment is an integer count of minutes since 1970-01-01 00:00 (UTC, no
-- zones, no daylight saving). Days follow the proleptic Gregorian calendar.
local M = {}

M.DAY = 1440

-- Format tokens understood in `dateFormat`; any other letter makes
-- `compile` return nil (the caller falls back to YYYY-MM-DD).
local TOKENS = { YYYY = 4, MM = 2, DD = 2, HH = 2, mm = 2 }

local UNITS = { m = 1, h = 60, d = 1440, w = 10080 }

local MONTH_DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

---@return boolean
function M.is_leap(y)
  return y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)
end

---@return integer
function M.days_in_month(y, m)
  return (m == 2 and M.is_leap(y)) and 29 or MONTH_DAYS[m]
end

-- Days since 1970-01-01 of a civil date (Howard Hinnant's algorithm,
-- public domain).
---@return integer
function M.days_from_civil(y, m, d)
  if m <= 2 then
    y = y - 1
  end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

---@return integer y, integer m, integer d
function M.civil_from_days(z)
  z = z + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor(
    (doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365
  )
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local d = doy - math.floor((153 * mp + 2) / 5) + 1
  local m = mp + (mp < 10 and 3 or -9)
  local y = yoe + era * 400 + (m <= 2 and 1 or 0)
  return y, m, d
end

---@return integer minutes
function M.to_minutes(y, mo, d, h, mi)
  return M.days_from_civil(y, mo, d) * M.DAY + h * 60 + mi
end

---@return integer y, integer mo, integer d, integer h, integer mi
function M.from_minutes(t)
  local days = math.floor(t / M.DAY)
  local rest = t - days * M.DAY
  local y, mo, d = M.civil_from_days(days)
  return y, mo, d, math.floor(rest / 60), rest % 60
end

-- `YYYY-MM-DD` (unit "day") or `YYYY-MM-DD HH:mm` (unit "minute").
---@param t integer
---@param unit "day"|"minute"
---@return string
function M.format(t, unit)
  local y, mo, d, h, mi = M.from_minutes(t)
  local s = ("%04d-%02d-%02d"):format(y, mo, d)
  return unit == "minute" and (s .. (" %02d:%02d"):format(h, mi)) or s
end

-- Split a format into literal and token pieces; nil when it holds a token
-- (letter) outside the supported set. `X` (unix seconds) must stand alone.
---@param fmt string
---@return table|nil  { { token = "YYYY" } | { lit = "-" }, ... }
function M.compile(fmt)
  if fmt == "X" then
    return { { token = "X" } }
  end
  local parts, i = {}, 1
  while i <= #fmt do
    local tok
    for name in pairs(TOKENS) do
      if fmt:sub(i, i + #name - 1) == name then
        tok = name
      end
    end
    if tok then
      parts[#parts + 1] = { token = tok }
      i = i + #tok
    elseif fmt:sub(i, i):match("%a") then
      return nil
    else
      parts[#parts + 1] = { lit = fmt:sub(i, i) }
      i = i + 1
    end
  end
  return parts
end

-- Numeric token at `pos`: its value and the position after it, or nil.
local function read_number(token, s, pos)
  local is_x = token == "X"
  local digits = s:match("^%d+", pos)
  if not digits or (not is_x and #digits < TOKENS[token]) then
    return nil
  end
  digits = is_x and digits or digits:sub(1, TOKENS[token])
  return tonumber(digits), pos + #digits
end

-- Read the parts from `s` into a field table, or nil when `s` does not match.
local function read_fields(parts, s)
  local f, pos = { YYYY = 1970, MM = 1, DD = 1, HH = 0, mm = 0 }, 1
  for _, p in ipairs(parts) do
    if p.lit then
      if s:sub(pos, pos) ~= p.lit then
        return nil
      end
      pos = pos + 1
    else
      local value, after = read_number(p.token, s, pos)
      if not value then
        return nil
      end
      f[p.token] = value
      pos = after
    end
  end
  return pos == #s + 1 and f or nil
end

---@param parts table  from compile
---@param s string
---@return integer|nil minutes
function M.parse(parts, s)
  local f = read_fields(parts, s)
  if not f then
    return nil
  end
  if f.X then
    return math.floor(f.X / 60)
  end
  if
    f.MM < 1
    or f.MM > 12
    or f.DD < 1
    or f.DD > M.days_in_month(f.YYYY, f.MM)
    or f.HH > 23
    or f.mm > 59
  then
    return nil
  end
  return M.to_minutes(f.YYYY, f.MM, f.DD, f.HH, f.mm)
end

-- `3d`, `2w`, `36h`, `90m`, `1.5d`, `30s` (rounded up to a minute).
---@param s string
---@return integer|nil minutes
function M.duration(s)
  local n, unit = s:match("^(%d+%.?%d*)([dwhms])$")
  if not n then
    return nil
  end
  if unit == "s" then
    return math.ceil(tonumber(n) / 60)
  end
  return math.floor(tonumber(n) * UNITS[unit] + 0.5)
end

return M
