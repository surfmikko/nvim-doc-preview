local doc_preview = require("doc_preview")

vim.cmd("runtime plugin/doc_preview.lua")

local src_lines = {
  "before", -- 1
  "", -- 2
  "![logo](logo.png)", -- 3
  "", -- 4
  "![a very long alternative text that must wrap over several rows](long.png)", -- 5
  "", -- 6
  "inline ![pic](p.png) here", -- 7
  "", -- 8
  "after", -- 9
}

describe("DocPreview images", function()
  after_each(function()
    pcall(vim.cmd, "only")
  end)

  local function open()
    vim.o.columns = 80
    vim.cmd("enew")
    local src = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(src, 0, -1, false, src_lines)
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    assert.is_true(doc_preview.wait(s, 2000))
    vim.wait(50)
    return s
  end

  local function find(lines, pattern)
    for i, l in ipairs(lines) do
      if l:find(pattern, 1, true) then
        return i
      end
    end
  end

  local function to_preview(s, row)
    vim.api.nvim_win_set_cursor(s.src_win, { row, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.src_buf })
    return vim.api.nvim_win_get_cursor(s.prev_win)[1]
  end

  local function to_source(s, row)
    vim.api.nvim_set_current_win(s.prev_win)
    vim.api.nvim_win_set_cursor(s.prev_win, { row, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.prev_buf })
    return vim.api.nvim_win_get_cursor(s.src_win)[1]
  end

  it("renders placeholders with DocPreviewImage extmarks", function()
    local s = open()
    local lines = vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)
    assert.is_truthy(find(lines, "[image: logo]"))
    assert.is_truthy(find(lines, "inline [image: pic] here"))
    local rows = {}
    for _, id in pairs(vim.api.nvim_get_namespaces()) do
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(s.prev_buf, id, 0, -1, { details = true })) do
        if m[4].hl_group == "DocPreviewImage" then
          rows[m[2] + 1] = true
        end
      end
    end
    assert.is_true(rows[find(lines, "[image: logo]")])
    assert.is_true(rows[find(lines, "inline")])
    assert.is_true(rows[find(lines, "that must wrap")])
    doc_preview.close()
  end)

  it("maps source lines to image rows and back, including wrapped rows", function()
    local s = open()
    local lines = vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)
    local logo = find(lines, "[image: logo]")
    local first = find(lines, "[image: a very long")
    local last = find(lines, "that must wrap")
    assert.is_true(last > first)
    assert.equals(logo, to_preview(s, 3))
    assert.equals(first, to_preview(s, 5))
    assert.equals(find(lines, "inline"), to_preview(s, 7))
    assert.equals(3, to_source(s, logo))
    for row = first, last do
      assert.equals(5, to_source(s, row))
    end
    doc_preview.close()
  end)
end)
