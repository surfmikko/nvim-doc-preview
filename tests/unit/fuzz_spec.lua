-- Robustness gate (doc/testing.md section 1 layer 5): parse + render never
-- throw, finish in time and never emit a line wider than the width.
local block = require("doc_preview.markdown.block")
local diagram_file = require("doc_preview.document.diagram_file")
local render = require("doc_preview.document.render")
local text = require("doc_preview.core.text")

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local WIDTHS = { 20, 40, 80 }
local MUTANTS = 6
local TIME_MS = 5000

local function rng(seed)
  local state = seed
  return function(n)
    state = (state * 1103515245 + 12345) % 2147483648
    return math.floor(state / 65536) % n + 1
  end
end

local function read(path)
  return vim.fn.readfile(path)
end

local function corpus()
  local files = vim.fn.glob(root .. "/golden/markdown/*.in", false, true)
  vim.list_extend(files, vim.fn.glob(root .. "/pairs/markdown/own/*.in", false, true))
  local out = {}
  for _, f in ipairs(files) do
    out[#out + 1] = { name = vim.fn.fnamemodify(f, ":t"), lines = read(f), frontend = block }
  end
  for _, f in ipairs(vim.fn.glob(root .. "/pairs/mermaid/own/*.in", false, true)) do
    out[#out + 1] = {
      name = "mermaid/" .. vim.fn.fnamemodify(f, ":t"),
      lines = read(f),
      frontend = diagram_file,
    }
  end
  return out
end

local SNIPPETS = {
  "```",
  "~~~",
  "> ",
  "- ",
  "1. ",
  "    ",
  "| a | b |",
  "|---|---|",
  "# ",
  "[^1]: x",
  "[x](",
  "<div>",
  "</div>",
  "*",
  "_",
  "`",
  "\\",
  "&amp;",
  "\t",
  "é",
  "日本語",
  "👍🏽",
  "e\204\129",
  "\226\128\139",
  "\239\191\189",
  "---",
  "===",
  "[[",
  "]]",
  "![",
  "<!--",
}

local function snippet(rand)
  return SNIPPETS[rand(#SNIPPETS)]
end

local MUTATIONS = {
  function(out, i)
    table.remove(out, i)
  end,
  function(out, i)
    table.insert(out, i, out[i])
  end,
  function(out, i, rand)
    out[i] = out[i]:sub(1, rand(#out[i] + 1) - 1)
  end,
  function(out, i, rand)
    out[i] = snippet(rand) .. out[i]
  end,
}

local function mutate_once(out, rand)
  local n, i = #out, rand(math.max(#out, 1))
  local op = rand(6)
  if op == 5 then
    table.insert(out, i, snippet(rand) .. snippet(rand))
  elseif op == 6 and n > 1 then
    local j = rand(n)
    out[i], out[j] = out[j], out[i]
  elseif op <= 4 and n > 0 then
    MUTATIONS[op](out, i, rand)
  end
end

local function mutate(lines, rand)
  local out = vim.deepcopy(lines)
  for _ = 1, rand(3) do
    mutate_once(out, rand)
  end
  return out
end

local function check(frontend, lines, width, label)
  local started = vim.uv.hrtime()
  local ok, res = pcall(function()
    return render.render(frontend.parse(lines), { width = width })
  end)
  assert.is_true(ok, label .. ": threw: " .. tostring(res))
  local ms = (vim.uv.hrtime() - started) / 1e6
  assert.is_true(ms < TIME_MS, ("%s: took %d ms"):format(label, ms))
  for i, line in ipairs(res.lines) do
    assert.is_true(
      text.width(line) <= width,
      ("%s: line %d wider than %d: %s"):format(label, i, width, line)
    )
  end
end

local function crafted()
  local cases = {}
  local function add(name, lines, widths)
    cases[#cases + 1] = { name = name, lines = lines, widths = widths }
  end
  add("deep quotes", { ("> "):rep(300) .. "deep" }, { 1, 2, 3, 20, 1000 })
  local nested = {}
  for i = 0, 149 do
    nested[#nested + 1] = (" "):rep(2 * i) .. "- item"
  end
  add("deep lists", nested, { 1000 })
  local lazy = { "> start" }
  for _ = 1, 3000 do
    lazy[#lazy + 1] = "lazy"
  end
  add("long lazy run", lazy)
  local table_lines = { "| " .. ("h | "):rep(40), "|" .. ("---|"):rep(41) }
  for r = 1, 150 do
    table_lines[#table_lines + 1] = "| " .. ("cell" .. r .. " | "):rep(40)
  end
  add("huge table", table_lines)
  add("unterminated fence", { "```lua", "local x = 1", "more" })
  add("unterminated mermaid", { "```mermaid", "graph TD", "A --> B" })
  add("fence in quote", { "> ```", "> code", "text", "> ```" })
  add("fence in list", { "- item", "  ```", "  code", "- next" })
  add("quote fence list", { "> - ```mermaid", ">   graph TD", ">   A-->B" })
  add("odd unicode", {
    "日本語のテキストがとても長く続く行です。"
      .. ("👍🏽e\204\129\226\128\139"):rep(30),
    "| 日本 | 👍🏽 |",
    "|---|---|",
    "| e\204\129 | \226\128\139 |",
    "\239\191\189\0\1\2 tab\there",
  })
  add("long word", { ("x"):rep(500), "[" .. ("l"):rep(300) .. "](" .. ("u"):rep(300) .. ")" })
  add("empty", {})
  add("blank only", { "", "", "" })
  return cases
end

describe("robustness fuzz", function()
  it("crafted cases never throw, hang or exceed width", function()
    for _, c in ipairs(crafted()) do
      for _, w in ipairs(c.widths or WIDTHS) do
        check(block, c.lines, w, c.name .. "@" .. w)
      end
    end
  end)

  it("crafted mermaid cases never throw, hang or exceed width", function()
    local cases = {
      { "graph TD", "A --> B", "B --> A", "A --> A" },
      { "graph TD", "subgraph s", "A --> B" },
      { "sequenceDiagram", "A->>B: " .. ("long "):rep(40), "loop", "A->>A: x" },
      { "pie", '"a" : 0', '"b" : -1' },
      { "gantt", "dateFormat YYYY-MM-DD", "section s", "t :a1, 2020-01-01, 0d" },
      { "classDiagram", "class A", "A <|-- A" },
      { "erDiagram", "A ||--o{ A : self" },
      { "stateDiagram-v2", "[*] --> A", "A --> A", "A --> [*]" },
      { "notadiagram", "日本語 👍🏽" },
    }
    for i, lines in ipairs(cases) do
      for _, w in ipairs(WIDTHS) do
        check(diagram_file, lines, w, "mermaid#" .. i .. "@" .. w)
      end
    end
  end)

  it("seeded mutations of golden and pair inputs", function()
    local rand = rng(20261115)
    for _, c in ipairs(corpus()) do
      check(c.frontend, c.lines, 40, c.name)
      for m = 1, MUTANTS do
        local lines = mutate(c.lines, rand)
        local w = WIDTHS[rand(#WIDTHS)]
        check(
          c.frontend,
          lines,
          w,
          ("%s mutant %d@%d\n%s"):format(c.name, m, w, table.concat(lines, "\n"))
        )
      end
    end
  end)
end)
