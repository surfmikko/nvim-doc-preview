-- Reference-pair runner (doc/testing.md 2). Walks <root>/<fmt>/<suite>/<case>.in
-- with .expected, parses, projects, normalises and compares.
-- <root>/<fmt>/skip.lua:      { ["<suite>/<case>"] = "reason" }
-- <root>/<fmt>/threshold.lua: { ["<suite>"] = minimum pass count }
local project_facts = require("pairs.project_facts")
local project_html = require("pairs.project_html")

local M = {}

-- Per format: `actual(lines)` returns the projected text and a list of
-- unsupported kinds; `normalize` is applied to both sides.
M.frontends = {
  markdown = {
    label = "commonmark-",
    normalize = project_html.normalize,
    actual = function(lines)
      local doc = require("doc_preview.markdown.block").parse(lines)
      local html, unsupported = project_html.project(doc)
      return html, unsupported
    end,
  },
  mermaid = {
    label = "mermaid-",
    normalize = project_facts.normalize,
    actual = function(lines)
      return project_facts.from_source(lines), {}
    end,
  },
}

local function read(path)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  return table.concat(vim.fn.readfile(path), "\n")
end

local function load_table(path)
  if vim.fn.filereadable(path) == 0 then
    return {}
  end
  return dofile(path)
end

-- Returns "pass" or "fail" plus a message.
local function run_case(cfg, base)
  local expected = cfg.normalize(read(base .. ".expected"))
  local text, unsupported = cfg.actual(vim.fn.readfile(base .. ".in"))
  local actual = cfg.normalize(text)
  if expected == actual then
    return "pass"
  end
  local why = #unsupported > 0 and ("unsupported: " .. table.concat(unsupported, ",") .. "\n") or ""
  return "fail", why .. "expected:\n" .. expected .. "\nactual:\n" .. actual
end

local function case_names(dir)
  local names = {}
  for _, input in ipairs(vim.fn.glob(dir .. "/*.in", false, true)) do
    names[#names + 1] = vim.fn.fnamemodify(input, ":t:r")
  end
  table.sort(names)
  return names
end

-- Run one case and record the outcome in `r`.
local function run_named(cfg, r, skip, suite, dir, name)
  local key, base = suite .. "/" .. name, dir .. "/" .. name
  r.total = r.total + 1
  if skip[key] then
    r.skipped[key] = skip[key]
    if read(base .. ".expected") and run_case(cfg, base) == "pass" then
      r.stale[#r.stale + 1] = key .. " (passes but is skipped)"
    end
  elseif not read(base .. ".expected") then
    r.pending[#r.pending + 1] = key
  else
    local verdict, msg = run_case(cfg, base)
    if verdict == "pass" then
      r.pass = r.pass + 1
    else
      r.failed[key] = msg
    end
  end
end

-- Result: { name, pass, total, skipped = {key=reason}, pending = {key}, failed = {key=msg},
-- stale = {key}, errors = {msg} }
---@param root string
---@param fmt string
---@param suite string
function M.run_suite(root, fmt, suite)
  local cfg = M.frontends[fmt]
  local skip = load_table(root .. "/" .. fmt .. "/skip.lua")
  local threshold = load_table(root .. "/" .. fmt .. "/threshold.lua")[suite] or 0
  local dir = root .. "/" .. fmt .. "/" .. suite
  local r = {
    name = cfg.label .. suite,
    pass = 0,
    total = 0,
    skipped = {},
    pending = {},
    failed = {},
    stale = {},
    errors = {},
  }
  local seen = {}
  for _, name in ipairs(case_names(dir)) do
    seen[suite .. "/" .. name] = true
    run_named(cfg, r, skip, suite, dir, name)
  end
  for key in pairs(skip) do
    if key:match("^" .. vim.pesc(suite) .. "/") and not seen[key] then
      r.stale[#r.stale + 1] = key .. " (no such case)"
    end
  end
  table.sort(r.stale)
  if r.pass < threshold then
    r.errors[#r.errors + 1] = string.format("%d passes, below threshold %d", r.pass, threshold)
  end
  return r
end

function M.summary(r)
  local n = 0
  for _ in pairs(r.skipped) do
    n = n + 1
  end
  local line = string.format("%s: %d/%d pass, %d skipped", r.name, r.pass, r.total, n)
  if #r.pending > 0 then
    line = line .. string.format(", %d pending (no .expected)", #r.pending)
  end
  return line
end

---@return string[] suites under <root>/<fmt>
function M.suites(root, fmt)
  local suites = {}
  for _, dir in ipairs(vim.fn.glob(root .. "/" .. fmt .. "/*", false, true)) do
    if vim.fn.isdirectory(dir) == 1 then
      suites[#suites + 1] = vim.fn.fnamemodify(dir, ":t")
    end
  end
  table.sort(suites)
  return suites
end

return M
