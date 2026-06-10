import CoreGraphics
import Testing
@testable import BottomSplitView

struct BottomSplitLayoutCalculatorTests {
    @Test("clamped bottom height stays within status bar and available height")
    func clampedBottomHeightRespectsBounds() {
        let calculator = makeCalculator(containerHeight: 300)

        #expect(calculator.clampedBottomHeight(20) == 32)
        #expect(calculator.clampedBottomHeight(180) == 180)
        #expect(calculator.clampedBottomHeight(500) == 299)
    }

    @Test("expanded panel height clamps to configured and available limits")
    func clampedExpandedPanelHeightRespectsBounds() {
        let calculator = makeCalculator(containerHeight: 240)

        #expect(calculator.clampedExpandedPanelHeight(20) == 140)
        #expect(calculator.clampedExpandedPanelHeight(400) == 207)
    }

    @Test("expanded panel height falls back to available space when minimum cannot fit")
    func clampedExpandedPanelHeightUsesAvailableSpaceWhenContainerIsSmall() {
        let calculator = makeCalculator(containerHeight: 120)

        #expect(calculator.clampedExpandedPanelHeight(20) == 87)
        #expect(calculator.clampedExpandedPanelHeight(300) == 87)
    }

    @Test("target bottom height uses status bar for collapsed and remembered height for expanded")
    func targetBottomHeightMatchesPresentationState() {
        let calculator = makeCalculator(containerHeight: 400)

        #expect(calculator.targetBottomHeight(isPresented: false, lastExpandedPanelHeight: 220) == 32)
        #expect(calculator.targetBottomHeight(isPresented: true, lastExpandedPanelHeight: 220) == 252)
    }

    @Test("drag ending below threshold collapses and keeps last expanded height")
    func dragEndedBelowThresholdCollapsesPanel() {
        let calculator = makeCalculator(containerHeight: 400)

        let outcome = calculator.dragEnded(currentPanelHeight: 60, lastExpandedPanelHeight: 220)

        #expect(outcome == BottomSplitDragOutcome(
            isPanelPresented: false,
            lastExpandedPanelHeight: 220,
            snappedBottomHeight: 32
        ))
    }

    @Test("drag ending above threshold expands and snaps to clamped height")
    func dragEndedAboveThresholdExpandsPanel() {
        let calculator = makeCalculator(containerHeight: 240)

        let outcome = calculator.dragEnded(currentPanelHeight: 400, lastExpandedPanelHeight: 220)

        #expect(outcome == BottomSplitDragOutcome(
            isPanelPresented: true,
            lastExpandedPanelHeight: 207,
            snappedBottomHeight: 239
        ))
    }

    private func makeCalculator(
        containerHeight: CGFloat,
        configuration: BottomSplitConfiguration = BottomSplitConfiguration(
            defaultPanelHeight: 220,
            minPanelHeight: 140,
            maxPanelHeight: 260,
            statusBarHeight: 32,
            collapseSnapThreshold: 90,
            dividerHitExtension: 10
        ),
        dividerThickness: CGFloat = 1
    ) -> BottomSplitLayoutCalculator {
        BottomSplitLayoutCalculator(
            configuration: configuration,
            containerHeight: containerHeight,
            dividerThickness: dividerThickness
        )
    }
}
