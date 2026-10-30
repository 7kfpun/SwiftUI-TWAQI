// APNs over HTTP/2 with a token (.p8) key. The provider JWT is signed with
// ES256 via WebCrypto and reused for 50 minutes: Apple rejects tokens older
// than an hour and throttles ones refreshed more often than every 20 minutes.

export interface ApnsConfig {
  APNS_KEY_ID: string
  APNS_TEAM_ID: string
  /** Contents of AuthKey_XXXXXXXXXX.p8 (PEM, PKCS#8). */
  APNS_KEY_P8: string
  APNS_BUNDLE_ID: string
}

export type ApnsEnvironment = 'sandbox' | 'production'

export interface ApnsResult {
  ok: boolean
  status: number
  reason?: string
  /** The token will never work again: archive the device. */
  deadToken: boolean
}

const HOSTS: Record<ApnsEnvironment, string> = {
  sandbox: 'https://api.sandbox.push.apple.com',
  production: 'https://api.push.apple.com',
}

const TOKEN_TTL_MS = 50 * 60_000

let cached: { jwt: string; issuedAt: number; keyId: string } | null = null

export async function sendAlert(
  config: ApnsConfig,
  environment: ApnsEnvironment,
  deviceToken: string,
  payload: unknown,
  options: { collapseId?: string; expiresInSeconds?: number } = {},
): Promise<ApnsResult> {
  const jwt = await providerToken(config)
  const headers: Record<string, string> = {
    authorization: `bearer ${jwt}`,
    'apns-topic': config.APNS_BUNDLE_ID,
    'apns-push-type': 'alert',
    'apns-priority': '10',
    'content-type': 'application/json',
  }
  if (options.collapseId) headers['apns-collapse-id'] = options.collapseId
  if (options.expiresInSeconds) {
    headers['apns-expiration'] = String(Math.floor(Date.now() / 1000) + options.expiresInSeconds)
  }

  const res = await fetch(`${HOSTS[environment]}/3/device/${encodeURIComponent(deviceToken)}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(payload),
  })
  if (res.ok) return { ok: true, status: res.status, deadToken: false }

  let reason: string | undefined
  try {
    reason = ((await res.json()) as { reason?: string }).reason
  } catch {
    // Empty or non-JSON body.
  }
  // A rejected provider token is ours, not the device's: sign a fresh one next time.
  if (res.status === 403) cached = null

  // 410 is Unregistered (app removed). BadDeviceToken also covers a sandbox
  // token sent to production or the reverse, which the stored environment
  // should rule out. DeviceTokenNotForTopic is a bundle id mistake on our
  // side, so the device is left alone.
  const deadToken = res.status === 410 || reason === 'BadDeviceToken' || reason === 'Unregistered'
  return { ok: false, status: res.status, reason, deadToken }
}

async function providerToken(config: ApnsConfig): Promise<string> {
  const now = Date.now()
  if (cached && cached.keyId === config.APNS_KEY_ID && now - cached.issuedAt < TOKEN_TTL_MS) {
    return cached.jwt
  }

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(config.APNS_KEY_P8),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  )
  const header = base64url(JSON.stringify({ alg: 'ES256', kid: config.APNS_KEY_ID }))
  const claims = base64url(JSON.stringify({ iss: config.APNS_TEAM_ID, iat: Math.floor(now / 1000) }))
  const input = `${header}.${claims}`
  // WebCrypto returns the raw r||s signature, which is what JWS ES256 wants.
  const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(input))
  const jwt = `${input}.${base64url(new Uint8Array(signature))}`

  cached = { jwt, issuedAt: now, keyId: config.APNS_KEY_ID }
  return jwt
}

/** Accepts the .p8 file as is, or with its newlines flattened to spaces or
 * literal "\n" by a secrets UI. */
function pemToDer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/\\n/g, '\n')
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '')
  const bytes = Uint8Array.from(atob(body), (c) => c.charCodeAt(0))
  return bytes.buffer
}

function base64url(data: string | Uint8Array): string {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : data
  let binary = ''
  for (const b of bytes) binary += String.fromCharCode(b)
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}
