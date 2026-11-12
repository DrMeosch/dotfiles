-- AI chat and inline editing with CodeCompanion. It stays off, not even loaded, until a backend
-- is picked with <leader>ab. The backends and the hotkeys live in config/codecompanion.lua.
-- Nothing about an endpoint is stored in this repo, see the README for the variables.
local function ai()
  return require("config.codecompanion")
end

-- An expression hotkey that types `keys`, and only while a backend is on.
local function typed(keys)
  return function()
    if ai().active() then
      return keys
    end
    vim.schedule(ai().warn_off)
    return ""
  end
end

return {
  {
    "olimorris/codecompanion.nvim",
    version = "^19.0.0",
    -- No cmd or keys: only picking a backend loads it.
    lazy = true,
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    init = function()
      local function map(lhs, rhs, desc, mode, opts)
        vim.keymap.set(mode or "n", lhs, rhs, vim.tbl_extend("force", { desc = desc }, opts or {}))
      end
      local expr = { expr = true }
      map("<leader>ab", function()
        ai().pick_backend()
      end, "Pick backend")
      map("<leader>aa", typed("<cmd>CodeCompanionActions<cr>"), "Actions", { "n", "v" }, expr)
      map("<leader>ac", typed("<cmd>CodeCompanionChat Toggle<cr>"), "Toggle chat", { "n", "v" }, expr)
      map("<leader>ai", typed(":CodeCompanion "), "Inline prompt", { "n", "v" }, expr)
      map("<leader>as", typed("<cmd>CodeCompanionChat Add<cr>"), "Add selection to chat", "v", expr)
      map(
        "<leader>am",
        ai().when_active(function()
          ai().pick_model()
        end),
        "Change model"
      )
      map(
        "<leader>ae",
        ai().when_active(function()
          ai().pick_effort()
        end),
        "Change reasoning effort"
      )
    end,
    opts = function()
      local backends = ai()
      return {
        adapters = backends.adapters,
        interactions = backends.interactions(),
      }
    end,
  },

  { "folke/which-key.nvim", opts = { spec = { { "<leader>a", group = "ai", mode = { "n", "v" } } } } },

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
