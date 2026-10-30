return {
  {
    "Mofiqul/dracula.nvim",
    lazy = false,
    priority = 1000,
  },
  {
    "projekt0n/github-nvim-theme",
    name = "github-theme",
    lazy = false,
    priority = 1000,
    opts = {
      options = {
        terminal_colors = true,
        transparent = false,
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = require("config.atc_theme").colorscheme(),
    },
  },
}
