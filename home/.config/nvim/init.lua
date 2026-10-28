-- bootstrap lazy.nvim, LazyVim and your plugins
local run_dir = vim.fn.stdpath("run")
vim.fn.mkdir(run_dir, "p")
vim.fn.serverstart(run_dir .. "/nvim-" .. vim.fn.getpid() .. ".sock")

if vim.g.neovide then
  require("config.neovide")
end

require("config.lazy")
