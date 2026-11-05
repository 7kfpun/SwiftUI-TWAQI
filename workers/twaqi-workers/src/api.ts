// TWAQI read API (FOX-82): GET /v1/{countries,stations,current-pollutants,historical-pollutants}
// as a Worker route on the R2 webcam host (`routes` in wrangler.jsonc; every other path
// there stays R2). Forwards to the Cloud Run service `twaqi-api`
// (services/twaqi-api, kf-personal-tools, asia-east1), which reads the Lambda's MySQL
// and answers with the Lambda's exact bytes. Successful answers are cached at the edge
// for TWAQI_API_CACHE_SECONDS (600): the data changes every 20 minutes, and the cache keeps
// Cloud Run and the db-f1-micro MySQL mostly idle.

export interface ApiEnv {
  TWAQI_API_ORIGIN_URL: string
  TWAQI_API_CACHE_SECONDS: string
  /** Same value as Secret Manager `twaqi-api-origin-token`. */
  TWAQI_API_ORIGIN_TOKEN: string
}

/** Must match ORIGIN_TOKEN_HEADER in services/twaqi-api/src/server.rs. */
export const ORIGIN_TOKEN_HEADER = 'x-twaqi-origin-token'
/** The params each route reads (services/twaqi-api/src/api.rs); the Worker drops every other one. */
const ROUTE_PARAMS: Record<string, readonly string[]> = {
  '/v1/countries': [],
  '/v1/stations': ['country', 'country_id'],
  '/v1/current-pollutants': ['country', 'country_id', 'station_id'],
  '/v1/historical-pollutants': ['limit', 'station', 'station_id'],
}
export const API_ROUTES = new Set(Object.keys(ROUTE_PARAMS))
const ORIGIN_TIMEOUT_MS = 15_000

export const isApiPath = (pathname: string): boolean => pathname.startsWith('/v1/')

/**
 * The query the origin and the cache key both use: only the route's own params, the first
 * value of each (the service reads the first too), in a fixed order. So `?_=1`, `?_=2`, …
 * or reordered params hit the same cache entry instead of each reaching Cloud Run.
 */
export function canonicalQuery(pathname: string, search: URLSearchParams): string {
  const query = new URLSearchParams()
  for (const name of ROUTE_PARAMS[pathname] ?? []) {
    const value = search.get(name)
    if (value !== null) query.set(name, value)
  }
  const text = query.toString()
  return text ? `?${text}` : ''
}

const json = (status: number, body: string, headers: Record<string, string> = {}) =>
  new Response(body, { status, headers: { 'content-type': 'application/json', ...headers } })

export interface ApiDeps {
  cache: Pick<Cache, 'match' | 'put'>
  fetch: typeof fetch
}

/** Handles any /v1/ path: the four reads, else 404; writes are 405. */
export async function handleApi(
  request: Request,
  env: ApiEnv,
  ctx: Pick<ExecutionContext, 'waitUntil'>,
  deps: ApiDeps,
): Promise<Response> {
  const url = new URL(request.url)
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return json(405, '{"message":"Method Not Allowed"}', { allow: 'GET, HEAD' })
  }
  if (!API_ROUTES.has(url.pathname)) return json(404, '{"message":"Not Found"}')

  const query = canonicalQuery(url.pathname, url.searchParams)
  const cacheKey = new Request(`${url.origin}${url.pathname}${query}`, { method: 'GET' })
  const seconds = Number(env.TWAQI_API_CACHE_SECONDS) || 600
  const cached = await deps.cache.match(cacheKey)
  if (cached) {
    // What the cache hands back carries the zone's Browser Cache TTL (4 h), not ours.
    // Give the apps only what is left of the edge's time, so a reading is at most
    // `seconds` old in total, edge and app together.
    const age = Number(cached.headers.get('age'))
    const left = Math.max(0, seconds - (Number.isFinite(age) && age > 0 ? Math.floor(age) : 0))
    return withCacheHeaders(request, cached, 'HIT', left)
  }

  let origin: Response
  let body: string
  try {
    origin = await deps.fetch(`${env.TWAQI_API_ORIGIN_URL.replace(/\/+$/, '')}${url.pathname}${query}`, {
      headers: { [ORIGIN_TOKEN_HEADER]: env.TWAQI_API_ORIGIN_TOKEN, accept: 'application/json' },
      signal: AbortSignal.timeout(ORIGIN_TIMEOUT_MS),
    })
    // Inside the try: the timeout also covers the body, and a stalled or reset body
    // must still answer the JSON 502, not Cloudflare's HTML 500.
    body = await origin.text()
  } catch (error) {
    console.error('api origin unreachable', url.pathname, error instanceof Error ? error.message : String(error))
    return json(502, '{"success":false,"error":"Upstream unavailable"}')
  }

  if (origin.status !== 200) {
    console.error('api origin error', url.pathname, origin.status, body.slice(0, 200))
    // Never pass Cloud Run's own error pages (or a 403 about the token) to the apps.
    const status = origin.status >= 500 ? origin.status : 502
    return json(status, '{"success":false,"error":"Upstream error"}')
  }

  // Also what goes into the cache, so the edge keeps it `seconds`.
  const response = json(200, body, { 'cache-control': `public, max-age=${seconds}` })
  ctx.waitUntil(deps.cache.put(cacheKey, response.clone()))
  return withCacheHeaders(request, response, 'MISS', seconds)
}

/** Every 200 gets our own cache-control, never the one the cache gives back. */
function withCacheHeaders(request: Request, response: Response, cache: 'HIT' | 'MISS', maxAge: number): Response {
  const headers = new Headers(response.headers)
  headers.set('cache-control', `public, max-age=${maxAge}`)
  headers.set('x-twaqi-cache', cache)
  return new Response(request.method === 'HEAD' ? null : response.body, { status: response.status, headers })
}
