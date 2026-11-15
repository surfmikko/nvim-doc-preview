-- Sequence diagram layout: Seq (mermaid/sequence_model) -> columns, rows
-- and frames, in character cells. Free of Mermaid syntax so PlantUML
-- sequence diagrams can share it (doc/diagram-model.md 2).
--
-- One column per participant (x of its lifeline), one row group per event:
-- message text above its arrow, notes as boxes, blocks as full-width frames
-- (rect blocks are transparent), a blank row after every item. Column x
-- positions are the longest-path solution of "c[j] >= c[i] + d" constraints
-- gathered from the participant boxes, message and note texts.
local job = require("doc_preview.core.job")
local text = require("doc_preview.core.text")

local M = {}

local GAP, COMPACT_GAP = 2, 1 -- blank columns between neighbouring boxes
local MIN_SPAN = 4 -- lifelines of a message at least this far apart
local LOOP = 3 -- columns a self-message loop uses right of its lifeline

-- Continuation keyword per block type (the first section has none).
local SECTION_WORD = { alt = "else", par = "and", critical = "option" }

-- Text rows; `wrap` (optional) is the widest row.
local function rows_of(s, wrap)
  local rows = {}
  for chunk in (s .. "\n"):gmatch("(.-)\n") do
    if chunk ~= "" and wrap then
      vim.list_extend(rows, text.wrap(chunk, wrap))
    elseif chunk ~= "" then
      rows[#rows + 1] = chunk
    end
  end
  return rows
end

local function widest(rows)
  local w = 0
  for _, r in ipairs(rows) do
    w = math.max(w, text.width(r))
  end
  return w
end

local function cut(s, max)
  if not max or text.width(s) <= max then
    return s
  end
  return text.hard_wrap(s, math.max(max, 4) - 3)[1] .. "..."
end

local function frame_text(word, label, wrap)
  local s = "[" .. word .. "]" .. ((label or "") ~= "" and (" " .. label) or "")
  return cut(s, wrap and wrap + 8)
end

-- Events as a flat list with block open/divider/close markers and depth.
local function flatten(events, depth, steps, wrap)
  for _, ev in ipairs(events) do
    if ev.kind ~= "block" then
      steps[#steps + 1] = { kind = ev.kind, ev = ev, depth = depth }
    elseif ev.type == "rect" then
      for _, sec in ipairs(ev.sections) do
        flatten(sec.events, depth, steps, wrap)
      end
    else
      local label = frame_text(ev.type, ev.label, wrap)
      steps[#steps + 1] = { kind = "open", ev = ev, depth = depth, text = label }
      for k, sec in ipairs(ev.sections) do
        if k > 1 then
          local word = SECTION_WORD[ev.type] or "and"
          local divider = frame_text(word, sec.label, wrap)
          steps[#steps + 1] = { kind = "divider", ev = ev, depth = depth, text = divider }
        end
        flatten(sec.events, depth + 1, steps, wrap)
      end
      steps[#steps + 1] = { kind = "close", ev = ev, depth = depth }
    end
  end
end

local function numbered(ev, num)
  if not num.on then
    return ev.text
  end
  local s = num.n .. "." .. (ev.text ~= "" and (" " .. ev.text) or "")
  num.n = num.n + num.step
  return s
end

local function prepare_message(st, c)
  st.from, st.to = c.idx[st.ev.from], c.idx[st.ev.to]
  st.lines = rows_of(numbered(st.ev, c.num), c.wrap)
end

local function prepare_note(st, c)
  st.lines = rows_of(st.ev.text, c.wrap)
  st.a, st.b = c.count, 1
  for _, id in ipairs(st.ev.targets) do
    st.a, st.b = math.min(st.a, c.idx[id]), math.max(st.b, c.idx[id])
  end
end

local function prepare_activation(st, c)
  st.col = c.idx[st.ev.id]
end

local function prepare_autonumber(st, c)
  c.num.on = not st.ev.off
  c.num.n, c.num.step = st.ev.start or 1, st.ev.step or 1
end

local PREPARE = {
  message = prepare_message,
  note = prepare_note,
  activate = prepare_activation,
  deactivate = prepare_activation,
  autonumber = prepare_autonumber,
}

-- Resolve ids to column indexes, wrap texts, apply autonumber.
local function prepare(seq, steps, wrap)
  local idx = {}
  for i, p in ipairs(seq.participants) do
    idx[p.id] = i
  end
  local num = { on = false, n = 1, step = 1 }
  local c = { idx = idx, count = #seq.participants, wrap = wrap, num = num }
  for _, st in ipairs(steps) do
    local f = PREPARE[st.kind]
    if f then
      f(st, c)
    end
  end
end

local function columns(seq, wrap)
  local cols = {}
  for i, p in ipairs(seq.participants) do
    local lines = rows_of(p.label, wrap)
    local bw = widest(lines) + 4
    cols[i] = { kind = p.kind, lines = lines, bw = bw, hl = math.floor((bw - 1) / 2) }
    cols[i].hr = bw - 1 - cols[i].hl
  end
  return cols
end

-- Collected constraints: need[j][i] = d (c[j] >= c[i] + d), sl/sr = how far
-- step content reaches left/right of a lifeline, width = lower bound.
local function new_needs(n)
  local k = { need = {}, sl = {}, sr = {}, width = 0, depth = -1 }
  for i = 1, n do
    k.need[i], k.sl[i], k.sr[i] = {}, 0, 0
  end
  return k
end

local function add_need(k, i, j, d)
  k.need[j][i] = math.max(k.need[j][i] or 0, d)
end

local function reach(k, i, left, right)
  k.sl[i] = math.max(k.sl[i], left)
  k.sr[i] = math.max(k.sr[i], right)
end

local function message_needs(k, st)
  local tw = widest(st.lines)
  if st.from == st.to then
    reach(k, st.from, 0, math.max(LOOP, 1 + tw))
  else
    add_need(k, math.min(st.from, st.to), math.max(st.from, st.to), math.max(tw + 3, MIN_SPAN))
  end
end

local function note_needs(k, st)
  local w = widest(st.lines) + 4
  local side = st.ev.side
  if side == "left" then
    reach(k, st.a, w + 1, 0)
  elseif side == "right" then
    reach(k, st.a, 0, w + 1)
  elseif st.a == st.b then
    reach(k, st.a, math.floor(w / 2), w - 1 - math.floor(w / 2))
  else
    reach(k, st.a, 1, 0)
    reach(k, st.b, 0, 1)
    add_need(k, st.a, st.b, math.max(w - 3, 1))
  end
end

local function frame_needs(k, st)
  k.depth = math.max(k.depth, st.depth)
  k.width = math.max(k.width, text.width(st.text) + 5 + 2 * st.depth)
end

local NEEDS = {
  message = message_needs,
  note = note_needs,
  open = frame_needs,
  divider = frame_needs,
}

-- Neighbouring boxes, and step content next to the neighbour's lifeline.
local function adjacent_needs(k, cols, gap)
  for i = 1, #cols - 1 do
    local boxes = cols[i].hr + cols[i + 1].hl + 1 + gap
    add_need(k, i, i + 1, math.max(boxes, k.sr[i] + 2, k.sl[i + 1] + 2))
  end
end

-- Lifeline x of every column and the diagram width.
local function solve(cols, k)
  local pad = k.depth >= 0 and k.depth + 2 or 0
  local width = k.width
  for j, col in ipairs(cols) do
    local x = math.max(col.hl, k.sl[j]) + pad
    if j > 1 then
      x = math.max(x, cols[j - 1].x + 1)
    end
    for i, d in pairs(k.need[j]) do
      x = math.max(x, cols[i].x + d)
    end
    col.x = x
    width = math.max(width, x + math.max(col.hr, k.sr[j]) + 1 + pad)
  end
  return width
end

local function note_box(cols, st)
  local w = widest(st.lines) + 4
  local side, a, b = st.ev.side, cols[st.a], cols[st.b]
  if side == "left" then
    return a.x - 1 - w, w
  elseif side == "right" then
    return a.x + 2, w
  elseif st.a == st.b then
    return a.x - math.floor(w / 2), w
  end
  return a.x - 1, b.x - a.x + 3
end

-- Placement state `s`: lay, cols, y (cursor), open (frames), active (bar starts per column).
local function start_bar(s, col, at)
  s.active[col] = s.active[col] or {}
  table.insert(s.active[col], at)
end

local function stop_bar(s, col, at)
  local y0 = table.remove(s.active[col] or {})
  if y0 then
    s.lay.bars[#s.lay.bars + 1] = { col = col, y0 = y0, y1 = math.max(at, y0) }
  end
end

local function place_message(s, st)
  local top = s.y + #st.lines
  local self_msg = st.from == st.to
  local ev = st.ev
  s.lay.items[#s.lay.items + 1] = {
    kind = "message",
    y = top,
    from = st.from,
    to = st.to,
    lines = st.lines,
    line = ev.line,
    head = ev.head,
    self = self_msg,
    src = ev.src,
  }
  if ev.activate then
    start_bar(s, st.to, top)
  end
  if ev.deactivate then
    stop_bar(s, st.from, top)
  end
  s.y = top + (self_msg and 2 or 1) + 1
end

local function place_note(s, st)
  local x0, w = note_box(s.cols, st)
  local h = math.max(#st.lines, 1) + 2
  s.lay.items[#s.lay.items + 1] = {
    kind = "note",
    y = s.y,
    h = h,
    x = x0,
    w = w,
    lines = st.lines,
    center = st.ev.side == "over",
    src = st.ev.src,
  }
  s.y = s.y + h + 1
end

local function place_open(s, st)
  local f = { depth = st.depth, y0 = s.y, text = st.text, dividers = {}, src = st.ev.src }
  s.open[#s.open + 1] = f
  s.y = s.y + 2
end

local function place_divider(s, st)
  table.insert(s.open[#s.open].dividers, { y = s.y, text = st.text })
  s.y = s.y + 2
end

local function place_close(s)
  local f = table.remove(s.open)
  f.y1 = s.y
  s.lay.frames[#s.lay.frames + 1] = f
  s.y = s.y + 2
end

local function place_activate(s, st)
  start_bar(s, st.col, s.y)
end

local function place_deactivate(s, st)
  stop_bar(s, st.col, s.y - 2)
end

local PLACE = {
  message = place_message,
  note = place_note,
  open = place_open,
  divider = place_divider,
  close = place_close,
  activate = place_activate,
  deactivate = place_deactivate,
}

-- Rows: advance the cursor per step and record drawable items.
local function place(lay, cols, steps)
  local s = { lay = lay, cols = cols, y = lay.boxh + 1, open = {}, active = {} }
  for n, st in ipairs(steps) do
    if n % 8 == 0 then
      job.yield_point()
    end
    local f = PLACE[st.kind]
    if f then
      f(s, st)
    end
  end
  for col in pairs(s.active) do
    while #s.active[col] > 0 do
      stop_bar(s, col, s.y - 1)
    end
  end
  return s.y
end

---@param seq table  Seq (mermaid/sequence_model)
---@param opts? { compact?: boolean, wrap?: integer }  wrap: widest text row
---@return table lay  { width, height, boxh, cols, items, frames, bars, life }
function M.layout(seq, opts)
  opts = opts or {}
  local steps = {}
  flatten(seq.events, 0, steps, opts.wrap)
  prepare(seq, steps, opts.wrap)
  local cols = columns(seq, opts.wrap)
  local k = new_needs(#cols)
  for _, st in ipairs(steps) do
    local f = NEEDS[st.kind]
    if f then
      f(k, st)
    end
  end
  adjacent_needs(k, cols, opts.compact and COMPACT_GAP or GAP)
  local width = solve(cols, k)
  local boxh = 2
  for _, col in ipairs(cols) do
    boxh = math.max(boxh, #col.lines + 2)
  end
  local lay = { width = width, boxh = boxh, cols = cols, items = {}, frames = {}, bars = {} }
  local y = place(lay, cols, steps)
  lay.height = y + boxh
  lay.life = { y0 = boxh, len = y - boxh }
  return lay
end

return M
