// Registers the LiteLLM gateway as a Pi provider. Pi interpolates environment
// variables in `apiKey` and `headers` but not in `baseUrl`, so the provider is
// registered here, from LITELLM_BASE_URL (the gateway URL, with or without the
// trailing /v1) and LITELLM_API_KEY. Without LITELLM_BASE_URL the provider is
// not registered.
//
// Every model reuses the metadata of the same model in Pi's built-in `anthropic`
// or `openai` catalog (api, thinking levels, prompt-cache and tool compat,
// prices, context window). Claude therefore goes through the gateway's
// /v1/messages and GPT through its /v1/responses, the way Pi talks to the
// vendors directly, instead of both through /v1/chat/completions.
import { getModel } from "@earendil-works/pi-ai";

const CLAUDE = ["claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"];
const GPT = ["gpt-6.1-sol", "gpt-6-sol", "gpt-6-luna", "gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-luna", "gpt-5.6-terra"];

export default function (pi) {
  const configured = process.env.LITELLM_BASE_URL?.trim();
  if (!configured) return;
  // Anthropic's client appends /v1/messages itself; OpenAI's expects the /v1.
  const root = configured.replace(/\/+$/, "").replace(/\/v1$/, "");

  const derive = (provider, id, baseUrl, { from = id, name } = {}) => {
    const model = getModel(provider, from);
    return model && { ...model, id, name: name ?? model.name, provider: "litellm", baseUrl };
  };

  pi.registerProvider("litellm", {
    name: "LiteLLM",
    baseUrl: root,
    apiKey: "$LITELLM_API_KEY",
    models: [
      ...CLAUDE.map((id) => derive("anthropic", id, root)),
      ...GPT.map((id) => derive("openai", id, `${root}/v1`)),
      // Not in Pi's catalog yet: same prices as gpt-6.1-sol (see models.json).
      derive("openai", "gpt-6.1-terra", `${root}/v1`, { from: "gpt-6.1-sol", name: "GPT-6.1 Terra" }),
    ].filter(Boolean),
  });
}
