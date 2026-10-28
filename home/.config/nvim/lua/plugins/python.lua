return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        basedpyright = {
          cmd = require("devcontainers").lsp_cmd({
            "basedpyright-langserver",
            "--stdio",
          }),
        },
        ruff = {
          cmd = require("devcontainers").lsp_cmd({
            "ruff",
            "server",
          }),
        },
      },
    },
  },
}
