// Pre-translates the MOENV forecast text (`content`, Traditional Chinese) into
// English with an LLM on OpenRouter, for `twaqi_aqi_forecast.content_i18n`.
//
// `content_i18n` is a JSON map of locale -> text. It always carries the source
// it was translated from under `zh-Hant`, so a translation is current exactly
// when `content_i18n["zh-Hant"] === content`; anything else (no map, a map for
// older text) is translated again. `content` itself stays the source of truth.
//
// The pure parts (decision, prompt, parsing) are exported for `node --test`.

/** Pinned model; changing it is a code change, so a provider-side alias can't swap it silently. */
export const TRANSLATION_MODEL = 'deepseek/deepseek-v4.1-flash'
export const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions'
export const SOURCE_LOCALE = 'zh-Hant'
export const TARGET_LOCALES = ['en'] as const
export type TargetLocale = (typeof TARGET_LOCALES)[number]

/** At most this many model calls per sync; the next hourly run picks up the rest. */
export const MAX_TRANSLATIONS_PER_RUN = 40
/** Per call. A slow provider costs one row's translation, not the sync. */
export const TRANSLATION_TIMEOUT_MS = 30_000
/** Total time a sync spends translating before leaving the rest for the next run. */
export const TRANSLATION_BUDGET_MS = 120_000

export type ContentI18n = Partial<Record<string, string>>

/** MOENV's text has Han characters; a test row in English never needs a model. */
export function hasHan(text: string): boolean {
  return /\p{Script=Han}/u.test(text)
}

/** Whether a row's `content` needs (re)translating into `locale`. */
export function needsTranslation(content: string | null | undefined, i18n: unknown, locale: TargetLocale = 'en'): boolean {
  const source = content?.trim()
  if (!source || !hasHan(source)) return false
  const map = asI18n(i18n)
  return !(map && map[SOURCE_LOCALE] === source && typeof map[locale] === 'string' && map[locale]!.trim() !== '')
}

/** Directus returns JSON fields parsed, but tolerate a JSON string or junk. */
export function asI18n(value: unknown): ContentI18n | null {
  let v = value
  if (typeof v === 'string') {
    try {
      v = JSON.parse(v)
    } catch {
      return null
    }
  }
  if (!v || typeof v !== 'object' || Array.isArray(v)) return null
  const out: ContentI18n = {}
  for (const [k, s] of Object.entries(v as Record<string, unknown>)) if (typeof s === 'string') out[k] = s
  return out
}

/** The value to store: the source it came from plus the translations. */
export function buildI18n(source: string, translations: Partial<Record<TargetLocale, string>>): ContentI18n {
  return { [SOURCE_LOCALE]: source.trim(), ...translations }
}

/** Fixed renderings so area names, pollutants and MOENV terms read the same every day. */
export const GLOSSARY: ReadonlyArray<readonly [string, string]> = [
  // 空品區 (air quality regions)
  ['北部空品區', 'Northern air quality region'],
  ['竹苗空品區', 'Chu-Miao air quality region'],
  ['中部空品區', 'Central air quality region'],
  ['雲嘉南空品區', 'Yun-Chia-Nan air quality region'],
  ['高屏空品區', 'Kao-Ping air quality region'],
  ['宜蘭空品區', 'Yilan air quality region'],
  ['花東空品區', 'Hua-Tung air quality region'],
  ['北部', 'Northern'],
  ['竹苗', 'Chu-Miao'],
  ['中部', 'Central'],
  ['雲嘉南', 'Yun-Chia-Nan'],
  ['高屏', 'Kao-Ping'],
  ['宜蘭', 'Yilan'],
  ['花東', 'Hua-Tung'],
  ['馬祖', 'Matsu'],
  ['金門', 'Kinmen'],
  ['澎湖', 'Penghu'],
  ['空品區', 'air quality region'],
  // Pollutants
  ['細懸浮微粒', 'PM2.5'],
  ['懸浮微粒', 'PM10'],
  ['臭氧', 'ozone'],
  ['二氧化氮', 'NO2'],
  ['二氧化硫', 'SO2'],
  ['一氧化碳', 'CO'],
  // AQI levels and MOENV alerts
  ['良好', 'Good'],
  ['普通', 'Moderate'],
  ['對敏感族群不健康', 'Unhealthy for Sensitive Groups'],
  ['對所有族群不健康', 'Unhealthy'],
  ['非常不健康', 'Very Unhealthy'],
  ['危害', 'Hazardous'],
  ['橘色提醒', 'Orange Alert'],
  ['紅色警示', 'Red Alert'],
  ['紫色警示', 'Purple Alert'],
  // Agencies and weather terms
  ['環境部', 'Ministry of Environment'],
  ['氣象署', 'Central Weather Administration'],
  ['境外污染物', 'transboundary pollutants'],
  ['東北季風', 'northeast monsoon'],
  ['擴散條件', 'dispersion conditions'],
  ['光化作用', 'photochemical reactions'],
  ['背風側', 'leeward side'],
  ['下風處', 'downwind'],
  ['沙塵', 'dust'],
]

/** Only the glossary entries that occur in this text, so the prompt stays short. */
export function glossaryFor(text: string): Array<readonly [string, string]> {
  return GLOSSARY.filter(([zh]) => text.includes(zh))
}

export function buildMessages(text: string): Array<{ role: 'system' | 'user'; content: string }> {
  const terms = glossaryFor(text)
  const system = [
    "Translate Taiwan's Ministry of Environment air quality forecast from Traditional Chinese into English for a mobile app.",
    'Output only the English translation as plain text: no preamble, notes, quotes, Markdown or Chinese characters.',
    'Keep the meaning, numbers, dates, times and line breaks. Render dates like 今（3）日 as "Today (the 3rd)".',
    terms.length ? `Use these renderings:\n${terms.map(([zh, en]) => `${zh} = ${en}`).join('\n')}` : '',
  ]
    .filter(Boolean)
    .join('\n')
  return [
    { role: 'system', content: system },
    { role: 'user', content: text },
  ]
}

export function buildRequestBody(text: string, model = TRANSLATION_MODEL) {
  return {
    model,
    messages: buildMessages(text),
    temperature: 0,
    max_tokens: 2000,
    // A translation needs no thinking tokens; they only add cost and latency.
    reasoning: { enabled: false },
  }
}

/**
 * The English text from an OpenAI-compatible chat completion, or an error
 * message. Rejects truncated output and anything still holding Chinese.
 */
export function parseCompletion(body: unknown): { text: string } | { error: string } {
  const b = body as {
    error?: { message?: string }
    choices?: Array<{ finish_reason?: string | null; message?: { content?: unknown } }>
  }
  if (b?.error) return { error: `OpenRouter error: ${String(b.error.message ?? 'unknown').slice(0, 160)}` }
  const choice = b?.choices?.[0]
  if (!choice) return { error: 'no choices' }
  if (choice.finish_reason === 'length') return { error: 'output truncated' }
  const raw = choice.message?.content
  if (typeof raw !== 'string') return { error: 'no text content' }
  const text = cleanOutput(raw)
  if (!text) return { error: 'empty translation' }
  if (hasHan(text)) return { error: 'translation still contains Chinese' }
  return { text }
}

/** Strips wrappers models add despite the prompt: code fences, a "Translation:" label, surrounding quotes. */
export function cleanOutput(raw: string): string {
  let s = raw.replace(/<think>[\s\S]*?<\/think>/gi, '').trim()
  s = s.replace(/^```[a-z]*\s*\n?/i, '').replace(/\n?```$/, '').trim()
  s = s.replace(/^(?:english\s+)?translation\s*:\s*/i, '').trim()
  if (/^["“].*["”]$/s.test(s)) s = s.slice(1, -1).trim()
  return s.replace(/[ \t]+\n/g, '\n')
}

export interface TranslateOptions {
  apiKey: string
  model?: string
  timeoutMs?: number
  fetchImpl?: typeof fetch
}

export interface TranslateCall {
  text: string
  /** USD, as OpenRouter reports it (`usage.cost`), when present. */
  cost?: number
  model?: string
}

/** One model call. Throws on HTTP, timeout or unusable output. */
export async function translateText(text: string, opts: TranslateOptions): Promise<TranslateCall> {
  const res = await (opts.fetchImpl ?? fetch)(OPENROUTER_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${opts.apiKey}`,
      'Content-Type': 'application/json',
      'X-Title': 'TWAQI forecast sync',
    },
    body: JSON.stringify(buildRequestBody(text, opts.model)),
    signal: AbortSignal.timeout(opts.timeoutMs ?? TRANSLATION_TIMEOUT_MS),
  })
  const raw = await res.text()
  // Never echo request headers; the body of an error response carries no key.
  if (!res.ok) throw new Error(`OpenRouter ${res.status}: ${raw.slice(0, 160)}`)
  let body: unknown
  try {
    body = JSON.parse(raw)
  } catch {
    throw new Error(`OpenRouter not JSON: ${raw.slice(0, 120)}`)
  }
  const parsed = parseCompletion(body)
  if ('error' in parsed) throw new Error(parsed.error)
  const usage = (body as { usage?: { cost?: unknown }; model?: unknown })
  return {
    text: parsed.text,
    cost: typeof usage.usage?.cost === 'number' ? usage.usage.cost : undefined,
    model: typeof usage.model === 'string' ? usage.model : undefined,
  }
}

export interface TranslatableRow {
  id: number
  content: string | null
  content_i18n?: unknown
}

export interface TranslationPlan {
  /** Rows whose text another row already has a current translation for: no model call. */
  reuse: Array<{ id: number; i18n: ContentI18n }>
  /** Distinct source texts to send, at most `cap`, oldest-first order kept. */
  texts: string[]
  /** Rows waiting on each text in `texts`. */
  rowsByText: Map<string, number[]>
  /** Distinct texts left for a later run because of the cap. */
  deferred: number
}

/**
 * Which rows to translate this run. MOENV repeats one text on every row of a
 * publish, so each distinct text is sent once and shared; a text that some row
 * already has a current translation for is copied rather than sent again.
 */
export function planTranslations(rows: TranslatableRow[], cap = MAX_TRANSLATIONS_PER_RUN, locale: TargetLocale = 'en'): TranslationPlan {
  const known = new Map<string, ContentI18n>()
  for (const row of rows) {
    const source = row.content?.trim()
    if (source && !needsTranslation(source, row.content_i18n, locale)) known.set(source, asI18n(row.content_i18n)!)
  }
  const reuse: TranslationPlan['reuse'] = []
  const rowsByText = new Map<string, number[]>()
  for (const row of rows) {
    if (!needsTranslation(row.content, row.content_i18n, locale)) continue
    const source = row.content!.trim()
    const have = known.get(source)
    if (have) reuse.push({ id: row.id, i18n: have })
    else rowsByText.set(source, [...(rowsByText.get(source) ?? []), row.id])
  }
  const all = [...rowsByText.keys()]
  const texts = all.slice(0, Math.max(0, cap))
  return { reuse, texts, rowsByText, deferred: all.length - texts.length }
}

/** Directus answers a field it lacks, or one the role can't read, with a 403 naming it. */
export function isMissingFieldError(error: unknown, field = 'content_i18n'): boolean {
  const s = String(error)
  return /\b403\b/.test(s) && s.includes(field)
}

export interface TranslationResult {
  translated: number
  translatedRows: number
  translationFailed: number
  translationDeferred: number
  translationSkipped?: string
}

/** The two Directus calls translation needs, on `twaqi_aqi_forecast`. */
export interface TranslationStore {
  list<T>(params: Record<string, string>): Promise<T[]>
  updateBatch(items: Array<{ id: number }>): Promise<unknown>
}

/**
 * Fills `content_i18n` for the feed's rows whose translation is missing or was
 * made from older text: new rows, rows whose publish changed the text, and
 * rows a previous run failed on. Rows already current are left alone, so a
 * run with nothing new makes no model calls. Runs after the upsert and never
 * throws; anything not done here is retried next hour.
 */
export async function translateForecast(
  apiKey: string | undefined,
  directus: TranslationStore,
  dates: string[],
  options: { cap?: number; budgetMs?: number; translate?: typeof translateText; now?: () => number } = {},
): Promise<TranslationResult> {
  const result: TranslationResult = { translated: 0, translatedRows: 0, translationFailed: 0, translationDeferred: 0 }
  if (!apiKey) return { ...result, translationSkipped: 'OPENROUTER_FORECAST_API_KEY not set' }

  let rows: TranslatableRow[]
  try {
    rows = await directus.list<TranslatableRow>({
      'filter[forecast_date][_in]': dates.join(','),
      'filter[archived][_neq]': 'true',
      fields: 'id,content,content_i18n',
      limit: '-1',
    })
  } catch (e) {
    // Until the field exists (and the Worker role may read it) the sync just
    // carries on without translations.
    const reason = isMissingFieldError(e) ? 'content_i18n field missing or not readable' : `could not read rows: ${String(e).slice(0, 200)}`
    console.warn('forecast translation skipped', reason)
    return { ...result, translationSkipped: reason }
  }

  const plan = planTranslations(rows, options.cap ?? MAX_TRANSLATIONS_PER_RUN)
  result.translationDeferred = plan.deferred
  const writes: Array<{ id: number; content_i18n: ContentI18n }> = plan.reuse.map((r) => ({ id: r.id, content_i18n: r.i18n }))

  const now = options.now ?? Date.now
  const deadline = now() + (options.budgetMs ?? TRANSLATION_BUDGET_MS)
  const translate = options.translate ?? translateText
  for (const [i, text] of plan.texts.entries()) {
    if (now() > deadline) {
      result.translationDeferred += plan.texts.length - i
      break
    }
    try {
      const { text: en } = await translate(text, { apiKey })
      result.translated++
      const i18n = buildI18n(text, { en })
      for (const id of plan.rowsByText.get(text) ?? []) writes.push({ id, content_i18n: i18n })
    } catch (e) {
      result.translationFailed++
      console.error('forecast translation failed', String(e).slice(0, 300))
    }
  }

  if (writes.length === 0) return result
  try {
    await directus.updateBatch(writes)
    result.translatedRows = writes.length
  } catch (e) {
    // e.g. the Worker role lacks update on content_i18n. The rows are stored;
    // count these texts as failed so the status shows it, and retry next run.
    result.translationFailed += result.translated
    result.translated = 0
    result.translationSkipped = `could not save translations: ${String(e).slice(0, 200)}`
    console.error('forecast translation save failed', e)
  }
  return result
}
