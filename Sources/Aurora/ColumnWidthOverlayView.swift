import AppKit

/// Due guide verticali sopra l'editor, visibili mentre si tiene premuto ⌥.
/// La larghezza è sempre calcolata rispetto al centro: trascinare una guida
/// sposta automaticamente anche quella opposta della stessa distanza.
final class ColumnWidthOverlayView: NSView {

    var preferredWidth: CGFloat = Theme().maxContentWidth {
        didSet { needsDisplay = true; invalidateCursorRects() }
    }
    var availableWidth: CGFloat = 0 {
        didSet { needsDisplay = true; invalidateCursorRects() }
    }
    var minimumSideMargin: CGFloat = Theme().minSideMargin {
        didSet { needsDisplay = true; invalidateCursorRects() }
    }

    var onWidthPreview: ((CGFloat) -> Void)?
    var onWidthCommit: ((CGFloat) -> Void)?

    private var optionIsHeld = false
    private var isDraggingGuide = false
    private var previewWidth: CGFloat?
    private let hitTolerance: CGFloat = 7
    /// Respiro visivo fra il bordo del testo e la relativa guida.
    private let guideToTextSpacing: CGFloat = 18

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    var isInteracting: Bool { isDraggingGuide }

    func setOptionHeld(_ isHeld: Bool) {
        guard optionIsHeld != isHeld else { return }
        optionIsHeld = isHeld
        needsDisplay = true
        invalidateCursorRects()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard guidesAreVisible, isNearGuide(point.x) else { return nil }
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard guidesAreVisible else { return }
        let guides = guidePositions
        for x in [guides.left, guides.right] {
            addCursorRect(NSRect(x: x - hitTolerance, y: 0,
                                 width: hitTolerance * 2, height: bounds.height),
                          cursor: .resizeLeftRight)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard guidesAreVisible else { return }

        let guides = guidePositions
        // Le guide restano sospese dentro la pagina, anziché toccarne i bordi.
        // Il margine cresce appena sulle finestre alte, ma resta contenuto per
        // non accorciare troppo le linee su una finestra piccola.
        let verticalMargin = min(52, max(32, bounds.height * 0.055))
        let color = Theme.current.accent.withAlphaComponent(isDraggingGuide ? 0.88 : 0.54)
        color.setStroke()

        for x in [guides.left, guides.right] {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x, y: verticalMargin))
            path.line(to: NSPoint(x: x, y: max(verticalMargin, bounds.height - verticalMargin)))
            path.lineWidth = isDraggingGuide ? 2 : 1.25
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard optionIsHeld else { return }
        isDraggingGuide = true
        previewWidth = preferredWidth
        NSCursor.resizeLeftRight.set()
        updateWidth(from: event)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggingGuide else { return }
        updateWidth(from: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDraggingGuide else { return }
        updateWidth(from: event)
        isDraggingGuide = false
        let width = previewWidth ?? preferredWidth
        previewWidth = nil
        onWidthCommit?(width)
        needsDisplay = true
        invalidateCursorRects()
    }

    private var guidesAreVisible: Bool {
        optionIsHeld || isDraggingGuide
    }

    private var displayedWidth: CGFloat {
        let width = previewWidth ?? preferredWidth
        let room = max(0, availableWidth - minimumSideMargin * 2)
        return min(width, room)
    }

    private var guidePositions: (left: CGFloat, right: CGFloat) {
        let center = availableWidth / 2
        let half = displayedWidth / 2 + guideToTextSpacing
        return (center - half, center + half)
    }

    private func isNearGuide(_ x: CGFloat) -> Bool {
        let guides = guidePositions
        return abs(x - guides.left) <= hitTolerance || abs(x - guides.right) <= hitTolerance
    }

    private func updateWidth(from event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let center = availableWidth / 2
        // La guida vive appena fuori dal testo: sottraiamo lo spazio visivo
        // per salvare la larghezza effettiva della colonna, non quella fra le
        // due guide.
        let candidate = max(0, (abs(point.x - center) - guideToTextSpacing) * 2)
        let range = Settings.contentWidthRange
        let width = min(max(candidate, range.lowerBound), range.upperBound).rounded()
        guard previewWidth != width else { return }
        previewWidth = width
        onWidthPreview?(width)
        needsDisplay = true
        invalidateCursorRects()
    }

    private func invalidateCursorRects() {
        window?.invalidateCursorRects(for: self)
    }
}
