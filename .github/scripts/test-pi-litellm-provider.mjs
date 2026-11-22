#!/usr/bin/env node
// Tests home/.pi/agent/extensions/litellm-provider.js with a fake pi API and a fake built-in model
// catalog standing in for `@earendil-works/pi-ai`, so it needs no pi: which models the `litellm`
// provider registers on a Pi whose catalog has no GPT-6.2 (before 1.6.0) and on one that has it.
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
  JSON.stringify({ name: "@earendil-works/pi-ai", type: "module", exports: { "./providers/*": "./providers/*.js" } }),
);
writeFileSync(
  join(piAi, "providers/all.js"),
  "export const catalog = { lookup: () => undefined };\nexport const getBuiltinModel = (provider, id) => catalog.lookup(provider, id);\n",
);

// Pi loads the file as an ES module; a .mjs copy makes plain node do the same on every version.
const copy = join(work, "litellm-provider.mjs");
copyFileSync(EXTENSION, copy);
const ext = await import(pathToFileURL(copy).href);
const { catalog } = await import(pathToFileURL(join(piAi, "providers/all.js")).href);

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

/** Start the extension against `lookup`: the litellm models by id, and the warnings it gave. */
function start(lookup) {
  catalog.lookup = lookup;
  const printed = [];
  const handlers = {};
  const providers = {};
  const realWarn = console.warn;
  const oldUrl = process.env.LITELLM_BASE_URL;
  console.warn = (message) => printed.push(message);
  process.env.LITELLM_BASE_URL = `${GATEWAY}/v1/`;
  try {
    ext.default({ on: (name, fn) => (handlers[name] = fn), registerProvider: (name, config) => (providers[name] = config) });
  } finally {
    console.warn = realWarn;
    if (oldUrl === undefined) delete process.env.LITELLM_BASE_URL;
    else process.env.LITELLM_BASE_URL = oldUrl;
  }
  const notified = [];
  handlers.session_start?.({}, { hasUI: true, ui: { notify: (message) => notified.push(message) } });
  return { models: Object.fromEntries(providers.litellm.models.map((m) => [m.id, m])), printed, notified };
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
