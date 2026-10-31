// Registers the LiteLLM gateway as a Pi provider. Pi interpolates environment
// variables in `apiKey` and `headers` but not in `baseUrl`, so the provider is
// registered here, from LITELLM_BASE_URL (the full .../v1 URL) and
// LITELLM_API_KEY. Without LITELLM_BASE_URL the provider is not registered.
const CLAUDE = { contextWindow: 200000, maxTokens: 32000 };
const GPT = { contextWindow: 272000, maxTokens: 128000 };

const MODELS = [
  ["claude-fable-5-1", "Claude Fable 5.1", CLAUDE],
  ["claude-opus-5-5", "Claude Opus 5.5", CLAUDE],
  ["claude-sonnet-5-5", "Claude Sonnet 5.5", CLAUDE],
  ["claude-haiku-5-5", "Claude Haiku 5.5", CLAUDE],
  ["gpt-6.1-sol", "GPT-6.1 Sol", GPT],
  ["gpt-6.1-terra", "GPT-6.1 Terra", GPT],
  ["gpt-6-sol", "GPT-6 Sol", GPT],
  ["gpt-6-luna", "GPT-6 Luna", GPT],
  ["gpt-6-astra", "GPT-6 Astra", GPT],
  ["gpt-5.6-sol", "GPT-5.6 Sol", GPT],
  ["gpt-5.6-luna", "GPT-5.6 Luna", GPT],
  ["gpt-5.6-terra", "GPT-5.6 Terra", GPT],
];

export default function (pi) {
  const baseUrl = process.env.LITELLM_BASE_URL?.trim();
  if (!baseUrl) return;

  pi.registerProvider("litellm", {
    name: "LiteLLM",
    baseUrl,
    apiKey: "$LITELLM_API_KEY",
    api: "openai-completions",
    models: MODELS.map(([id, name, limits]) => ({
      type: "chat",
      id,
      name,
      reasoning: true,
      input: ["text", "image"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      ...limits,
    })),
  });
}
