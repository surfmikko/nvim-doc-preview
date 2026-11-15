local M = {}

M.layouts = { "vsplit", "hsplit", "replace" }

M.defaults = {
  debounce_ms = 150,
  slice_ms = 8,
  large_file_lines = 5000, -- over this, refresh on save only
  max_width = 100, -- hard-wrap width = min(window width, max_width)
  layout = "vsplit", -- vsplit|hsplit|replace
  charset = "unicode", -- unicode|ascii
  sync = { cursor = true, scroll = true },
  engines = { mermaid = true }, -- false shows the block as plain code
  keymaps = { close = "q" }, -- lhs or false; preview-local
}

M.options = vim.deepcopy(M.defaults)

local function is_bool(v)
  return type(v) == "boolean"
end

local function is_number_min(min)
  return function(v)
    return type(v) == "number" and v >= min
  end
end

local function one_of(...)
  local names = { ... }
  return function(v)
    return vim.tbl_contains(names, v)
  end
end

local function is_keymap(v)
  return v == false or (type(v) == "string" and v ~= "")
end

local function bool_fields(...)
  local fields = {}
  for _, name in ipairs({ ... }) do
    fields[name] = { check = is_bool, allowed = "a boolean" }
  end
  return fields
end

local KEYMAP = { check = is_keymap, allowed = "a non-empty string or false" }

-- An entry is a leaf ({check, allowed}) or a group ({fields}).
local schema = {
  debounce_ms = { check = is_number_min(0), allowed = "a number >= 0" },
  slice_ms = { check = is_number_min(0), allowed = "a number >= 0" },
  large_file_lines = { check = is_number_min(1), allowed = "a number >= 1" },
  max_width = { check = is_number_min(1), allowed = "a number >= 1" },
  layout = { check = one_of(unpack(M.layouts)), allowed = "vsplit|hsplit|replace" },
  charset = { check = one_of("unicode", "ascii"), allowed = "unicode|ascii" },
  sync = { fields = bool_fields("cursor", "scroll") },
  engines = { fields = bool_fields("mermaid") },
  keymaps = {
    fields = { close = KEYMAP },
    allowed = "a table (or false for none)",
  },
}

local function fail(key, allowed, value)
  error(("doc_preview.setup: %s must be %s, got %s"):format(key, allowed, vim.inspect(value)), 0)
end

local function sorted_keys(t)
  local keys = vim.tbl_keys(t)
  table.sort(keys)
  return keys
end

local function fail_unknown(key, entries, prefix)
  if prefix == "" and key == "split" then
    error("doc_preview.setup: 'split' was renamed to 'layout' (vsplit|hsplit|replace)", 0)
  end
  local msg = "doc_preview.setup: unknown key %s, valid keys: %s"
  error(msg:format(prefix .. tostring(key), table.concat(sorted_keys(entries), ", ")), 0)
end

local function validate(entries, opts, prefix)
  for key, value in pairs(opts) do
    local entry = entries[key]
    if not entry then
      fail_unknown(key, entries, prefix)
    end
    if entry.fields then
      if type(value) ~= "table" then
        fail(prefix .. key, entry.allowed or "a table", value)
      end
      validate(entry.fields, value, prefix .. key .. ".")
    elseif not entry.check(value) then
      fail(prefix .. key, entry.allowed, value)
    end
  end
end

--- Raises on invalid options; a rejected call leaves M.options untouched.
function M.setup(opts)
  opts = opts or {}
  if opts.keymaps == false then
    opts = vim.tbl_extend("force", opts, { keymaps = { close = false } })
  end
  validate(schema, opts, "")
  M.options = vim.tbl_deep_extend("force", M.defaults, opts)
end

return M
