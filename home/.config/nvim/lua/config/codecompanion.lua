-- CodeCompanion backends and the hotkeys that drive them (see plugins/codecompanion.lua).
--
-- Four backends, cycled with switch_backend():
--   openai_env      any OpenAI-compatible chat completions endpoint
--   anthropic_env   the Anthropic Messages API, e.g. the /v1/messages route of a LiteLLM gateway
--   copilot         GitHub Copilot (Business included), signed in once with :Copilot auth
--   claude_code     the Claude Code CLI over ACP, which uses the local Claude subscription login
-- Hosts, keys and model names come only from the environment, see the README.
local M = {}

M.backends = { "openai_env", "anthropic_env", "copilot", "claude_code" }

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

-- Adapters are resolved many times per session, warn about a missing variable once.
local warned = {}
local function warn_unset(names)
  for _, name in ipairs(names) do
    if (vim.env[name] or "") == "" and not warned[name] then
      warned[name] = true
      notify(name .. " is not set, requests will fail", vim.log.levels.WARN)
    end
  end
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
    openai_env = function()
      local model = vim.env.CODECOMPANION_MODEL or ""
      warn_unset({ "CODECOMPANION_BASE_URL", "CODECOMPANION_API_KEY" })
      return require("codecompanion.adapters").extend("openai_compatible", {
        formatted_name = "OpenAI compatible",
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

    anthropic_env = function()
      local model = vim.env.CODECOMPANION_ANTHROPIC_MODEL or ""
      warn_unset({ "CODECOMPANION_ANTHROPIC_BASE_URL", "CODECOMPANION_ANTHROPIC_API_KEY" })
      return require("codecompanion.adapters").extend("anthropic", {
        formatted_name = "Anthropic Messages",
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

local function active_chat()
  local chat = require("codecompanion").last_chat()
  if not chat then
    notify("Open a chat first", vim.log.levels.WARN)
  end
  return chat
end

-- Select the backend for new chats and inline edits and move the open chat along.
function M.switch_backend()
  local config = require("codecompanion.config")
  local current = config.interactions.chat.adapter
  current = type(current) == "table" and current.name or current

  local index = 1
  for i, name in ipairs(M.backends) do
    if name == current then
      index = i % #M.backends + 1
    end
  end
  local name = M.backends[index]

  config.interactions.chat.adapter = name
  if name ~= "claude_code" then
    -- Agents only work in the chat buffer.
    config.interactions.inline.adapter = name
    config.interactions.cmd.adapter = name
  end

  local chat = require("codecompanion").last_chat()
  if chat and chat.adapter.name ~= name and not chat:change_adapter(name) then
    return
  end
  notify("Backend: " .. name)
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
