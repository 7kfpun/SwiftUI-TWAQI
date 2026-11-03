// Alert text, in the app's language. Pure, so it can be tested with node --test.

import type { Direction } from './rules.ts'

/** The app writes `bundle.preferredLocalizations.first`: "zh-Hant" or "en". */
export function isChinese(locale: string | null | undefined): boolean {
  return (locale ?? '').toLowerCase().startsWith('zh')
}

export function stationName(
  locale: string | null | undefined,
  names: { nameZh: string | null; nameEn: string | null },
  stationId: number | null,
): string {
  const name = isChinese(locale) ? names.nameZh ?? names.nameEn : names.nameEn ?? names.nameZh
  return name ?? `#${stationId ?? '?'}`
}

export function alertText(
  direction: Direction,
  locale: string | null | undefined,
  name: string,
  aqi: number,
  threshold: number,
): { title: string; body: string } {
  const value = String(Math.round(aqi))
  const limit = String(Math.round(threshold))
  if (isChinese(locale)) {
    return direction === 'above'
      ? { title: `${name} AQI ${value}`, body: `空氣品質指標已高於你設定的 ${limit}，外出請留意。` }
      : { title: `${name} AQI ${value}`, body: `空氣品質指標已低於你設定的 ${limit}，空氣變好了。` }
  }
  return direction === 'above'
    ? { title: `${name}: AQI ${value}`, body: `Air quality is now above your alert level of ${limit}.` }
    : { title: `${name}: AQI ${value}`, body: `Air quality is now below your alert level of ${limit}. The air has cleared up.` }
}

export function testText(locale: string | null | undefined): { title: string; body: string } {
  return isChinese(locale)
    ? { title: '台灣空氣 測試通知', body: '這台裝置的空氣品質通知運作正常。' }
    : { title: 'Taiwan Air test alert', body: 'Air quality alerts are working on this device.' }
}
