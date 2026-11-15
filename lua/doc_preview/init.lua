local config = require("doc_preview.config")
local session = require("doc_preview.session")

local M = {}

-- Keep in step with CHANGELOG.md and the git tag (see CLAUDE.md).
M.version = "0.1.0"

---@param opts? table
function M.setup(opts)
  config.setup(opts)
end

M.wait = session.wait

---@param buf? integer defaults to the current buffer
function M.session(buf)
  return session.get(buf or vim.api.nvim_get_current_buf())
end

local function notify_error(msg)
  vim.notify("DocPreview: " .. msg, vim.log.levels.ERROR)
end

-- Returns false (after reporting) for an invalid layout name.
local function valid_layout(layout)
  if layout == nil or vim.tbl_contains(config.layouts, layout) then
    return true
  end
  notify_error("invalid layout '" .. layout .. "', expected " .. table.concat(config.layouts, "|"))
  return false
end

---@param layout? string vsplit|hsplit|replace, overrides config for this session
function M.open(layout)
  if not valid_layout(layout) then
    return nil
  end
  local s = M.session()
  return session.open(s and s.src_buf or vim.api.nvim_get_current_buf(), layout)
end

function M.close()
  local s = M.session()
  if s then
    session.close(s)
  end
end

function M.toggle(layout)
  if M.session() then
    M.close()
  elseif valid_layout(layout) then
    M.open(layout)
  end
end

M.subcommands = { "open", "close", "toggle", "sync" }

---@param arg? string "on" or "off"
function M.sync(arg)
  if arg ~= "on" and arg ~= "off" then
    notify_error("sync expects 'on' or 'off'")
    return
  end
  local s = M.session()
  if not s then
    notify_error("no preview session for this buffer")
    return
  end
  require("doc_preview.sync").set_enabled(s, arg == "on")
end

---@param args string e.g. "open" or "sync off"
function M.command(args)
  local words = vim.split(vim.trim(args), "%s+")
  local name = words[1]
  if name == "" then
    M.toggle()
    return
  end
  if not vim.tbl_contains(M.subcommands, name) then
    notify_error("unknown subcommand '" .. name .. "'")
    return
  end
  M[name](words[2])
end

---@param lead string
---@param line string
function M.complete(lead, line)
  local words = vim.split(vim.trim(line), "%s+")
  local choices = M.subcommands
  if words[2] == "sync" and (#words > 2 or line:match("%s$")) then
    choices = { "on", "off" }
  elseif (words[2] == "open" or words[2] == "toggle") and (#words > 2 or line:match("%s$")) then
    choices = config.layouts
  end
  return vim.tbl_filter(function(c)
    return vim.startswith(c, lead)
  end, choices)
end

return M
