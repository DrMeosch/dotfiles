return {
  -- Run configured LSP servers inside the project devcontainer while Neovim stays on the host.
  {
    "jedrzejboczar/devcontainers.nvim",
    dependencies = {
      "stevearc/overseer.nvim", -- optional: view `devcontainer up` output as a task
    },
    opts = {},
  },
  -- Provide commands and a terminal for explicit devcontainer lifecycle and shell access.
  {
    "erichlf/devcontainer-cli.nvim",
    dependencies = { "akinsho/toggleterm.nvim" },
    init = function()
      require("devcontainer-cli").setup({
        interactive = false,
        toplevel = true,
        remove_existing_container = false,
        shell = "bash",
        nvim_binary = "nvim",
        log_level = "debug",
        console_level = "info",
        -- Optional dotfiles bootstrap for containers started by this plugin.
        -- dotfiles_repository = "https://github.com/<you>/dotfiles.git",
        -- dotfiles_installCommand = "install.sh",
      })
    end,
  }
}
