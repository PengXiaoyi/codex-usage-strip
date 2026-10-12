import AppKit
import Foundation

@MainActor
protocol UsageStripViewDelegate: AnyObject {
    func usageViewDidRequestRefresh()
    func usageViewDidRequestContextMenu(event: NSEvent, view: NSView)
    func usageViewDidEndResize()
}

final class UsageStripView: NSView {
    weak var delegate: UsageStripViewDelegate?
    var quota: WeeklyQuota? { didSet { needsDisplay = true } }
    var errorText: String? { didSet { needsDisplay = true } }
    var theme: ThemeDefinition = ThemeStore.shared.builtIns[0] { didSet { needsDisplay = true } }
    var displayMode: DisplayMode = .strip { didSet { needsDisplay = true } }
    var phrases: PhraseSet = .standard { didSet { needsDisplay = true } }
    var criticalThreshold: Double = 10 { didSet { needsDisplay = true } }
    var backgroundImage: NSImage? { didSet { needsDisplay = true } }
    var backgroundImageOpacity: Double = 0.55 { didSet { needsDisplay = true } }
    var backgroundImageMode: BackgroundImageMode = .fill { didSet { needsDisplay = true } }
    var now = Date() { didSet { needsDisplay = true } }
    private var activeResizeCorner: ResizeCorner?
    private var hoveredResizeCorner: ResizeCorner? {
        didSet {
            if oldValue != hoveredResizeCorner { needsDisplay = true }
        }
    }
    private var pointerTrackingArea: NSTrackingArea?
    private var resizeAnchor = NSPoint.zero
    private let resizeMargin: CGFloat = 14

    private static let northwestSoutheastCursor = makeDiagonalResizeCursor(northwestSoutheast: true)
    private static let northeastSouthwestCursor = makeDiagonalResizeCursor(northwestSoutheast: false)

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        window?.disableCursorRects()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        bounds = NSRect(origin: .zero, size: displayMode.size)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let scale = max(frame.width / max(bounds.width, 1), 0.01)
        let margin = resizeMargin / scale
        let size = NSSize(width: margin * 2, height: margin * 2)
        addCursorRect(NSRect(origin: .zero, size: size), cursor: Self.northwestSoutheastCursor)
        addCursorRect(NSRect(x: bounds.maxX - size.width, y: 0, width: size.width, height: size.height), cursor: Self.northeastSouthwestCursor)
        addCursorRect(NSRect(x: 0, y: bounds.maxY - size.height, width: size.width, height: size.height), cursor: Self.northeastSouthwestCursor)
        addCursorRect(NSRect(x: bounds.maxX - size.width, y: bounds.maxY - size.height, width: size.width, height: size.height), cursor: Self.northwestSoutheastCursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        window?.disableCursorRects()
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        updateResizeHover(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        updateResizeHover(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateResizeHover(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredResizeCorner = nil
        NSCursor.arrow.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.current?.imageInterpolation = .high
        drawBackground()

        guard let quota else {
            drawLoadingOrError()
            return
        }

        let state = quota.paceState(now: now, criticalThreshold: criticalThreshold)
        switch displayMode {
        case .pill: drawPill(quota, state: state)
        case .strip: drawStrip(quota, state: state)
        case .card: drawCard(quota, state: state)
        case .minimalNumber: drawMinimalNumber(quota, state: state)
        case .minimalLine: drawMinimalLine(quota, state: state)
        case .minimalCard: drawMinimalCard(quota, state: state)
        case .squareCircular: drawSquareCircular(quota, state: state)
        case .statusBar: drawMinimalLine(quota, state: state)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            delegate?.usageViewDidRequestRefresh()
        } else if let window, let corner = resizeCorner(at: event.locationInWindow, window: window) {
            activeResizeCorner = corner
            hoveredResizeCorner = corner
            resizeCursor(for: corner).set()
            resizeAnchor = ResizeGeometry.oppositeAnchor(for: corner, frame: window.frame)
        } else {
            window?.performDrag(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let corner = activeResizeCorner else { return }
        resizeCursor(for: corner).set()
        let pointer = NSEvent.mouseLocation
        let base = displayMode.size
        let desired = ResizeGeometry.desiredSize(pointer: pointer, anchor: resizeAnchor, corner: corner)
        let projectedScale = (desired.width * base.width + desired.height * base.height)
            / (base.width * base.width + base.height * base.height)
        let minScale = displayMode.minimumSize.width / base.width
        let maxScale = displayMode.maximumSize.width / base.width
        let scale = min(max(projectedScale, minScale), maxScale)
        let size = NSSize(width: base.width * scale, height: base.height * scale)
        window.setFrame(ResizeGeometry.frame(size: size, anchor: resizeAnchor, corner: corner), display: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard activeResizeCorner != nil else { return }
        activeResizeCorner = nil
        updateResizeHover(with: event)
        delegate?.usageViewDidEndResize()
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.usageViewDidRequestContextMenu(event: event, view: self)
    }

    private func drawBackground() {
        let rect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let radius = CGFloat(theme.cornerRadius)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSGradient(
            starting: NSColor(hex: theme.backgroundTop),
            ending: NSColor(hex: theme.backgroundBottom)
        )?.draw(in: rect, angle: 90)

        if let backgroundImage {
            drawBackgroundImage(backgroundImage, in: rect)
            NSColor(hex: theme.backgroundBottom).withAlphaComponent(0.20).setFill()
            rect.fill()
        }

        if theme.id == "paper" {
            NSColor(hex: "6F5D430D").setFill()
            for x in stride(from: 12.0, to: Double(bounds.width), by: 18) {
                NSBezierPath(ovalIn: NSRect(x: x, y: 8 + x.truncatingRemainder(dividingBy: 22), width: 1.2, height: 1.2)).fill()
            }
        } else if theme.id == "terminal" {
            NSColor(hex: "53FF9B0D").setFill()
            for y in stride(from: 3.0, to: Double(bounds.height), by: 4) {
                NSRect(x: 0, y: y, width: Double(bounds.width), height: 1).fill()
            }
        } else if theme.id == "cyber" {
            NSColor(hex: "3FE9FF0F").setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: bounds.width * 0.62, y: 0))
            line.line(to: NSPoint(x: bounds.width * 0.48, y: bounds.height))
            line.lineWidth = 1
            line.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        NSColor(hex: theme.border).setStroke()
        path.lineWidth = theme.id.hasPrefix("system-") ? 0.75 : theme.id == "terminal" ? 1.5 : 1
        path.stroke()
    }

    private func updateResizeHover(with event: NSEvent) {
        guard let window else {
            hoveredResizeCorner = nil
            NSCursor.arrow.set()
            return
        }
        let corner = resizeCorner(at: event.locationInWindow, window: window)
        hoveredResizeCorner = corner
        let cursor = corner.map(resizeCursor(for:)) ?? .arrow
        cursor.set()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.hoveredResizeCorner == corner else { return }
            cursor.set()
        }
    }

    private func resizeCursor(for corner: ResizeCorner) -> NSCursor {
        switch corner {
        case .topLeft, .bottomRight: return Self.northwestSoutheastCursor
        case .topRight, .bottomLeft: return Self.northeastSouthwestCursor
        }
    }

    private static func makeDiagonalResizeCursor(northwestSoutheast: Bool) -> NSCursor {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
            let start = northwestSoutheast ? NSPoint(x: 3, y: 17) : NSPoint(x: 3, y: 3)
            let end = northwestSoutheast ? NSPoint(x: 17, y: 3) : NSPoint(x: 17, y: 17)
            let sign: CGFloat = northwestSoutheast ? -1 : 1

            func drawStroke(color: NSColor, width: CGFloat) {
                color.setStroke()
                let path = NSBezierPath()
                path.move(to: start)
                path.line(to: end)
                path.move(to: start)
                path.line(to: NSPoint(x: start.x, y: start.y + sign * 5))
                path.move(to: start)
                path.line(to: NSPoint(x: start.x + 5, y: start.y))
                path.move(to: end)
                path.line(to: NSPoint(x: end.x, y: end.y - sign * 5))
                path.move(to: end)
                path.line(to: NSPoint(x: end.x - 5, y: end.y))
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.lineWidth = width
                path.stroke()
            }

            drawStroke(color: .white, width: 4)
            drawStroke(color: .black, width: 1.8)
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 10, y: 10))
    }

    private func resizeCorner(at point: NSPoint, window: NSWindow) -> ResizeCorner? {
        let width = window.contentView?.frame.width ?? window.frame.width
        let height = window.contentView?.frame.height ?? window.frame.height
        let left = point.x <= resizeMargin
        let right = point.x >= width - resizeMargin
        let bottom = point.y <= resizeMargin
        let top = point.y >= height - resizeMargin
        if left && top { return .topLeft }
        if right && top { return .topRight }
        if left && bottom { return .bottomLeft }
        if right && bottom { return .bottomRight }
        return nil
    }

    private func drawBackgroundImage(_ image: NSImage, in rect: NSRect) {
        let fraction = CGFloat(min(max(backgroundImageOpacity, 0), 1))
        guard fraction > 0, image.size.width > 0, image.size.height > 0 else { return }

        let draw: (NSRect) -> Void = { target in
            image.draw(
                in: target,
                from: NSRect(origin: .zero, size: image.size),
                operation: .sourceOver,
                fraction: fraction,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        }

        switch backgroundImageMode {
        case .stretch:
            draw(rect)
        case .fill, .fit:
            let widthScale = rect.width / image.size.width
            let heightScale = rect.height / image.size.height
            let scale = backgroundImageMode == .fill ? max(widthScale, heightScale) : min(widthScale, heightScale)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            draw(NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        case .center:
            draw(NSRect(x: rect.midX - image.size.width / 2, y: rect.midY - image.size.height / 2, width: image.size.width, height: image.size.height))
        case .tile:
            let tileWidth = min(max(image.size.width, 48), 256)
            let tileHeight = min(max(image.size.height, 32), 256)
            var y = rect.minY
            while y < rect.maxY {
                var x = rect.minX
                while x < rect.maxX {
                    draw(NSRect(x: x, y: y, width: tileWidth, height: tileHeight))
                    x += tileWidth
                }
                y += tileHeight
            }
        }
    }

    private func drawPill(_ quota: WeeklyQuota, state: PaceState) {
        let percent = quota.remainingPercent
        let systemSpacing = theme.id.hasPrefix("system-")
        let barRect = NSRect(
            x: systemSpacing ? 18 : 16,
            y: systemSpacing ? 21 : 18,
            width: systemSpacing ? 140 : 144,
            height: systemSpacing ? 6 : 12
        )
        drawProgress(in: barRect, percent: percent, state: state)

        drawText(
            "\(Int(percent.rounded()))%",
            rect: NSRect(x: 171, y: 10, width: 54, height: 28),
            size: 18,
            weight: .bold,
            color: NSColor(hex: theme.primaryText),
            numeric: true
        )
        drawText(
            PhraseEngine.countdown(to: quota.resetsAt, now: now),
            rect: NSRect(x: 226, y: 14, width: 50, height: 20),
            size: 10,
            weight: .medium,
            color: NSColor(hex: theme.secondaryText),
            alignment: .right
        )
    }

    private func drawStrip(_ quota: WeeklyQuota, state: PaceState) {
        let percent = quota.remainingPercent
        let systemSpacing = theme.id.hasPrefix("system-")
        let barRect = NSRect(
            x: systemSpacing ? 20 : 18,
            y: systemSpacing ? 21 : 18,
            width: bounds.width - (systemSpacing ? 112 : 104),
            height: systemSpacing ? 6 : 12
        )
        drawProgress(in: barRect, percent: percent, state: state)
        drawText(
            "\(Int(percent.rounded()))%",
            rect: NSRect(x: bounds.width - 76, y: 9, width: 58, height: 30),
            size: 20,
            weight: .bold,
            color: NSColor(hex: theme.primaryText),
            numeric: true,
            alignment: .right
        )

        let phrase = PhraseEngine.phrase(for: quota, state: state, phrases: phrases, now: now)
        drawText(
            phrase,
            rect: NSRect(x: 18, y: 45, width: bounds.width - 132, height: 22),
            size: 12,
            weight: .medium,
            color: NSColor(hex: theme.secondaryText)
        )
        drawText(
            PhraseEngine.countdown(to: quota.resetsAt, now: now),
            rect: NSRect(x: bounds.width - 122, y: 45, width: 104, height: 22),
            size: 11,
            weight: .semibold,
            color: theme.accentColor(for: state),
            numeric: true,
            alignment: .right
        )
    }

    private func drawCard(_ quota: WeeklyQuota, state: PaceState) {
        let percent = quota.remainingPercent
        let systemSpacing = theme.id.hasPrefix("system-")
        drawText(
            "WEEKLY QUOTA",
            rect: NSRect(x: 18, y: 14, width: 160, height: 18),
            size: 10,
            weight: .bold,
            color: NSColor(hex: theme.secondaryText)
        )
        drawText(
            "\(Int(percent.rounded()))%",
            rect: NSRect(x: bounds.width - 92, y: 8, width: 74, height: 34),
            size: 25,
            weight: .bold,
            color: NSColor(hex: theme.primaryText),
            numeric: true,
            alignment: .right
        )

        drawProgress(
            in: NSRect(
                x: systemSpacing ? 20 : 18,
                y: systemSpacing ? 48 : 45,
                width: bounds.width - (systemSpacing ? 40 : 36),
                height: systemSpacing ? 7 : 13
            ),
            percent: percent,
            state: state
        )

        let phrase = PhraseEngine.phrase(for: quota, state: state, phrases: phrases, now: now)
        drawText(
            phrase,
            rect: NSRect(x: 18, y: 70, width: bounds.width - 36, height: 22),
            size: 13,
            weight: .semibold,
            color: NSColor(hex: theme.primaryText)
        )

        let stale = now.timeIntervalSince(quota.updatedAt) > 600
        let footer = "节奏 \(state.title)  ·  \(PhraseEngine.countdown(to: quota.resetsAt, now: now)) 后刷新"
        drawText(
            footer,
            rect: NSRect(x: 18, y: 97, width: 230, height: 18),
            size: 10.5,
            weight: .medium,
            color: NSColor(hex: theme.secondaryText)
        )
        drawText(
            stale ? "数据过期" : "刚刚更新",
            rect: NSRect(x: bounds.width - 88, y: 97, width: 70, height: 18),
            size: 10,
            weight: .medium,
            color: stale ? theme.accentColor(for: .fast) : NSColor(hex: theme.secondaryText),
            alignment: .right
        )
    }

    private func drawMinimalNumber(_ quota: WeeklyQuota, state: PaceState) {
        let percent = quota.remainingPercent
        let dot = NSBezierPath(ovalIn: NSRect(x: 18, y: 19, width: 6, height: 6))
        theme.accentColor(for: state).setFill()
        dot.fill()

        drawText(
            "\(Int(percent.rounded()))%",
            rect: NSRect(x: 36, y: 6, width: 64, height: 30),
            size: 22,
            weight: .bold,
            color: NSColor(hex: theme.primaryText),
            numeric: true
        )
        drawText(
            "本周剩余",
            rect: NSRect(x: 112, y: 7, width: bounds.width - 126, height: 17),
            size: 10.5,
            weight: .medium,
            color: NSColor(hex: theme.secondaryText)
        )
        drawText(
            PhraseEngine.countdown(to: quota.resetsAt, now: now),
            rect: NSRect(x: 112, y: 22, width: bounds.width - 126, height: 16),
            size: 10,
            weight: .medium,
            color: NSColor(hex: theme.secondaryText),
            numeric: true
        )
    }

    private func drawMinimalLine(_ quota: WeeklyQuota, state: PaceState) {
        let percent = quota.remainingPercent
        drawText(
            "\(Int(percent.rounded()))%",
            rect: NSRect(x: 18, y: 5, width: 62, height: 29),
            size: 20,
            weight: .bold,
            color: NSColor(hex: theme.primaryText),
            numeric: true
        )
        drawProgress(
            in: NSRect(x: 96, y: 17, width: bounds.width - 198, height: 5),
            percent: percent,
            state: state
        )
        drawText(
            PhraseEngine.countdown(to: quota.resetsAt, now: now),
            rect: NSRect(x: bounds.width - 86, y: 11, width: 70, height: 18),
            size: 10,
            weight: .medium,
            color: NSColor(hex: theme.secondaryText),
            numeric: true,
            alignment: .right
        )
    }

    private func drawMinimalCard(_ quota: WeeklyQuota, state: PaceState) {
        let percent = quota.remainingPercent
        drawText(
            "本周剩余",
            rect: NSRect(x: 20, y: 11, width: 90, height: 18),
            size: 11,
            weight: .medium,
            color: NSColor(hex: theme.secondaryText)
        )
        drawText(
            "\(Int(percent.rounded()))%",
            rect: NSRect(x: bounds.width - 92, y: 6, width: 72, height: 32),
            size: 23,
            weight: .bold,
            color: NSColor(hex: theme.primaryText),
            numeric: true,
            alignment: .right
        )
        drawProgress(
            in: NSRect(x: 20, y: 42, width: bounds.width - 40, height: 5),
            percent: percent,
            state: state
        )
        drawText(
            "重置于",
            rect: NSRect(x: 20, y: 59, width: 48, height: 17),
            size: 10,
            weight: .medium,
            color: NSColor(hex: theme.secondaryText)
        )
        drawText(
            PhraseEngine.countdown(to: quota.resetsAt, now: now),
            rect: NSRect(x: 70, y: 58, width: bounds.width - 90, height: 18),
            size: 10.5,
            weight: .medium,
            color: NSColor(hex: theme.secondaryText),
            numeric: true
        )
    }

    private func drawSquareCircular(_ quota: WeeklyQuota, state: PaceState) {
        let percent = quota.remainingPercent
        let lineWidth: CGFloat = 7
        let ringSize = min(bounds.width - 36, bounds.height - 34)
        let ringRect = NSRect(
            x: bounds.midX - ringSize / 2,
            y: 14,
            width: ringSize,
            height: ringSize
        ).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let center = NSPoint(x: ringRect.midX, y: ringRect.midY)
        let radius = ringRect.width / 2

        let track = NSBezierPath(ovalIn: ringRect)
        track.lineWidth = lineWidth
        NSColor(hex: theme.track).setStroke()
        track.stroke()

        let progress = CGFloat(min(max(percent, 0), 100) / 100)
        if progress > 0 {
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - 360 * progress,
                clockwise: true
            )
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            theme.accentColor(for: state).setStroke()
            arc.stroke()
        }

        drawText(
            "\(Int(percent.rounded()))%",
            rect: NSRect(x: center.x - 38, y: center.y - 18, width: 76, height: 36),
            size: 28,
            weight: .bold,
            color: NSColor(hex: theme.primaryText),
            numeric: true,
            alignment: .center
        )
        drawText(
            PhraseEngine.countdown(to: quota.resetsAt, now: now),
            rect: NSRect(x: 16, y: bounds.height - 23, width: bounds.width - 32, height: 15),
            size: 9.5,
            weight: .medium,
            color: NSColor(hex: theme.secondaryText),
            numeric: true,
            alignment: .center
        )
    }

    private func drawProgress(in rect: NSRect, percent: Double, state: PaceState) {
        let accent = theme.accentColor(for: state)
        let progress = CGFloat(min(max(percent, 0), 100) / 100)

        switch theme.progressStyle {
        case .rounded:
            let track = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
            NSColor(hex: theme.track).setFill()
            track.fill()
            let width = max(progress > 0 ? rect.height : 0, rect.width * progress)
            let fillRect = NSRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
            let fill = NSBezierPath(roundedRect: fillRect, xRadius: rect.height / 2, yRadius: rect.height / 2)
            accent.setFill()
            fill.fill()

        case .hairline:
            NSColor(hex: theme.track).setFill()
            NSRect(x: rect.minX, y: rect.midY - 1, width: rect.width, height: 2).fill()
            accent.setFill()
            NSRect(x: rect.minX, y: rect.midY - 2, width: rect.width * progress, height: 4).fill()
            let marker = NSBezierPath(ovalIn: NSRect(x: rect.minX + rect.width * progress - 4, y: rect.midY - 4, width: 8, height: 8))
            marker.fill()

        case .segmented:
            let count = 8
            let gap: CGFloat = 3
            let segmentWidth = (rect.width - gap * CGFloat(count - 1)) / CGFloat(count)
            let filled = Int((Double(count) * percent / 100).rounded(.up))
            for index in 0..<count {
                let segment = NSRect(
                    x: rect.minX + CGFloat(index) * (segmentWidth + gap),
                    y: rect.minY,
                    width: segmentWidth,
                    height: rect.height
                )
                let path = NSBezierPath(roundedRect: segment, xRadius: 2, yRadius: 2)
                (index < filled ? accent : NSColor(hex: theme.track)).setFill()
                path.fill()
            }

        case .neon:
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(hex: theme.glow)
            shadow.shadowBlurRadius = 10
            shadow.shadowOffset = .zero
            shadow.set()
            let track = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            NSColor(hex: theme.track).setFill()
            track.fill()
            let fillRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width * progress, height: rect.height)
            let fill = NSBezierPath(roundedRect: fillRect, xRadius: 3, yRadius: 3)
            accent.setFill()
            fill.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawLoadingOrError() {
        let label = errorText ?? "正在读取每周额度…"
        let center = NSRect(x: 18, y: bounds.midY - 13, width: bounds.width - 36, height: 26)
        drawText(
            label,
            rect: center,
            size: 13,
            weight: .medium,
            color: NSColor(hex: theme.secondaryText),
            alignment: .center
        )
    }

    private func drawText(
        _ text: String,
        rect: NSRect,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        numeric: Bool = false,
        alignment: NSTextAlignment = .left
    ) {
        let font: NSFont
        if numeric && theme.usesMonospacedDigits {
            font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        } else if let fontName = theme.fontName, let custom = NSFont(name: fontName, size: size) {
            font = custom
        } else {
            font = NSFont.systemFont(ofSize: size, weight: weight)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        if backgroundImage != nil {
            let shadow = NSShadow()
            shadow.shadowColor = (theme.id == "paper" || theme.id == "sakura")
                ? NSColor.white.withAlphaComponent(0.75)
                : NSColor.black.withAlphaComponent(0.85)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = .zero
            attributes[.shadow] = shadow
        }
        text.draw(in: rect, withAttributes: attributes)
    }
}

enum SkinPreviewExporter {
    static func export(to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        let previewQuota = WeeklyQuota(
            usedPercent: 28,
            resetsAt: now.addingTimeInterval(4 * 86_400 + 8 * 3_600 + 31 * 60),
            windowDurationMins: 10_080,
            updatedAt: now
        )
        var urls: [URL] = []
        for theme in ThemeStore.shared.builtIns {
            let url = directory.appendingPathComponent("\(theme.id).png")
            try render(theme: theme, quota: previewQuota, now: now, to: url)
            urls.append(url)
        }
        return urls
    }

    static func exportCurrent(to url: URL) throws {
        let preferences = AppPreferences.shared
        let now = Date()
        let quota = WeeklyQuota(
            usedPercent: 28,
            resetsAt: now.addingTimeInterval(4 * 86_400 + 8 * 3_600 + 31 * 60),
            windowDurationMins: 10_080,
            updatedAt: now
        )
        try render(
            theme: ThemeStore.shared.theme(id: preferences.themeID),
            quota: quota,
            now: now,
            backgroundImage: BackgroundAssetStore.currentImage(preferences: preferences),
            backgroundOpacity: preferences.backgroundImageOpacity,
            backgroundMode: preferences.backgroundImageMode,
            to: url
        )
    }

    private static func render(
        theme: ThemeDefinition,
        quota: WeeklyQuota,
        now: Date,
        backgroundImage: NSImage? = nil,
        backgroundOpacity: Double = 0.55,
        backgroundMode: BackgroundImageMode = .fill,
        to url: URL
    ) throws {
        let size = DisplayMode.strip.size
        let view = UsageStripView(frame: NSRect(origin: .zero, size: size))
        view.theme = theme
        view.displayMode = .strip
        view.quota = quota
        view.phrases = .standard
        view.criticalThreshold = 10
        view.backgroundImage = backgroundImage
        view.backgroundImageOpacity = backgroundOpacity
        view.backgroundImageMode = backgroundMode
        view.now = now

        let scale: CGFloat = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "CodexUsageStrip.Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建预览画布"])
        }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        view.displayIgnoringOpacity(view.bounds, in: NSGraphicsContext.current!)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "CodexUsageStrip.Preview", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法生成 PNG 预览"])
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
