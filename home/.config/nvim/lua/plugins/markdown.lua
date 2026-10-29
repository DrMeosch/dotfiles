-- Markdown reading setup on top of LazyVim's Markdown extra (imported in
-- config/lazy.lua): the extra adds the browser preview, the render toggle,
-- markdownlint and the marksman language server.
return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.icons" },
    -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
    ---@module 'render-markdown'
    ---@type render.md.UserConfig
    opts = {
      -- Keep the rendered view in every mode, also while editing in insert mode.
      render_modes = true,
      heading = { width = "full" },
    },
  },

  -- Browser preview: build the app with npm (node comes from Nix) instead of the
  -- extra's download of a prebuilt binary, which only exists for some platforms.
  {
    "iamcco/markdown-preview.nvim",
    build = "cd app && npm install",
    -- Print the preview URL, so it can be opened by hand if no browser opens (WSL).
    init = function()
      vim.g.mkdp_echo_preview_url = 1
    end,
  },

  -- marksman comes from Nix (home/common.nix), so Mason must not download it.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        marksman = { mason = false },
      },
    },
  },
}
