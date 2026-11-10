# 💤 LazyVim

A starter template for [LazyVim](https://github.com/LazyVim/LazyVim).
Refer to the [documentation](https://lazyvim.github.io/installation) to get started.

## AI assistant

[CodeCompanion](https://github.com/olimorris/codecompanion.nvim) (`lua/plugins/codecompanion.lua`,
`lua/config/codecompanion.lua`) provides a chat buffer and inline editing. It needs Neovim 0.11 or
newer; run `:checkhealth codecompanion` to check the setup.

Four backends are set up and `<leader>ab` cycles through them, for the open chat as well as for new
chats and inline edits. The Claude Code backend only works in the chat buffer, inline edits stay on
the last HTTP backend.

| Backend         | Talks to                                                | Set up                                  |
| --------------- | ------------------------------------------------------- | --------------------------------------- |
| `openai_env`    | any OpenAI-compatible chat completions endpoint         | environment variables, see below        |
| `anthropic_env` | the Anthropic Messages API, e.g. LiteLLM's `/v1/messages` | environment variables, see below      |
| `copilot`       | GitHub Copilot, Business seats included                 | `:Copilot auth` once, see below         |
| `claude_code`   | Claude through the Claude Code CLI and a subscription   | Claude Code login, see below            |

`openai_env` is the default. No host, key or model name is stored in this repository, the HTTP
backends read them from the environment of the shell that starts Neovim:

| Variable                           | Backend         | Meaning                                                            |
| ---------------------------------- | --------------- | ------------------------------------------------------------------ |
| `CODECOMPANION_BASE_URL`           | `openai_env`    | Server root without `/v1`, e.g. `https://llm.example.com`          |
| `CODECOMPANION_API_KEY`            | `openai_env`    | Bearer token sent with every request                               |
| `CODECOMPANION_MODEL`              | `openai_env`    | Optional, defaults to the first model the server lists             |
| `CODECOMPANION_ANTHROPIC_BASE_URL` | `anthropic_env` | Gateway root without `/v1`, requests go to `<root>/v1/messages`    |
| `CODECOMPANION_ANTHROPIC_API_KEY`  | `anthropic_env` | Key sent in the `x-api-key` header                                 |
| `CODECOMPANION_ANTHROPIC_MODEL`    | `anthropic_env` | Model id, defaults to the first model the gateway lists            |

`copilot` reads the token that the Copilot sign-in leaves behind. Run `:Copilot auth` once and follow
the prompts, sign in with the GitHub account that has the Copilot (Business) seat. This needs Node.js.
The models the seat grants are offered by the model picker.

`claude_code` runs the Claude Code CLI over the Agent Client Protocol and bills the Claude
subscription, no API key involved. It needs the `claude` CLI, signed in (`claude` and `/login`), and
the `claude-agent-acp` adapter on the `PATH` (`npm install -g @zed-industries/claude-agent-acp`).
To use a token from `claude setup-token` instead of the local login, export `CLAUDE_CODE_OAUTH_TOKEN`.

| Keymap       | Mode | Action                                                              |
| ------------ | ---- | ------------------------------------------------------------------- |
| `<leader>ac` | n, v | Toggle the chat buffer                                              |
| `<leader>ai` | n, v | Start an inline prompt (`:CodeCompanion `)                          |
| `<leader>aa` | n, v | Open the action palette                                             |
| `<leader>as` | v    | Add the selection to the chat                                       |
| `<leader>ab` | n    | Switch to the next backend and say which one is active              |
| `<leader>am` | n    | Pick the model of the current chat (`ga` in the chat does the same, and swaps the adapter) |
| `<leader>ae` | n    | Pick the reasoning effort                                           |

The effort picker offers low, medium, high and max, or default to send nothing. It applies to
`openai_env` (as `reasoning_effort`, max counts as high) and `anthropic_env` (adaptive thinking
with that effort, which needs a model that supports it) and takes effect on the next request. For
`claude_code` it opens the agent's session options, where model, mode and effort are listed as the
agent offers them. `copilot` has no effort setting.
