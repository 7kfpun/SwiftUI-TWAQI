package com.kfpun.twaqi.cooperate

import com.kfpun.twaqi.forms.SubmitResult

/** Sends business partner enquiries (iOS `CooperateService`). */
fun interface CooperateRepository {
    suspend fun submit(submission: CooperateSubmission): SubmitResult
}
