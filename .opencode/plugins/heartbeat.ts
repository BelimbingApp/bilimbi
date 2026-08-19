// Bilimbi AI-team heartbeat for opencode agents (docs/ai-team/README.md).
//
// Mechanism: opencode has no timer hook, but plugins receive `session.idle`
// events. On idle we arm a timer (10–30 min, adaptive); when it fires we run
// the /heartbeat command in that idle session via the SDK, which executes the
// tick protocol in .opencode/command/heartbeat.md.
//
// The timer re-arms on every session.idle, so an actively-used session never
// interrupts the user: the heartbeat only fires after `interval_ms` of
// idleness. State (.opencode/heartbeat/) is gitignored runtime state.
//
// Activation: restart opencode in this repository; plugins and commands load
// at startup. Identity is `BILIMBI_AGENT_ID` (default opencode/deepseek-v4-pro).
// Halt: the tick protocol calls heartbeat_schedule({halted:true}) when the
// board carries `halt <id>` or `halt all`.
import type { Plugin } from "@opencode-ai/plugin"
import { tool } from "@opencode-ai/plugin"
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { dirname, join } from "node:path"

const DEFAULT_AGENT = process.env.BILIMBI_AGENT_ID ?? "opencode/deepseek-v4-pro"
const REPO = process.env.BILIMBI_REPO ?? "BelimbingApp/bilimbi"
const BOARD = 208
const MIN_MS = 10 * 60 * 1000
const MAX_MS = 30 * 60 * 1000

type State = {
  halted: boolean
  interval_ms: number
  idle_streak: number
  last_tick: string | null
  last_session: string | null
}

function statePath(directory: string) {
  return join(directory, ".opencode", "heartbeat", "state.json")
}

function loadState(directory: string): State {
  const path = statePath(directory)
  const fallback: State = {
    halted: false,
    interval_ms: MIN_MS,
    idle_streak: 0,
    last_tick: null,
    last_session: null,
  }
  try {
    if (!existsSync(path)) return fallback
    return { ...fallback, ...JSON.parse(readFileSync(path, "utf8")) }
  } catch {
    return fallback
  }
}

function saveState(directory: string, state: State) {
  const path = statePath(directory)
  mkdirSync(dirname(path), { recursive: true })
  writeFileSync(path, JSON.stringify(state, null, 2) + "\n")
}

function sessionIdFromEvent(event: { type?: string; properties?: Record<string, unknown> }) {
  const props = event.properties ?? {}
  const id = props.sessionID ?? props.sessionId ?? props.id
  return typeof id === "string" ? id : null
}

export const HeartbeatPlugin: Plugin = async ({ client, directory, $ }) => {
  let timer: ReturnType<typeof setTimeout> | undefined
  let inflight = false

  const log = (message: string, extra?: Record<string, unknown>) =>
    client.app.log({
      body: { service: "bilimbi-heartbeat", level: "info", message, extra },
    })

  const clearTimer = () => {
    if (timer) clearTimeout(timer)
    timer = undefined
  }

  const fire = async (sessionID: string) => {
    const state = loadState(directory)
    if (state.halted || inflight) return
    inflight = true
    try {
      await client.session.command({
        path: { id: sessionID },
        body: { command: "heartbeat" },
      })
    } catch {
      await client.session.prompt({
        path: { id: sessionID },
        body: {
          parts: [
            {
              type: "text",
              text: "Run the /heartbeat command now. Follow .opencode/command/heartbeat.md exactly.",
            },
          ],
        },
      })
    } finally {
      inflight = false
    }
  }

  const schedule = (sessionID: string) => {
    const state = loadState(directory)
    if (state.halted) return
    clearTimer()
    state.last_session = sessionID
    saveState(directory, state)
    timer = setTimeout(() => {
      void fire(sessionID)
    }, state.interval_ms)
    void log("scheduled", { sessionID, interval_ms: state.interval_ms })
  }

  return {
    event: async ({ event }) => {
      if (event.type === "session.idle") {
        const id = sessionIdFromEvent(event)
        if (id) schedule(id)
      }
      if (event.type === "session.deleted") {
        const id = sessionIdFromEvent(event)
        const state = loadState(directory)
        if (id && state.last_session === id) clearTimer()
      }
    },
    tool: {
      heartbeat_presence: tool({
        description:
          "Create or edit the single #208 presence tick for this agent. Edits in place when the <!-- tick:id --> marker exists.",
        args: {
          status: tool.schema
            .string()
            .describe("One line after the timestamp, e.g. idle (nothing actionable)"),
        },
        async execute(args) {
          const agent = DEFAULT_AGENT
          const marker = `<!-- tick:${agent} -->`
          const stamp = new Date().toISOString().replace(/\.\d{3}Z$/, "Z")
          const body = `${marker}\n**From:** ${agent}\n\ntick ${agent} · ${stamp} · ${args.status}`
          const payloadPath = join(directory, ".opencode", "heartbeat", "payload.json")
          mkdirSync(dirname(payloadPath), { recursive: true })
          writeFileSync(payloadPath, JSON.stringify({ body }))

          const listed = await $`gh api repos/${REPO}/issues/${BOARD}/comments --paginate`.text()
          const comments = JSON.parse(listed) as Array<{ id: number; body?: string }>
          const existing = comments.find((comment) => comment.body?.includes(marker))

          if (existing) {
            await $`gh api -X PATCH repos/${REPO}/issues/comments/${existing.id} --input ${payloadPath}`
            return `updated comment ${existing.id}`
          }

          await $`gh api -X POST repos/${REPO}/issues/${BOARD}/comments --input ${payloadPath}`
          return "created presence comment"
        },
      }),
      heartbeat_schedule: tool({
        description:
          "Adjust the adaptive heartbeat interval. Pass idle=true after a no-work tick, idle=false after real work. interval_ms overrides. halted stops the loop.",
        args: {
          idle: tool.schema.boolean().optional(),
          interval_ms: tool.schema.number().optional(),
          halted: tool.schema.boolean().optional(),
        },
        async execute(args) {
          const state = loadState(directory)
          if (typeof args.halted === "boolean") state.halted = args.halted
          if (args.idle === true) {
            state.idle_streak += 1
            state.interval_ms = Math.min(MAX_MS, Math.round(state.interval_ms * 1.5))
          } else if (args.idle === false) {
            state.idle_streak = 0
            state.interval_ms = MIN_MS
          }
          if (typeof args.interval_ms === "number") {
            state.interval_ms = Math.min(MAX_MS, Math.max(MIN_MS, args.interval_ms))
          }
          state.last_tick = new Date().toISOString()
          saveState(directory, state)
          if (state.halted) clearTimer()
          else if (state.last_session) schedule(state.last_session)
          return JSON.stringify(state)
        },
      }),
    },
  }
}
