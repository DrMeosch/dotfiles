# 💤 LazyVim

A starter template for [LazyVim](https://github.com/LazyVim/LazyVim).
Refer to the [documentation](https://lazyvim.github.io/installation) to get started.

## AI assistant

[CodeCompanion](https://github.com/olimorris/codecompanion.nvim) (`lua/plugins/codecompanion.lua`,
`lua/config/codecompanion.lua`) provides a chat buffer and inline editing. It needs Neovim 0.11 or
newer; run `:checkhealth codecompanion` to check the setup.

CodeCompanion is off by default. It is not even loaded, nothing is selected and nothing is contacted,
until you pick a backend with `<leader>ab`. The picker lists only the backends that are configured on
this machine (see below), plus `Off` while one is active. Picking one switches CodeCompanion on with it,
the open chat as well as new chats and inline edits move along. `Off` closes the open chats and goes
back to the initial state, the `:CodeCompanion*` commands are gone again and the other AI keymaps only
tell you to pick a backend first. The Claude Code backend only works in the chat buffer, inline edits
and commands stay on the last HTTP backend that was picked.

| Backend             | Talks to                                                | Listed when                           |
| ------------------- | ------------------------------------------------------- | ------------------------------------- |
| `claude_code`       | Claude through the Claude Code CLI and a subscription   | `claude` and `claude-agent-acp` found |
| `anthropic_litellm` | the Anthropic Messages API, e.g. LiteLLM `/v1/messages` | its two variables are set             |
| `openai`            | OpenAI directly                                         | `OPENAI_API_KEY` is set               |
| `openai_litellm`    | any OpenAI-compatible endpoint, e.g. LiteLLM            | its two variables are set             |
| `copilot`           | GitHub Copilot, Business seats included                 | `:Copilot auth` was run               |

No host, key or model name is stored in this repository, the HTTP backends read them from the
environment of the shell that starts Neovim:

| Variable                           | Backend             | Meaning                                                         |
| ---------------------------------- | ------------------- | --------------------------------------------------------------- |
| `CODECOMPANION_ANTHROPIC_BASE_URL` | `anthropic_litellm` | Gateway root without `/v1`, requests go to `<root>/v1/messages` |
| `CODECOMPANION_ANTHROPIC_API_KEY`  | `anthropic_litellm` | Key sent in the `x-api-key` header                              |
| `CODECOMPANION_ANTHROPIC_MODEL`    | `anthropic_litellm` | Optional, defaults to the first model the gateway lists         |
| `OPENAI_API_KEY`                   | `openai`            | OpenAI API key                                                  |
| `CODECOMPANION_OPENAI_MODEL`       | `openai`            | Optional, defaults to the plugin's default model                |
| `CODECOMPANION_BASE_URL`           | `openai_litellm`    | Server root without `/v1`, e.g. `https://llm.example.com`       |
| `CODECOMPANION_API_KEY`            | `openai_litellm`    | Bearer token sent with every request                            |
| `CODECOMPANION_MODEL`              | `openai_litellm`    | Optional, defaults to the first model the server lists          |

`copilot` reads the token that the Copilot sign-in leaves behind. Run `:Copilot auth` once and follow
the prompts, sign in with the GitHub account that has the Copilot (Business) seat. This needs Node.js.
Without the token the backend is not listed. The models the seat grants are offered by the model picker.

`claude_code` runs the Claude Code CLI over the Agent Client Protocol and bills the Claude
subscription, no API key involved. It needs the `claude` CLI, signed in (`claude` and `/login`), and
the `claude-agent-acp` adapter on the `PATH` (`npm install -g @zed-industries/claude-agent-acp`).
To use a token from `claude setup-token` instead of the local login, export `CLAUDE_CODE_OAUTH_TOKEN`.

| Keymap       | Mode | Action                                                                                     |
| ------------ | ---- | ------------------------------------------------------------------------------------------ |
| `<leader>ab` | n    | Pick the backend among the configured ones, or switch CodeCompanion off                    |
| `<leader>ac` | n, v | Toggle the chat buffer                                                                     |
| `<leader>ai` | n, v | Start an inline prompt (`:CodeCompanion `)                                                 |
| `<leader>aa` | n, v | Open the action palette                                                                    |
| `<leader>as` | v    | Add the selection to the chat                                                              |
| `<leader>am` | n    | Pick the model of the current chat (`ga` in the chat does the same, and swaps the adapter) |
| `<leader>ae` | n    | Pick the reasoning effort                                                                  |

The effort picker offers low, medium, high and max, or default to send nothing. It applies to
`openai` and `openai_litellm` (as `reasoning_effort`, max counts as high) and `anthropic_litellm`
(adaptive thinking with that effort, which needs a model that supports it) and takes effect on the
next request. For `claude_code` it opens the agent's session options, where model, mode and effort
are listed as the agent offers them. `copilot` has no effort setting.
