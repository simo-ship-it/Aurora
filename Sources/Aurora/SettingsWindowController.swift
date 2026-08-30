import AppKit

/// La finestra Impostazioni: font, misura del testo, interlinea, larghezza
/// della colonna e aspetto.
///
/// I cursori mostrano il valore mentre li trascini, ma lo scrivono nelle
/// preferenze solo quando lasci il mouse: ogni scrittura ridisegna tutti i
/// documenti aperti, e farlo a ogni scatto del cursore renderebbe il
/// trascinamento a scatti sui file lunghi.
final class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    private let settings = Settings.shared

    private let fontPopUp = NSPopUpButton()
    private let appearancePopUp = NSPopUpButton()
    private let sizeSlider = NSSlider()
    private let lineHeightSlider = NSSlider()
    private let widthSlider = NSSlider()
    private let sizeValue = NSTextField(labelWithString: "")
    private let lineHeightValue = NSTextField(labelWithString: "")
    private let widthValue = NSTextField(labelWithString: "")

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = localized("Settings")
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("AuroraSettingsWindow")
        super.init(window: window)
        window.contentView = buildContent()
        readFromSettings()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    func show() {
        readFromSettings()          // un altro pannello può aver cambiato i valori
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Costruzione

    private func buildContent() -> NSView {
        fontPopUp.target = self
        fontPopUp.action = #selector(fontChanged)
        fontPopUp.addItem(withTitle: localized("System Font"))
        fontPopUp.menu?.addItem(.separator())
        for family in NSFontManager.shared.availableFontFamilies.sorted() {
            fontPopUp.addItem(withTitle: family)
        }

        appearancePopUp.target = self
        appearancePopUp.action = #selector(appearanceChanged)
        for option in Settings.Appearance.allCases {
            appearancePopUp.addItem(withTitle: option.title)
        }

        configure(sizeSlider, range: Settings.fontSizeRange, action: #selector(sizeChanged))
        configure(lineHeightSlider, range: Settings.lineHeightRange, action: #selector(lineHeightChanged))
        configure(widthSlider, range: Settings.contentWidthRange, action: #selector(widthChanged))

        let reset = NSButton(title: localized("Restore Defaults"), target: self,
                             action: #selector(restoreDefaults))
        reset.bezelStyle = .rounded

        let grid = NSGridView(views: [
            [label(localized("Font:")), fontPopUp],
            [label(localized("Text size:")), row(sizeSlider, sizeValue)],
            [label(localized("Line spacing:")), row(lineHeightSlider, lineHeightValue)],
            [label(localized("Column width:")), row(widthSlider, widthValue)],
            [label(localized("Appearance:")), appearancePopUp],
            [NSGridCell.emptyContentView, reset]
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.columnSpacing = 12
        grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.rowAlignment = .firstBaseline
        grid.row(at: 5).topPadding = 8

        let container = NSView()
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -24)
        ])
        return container
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        return field
    }

    private func configure(_ slider: NSSlider, range: ClosedRange<CGFloat>, action: Selector) {
        slider.minValue = Double(range.lowerBound)
        slider.maxValue = Double(range.upperBound)
        slider.isContinuous = true
        slider.target = self
        slider.action = action
    }

    private func row(_ slider: NSSlider, _ value: NSTextField) -> NSView {
        value.alignment = .right
        value.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        value.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [slider, value])
        stack.orientation = .horizontal
        stack.spacing = 8
        value.setContentHuggingPriority(.required, for: .horizontal)
        value.widthAnchor.constraint(equalToConstant: 48).isActive = true
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        return stack
    }

    // MARK: - Valori

    private func readFromSettings() {
        if let family = settings.fontFamily, fontPopUp.itemTitles.contains(family) {
            fontPopUp.selectItem(withTitle: family)
        } else {
            fontPopUp.selectItem(at: 0)
        }
        appearancePopUp.selectItem(at: Settings.Appearance.allCases.firstIndex(of: settings.appearance) ?? 0)
        sizeSlider.doubleValue = Double(settings.fontSize)
        lineHeightSlider.doubleValue = Double(settings.lineHeight)
        widthSlider.doubleValue = Double(settings.contentWidth)
        updateValueLabels()
    }

    private func updateValueLabels() {
        sizeValue.stringValue = String(format: "%.0f pt", sizeSlider.doubleValue)
        lineHeightValue.stringValue = String(format: "%.2f", lineHeightSlider.doubleValue)
        widthValue.stringValue = String(format: "%.0f pt", widthSlider.doubleValue)
    }

    /// Vero quando il trascinamento è finito: solo allora vale la pena
    /// ricostruire il tema e ridisegnare i documenti.
    private var dragEnded: Bool {
        NSApp.currentEvent?.type != .leftMouseDragged
    }

    // MARK: - Azioni

    @objc private func fontChanged() {
        settings.fontFamily = fontPopUp.indexOfSelectedItem == 0 ? nil : fontPopUp.titleOfSelectedItem
    }

    @objc private func appearanceChanged() {
        let index = min(max(appearancePopUp.indexOfSelectedItem, 0), Settings.Appearance.allCases.count - 1)
        settings.appearance = Settings.Appearance.allCases[index]
    }

    @objc private func sizeChanged() {
        sizeSlider.doubleValue = sizeSlider.doubleValue.rounded()
        updateValueLabels()
        if dragEnded { settings.fontSize = CGFloat(sizeSlider.doubleValue) }
    }

    @objc private func lineHeightChanged() {
        lineHeightSlider.doubleValue = (lineHeightSlider.doubleValue * 20).rounded() / 20
        updateValueLabels()
        if dragEnded { settings.lineHeight = CGFloat(lineHeightSlider.doubleValue) }
    }

    @objc private func widthChanged() {
        widthSlider.doubleValue = (widthSlider.doubleValue / 10).rounded() * 10
        updateValueLabels()
        if dragEnded { settings.contentWidth = CGFloat(widthSlider.doubleValue) }
    }

    @objc private func restoreDefaults() {
        settings.restoreDefaults()
        readFromSettings()
    }
}
