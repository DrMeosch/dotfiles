local M = {}

-- The `atc` theme switcher keeps "dark" or "light" in an untracked state file.
-- Neovim reads it at startup (atc switches running instances itself), so the
-- tracked config never changes when the theme does.
local colorschemes = {
  dark = "dracula",
  light = "github_light_colorblind",
}

function M.state_file()
  local dir = vim.env.XDG_CONFIG_HOME
  if not dir or dir == "" then
    dir = vim.fn.expand("~/.config")
  end
  return dir .. "/atc-theme"
end

-- The colorscheme for the current atc theme; dark when the file is missing,
-- unreadable or says anything else.
function M.colorscheme()
  local ok, lines = pcall(vim.fn.readfile, M.state_file(), "", 1)
  local theme = ok and lines[1] and vim.trim(lines[1]) or "dark"
  return colorschemes[theme] or colorschemes.dark
end

return M
