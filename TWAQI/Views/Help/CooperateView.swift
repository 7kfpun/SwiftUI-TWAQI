//
//  CooperateView.swift
//  TWAQI
//
//  Created by kf on 31/10/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// Business partner enquiry form. Sends to the Directus `twaqi_cooperate`
/// collection, replacing the old Airtable partner page. App and device
/// details are added automatically and never shown.
struct CooperateView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var cooperationType: CooperationType?
    @State private var company = ""
    @State private var name = ""
    @State private var jobTitle = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var website = ""
    @State private var message = ""

    @State private var isSending = false
    @State private var showingSuccess = false
    @State private var failure: FeedbackError?

    var body: some View {
        Form {
            typeSection
            companySection
            contactSection
            messageSection
            sendSection
        }
        .navigationTitle("Cooperate.title")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSending)
        .onAppear {
            TrackingManager.logEvent(eventName: "open_cooperate_form")
        }
        .alert("Cooperate.sent_title", isPresented: $showingSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Cooperate.sent_message")
        }
        .alert(
            "Cooperate.error_title",
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

    private var typeSection: some View {
        Section(
            header: Text("Cooperate.intro_header"),
            footer: Text("Cooperate.intro_footer").fontWeight(.light)
        ) {
            Picker(selection: $cooperationType) {
                Text("Cooperate.type_choose").tag(CooperationType?.none)
                ForEach(CooperationType.allCases) { type in
                    Text(type.title).tag(CooperationType?.some(type))
                }
            } label: {
                requiredLabel("Cooperate.type")
            }
        }
    }

    private var companySection: some View {
        Section(header: requiredLabel("Cooperate.company_header")) {
            TextField("Cooperate.company_placeholder", text: $company)
                .textContentType(.organizationName)

            TextField("Cooperate.website_placeholder", text: $website)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
    }

    private var contactSection: some View {
        Section(
            header: requiredLabel("Cooperate.contact_header"),
            footer: Group {
                if showsEmailError {
                    Text("Feedback.email_invalid").foregroundColor(.red)
                } else {
                    Text("Cooperate.contact_footer").fontWeight(.light)
                }
            }
        ) {
            TextField("Cooperate.name_placeholder", text: $name)
                .textContentType(.name)

            TextField("Cooperate.job_title_placeholder", text: $jobTitle)
                .textContentType(.jobTitle)

            TextField("Feedback.email_placeholder", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

            TextField("Cooperate.phone_placeholder", text: $phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
        }
    }

    private var messageSection: some View {
        Section(header: requiredLabel("Cooperate.message_header")) {
            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text("Cooperate.message_placeholder")
                        .foregroundColor(.secondary)
                        .fontWeight(.light)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $message)
                    .frame(minHeight: 140)
            }
        }
    }

    private var sendSection: some View {
        Section(footer: Text("Cooperate.privacy_footer").fontWeight(.light)) {
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

    /// Only once something is typed, so an empty form isn't shown in red.
    private var showsEmailError: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !FeedbackSubmission.isValidEmail(email)
    }

    private var canSend: Bool {
        !isSending
            && cooperationType != nil
            && FeedbackSubmission.trimmed(company) != nil
            && FeedbackSubmission.trimmed(name) != nil
            && FeedbackSubmission.isValidEmail(email)
            && FeedbackSubmission.trimmed(message) != nil
    }

    private func send() {
        guard canSend, let cooperationType = cooperationType else { return }
        let submission = CooperateSubmission.make(
            cooperationType: cooperationType,
            company: company,
            name: name,
            jobTitle: jobTitle,
            email: email,
            phone: phone,
            website: website,
            message: message
        )
        isSending = true

        Task {
            do {
                try await CooperateService.submit(submission)
                TrackingManager.logEvent(
                    eventName: "submit_cooperate",
                    parameters: ["cooperation_type": submission.cooperationType]
                )
                isSending = false
                showingSuccess = true
            } catch {
                let cooperateError = error as? FeedbackError ?? .network
                debugPrint("CooperateService.submit failed: \(cooperateError)")
                TrackingManager.logEvent(
                    eventName: "submit_cooperate_failed",
                    parameters: ["reason": String(describing: cooperateError)]
                )
                isSending = false
                failure = cooperateError
            }
        }
    }
}

private extension CooperationType {
    var title: LocalizedStringKey {
        switch self {
        case .advertising:
            return "Cooperate.type_advertising"
        case .dataApi:
            return "Cooperate.type_data_api"
        case .sponsorship:
            return "Cooperate.type_sponsorship"
        case .media:
            return "Cooperate.type_media"
        case .other:
            return "Cooperate.type_other"
        }
    }
}

struct CooperateView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CooperateView()
        }
    }
}
