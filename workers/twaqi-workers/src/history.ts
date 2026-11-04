// Hourly station-cam history: one frame per site per Taiwan clock hour.
//
//   stations/{siteId}/{yyyy-MM-dd}/{HH}.jpg   e.g. stations/001/2026-10-30/22.jpg
//
// The app builds these URLs from a site id and an hour, so it never lists the
// bucket. The sync lists it about once an hour to delete every hourly object
// outside the 24 hours the app shows (`staleHourKeys`). Kept to plain
// functions (no Workers APIs) so they can be tested with `node --test`.

/**
 * Days of hourly frames kept in R2: 1, so each site holds the 24 clock-hour
 * slots the app scrubs and nothing else. The app keeps its own offline copies
 * for up to a week.
 */
export const HISTORY_DAYS = 1

/** Hourly objects never change once written. */
export const HISTORY_CACHE_CONTROL = 'public, max-age=86400'

const STAMP = /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})$/
const HOUR_KEY = /^stations\/([0-9A-Za-z]+)\/(\d{4})-(\d{2})-(\d{2})\/(\d{2})\.jpg$/

/**
 * `001`, `202610302210` → `stations/001/2026-10-30/22.jpg`.
 *
 * MOENV stamps are already Taiwan local time (UTC+8, no DST), so the date and
 * hour are read straight off the stamp. Null for a malformed stamp.
 */
export function hourKey(siteId: string, stamp: string): string | null {
  const m = stamp.match(STAMP)
  if (!m) return null
  const [, y, mo, d, h] = m
  return `stations/${siteId}/${y}-${mo}-${d}/${h}.jpg`
}

/**
 * `stations/001/2026-10-30/22.jpg` → its site and clock hour, the hour as a
 * count of hours (Taiwan wall clock read as UTC: no DST, so a day is always
 * 24). Null for any other key, such as the latest `stations/001.jpg`.
 */
export function parseHourKey(key: string): { siteId: string; hour: number } | null {
  const m = key.match(HOUR_KEY)
  if (!m) return null
  const [, siteId, y, mo, d, h] = m
  const ms = Date.UTC(Number(y), Number(mo) - 1, Number(d), Number(h))
  return Number.isNaN(ms) ? null : { siteId, hour: ms / 3_600_000 }
}

/**
 * The hourly objects to delete: every hourly key outside the
 * `HISTORY_DAYS × 24` clock hours up to and including its site's anchor hour.
 *
 * `anchors` maps a site id to the hourly key last filed for it (the
 * manifest's `hourKey`), which is the hour the app's scrubber ends on. A site
 * that stopped reporting keeps the 24 hours before it stopped, as the app
 * still shows them. Keys of a site with no anchor are measured against the
 * newest anchor of all. Anything that isn't an hourly key is kept.
 */
export function staleHourKeys(
  keys: Iterable<string>,
  anchors: Record<string, string | undefined>,
  days = HISTORY_DAYS,
): string[] {
  const anchorHours = new Map<string, number>()
  let newest: number | undefined
  for (const [siteId, key] of Object.entries(anchors)) {
    const hour = key ? parseHourKey(key)?.hour : undefined
    if (hour === undefined) continue
    anchorHours.set(siteId, hour)
    if (newest === undefined || hour > newest) newest = hour
  }
  const window = days * 24
  const stale: string[] = []
  for (const key of keys) {
    const parsed = parseHourKey(key)
    if (!parsed) continue
    const anchor = anchorHours.get(parsed.siteId) ?? newest
    if (anchor !== undefined && parsed.hour <= anchor - window) stale.push(key)
  }
  return stale
}

/**
 * The newest anchor hour as its `yyyy-MM-dd/HH` (e.g. `2026-10-30/22`), or
 * null when there is none. The sync sweeps once each time this changes, so
 * about once an hour rather than every 10 minutes.
 */
export function sweepHour(anchors: Record<string, string | undefined>): string | null {
  let best: { hour: number; key: string } | null = null
  for (const key of Object.values(anchors)) {
    const parsed = key ? parseHourKey(key) : null
    if (parsed && (!best || parsed.hour > best.hour)) best = { hour: parsed.hour, key: key! }
  }
  return best ? best.key.replace(/^stations\/[0-9A-Za-z]+\//, '').replace(/\.jpg$/, '') : null
}

/**
 * Whether a frame should be written as its hour's history object.
 *
 * The first frame seen in each clock hour is kept — the :00 frame whenever a
 * sync picks it up, otherwise the earliest one after it (a missed sync or a
 * site that skipped :00). Later frames in the same hour are not, so a site
 * gets at most 24 history objects a day, not one per 10-minute frame.
 *
 * `lastHourKey` is the hourly key last written for the site (kept in the
 * manifest), or undefined before the first. A forced sync doesn't change
 * this: re-filing would replace an hour's :00 frame with a later one.
 */
export function shouldWriteHour(key: string | null, lastHourKey: string | undefined): key is string {
  return key !== null && key !== lastHourKey
}

/** `/station-cams/stations/001/2026-10-30/22.jpg` → `stations/001/2026-10-30/22.jpg`. */
export const HISTORY_ROUTE = /^\/station-cams\/(stations\/[0-9A-Za-z]+\/\d{4}-\d{2}-\d{2}\/\d{2}\.jpg)$/
