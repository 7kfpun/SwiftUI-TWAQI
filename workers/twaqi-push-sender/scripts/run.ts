// Runs the push sender's run() under Node, for the scheduled sends in GitHub
// Actions (.github/workflows/push-sender.yml, FOX-71). The Workers Free plan
// allows 50 subrequests per run, too few for the sends, so the Worker keeps
// only the app API and the manual routes; this script calls the same run()
// from src/index.ts. No send logic lives here.
//
//   node --experimental-strip-types --no-warnings scripts/run.ts [--dry-run]
//
// The env is the `vars` in wrangler.jsonc plus three secrets from the process
// environment: FCM_SERVICE_ACCOUNT, DIRECTUS_PUSH_TOKEN, AQI_API_BASE. There
// are no Worker bindings: PUSH_EVENTS (Analytics Engine) is absent, so sends
// are counted only in Directus logs (failures, dead tokens). SYNC_TOKEN gates
// the Worker's HTTP routes and isn't needed here.
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { run, type Env, type RunResult } from '../src/index.ts'

export const SECRETS = ['FCM_SERVICE_ACCOUNT', 'DIRECTUS_PUSH_TOKEN', 'AQI_API_BASE'] as const

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

async function main(): Promise<void> {
  const { dryRun } = parseArgs(process.argv.slice(2))
  const config = readFileSync(new URL('../wrangler.jsonc', import.meta.url), 'utf8')
  const result = await run(nodeEnv(config, process.env), { dryRun })
  // The log is public (public repo): counts only, no per-device decisions.
  const { decisions, ...summary } = result
  const failed = failure(result)
  console.log(failed ? 'run finished with failures' : 'run ok', JSON.stringify({ ...summary, decisions: decisions?.length }))
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
