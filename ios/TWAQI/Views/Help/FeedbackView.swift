//
//  FeedbackView.swift
//  TWAQI
//
//  Created by kf on 29/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// Sends feedback to the Directus `twaqi_feedback` collection.
/// Platform, app and device details are added
/// automatically and never shown.
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// Where the form was opened from, for the `open_feedback_form` event.
    private let source: FeedbackSource

    @State private var rating: Int?
    @State private var message = ""
    @State private var otherFeedback = ""
    @State private var interviewInterest = false
    @State private var name = ""
    @State private var email = ""

    @State private var isSending = false
    @State private var showingSuccess = false
    /// What was sent, for the thank-you's wording and buttons.
    @State private var sent: FeedbackSubmission?
    @State private var failure: FeedbackError?

    var body: some View {
        Form {
            ratingSection
            messageSection
            otherFeedbackSection
            interviewSection
            contactSection
            sendSection
        }
        .navigationTitle("Feedback.title")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSending)
        .onAppear {
            TrackingManager.logEvent(.openFeedbackForm, parameters: source.openFormEventParameters)
        }
        .alert("Feedback.sent_title", isPresented: $showingSuccess) {
            #if os(iOS)
            if offersAppStoreReview {
                // User-initiated only: no custom rating pop-up (5.6.1).
                Button("Feedback.rate_on_app_store") {
                    TrackingManager.logEvent(
                        .writeReviewTapped,
                        parameters: ["source": ReviewRequestSource.feedback.rawValue]
                    )
                    openURL(StoreReviewHelper.writeReviewURL)
                    finish()
                }
            }
            #endif
            Button("OK", action: finish)
        } message: {
            Text(LocalizedStringKey(Self.thankYouMessageKey(
                offersAppStoreReview: offersAppStoreReview,
                email: sent?.email ?? ""
            )))
        }
        .alert(
            "Feedback.error_title",
            isPresented: Binding(
                get: { failure != nil },
                set: { if !$0 { failure = nil } }
            )
        ) {
            Button("Feedback.try_again") {
                failure = nil
                send()
            }
            Button("Feedback.cancel", role: .cancel) {}
        } message: {
            Text(failure == .offline
                ? LocalizedStringKey("Feedback.error_offline")
                : LocalizedStringKey("Feedback.error_generic"))
        }
    }

    /// How long the thank-you shows before the system review prompt.
    nonisolated static let reviewPromptDelay: UInt64 = 1_000_000_000

    /// The thank-you's message: a 4- or 5-star feedback offers the App
    /// Store instead; a lower one with an email says we may reply.
    nonisolated static func thankYouMessageKey(offersAppStoreReview: Bool, email: String) -> String {
        if !offersAppStoreReview, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Feedback.sent_message_may_reply"
        }
        return "Feedback.sent_message"
    }

    /// Whether the thank-you offers "Rate on the App Store" (iPhone/iPad only).
    private var offersAppStoreReview: Bool {
        #if os(iOS)
        return sent.map { StoreReviewHelper.shouldRequestReview(afterFeedbackRating: $0.rating) } ?? false
        #else
        return false
        #endif
    }

    // Explicit: the private `@State` properties would make the memberwise
    // initialiser private.
    init(source: FeedbackSource = .help) {
        self.source = source
    }

    private var ratingSection: some View {
        Section(header: requiredLabel("Feedback.rating_header")) {
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating = star
                    } label: {
                        Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundColor(star <= (rating ?? 0) ? .yellow : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Feedback.rating_stars \(star)"))
                    .accessibilityAddTraits(star == rating ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    private var messageSection: some View {
        Section(header: requiredLabel("Feedback.message_header")) {
            multilineField(text: $message, placeholder: "Feedback.message_placeholder")
        }
    }

    private var otherFeedbackSection: some View {
        Section(header: Text("Feedback.other_header")) {
            multilineField(text: $otherFeedback, placeholder: "Feedback.optional", minHeight: 80)
        }
    }

    private var interviewSection: some View {
        Section(footer: Text("Feedback.interview_footer").fontWeight(.light)) {
            Toggle(isOn: $interviewInterest) {
                Text("Feedback.interview")
                    .fontWeight(.light)
            }
        }
    }

    private var contactSection: some View {
        Section(
            footer: Group {
                if showsEmailError {
                    Text("Feedback.email_invalid").foregroundColor(.red)
                } else {
                    Text("Feedback.email_footer").fontWeight(.light)
                }
            }
        ) {
            TextField("Feedback.name_placeholder", text: $name)
                .textContentType(.name)

            TextField("Feedback.email_placeholder", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
    }

    private var sendSection: some View {
        Section(footer: Text("Feedback.privacy_footer").fontWeight(.light)) {
            Button(action: send) {
                HStack {
                    Spacer()
                    if isSending {
                        ProgressView()
                    } else {
                        Text("Feedback.send")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .disabled(!canSend)
        }
    }

    /// Section header or row label with a red asterisk for required fields.
    private func requiredLabel(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 2) {
            Text(title)
            Text(verbatim: "*").foregroundColor(.red)
        }
    }

    private func multilineField(
        text: Binding<String>,
        placeholder: LocalizedStringKey,
        minHeight: CGFloat = 120
    ) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .foregroundColor(.secondary)
                    .fontWeight(.light)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }
            TextEditor(text: text)
                .frame(minHeight: minHeight)
        }
    }

    /// Only once something is typed, so an empty form isn't shown in red.
    private var showsEmailError: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !FeedbackSubmission.isValidEmail(email)
    }

    private var canSend: Bool {
        !isSending
            && rating != nil
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && FeedbackSubmission.isValidEmail(email)
    }

    /// Closes the thank-you. In a wide window this is the column beside
    /// Help, which `dismiss` can't close: empty it so it can't be sent twice.
    private func finish() {
        clear()
        dismiss()
    }

    private func clear() {
        rating = nil
        message = ""
        otherFeedback = ""
        interviewInterest = false
        name = ""
        email = ""
    }

    private func send() {
        guard canSend, let rating = rating else { return }
        let submission = FeedbackSubmission.make(
            rating: rating,
            message: message,
            otherFeedback: otherFeedback,
            interviewInterest: interviewInterest,
            name: name,
            email: email
        )
        isSending = true

        Task {
            do {
                try await FeedbackService.submit(submission)
                TrackingManager.logEvent(
                    .submitFeedback,
                    parameters: [
                        "platform": submission.platform,
                        "rating": submission.rating,
                        "interview_interest": submission.interviewInterest,
                    ]
                )
                isSending = false
                sent = submission
                showingSuccess = true
                #if os(iOS)
                // After the thank-you appears, not over the form; 4–5 stars only.
                if StoreReviewHelper.shouldRequestReview(afterFeedbackRating: submission.rating) {
                    try? await Task.sleep(nanoseconds: Self.reviewPromptDelay)
                    // Closed within the delay: not over the screen behind.
                    guard showingSuccess else { return }
                    StoreReviewHelper.requestReviewAfterFeedback(rating: submission.rating)
                }
                #endif
            } catch {
                let feedbackError = error as? FeedbackError ?? .network
                debugPrint("FeedbackService.submit failed: \(feedbackError)")
                TrackingManager.logEvent(
                    .submitFeedbackFailed,
                    parameters: ["reason": String(describing: feedbackError)]
                )
                isSending = false
                failure = feedbackError
            }
        }
    }
}

struct FeedbackView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            FeedbackView()
        }
    }
}
