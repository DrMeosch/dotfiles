#!/usr/bin/env node
// Tests home/.pi/agent/extensions/jev-capture.js with a fake pi API and a fake `jev-hook` that
// records what it is given, so it needs neither pi nor Jev: the owner's prompts and final answers
// reach the hook, nothing else does, and a slow or missing hook never reaches the session.
//
// Usage: test-pi-jev-capture.mjs
import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const EXTENSION = join(REPO, "home/.pi/agent/extensions/jev-capture.js");

const work = mkdtempSync(join(tmpdir(), "pi-jev-capture-"));
after(() => rmSync(work, { recursive: true, force: true }));

// Pi loads the file as an ES module; a .mjs copy makes plain node do the same on every version.
const copy = join(work, "jev-capture.mjs");
copyFileSync(EXTENSION, copy);
const ext = await import(pathToFileURL(copy).href);

let hooks = 0;
/** A fake jev-hook that writes its argv and stdin to a file of its own in `dir`, after `delay` s. */
function fakeHook(delay = 0) {
  const dir = join(work, `calls-${++hooks}`);
  mkdirSync(dir);
  const bin = join(work, `jev-hook-${hooks}`);
  writeFileSync(
    bin,
    `#!/bin/sh\nsleep ${delay}\nout="${dir}/$$"\n{ printf '%s\\n' "$*"; cat; } > "$out.tmp" && mv "$out.tmp" "$out.json"\n`,
    { mode: 0o755 },
  );
  return { bin, dir };
}

/** The calls `dir` has received, once `count` of them have landed (the hook is detached). */
async function calls(dir, count, timeoutMs = 5000) {
  const deadline = Date.now() + timeoutMs;
  let found = [];
  while (Date.now() < deadline) {
    found = readdirSync(dir).filter((f) => f.endsWith(".json"));
    if (found.length >= count) break;
    await new Promise((r) => setTimeout(r, 20));
  }
  return found.map((f) => {
    const [args, ...body] = readFileSync(join(dir, f), "utf8").split("\n");
    return { args, payload: JSON.parse(body.join("\n")) };
  });
}

/** Load the extension into a fake pi and return its handlers. */
function load() {
  const handlers = {};
  ext.default({ on: (name, fn) => (handlers[name] = fn) });
  return handlers;
}

function ctx(mode = "tui") {
  return {
    mode,
    cwd: "/work/project",
    sessionManager: { getSessionId: () => "sess-1", getSessionFile: () => "/pi/sessions/s.jsonl" },
  };
}

const typed = (text) => ({ type: "input", text, source: "interactive" });
const ended = (...content) => ({
  type: "agent_end",
  messages: [
    { role: "user", content: "hi" },
    { role: "assistant", stopReason: "stop", content },
  ],
});

/** Run `fn` with JEV_HOOK_BIN pointing at `bin`. */
function withHook(bin, fn) {
  const old = process.env.JEV_HOOK_BIN;
  process.env.JEV_HOOK_BIN = bin;
  try {
    return fn();
  } finally {
    if (old === undefined) delete process.env.JEV_HOOK_BIN;
    else process.env.JEV_HOOK_BIN = old;
  }
}

test("a typed prompt and the final answer reach jev-hook as pi events", async () => {
  const { bin, dir } = fakeHook();
  const on = load();
  const before = Date.now();
  withHook(bin, () => {
    on.input(typed("fix the build"), ctx());
    on.agent_end(ended({ type: "thinking", thinking: "hmm" }, { type: "text", text: "done" }, { type: "text", text: "pushed" }), ctx());
  });
  const got = await calls(dir, 2);
  const prompt = got.find((c) => c.args.startsWith("prompt"));
  const stop = got.find((c) => c.args.startsWith("stop"));
  assert.equal(prompt?.args, "prompt --source pi");
  assert.equal(stop?.args, "stop --source pi");
  assert.equal(prompt.payload.hook_event_name, "UserPromptSubmit");
  assert.equal(prompt.payload.prompt, "fix the build");
  assert.equal(stop.payload.hook_event_name, "Stop");
  assert.equal(stop.payload.last_assistant_message, "done\npushed");
  for (const { payload } of [prompt, stop]) {
    assert.equal(payload.session_id, "sess-1");
    assert.equal(payload.cwd, "/work/project");
    assert.equal(payload.transcript_path, "/pi/sessions/s.jsonl");
    assert.ok(payload.ts_ms >= before && payload.ts_ms <= Date.now(), "ts_ms is when it happened");
    assert.equal(payload.ts, Math.floor(payload.ts_ms / 1000));
  }
});

test("an editor client (rpc mode) is captured too", async () => {
  const { bin, dir } = fakeHook();
  const on = load();
  withHook(bin, () => on.input(typed("from the editor"), ctx("rpc")));
  const [call] = await calls(dir, 1);
  assert.equal(call?.payload.prompt, "from the editor");
});

test("events in the same millisecond keep their order and their identity", async () => {
  const { bin, dir } = fakeHook();
  const on = load();
  withHook(bin, () => {
    on.input(typed("again"), ctx());
    on.input(typed("again"), ctx());
    on.agent_end(ended({ type: "text", text: "ok" }), ctx());
  });
  const got = (await calls(dir, 3)).map((c) => c.payload).sort((a, b) => a.ts_ms - b.ts_ms);
  assert.deepEqual(got.map((p) => p.hook_event_name), ["UserPromptSubmit", "UserPromptSubmit", "Stop"]);
  assert.equal(new Set(got.map((p) => p.ts_ms)).size, 3, "a clock that never repeats");
  assert.equal(new Set(got.map((p) => p.event_id)).size, 3, "two identical prompts are two events");
  assert.ok(got.every((p) => typeof p.event_id === "string" && p.event_id.length > 0));
});

const notTheOwner = {
  "another extension speaking": (on) => on.input({ type: "input", text: "x", source: "extension" }, ctx()),
  "a scripted print run": (on) => on.input(typed("x"), ctx("print")),
  "a json run (a subagent)": (on) => on.input(typed("x"), ctx("json")),
  "the answer of a print run": (on) => on.agent_end(ended({ type: "text", text: "x" }), ctx("print")),
  "an aborted run": (on) => on.agent_end({ messages: [{ role: "assistant", stopReason: "aborted", content: [{ type: "text", text: "half" }] }] }, ctx()),
  "a failed run": (on) => on.agent_end({ messages: [{ role: "assistant", stopReason: "error", content: [{ type: "text", text: "half" }] }] }, ctx()),
  "a run with no text": (on) => on.agent_end(ended({ type: "toolCall", name: "bash" }), ctx()),
  "a run with no messages": (on) => on.agent_end({ messages: [] }, ctx()),
};
for (const [name, act] of Object.entries(notTheOwner)) {
  test(`nothing is sent for ${name}`, async () => {
    const { bin, dir } = fakeHook();
    withHook(bin, () => act(load()));
    assert.deepEqual(await calls(dir, 1, 500), []);
  });
}

test("handlers return at once while a slow hook is still running", async () => {
  const { bin, dir } = fakeHook(2);
  const on = load();
  const start = performance.now();
  const results = withHook(bin, () => [
    on.input(typed("a prompt ".repeat(5000)), ctx()),
    on.agent_end(ended({ type: "text", text: "an answer ".repeat(5000) }), ctx()),
  ]);
  assert.ok(performance.now() - start < 500, "the handlers did not wait for the hook");
  assert.deepEqual(results, [undefined, undefined]);
  assert.equal((await calls(dir, 2, 6000)).length, 2, "the hook still got both payloads");
});

test("a missing jev-hook, or a broken context, never reaches the session", async () => {
  const on = load();
  const errors = [];
  const record = (e) => errors.push(e);
  process.on("uncaughtException", record);
  try {
    withHook(join(work, "no-such-hook"), () => {
      assert.equal(on.input(typed("hi"), ctx()), undefined);
      assert.equal(on.agent_end(ended({ type: "text", text: "yes" }), ctx()), undefined);
      assert.equal(on.input(typed("hi"), { mode: "tui" }), undefined);
      assert.equal(on.agent_end(null, ctx()), undefined);
    });
    await new Promise((r) => setTimeout(r, 300)); // a spawn failure is reported asynchronously
  } finally {
    process.off("uncaughtException", record);
  }
  assert.deepEqual(errors, []);
});

test("jev-hook is found through JEV_HOOK_BIN, then XDG_BIN_HOME, then PATH", () => {
  const bin = join(work, "xdg-bin");
  mkdirSync(bin);
  assert.equal(ext.hookBin({ JEV_HOOK_BIN: "/opt/jev-hook", XDG_BIN_HOME: bin }), "/opt/jev-hook");
  assert.equal(ext.hookBin({ XDG_BIN_HOME: bin }), "jev-hook", "an empty bin directory falls through to PATH");
  writeFileSync(join(bin, "jev-hook"), "", { mode: 0o755 });
  assert.equal(ext.hookBin({ XDG_BIN_HOME: bin }), join(bin, "jev-hook"));
});
