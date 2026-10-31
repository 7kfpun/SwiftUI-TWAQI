// Hourly station-cam history: one frame per site per Taiwan clock hour.
//
//   stations/{siteId}/{yyyy-MM-dd}/{HH}.jpg   e.g. stations/001/2026-10-30/22.jpg
//
// The app builds these URLs from a site id and an hour, so nothing has to list
// the bucket. Kept to plain functions (no Workers APIs) so they can be tested
// with `node --test`.

/** Days of hourly frames kept in R2. The app scrubs 24 hours and keeps its own copies at most a week. */
export const HISTORY_DAYS = 7

/** Hourly objects never change once written. */
export const HISTORY_CACHE_CONTROL = 'public, max-age=86400'

const STAMP = /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})$/

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
 * The hourly key `days` before the one `stamp` falls in: what to delete when
 * that hour is written, so R2 keeps a rolling `days` of history without
 * listing the bucket.
 */
export function expiredHourKey(siteId: string, stamp: string, days = HISTORY_DAYS): string | null {
  const m = stamp.match(STAMP)
  if (!m) return null
  const [, y, mo, d, h] = m.map(Number)
  // Wall-clock arithmetic in UTC: Taiwan has no DST, so a day is always 24 h.
  const t = new Date(Date.UTC(y, mo - 1, d - days, h))
  const pad = (n: number) => String(n).padStart(2, '0')
  return `stations/${siteId}/${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}/${pad(t.getUTCHours())}.jpg`
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
