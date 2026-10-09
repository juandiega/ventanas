import AppKit

/// Floating panel (doesn't activate the app) with the window list.
final class SwitcherPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate {
    var onPick: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onQuit: ((Int) -> Void)?
    /// Help line shown at the bottom of the panel.
    var hint = "" {
        didSet { helpLabel.stringValue = hint }
    }

    private var items: [WindowItem] = []
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let queryLabel = NSTextField(labelWithString: "")
    private let helpLabel = NSTextField(labelWithString: "")

    private let panelWidth: CGFloat = 640
    private let rowHeight: CGFloat = 44
    private let maxVisibleRows = 12
    private let chromeHeight: CGFloat = 76  // search label + help line + margins

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        contentView = background

        queryLabel.font = .systemFont(ofSize: 15, weight: .medium)
        queryLabel.lineBreakMode = .byTruncatingTail
        queryLabel.translatesAutoresizingMaskIntoConstraints = false

        helpLabel.font = .systemFont(ofSize: 11)
        helpLabel.textColor = .tertiaryLabelColor
        helpLabel.lineBreakMode = .byTruncatingTail
        helpLabel.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: .init("window"))
        column.width = panelWidth - 12
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = rowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.style = .plain
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)

        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        background.addSubview(queryLabel)
        background.addSubview(scroll)
        background.addSubview(helpLabel)
        NSLayoutConstraint.activate([
            queryLabel.topAnchor.constraint(equalTo: background.topAnchor, constant: 14),
            queryLabel.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            queryLabel.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -18),
            scroll.topAnchor.constraint(equalTo: queryLabel.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -6),
            scroll.bottomAnchor.constraint(equalTo: helpLabel.topAnchor, constant: -6),
            helpLabel.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            helpLabel.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -18),
            helpLabel.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -10),
        ])
    }

    // Must never steal focus: keys are captured by the event tap.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(items: [WindowItem], query: String, selection: Int) {
        self.items = items
        if query.isEmpty {
            queryLabel.stringValue = "Type to search…"
            queryLabel.textColor = .tertiaryLabelColor
        } else {
            queryLabel.stringValue = items.isEmpty ? "\(query) — no results" : query
            queryLabel.textColor = .labelColor
        }
        table.reloadData()
        layoutOnScreen()
        select(selection)
        orderFrontRegardless()
    }

    func select(_ index: Int) {
        guard items.indices.contains(index) else {
            table.deselectAll(nil)
            return
        }
        table.selectRowIndexes([index], byExtendingSelection: false)
        table.scrollRowToVisible(index)
    }

    private func layoutOnScreen() {
        let rows = CGFloat(max(1, min(items.count, maxVisibleRows)))
        let height = rows * rowHeight + chromeHeight
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let origin = NSPoint(x: frame.midX - panelWidth / 2, y: frame.midY - height / 2 + frame.height * 0.08)
        setFrame(NSRect(origin: origin, size: NSSize(width: panelWidth, height: height)), display: true)
    }

    @objc private func rowClicked() {
        if table.clickedRow >= 0 { onPick?(table.clickedRow) }
    }

    /// Runs a row button's callback with the row the button's cell is in right now.
    private func perform(_ cell: WindowCell?, _ callback: ((Int) -> Void)?) {
        guard let cell else { return }
        let row = table.row(for: cell)
        if row >= 0 { callback?(row) }
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: WindowCell.identifier, owner: nil) as? WindowCell ?? WindowCell()
        cell.configure(items[row])
        cell.onClose = { [weak self, weak cell] in self?.perform(cell, self?.onClose) }
        cell.onQuit = { [weak self, weak cell] in self?.perform(cell, self?.onQuit) }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SelectionRowView()
    }
}

private final class SelectionRowView: NSTableRowView {
    private var isHovered = false { didSet { refreshActions() } }
    private var tracking: NSTrackingArea?

    override var isSelected: Bool {
        didSet { refreshActions() }
    }

    /// The row's buttons show on the selected row and on the one under the mouse.
    private func refreshActions() {
        (subviews.first { $0 is WindowCell } as? WindowCell)?.actionsVisible = isSelected || isHovered
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        refreshActions()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill()
    }
}

private final class WindowCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("WindowCell")

    var onClose: (() -> Void)?
    var onQuit: (() -> Void)?
    var actionsVisible = false { didSet { updateButtons() } }

    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let quitButton = NSButton()
    private var canClose = true
    private var canQuit = true

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier

        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail

        configure(closeButton, symbol: "xmark.circle.fill", label: "Close window", action: #selector(closeClicked))
        configure(quitButton, symbol: "power.circle.fill", label: "Quit app", action: #selector(quitClicked))

        for view in [icon, title, detail, closeButton, quitButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
            // The space for the buttons is always reserved, so the text doesn't jump when they show.
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -72),
            title.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            detail.topAnchor.constraint(equalTo: centerYAnchor, constant: 2),
            quitButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            closeButton.trailingAnchor.constraint(equalTo: quitButton.leadingAnchor, constant: -6),
        ])
        for button in [closeButton, quitButton] {
            NSLayoutConstraint.activate([
                button.centerYAnchor.constraint(equalTo: centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 22),
                button.heightAnchor.constraint(equalToConstant: 22),
            ])
        }
        updateButtons()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func configure(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = label
        button.target = self
        button.action = action
    }

    @objc private func closeClicked() { onClose?() }
    @objc private func quitClicked() { onQuit?() }

    private func updateButtons() {
        closeButton.isHidden = !(actionsVisible && canClose)
        quitButton.isHidden = !(actionsVisible && canQuit)
    }

    func configure(_ item: WindowItem) {
        icon.image = item.app.icon
        title.stringValue = item.displayTitle
        detail.stringValue = item.detail
        alphaValue = item.isMinimized || item.app.isHidden || item.element == nil ? 0.6 : 1
        canClose = item.hasWindow
        canQuit = item.canQuit
        updateButtons()
    }
}
