local config = require("doc_preview.config")
local doc_preview = require("doc_preview")
local text = require("doc_preview.core.text")

vim.cmd("runtime plugin/doc_preview.lua")

describe("DocPreview standalone mermaid file", function()
  after_each(function()
    doc_preview.close()
    config.setup({})
    pcall(vim.cmd, "only")
  end)

  local function open(lines, name, layout)
    vim.cmd("enew")
    local src = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(src, name or (vim.fn.tempname() .. ".mmd"))
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

  it("previews a .mmd buffer", function()
    local s = open({ "flowchart TD", "A[Start]" })
    assert.is_true(has(prev_lines(s), "│ Start │"))
  end)

  it("previews by filetype without a mermaid name", function()
    vim.cmd("enew")
    local src = vim.api.nvim_get_current_buf()
    vim.bo[src].filetype = "mermaid"
    vim.api.nvim_buf_set_lines(src, 0, -1, false, { "flowchart TD", "A[Hi]" })
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    assert.is_true(doc_preview.wait(s, 2000))
    assert.is_true(has(prev_lines(s), "│ Hi │"))
  end)

  it("re-renders after an edit", function()
    local s = open({ "flowchart TD", "A[Start]" })
    vim.api.nvim_buf_set_lines(s.src_buf, 0, -1, false, { "flowchart TD", "A[Changed]" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = s.src_buf })
    vim.wait(500, function()
      return has(prev_lines(s), "Changed")
    end)
    assert.is_true(doc_preview.wait(s, 2000))
    assert.is_true(has(prev_lines(s), "│ Changed │"))
  end)

  it("shows an errbox for a broken diagram", function()
    local s = open({ "gantt", "title x" })
    local lines = prev_lines(s)
    assert.is_true(has(lines, "gantt"))
    assert.is_true(has(lines, "┌"))
  end)

  it("shows an errbox for an empty buffer", function()
    local s = open({})
    assert.is_true(has(prev_lines(s), "┌"))
  end)

  it("maps every source line to the single diagram entry", function()
    local s = open({ "flowchart TD", "A[Start]", "", "%% c" })
    assert.equals(1, #s.output.map)
    local m = s.output.map[1]
    assert.equals(1, m.src_start)
    assert.equals(4, m.src_end)
  end)

  for _, layout in ipairs({ "vsplit", "hsplit", "replace" }) do
    it("works with layout " .. layout, function()
      local s = open({ "flowchart TD", "A[Start]" }, nil, layout)
      local lines = prev_lines(s)
      assert.is_true(has(lines, "│ Start │"))
      for _, l in ipairs(lines) do
        assert.is_true(text.width(l) <= s.width)
      end
    end)
  end

  it("keeps markdown for other buffers", function()
    local s = open({ "# T" }, vim.fn.tempname() .. ".md")
    assert.is_true(has(prev_lines(s), "T"))
    assert.is_false(has(prev_lines(s), "┌"))
  end)

  it("keeps the large-file guard", function()
    config.setup({ large_file_lines = 5 })
    local lines = { "flowchart TD" }
    for i = 1, 10 do
      lines[#lines + 1] = "N" .. i
    end
    local s = open(lines)
    local before = prev_lines(s)
    lines[2] = "Z[Zed]"
    vim.api.nvim_buf_set_lines(s.src_buf, 0, -1, false, lines)
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = s.src_buf })
    doc_preview.wait(s, 500)
    assert.same(before, prev_lines(s))
  end)
end)
