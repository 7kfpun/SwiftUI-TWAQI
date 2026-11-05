// Run with `npm test` (Node 23.6+ strips the types; no extra dependencies).
import assert from 'node:assert/strict'
import { test } from 'node:test'
import {
  GLOSSARY,
  TRANSLATION_MODEL,
  TRANSLATION_SAVE_BATCH,
  buildI18n,
  buildMessages,
  buildRequestBody,
  cleanOutput,
  glossaryFor,
  isMissingFieldError,
  needsTranslation,
  parseCompletion,
  planTranslations,
  translateForecast,
  translateText,
} from '../src/translate.ts'


const ZH = '今（3）日環境風場為東北風，北部、竹苗空品區為「普通」等級；細懸浮微粒濃度稍高。'
const EN = 'Today (the 3rd), the wind is from the northeast; the Northern and Chu-Miao air quality regions are Moderate.'

test('needs translation: Chinese text without a current English translation', () => {
  assert.equal(needsTranslation(ZH, null), true)
  assert.equal(needsTranslation(ZH, {}), true)
  // Translated from this exact text: current.
  assert.equal(needsTranslation(ZH, buildI18n(ZH, { en: EN })), false)
  // Whitespace around the source doesn't count as a change.
  assert.equal(needsTranslation(`  ${ZH}\n`, buildI18n(ZH, { en: EN })), false)
  // A new publish changed the text: the stored English is stale.
  assert.equal(needsTranslation(`${ZH}明日轉佳。`, buildI18n(ZH, { en: EN })), true)
  // English present but no record of its source, or empty English.
  assert.equal(needsTranslation(ZH, { en: EN }), true)
  assert.equal(needsTranslation(ZH, buildI18n(ZH, { en: ' ' })), true)
  // A JSON string from Directus is read like an object; junk is "no translation".
  assert.equal(needsTranslation(ZH, JSON.stringify(buildI18n(ZH, { en: EN }))), false)
  assert.equal(needsTranslation(ZH, 'not json'), true)
  assert.equal(needsTranslation(ZH, ['en']), true)
})

test('nothing to translate: empty or non-Chinese content', () => {
  assert.equal(needsTranslation(null, null), false)
  assert.equal(needsTranslation('   ', null), false)
  assert.equal(needsTranslation('smoke test FOX-8', null), false)
})

test('content_i18n keeps the source it was translated from', () => {
  assert.deepEqual(buildI18n(` ${ZH} `, { en: EN }), { 'zh-Hant': ZH, en: EN })
})

test('glossary: only the terms in the text, longest area names kept', () => {
  const terms = new Map(glossaryFor(ZH))
  assert.equal(terms.get('竹苗空品區'), 'Chu-Miao air quality region')
  assert.equal(terms.get('北部'), 'Northern')
  assert.equal(terms.get('普通'), 'Moderate')
  assert.equal(terms.get('細懸浮微粒'), 'PM2.5')
  assert.equal(terms.has('澎湖'), false)
  assert.equal(terms.has('臭氧'), false)
  // All ten 空品區 / island forecast areas have a fixed name.
  const all = new Map(GLOSSARY)
  for (const area of ['北部', '竹苗', '中部', '雲嘉南', '高屏', '宜蘭', '花東', '馬祖', '金門', '澎湖']) assert.ok(all.get(area), area)
})

test('prompt: short system prompt with the glossary, the text as the user turn', () => {
  const [system, user] = buildMessages(ZH)
  assert.equal(system.role, 'system')
  assert.match(system.content, /plain text/)
  assert.match(system.content, /雲嘉南|北部 = Northern/)
  assert.ok(!system.content.includes('澎湖'))
  assert.deepEqual(user, { role: 'user', content: ZH })
  assert.ok(system.content.length < 1500)

  const body = buildRequestBody(ZH)
  assert.equal(body.model, TRANSLATION_MODEL)
  assert.equal(body.temperature, 0)
  assert.deepEqual(body.reasoning, { enabled: false })
  // Pinned to an exact id, not an OpenRouter "~…-latest" alias.
  assert.ok(!TRANSLATION_MODEL.startsWith('~') && !TRANSLATION_MODEL.includes('latest'))
})

test('response parsing: plain English only', () => {
  const ok = (content: unknown, finish_reason = 'stop') => ({ choices: [{ finish_reason, message: { content } }] })
  assert.deepEqual(parseCompletion(ok(`  ${EN}  `)), { text: EN })
  assert.deepEqual(parseCompletion(ok(`Translation: ${EN}`)), { text: EN })
  assert.deepEqual(parseCompletion(ok('```\n' + EN + '\n```')), { text: EN })
  assert.deepEqual(parseCompletion(ok(`"${EN}"`)), { text: EN })
  assert.deepEqual(parseCompletion(ok(`<think>hmm</think>\n${EN}`)), { text: EN })
  // Line breaks between numbered days survive.
  assert.deepEqual(parseCompletion(ok('1. Today.\n2. Tomorrow.')), { text: '1. Today.\n2. Tomorrow.' })

  assert.ok('error' in parseCompletion(ok(EN, 'length')))
  assert.ok('error' in parseCompletion(ok(`${EN} 北部`)))
  assert.ok('error' in parseCompletion(ok('  ')))
  assert.ok('error' in parseCompletion(ok(null)))
  assert.ok('error' in parseCompletion({ choices: [] }))
  assert.ok('error' in parseCompletion({ error: { message: 'rate limited' } }))
  assert.equal(cleanOutput('English translation:\nHello'), 'Hello')
})

test('translateText: sends the key, parses the reply, throws on HTTP errors', async () => {
  let seen: { url: string; init: RequestInit } | undefined
  const fetchOk = (async (url: string, init: RequestInit) => {
    seen = { url, init }
    return new Response(JSON.stringify({ model: TRANSLATION_MODEL, usage: { cost: 0.0004 }, choices: [{ finish_reason: 'stop', message: { content: EN } }] }))
  }) as unknown as typeof fetch
  const r = await translateText(ZH, { apiKey: 'k', fetchImpl: fetchOk })
  assert.deepEqual(r, { text: EN, cost: 0.0004, model: TRANSLATION_MODEL })
  assert.equal(seen!.url, 'https://openrouter.ai/api/v1/chat/completions')
  assert.equal((seen!.init.headers as Record<string, string>).Authorization, 'Bearer k')
  assert.ok(seen!.init.signal, 'has a timeout')

  const fetch429 = (async () => new Response('{"error":{"message":"rate limited"}}', { status: 429 })) as unknown as typeof fetch
  await assert.rejects(translateText(ZH, { apiKey: 'k', fetchImpl: fetch429 }), /OpenRouter 429/)
})

test('plan: one call per distinct text, shared by every row of a publish, capped', () => {
  const OTHER = '明日北部普通。'
  const rows = [
    { id: 1, content: ZH, content_i18n: null },
    { id: 2, content: ZH, content_i18n: null },
    { id: 3, content: OTHER, content_i18n: buildI18n(OTHER, { en: 'Tomorrow north moderate.' }) },
    { id: 4, content: OTHER, content_i18n: null },
    { id: 5, content: '第三段。', content_i18n: null },
    { id: 6, content: null, content_i18n: null },
  ]
  const plan = planTranslations(rows)
  assert.deepEqual(plan.texts, [ZH, '第三段。'])
  assert.deepEqual(plan.rowsByText.get(ZH), [1, 2])
  // Row 4 copies row 3's current translation, no call.
  assert.deepEqual(plan.reuse, [{ id: 4, i18n: buildI18n(OTHER, { en: 'Tomorrow north moderate.' }) }])
  assert.equal(plan.deferred, 0)

  const capped = planTranslations(rows, 1)
  assert.deepEqual(capped.texts, [ZH])
  assert.equal(capped.deferred, 1)

  // Everything current: no calls at all (idempotent).
  const done = planTranslations([{ id: 1, content: ZH, content_i18n: buildI18n(ZH, { en: EN }) }])
  assert.deepEqual([done.texts, done.reuse, done.deferred], [[], [], 0])
})

test('missing field: Directus 403 naming content_i18n', () => {
  assert.equal(isMissingFieldError(new Error('Directus GET /items/twaqi_aqi_forecast 403: {"errors":[{"message":"You don\'t have permission to access field \\"content_i18n\\" in collection \\"twaqi_aqi_forecast\\" or it does not exist."}]}')), true)
  assert.equal(isMissingFieldError(new Error('Directus GET /items/twaqi_aqi_forecast 401: Invalid user credentials.')), false)
})

/** In-memory stand-in for the Directus client. */
function fakeDirectus(rows: Array<{ id: number; content: string | null; content_i18n?: unknown }>, opts: { listError?: Error; updateError?: Error; savesBeforeError?: number } = {}) {
  const updates: Array<Array<{ id: number }>> = []
  let saves = 0
  return {
    updates,
    get saves() {
      return saves
    },
    async list<T>(): Promise<T[]> {
      if (opts.listError) throw opts.listError
      return rows as T[]
    },
    async updateBatch(items: Array<{ id: number }>) {
      saves++
      if (opts.updateError && saves > (opts.savesBeforeError ?? 0)) throw opts.updateError
      updates.push(items)
      return {}
    },
  }
}

const KEY = 'k'

test('translateForecast: writes one translation to every row sharing the text', async () => {
  const d = fakeDirectus([
    { id: 1, content: ZH, content_i18n: null },
    { id: 2, content: ZH, content_i18n: null },
  ])
  const calls: string[] = []
  const r = await translateForecast(KEY, d, ['2026-11-03'], { translate: async (t) => (calls.push(t), { text: EN }) })
  assert.deepEqual(calls, [ZH])
  assert.deepEqual(r, { translated: 1, translatedRows: 2, translationFailed: 0, translationDeferred: 0 })
  assert.deepEqual(d.updates, [[
    { id: 1, content_i18n: { 'zh-Hant': ZH, en: EN } },
    { id: 2, content_i18n: { 'zh-Hant': ZH, en: EN } },
  ]])
})

test('translateForecast: a failed call is counted, never thrown, and leaves the row for next run', async () => {
  const d = fakeDirectus([{ id: 1, content: ZH, content_i18n: null }, { id: 2, content: '明日北部普通。', content_i18n: null }])
  const r = await translateForecast(KEY, d, ['2026-11-03'], {
    translate: async (t) => {
      if (t === ZH) throw new Error('timeout')
      return { text: 'Tomorrow north moderate.' }
    },
  })
  assert.deepEqual(r, { translated: 1, translatedRows: 1, translationFailed: 1, translationDeferred: 0 })
  assert.deepEqual(d.updates, [[{ id: 2, content_i18n: { 'zh-Hant': '明日北部普通。', en: 'Tomorrow north moderate.' } }]])
})

test('translateForecast: skips without a key, without the field, and when saving is refused', async () => {
  const fail = async () => {
    throw new Error('should not be called')
  }
  const noKey = await translateForecast('', fakeDirectus([{ id: 1, content: ZH }]), [], { translate: fail })
  assert.match(noKey.translationSkipped ?? '', /OPENROUTER_FORECAST_API_KEY/)

  const missing = fakeDirectus([], { listError: new Error('Directus GET /items/twaqi_aqi_forecast 403: field "content_i18n" … does not exist') })
  const noField = await translateForecast(KEY, missing, ['2026-11-03'], { translate: fail })
  assert.deepEqual(noField, { translated: 0, translatedRows: 0, translationFailed: 0, translationDeferred: 0, translationSkipped: 'content_i18n field missing or not readable' })

  const refused = fakeDirectus([{ id: 1, content: ZH }], { updateError: new Error('Directus PATCH 403: no update on content_i18n') })
  const noSave = await translateForecast(KEY, refused, ['2026-11-03'], { translate: async () => ({ text: EN }) })
  assert.equal(noSave.translated, 0)
  assert.equal(noSave.translationFailed, 1)
  assert.match(noSave.translationSkipped ?? '', /could not save/)
})

const REFUSED = new Error('Directus PATCH /items/twaqi_aqi_forecast 403: You don\'t have permission to access field "content_i18n"')
/** `n` rows with distinct Chinese texts, none translated yet. */
const distinctRows = (n: number, from = 1) => Array.from({ length: n }, (_, k) => ({ id: from + k, content: `第${from + k}則預報。`, content_i18n: null }))

test('translateForecast: a refused save stops model calls after one batch', async () => {
  const d = fakeDirectus(distinctRows(12), { updateError: REFUSED })
  let calls = 0
  const r = await translateForecast(KEY, d, ['2026-11-03'], { translate: async () => (calls++, { text: EN }) })
  assert.equal(calls, TRANSLATION_SAVE_BATCH)
  assert.equal(d.saves, 1)
  assert.deepEqual([r.translated, r.translatedRows, r.translationFailed, r.translationDeferred], [0, 0, TRANSLATION_SAVE_BATCH, 12 - TRANSLATION_SAVE_BATCH])
  assert.match(r.translationSkipped ?? '', /could not save translations: .*403/)
  assert.match(r.translationSkipped ?? '', new RegExp(`model calls stopped after ${TRANSLATION_SAVE_BATCH}, ${12 - TRANSLATION_SAVE_BATCH} left for next run`))
})

test('translateForecast: a refused save of copied translations makes no model calls', async () => {
  const done = buildI18n(ZH, { en: EN })
  const d = fakeDirectus([{ id: 1, content: ZH, content_i18n: done }, { id: 2, content: ZH, content_i18n: null }, ...distinctRows(3, 10)], { updateError: REFUSED })
  const r = await translateForecast(KEY, d, ['2026-11-03'], {
    translate: async () => {
      throw new Error('should not be called')
    },
  })
  assert.deepEqual([r.translated, r.translatedRows, r.translationFailed, r.translationDeferred], [0, 0, 0, 3])
  assert.match(r.translationSkipped ?? '', /model calls stopped after 0, 3 left for next run/)
})

test('translateForecast: saves each batch; a later refusal keeps what was saved', async () => {
  const d = fakeDirectus(distinctRows(7), { updateError: REFUSED, savesBeforeError: 1 })
  let calls = 0
  const r = await translateForecast(KEY, d, ['2026-11-03'], { saveBatch: 2, translate: async () => (calls++, { text: EN }) })
  // Batch 1 saved, batch 2 refused, the other 3 never sent.
  assert.equal(calls, 4)
  assert.deepEqual(d.updates.map((u) => u.map((w) => w.id)), [[1, 2]])
  assert.deepEqual([r.translated, r.translatedRows, r.translationFailed, r.translationDeferred], [2, 2, 2, 3])
  assert.match(r.translationSkipped ?? '', /model calls stopped after 4, 3 left for next run/)
})

test('translateForecast: without a refusal every batch is saved and nothing is skipped', async () => {
  const d = fakeDirectus(distinctRows(5))
  const r = await translateForecast(KEY, d, ['2026-11-03'], { saveBatch: 2, translate: async () => ({ text: EN }) })
  assert.deepEqual(d.updates.map((u) => u.map((w) => w.id)), [[1, 2], [3, 4], [5]])
  assert.deepEqual(r, { translated: 5, translatedRows: 5, translationFailed: 0, translationDeferred: 0 })
})

test('translateForecast: the time budget defers what is left', async () => {
  let t = 0
  const d = fakeDirectus([{ id: 1, content: '一。' }, { id: 2, content: '二。' }, { id: 3, content: '三。' }])
  const r = await translateForecast(KEY, d, ['2026-11-03'], {
    budgetMs: 10,
    now: () => t,
    translate: async () => {
      t += 11
      return { text: 'One.' }
    },
  })
  assert.deepEqual([r.translated, r.translationDeferred, r.translatedRows], [1, 2, 1])
})
