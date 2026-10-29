local M = {}

-- Root of the Git repository for the current buffer's file, falling back to the
-- working directory when the buffer has no file or lives outside any repository.
-- `.git` may be a file (linked worktrees, submodules), which vim.fs.root handles.
function M.get()
  local root = vim.fs.root(0, ".git") or vim.fs.root(vim.fn.getcwd(), ".git")
  if not root then
    vim.notify("Neither the current buffer nor the working directory is inside a Git repository", vim.log.levels.ERROR)
  end
  return root
end

return M
