// When an alert fires. Pure functions only, so they can be tested with
// `node --test` without a Workers runtime.

export type Direction = 'above' | 'below'

/** Whether `value` is past the threshold the user set. "Above 100" means
 * more than 100, "below 30" less than 30; equal is outside both. */
export function isInZone(direction: Direction, threshold: number, value: number): boolean {
  return direction === 'above' ? value > threshold : value < threshold
}

/** `"HH:mm"` or `"HH:mm:ss"` → minutes after midnight, or null if unreadable. */
export function minutesOfDay(time: string | null | undefined): number | null {
  const m = /^(\d{1,2}):(\d{2})/.exec(time ?? '')
  if (!m) return null
  const h = Number(m[1])
  const min = Number(m[2])
  if (h > 23 || min > 59) return null
  return h * 60 + min
}

/** Wall-clock minutes after midnight at `now` in `timeZone`. An unknown zone
 * falls back to Asia/Taipei, which is where every station is. */
export function localMinutes(now: Date, timeZone: string | null | undefined): number {
  const format = (zone: string) =>
    new Intl.DateTimeFormat('en-GB', { timeZone: zone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
      .formatToParts(now)
  let parts: Intl.DateTimeFormatPart[]
  try {
    parts = format(timeZone || 'Asia/Taipei')
  } catch {
    parts = format('Asia/Taipei')
  }
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? 0)
  return get('hour') * 60 + get('minute')
}

export interface QuietHours {
  dnd_enabled?: boolean | null
  dnd_start?: string | null
  dnd_end?: string | null
  timezone?: string | null
}

/** Whether `now` falls in the device's do-not-disturb window. The window
 * includes its start and excludes its end, and may run past midnight
 * (23:00–07:00). Start equal to end, or an unreadable time, means no window. */
export function isQuiet(device: QuietHours, now: Date): boolean {
  if (!device.dnd_enabled) return false
  const start = minutesOfDay(device.dnd_start)
  const end = minutesOfDay(device.dnd_end)
  if (start === null || end === null || start === end) return false
  const t = localMinutes(now, device.timezone)
  return start < end ? t >= start && t < end : t >= start || t < end
}

export type Outcome =
  /** Just crossed into the zone: send. Mark in_zone only once APNs accepts it. */
  | 'fire'
  /** Outside the zone. */
  | 'out'
  /** Already in the zone last time; the alert for this crossing has gone. */
  | 'still-in'
  /** Crossed in during quiet hours. Dropped, not held for later. */
  | 'quiet'
  /** Crossed in again too soon after the last alert (the value is bouncing
   * around the threshold). */
  | 'cooldown'

export interface Decision {
  outcome: Outcome
  /** in_zone to store after this run. For 'fire', only if the send succeeds. */
  inZone: boolean
}

/** Edge trigger: alert on entering the zone, not on every run spent inside
 * it. A new subscription (in_zone null) that starts inside the zone counts as
 * entering it. Quiet hours and the cool-down both still record the crossing,
 * so a skipped alert is not sent late when they end. */
export function decide(input: {
  direction: Direction
  threshold: number
  value: number
  wasInZone: boolean | null | undefined
  lastFiredAt: string | null | undefined
  quiet: boolean
  now: Date
  cooldownMinutes: number
}): Decision {
  if (!isInZone(input.direction, input.threshold, input.value)) {
    return { outcome: 'out', inZone: false }
  }
  if (input.wasInZone === true) return { outcome: 'still-in', inZone: true }
  if (input.quiet) return { outcome: 'quiet', inZone: true }

  const last = input.lastFiredAt ? Date.parse(input.lastFiredAt) : NaN
  if (Number.isFinite(last) && input.now.getTime() - last < input.cooldownMinutes * 60_000) {
    return { outcome: 'cooldown', inZone: true }
  }
  return { outcome: 'fire', inZone: true }
}

/** The AQI API's `publish_time` is Taiwan local time without an offset. */
export function publishedAt(publishTime: string | null | undefined): Date | null {
  if (!publishTime) return null
  const withZone = /[zZ]|[+-]\d{2}:?\d{2}$/.test(publishTime) ? publishTime : `${publishTime}+08:00`
  const t = Date.parse(withZone)
  return Number.isFinite(t) ? new Date(t) : null
}
