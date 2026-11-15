local config = require("doc_preview.config")

local function rejects(opts, ...)
  local ok, err = pcall(config.setup, opts)
  assert.is_false(ok)
  for _, part in ipairs({ ... }) do
    assert.is_truthy(err:find(part, 1, true), err)
  end
end

describe("config", function()
  after_each(function()
    config.setup({})
  end)

  it("has the documented defaults", function()
    config.setup({})
    local o = config.options
    assert.equals(150, o.debounce_ms)
    assert.equals(8, o.slice_ms)
    assert.equals(100, o.max_width)
    assert.equals(5000, o.large_file_lines)
    assert.equals("vsplit", o.layout)
    assert.equals("unicode", o.charset)
    assert.same({ cursor = true, scroll = true }, o.sync)
    assert.same({ mermaid = true }, o.engines)
    assert.same({ close = "q" }, o.keymaps)
  end)

  it("merges nested tables with defaults", function()
    config.setup({ keymaps = { close = "x" }, sync = { scroll = false } })
    assert.same({ close = "x" }, config.options.keymaps)
    assert.same({ cursor = true, scroll = false }, config.options.sync)
  end)

  it("rejects invalid values naming key and allowed values", function()
    rejects({ debounce_ms = "x" }, "debounce_ms", "a number >= 0")
    rejects({ slice_ms = -1 }, "slice_ms", "a number >= 0")
    rejects({ max_width = 0 }, "max_width", "a number >= 1")
    rejects({ charset = "latin" }, "charset", "unicode|ascii", "latin")
    rejects({ auto_open = true }, "auto_open", "valid keys")
    rejects({ sync = { cursor = "yes" } }, "sync.cursor", "a boolean")
    rejects({ sync = true }, "sync", "a table")
    rejects({ engines = { mermaid = 0 } }, "engines.mermaid", "a boolean")
    rejects({ engines = { d2 = true } }, "engines.d2", "valid keys: mermaid")
    rejects({ keymaps = { close = "" } }, "keymaps.close", "non-empty string or false")
    rejects({ keymaps = { toggle = "<leader>p" } }, "keymaps.toggle", "valid keys: close")
  end)

  it("accepts the three layout names and rejects others", function()
    for _, name in ipairs({ "vsplit", "hsplit", "replace" }) do
      config.setup({ layout = name })
      assert.equals(name, config.options.layout)
    end
    rejects({ layout = "tab" }, "layout", "vsplit|hsplit|replace", "tab")
  end)

  it("rejects unknown keys listing the valid ones", function()
    rejects({ nope = 1 }, "nope", "layout", "keymaps")
    rejects({ keymaps = { nope = "x" } }, "keymaps.nope", "valid keys: close")
    rejects(
      { keymaps = { jump_to_source = "<CR>" } },
      "keymaps.jump_to_source",
      "valid keys: close"
    )
  end)

  it("reports the split to layout migration", function()
    rejects({ split = "right" }, "'split' was renamed to 'layout'", "vsplit|hsplit|replace")
  end)

  it("keeps previous options when setup is rejected", function()
    config.setup({ max_width = 60 })
    rejects({ max_width = 70, charset = "bad" }, "charset")
    assert.equals(60, config.options.max_width)
  end)

  it("validates large_file_lines", function()
    config.setup({ large_file_lines = 20 })
    assert.equals(20, config.options.large_file_lines)
    for _, bad in ipairs({ 0, "x", false }) do
      local msg = "large_file_lines must be a number >= 1, got " .. vim.inspect(bad)
      rejects({ large_file_lines = bad }, msg)
    end
    assert.equals(20, config.options.large_file_lines)
  end)

  it("accepts explicit keymaps", function()
    config.setup({ keymaps = { close = "Q" } })
    assert.same({ close = "Q" }, config.options.keymaps)
    config.setup({ keymaps = { close = false } })
    assert.is_false(config.options.keymaps.close)
  end)

  it("treats keymaps = false as all off", function()
    config.setup({ keymaps = false })
    assert.same({ close = false }, config.options.keymaps)
  end)

  it("rejects other non-table keymaps naming the option", function()
    rejects({ keymaps = "no" }, "keymaps", "table")
    rejects({ keymaps = true }, "keymaps", "table")
    rejects({ keymaps = 1 }, "keymaps", "table")
  end)
end)
