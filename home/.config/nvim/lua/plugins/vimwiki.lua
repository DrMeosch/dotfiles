return {
  {
    -- The plugin location on GitHub
    "vimwiki/vimwiki",
    -- The event that triggers the plugin
    -- event = "BufEnter *.md",
    -- The keys that trigger the plugin
    -- keys = { "<leader>ww", "<leader>wt" },
    -- The configuration for the plugin
    init = function()
      vim.g.vimwiki_list = {
        {
          -- Here will be the path for your wiki
          path = "~/vimwiki/",
          -- The syntax for the wiki
          syntax = "markdown",
          ext = "md",
        },
      }
      -- Only files under the wiki path above are vimwiki files. With the default
      -- (1) every .md file anywhere would open as vimwiki, and render-markdown
      -- and LazyVim's Markdown settings would not apply to it.
      vim.g.vimwiki_global_ext = 0
      vim.g.vimwiki_ext2syntax ={ [".md"] = "markdown", [".markdown"] = "markdown", [".mdown"] = "markdown" }
      vim.g.vimwiki_use_mouse = 1
      vim.g.vimwiki_markdown_link_ext = 1
    end,
  },
}
