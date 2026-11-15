local config = require("doc_preview.config")
local doc_preview = require("doc_preview")
local job = require("doc_preview.core.job")
local render = require("doc_preview.document.render")
local session = require("doc_preview.session")
local text = require("doc_preview.core.text")

vim.cmd("runtime plugin/doc_preview.lua")

local CHAIN = { "flowchart LR", "A[Alpha] -->|go| B[Beta] --> C[Gamma] --> D[Delta]" }

local function fenced(body)
  local lines = { "before", "", "```mermaid" }
  vim.list_extend(lines, body)
  vim.list_extend(lines, { "```", "", "after" })
  return lines
end

describe("DocPreview mermaid flowchart", function()
  after_each(function()
    render.test_hook = nil
    doc_preview.close()
    config.setup({})
    pcall(vim.cmd, "only")
  end)

  local function open(lines, name, layout)
    vim.cmd("enew")
    local src = vim.api.nvim_get_current_buf()
    if name then
      vim.api.nvim_buf_set_name(src, vim.fn.tempname() .. name)
    end
    vim.api.nvim_buf_set_lines(src, 0, -1, false, lines)
    vim.cmd("DocPreview open" .. (layout and (" " .. layout) or ""))
    local s = doc_preview.session(src)
    assert.is_true(doc_preview.wait(s, 2000))
    vim.wait(50)
    return s
  end

  local function prev_lines(s)
    return vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)
  end

  local function has(lines, str)
    return table.concat(lines, "\n"):find(str, 1, true) ~= nil
  end

  local function assert_fits(s)
    for _, l in ipairs(prev_lines(s)) do
      assert.is_true(text.width(l) <= s.width, l)
    end
  end

  local function resize(s, n)
    vim.api.nvim_win_set_width(s.prev_win, n)
    vim.api.nvim_exec_autocmds("VimResized", {})
    vim.wait(500, function()
      return session.width(s) == n and s.width == n
    end)
    assert.is_true(doc_preview.wait(s, 2000))
  end

  for _, layout in ipairs({ "vsplit", "hsplit", "replace" }) do
    it("renders a fenced block and a .mmd file with layout " .. layout, function()
      local s = open(fenced({ "flowchart TD", "A[Start] --> B[End]" }), nil, layout)
      assert.is_true(has(prev_lines(s), "│ Start │"))
      assert.is_true(has(prev_lines(s), "│ End │"))
      assert_fits(s)
      doc_preview.close()
      s = open({ "flowchart TD", "A[Start] --> B[End]" }, ".mmd", layout)
      assert.is_true(has(prev_lines(s), "▼"))
      assert_fits(s)
    end)
  end

  it("re-applies the width fallbacks on resize", function()
    local s = open(fenced(CHAIN), nil, "vsplit")
    resize(s, 70)
    assert.is_true(has(prev_lines(s), "▶"), "left to right at 70")
    resize(s, 30)
    assert_fits(s)
    assert.is_false(has(prev_lines(s), "▶ "), "top-down at 30")
    assert.is_true(has(prev_lines(s), "▼"))
    resize(s, 8)
    assert_fits(s)
    assert.is_false(has(prev_lines(s), "▼"), "boxed source at 8")
    assert.is_true(has(prev_lines(s), "flow"))
    resize(s, 70)
    assert.is_true(has(prev_lines(s), "▶"), "fallback undone when wide again")
  end)

  it("re-renders a .mmd file with the fallback after an edit", function()
    local s = open({ "flowchart TD", "A[Start]" }, ".mmd", "vsplit")
    resize(s, 30)
    vim.api.nvim_buf_set_lines(s.src_buf, 0, -1, false, CHAIN)
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = s.src_buf })
    vim.wait(500, function()
      return has(prev_lines(s), "Alpha")
    end)
    assert.is_true(doc_preview.wait(s, 2000))
    assert.is_true(has(prev_lines(s), "▼"))
    assert_fits(s)
  end)

  it("a render running during edits is cancelled and stale output is never applied", function()
    render.test_hook = function(node)
      if node.kind == "paragraph" and node.inlines[1].value == "before" then
        local stop = vim.uv.hrtime() + 400e6
        while vim.uv.hrtime() < stop do
          job.yield_point()
        end
      end
    end
    local s = open(fenced({ "flowchart TD", "A[Old]" }), nil, "vsplit")
    local function edit(label)
      vim.api.nvim_buf_set_lines(
        s.src_buf,
        0,
        -1,
        false,
        fenced({ "flowchart TD", "A[" .. label .. "]" })
      )
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = s.src_buf })
    end
    edit("First")
    assert.is_true(vim.wait(1000, function()
      return s.job ~= nil
    end, 5))
    local first = s.job
    vim.wait(60)
    edit("Second")
    assert.is_true(first.cancelled)
    render.test_hook = nil
    assert.is_true(doc_preview.wait(s, 5000))
    assert.is_true(has(prev_lines(s), "Second"))
    assert.is_false(has(prev_lines(s), "First"))
  end)
end)
