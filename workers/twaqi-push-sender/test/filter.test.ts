import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { crossingFilter } from '../src/directus.ts'
import { decide } from '../src/rules.ts'

// Just enough of Directus's filter rules to run crossingFilter against rows.
type Row = Record<string, unknown>
function matches(filter: Record<string, unknown>, row: Row): boolean {
  return Object.entries(filter).every(([key, cond]) => {
    if (key === '_and') return (cond as Record<string, unknown>[]).every((f) => matches(f, row))
    if (key === '_or') return (cond as Record<string, unknown>[]).some((f) => matches(f, row))
    const value = row[key]
    const ops = cond as Record<string, unknown>
    return Object.entries(ops).every(([op, arg]) => {
      switch (op) {
        case '_eq': return value === arg
        case '_lt': return (value as number) < (arg as number)
        case '_lte': return (value as number) <= (arg as number)
        case '_gt': return (value as number) > (arg as number)
        case '_gte': return (value as number) >= (arg as number)
        case '_null': return (value === null || value === undefined) === arg
        case '_nnull': return (value !== null && value !== undefined) === arg
        default:
          // A relation: { device: { archived: { _eq: false } } }
          return matches({ [op]: arg }, (value ?? {}) as Row)
      }
    })
  })
}

const device = { archived: false, fcm_token: 'tok' }
const sub = (over: Row): Row => ({
  station_id: '105', direction: 'above', threshold: 120, in_zone: false,
  enabled: true, archived: false, metric: 'aqi', device, ...over,
})

describe('crossingFilter', () => {
  const at = (aqi: number) => crossingFilter([{ stationId: 105, aqi }])

  it('returns an "above" alert that just crossed in, not one still outside', () => {
    assert.equal(matches(at(121), sub({})), true)
    assert.equal(matches(at(120), sub({})), true) // equal counts: inclusive
    assert.equal(matches(at(119), sub({})), false)
    assert.equal(matches(at(80), sub({})), false)
    // New rows (in_zone null) count as outside.
    assert.equal(matches(at(121), sub({ in_zone: null })), true)
  })

  it('returns an "above" alert to re-arm once AQI falls back, not one still inside', () => {
    assert.equal(matches(at(119), sub({ in_zone: true })), true)
    assert.equal(matches(at(120), sub({ in_zone: true })), false)
    assert.equal(matches(at(150), sub({ in_zone: true })), false)
  })

  it('mirrors it for "below"', () => {
    const below = (over: Row) => sub({ direction: 'below', threshold: 30, ...over })
    assert.equal(matches(at(29), below({})), true)
    assert.equal(matches(at(30), below({})), true)
    assert.equal(matches(at(31), below({})), false)
    assert.equal(matches(at(31), below({ in_zone: true })), true)
    assert.equal(matches(at(30), below({ in_zone: true })), false)
  })

  it('only reads the stations it was given', () => {
    assert.equal(matches(at(200), sub({ station_id: '126' })), false)
    const both = crossingFilter([{ stationId: 105, aqi: 80 }, { stationId: 126, aqi: 200 }])
    assert.equal(matches(both, sub({ station_id: '126' })), true)
    assert.equal(matches(both, sub({ station_id: '105' })), false)
  })

  it('skips switched-off, archived, other-metric and unreachable rows', () => {
    assert.equal(matches(at(200), sub({ enabled: false })), false)
    assert.equal(matches(at(200), sub({ archived: true })), false)
    assert.equal(matches(at(200), sub({ metric: 'pm25' })), false)
    assert.equal(matches(at(200), sub({ metric: null })), true)
    assert.equal(matches(at(200), sub({ device: { archived: true, fcm_token: 'tok' } })), false)
    assert.equal(matches(at(200), sub({ device: { archived: false, fcm_token: null } })), false)
  })

  it('agrees with decide(): every row it returns changes state, and no row it skips does', () => {
    for (const direction of ['above', 'below'] as const) {
      for (const threshold of [30, 100, 120]) {
        for (const inZone of [true, false, null]) {
          for (const aqi of [29, 30, 31, 99, 100, 101, 119, 120, 121, 200]) {
            const row = sub({ direction, threshold, in_zone: inZone })
            const d = decide({ direction, threshold, value: aqi, wasInZone: inZone, lastFiredAt: null, quiet: false, now: new Date(), cooldownMinutes: 180 })
            const changes = d.outcome === 'fire' || d.inZone !== (inZone === true)
            assert.equal(matches(at(aqi), row), changes, `${direction} ${threshold} in_zone=${inZone} aqi=${aqi}`)
          }
        }
      }
    }
  })
})
