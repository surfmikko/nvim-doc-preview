local draw = require("doc_preview.mermaid.gantt_draw")
local gantt = require("doc_preview.mermaid.gantt")
local mermaid = require("doc_preview.mermaid")
local text = require("doc_preview.core.text")

local function render(width, body, charset)
  local lines = { "gantt" }
  vim.list_extend(lines, body)
  local o = mermaid.render(lines, { width = width, charset = charset })
  for _, l in ipairs(o.lines) do
    assert.is_true(text.width(l) <= width, l)
  end
  return vim.tbl_map(function(l)
    return (l:gsub("█", "#"):gsub("▓", "="):gsub("░", "-"):gsub("◆", "*"))
  end, o.lines)
end

describe("gantt scale", function()
  local function model(...)
    return gantt.parse({ "gantt", ... })
  end

  it("maps dates to columns so the whole span fits", function()
    local g = model("a :2024-01-01, 10d", "b :2024-01-06, 5d")
    local sc = { first = 19723, span = 10, w = 40 }
    local x0, x1 = draw.cells(sc, g.tasks[1])
    assert.same({ 0, 40 }, { x0, x1 })
    x0, x1 = draw.cells(sc, g.tasks[2])
    assert.same({ 20, 40 }, { x0, x1 })
  end)

  it("gives a one-day task one unit and a milestone one column", function()
    local g = model("a :2024-01-01, 1d", "m :milestone, 2024-01-03, 0d", "b :2024-01-04, 1d")
    local sc = { first = g.tasks[1].start, span = 4, w = 8 }
    assert.same({ 0, 2 }, { draw.cells(sc, g.tasks[1]) })
    local x0, x1 = draw.cells(sc, g.tasks[2])
    assert.same({ 4, 5 }, { x0, x1 })
  end)

  it("keeps a milestone at the very end inside the area", function()
    local g = model("a :2024-01-01, 2d", "m :milestone, 2024-01-03, 0d")
    local sc = { first = g.tasks[1].start, span = 2, w = 10 }
    assert.same({ 9, 10 }, { draw.cells(sc, g.tasks[2]) })
  end)
end)

describe("gantt render", function()
  local BASIC = {
    "title Plan",
    "section Build",
    "Design :done, d1, 2024-01-01, 3d",
    "Code :active, c1, after d1, 1w",
    "Ship :crit, s1, 2024-01-12, 2024-01-15",
    "Go :milestone, m1, 2024-01-15, 0d",
  }

  it("draws title, tick row, section header and one row per task", function()
    local lines = render(60, BASIC)
    assert.equals("Plan", lines[1])
    assert.truthy(lines[2]:find("01-01", 1, true))
    assert.equals("Build", lines[3])
    assert.equals(7, #lines)
    assert.truthy(lines[4]:match("^Design #+$"))
    assert.truthy(lines[5]:match("^Code +=+$"))
    assert.truthy(lines[6]:match("^Ship  ! +%-+$"))
    assert.truthy(lines[7]:find("*", 1, true))
  end)

  it("bars start and end at the scaled columns", function()
    local lines = render(60, { "a :2024-01-01, 2d", "b :2024-01-03, 2d" })
    -- label 1, gap, area 58 -> 4 days * 14 = 56 columns, 28 per task
    local a, b = lines[2], lines[3]
    assert.equals(28, #a:match("%-+"))
    assert.equals(28, #b:match("%-+"))
    assert.equals(2 + 28, #b:match("^b +"))
  end)

  it("uses ascii glyphs", function()
    local lines = render(40, BASIC, "ascii")
    assert.truthy(lines[4]:match("^Design #+$"))
    assert.truthy(lines[5]:find("=", 1, true))
    assert.truthy(lines[7]:find("*", 1, true))
  end)

  it("scales a long project coarser and cuts long labels", function()
    local lines =
      render(30, { "A very long task label here :2020-01-01, 2024-12-31", "b :2022-01-01, 30d" })
    assert.truthy(lines[1]:find("2020-01", 1, true))
    assert.truthy(lines[2]:find("...", 1, true))
  end)

  it("renders minute schedules with time ticks", function()
    local lines = render(50, { "dateFormat HH:mm", "a :a1, 08:00, 2h", "b :after a1, 90m" })
    assert.truthy(lines[1]:find("%d%d:%d%d"))
  end)

  it("never exceeds the width, down to the errbox and tiny widths", function()
    for w = 1, 60 do
      render(w, BASIC)
    end
  end)

  it("boxes the source with a note when too narrow", function()
    local lines = render(12, BASIC)
    assert.truthy(lines[1]:find("┌", 1, true))
    assert.truthy(table.concat(lines, "\n"):find("Design", 1, true))
  end)

  it("gives an errbox without tasks and for a bad date", function()
    assert.truthy(table.concat(render(40, { "title x" }), "\n"):find("no tasks", 1, true))
    assert.truthy(table.concat(render(40, { "a :2024-13-01, 1d" }), "\n"):find("bad date", 1, true))
  end)
end)
