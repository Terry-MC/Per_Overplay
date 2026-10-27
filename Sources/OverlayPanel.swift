import AppKit

struct VendorCardModel {
    var name: String
    var statusText: String
    var statusColor: NSColor
    var fields: [FieldDisplay]
    var healthText: String
    var errorText: String?
}

struct OverplayModel {
    var title = "API 额度"
    var subtitle = ""
    var notices: [String] = []
    var cards: [VendorCardModel] = []
}

final class OverplayView: NSView {
    var model = OverplayModel() {
        didSet { needsDisplay = true }
    }

    private let outerPadding: CGFloat = 10
    private let headerHeight: CGFloat = 18
    private let headerGap: CGFloat = 6
    private let cardPadding: CGFloat = 9
    private let cardSpacing: CGFloat = 8
    private let noticeSpacing: CGFloat = 4

    private let titleFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
    private let vendorFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
    private let labelFont = NSFont.systemFont(ofSize: 9.5, weight: .regular)
    private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
    private let smallFont = NSFont.systemFont(ofSize: 9.5, weight: .regular)
    private let tinyFont = NSFont.systemFont(ofSize: 9, weight: .regular)

    private let primaryColor = NSColor.white.withAlphaComponent(0.94)
    private let secondaryColor = NSColor.white.withAlphaComponent(0.58)
    private let tertiaryColor = NSColor.white.withAlphaComponent(0.4)
    private let backgroundFill = NSColor(calibratedWhite: 0.06, alpha: 0.86)
    private let cardFill = NSColor.white.withAlphaComponent(0.055)
    private let cardBorder = NSColor.white.withAlphaComponent(0.07)

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func contentHeight(forWidth width: CGFloat) -> CGFloat {
        let cardWidth = max(120, width - outerPadding * 2)
        var height = outerPadding + headerHeight + headerGap
        for notice in model.notices {
            height += noticeHeight(notice, width: cardWidth) + noticeSpacing
        }
        for (index, card) in model.cards.enumerated() {
            height += cardHeight(for: card)
            if index < model.cards.count - 1 {
                height += cardSpacing
            }
        }
        height += outerPadding
        return ceil(max(72, height))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()

        let background = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 12,
            yRadius: 12
        )
        backgroundFill.setFill()
        background.fill()
        NSColor.white.withAlphaComponent(0.08).setStroke()
        background.lineWidth = 1
        background.stroke()

        let cardWidth = bounds.width - outerPadding * 2
        var y = outerPadding

        drawText(
            model.title,
            font: titleFont,
            color: primaryColor,
            rect: NSRect(x: outerPadding + 2, y: y, width: bounds.width / 2, height: headerHeight)
        )
        drawText(
            model.subtitle,
            font: smallFont,
            color: tertiaryColor,
            rect: NSRect(
                x: bounds.width / 2,
                y: y + 1,
                width: bounds.width / 2 - outerPadding - 2,
                height: headerHeight
            ),
            alignment: .right
        )
        y += headerHeight + headerGap

        for notice in model.notices {
            let height = noticeHeight(notice, width: cardWidth)
            let rect = NSRect(x: outerPadding, y: y, width: cardWidth, height: height)
            let box = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
            NSColor.systemOrange.withAlphaComponent(0.12).setFill()
            box.fill()
            NSColor.systemOrange.withAlphaComponent(0.3).setStroke()
            box.lineWidth = 1
            box.stroke()
            drawText(
                notice,
                font: smallFont,
                color: NSColor.systemOrange,
                rect: rect.insetBy(dx: 8, dy: 5),
                lineBreak: .byWordWrapping
            )
            y += height + noticeSpacing
        }

        for (index, card) in model.cards.enumerated() {
            let height = cardHeight(for: card)
            drawCard(card, in: NSRect(x: outerPadding, y: y, width: cardWidth, height: height))
            y += height
            if index < model.cards.count - 1 {
                y += cardSpacing
            }
        }

        context.restoreGraphicsState()
    }

    private func cardHeight(for card: VendorCardModel) -> CGFloat {
        let fieldsHeight: CGFloat
        if card.fields.isEmpty {
            fieldsHeight = 16
        } else {
            let columns = card.fields.count > 1 ? 2 : 1
            let rows = Int(ceil(Double(card.fields.count) / Double(columns)))
            fieldsHeight = CGFloat(rows) * 31
        }
        let errorHeight: CGFloat = card.errorText == nil ? 0 : 12
        return cardPadding * 2 + 15 + 5 + fieldsHeight + 4 + 12 + errorHeight
    }

    private func noticeHeight(_ text: String, width: CGFloat) -> CGFloat {
        let font = smallFont
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: max(40, width - 16), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return ceil(rect.height) + 12
    }

    private func drawCard(_ card: VendorCardModel, in rect: NSRect) {
        let box = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        cardFill.setFill()
        box.fill()
        cardBorder.setStroke()
        box.lineWidth = 1
        box.stroke()

        let contentX = rect.minX + cardPadding
        let contentWidth = rect.width - cardPadding * 2
        let headerY = rect.minY + cardPadding

        let dotRect = NSRect(x: contentX, y: headerY + 5, width: 6, height: 6)
        card.statusColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        drawText(
            card.name,
            font: vendorFont,
            color: primaryColor,
            rect: NSRect(
                x: contentX + 12,
                y: headerY,
                width: max(40, contentWidth - 12 - 110),
                height: 15
            )
        )
        drawText(
            card.statusText,
            font: smallFont,
            color: card.statusColor,
            rect: NSRect(x: rect.maxX - cardPadding - 100, y: headerY + 1, width: 100, height: 12),
            alignment: .right
        )

        let fieldsTop = headerY + 15 + 5
        if card.fields.isEmpty {
            drawText(
                "等待首次查询…",
                font: smallFont,
                color: tertiaryColor,
                rect: NSRect(x: contentX, y: fieldsTop + 1, width: contentWidth, height: 14)
            )
        } else {
            let columns = card.fields.count > 1 ? 2 : 1
            let cellWidth = contentWidth / CGFloat(columns)
            for (index, field) in card.fields.enumerated() {
                let column = index % columns
                let row = index / columns
                let x = contentX + CGFloat(column) * cellWidth
                let y = fieldsTop + CGFloat(row) * 31
                drawText(
                    field.label,
                    font: labelFont,
                    color: secondaryColor,
                    rect: NSRect(x: x, y: y, width: cellWidth - 6, height: 11)
                )
                drawText(
                    field.value,
                    font: valueFont,
                    color: primaryColor,
                    rect: NSRect(x: x, y: y + 11, width: cellWidth - 6, height: 16)
                )
            }
        }

        var bottom = rect.maxY - cardPadding
        if let error = card.errorText {
            bottom -= 12
            drawText(
                error,
                font: tinyFont,
                color: NSColor.systemRed,
                rect: NSRect(x: contentX, y: bottom, width: contentWidth, height: 12)
            )
        }
        if !card.healthText.isEmpty {
            bottom -= 12
            drawText(
                card.healthText,
                font: tinyFont,
                color: tertiaryColor,
                rect: NSRect(x: contentX, y: bottom, width: contentWidth, height: 12)
            )
        }
    }

    private func drawText(
        _ text: String,
        font: NSFont,
        color: NSColor,
        rect: NSRect,
        alignment: NSTextAlignment = .left,
        lineBreak: NSLineBreakMode = .byTruncatingTail
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreak
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }
}

final class OverplayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        title = "DSOverplay"
    }
}
