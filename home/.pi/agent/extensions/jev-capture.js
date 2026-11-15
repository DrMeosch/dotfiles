// Jev capture for the pi harness: the same events as the Claude Code hooks, into the same store.
//
// This file only forwards. Every prompt the owner types and every final answer is handed to
// `jev-hook --source pi` as a Claude-style JSON payload on stdin, detached and not awaited, so the
// redactor, the exclusion rules (own sessions, excluded working directories, fleet machinery
// prompts), the head/tail cut and the SQLite/spool write are the ones in src/jev/hook.py and
// nothing is duplicated here. See docs/p1-capture.md ("Pi sessions").
//
// Contract, as for the hooks: never block, never fail, never print. The handlers return
// immediately; every error is swallowed. Nothing leaves this process except to the local
// `jev-hook` binary, and nothing unredacted is written anywhere.
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// `tui` is the owner at a terminal, `rpc` is an editor client (pi-acp). `print` and `json` are
// scripted runs, which is what a pi subagent or a one-shot automation uses: not the owner talking.
const CAPTURE_MODES = new Set(["tui", "rpc"]);

/** Absolute path of jev-hook: JEV_HOOK_BIN, the `uv tool` bin directory, else whatever PATH has. */
export function hookBin(env = process.env) {
  if (env.JEV_HOOK_BIN) return env.JEV_HOOK_BIN;
  const bin = env.XDG_BIN_HOME || join(homedir(), ".local", "bin");
  const installed = join(bin, "jev-hook");
  return existsSync(installed) ? installed : "jev-hook";
}

/** Fire and forget: start `jev-hook <kind>` and give it the payload. Never throws. */
export function send(kind, payload, env = process.env) {
  try {
    const child = spawn(hookBin(env), [kind, "--source", "pi"], {
      stdio: ["pipe", "ignore", "ignore"],
      detached: true,
      env,
    });
    child.on("error", () => {});
    child.stdin.on("error", () => {});
    child.stdin.end(JSON.stringify(payload));
    child.unref(); // the stdin pipe stays referenced until the payload is written
  } catch {
    // fail open: a capture problem must never reach the session
  }
}

function base(ctx) {
  const session = ctx.sessionManager;
  return {
    session_id: session.getSessionId(),
    cwd: ctx.cwd,
    transcript_path: session.getSessionFile() ?? "",
    ts: Math.floor(Date.now() / 1000),
  };
}

/** The text of the last assistant message of a run, or "" when it was aborted or failed. */
export function finalAnswer(messages) {
  const last = messages.findLast((m) => m?.role === "assistant");
  if (!last || last.stopReason === "aborted" || last.stopReason === "error") return "";
  const parts = Array.isArray(last.content) ? last.content : [];
  return parts
    .filter((p) => p?.type === "text" && typeof p.text === "string")
    .map((p) => p.text)
    .join("\n");
}

export default function (pi) {
  // `input` fires for each thing the owner submits, including steering and follow-up messages typed
  // while the agent is working; `source: "extension"` is another extension speaking, not the owner.
  pi.on("input", (event, ctx) => {
    try {
      if (event.source === "extension" || !CAPTURE_MODES.has(ctx.mode)) return;
      send("prompt", {
        ...base(ctx),
        hook_event_name: "UserPromptSubmit",
        prompt: event.text,
      });
    } catch {
      // fail open
    }
  });

  // `agent_end` is the analogue of Stop: the run is over and the final answer is in `messages`.
  pi.on("agent_end", (event, ctx) => {
    try {
      if (!CAPTURE_MODES.has(ctx.mode)) return;
      const answer = finalAnswer(event.messages ?? []);
      if (!answer.trim()) return;
      send("stop", { ...base(ctx), hook_event_name: "Stop", last_assistant_message: answer });
    } catch {
      // fail open
    }
  });
}
