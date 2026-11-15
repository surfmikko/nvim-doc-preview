local config = require("doc_preview.config")
local doc_preview = require("doc_preview")
local render = require("doc_preview.document.render")
local text = require("doc_preview.core.text")

vim.cmd("runtime plugin/doc_preview.lua")

local BODY = {
  "sequenceDiagram",
  "participant A as Alice",
  "A->>+B: Hello Bob",
  "Note right of B: thinks",
  "B-->>-A: Hi",
}

local function fenced(body)
  local lines = { "before", "", "```mermaid" }
  vim.list_extend(lines, body)
  vim.list_extend(lines, { "```", "", "after" })
  return lines
end

describe("DocPreview mermaid sequence", function()
  after_each(function()
    render.test_hook = nil
    doc_preview.close()
    config.setup({})
    pcall(vim.cmd, "only")
  end)

  local function open(lines, name)
    vim.cmd("enew")
    local src = vim.api.nvim_get_current_buf()
    if name then
      vim.api.nvim_buf_set_name(src, vim.fn.tempname() .. name)
    end
    vim.api.nvim_buf_set_lines(src, 0, -1, false, lines)
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    assert.is_true(doc_preview.wait(s, 2000))
    vim.wait(50)
    return s, src
  end

  local function joined(s)
    return table.concat(vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false), "\n")
  end

  local function assert_fits(s)
    for _, l in ipairs(vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)) do
      assert.is_true(text.width(l) <= s.width, l)
    end
  end

  it("renders a fenced sequence block", function()
    local s = open(fenced(BODY))
    local out = joined(s)
    assert.is_truthy(out:find("│ Alice │", 1, true))
    assert.is_truthy(out:find("Hello Bob", 1, true))
    assert.is_truthy(out:find("▶", 1, true))
    assert.is_truthy(out:find("│ thinks │", 1, true))
    assert.is_truthy(out:find("after", 1, true))
    assert_fits(s)
  end)

  it("renders a .mmd file and re-renders after an edit", function()
    local s, src = open(BODY, ".mmd")
    assert.is_truthy(joined(s):find("Hello Bob", 1, true))
    vim.api.nvim_buf_set_lines(src, 2, 3, false, { "A->>+B: Changed text" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = src })
    vim.wait(2000, function()
      return joined(s):find("Changed text", 1, true) ~= nil
    end)
    assert.is_truthy(joined(s):find("Changed text", 1, true))
    assert_fits(s)
  end)

  it("shows the errbox for a broken sequence diagram", function()
    local s = open(fenced({ "sequenceDiagram", "nonsense" }))
    assert.is_truthy(joined(s):find("nonsense", 1, true))
  end)

  it("fits a narrow preview window", function()
    local s = open(fenced(BODY))
    vim.api.nvim_win_set_width(s.prev_win, 30)
    vim.api.nvim_exec_autocmds("VimResized", {})
    vim.wait(500, function()
      return s.width == 30
    end)
    assert.is_true(doc_preview.wait(s, 2000))
    assert_fits(s)
    assert.is_truthy(joined(s):find("Hello", 1, true))
  end)
end)
