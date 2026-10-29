local function open_neogit()
  local repo_root = require("config.git_root").get()
  if repo_root then
    require("neogit").open({ cwd = repo_root })
  end
end

local function fetch_and_open_branches()
  local repo_root = require("config.git_root").get()
  if not repo_root then
    return
  end

  vim.notify("Fetching origin...", vim.log.levels.INFO)

  vim.system({ "git", "fetch", "origin", "--prune" }, { cwd = repo_root, text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local message = vim.trim(result.stderr or result.stdout or "git fetch failed")
        vim.notify("Git fetch failed: " .. message, vim.log.levels.ERROR)
        return
      end

      vim.notify("Remote branches updated", vim.log.levels.INFO)
      require("neogit").open({ "branch", cwd = repo_root })
    end)
  end)
end

return {
  {
    "NeogitOrg/neogit",
    cmd = "Neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
    },
    opts = {
      auto_refresh = true,
      filewatcher = { enabled = true },
      integrations = {
        diffview = true,
      },
    },
    keys = {
      { "<leader>gg", open_neogit, desc = "Open Neogit" },
      {
        "<leader>gb",
        fetch_and_open_branches,
        desc = "Fetch and switch Git branch",
      },
    },
  },
}
