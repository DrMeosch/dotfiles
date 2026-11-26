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
// vendors directly, instead of both through /v1/chat/completions. The GPT-6.2
// models, which Pi's catalog only has from 1.6.0 on, carry a copy of that
// metadata for an older Pi.
//
// The provider streams through Pi's own anthropic-messages and openai-responses
// implementations, with one change: a model call the gateway answers with HTTP
// 499 ends with an error Pi retries (see retryGatewayClose below). Every litellm
// call goes through these streams, so this covers agent turns, compaction, branch
// summaries and bug-report summaries alike.
import {
  anthropicMessagesApi,
  createAssistantMessageEventStream,
  createProvider,
  envApiKeyAuth,
  openAIResponsesApi,
} from "@earendil-works/pi-ai";
import { getBuiltinModel } from "@earendil-works/pi-ai/providers/all";

const CLAUDE = ["claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"];
const GPT = ["gpt-6.2-sol", "gpt-6.2-astra", "gpt-6.1-sol", "gpt-6-sol", "gpt-6-luna", "gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-luna", "gpt-5.6-terra"];

// Used only when Pi's catalog has no such model (Pi before 1.6.0): the entries of
// Pi 1.6.0's `openai` catalog (pi-ai dist/providers/data/openai.json).
const GPT_6_2 = {
  api: "openai-responses",
  reasoning: true,
  input: ["text", "image"],
  contextWindow: 272000,
  maxTokens: 128000,
  thinkingLevelMap: { off: null, minimal: null, low: "low", medium: "medium", high: "high", xhigh: "xhigh", max: "max" },
  compat: {
    supportsStrictMode: true,
    supportsOpenAIGrammarTools: true,
    supportsAdditionalTools: true,
    supportsToolSearch: true,
    supportsMidConvoSystemMessages: true,
    supportsExplicitPromptCacheMode: true,
    supportsMidConvoEffort: true,
  },
  inputLimits: {
    maxRequestBytes: 536870912,
    images: { maxPerRequest: 1500, resize: { maxWidth: 2000, maxHeight: 2000, maxBytes: 4718592, jpegQuality: 80 } },
  },
  type: "chat",
};
const NOT_IN_OLDER_PI = {
  "openai/gpt-6.2-sol": {
    ...GPT_6_2,
    name: "GPT-6.2 Sol",
    cost: {
      input: 2,
      output: 10,
      cacheRead: 0.1,
      cacheWrite: 2.5,
      tiers: [{ inputTokensAbove: 272000, input: 4, output: 15, cacheRead: 0.2, cacheWrite: 5 }],
    },
  },
  "openai/gpt-6.2-astra": {
    ...GPT_6_2,
    name: "GPT-6.2 Astra",
    cost: {
      input: 8,
      output: 40,
      cacheRead: 0.4,
      cacheWrite: 10,
      tiers: [{ inputTokensAbove: 272000, input: 16, output: 60, cacheRead: 0.8, cacheWrite: 20 }],
    },
  },
};

// A model call the gateway answered with HTTP 499 ("Client Closed Request"): a
// hop behind Pi (the gateway or what it calls) dropped its request for this call
// before it got an answer. Pi's own connection was still open, since this answer
// reached it. It is a transient gateway failure, but Pi's list of retryable
// errors has no 499, so the call would fail for good. The status leads the
// message: "litellm API error (499): ..." on /v1/responses, "499 ..." on
// /v1/messages.
const GATEWAY_CLOSED = /^(?:litellm API error \(499\):|499 )/;

// Appended to such an error so that it matches "upstream request failed" in
// Pi's retryable errors. Pi then retries the call with its usual retry settings
// (`retry` in settings.json: retries and backoff) and shows it as a retry.
// Nothing else changes: when Pi itself cancels a call (Escape, or its HTTP idle
// timeout) the call ends as aborted or with Pi's own timeout error, never with
// an HTTP 499 answer, so this never turns a cancellation by Pi into a retry.
const GATEWAY_CLOSED_NOTE = " (the gateway's upstream request failed)";

/** `message`, or a copy of it that Pi retries when it is a 499 from the gateway. */
function markGatewayCloseRetryable(message) {
  if (message.stopReason !== "error" || !GATEWAY_CLOSED.test(message.errorMessage ?? "")) return message;
  return { ...message, errorMessage: message.errorMessage + GATEWAY_CLOSED_NOTE };
}

/** Pi's implementation of a wire API, with the final error of each call passed through markGatewayCloseRetryable. */
function retryGatewayClose(api) {
  const wrap = (stream) => (model, context, options) => {
    const inner = stream(model, context, options);
    const outer = createAssistantMessageEventStream();
    void (async () => {
      for await (const event of inner) {
        outer.push(event.type === "error" ? { ...event, error: markGatewayCloseRetryable(event.error) } : event);
      }
      outer.end(markGatewayCloseRetryable(await inner.result()));
    })();
    return outer;
  };
  return { ...api, stream: wrap(api.stream), streamSimple: wrap(api.streamSimple) };
}

export default function (pi) {
  const configured = process.env.LITELLM_BASE_URL?.trim();
  if (!configured) return;
  // Anthropic's client appends /v1/messages itself; OpenAI's expects the /v1.
  const root = configured.replace(/\/+$/, "").replace(/\/v1$/, "");

  const missing = [];
  const derive = (provider, id, baseUrl, { from = id, name } = {}) => {
    const model = getBuiltinModel(provider, from) ?? NOT_IN_OLDER_PI[`${provider}/${from}`];
    if (!model) {
      missing.push(id === from ? `${provider}/${from}` : `${id} (from ${provider}/${from})`);
      return undefined;
    }
    return { ...model, id, name: name ?? model.name, provider: "litellm", baseUrl };
  };

  const models = [
    ...CLAUDE.map((id) => derive("anthropic", id, root)),
    ...GPT.map((id) => derive("openai", id, `${root}/v1`)),
    // Not in Pi's catalog yet: same prices as gpt-6.1-sol (see models.json).
    derive("openai", "gpt-6.1-terra", `${root}/v1`, { from: "gpt-6.1-sol", name: "GPT-6.1 Terra" }),
  ].filter(Boolean);

  // A model missing from Pi's catalog is skipped, which can also change which
  // litellm model Pi picks by default (settings.json asks for gpt-5.6-luna).
  if (missing.length) {
    const warning = `litellm provider: not in Pi's built-in catalog, skipped: ${missing.join(", ")}`;
    console.warn(warning);
    // The TUI clears the screen after loading, so also show it inside the session.
    pi.on("session_start", (_event, ctx) => {
      if (ctx.hasUI) ctx.ui.notify(warning, "warning");
    });
  }

  pi.registerProvider(
    createProvider({
      id: "litellm",
      name: "LiteLLM",
      baseUrl: root,
      auth: { apiKey: envApiKeyAuth("LiteLLM API key", ["LITELLM_API_KEY"]) },
      models,
      api: {
        "anthropic-messages": retryGatewayClose(anthropicMessagesApi()),
        "openai-responses": retryGatewayClose(openAIResponsesApi()),
      },
    }),
  );
}
