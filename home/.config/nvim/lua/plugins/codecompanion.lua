-- AI chat and inline editing with CodeCompanion. The backends, and the hotkeys to
-- switch between them and to change model and effort, live in config/codecompanion.lua.
-- Nothing about an endpoint is stored in this repo, see the README for the variables.
local function ai(name)
  return function()
    require("config.codecompanion")[name]()
  end
end

return {
  {
    "olimorris/codecompanion.nvim",
    version = "^19.0.0",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions", "CodeCompanionCmd" },
    opts = function()
      local backends = require("config.codecompanion")
      local default = backends.backends[1]
      return {
        adapters = backends.adapters,
        interactions = {
          chat = { adapter = default },
          inline = { adapter = default },
          cmd = { adapter = default },
        },
      }
    end,
    keys = {
      { "<leader>a", "", desc = "+ai", mode = { "n", "v" } },
      { "<leader>aa", "<cmd>CodeCompanionActions<cr>", desc = "Actions", mode = { "n", "v" } },
      { "<leader>ac", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle chat", mode = { "n", "v" } },
      { "<leader>ai", ":CodeCompanion ", desc = "Inline prompt", mode = { "n", "v" } },
      { "<leader>as", "<cmd>CodeCompanionChat Add<cr>", desc = "Add selection to chat", mode = "v" },
      { "<leader>ab", ai("switch_backend"), desc = "Switch backend" },
      { "<leader>am", ai("pick_model"), desc = "Change model" },
      { "<leader>ae", ai("pick_effort"), desc = "Change reasoning effort" },
    },
  },

  -- Only here for the sign-in: `:Copilot auth` stores the token that CodeCompanion's
  -- copilot adapter reads. Inline suggestions are not wanted.
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    opts = {
      suggestion = { enabled = false },
      panel = { enabled = false },
    },
  },
}
