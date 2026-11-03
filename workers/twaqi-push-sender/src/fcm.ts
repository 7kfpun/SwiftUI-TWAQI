// Firebase Cloud Messaging HTTP v1. The OAuth access token comes from a
// service-account key: a JWT signed with RS256 via WebCrypto, exchanged at
// Google's token endpoint, and reused until five minutes before it expires.
// FCM hands the alert to APNs with the auth key uploaded in the Firebase
// console, so this Worker holds no Apple key.

export interface FcmConfig {
  /** The whole service-account JSON from Firebase → Project settings →
   * Service accounts → Generate new private key. */
  FCM_SERVICE_ACCOUNT: string
}

interface ServiceAccount {
  project_id: string
  client_email: string
  private_key: string
}

export interface FcmMessage {
  token: string
  title: string
  body: string
  /** Delivered to the app as userInfo; FCM wants string values only. */
  data?: Record<string, string>
  /** Same id replaces an earlier alert still on screen. */
  collapseId?: string
  /** Groups a station's alerts together in Notification Center. */
  threadId?: string
  /** Let APNs drop the alert if the phone stays offline this long. */
  expiresInSeconds?: number
}

export interface FcmResult {
  ok: boolean
  status: number
  /** `projects/…/messages/…` on success. */
  messageId?: string
  /** FcmError code, e.g. UNREGISTERED, or the HTTP status text. */
  errorCode?: string
  /** The token will never work again: archive the device. */
  deadToken: boolean
}

const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging'
const TOKEN_URL = 'https://oauth2.googleapis.com/token'
const REFRESH_MARGIN_MS = 5 * 60_000

let cached: { token: string; expiresAt: number; email: string } | null = null
/** The exchange in flight, shared by sends that start before it finishes, so
 * 25 parallel sends make one OAuth call, not 25. */
let pending: Promise<string> | null = null

export function isConfigured(config: Partial<FcmConfig>): boolean {
  try {
    parseServiceAccount(config.FCM_SERVICE_ACCOUNT)
    return true
  } catch {
    return false
  }
}

/** Never puts the key itself in an error message. */
export function parseServiceAccount(raw: string | undefined): ServiceAccount {
  if (!raw) throw new Error('FCM_SERVICE_ACCOUNT is not set')
  let parsed: Partial<ServiceAccount>
  try {
    parsed = JSON.parse(raw)
  } catch {
    throw new Error('FCM_SERVICE_ACCOUNT is not JSON')
  }
  for (const key of ['project_id', 'client_email', 'private_key'] as const) {
    if (typeof parsed[key] !== 'string' || !parsed[key]) throw new Error(`FCM_SERVICE_ACCOUNT has no ${key}`)
  }
  return parsed as ServiceAccount
}

/** The `message` object for `messages:send`. */
export function buildMessage(m: FcmMessage, now = Date.now()) {
  const headers: Record<string, string> = { 'apns-priority': '10' }
  if (m.collapseId) headers['apns-collapse-id'] = m.collapseId
  if (m.expiresInSeconds) headers['apns-expiration'] = String(Math.floor(now / 1000) + m.expiresInSeconds)
  const aps: Record<string, unknown> = { sound: 'default' }
  if (m.threadId) aps['thread-id'] = m.threadId
  return {
    token: m.token,
    notification: { title: m.title, body: m.body },
    ...(m.data && Object.keys(m.data).length ? { data: m.data } : {}),
    // No badge: the app clears the icon's number when it opens and sets none.
    apns: { headers, payload: { aps } },
  }
}

/** Reads an FCM error response. A token is dead when FCM says it is
 * unregistered, belongs to another sender, or isn't a registration token. */
export function classifyError(status: number, body: unknown): { errorCode: string; deadToken: boolean } {
  const error = (body as { error?: { status?: string; message?: string; details?: unknown[] } })?.error
  const fcmCode = error?.details
    ?.map((d) => d as { '@type'?: string; errorCode?: string })
    .find((d) => d['@type']?.endsWith('google.firebase.fcm.v1.FcmError') && d.errorCode)?.errorCode
  const errorCode = fcmCode ?? error?.status ?? `HTTP_${status}`
  const badToken = errorCode === 'INVALID_ARGUMENT' && /registration token/i.test(error?.message ?? '')
  const deadToken = errorCode === 'UNREGISTERED' || errorCode === 'SENDER_ID_MISMATCH' || badToken
  return { errorCode, deadToken }
}

/** Retried once, a moment later, on FCM 429/5xx: FCM answered and did not
 * take the message. Not on a network error, where FCM may already have
 * accepted it; the alert is then retried by the next run, never twice now. */
const RETRY_DELAY_MS = 500

export async function send(config: FcmConfig, m: FcmMessage): Promise<FcmResult> {
  const first = await sendOnce(config, m)
  if (first.ok || !(first.status === 429 || first.status >= 500)) return first
  await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS))
  return sendOnce(config, m)
}

async function sendOnce(config: FcmConfig, m: FcmMessage): Promise<FcmResult> {
  const account = parseServiceAccount(config.FCM_SERVICE_ACCOUNT)
  const accessToken = await getAccessToken(account)
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify({ message: buildMessage(m) }),
  })
  const text = await res.text()
  let body: unknown = null
  try {
    body = text ? JSON.parse(text) : null
  } catch {
    // Not JSON; classified by status alone.
  }
  if (res.ok) return { ok: true, status: res.status, messageId: (body as { name?: string })?.name, deadToken: false }
  // A rejected access token is ours, not the device's: fetch a fresh one next time.
  if (res.status === 401) cached = null
  return { ok: false, status: res.status, ...classifyError(res.status, body) }
}

async function getAccessToken(account: ServiceAccount): Promise<string> {
  if (cached && cached.email === account.client_email && Date.now() < cached.expiresAt - REFRESH_MARGIN_MS) {
    return cached.token
  }
  pending ??= exchange(account).finally(() => {
    pending = null
  })
  return pending
}

async function exchange(account: ServiceAccount): Promise<string> {
  const now = Date.now()

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(account.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const iat = Math.floor(now / 1000)
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const claims = base64url(JSON.stringify({ iss: account.client_email, scope: SCOPE, aud: TOKEN_URL, iat, exp: iat + 3600 }))
  const input = `${header}.${claims}`
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(input))
  const assertion = `${input}.${base64url(new Uint8Array(signature))}`

  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
  })
  const body = (await res.json().catch(() => ({}))) as { access_token?: string; expires_in?: number; error?: string }
  if (!res.ok || !body.access_token) throw new Error(`Google OAuth ${res.status}: ${body.error ?? 'no access_token'}`)

  cached = { token: body.access_token, expiresAt: now + (body.expires_in ?? 3600) * 1000, email: account.client_email }
  return cached.token
}

/** Accepts the key with real newlines, or with them escaped to "\n" by a secrets UI. */
function pemToDer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/\\n/g, '\n')
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '')
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0)).buffer
}

function base64url(data: string | Uint8Array): string {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : data
  let binary = ''
  for (const b of bytes) binary += String.fromCharCode(b)
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}
