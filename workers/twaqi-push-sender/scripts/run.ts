// Runs the push sender's run() under Node, for the scheduled sends in GitHub
// Actions (.github/workflows/push-sender.yml, FOX-71). The Workers Free plan
// allows 50 subrequests per run, too few for the sends, so the Worker keeps
// only the app API and the manual routes; this script calls the same run()
// from src/index.ts. No send logic lives here.
//
//   node --experimental-strip-types --no-warnings scripts/run.ts [--dry-run]
//
// The env is the `vars` in wrangler.jsonc plus four secrets from the process
// environment: FCM_SERVICE_ACCOUNT, DIRECTUS_PUSH_TOKEN, AQI_API_BASE and
// SYNC_TOKEN. Node has no Worker bindings, so PUSH_EVENTS is a collector: run()
// writes its per-send data points to it exactly as to Analytics Engine, and
// once run() has saved state and logs they are POSTed to the Worker's
// /internal/events (PUSH_SENDER_URL, SYNC_TOKEN), which writes them to the
// twaqi_push_events dataset. A failed forward is a warning: it never re-sends
// an alert and never fails the job.
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { MAX_EVENTS_PER_REQUEST } from '../src/events.ts'
import { run, type Env, type RunResult } from '../src/index.ts'

export const SECRETS = ['FCM_SERVICE_ACCOUNT', 'DIRECTUS_PUSH_TOKEN', 'AQI_API_BASE', 'SYNC_TOKEN'] as const

/** wrangler.jsonc → object: drops comments and trailing commas, leaving
 * string contents alone (the same parse as workers.yml's secrets step). */
export function parseJsonc(text: string): Record<string, unknown> {
  return JSON.parse(
    text
      .replace(/("(?:\\.|[^"\\])*")|\/\/[^\n]*|\/\*[\s\S]*?\*\//g, (_m, str) => str ?? '')
      .replace(/("(?:\\.|[^"\\])*")|,(\s*[}\]])/g, (_m, str, end) => str ?? end),
  )
}

/** The Worker's `vars` plus the secrets, as a plain object (no bindings). */
export function nodeEnv(config: string, source: Record<string, string | undefined>): Env {
  const vars = (parseJsonc(config).vars ?? {}) as Record<string, string>
  const missing = SECRETS.filter((name) => !source[name])
  if (missing.length) throw new Error(`Missing secrets: ${missing.join(', ')}`)
  return {
    ...vars,
    ...Object.fromEntries(SECRETS.map((name) => [name, source[name]])),
    // SUBREQUEST_LIMIT is the Worker's per-request cap (50 on Free). Node has
    // none, so it must not cut the run short; MAX_SENDS_PER_RUN still applies.
    SUBREQUEST_LIMIT: 'Infinity',
  } as unknown as Env
}

/** Only `--dry-run`; anything else (a typo like `--dry`) is refused rather
 * than turning into a real send. */
export function parseArgs(argv: string[]): { dryRun: boolean } {
  const unknown = argv.filter((arg) => arg !== '--dry-run')
  if (unknown.length) throw new Error(`Unknown arguments: ${unknown.join(' ')} (only --dry-run)`)
  return { dryRun: argv.includes('--dry-run') }
}

/** Why the job should fail after a run that finished, or null. A send FCM
 * refused (`failed`) fails it, after run() has saved state and logs, so a run
 * where FCM rejects every alert doesn't go green. Dead tokens (the device is
 * archived) and deferred sends (they go out next run) are expected. */
export function failure(result: RunResult): string | null {
  const failed = result.counts.failed ?? 0
  return failed ? `${failed} alert(s) failed to send; they stay unsent and are retried next run` : null
}

/** Stands in for the PUSH_EVENTS binding: keeps every data point run()
 * writes, to forward afterwards. */
export function eventCollector(): { dataset: AnalyticsEngineDataset; points: AnalyticsEngineDataPoint[] } {
  const points: AnalyticsEngineDataPoint[] = []
  return { dataset: { writeDataPoint: (point?: AnalyticsEngineDataPoint) => void points.push(point ?? {}) }, points }
}

export interface ForwardResult {
  /** Points collected. */
  events: number
  /** Points in requests the Worker accepted. */
  forwarded: number
  /** Points the Worker reports written to Analytics Engine. */
  written: number
  /** Points in requests that failed twice. */
  failed: number
  /** HTTP status (or "network") of the last failed request. */
  lastError?: string
}

/** POSTs the points to `${url}/internal/events` in chunks of 250, each tried
 * twice. Only talks to that URL, so it can't re-send an alert, and never
 * throws: what didn't make it is counted. */
export async function forwardEvents(
  points: AnalyticsEngineDataPoint[],
  options: { url: string; token: string; fetch?: typeof fetch; retryDelayMs?: number; chunkSize?: number },
): Promise<ForwardResult> {
  const { url, token, fetch: fetchImpl = fetch, retryDelayMs = 1000, chunkSize = MAX_EVENTS_PER_REQUEST } = options
  const endpoint = `${url.replace(/\/+$/, '')}/internal/events`
  const result: ForwardResult = { events: points.length, forwarded: 0, written: 0, failed: 0 }
  for (let i = 0; i < points.length; i += chunkSize) {
    const chunk = points.slice(i, i + chunkSize)
    let ok = false
    for (let attempt = 1; attempt <= 2 && !ok; attempt++) {
      if (attempt > 1) await new Promise((r) => setTimeout(r, retryDelayMs))
      try {
        const res = await fetchImpl(endpoint, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ events: chunk }),
          signal: AbortSignal.timeout(30_000),
        })
        if (res.ok) {
          const body = (await res.json().catch(() => ({}))) as { written?: unknown }
          result.forwarded += chunk.length
          result.written += typeof body.written === 'number' ? body.written : 0
          ok = true
        } else {
          result.lastError = `HTTP ${res.status}`
        }
      } catch {
        result.lastError = 'network'
      }
    }
    if (!ok) result.failed += chunk.length
  }
  return result
}

/** Runs `work`, then `forward` whether it resolved or threw: a run that
 * stops partway (a state write Directus kept refusing) has already sent some
 * alerts, and their events still go out. The run's error is rethrown, so the
 * job still fails. `forward` must not throw (forwardEvents doesn't). */
export async function runThenForward<T>(work: () => Promise<T>, forward: () => Promise<void>): Promise<T> {
  try {
    return await work()
  } finally {
    await forward()
  }
}

/** Forwards the collected points and logs counts only. Never throws. */
async function forwardCollected(points: AnalyticsEngineDataPoint[], token: string): Promise<void> {
  if (!points.length) return
  const url = process.env.PUSH_SENDER_URL
  if (!url) {
    console.log(`::warning::${points.length} push events not forwarded: PUSH_SENDER_URL is not set`)
    return
  }
  const forward = await forwardEvents(points, { url, token })
  const { lastError, ...counts } = forward
  console.log('events forwarded', JSON.stringify(counts))
  if (forward.failed) {
    console.log(`::warning::${forward.failed} of ${forward.events} push events not forwarded to Analytics Engine (${lastError})`)
  } else if (forward.written < forward.forwarded) {
    console.log(`::warning::Analytics Engine wrote ${forward.written} of ${forward.forwarded} forwarded push events`)
  }
}

async function main(): Promise<void> {
  const { dryRun } = parseArgs(process.argv.slice(2))
  const config = readFileSync(new URL('../wrangler.jsonc', import.meta.url), 'utf8')
  const collector = eventCollector()
  const env = { ...nodeEnv(config, process.env), PUSH_EVENTS: collector.dataset }
  // Events are forwarded once run() has saved state and logs, or has thrown.
  // That is separate from the exit code below.
  const result = await runThenForward(
    () => run(env, { dryRun }),
    () => forwardCollected(collector.points, env.SYNC_TOKEN),
  )
  // The log is public (public repo): counts only, never device ids, token
  // suffixes or per-device decisions.
  const { decisions, archivedDevices, ...summary } = result
  const failed = failure(result)
  console.log(
    failed ? 'run finished with failures' : 'run ok',
    JSON.stringify({ ...summary, archivedDevices: archivedDevices.length, decisions: decisions?.length }),
  )

  if (failed) {
    console.error(`::error::${failed}`)
    process.exitCode = 1
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((e) => {
    console.error('run failed', e)
    process.exitCode = 1
  })
}
