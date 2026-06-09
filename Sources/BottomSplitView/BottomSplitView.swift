import AppKit
import SwiftUI

@available(macOS 14, *)
public struct BottomSplitView<Primary: View, Panel: View, StatusBar: View>: NSViewRepresentable {
    public typealias NSViewType = NSView

    @Binding var isPanelPresented: Bool

    let defaultPanelHeight: CGFloat
    let minPanelHeight: CGFloat
    let maxPanelHeight: CGFloat
    let statusBarHeight: CGFloat
    let collapseSnapThreshold: CGFloat
    let dividerHitExtension: CGFloat
    let primary: Primary
    let panel: Panel
    let statusBar: StatusBar

    public init(
        isPanelPresented: Binding<Bool>,
        defaultPanelHeight: CGFloat,
        minPanelHeight: CGFloat,
        maxPanelHeight: CGFloat,
        statusBarHeight: CGFloat = 32,
        collapseSnapThreshold: CGFloat = 90,
        dividerHitExtension: CGFloat = 10,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder panel: () -> Panel,
        @ViewBuilder statusBar: () -> StatusBar
    ) {
        _isPanelPresented = isPanelPresented
        self.defaultPanelHeight = defaultPanelHeight
        self.minPanelHeight = minPanelHeight
        self.maxPanelHeight = maxPanelHeight
        self.statusBarHeight = statusBarHeight
        self.collapseSnapThreshold = collapseSnapThreshold
        self.dividerHitExtension = dividerHitExtension
        self.primary = primary()
        self.panel = panel()
        self.statusBar = statusBar()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(isPanelPresented: $isPanelPresented)
    }

    public func makeNSView(context: Context) -> NSView {
        let view = BottomSplitContainerView()
        view.onPanelPresentedChange = { presented in
            context.coordinator.setPanelPresented(presented)
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let nsView = nsView as? BottomSplitContainerView else { return }

        nsView.update(
            configuration: .init(
                defaultPanelHeight: defaultPanelHeight,
                minPanelHeight: minPanelHeight,
                maxPanelHeight: maxPanelHeight,
                statusBarHeight: statusBarHeight,
                collapseSnapThreshold: collapseSnapThreshold,
                dividerHitExtension: dividerHitExtension
            ),
            isPanelPresented: isPanelPresented,
            primaryRootView: AnyView(primary),
            panelRootView: AnyView(panel),
            statusRootView: AnyView(statusBar)
        )
    }

    public final class Coordinator: NSObject {
        @Binding private var isPanelPresented: Bool

        init(isPanelPresented: Binding<Bool>) {
            _isPanelPresented = isPanelPresented
        }

        func setPanelPresented(_ presented: Bool) {
            guard isPanelPresented != presented else { return }
            isPanelPresented = presented
        }
    }
}

struct BottomSplitConfiguration: Equatable {
    let defaultPanelHeight: CGFloat
    let minPanelHeight: CGFloat
    let maxPanelHeight: CGFloat
    let statusBarHeight: CGFloat
    let collapseSnapThreshold: CGFloat
    let dividerHitExtension: CGFloat
}

@available(macOS 14, *)
final class BottomSplitContainerView: NSView, NSSplitViewDelegate {
    var onPanelPresentedChange: ((Bool) -> Void)?

    private let splitView = TrackingNSSplitView()
    private let accessoryView = BottomAccessoryView()
    private let primaryHostingView = NSHostingView(rootView: AnyView(EmptyView()))

    private var configuration = BottomSplitConfiguration(
        defaultPanelHeight: 220,
        minPanelHeight: 140,
        maxPanelHeight: .greatestFiniteMagnitude,
        statusBarHeight: 32,
        collapseSnapThreshold: 90,
        dividerHitExtension: 10
    )
    private var currentPanelPresented = false
    private var lastExpandedPanelHeight: CGFloat = 220
    private var hasAppliedInitialLayout = false
    private var isApplyingProgrammaticLayout = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        splitView.frame = bounds

        guard bounds.height > 0 else { return }

        if hasAppliedInitialLayout == false {
            hasAppliedInitialLayout = true
            applyPresentedState(currentPanelPresented, animated: false)
            return
        }

        guard isApplyingProgrammaticLayout == false, splitView.isDraggingDivider == false else {
            return
        }

        let targetBottomHeight = targetBottomHeight(for: currentPanelPresented)
        if abs(currentBottomHeight - targetBottomHeight) > 0.5 {
            setBottomHeight(targetBottomHeight, animated: false)
        }
    }

    func update(
        configuration: BottomSplitConfiguration,
        isPanelPresented: Bool,
        primaryRootView: AnyView,
        panelRootView: AnyView,
        statusRootView: AnyView
    ) {
        let previousConfiguration = self.configuration
        self.configuration = configuration

        splitView.dividerHitExtension = configuration.dividerHitExtension
        primaryHostingView.rootView = primaryRootView
        accessoryView.panelHostingView.rootView = panelRootView
        accessoryView.statusHostingView.rootView = statusRootView
        accessoryView.statusBarHeight = configuration.statusBarHeight

        if lastExpandedPanelHeight.isFinite == false || lastExpandedPanelHeight <= 0 {
            lastExpandedPanelHeight = configuration.defaultPanelHeight
        }

        guard splitView.isDraggingDivider == false else { return }

        if currentPanelPresented != isPanelPresented {
            currentPanelPresented = isPanelPresented
            applyPresentedState(isPanelPresented, animated: hasAppliedInitialLayout)
            return
        }

        if previousConfiguration != configuration {
            if currentPanelPresented {
                lastExpandedPanelHeight = clampedExpandedPanelHeight(lastExpandedPanelHeight)
            }
            applyPresentedState(currentPanelPresented, animated: false)
        }
    }

    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let proposedBottomHeight = splitView.bounds.height - splitView.dividerThickness - proposedPosition
        let clampedBottomHeight = clampedBottomHeight(proposedBottomHeight)
        return splitView.bounds.height - splitView.dividerThickness - clampedBottomHeight
    }

    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        guard splitView.subviews.count == 2 else {
            splitView.adjustSubviews()
            return
        }

        let dividerThickness = splitView.dividerThickness
        let boundedBottomHeight = clampedBottomHeight(currentBottomHeight)
        let totalWidth = splitView.bounds.width
        let totalHeight = splitView.bounds.height
        let primaryHeight = max(0, totalHeight - boundedBottomHeight - dividerThickness)

        primaryHostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: totalWidth,
            height: primaryHeight
        )
        accessoryView.frame = NSRect(
            x: 0,
            y: primaryHeight + dividerThickness,
            width: totalWidth,
            height: boundedBottomHeight
        )
    }

    func splitView(
        _ splitView: NSSplitView,
        effectiveRect proposedEffectiveRect: NSRect,
        forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    ) -> NSRect {
        expandedDividerRect(from: drawnRect)
    }

    func splitView(_ splitView: NSSplitView, additionalEffectiveRectOfDividerAt dividerIndex: Int) -> NSRect {
        guard dividerIndex == 0 else { return .zero }

        let drawnRect = dividerRect(in: splitView, at: dividerIndex)
        let extensionHeight = min(configuration.dividerHitExtension, max(0, splitView.bounds.maxY - drawnRect.maxY))
        return NSRect(
            x: drawnRect.minX,
            y: drawnRect.maxY,
            width: drawnRect.width,
            height: extensionHeight
        )
    }

    private var currentBottomHeight: CGFloat {
        accessoryView.frame.height
    }

    private var currentPanelHeight: CGFloat {
        max(0, currentBottomHeight - configuration.statusBarHeight)
    }

    private func setup() {
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.dividerHitExtension = configuration.dividerHitExtension
        splitView.onDividerDragEnded = { [weak self] in
            self?.handleDividerDragEnded()
        }

        addSubview(splitView)
        splitView.addArrangedSubview(primaryHostingView)
        splitView.addArrangedSubview(accessoryView)
    }

    private func handleDividerDragEnded() {
        let measuredPanelHeight = currentPanelHeight

        if measuredPanelHeight < configuration.collapseSnapThreshold {
            currentPanelPresented = false
            setBottomHeight(configuration.statusBarHeight, animated: true) { [weak self] in
                self?.onPanelPresentedChange?(false)
            }
            return
        }

        currentPanelPresented = true
        lastExpandedPanelHeight = clampedExpandedPanelHeight(measuredPanelHeight)
        onPanelPresentedChange?(true)

        let snappedBottomHeight = configuration.statusBarHeight + lastExpandedPanelHeight
        if abs(currentBottomHeight - snappedBottomHeight) > 0.5 {
            setBottomHeight(snappedBottomHeight, animated: true)
        }
    }

    private func applyPresentedState(_ isPresented: Bool, animated: Bool) {
        guard hasAppliedInitialLayout else { return }

        if isPresented {
            lastExpandedPanelHeight = clampedExpandedPanelHeight(lastExpandedPanelHeight)
        }

        setBottomHeight(targetBottomHeight(for: isPresented), animated: animated)
    }

    private func targetBottomHeight(for isPresented: Bool) -> CGFloat {
        configuration.statusBarHeight + (isPresented ? clampedExpandedPanelHeight(lastExpandedPanelHeight) : 0)
    }

    private func clampedBottomHeight(_ proposedHeight: CGFloat) -> CGFloat {
        let maximumAllowed = maximumAllowedBottomHeight
        return min(max(configuration.statusBarHeight, proposedHeight), maximumAllowed)
    }

    private func clampedExpandedPanelHeight(_ proposedHeight: CGFloat) -> CGFloat {
        let maximumAllowed = maximumAllowedPanelHeight
        guard maximumAllowed > 0 else { return 0 }

        let minimumAllowed = min(configuration.minPanelHeight, maximumAllowed)
        return min(max(proposedHeight, minimumAllowed), min(configuration.maxPanelHeight, maximumAllowed))
    }

    private var maximumAllowedBottomHeight: CGFloat {
        max(configuration.statusBarHeight, bounds.height - splitView.dividerThickness)
    }

    private var maximumAllowedPanelHeight: CGFloat {
        max(0, maximumAllowedBottomHeight - configuration.statusBarHeight)
    }

    private func setBottomHeight(_ bottomHeight: CGFloat, animated: Bool, completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard splitView.subviews.count > 1 else {
            completion?()
            return
        }

        let clampedHeight = clampedBottomHeight(bottomHeight)
        let applyWithoutAnimation = {
            let dividerPosition = max(0, self.splitView.bounds.height - self.splitView.dividerThickness - clampedHeight)
            self.splitView.setPosition(dividerPosition, ofDividerAt: 0)
            self.accessoryView.needsLayout = true
            self.needsLayout = true
            completion?()
        }

        guard animated, window != nil else {
            applyWithoutAnimation()
            return
        }

        isApplyingProgrammaticLayout = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            let dividerPosition = max(0, self.splitView.bounds.height - self.splitView.dividerThickness - clampedHeight)
            self.splitView.animator().setPosition(dividerPosition, ofDividerAt: 0)
        } completionHandler: {
            Task { @MainActor [weak self] in
                guard let self else {
                    completion?()
                    return
                }

                self.isApplyingProgrammaticLayout = false
                self.accessoryView.needsLayout = true
                self.needsLayout = true
                completion?()
            }
        }
    }

    private func expandedDividerRect(from drawnRect: NSRect) -> NSRect {
        let extensionHeight = configuration.dividerHitExtension
        return NSRect(
            x: drawnRect.minX,
            y: drawnRect.minY,
            width: drawnRect.width,
            height: drawnRect.height + extensionHeight
        )
    }

    private func dividerRect(in splitView: NSSplitView, at dividerIndex: Int) -> NSRect {
        guard dividerIndex < splitView.subviews.count - 1 else { return .zero }

        let upperSubview = splitView.subviews[dividerIndex]
        return NSRect(
            x: splitView.bounds.minX,
            y: upperSubview.frame.maxY,
            width: splitView.bounds.width,
            height: splitView.dividerThickness
        )
    }
}

@available(macOS 10.15, *)
private final class BottomAccessoryView: NSView {
    let panelHostingView = NSHostingView(rootView: AnyView(EmptyView()))
    let statusHostingView = NSHostingView(rootView: AnyView(EmptyView()))

    var statusBarHeight: CGFloat = 32 {
        didSet {
            needsLayout = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(panelHostingView)
        addSubview(statusHostingView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let boundedStatusBarHeight = min(statusBarHeight, bounds.height)
        statusHostingView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: boundedStatusBarHeight)

        let panelHeight = max(0, bounds.height - boundedStatusBarHeight)
        panelHostingView.frame = NSRect(x: 0, y: boundedStatusBarHeight, width: bounds.width, height: panelHeight)
        panelHostingView.isHidden = panelHeight <= 0.5
    }
}

private final class TrackingNSSplitView: NSSplitView {
    var dividerHitExtension: CGFloat = 10
    var onDividerDragEnded: (() -> Void)?
    private(set) var isDraggingDivider = false

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let shouldTrackDivider = subviews.count > 1 && expandedDividerRect(at: 0).contains(point)

        if shouldTrackDivider {
            isDraggingDivider = true
        }

        super.mouseDown(with: event)

        if shouldTrackDivider {
            isDraggingDivider = false
            onDividerDragEnded?()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        guard subviews.count > 1 else { return }
        addCursorRect(expandedDividerRect(at: 0), cursor: .resizeUpDown)
    }

    private func expandedDividerRect(at dividerIndex: Int) -> NSRect {
        var rect = dividerRect(at: dividerIndex)
        let extensionHeight = min(dividerHitExtension, max(0, bounds.maxY - rect.maxY))
        rect.size.height += extensionHeight
        return rect
    }

    private func dividerRect(at dividerIndex: Int) -> NSRect {
        guard dividerIndex < subviews.count - 1 else { return .zero }

        let upperSubview = subviews[dividerIndex]
        return NSRect(
            x: bounds.minX,
            y: upperSubview.frame.maxY,
            width: bounds.width,
            height: dividerThickness
        )
    }
}
