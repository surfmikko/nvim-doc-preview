-- Golden runner: tests/golden/<fmt>/<name>.in -> rendered lines compared to
-- <name>.out at width 40 (or the number in <name>.width).
-- If <name>.spans exists it is compared too: one span per line,
-- "line col_start col_end group", sorted by line then column.
-- UPDATE_GOLDEN=1 rewrites the .out (and .spans) files instead of failing.
local render = require("doc_preview.document.render")
local text = require("doc_preview.core.text")

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local frontends = { markdown = "doc_preview.markdown.block" }
local DEFAULT_WIDTH = 40

local function read_lines(path)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  return vim.fn.readfile(path)
end

local function diff(expected, actual)
  local out = {}
  for i = 1, math.max(#expected, #actual) do
    if expected[i] ~= actual[i] then
      out[#out + 1] = string.format(
        "line %d\n  expected: %s\n  actual:   %s",
        i,
        vim.inspect(expected[i]),
        vim.inspect(actual[i])
      )
    end
  end
  return table.concat(out, "\n")
end

local function serialize_spans(spans)
  local sorted = vim.deepcopy(spans)
  table.sort(sorted, function(a, b)
    if a.line ~= b.line then
      return a.line < b.line
    end
    if a.col_start ~= b.col_start then
      return a.col_start < b.col_start
    end
    if a.col_end ~= b.col_end then
      return a.col_end < b.col_end
    end
    return a.hl_group < b.hl_group
  end)
  local lines = {}
  for _, s in ipairs(sorted) do
    lines[#lines + 1] = string.format("%d %d %d %s", s.line, s.col_start, s.col_end, s.hl_group)
  end
  return lines
end

local function parse_spans(lines)
  local spans = {}
  for _, l in ipairs(lines) do
    local line, c1, c2, group = l:match("^(%d+) (%d+) (%d+) (%S+)$")
    spans[#spans + 1] =
      { line = tonumber(line), col_start = tonumber(c1), col_end = tonumber(c2), hl_group = group }
  end
  return spans
end

local function render_fixture(fmt, base)
  local width = tonumber((read_lines(base .. ".width") or {})[1]) or DEFAULT_WIDTH
  local frontend = require(frontends[fmt])
  return render.render(frontend.parse(read_lines(base .. ".in")), { width = width })
end

local function update(base, output)
  vim.fn.writefile(output.lines, base .. ".out")
  if #output.spans > 0 then
    vim.fn.writefile(serialize_spans(output.spans), base .. ".spans")
  else
    vim.fn.delete(base .. ".spans")
  end
end

local function check(base, output)
  local expected = read_lines(base .. ".out")
  assert.is_not_nil(expected, "missing " .. base .. ".out (run UPDATE_GOLDEN=1 make test-golden)")
  assert.is_true(
    vim.deep_equal(expected, output.lines),
    "golden mismatch:\n" .. diff(expected, output.lines)
  )
  local want = read_lines(base .. ".spans")
  if want then
    local got = serialize_spans(output.spans)
    assert.is_true(vim.deep_equal(want, got), "span mismatch:\n" .. diff(want, got))
  end
end

local function check_diagram_invariants(output, base)
  local width = tonumber((read_lines(base .. ".width") or {})[1]) or DEFAULT_WIDTH
  for _, l in ipairs(output.lines) do
    assert.is_true(text.width(l) <= width, base .. ": " .. l)
  end
end

describe("golden spans format", function()
  it("round-trips and sorts by line then column", function()
    local spans = {
      { line = 2, col_start = 0, col_end = 3, hl_group = "B" },
      { line = 1, col_start = 4, col_end = 6, hl_group = "A" },
      { line = 1, col_start = 0, col_end = 2, hl_group = "A" },
    }
    local lines = serialize_spans(spans)
    assert.same({ "1 0 2 A", "1 4 6 A", "2 0 3 B" }, lines)
    assert.same(lines, serialize_spans(parse_spans(lines)))
  end)
end)

local function check_table_invariants(output)
  local groups = {}
  for _, s in ipairs(output.spans) do
    groups[s.hl_group] = true
  end
  assert.is_true(groups.DocPreviewTableHeader and groups.DocPreviewTableBorder)
  for _, l in ipairs(output.lines) do
    assert.is_true(text.width(l) <= DEFAULT_WIDTH, l)
  end
end

local function check_image_invariants(output)
  local found = false
  for _, s in ipairs(output.spans) do
    found = found or s.hl_group == "DocPreviewImage"
  end
  assert.is_true(found)
  for _, l in ipairs(output.lines) do
    assert.is_true(text.width(l) <= DEFAULT_WIDTH, l)
  end
end

local function check_footnote_invariants(output, name)
  local found = false
  for _, s in ipairs(output.spans) do
    found = found or s.hl_group == "DocPreviewFootnoteRef"
  end
  assert.is_true(found)
  for _, l in ipairs(output.lines) do
    assert.is_true(text.width(l) <= DEFAULT_WIDTH, name .. ": " .. l)
  end
end

for fmt in pairs(frontends) do
  describe("golden " .. fmt, function()
    for _, input in ipairs(vim.fn.glob(root .. "/" .. fmt .. "/*.in", false, true)) do
      local base = input:sub(1, -4)
      it(vim.fn.fnamemodify(base, ":t"), function()
        local output = render_fixture(fmt, base)
        if vim.env.UPDATE_GOLDEN == "1" then
          update(base, output)
        else
          check(base, output)
        end
        if vim.fn.fnamemodify(base, ":t"):find("^table%-") then
          check_table_invariants(output)
        end
        local name = vim.fn.fnamemodify(base, ":t")
        if name:find("^mermaid%-flowchart%-") or name:find("^mermaid%-sequence%-") then
          check_diagram_invariants(output, base)
        end
        if vim.fn.fnamemodify(base, ":t"):find("^images%-") then
          check_image_invariants(output)
        end
        if vim.fn.fnamemodify(base, ":t"):find("^footnotes%-") then
          check_footnote_invariants(output, base)
        end
      end)
    end
  end)
end
