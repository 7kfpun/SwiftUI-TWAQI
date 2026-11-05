// Per-send analytics (Workers Analytics Engine, dataset twaqi_push_events,
// binding PUSH_EVENTS). One data point per send, in one shape, whether it is
// written by the Worker itself (/run, /test) or forwarded by the GitHub
// Actions run through POST /internal/events (FOX-71): the queries on the
// dataset read blob1..blob6, index1 and double1 by position.
import type { PushLog } from './directus.ts'

/** Analytics Engine takes at most 250 writeDataPoint calls per Worker
 * invocation (developers.cloudflare.com/analytics/analytics-engine/limits). */
export const MAX_EVENTS_PER_REQUEST = 250

const STATUSES = new Set<string>(['sent', 'failed', 'unregistered'])
const TRIGGERS = new Set<string>(['pollution', 'cleanliness', 'test'])
/** Analytics Engine: an index is at most 96 bytes; a point's blobs 16 KB. */
const MAX_INDEX_BYTES = 96
const MAX_BLOB_BYTES = 16 * 1024

/** A send as a data point: index station; blobs status, trigger, station,
 * error code, token suffix, device id; double AQI. */
export function pushEventPoint(log: PushLog): AnalyticsEngineDataPoint {
  return {
    indexes: [log.station ?? ''],
    blobs: [log.status, log.trigger, log.station ?? '', log.error_code ?? '', log.token_suffix, String(log.device)],
    doubles: [log.aqi ?? 0],
  }
}

/** Writes each point, never throwing; returns how many were written. */
export function writePushEvents(dataset: AnalyticsEngineDataset, points: AnalyticsEngineDataPoint[]): number {
  let written = 0
  for (const point of points) {
    try {
      dataset.writeDataPoint(point)
      written++
    } catch (e) {
      console.warn('push event write failed', String(e))
    }
  }
  return written
}

/** The body of POST /internal/events: `{ "events": [point, …] }`, each point
 * exactly the shape pushEventPoint makes. Returns the points, or why not. */
export function parseEvents(body: unknown): AnalyticsEngineDataPoint[] | string {
  const events = (body as { events?: unknown } | null)?.events
  if (!Array.isArray(events)) return 'events must be an array'
  if (events.length > MAX_EVENTS_PER_REQUEST) return `at most ${MAX_EVENTS_PER_REQUEST} events per request`
  for (const [i, event] of events.entries()) {
    const problem = pointProblem(event)
    if (problem) return `events[${i}]: ${problem}`
  }
  return events as AnalyticsEngineDataPoint[]
}

function pointProblem(event: unknown): string | null {
  if (!event || typeof event !== 'object' || Array.isArray(event)) return 'not an object'
  const { indexes, blobs, doubles, ...rest } = event as Record<string, unknown>
  if (Object.keys(rest).length) return `unknown field ${Object.keys(rest)[0]}`
  const bytes = (s: string) => new TextEncoder().encode(s).byteLength
  if (!Array.isArray(indexes) || indexes.length !== 1 || typeof indexes[0] !== 'string' || bytes(indexes[0]) > MAX_INDEX_BYTES) {
    return 'indexes must be one string of at most 96 bytes'
  }
  if (!Array.isArray(blobs) || blobs.length !== 6 || !blobs.every((b) => typeof b === 'string')) return 'blobs must be 6 strings'
  if (!STATUSES.has(blobs[0])) return 'blobs[0] must be a status'
  if (!TRIGGERS.has(blobs[1])) return 'blobs[1] must be a trigger'
  if (bytes(blobs.join('')) > MAX_BLOB_BYTES) return 'blobs over 16 KB'
  if (!Array.isArray(doubles) || doubles.length !== 1 || typeof doubles[0] !== 'number' || !Number.isFinite(doubles[0])) {
    return 'doubles must be one finite number'
  }
  return null
}
