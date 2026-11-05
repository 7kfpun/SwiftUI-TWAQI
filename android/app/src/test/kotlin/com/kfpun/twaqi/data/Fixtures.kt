package com.kfpun.twaqi.data

/** Recorded API responses in `src/test/resources/fixtures`, trimmed, with every host replaced by example.com. */
object Fixtures {
    fun read(name: String): String =
        requireNotNull(javaClass.getResource("/fixtures/$name")) { "no fixture $name" }.readText()

    val countries get() = read("countries.json")
    val stations get() = read("stations.json")
    val currentPollutants get() = read("current-pollutants.json")
    val historicalPollutants get() = read("historical-pollutants.json")
    val forecast get() = read("aqi-forecast.json")
}
