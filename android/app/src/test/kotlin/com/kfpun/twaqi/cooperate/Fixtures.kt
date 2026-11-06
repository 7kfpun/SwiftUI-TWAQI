package com.kfpun.twaqi.cooperate

import com.kfpun.twaqi.forms.ClientInfo

internal val testClient = ClientInfo(
    packageName = "com.kfpun.twaqi",
    appVersion = "2.0.0",
    build = "3000000",
    deviceModel = "Google Pixel 9",
    osVersion = "16",
    deviceIdiom = "phone",
    locale = "zh-TW",
    appLanguage = "zh-Hant",
    preferredLanguages = "zh-TW,en-US",
    timeZone = "Asia/Taipei"
)

internal fun submission(jobTitle: String? = null, phone: String? = null, website: String? = null) =
    CooperateSubmission.make(
        cooperationType = CooperationType.DATA_API,
        company = "  Fox Co. \n",
        name = " Ann ",
        jobTitle = jobTitle,
        email = " ann@example.com ",
        phone = phone,
        website = website,
        message = "  Embed AQI on our site \n",
        client = testClient
    )

internal val completeForm = CooperateForm(
    cooperationType = CooperationType.ADVERTISING,
    company = "Fox Co.",
    name = "Ann",
    email = "ann@example.com",
    message = "Banner on the map"
)
