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
    -- By default the heading backgrounds link to the Diff* groups, which many
    -- themes (dracula among them) colour as foreground only or as a loud bar.
    -- Use a background-only tint of each heading's own colour instead, so every
    -- level gets a full-width background and keeps its text colour. Set in init
    -- because the colorscheme loads before this plugin does.
    init = function()
      local function tint_heading_backgrounds()
        local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
        if not normal.bg then
          return
        end
        local function channels(rgb)
          return math.floor(rgb / 65536) % 256, math.floor(rgb / 256) % 256, rgb % 256
        end
        local nr, ng, nb = channels(normal.bg)
        local mix = 0.2 -- share of the heading colour in its background
        for level = 1, 6 do
          local heading = vim.api.nvim_get_hl(0, { name = "@markup.heading." .. level .. ".markdown", link = false })
          if heading.fg then
            local r, g, b = channels(heading.fg)
            local function blend(fg, bg)
              return math.floor(bg + (fg - bg) * mix + 0.5)
            end
            local bg = string.format("#%02x%02x%02x", blend(r, nr), blend(g, ng), blend(b, nb))
            vim.api.nvim_set_hl(0, "RenderMarkdownH" .. level .. "Bg", { bg = bg })
          end
        end
      end
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("markdown_heading_backgrounds", { clear = true }),
        callback = tint_heading_backgrounds,
      })
      tint_heading_backgrounds()
    end,
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
