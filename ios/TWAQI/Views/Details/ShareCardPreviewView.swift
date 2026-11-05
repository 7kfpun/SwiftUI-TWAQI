//
//  ShareCardPreviewView.swift
//  TWAQI
//
//  Created by kf on 4/11/26.
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI

/// Shown by the station page's share button (FOX-73): the card as it will be
/// sent, a shape for where it's going, then Share or Save to Photos.
///
/// The preview is the rendered image itself, so what is shared or saved is
/// exactly what the reader saw.
struct ShareCardPreviewView: View {
    /// The shape is ignored; the picker's choice replaces it.
    let card: ShareCardView
    let stationId: Int

    @AppStorage(ShareCardShape.defaultsKey) private var shape: ShareCardShape = .feed
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var saveResult: ShareCardSharing.SaveResult?
    @State private var isSaving = false
    /// Decides when closing counts as a cancel.
    @State private var session = ShareCardSession()
    @State private var didLogOpen = false
    /// Behind the Share button, for the share popover in a wide window.
    @State private var shareAnchor = PopoverAnchor()

    private var shapedCard: ShareCardView {
        var card = card
        card.shape = shape
        return card
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Picker("Share.shape", selection: $shape) {
                    ForEach(ShareCardShape.allCases) { shape in
                        Text(shape.label).tag(shape)
                    }
                }
                .pickerStyle(.segmented)

                Button(action: share) {
                    Label("Share.share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .background(PopoverAnchorView(anchor: shareAnchor))
                .disabled(image == nil)

                Button(action: save) {
                    Label("Share.save_to_photos", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(image == nil || isSaving)

                saveStatus
            }
            .padding()
            // A readable column in a wide window (iPad, an unfolded Duo).
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .navigationTitle(Text("Share.preview_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Share.cancel") { dismiss() }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            session.appeared()
            render()
            guard !didLogOpen else { return }
            didLogOpen = true
            ShareCardSharing.logPreviewOpened(card: shapedCard, stationId: stationId)
        }
        .onChange(of: shape) { _ in
            saveResult = nil
            render()
        }
        // Cancel, a swipe down, or the station page going away.
        .onDisappear {
            guard session.disappeared() else { return }
            ShareCardSharing.log(.cancel, card: shapedCard, stationId: stationId)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image = image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.2), radius: 8, y: 2)
                .accessibilityLabel(Text(verbatim: ShareCardSharing.message(title: card.title, aqi: card.aqi)))
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var saveStatus: some View {
        switch saveResult {
        case .saved:
            Label("Share.saved", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundColor(.green)
        case .denied:
            VStack(spacing: 4) {
                Text("Share.save_denied")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Share.open_settings", action: openSettings)
                    .font(.footnote)
            }
        case .failed:
            Text("Share.save_failed")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        case nil:
            EmptyView()
        }
    }

    private func render() {
        image = ShareCardSharing.render(shapedCard)
    }

    private func share() {
        guard let image = image else { return }
        session.shared()
        ShareCardSharing.share(image: image, card: shapedCard, from: shareAnchor.view)
        ShareCardSharing.log(.share, card: shapedCard, stationId: stationId)
    }

    private func save() {
        guard let image = image, !isSaving else { return }
        let card = shapedCard
        let session = session
        isSaving = true
        session.saveStarted()
        Task { @MainActor in
            let result = await ShareCardSharing.saveToPhotos(image)
            isSaving = false
            saveResult = result
            if result == .saved {
                ShareCardSharing.log(.save, card: card, stationId: stationId)
            }
            // The sheet may be gone by now: a failed save then ends the
            // session as a cancel.
            if session.saveFinished(saved: result == .saved) {
                ShareCardSharing.log(.cancel, card: card, stationId: stationId)
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
