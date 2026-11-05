// Run with `npm test` (Node 23.6+ strips the types; no extra dependencies).
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { HISTORY_ROUTE, hourKey, parseHourKey, shouldWriteHour, staleHourKeys, sweepDue, sweepHour } from '../src/history.ts'

test('hour key comes straight off the Taiwan-local MOENV stamp', () => {
  assert.equal(hourKey('001', '202610302200'), 'stations/001/2026-10-30/22.jpg')
  assert.equal(hourKey('001', '202610302250'), 'stations/001/2026-10-30/22.jpg')
  // Midnight in Taiwan is still the same calendar day there, not UTC's previous one.
  assert.equal(hourKey('204', '202611010005'), 'stations/204/2026-11-01/00.jpg')
  assert.equal(hourKey('001', 'nope'), null)
})

test('hour key parses back to its site and hour; other keys are not hourly', () => {
  const a = parseHourKey('stations/001/2026-10-30/22.jpg')
  const b = parseHourKey('stations/001/2026-10-31/00.jpg')
  assert.equal(a?.siteId, '001')
  assert.equal(b!.hour - a!.hour, 2)
  // Across a year end: still one hour apart.
  assert.equal(parseHourKey('stations/001/2027-01-01/00.jpg')!.hour - parseHourKey('stations/001/2026-12-31/23.jpg')!.hour, 1)
  assert.equal(parseHourKey('stations/001.jpg'), null)
  assert.equal(parseHourKey('manifest.json'), null)
  assert.equal(parseHourKey('forecast/last-sync.json'), null)
})

/** `stations/{site}/{day}/{HH}.jpg` for each of the `n` hours ending at `day` `endHour`, newest last. */
function hoursEnding(site: string, day: string, endHour: number, n: number): string[] {
  const end = Date.UTC(Number(day.slice(0, 4)), Number(day.slice(5, 7)) - 1, Number(day.slice(8, 10)), endHour)
  const pad = (x: number) => String(x).padStart(2, '0')
  return Array.from({ length: n }, (_, i) => {
    const t = new Date(end - (n - 1 - i) * 3_600_000)
    return `stations/${site}/${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}/${pad(t.getUTCHours())}.jpg`
  })
}

test('sweep keeps exactly the 24 hours up to the anchor, across a month end', () => {
  const keys = hoursEnding('001', '2026-11-01', 5, 48)
  const stale = staleHourKeys(keys, { '001': 'stations/001/2026-11-01/05.jpg' })
  assert.deepEqual(stale, keys.slice(0, 24))
  assert.equal(stale.at(-1), 'stations/001/2026-10-31/05.jpg')
  assert.equal(keys[24], 'stations/001/2026-10-31/06.jpg') // oldest slot kept
})

test('sweep catches what the old same-hour-yesterday delete left behind', () => {
  // 2026-11-02 12:00 was never filed (cam down), so 2026-11-01 12:00 outlived
  // its day; frames from the 7-day retention era are still there too.
  const keys = [
    'stations/001/2026-10-29/03.jpg',
    'stations/001/2026-11-01/12.jpg',
    'stations/001/2026-11-04/12.jpg',
    'stations/001/2026-11-05/01.jpg',
  ]
  assert.deepEqual(staleHourKeys(keys, { '001': 'stations/001/2026-11-05/01.jpg' }), [
    'stations/001/2026-10-29/03.jpg',
    'stations/001/2026-11-01/12.jpg',
  ])
})

test('sweep measures each site from its own anchor and never touches non-hourly keys', () => {
  const keys = [
    'stations/001.jpg',
    'stations/002.jpg',
    'manifest.json',
    // 002 stopped reporting at 2026-11-02 10:00: its last 24 hours stay, as the app still shows them.
    'stations/002/2026-11-01/11.jpg',
    'stations/002/2026-11-01/10.jpg',
    // 003 has no anchor: measured against the newest anchor (001's).
    'stations/003/2026-11-04/02.jpg',
    'stations/003/2026-11-04/01.jpg',
  ]
  const anchors = {
    '001': 'stations/001/2026-11-05/01.jpg',
    '002': 'stations/002/2026-11-02/10.jpg',
    '004': undefined,
  }
  assert.deepEqual(staleHourKeys(keys, anchors), ['stations/002/2026-11-01/10.jpg', 'stations/003/2026-11-04/01.jpg'])
})

test('sweep with no anchors deletes nothing', () => {
  assert.deepEqual(staleHourKeys(['stations/001/2020-01-01/00.jpg'], {}), [])
})

test('sweep hour is the newest anchor hour, so the sweep runs once per hour', () => {
  assert.equal(sweepHour({
    '001': 'stations/001/2026-10-30/23.jpg',
    '002': 'stations/002/2026-10-31/00.jpg',
    '003': undefined,
  }), '2026-10-31/00')
  assert.equal(sweepHour({ '001': undefined }), null)
})

test('a sweep stays owed until one succeeds, even with no new frame filed', () => {
  const anchors = { '001': 'stations/001/2026-10-31/00.jpg', '002': 'stations/002/2026-10-30/23.jpg' }
  // A new hour was filed: a sweep is owed for it.
  assert.equal(sweepDue(anchors, '2026-10-30/23'), '2026-10-31/00')
  // That sweep failed, so the manifest kept the old sweptHour. The next sync
  // sees the same MOENV ZIP and files nothing, but the same anchors still owe it.
  assert.equal(sweepDue(anchors, '2026-10-30/23'), '2026-10-31/00')
  // First deploy: no sweep has run yet.
  assert.equal(sweepDue(anchors, undefined), '2026-10-31/00')
  // Once it succeeds, nothing more is owed until the next hour is filed.
  assert.equal(sweepDue(anchors, '2026-10-31/00'), null)
  assert.equal(sweepDue({ '001': undefined }, undefined), null)
})

test('only the first frame of an hour is filed', () => {
  const frames = ['202610302200', '202610302210', '202610302220', '202610302300', '202610302310']
  let last: string | undefined
  const written: string[] = []
  for (const stamp of frames) {
    const key = hourKey('001', stamp)
    if (shouldWriteHour(key, last)) {
      written.push(key)
      last = key
    }
  }
  assert.deepEqual(written, ['stations/001/2026-10-30/22.jpg', 'stations/001/2026-10-30/23.jpg'])
})

test('a 10-minute day files 24 hourly frames, not 144', () => {
  let last: string | undefined
  let written = 0
  for (let minute = 0; minute < 24 * 60; minute += 10) {
    const h = String(Math.floor(minute / 60)).padStart(2, '0')
    const m = String(minute % 60).padStart(2, '0')
    const key = hourKey('001', `20261030${h}${m}`)
    if (shouldWriteHour(key, last)) {
      written++
      last = key
    }
  }
  assert.equal(written, 24)
})

test('history route accepts only hourly keys', () => {
  assert.equal('/station-cams/stations/001/2026-10-30/22.jpg'.match(HISTORY_ROUTE)?.[1], 'stations/001/2026-10-30/22.jpg')
  assert.equal('/station-cams/stations/001.jpg'.match(HISTORY_ROUTE), null)
  assert.equal('/station-cams/stations/../manifest.json'.match(HISTORY_ROUTE), null)
})
