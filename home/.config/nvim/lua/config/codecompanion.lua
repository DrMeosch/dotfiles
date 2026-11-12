-- CodeCompanion backends and the hotkeys that drive them (see plugins/codecompanion.lua).
--
-- CodeCompanion is off until a backend is picked with pick_backend(), nothing is loaded or
-- contacted before that. Five backends exist, the picker lists the ones that are configured:
--   claude_code       Claude through the Claude Code CLI over ACP, on the local Claude subscription login
--   anthropic_litellm the Anthropic Messages API, e.g. the /v1/messages route of a LiteLLM gateway
--   openai            OpenAI directly, with an API key
--   openai_litellm    any OpenAI-compatible chat completions endpoint, e.g. a LiteLLM gateway
--   copilot           GitHub Copilot (Business included), signed in once with :Copilot auth
-- Hosts, keys and model names come only from the environment, see the README.
local M = {}

local function set(...)
  for _, name in ipairs({ ... }) do
    if (vim.env[name] or "") == "" then
      return false
    end
  end
  return true
end

-- The OAuth token that `:Copilot auth` leaves behind, searched where CodeCompanion looks for it.
local function copilot_signed_in()
  local root = vim.env.CODECOMPANION_TOKEN_PATH
  if (root or "") == "" then
    root = vim.fs.normalize(vim.env.XDG_CONFIG_HOME or "~/.config")
  end
  for _, file in ipairs({ "hosts.json", "apps.json" }) do
    local ok, lines = pcall(vim.fn.readfile, vim.fs.joinpath(root, "github-copilot", file))
    if ok and table.concat(lines, "\n"):find("oauth_token", 1, true) then
      return true
    end
  end
  return false
end

-- In picker order. `ready` says whether the backend is configured here, without touching the
-- network or loading CodeCompanion. Only `http` backends serve inline edits and commands.
M.backends = {
  {
    name = "claude_code",
    label = "Anthropic - Claude subscription (Claude Code)",
    type = "acp",
    ready = function()
      return vim.fn.executable("claude") == 1 and vim.fn.executable("claude-agent-acp") == 1
    end,
  },
  {
    name = "anthropic_litellm",
    label = "Anthropic - LiteLLM and API key",
    type = "http",
    ready = function()
      return set("CODECOMPANION_ANTHROPIC_BASE_URL", "CODECOMPANION_ANTHROPIC_API_KEY")
    end,
  },
  {
    name = "openai",
    label = "OpenAI - API key",
    type = "http",
    ready = function()
      return set("OPENAI_API_KEY")
    end,
  },
  {
    name = "openai_litellm",
    label = "OpenAI - LiteLLM and API key",
    type = "http",
    ready = function()
      return set("CODECOMPANION_BASE_URL", "CODECOMPANION_API_KEY")
    end,
  },
  { name = "copilot", label = "GitHub Copilot", type = "http", ready = copilot_signed_in },
}

local EFFORTS = { "low", "medium", "high", "max" }
local MODEL_CACHE_SECONDS = 1800
local MODEL_RETRY_SECONDS = 60

-- Reasoning effort for the HTTP backends, nil sends nothing. Read on every request, so
-- changing it applies to chats that are already open.
local effort

local function env(name)
  return function()
    return vim.env[name] or ""
  end
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "CodeCompanion" })
end

-- Ids served by an Anthropic-compatible gateway in listing order, from the last successful listing.
-- A failed listing is retried after MODEL_RETRY_SECONDS, a successful one after MODEL_CACHE_SECONDS.
local models_cache = { ids = {}, expires = 0 }
local function anthropic_model_ids()
  local base = vim.env.CODECOMPANION_ANTHROPIC_BASE_URL or ""
  if base == "" or os.time() < models_cache.expires then
    return models_cache.ids
  end

  models_cache.expires = os.time() + MODEL_RETRY_SECONDS
  local key = vim.env.CODECOMPANION_ANTHROPIC_API_KEY or ""
  local ok, response = pcall(require("plenary.curl").get, base .. "/v1/models", {
    headers = {
      ["x-api-key"] = key,
      Authorization = "Bearer " .. key,
      ["anthropic-version"] = "2023-06-01",
    },
    timeout = 3000,
    -- An unreachable gateway is not an error here, plenary would raise one from its job callback.
    on_error = function() end,
  })
  if not (ok and response and response.status == 200) then
    return models_cache.ids
  end
  local decoded, json = pcall(vim.json.decode, response.body)
  if not (decoded and type(json) == "table" and type(json.data) == "table") then
    return models_cache.ids
  end

  local ids = {}
  for _, model in ipairs(json.data) do
    if type(model) == "table" and type(model.id) == "string" then
      table.insert(ids, model.id)
    end
  end
  models_cache = { ids = ids, expires = os.time() + MODEL_CACHE_SECONDS }
  return ids
end

-- The listed ids plus the configured model, as a CodeCompanion model choice map.
local function anthropic_models()
  local choices = {}
  local ids = vim.list_extend({ vim.env.CODECOMPANION_ANTHROPIC_MODEL or "" }, anthropic_model_ids())
  for _, id in ipairs(ids) do
    if id ~= "" then
      choices[id] = { formatted_name = id, opts = { has_vision = true } }
    end
  end
  return choices
end

local function wrap_form_parameters(adapter_name, apply)
  local base = require("codecompanion.adapters.http." .. adapter_name).handlers.form_parameters
  return function(self, params, messages)
    params = base(self, params, messages)
    if effort then
      apply(params)
    end
    return params
  end
end

M.adapters = {
  http = {
    openai = function()
      local model = vim.env.CODECOMPANION_OPENAI_MODEL or ""
      return require("codecompanion.adapters").extend("openai", {
        handlers = {
          form_parameters = wrap_form_parameters("openai", function(params)
            -- Chat completions know low, medium and high.
            params.reasoning_effort = effort == "max" and "high" or effort
          end),
        },
        schema = model ~= "" and { model = { default = model } } or nil,
      })
    end,

    openai_litellm = function()
      local model = vim.env.CODECOMPANION_MODEL or ""
      return require("codecompanion.adapters").extend("openai_compatible", {
        formatted_name = "OpenAI via LiteLLM",
        env = { url = env("CODECOMPANION_BASE_URL"), api_key = env("CODECOMPANION_API_KEY") },
        handlers = {
          form_parameters = wrap_form_parameters("openai_compatible", function(params)
            -- Chat completions know low, medium and high.
            params.reasoning_effort = effort == "max" and "high" or effort
          end),
        },
        -- Pinning the model also keeps the adapter from listing models on every start.
        schema = model ~= "" and { model = { default = model } } or nil,
      })
    end,

    anthropic_litellm = function()
      local model = vim.env.CODECOMPANION_ANTHROPIC_MODEL or ""
      return require("codecompanion.adapters").extend("anthropic", {
        formatted_name = "Anthropic via LiteLLM",
        url = "${url}/v1/messages",
        env = { url = env("CODECOMPANION_ANTHROPIC_BASE_URL"), api_key = env("CODECOMPANION_ANTHROPIC_API_KEY") },
        handlers = {
          form_parameters = wrap_form_parameters("anthropic", function(params)
            -- Adaptive thinking whose depth is steered by the effort level.
            params.thinking = { type = "adaptive" }
            params.output_config = { effort = effort }
            params.top_k = nil
          end),
        },
        schema = {
          model = {
            default = model ~= "" and model or function()
              return anthropic_model_ids()[1]
            end,
            choices = anthropic_models,
          },
          -- Thinking tokens count towards max_tokens, so leave room for them.
          max_tokens = { default = 32000 },
        },
      })
    end,
  },
  acp = {
    claude_code = function()
      return require("codecompanion.adapters").extend("claude_code", {
        -- The stock value would hand the variable's name to the CLI as a token when unset.
        -- Empty falls back to the login of the local Claude Code install.
        env = { CLAUDE_CODE_OAUTH_TOKEN = env("CLAUDE_CODE_OAUTH_TOKEN") },
      })
    end,
  },
}

local function backend(name)
  for _, candidate in ipairs(M.backends) do
    if candidate.name == name then
      return candidate
    end
  end
end

-- The backend CodeCompanion is switched on with, nil while it is off.
local active
-- The last HTTP backend, which inline edits and commands stay on while an ACP agent is active.
local last_http

function M.active()
  return active
end

-- Adapter names for the chat, the inline assistant and the command interaction.
local function selection()
  if not active then
    return {}
  end
  local inline = backend(active).type == "http" and active or last_http or active
  return { chat = active, inline = inline, cmd = inline }
end

-- The `interactions` of the plugin options. Nothing is selected before a backend is picked.
function M.interactions()
  local chosen = selection()
  return {
    chat = { adapter = chosen.chat },
    inline = { adapter = chosen.inline },
    cmd = { adapter = chosen.cmd },
  }
end

local function close_chats()
  local codecompanion = require("codecompanion")
  for _, bufnr in ipairs(vim.deepcopy(_G.codecompanion_buffers or {})) do
    local chat = codecompanion.buf_get_chat(bufnr)
    if chat and chat.close then
      chat:close()
    end
  end
end

-- The Ex commands exist only while a backend is on, as before the first one is picked.
local function set_commands(enabled)
  for _, command in ipairs(require("codecompanion.commands")) do
    if enabled then
      vim.api.nvim_create_user_command(command.cmd, command.callback, command.opts)
    else
      pcall(vim.api.nvim_del_user_command, command.cmd)
    end
  end
end

-- Switch CodeCompanion on with `name`, or off with nil. The plugin is loaded on first use only, so
-- nothing of it runs while it is off. Open chats follow the new backend, or are closed when off.
function M.set_backend(name)
  active = name
  if backend(name) and backend(name).type == "http" then
    last_http = name
  end
  if not name and not package.loaded["codecompanion"] then
    return
  end

  require("lazy").load({ plugins = { "codecompanion.nvim" } })
  local config = require("codecompanion.config")
  for interaction, adapter in pairs(M.interactions()) do
    config.interactions[interaction].adapter = adapter.adapter
  end
  set_commands(name ~= nil)

  if not name then
    close_chats()
    notify("Off")
    return
  end
  local chat = require("codecompanion").last_chat()
  if chat and chat.adapter.name ~= name and not chat:change_adapter(name) then
    return
  end
  notify("Backend: " .. name)
end

-- Ask which of the configured backends to switch on, or to switch off again.
function M.pick_backend()
  local items = {}
  for _, candidate in ipairs(M.backends) do
    if candidate.ready() then
      table.insert(items, candidate)
    end
  end
  if #items == 0 then
    notify("No backend is configured, see the AI assistant section of the Neovim README", vim.log.levels.WARN)
    return
  end
  if active then
    table.insert(items, { name = false, label = "Off" })
  end

  vim.ui.select(items, {
    prompt = "AI backend",
    format_item = function(item)
      return (item.name == active and "* " or "  ") .. item.label
    end,
  }, function(choice)
    if choice and choice.name ~= active then
      M.set_backend(choice.name or nil)
    end
  end)
end

function M.warn_off()
  notify("Off, pick a backend first with the backend hotkey", vim.log.levels.WARN)
end

-- A hotkey action that only runs while a backend is on.
function M.when_active(action)
  return function()
    if active then
      return action()
    end
    M.warn_off()
  end
end

local function active_chat()
  local chat = require("codecompanion").last_chat()
  if not chat then
    notify("Open a chat first", vim.log.levels.WARN)
  end
  return chat
end

-- CodeCompanion's own picker: models from the endpoint for HTTP adapters, the session's
-- models for ACP agents.
function M.pick_model()
  local chat = active_chat()
  if chat then
    require("codecompanion.interactions.chat.keymaps.change_adapter").select_model(chat)
  end
end

function M.pick_effort()
  local chat = require("codecompanion").last_chat()
  local current = chat and chat.adapter.name or require("codecompanion.config").interactions.chat.adapter
  if current == "copilot" then
    notify("Effort is not configurable for the copilot backend", vim.log.levels.WARN)
    return
  end
  if chat and chat.adapter.type == "acp" then
    -- The agent advertises its own options, effort among them, as session options.
    local command = require("codecompanion.interactions.chat.slash_commands.builtin.acp_session_options")
    command.new({ Chat = chat, config = {}, context = {} }):execute()
    return
  end

  local items = vim.list_extend({ "default" }, EFFORTS)
  vim.ui.select(items, {
    prompt = "Reasoning effort",
    format_item = function(item)
      return ((item == "default" and not effort or item == effort) and "* " or "  ") .. item
    end,
  }, function(choice)
    if choice then
      effort = choice ~= "default" and choice or nil
      notify("Reasoning effort: " .. choice)
    end
  end)
end

return M
