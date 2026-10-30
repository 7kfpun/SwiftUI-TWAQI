// MOENV station webcam sync: aqx_p_01 zip -> R2 `stations/{siteId}.jpg` + `manifest.json`.
// Object keys use the MOENV site id from the JPEG filename (e.g. 001), not a TWAQI station id.
import { unzipSync } from 'fflate'

interface Env {
  CAMS: R2Bucket
  MOENV_API_KEY: string
  SYNC_TOKEN: string
}

interface Station {
  name: string | null
  lat: number | null
  lon: number | null
  time: string // ISO 8601, Asia/Taipei offset
  key: string
}

interface Manifest {
  updatedAt: string
  source: { filename: string; url: string; uploadDate: string } | null
  stations: Record<string, Station>
}

interface SyncResult {
  skipped: boolean
  source: string
  images: number
  uploaded: number
  unchanged: number
  stations: number
}

const MOENV_LIST = 'https://data.moenv.gov.tw/api/v2/aqx_p_01?format=JSON&limit=1&sort=ImportDate%20desc'
const MANIFEST_KEY = 'manifest.json'
const JPEG_NAME = /^(?:.*\/)?([0-9A-Za-z]+)-(\d{12})\.jpe?g$/i
const UPLOAD_BATCH = 8

export default {
  async scheduled(_controller, env, ctx) {
    ctx.waitUntil(
      sync(env).then(
        (r) => console.log('sync ok', JSON.stringify(r)),
        (e) => {
          console.error('sync failed', e)
          throw e
        },
      ),
    )
  },

  async fetch(request, env) {
    const url = new URL(request.url)
    const path = url.pathname

    // Each feature lives under its own prefix; this one is /station-cams.
    if (path === '/station-cams/sync') {
      if (request.method !== 'POST') return json({ error: 'method not allowed' }, 405, { Allow: 'POST' })
      if (!(await authorized(request, env))) return json({ error: 'unauthorized' }, 401)
      try {
        return json(await sync(env, url.searchParams.has('force')))
      } catch (e) {
        return json({ error: String(e) }, 502)
      }
    }

    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return json({ error: 'method not allowed' }, 405, { Allow: 'GET, HEAD' })
    }

    if (path === '/') {
      return json({ ok: true, service: 'twaqi-workers' }, 200, { 'Cache-Control': 'no-store' })
    }

    if (path === '/station-cams') {
      const m = await readManifest(env)
      return json({
        ok: true,
        service: 'station-cams',
        updatedAt: m?.updatedAt ?? null,
        source: m?.source?.filename ?? null,
        stations: m ? Object.keys(m.stations).length : 0,
      }, 200, { 'Cache-Control': 'no-store' })
    }

    if (path === '/station-cams/manifest.json') {
      return serveObject(request, env, MANIFEST_KEY, 'application/json; charset=utf-8', 'public, max-age=60')
    }

    const m = path.match(/^\/station-cams\/stations\/([0-9A-Za-z]+)\.jpg$/)
    if (m) return serveObject(request, env, `stations/${m[1]}.jpg`, 'image/jpeg', 'public, max-age=300')

    return json({ error: 'not found' }, 404)
  },
} satisfies ExportedHandler<Env>

async function sync(env: Env, force = false): Promise<SyncResult> {
  const listRes = await fetch(`${MOENV_LIST}&api_key=${encodeURIComponent(env.MOENV_API_KEY)}`)
  if (!listRes.ok) throw new Error(`MOENV list ${listRes.status}`)
  const rows = (await listRes.json()) as Array<{ filename?: string; url?: string; upload_date?: string }>
  const row = rows[0]
  if (!row?.url) throw new Error('MOENV list returned no zip url')

  const prev = await readManifest(env)
  if (!force && prev?.source?.url === row.url) {
    return { skipped: true, source: row.filename ?? row.url, images: 0, uploaded: 0, unchanged: 0, stations: Object.keys(prev.stations).length }
  }

  const zipRes = await fetch(row.url)
  if (!zipRes.ok) throw new Error(`MOENV zip ${zipRes.status}`)
  const files = unzipSync(new Uint8Array(await zipRes.arrayBuffer()), {
    filter: (f) => JPEG_NAME.test(f.name) || /(?:^|\/)(info\.xml|Data\.csv)$/i.test(f.name),
  })

  const meta = new Map<string, { name?: string; lat?: number; lon?: number; time?: string }>()
  const text = new TextDecoder()
  for (const [name, data] of Object.entries(files)) {
    if (/(?:^|\/)Data\.csv$/i.test(name)) parseDataCsv(text.decode(data), meta)
  }
  // info.xml carries site names; let it win over Data.csv.
  for (const [name, data] of Object.entries(files)) {
    if (/(?:^|\/)info\.xml$/i.test(name)) parseInfoXml(text.decode(data), meta)
  }

  // Latest JPEG per site id (a zip normally holds one each, but be safe).
  const latest = new Map<string, { file: string; stamp: string }>()
  for (const name of Object.keys(files)) {
    const m = name.match(JPEG_NAME)
    if (!m) continue
    const [, siteId, stamp] = m
    const cur = latest.get(siteId)
    if (!cur || stamp > cur.stamp) latest.set(siteId, { file: name, stamp })
  }

  const stations: Record<string, Station> = { ...(prev?.stations ?? {}) }
  const pending: Array<() => Promise<unknown>> = []
  let unchanged = 0
  for (const [siteId, { file, stamp }] of latest) {
    const base = file.split('/').pop()!
    const info = meta.get(base)
    const key = `stations/${siteId}.jpg`
    const time = stampToIso(stamp)
    const old = stations[siteId]
    stations[siteId] = {
      name: info?.name ?? old?.name ?? null,
      lat: info?.lat ?? old?.lat ?? null,
      lon: info?.lon ?? old?.lon ?? null,
      time,
      key,
    }
    if (!force && old?.time === time) {
      unchanged++
      continue
    }
    const body = files[file]
    pending.push(() =>
      env.CAMS.put(key, body, {
        httpMetadata: { contentType: 'image/jpeg', cacheControl: 'public, max-age=300' },
        customMetadata: { siteId, time, source: base },
      }),
    )
  }

  for (let i = 0; i < pending.length; i += UPLOAD_BATCH) {
    await Promise.all(pending.slice(i, i + UPLOAD_BATCH).map((run) => run()))
  }

  const manifest: Manifest = {
    updatedAt: new Date().toISOString(),
    source: { filename: row.filename ?? '', url: row.url, uploadDate: row.upload_date ?? '' },
    stations: Object.fromEntries(Object.entries(stations).sort(([a], [b]) => a.localeCompare(b))),
  }
  await env.CAMS.put(MANIFEST_KEY, JSON.stringify(manifest), {
    httpMetadata: { contentType: 'application/json; charset=utf-8', cacheControl: 'public, max-age=60' },
  })

  return {
    skipped: false,
    source: row.filename ?? row.url,
    images: latest.size,
    uploaded: pending.length,
    unchanged,
    stations: Object.keys(stations).length,
  }
}

// <image><site>基隆</site><file>001-202610302200.jpg</file><time>…</time><TWD97Lon>…</TWD97Lon><TWD97Lat>…</TWD97Lat>…</image>
function parseInfoXml(xml: string, meta: Map<string, { name?: string; lat?: number; lon?: number }>) {
  for (const [, block] of xml.matchAll(/<image>([\s\S]*?)<\/image>/g)) {
    const tag = (t: string) => block.match(new RegExp(`<${t}>([^<]*)</${t}>`))?.[1]?.trim()
    const file = tag('file')
    if (!file) continue
    const entry = meta.get(file) ?? {}
    const name = tag('site')
    const lat = num(tag('TWD97Lat'))
    const lon = num(tag('TWD97Lon'))
    if (name) entry.name = decodeXml(name)
    if (lat !== undefined) entry.lat = lat
    if (lon !== undefined) entry.lon = lon
    meta.set(file, entry)
  }
}

// 檔案名稱, 內容, TWD97Lon, TWD97Lat, TWD97TM2X, TWD97TM2Y
function parseDataCsv(csv: string, meta: Map<string, { name?: string; lat?: number; lon?: number }>) {
  const lines = csv.replace(/^﻿/, '').split(/\r?\n/).filter(Boolean)
  const header = lines.shift()?.split(',').map((h) => h.trim()) ?? []
  const iFile = header.indexOf('檔案名稱')
  const iLon = header.indexOf('TWD97Lon')
  const iLat = header.indexOf('TWD97Lat')
  if (iFile < 0) return
  for (const line of lines) {
    const cols = line.split(',').map((c) => c.trim())
    const file = cols[iFile]
    if (!file) continue
    const entry = meta.get(file) ?? {}
    const lat = num(cols[iLat])
    const lon = num(cols[iLon])
    if (lat !== undefined) entry.lat = lat
    if (lon !== undefined) entry.lon = lon
    meta.set(file, entry)
  }
}

function num(s: string | undefined): number | undefined {
  if (!s) return undefined
  const n = Number(s)
  return Number.isFinite(n) ? n : undefined
}

function decodeXml(s: string): string {
  return s
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&')
}

// 202610302200 -> 2026-10-30T22:00:00+08:00 (MOENV stamps are Taiwan local time)
function stampToIso(s: string): string {
  return `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}T${s.slice(8, 10)}:${s.slice(10, 12)}:00+08:00`
}

async function readManifest(env: Env): Promise<Manifest | null> {
  const obj = await env.CAMS.get(MANIFEST_KEY)
  return obj ? ((await obj.json()) as Manifest) : null
}

async function serveObject(request: Request, env: Env, key: string, contentType: string, cacheControl: string) {
  const obj = await env.CAMS.get(key, { onlyIf: request.headers })
  if (!obj) return json({ error: 'not found' }, 404, { 'Cache-Control': 'public, max-age=60' })

  const headers = new Headers()
  obj.writeHttpMetadata(headers)
  headers.set('Content-Type', contentType)
  headers.set('Cache-Control', cacheControl)
  headers.set('ETag', obj.httpEtag)
  headers.set('Last-Modified', obj.uploaded.toUTCString())
  headers.set('Access-Control-Allow-Origin', '*')

  // onlyIf precondition failed -> R2Object without a body.
  if (!('body' in obj)) return new Response(null, { status: 304, headers })
  return new Response(request.method === 'HEAD' ? null : obj.body, { headers })
}

async function authorized(request: Request, env: Env): Promise<boolean> {
  if (!env.SYNC_TOKEN) return false
  const got = request.headers.get('Authorization') ?? ''
  const enc = new TextEncoder()
  const a = enc.encode(got)
  const b = enc.encode(`Bearer ${env.SYNC_TOKEN}`)
  return a.byteLength === b.byteLength && crypto.subtle.timingSafeEqual(a, b)
}

function json(data: unknown, status = 200, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Access-Control-Allow-Origin': '*', ...extra },
  })
}
