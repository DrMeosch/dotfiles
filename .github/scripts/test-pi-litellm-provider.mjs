#!/usr/bin/env node
// Tests home/.pi/agent/extensions/litellm-provider.js with a fake pi API and a fake built-in model
// catalog standing in for `@earendil-works/pi-ai`, so it needs no pi: which models the `litellm`
// provider registers on a Pi whose catalog has no GPT-6.2 (before 1.6.0) and on one that has it,
// and which failed model calls its streams make retryable.
//
// Usage: test-pi-litellm-provider.mjs
import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const EXTENSION = join(REPO, "home/.pi/agent/extensions/litellm-provider.js");

const work = realpathSync(mkdtempSync(join(tmpdir(), "pi-litellm-provider-")));
after(() => rmSync(work, { recursive: true, force: true }));

// The catalog module the extension imports, answering from whatever lookup a test puts in it.
const piAi = join(work, "node_modules/@earendil-works/pi-ai");
mkdirSync(join(piAi, "providers"), { recursive: true });
writeFileSync(
  join(piAi, "package.json"),
  JSON.stringify({ name: "@earendil-works/pi-ai", type: "module", exports: { ".": "./index.js", "./providers/*": "./providers/*.js" } }),
);
writeFileSync(
  join(piAi, "providers/all.js"),
  "export const catalog = { lookup: () => undefined };\nexport const getBuiltinModel = (provider, id) => catalog.lookup(provider, id);\n",
);
// The rest of pi-ai the extension uses. createProvider dispatches on `model.api` as Pi's does (pi-ai
// dist/models.js), and the two wire APIs answer every call with what `gateway.answer` returns for it,
// as the final message Pi's implementation would end the call with.
writeFileSync(
  join(piAi, "index.js"),
  `
export const gateway = { answer: () => ({ stopReason: "stop" }), calls: [] };
export function createAssistantMessageEventStream() {
  const events = [];
  let done = false;
  let wake = () => {};
  let resolveResult;
  const result = new Promise((resolve) => (resolveResult = resolve));
  return {
    push(event) {
      if (event.type === "done") resolveResult(event.message);
      if (event.type === "error") resolveResult(event.error);
      events.push(event);
      wake();
    },
    end(message) {
      done = true;
      if (message) resolveResult(message);
      wake();
    },
    result: () => result,
    async *[Symbol.asyncIterator]() {
      for (;;) {
        if (events.length) yield events.shift();
        else if (done) return;
        else await new Promise((resolve) => (wake = resolve));
      }
    },
  };
}
const wireApi = (api) => () => {
  const call = (model, context, options) => {
    const message = { role: "assistant", content: [], api: model.api, provider: model.provider, model: model.id, timestamp: 1, ...gateway.answer(model) };
    gateway.calls.push({ api, model: model.id, baseUrl: model.baseUrl, options, message });
    const failed = message.stopReason === "error" || message.stopReason === "aborted";
    const stream = createAssistantMessageEventStream();
    stream.push({ type: "start", partial: message });
    stream.push(failed ? { type: "error", reason: message.stopReason, error: message } : { type: "done", reason: message.stopReason, message });
    stream.end();
    return stream;
  };
  return { stream: call, streamSimple: call };
};
export const anthropicMessagesApi = wireApi("anthropic-messages");
export const openAIResponsesApi = wireApi("openai-responses");
export const envApiKeyAuth = (name, envVars) => ({ name, envVars });
export function createProvider(input) {
  const dispatch = (operation) => (model, context, options) => input.api[model.api][operation](model, context, options);
  return { ...input, getModels: () => input.models, stream: dispatch("stream"), streamSimple: dispatch("streamSimple") };
}
`,
);

// Pi loads the file as an ES module; a .mjs copy makes plain node do the same on every version.
const copy = join(work, "litellm-provider.mjs");
copyFileSync(EXTENSION, copy);
const ext = await import(pathToFileURL(copy).href);
const { catalog } = await import(pathToFileURL(join(piAi, "providers/all.js")).href);
const { gateway } = await import(pathToFileURL(join(piAi, "index.js")).href);

const GATEWAY = "https://gateway.example";

/** What a catalog that has `id` answers: unlike anything the extension carries itself. */
const inCatalog = (provider, id) => ({
  id,
  name: `${id} (catalog)`,
  api: "catalog-api",
  provider,
  baseUrl: "https://vendor.example/v1",
  contextWindow: 1,
});

/** A catalog with every model except the ones `lacks` matches. */
const catalogWithout = (lacks) => (provider, id) => (lacks(id) ? undefined : inCatalog(provider, id));

/** Start the extension against `lookup`: the provider it registers, its litellm models by id, and the warnings it gave. */
function start(lookup) {
  catalog.lookup = lookup;
  const printed = [];
  const handlers = {};
  const providers = [];
  const realWarn = console.warn;
  const oldUrl = process.env.LITELLM_BASE_URL;
  console.warn = (message) => printed.push(message);
  process.env.LITELLM_BASE_URL = `${GATEWAY}/v1/`;
  try {
    ext.default({ on: (name, fn) => (handlers[name] = fn), registerProvider: (provider) => providers.push(provider) });
  } finally {
    console.warn = realWarn;
    if (oldUrl === undefined) delete process.env.LITELLM_BASE_URL;
    else process.env.LITELLM_BASE_URL = oldUrl;
  }
  assert.deepEqual(providers.map((p) => p.id), ["litellm"], "only the litellm provider is registered");
  const [provider] = providers;
  assert.deepEqual(provider.auth.apiKey.envVars, ["LITELLM_API_KEY"], "the key comes from LITELLM_API_KEY");
  const notified = [];
  handlers.session_start?.({}, { hasUI: true, ui: { notify: (message) => notified.push(message) } });
  return { provider, models: Object.fromEntries(provider.getModels().map((m) => [m.id, m])), printed, notified, handlers };
}

// The `openai` catalog of Pi 1.6.0 (pi-ai dist/providers/data/openai.json, "openai-responses"),
// the first release that has these two models.
const PUBLISHED = {
  "gpt-6.2-sol": {
    name: "GPT-6.2 Sol",
    api: "openai-responses",
    reasoning: true,
    input: ["text", "image"],
    cost: {
      input: 2,
      output: 10,
      cacheRead: 0.1,
      cacheWrite: 2.5,
      tiers: [{ inputTokensAbove: 272000, input: 4, output: 15, cacheRead: 0.2, cacheWrite: 5 }],
    },
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
  },
  "gpt-6.2-astra": {
    name: "GPT-6.2 Astra",
    api: "openai-responses",
    reasoning: true,
    input: ["text", "image"],
    cost: {
      input: 8,
      output: 40,
      cacheRead: 0.4,
      cacheWrite: 10,
      tiers: [{ inputTokensAbove: 272000, input: 16, output: 60, cacheRead: 0.8, cacheWrite: 20 }],
    },
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
  },
};

test("a Pi whose catalog has no GPT-6.2 still gets both models, as Pi 1.6.0 publishes them", () => {
  const { models, printed, notified } = start(catalogWithout((id) => id.startsWith("gpt-6.2")));
  for (const [id, published] of Object.entries(PUBLISHED)) {
    assert.deepEqual(models[id], { ...published, id, provider: "litellm", baseUrl: `${GATEWAY}/v1` });
  }
  assert.deepEqual(printed, [], "neither is reported as skipped");
  assert.deepEqual(notified, []);
  assert.equal(models["gpt-5.6-luna"]?.name, "gpt-5.6-luna (catalog)", "the default model of settings.json still comes from the catalog");
});

test("a Pi whose catalog has GPT-6.2 uses the catalog's entries", () => {
  const { models, printed, notified } = start(catalogWithout(() => false));
  for (const id of Object.keys(PUBLISHED)) {
    assert.deepEqual(models[id], { ...inCatalog("openai", id), provider: "litellm", baseUrl: `${GATEWAY}/v1` });
  }
  assert.deepEqual(printed, []);
  assert.deepEqual(notified, []);
});

test("any other model missing from the catalog is skipped and named in a warning", () => {
  const { models, printed, notified } = start(catalogWithout((id) => id.startsWith("gpt-6.2") || id === "gpt-6-luna"));
  assert.equal(models["gpt-6-luna"], undefined);
  assert.deepEqual(printed, ["litellm provider: not in Pi's built-in catalog, skipped: openai/gpt-6-luna"]);
  assert.deepEqual(notified, printed, "the interactive session shows the same warning");
  assert.ok(models["gpt-6.2-sol"] && models["gpt-6.2-astra"], "the GPT-6.2 models are not affected");
});

// Pi 1.4.0's retryable-error pattern this relies on (pi-ai dist/utils/retry.js).
const PI_RETRYABLE = /upstream.?request.?failed/i;

// What Pi's wire implementations end a call with when the gateway answers HTTP 499: openai-responses
// prefixes the status with "<provider> API error" (pi-ai dist/api/openai-responses.js), Anthropic's SDK
// leads with the bare status. The first is the error of the failed session (see the README).
const CLOSED = {
  "gpt-5.6-luna": { api: "openai-responses", baseUrl: `${GATEWAY}/v1`, error: "litellm API error (499): 499 Client Closed Request" },
  "claude-opus-5-5": { api: "anthropic-messages", baseUrl: GATEWAY, error: "499 Client Closed Request" },
};
const RETRYABLE = (error) => `${error} (the gateway's upstream request failed)`;

/** The gateway answers the first `failures` calls with `answer` and every later one with a reply. */
function answerFirst(failures, answer) {
  gateway.calls = [];
  gateway.answer = () => (gateway.calls.length < failures ? answer : { stopReason: "stop", content: [{ type: "text", text: "ok" }] });
}

const context = { messages: [{ role: "user", content: "hi", timestamp: 1 }] };

/** A catalog whose entries carry the wire API of Pi's real ones: Claude on Anthropic Messages, GPT on OpenAI Responses. */
const wireCatalog = (provider, id) => ({ ...inCatalog(provider, id), api: { anthropic: "anthropic-messages", openai: "openai-responses" }[provider] });

test("a turn the gateway answers with 499 ends with an error Pi retries, on /v1/responses and on /v1/messages", async () => {
  const { provider, models } = start(wireCatalog);
  for (const [id, { api, baseUrl, error }] of Object.entries(CLOSED)) {
    assert.ok(!PI_RETRYABLE.test(error), "Pi alone would not retry it");
    for (const operation of ["streamSimple", "stream"]) {
      answerFirst(1, { stopReason: "error", errorMessage: error });
      // The agent loop takes the call's outcome from its terminal event.
      const events = [];
      for await (const event of provider[operation](models[id], context, { apiKey: "key" })) events.push(event);
      assert.deepEqual(events.map((e) => e.type), ["start", "error"], operation);
      assert.equal(events[1].error.errorMessage, RETRYABLE(error), operation);
      assert.ok(PI_RETRYABLE.test(events[1].error.errorMessage));
      assert.deepEqual(
        gateway.calls.map((c) => [c.api, c.model, c.baseUrl, c.options.apiKey]),
        [[api, id, baseUrl, "key"]],
        "the call still goes to the model's own wire API and endpoint",
      );
    }
  }
});

test("a compaction summary the gateway answers with 499 once succeeds through Pi's retry", async () => {
  const { provider, models } = start(wireCatalog);
  for (const [id, { error }] of Object.entries(CLOSED)) {
    answerFirst(1, { stopReason: "error", errorMessage: error });
    // Compaction and branch summaries take the call's result and retry it while it is a retryable
    // error (pi-coding-agent dist/core/compaction/compaction.js completeSummarization).
    const produce = () => provider.streamSimple(models[id], context, { cacheRetention: "none" }).result();
    const first = await produce();
    assert.equal(first.errorMessage, RETRYABLE(error));
    assert.ok(PI_RETRYABLE.test(first.errorMessage), "Pi schedules a retry");
    const second = await produce();
    assert.equal(second.stopReason, "stop");
    assert.equal(gateway.calls.length, 2);
  }
});

test("other failures, cancellations and replies are left alone", async () => {
  const { provider, models, handlers } = start(wireCatalog);
  assert.deepEqual(Object.keys(handlers), [], "no message hook, so calls of other providers never reach the extension");
  const unchanged = [
    { stopReason: "error", errorMessage: "litellm API error (400): max_tokens must be at most 499" },
    { stopReason: "error", errorMessage: "400 max_tokens must be at most 499" },
    { stopReason: "error", errorMessage: "litellm API error (500): Internal Server Error" },
    { stopReason: "error", errorMessage: "OpenAI API error (499): 499 Client Closed Request" },
    { stopReason: "error" },
    { stopReason: "aborted", errorMessage: "Request was aborted" },
    { stopReason: "aborted", errorMessage: "litellm API error (499): 499 Client Closed Request" },
    { stopReason: "stop", content: [{ type: "text", text: "499 Client Closed Request" }] },
  ];
  for (const id of Object.keys(CLOSED)) {
    for (const answer of unchanged) {
      gateway.answer = () => answer;
      for (const operation of ["streamSimple", "stream"]) {
        const message = await provider[operation](models[id], context, {}).result();
        assert.equal(message, gateway.calls.at(-1).message, `${id} ${operation} ${JSON.stringify(answer)}: the wire API's own message`);
      }
    }
  }
});
