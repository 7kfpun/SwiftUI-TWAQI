package com.kfpun.twaqi.data.places

import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.model.Station
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** FOX-114: Taiwan's official English place names, never machine-translated. */
class TaiwanPlaceNamesTest {
    private val places = TaiwanPlaceNames.parse(File("src/main/assets/${TaiwanPlaceNames.ASSET}").readText())

    @Test
    fun theTableHasEveryCountyAndTownship() {
        assertEquals(22, places.countyCount)
        assertEquals(368, places.townshipCount)
    }

    @Test
    fun districtsFromTheQaPass() {
        // ML Kit said "New store area", "Daxian District" and "North District".
        assertEquals("Xindian District", places.township("新店區", "新北市"))
        assertEquals("Da'an District", places.township("大安區", "臺北市"))
        assertEquals("Beitou District", places.township("北投區", "臺北市"))
        assertEquals("Songshan District", places.township("松山區", "臺北市"))
        assertEquals("Shilin District", places.township("士林區"))
    }

    @Test
    fun townshipsCitiesAndNamesakes() {
        assertEquals("Puli Township", places.township("埔里鎮", "南投縣"))
        assertEquals("Ren'ai Township", places.township("仁愛鄉", "南投縣"))
        assertEquals("Ren'ai District", places.township("仁愛區", "基隆市"))
        assertEquals("Hualien City", places.township("花蓮市", "花蓮縣"))
        // 東區 is in Hsinchu City, Chiayi City and Tainan City, 大安區 in Taipei and Taichung.
        assertEquals("East District", places.township("東區", "臺南市"))
        assertEquals("East District", places.township("東區"))
        assertEquals("Da'an District", places.township("大安區", "臺中市"))
        // A county the table doesn't know still finds the township by name.
        assertEquals("Xindian District", places.township("新店區", "臺北縣"))
    }

    @Test
    fun citiesAndCounties() {
        assertEquals("New Taipei City", places.county("新北市"))
        assertEquals("Taipei City", places.county("臺北市"))
        assertEquals("Lienchiang County", places.county("連江縣"))
        // MOENV and the API write 台 as often as 臺.
        assertEquals("Taipei City", places.county("台北市"))
        assertEquals("Taitung City", places.township("台東市", "台東縣"))
        assertEquals("Taixi Township", places.township(" 臺西鄉 ", "雲林縣"))
    }

    @Test
    fun unknownNamesAreNull() {
        assertNull(places.township("不存在區"))
        assertNull(places.township(""))
        assertNull(places.township(null))
        assertNull(places.county("火星市"))
        assertNull(places.county(null))
        assertNull(TaiwanPlaceNames.EMPTY.township("新店區"))
    }

    @Test
    fun localityInEnglishUsesTheTableAndKeepsTheChineseWhenUnknown() {
        assertEquals("Xindian District, New Taipei City", pollutant("新店區", "New Taipei City", "新北市").locality())
        assertEquals("Da'an District, Taipei City", station("大安區", "Taipei City", "臺北市").locality())
        // No English county from the API: the table's.
        assertEquals("Songshan District, Taipei City", pollutant("松山區", null, "臺北市").locality())
        // Not in the table: as written, never a guess.
        assertEquals("新興里, Taipei City", pollutant("新興里", "Taipei City", "臺北市").locality())
        assertEquals("新興里, 火星市", pollutant("新興里", null, "火星市").locality())
        // The API's own English township wins, should it ever send one.
        assertEquals(
            "Xindian Dist., New Taipei City",
            pollutant("新店區", "New Taipei City", "新北市", townshipEn = "Xindian Dist.").locality()
        )
        // Chinese stays as the API wrote it.
        assertEquals("新店區, 新北市", pollutant("新店區", "New Taipei City", "新北市").displayLocality(true, places))
        // A micro sensor has none of it.
        assertNull(pollutant(null, null, null).locality())
    }

    private fun Pollutant.locality() = displayLocality(chinese = false, places)

    private fun Station.locality() = displayLocality(chinese = false, places)

    private fun pollutant(township: String?, county: String?, countyLocal: String?, townshipEn: String? = null) =
        Pollutant(
            stationId = 1, code = "x", lat = 25.0, lon = 121.5, aqi = 40.0, pm25 = 10.0, pm10 = 20.0,
            no2 = 5.0, so2 = 1.0, co = 0.3, o3 = 30.0, windDirection = 0.0, windSpeed = 0.0,
            publishTime = "2026-11-06 14:00:00", name = "X", nameLocal = "X",
            address = "臺北市松山區八德路四段746號",
            county = county, countyLocal = countyLocal, township = township, townshipEn = townshipEn
        )

    private fun station(township: String?, county: String?, countyLocal: String?) = Station(
        id = 1, countryId = 1, countryCode = "TW", code = "x", lat = 25.0, lon = 121.5, imageUrl = null,
        name = "X", nameLocal = "X", county = county, countyLocal = countyLocal, township = township
    )
}
