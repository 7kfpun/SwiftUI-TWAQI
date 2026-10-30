import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { decide, isInZone, isQuiet, localMinutes, minutesOfDay, publishedAt } from '../src/rules.ts'

// 2026-10-31 14:30 in Taipei / Hong Kong (UTC+8).
const afternoon = new Date('2026-10-31T06:30:00Z')
// 2026-10-31 23:30 in Taipei.
const lateNight = new Date('2026-10-31T15:30:00Z')
// 2026-11-01 06:59 in Taipei.
const earlyMorning = new Date('2026-10-31T22:59:00Z')

const base = {
  direction: 'above' as const,
  threshold: 100,
  value: 120,
  wasInZone: false,
  lastFiredAt: null,
  quiet: false,
  now: afternoon,
  cooldownMinutes: 180,
}

describe('isInZone', () => {
  it('is strict on both sides', () => {
    assert.equal(isInZone('above', 100, 101), true)
    assert.equal(isInZone('above', 100, 100), false)
    assert.equal(isInZone('below', 30, 29), true)
    assert.equal(isInZone('below', 30, 30), false)
  })
})

describe('decide', () => {
  it('fires on entering the zone', () => {
    assert.deepEqual(decide(base), { outcome: 'fire', inZone: true })
  })

  it('fires for a new subscription that starts in the zone', () => {
    assert.equal(decide({ ...base, wasInZone: null }).outcome, 'fire')
  })

  it('does not fire again while still in the zone', () => {
    assert.deepEqual(decide({ ...base, wasInZone: true }), { outcome: 'still-in', inZone: true })
  })

  it('leaves the zone, then fires on the next crossing', () => {
    const left = decide({ ...base, value: 80, wasInZone: true })
    assert.deepEqual(left, { outcome: 'out', inZone: false })
    const back = decide({ ...base, value: 130, wasInZone: left.inZone })
    assert.equal(back.outcome, 'fire')
  })

  it('handles "below"', () => {
    assert.equal(decide({ ...base, direction: 'below', threshold: 30, value: 20 }).outcome, 'fire')
    assert.equal(decide({ ...base, direction: 'below', threshold: 30, value: 40 }).outcome, 'out')
  })

  it('drops the alert in quiet hours but records the crossing', () => {
    const quiet = decide({ ...base, quiet: true })
    assert.deepEqual(quiet, { outcome: 'quiet', inZone: true })
    // No backlog: the next run, after quiet hours, does not send it late.
    assert.equal(decide({ ...base, wasInZone: quiet.inZone }).outcome, 'still-in')
  })

  it('holds back a crossing inside the cool-down', () => {
    const lastFiredAt = new Date(afternoon.getTime() - 60 * 60_000).toISOString()
    assert.deepEqual(decide({ ...base, lastFiredAt }), { outcome: 'cooldown', inZone: true })
  })

  it('fires once the cool-down has passed', () => {
    const lastFiredAt = new Date(afternoon.getTime() - 181 * 60_000).toISOString()
    assert.equal(decide({ ...base, lastFiredAt }).outcome, 'fire')
  })
})

describe('quiet hours', () => {
  const overnight = { dnd_enabled: true, dnd_start: '23:00', dnd_end: '07:00', timezone: 'Asia/Hong_Kong' }

  it('reads HH:mm and HH:mm:ss', () => {
    assert.equal(minutesOfDay('07:30'), 450)
    assert.equal(minutesOfDay('23:00:00'), 1380)
    assert.equal(minutesOfDay('25:00'), null)
    assert.equal(minutesOfDay(null), null)
  })

  it('uses the device time zone', () => {
    assert.equal(localMinutes(afternoon, 'Asia/Hong_Kong'), 14 * 60 + 30)
    assert.equal(localMinutes(afternoon, 'Europe/London'), 6 * 60 + 30)
    assert.equal(localMinutes(afternoon, 'Not/AZone'), 14 * 60 + 30)
  })

  it('wraps past midnight', () => {
    assert.equal(isQuiet(overnight, lateNight), true)
    assert.equal(isQuiet(overnight, earlyMorning), true)
    assert.equal(isQuiet(overnight, afternoon), false)
  })

  it('handles a same-day window', () => {
    const lunch = { ...overnight, dnd_start: '12:00', dnd_end: '15:00' }
    assert.equal(isQuiet(lunch, afternoon), true)
    assert.equal(isQuiet(lunch, lateNight), false)
  })

  it('includes the start and excludes the end', () => {
    const window = { ...overnight, dnd_start: '14:30', dnd_end: '15:00' }
    assert.equal(isQuiet(window, afternoon), true)
    assert.equal(isQuiet({ ...window, dnd_start: '14:00', dnd_end: '14:30' }, afternoon), false)
  })

  it('is off when disabled, empty or unreadable', () => {
    assert.equal(isQuiet({ ...overnight, dnd_enabled: false }, lateNight), false)
    assert.equal(isQuiet({ ...overnight, dnd_end: '23:00' }, lateNight), false)
    assert.equal(isQuiet({ ...overnight, dnd_start: null }, lateNight), false)
  })
})

describe('publishedAt', () => {
  it('reads publish_time as Taiwan time', () => {
    assert.equal(publishedAt('2026-10-31T14:00:00')?.toISOString(), '2026-10-31T06:00:00.000Z')
    assert.equal(publishedAt('2026-10-31T14:00:00Z')?.toISOString(), '2026-10-31T14:00:00.000Z')
    assert.equal(publishedAt(''), null)
  })
})
