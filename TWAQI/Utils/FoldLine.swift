//
//  FoldLine.swift
//  TWAQI
//
//  Copyright © 2026 kf. All rights reserved.
//

import SwiftUI
import UIKit

/// Where a foldable's inner display folds, so the two-pane layouts can put
/// their divider on it.
///
/// Unfolded, the iPhone Duo is one continuous landscape display with the hinge
/// down its middle. A pane that straddles that line is bent in half whenever
/// the phone isn't opened flat, so map | station, list | station and
/// Help | topic each split there instead of at their usual width.
///
/// The hinge is only observable from iOS 27.1 (`UIHingeInteraction`). Before
/// that, and on every device without one, there is no fold and the layouts
/// keep their own split.
enum FoldLine {
    /// Narrowest a pane may be for the split to follow the fold. A window that
    /// only just crosses the hinge, as in split screen, keeps its own split.
    static let minimumPaneWidth: CGFloat = 320

    /// Width of a leading pane that ends on the fold, for a container whose
    /// frame in the window (`.global`) is `frame`. Nil when there is no fold,
    /// or when it falls too close to either edge of the container.
    static func leadingWidth(foldX: CGFloat?, in frame: CGRect) -> CGFloat? {
        guard let foldX = foldX else { return nil }
        let width = foldX - frame.minX
        guard width >= minimumPaneWidth, frame.width - width >= minimumPaneWidth else { return nil }
        return width
    }
}

private struct FoldLineXKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// x of the fold in window (`.global`) coordinates. Nil when there is no
    /// hinge, the phone is closed, the fold runs across the window rather
    /// than down it, or the window doesn't straddle it.
    var foldLineX: CGFloat? {
        get { self[FoldLineXKey.self] }
        set { self[FoldLineXKey.self] = newValue }
    }
}

extension View {
    /// Publishes `foldLineX` to everything below. Applied once, at the root,
    /// where the view spans the whole window.
    func readsFoldLine() -> some View {
        modifier(FoldLineReader())
    }
}

private struct FoldLineReader: ViewModifier {
    @State private var foldX: CGFloat?

    func body(content: Content) -> some View {
        content
            .background(FoldObserver(foldX: $foldX).accessibilityHidden(true))
            .environment(\.foldLineX, foldX)
    }
}

private struct FoldObserver: UIViewRepresentable {
    @Binding var foldX: CGFloat?

    func makeUIView(context: Context) -> FoldObservingView {
        let view = FoldObservingView()
        view.onChange = { foldX = $0 }
        return view
    }

    func updateUIView(_ uiView: FoldObservingView, context: Context) {
        uiView.onChange = { foldX = $0 }
    }
}

/// An invisible view that works out where the fold crosses its window, again
/// whenever the hinge moves or the window is laid out (rotation, resizing,
/// moving between the outer and inner display).
private final class FoldObservingView: UIView {
    var onChange: ((CGFloat?) -> Void)?

    private var isHingeOpen = false
    private var reported: CGFloat??

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false

        if #available(iOS 27.1, *) {
            addInteraction(UIHingeInteraction { [weak self] _, update in
                // Unknown counts as open: the width checks below still rule
                // out the outer display.
                self?.isHingeOpen = update.hinge.map { $0.status != .closed } ?? false
                self?.report()
            })
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        report()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        report()
    }

    private func report() {
        let foldX = currentFoldX()
        guard reported != .some(foldX) else { return }
        reported = .some(foldX)
        // Not from inside a layout pass: this sets SwiftUI state.
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(foldX)
        }
    }

    private func currentFoldX() -> CGFloat? {
        guard isHingeOpen,
              let window = window,
              let screen = window.windowScene?.screen else { return nil }

        // A book fold runs down the middle of the landscape display. Turned
        // to portrait it runs across, and can't separate side-by-side panes.
        let bounds = screen.bounds
        guard bounds.width > bounds.height else { return nil }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let x = window.convert(center, from: screen.coordinateSpace).x
        guard x >= FoldLine.minimumPaneWidth,
              x <= window.bounds.width - FoldLine.minimumPaneWidth else { return nil }
        return x
    }
}
