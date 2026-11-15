std = "lua51"
globals = { "vim", "bit" }
max_line_length = false -- line width is stylua's job
max_cyclomatic_complexity = 10 -- warning 561

files["tests/"] = {
  std = "+busted",
}
