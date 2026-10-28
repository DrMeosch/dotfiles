-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local themes = {
  { name = "Dracula", colorscheme = "dracula" },
  { name = "Gruvbox", colorscheme = "gruvbox" },
  { name = "GitHub Dark Colorblind", colorscheme = "github_dark_colorblind" },
  { name = "GitHub Light Colorblind", colorscheme = "github_light_colorblind" },
}

local function choose_theme()
  vim.ui.select(themes, {
    prompt = "Choose colorscheme",
    format_item = function(theme)
      return theme.name
    end,
  }, function(theme)
    if theme then
      vim.cmd.colorscheme(theme.colorscheme)
    end
  end)
end

vim.api.nvim_create_user_command("ThemeSwitch", choose_theme, {
  desc = "Choose a colorscheme",
})

vim.keymap.set("n", "<leader>uC", choose_theme, {
  desc = "Choose colorscheme",
})

local function open_git_worktree_in_neovide()
  local cwd = vim.fn.getcwd()
  local repo_root = vim.fn.system({ "git", "-C", cwd, "rev-parse", "--show-toplevel" }):gsub("%s+$", "")
  if vim.v.shell_error ~= 0 or repo_root == "" then
    vim.notify("The current directory is not inside a Git repository", vim.log.levels.ERROR)
    return
  end

  local output = vim.fn.systemlist({ "git", "-C", repo_root, "worktree", "list", "--porcelain" })
  if vim.v.shell_error ~= 0 then
    vim.notify("Unable to list Git worktrees", vim.log.levels.ERROR)
    return
  end

  local worktrees = {}
  local current
  local function finish_worktree()
    if current then
      current.display = string.format("%-24s %s", current.branch, current.path)
      table.insert(worktrees, current)
      current = nil
    end
  end

  for _, field in ipairs(output) do
    if vim.startswith(field, "worktree ") then
      finish_worktree()
      current = { path = field:sub(#"worktree " + 1), branch = "detached" }
    elseif current and vim.startswith(field, "branch ") then
      current.branch = field:sub(#"branch " + 1):gsub("^refs/heads/", "")
    end
  end
  finish_worktree()

  if #worktrees == 0 then
    vim.notify("No Git worktrees found", vim.log.levels.WARN)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers
    .new({}, {
      prompt_title = "Git worktrees → Neovide",
      finder = finders.new_table({
        results = worktrees,
        entry_maker = function(item)
          return {
            value = item,
            display = item.display,
            ordinal = item.branch .. " " .. item.path,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if not selection then
            return
          end

          local neovide = vim.g.neovide_worktree_command or "neovide"
          if vim.fn.executable(neovide) ~= 1 then
            vim.notify(
              "Neovide is not executable from this Neovim environment: " .. neovide,
              vim.log.levels.ERROR
            )
            return
          end

          vim.notify("Opening " .. selection.value.path .. " in Neovide")
          local job_id = vim.fn.jobstart({ neovide, selection.value.path }, {
            detach = true,
            stdin = "null",
            cwd = selection.value.path,
            on_exit = function(_, exit_code)
              if exit_code ~= 0 then
                vim.schedule(function()
                  vim.notify(
                    string.format("Neovide exited with status %d. Check vim.g.neovide_worktree_command", exit_code),
                    vim.log.levels.ERROR
                  )
                end)
              end
            end,
          })
          if job_id <= 0 then
            vim.notify(
              "Unable to start Neovide. Set vim.g.neovide_worktree_command to a command visible in this container",
              vim.log.levels.ERROR
            )
          end
        end)
        return true
      end,
    })
    :find()
end

vim.api.nvim_create_user_command("GitWorktreeNeovide", open_git_worktree_in_neovide, {
  desc = "Select a Git worktree and open it in a new Neovide window",
})

vim.keymap.set("n", "<leader>gw", open_git_worktree_in_neovide, {
  desc = "Select Git worktree in a new Neovide window",
})
