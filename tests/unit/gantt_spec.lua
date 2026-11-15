local dates = require("doc_preview.mermaid.gantt_dates")
local gantt = require("doc_preview.mermaid.gantt")
local mermaid = require("doc_preview.mermaid")

local function parse(...)
  return gantt.parse({ "gantt", ... })
end

local function fails(msg, ...)
  local args = { ... }
  assert.has_error(function()
    parse(unpack(args))
  end, msg)
end

local function d(s)
  return dates.parse(dates.compile("YYYY-MM-DD"), s) / dates.DAY
end

describe("gantt_dates", function()
  it("converts civil dates and days both ways", function()
    assert.equals(0, dates.days_from_civil(1970, 1, 1))
    assert.equals(19782, dates.days_from_civil(2024, 2, 29))
    assert.equals(-1, dates.days_from_civil(1969, 12, 31))
    for _, z in ipairs({ -800000, -1, 0, 59, 11016, 19782, 800000 }) do
      assert.equals(z, dates.days_from_civil(dates.civil_from_days(z)))
    end
  end)

  it("knows leap years", function()
    assert.is_true(dates.is_leap(2000))
    assert.is_true(dates.is_leap(2024))
    assert.is_false(dates.is_leap(1900))
    assert.equals(29, dates.days_in_month(2024, 2))
    assert.equals(28, dates.days_in_month(2023, 2))
  end)

  it("parses dates with times and rejects impossible ones", function()
    local p = dates.compile("YYYY-MM-DD HH:mm")
    assert.equals(d("2024-03-01") * 1440 + 9 * 60 + 5, dates.parse(p, "2024-03-01 09:05"))
    assert.is_nil(dates.parse(p, "2024-03-01 24:00"))
    assert.is_nil(dates.parse(p, "2024-03-01"))
    local day = dates.compile("YYYY-MM-DD")
    assert.is_nil(dates.parse(day, "2023-02-29"))
    assert.is_nil(dates.parse(day, "2024-13-01"))
    assert.is_nil(dates.parse(day, "2024-01-01x"))
    assert.is_not_nil(dates.parse(day, "2024-02-29"))
  end)

  it("reads unix seconds and rejects unsupported tokens", function()
    assert.equals(1440, dates.parse(dates.compile("X"), "86400"))
    assert.is_nil(dates.compile("DD/MMM/YY"))
  end)

  it("reads durations", function()
    assert.equals(1440, dates.duration("1d"))
    assert.equals(10080, dates.duration("1w"))
    assert.equals(120, dates.duration("2h"))
    assert.equals(36, dates.duration("36m"))
    assert.equals(1, dates.duration("30s"))
    assert.equals(2160, dates.duration("1.5d"))
    assert.is_nil(dates.duration("3x"))
    assert.is_nil(dates.duration("d"))
  end)

  it("formats moments", function()
    assert.equals("2024-02-29", dates.format(d("2024-02-29") * 1440, "day"))
    assert.equals("2024-02-29 13:07", dates.format(d("2024-02-29") * 1440 + 787, "minute"))
  end)
end)

describe("gantt.parse", function()
  it("reads title, sections and settings", function()
    local g = parse(
      "title T",
      "axisFormat %d",
      "tickInterval 1week",
      "section A",
      "x :2024-01-01, 1d",
      "section B"
    )
    assert.equals("T", g.title)
    assert.equals("%d", g.axis_format)
    assert.equals("1week", g.tick_interval)
    assert.same({ "A", "B" }, g.sections)
    assert.equals(1, g.tasks[1].section_no)
    assert.equals("A", g.tasks[1].section)
  end)

  it("falls back on an unsupported dateFormat with a note", function()
    local g = parse("dateFormat MMM Do", "x :2024-01-01, 1d")
    assert.equals("YYYY-MM-DD", g.date_format)
    assert.is_truthy(g.format_note:find("MMM Do", 1, true))
  end)

  it("resolves after, until and implicit starts in day units", function()
    local g = parse(
      "a :a, 2024-01-01, 2d",
      "b :b, after a, 3d",
      "c :c, after a b, until z",
      "z :z, 2024-01-10, 1d",
      "e :2d"
    )
    assert.equals("day", g.unit)
    assert.equals(d("2024-01-03"), g.tasks[2].start)
    assert.equals(d("2024-01-06"), g.tasks[2].finish)
    assert.equals(d("2024-01-06"), g.tasks[3].start)
    assert.equals(d("2024-01-10"), g.tasks[3].finish)
    assert.equals(g.tasks[4].finish, g.tasks[5].start)
  end)

  it("crosses a leap day", function()
    local g = parse("a :a, 2024-02-28, 2d", "b :2023-02-28, 2d")
    assert.equals(d("2024-03-01"), g.tasks[1].finish)
    assert.equals(d("2023-03-02"), g.tasks[2].finish)
  end)

  it("handles milestones", function()
    local g = parse("m :milestone, m, 2024-01-05, 0d", "n :milestone, after m, 0d")
    assert.is_true(g.tasks[1].milestone)
    assert.equals(g.tasks[1].start, g.tasks[1].finish)
    assert.equals(g.tasks[1].finish, g.tasks[2].start)
    assert.equals(g.tasks[2].start, g.tasks[2].finish)
  end)

  it("switches to minutes for times of day", function()
    local g = parse("dateFormat YYYY-MM-DD HH:mm", "a :2024-01-01 09:00, 90m")
    assert.equals("minute", g.unit)
    assert.equals(90, g.tasks[1].finish - g.tasks[1].start)
  end)

  it("names the line of each error and never throws anything else", function()
    fails("line 2: unknown task id q", "a :after q, 1d")
    fails("line 3: cycle in task dependencies at a", "a :a, after b, 1d", "b :b, after a, 1d")
    fails("line 2: cycle in task dependencies at a", "a :a, after a, 1d")
    fails("line 2: bad date 2024-02-30", "a :2024-02-30, 1d")
    fails("line 2: bad date 3x", "a :2024-01-01, 3x")
    fails("line 2: task has no start and no previous task", "a :2d")
    fails("line 3: task has no end date or duration", "p :2024-01-01, 1d", "a :done")
    fails("line 3: duplicate task id a", "a :a, 2024-01-01, 1d", "b :a, 2024-01-01, 1d")
    fails("line 2: syntax error: nonsense", "nonsense")
    assert.has_error(function()
      gantt.parse({ "graph TD" })
    end, "line 1: expected gantt")
  end)
end)

describe("gantt registration", function()
  it("is registered and drawn, while other unimplemented types stay errboxes", function()
    local o = mermaid.render({ "gantt", "a :2024-01-01, 1d" }, { width = 60 })
    assert.is_falsy(table.concat(o.lines, "\n"):find("unsupported", 1, true))
    o = mermaid.render({ "mindmap" }, { width = 60 })
    assert.is_truthy(table.concat(o.lines, "\n"):find("unsupported diagram type", 1, true))
  end)
end)
