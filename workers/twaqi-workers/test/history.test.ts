// Run with `npm test` (Node 23.6+ strips the types; no extra dependencies).
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { HISTORY_ROUTE, expiredHourKey, hourKey, shouldWriteHour } from '../src/history.ts'

test('hour key comes straight off the Taiwan-local MOENV stamp', () => {
  assert.equal(hourKey('001', '202610302200'), 'stations/001/2026-10-30/22.jpg')
  assert.equal(hourKey('001', '202610302250'), 'stations/001/2026-10-30/22.jpg')
  // Midnight in Taiwan is still the same calendar day there, not UTC's previous one.
  assert.equal(hourKey('204', '202611010005'), 'stations/204/2026-11-01/00.jpg')
  assert.equal(hourKey('001', 'nope'), null)
})

test('expired key is the same hour HISTORY_DAYS earlier, across month ends', () => {
  assert.equal(expiredHourKey('001', '202610302210'), 'stations/001/2026-10-23/22.jpg')
  assert.equal(expiredHourKey('001', '202611030010'), 'stations/001/2026-10-27/00.jpg')
  assert.equal(expiredHourKey('001', '202701020300', 7), 'stations/001/2026-12-26/03.jpg')
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
