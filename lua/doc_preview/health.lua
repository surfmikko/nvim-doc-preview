local config = require("doc_preview.config")

local M = {}

local function check_nvim()
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim >= 0.10")
  else
    vim.health.error("Neovim 0.10 or newer is required")
  end
end

local function check_command()
  if vim.fn.exists(":DocPreview") == 2 then
    vim.health.ok(":DocPreview command is registered")
  else
    vim.health.error(":DocPreview is not registered", "Is the plugin on 'runtimepath'?")
  end
end

local function check_encoding()
  if config.options.charset == "ascii" or vim.o.encoding == "utf-8" then
    vim.health.ok("charset '" .. config.options.charset .. "' matches 'encoding'")
  else
    vim.health.warn(
      "charset 'unicode' needs 'encoding' utf-8, got '" .. vim.o.encoding .. "'",
      { "set encoding=utf-8", 'or use setup({ charset = "ascii" })' }
    )
  end
end

local function check_config()
  local ok, err = pcall(config.setup, vim.deepcopy(config.options))
  if ok then
    vim.health.ok("configuration is valid")
  else
    vim.health.error(tostring(err))
  end
end

function M.check()
  vim.health.start("doc_preview")
  vim.health.info("version " .. require("doc_preview").version)
  check_nvim()
  check_command()
  check_encoding()
  check_config()
end

return M
