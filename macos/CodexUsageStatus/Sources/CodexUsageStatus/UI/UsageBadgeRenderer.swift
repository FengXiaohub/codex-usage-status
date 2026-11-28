import AppKit

enum UsageBadgeRenderer {
    private static let doubleRingImageSize = NSSize(width: 86, height: 24)
    private static let largeReadoutImageSize = NSSize(width: 86, height: 24)
    private static let quotaAndResetTimesImageHeight: CGFloat = 24
    private static let singleRingImageSize = NSSize(width: 46, height: 24)
    private static let singleReadoutImageSize = NSSize(width: 58, height: 24)
    private static let proQuotaAndResetTimesFontSize: CGFloat = 12.6
    /// High-contrast crimson pill fill (> 5:1 contrast with white text on both light and dark menu bars).
    private static let lowQuotaPillColor = NSColor(srgbRed: 0.85, green: 0.12, blue: 0.15, alpha: 0.96)

    static func image(
        for combined: CombinedUsageSummary,
        style: BadgeStyle,
        visibility: QuotaVisibility = QuotaVisibility(),
        appearance: NSAppearance
    ) -> NSImage {
        let columnImages = combined.columns(for: visibility).map { column -> NSImage in
            if let fiveHour = column.fiveHour, let weekly = column.weekly {
                let summary = UsageSummary(
                    shortLabel: column.shortLabel,
                    title: column.title,
                    planType: nil,
                    fiveHour: fiveHour,
                    weekly: weekly
                )
                return image(for: summary, prefix: column.shortLabel, style: style, appearance: appearance)
            } else if let weekly = column.weekly {
                let summary = UsageSummary(
                    shortLabel: column.shortLabel,
                    title: column.title,
                    planType: nil,
                    fiveHour: nil,
                    weekly: weekly
                )
                return image(for: summary, prefix: column.shortLabel, style: style, appearance: appearance)
            } else {
                let override = column.errorDescription != nil ? "?" : "--"
                let forcedColor: NSColor? = column.errorDescription != nil ? .systemRed : nil
                return renderPrefixedColumn(
                    prefix: column.shortLabel,
                    style: style,
                    left: BadgeValue(label: "5H", percent: nil, overrideText: override),
                    right: BadgeValue(label: "7D", percent: nil, overrideText: override),
                    appearance: appearance,
                    forcedColor: forcedColor
                )
            }
        }
        return combineColumnsHorizontally(columnImages, appearance: appearance)
    }

    static func image(for usage: UsageSummary, prefix: String? = nil, style: BadgeStyle, appearance: NSAppearance) -> NSImage {
        let weekly = BadgeValue(label: usage.weekly.shortLabel, percent: usage.weekly.remainingPercent, resetDate: usage.weekly.resetsAt)
        guard let fiveHour = usage.fiveHour else {
            let base: NSImage
            switch style {
            case .doubleRing:
                base = renderSingleRing(value: weekly, appearance: appearance)
            case .largeReadout:
                base = renderSingleReadout(value: weekly, appearance: appearance)
            case .quotaAndResetTimes:
                base = renderProQuotaAndResetTimes(value: weekly, appearance: appearance)
            }
            if let prefix {
                return prependPrefixLabel(prefix, to: base, appearance: appearance, forcedColor: nil)
            }
            return base
        }

        let left = BadgeValue(label: "5H", percent: fiveHour.remainingPercent, resetDate: fiveHour.resetsAt)
        if let prefix {
            return renderPrefixedColumn(
                prefix: prefix,
                style: style,
                left: left,
                right: weekly,
                appearance: appearance,
                forcedColor: nil
            )
        }
        return render(style: style, left: left, right: weekly, appearance: appearance)
    }

    static func placeholderImage(
        style: BadgeStyle,
        visibility: QuotaVisibility = QuotaVisibility(),
        appearance: NSAppearance
    ) -> NSImage {
        let columns = visibility.visibleProviders.map(\.shortLabel).map { prefix in
            renderPrefixedColumn(
                prefix: prefix,
                style: style,
                left: BadgeValue(label: "5H", percent: nil),
                right: BadgeValue(label: "7D", percent: nil),
                appearance: appearance,
                forcedColor: nil
            )
        }
        return combineColumnsHorizontally(columns, appearance: appearance)
    }

    static func errorImage(
        style: BadgeStyle,
        visibility: QuotaVisibility = QuotaVisibility(),
        appearance: NSAppearance
    ) -> NSImage {
        let columns = visibility.visibleProviders.map(\.shortLabel).map { prefix in
            renderPrefixedColumn(
                prefix: prefix,
                style: style,
                left: BadgeValue(label: "5H", percent: nil, overrideText: "?"),
                right: BadgeValue(label: "7D", percent: nil, overrideText: "?"),
                appearance: appearance,
                forcedColor: .systemRed
            )
        }
        return combineColumnsHorizontally(columns, appearance: appearance)
    }

    private static func makeImage(size: NSSize, appearance: NSAppearance, draw: @escaping () -> Void) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            appearance.performAsCurrentDrawingAppearance(draw)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func renderPrefixedColumn(
        prefix: String,
        style: BadgeStyle,
        left: BadgeValue,
        right: BadgeValue,
        appearance: NSAppearance,
        forcedColor: NSColor?
    ) -> NSImage {
        let contentImage = render(
            style: style,
            left: left,
            right: right,
            appearance: appearance,
            forcedColor: forcedColor
        )
        return prependPrefixLabel(prefix, to: contentImage, appearance: appearance, forcedColor: forcedColor)
    }

    private static func prependPrefixLabel(
        _ prefix: String,
        to contentImage: NSImage,
        appearance: NSAppearance,
        forcedColor: NSColor?
    ) -> NSImage {
        let prefixWidth: CGFloat = 11
        let prefixGap: CGFloat = 2
        let totalSize = NSSize(
            width: prefixWidth + prefixGap + contentImage.size.width,
            height: contentImage.size.height
        )
        return makeImage(size: totalSize, appearance: appearance) {
            drawString(
                prefix,
                in: NSRect(x: 0, y: 4.5, width: prefixWidth, height: 15),
                fontSize: 11.5,
                weight: .heavy,
                alpha: 0.85,
                alignment: .center,
                color: forcedColor
            )
            contentImage.draw(
                in: NSRect(
                    x: prefixWidth + prefixGap,
                    y: 0,
                    width: contentImage.size.width,
                    height: contentImage.size.height
                )
            )
        }
    }

    private static func combineColumnsHorizontally(_ columns: [NSImage], appearance: NSAppearance) -> NSImage {
        guard !columns.isEmpty else {
            return NSImage(size: NSSize(width: 1, height: quotaAndResetTimesImageHeight))
        }

        let gap: CGFloat = 10
        let totalWidth = columns.reduce(CGFloat(0)) { $0 + $1.size.width } + gap * CGFloat(max(0, columns.count - 1))
        let maxHeight = columns.map(\.size.height).max() ?? quotaAndResetTimesImageHeight
        let imageSize = NSSize(width: ceil(totalWidth), height: maxHeight)
        return makeImage(size: imageSize, appearance: appearance) {
            var currentX: CGFloat = 0
            for (index, columnImage) in columns.enumerated() {
                columnImage.draw(
                    in: NSRect(
                        x: currentX,
                        y: (maxHeight - columnImage.size.height) / 2,
                        width: columnImage.size.width,
                        height: columnImage.size.height
                    )
                )
                currentX += columnImage.size.width
                if index < columns.count - 1 {
                    let dividerX = currentX + gap / 2
                    let divider = NSBezierPath()
                    divider.move(to: NSPoint(x: dividerX, y: 4))
                    divider.line(to: NSPoint(x: dividerX, y: maxHeight - 4))
                    divider.lineWidth = 1.0
                    NSColor.labelColor.withAlphaComponent(0.18).setStroke()
                    divider.stroke()
                    currentX += gap
                }
            }
        }
    }

    private static func render(
        style: BadgeStyle,
        left: BadgeValue,
        right: BadgeValue,
        appearance: NSAppearance,
        forcedColor: NSColor? = nil
    ) -> NSImage {
        switch style {
        case .doubleRing:
            return renderDoubleRing(left: left, right: right, appearance: appearance, forcedColor: forcedColor)
        case .largeReadout:
            return renderLargeReadout(left: left, right: right, appearance: appearance, forcedColor: forcedColor)
        case .quotaAndResetTimes:
            return renderQuotaAndResetTimes(left: left, right: right, appearance: appearance, forcedColor: forcedColor)
        }
    }

    private static func renderQuotaAndResetTimes(
        left: BadgeValue,
        right: BadgeValue,
        appearance: NSAppearance,
        forcedColor: NSColor?
    ) -> NSImage {
        let leftPercent = left.percent.map { "\($0)%" } ?? left.centerText
        let rightPercent = right.percent.map { "\($0)%" } ?? right.centerText
        let fiveHourText = "\(leftPercent)·\(ResetFormatter.shared.text(for: left.resetDate, includeWeekday: false))"
        let weeklyText = "\(rightPercent)·\(ResetFormatter.shared.text(for: right.resetDate, includeWeekday: true))"

        let leftIsAlert = forcedColor == nil && isLowQuota(left.percent)
        let rightIsAlert = forcedColor == nil && isLowQuota(right.percent)
        let pillPadX: CGFloat = 3.5

        let leftWidth = rowWidth(for: fiveHourText, fontSize: leftIsAlert ? 9.8 : 10.2, weight: leftIsAlert ? .bold : .semibold, padX: leftIsAlert ? pillPadX : 0)
        let rightWidth = rowWidth(for: weeklyText, fontSize: rightIsAlert ? 9.8 : 10.2, weight: rightIsAlert ? .bold : .semibold, padX: rightIsAlert ? pillPadX : 0)
        let imageSize = NSSize(width: max(leftWidth, rightWidth), height: quotaAndResetTimesImageHeight)

        return makeImage(size: imageSize, appearance: appearance) {
            if leftIsAlert {
                drawAlertPillRow(fiveHourText, y: 12.5, height: 10.8, fontSize: 9.8, padX: pillPadX, cornerRadius: 3.2)
            } else {
                drawString(
                    fiveHourText,
                    in: NSRect(x: 0, y: 12, width: imageSize.width, height: 11),
                    fontSize: 10.2,
                    weight: .semibold,
                    alpha: 0.98,
                    alignment: .left,
                    color: forcedColor
                )
            }

            if rightIsAlert {
                drawAlertPillRow(weeklyText, y: 0.8, height: 10.8, fontSize: 9.8, padX: pillPadX, cornerRadius: 3.2)
            } else {
                drawString(
                    weeklyText,
                    in: NSRect(x: 0, y: 1, width: imageSize.width, height: 11),
                    fontSize: 10.2,
                    weight: .semibold,
                    alpha: 0.98,
                    alignment: .left,
                    color: forcedColor
                )
            }
        }
    }

    private static func renderProQuotaAndResetTimes(value: BadgeValue, appearance: NSAppearance) -> NSImage {
        let percent = value.percent.map { "\($0)%" } ?? value.centerText
        let text = "\(percent)·\(ResetFormatter.shared.text(for: value.resetDate, includeWeekday: true))"
        let isAlert = isLowQuota(value.percent)
        let pillPadX: CGFloat = 4.5
        let fontSize: CGFloat = isAlert ? 12.0 : proQuotaAndResetTimesFontSize
        let width = rowWidth(for: text, fontSize: fontSize, weight: isAlert ? .bold : .semibold, padX: isAlert ? pillPadX : 0)
        let imageSize = NSSize(width: width, height: quotaAndResetTimesImageHeight)

        return makeImage(size: imageSize, appearance: appearance) {
            if isAlert {
                drawAlertPillRow(text, y: 4.2, height: 15.6, fontSize: fontSize, padX: pillPadX, cornerRadius: 4.2)
            } else {
                drawString(
                    text,
                    in: NSRect(x: 0, y: 4, width: imageSize.width, height: 16),
                    fontSize: fontSize,
                    weight: .semibold,
                    alpha: 0.98,
                    alignment: .left
                )
            }
        }
    }

    private static func rowWidth(for text: String, fontSize: CGFloat, weight: NSFont.Weight, padX: CGFloat) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        return ceil(textWidth + padX * 2 + 1)
    }

    private static func drawAlertPillRow(
        _ text: String,
        y: CGFloat,
        height: CGFloat,
        fontSize: CGFloat,
        padX: CGFloat,
        cornerRadius: CGFloat
    ) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let pillRect = NSRect(x: 0, y: y, width: ceil(textSize.width + padX * 2), height: height)
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: cornerRadius, yRadius: cornerRadius)
        lowQuotaPillColor.setFill()
        pillPath.fill()

        let textOrigin = NSPoint(
            x: pillRect.minX + (pillRect.width - textSize.width) / 2,
            y: pillRect.midY - textSize.height / 2
        )
        (text as NSString).draw(at: textOrigin, withAttributes: attributes)
    }

    private static func renderSingleRing(value: BadgeValue, appearance: NSAppearance) -> NSImage {
        makeImage(size: singleRingImageSize, appearance: appearance) {
            drawLabeledRing(
                value: value,
                labelRect: NSRect(x: 1, y: 4.0, width: 11, height: 16),
                ringCenter: NSPoint(x: 32, y: 12),
                forcedColor: nil
            )
        }
    }

    private static func renderSingleReadout(value: BadgeValue, appearance: NSAppearance) -> NSImage {
        makeImage(size: singleReadoutImageSize, appearance: appearance) {
            drawReadoutGroup(
                value: value,
                labelRect: NSRect(x: 1, y: 4.0, width: 11, height: 16),
                numberRect: NSRect(x: 15, y: 2.2, width: 42, height: 19),
                lineRect: NSRect(x: 1, y: 2.4, width: 56, height: 1.5),
                forcedColor: nil,
                numberFontSize: 15
            )
        }
    }

    private static func renderDoubleRing(
        left: BadgeValue,
        right: BadgeValue,
        appearance: NSAppearance,
        forcedColor: NSColor?
    ) -> NSImage {
        makeImage(size: doubleRingImageSize, appearance: appearance) {
            let divider = NSBezierPath()
            divider.appendArc(withCenter: NSPoint(x: 43, y: 12), radius: 1.0, startAngle: 0, endAngle: 360)
            NSColor.labelColor.withAlphaComponent(0.22).setFill()
            divider.fill()

            drawLabeledRing(value: left, labelRect: NSRect(x: 1, y: 4.0, width: 11, height: 16), ringCenter: NSPoint(x: 29, y: 12), forcedColor: forcedColor)
            drawLabeledRing(value: right, labelRect: NSRect(x: 50, y: 4.0, width: 11, height: 16), ringCenter: NSPoint(x: 75, y: 12), forcedColor: forcedColor)
        }
    }

    private static func renderLargeReadout(
        left: BadgeValue,
        right: BadgeValue,
        appearance: NSAppearance,
        forcedColor: NSColor?
    ) -> NSImage {
        makeImage(size: largeReadoutImageSize, appearance: appearance) {
            let divider = NSBezierPath()
            divider.appendArc(withCenter: NSPoint(x: 43, y: 12), radius: 1.0, startAngle: 0, endAngle: 360)
            NSColor.labelColor.withAlphaComponent(0.28).setFill()
            divider.fill()

            drawReadoutGroup(value: left, labelRect: NSRect(x: 1, y: 4.0, width: 11, height: 16), numberRect: NSRect(x: 15, y: 3.4, width: 25, height: 17), lineRect: NSRect(x: 1, y: 2.4, width: 36, height: 1.5), forcedColor: forcedColor)
            drawReadoutGroup(value: right, labelRect: NSRect(x: 49, y: 4.0, width: 11, height: 16), numberRect: NSRect(x: 61, y: 3.4, width: 25, height: 17), lineRect: NSRect(x: 48, y: 2.4, width: 36, height: 1.5), forcedColor: forcedColor)
        }
    }

    private static func drawLabeledRing(
        value: BadgeValue,
        labelRect: NSRect,
        ringCenter: NSPoint,
        forcedColor: NSColor?
    ) {
        drawSideLabel(value.label, in: labelRect)
        drawRing(value: value, center: ringCenter, forcedColor: forcedColor)
    }

    private static func drawRing(value: BadgeValue, center: NSPoint, forcedColor: NSColor?) {
        let radius: CGFloat = 9.7
        let lineWidth: CGFloat = 2.25
        let isAlert = forcedColor == nil && isLowQuota(value.percent)

        if isAlert {
            let innerRadius = radius - lineWidth / 2 - 0.4
            let disc = NSBezierPath()
            disc.appendArc(withCenter: center, radius: innerRadius, startAngle: 0, endAngle: 360)
            lowQuotaPillColor.setFill()
            disc.fill()
        }

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        track.lineCapStyle = .round
        NSColor.labelColor.withAlphaComponent(0.20).setStroke()
        track.stroke()

        if let percent = value.percent {
            let progress = max(0, min(100, percent))
            let ring = NSBezierPath()
            ring.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - CGFloat(progress) * 3.6,
                clockwise: true
            )
            ring.lineWidth = lineWidth
            ring.lineCapStyle = .round
            (forcedColor ?? color(for: progress)).withAlphaComponent(0.92).setStroke()
            ring.stroke()
        }

        drawText(
            value.centerText,
            center: center,
            yOffset: -5.5,
            fontSize: value.centerText.count >= 3 ? 7.4 : 9.0,
            weight: .bold,
            alpha: isAlert ? 1.0 : 0.98,
            color: isAlert ? .white : forcedColor
        )
    }

    private static func drawReadoutGroup(
        value: BadgeValue,
        labelRect: NSRect,
        numberRect: NSRect,
        lineRect: NSRect,
        forcedColor: NSColor?,
        numberFontSize: CGFloat? = nil
    ) {
        let percent = value.percent.map { max(0, min(100, $0)) }
        let isAlert = forcedColor == nil && isLowQuota(percent)
        let accent = forcedColor ?? percent.map(color(for:)) ?? NSColor.labelColor.withAlphaComponent(0.26)

        drawStackedLabel(value.label, in: labelRect, alpha: 0.62)
        let fontSize = numberFontSize ?? (value.centerText.count >= 3 ? 11.6 : 13.2)

        if isAlert {
            let pillRect = NSRect(x: numberRect.minX - 2, y: numberRect.minY + 1.4, width: numberRect.width + 2, height: numberRect.height - 2.2)
            let pill = NSBezierPath(roundedRect: pillRect, xRadius: 3.4, yRadius: 3.4)
            lowQuotaPillColor.setFill()
            pill.fill()
            drawString(value.centerText, in: pillRect, fontSize: fontSize - 0.8, weight: .bold, alpha: 1.0, alignment: .center, color: .white)
        } else {
            drawString(value.centerText, in: numberRect, fontSize: fontSize, weight: .bold, alpha: 0.96, alignment: .left, color: forcedColor)
        }

        let track = NSBezierPath(roundedRect: lineRect, xRadius: 0.7, yRadius: 0.7)
        NSColor.labelColor.withAlphaComponent(0.14).setFill()
        track.fill()

        if let percent {
            let fillWidth = max(1.2, lineRect.width * CGFloat(percent) / 100)
            let fillRect = NSRect(x: lineRect.minX, y: lineRect.minY, width: fillWidth, height: lineRect.height)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 0.7, yRadius: 0.7)
            accent.withAlphaComponent(isAlert ? 0.95 : 0.72).setFill()
            fillPath.fill()
        }
    }

    private static func drawText(
        _ text: String,
        center: NSPoint,
        yOffset: CGFloat,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        alpha: CGFloat,
        color: NSColor? = nil
    ) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: (color ?? NSColor.labelColor).withAlphaComponent(alpha),
            .paragraphStyle: centeredParagraphStyle,
        ]
        let height = fontSize + 2
        let rect = NSRect(x: center.x - 10, y: center.y + yOffset, width: 20, height: height)
        text.draw(in: rect, withAttributes: attributes)
    }

    private static func drawSideLabel(_ text: String, in rect: NSRect) {
        drawStackedLabel(text, in: rect, alpha: 0.78)
    }

    private static func drawStackedLabel(_ text: String, in rect: NSRect, alpha: CGFloat) {
        let lines: [String]
        let normalized = text.uppercased()
        if normalized.count == 2 {
            lines = normalized.map(String.init)
        } else if let unitIndex = normalized.firstIndex(where: { !$0.isNumber }),
                  unitIndex != normalized.startIndex,
                  normalized[unitIndex...].count == 1 {
            lines = [String(normalized[..<unitIndex]), String(normalized[unitIndex...])]
        } else {
            lines = [normalized]
        }

        let fontSize: CGFloat = lines.count > 1 ? 7.4 : 10.0
        let lineHeight: CGFloat = lines.count > 1 ? 7.5 : 10.8
        let totalHeight = CGFloat(lines.count) * lineHeight
        let startY = rect.midY + totalHeight / 2 - lineHeight

        for (index, line) in lines.enumerated() {
            let lineRect = NSRect(
                x: rect.minX,
                y: startY - CGFloat(index) * lineHeight,
                width: rect.width,
                height: lineHeight
            )
            drawString(line, in: lineRect, fontSize: fontSize, weight: .bold, alpha: alpha, alignment: .center)
        }
    }

    private static func drawString(
        _ text: String,
        in rect: NSRect,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        alpha: CGFloat,
        alignment: NSTextAlignment,
        color: NSColor? = nil
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: (color ?? NSColor.labelColor).withAlphaComponent(alpha),
            .paragraphStyle: style,
        ]
        text.draw(in: rect, withAttributes: attributes)
    }

    private static var centeredParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byClipping
        return style
    }

    private static func isLowQuota(_ percent: Int?) -> Bool {
        guard let percent else { return false }
        return percent < AppConfig.lowQuotaRedThresholdPercent
    }

    private static func color(for percent: Int) -> NSColor {
        switch percent {
        case 50...100:
            return .systemGreen
        case AppConfig.lowQuotaRedThresholdPercent..<50:
            return .systemOrange
        default:
            return .systemRed
        }
    }
}

private final class ResetFormatter: @unchecked Sendable {
    static let shared = ResetFormatter()

    private let lock = NSLock()
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    private let zhWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter
    }()
    private let enWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter
    }()
    private let zhDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
    private let enDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    func text(for date: Date?, includeWeekday: Bool) -> String {
        guard let date else {
            return "--"
        }
        lock.lock()
        defer { lock.unlock() }

        timeFormatter.locale = Locale.current
        let time = timeFormatter.string(from: date)
        let usesChinese = Locale.current.language.languageCode?.identifier == "zh"

        if includeWeekday {
            if let sixDaysOut = Calendar.current.date(byAdding: .day, value: 6, to: Date()), date > sixDaysOut {
                return (usesChinese ? zhDateFormatter : enDateFormatter).string(from: date)
            }
            let weekday = (usesChinese ? zhWeekdayFormatter : enWeekdayFormatter).string(from: date)
            return "\(weekday)\(time)"
        }

        if Calendar.current.isDateInTomorrow(date) {
            return usesChinese ? "明天\(time)" : "Tomorrow \(time)"
        }
        return time
    }
}

struct BadgeValue {
    let label: String
    let percent: Int?
    let overrideText: String?
    let resetDate: Date?

    init(label: String, percent: Int?, overrideText: String? = nil, resetDate: Date? = nil) {
        self.label = label
        self.percent = percent
        self.overrideText = overrideText
        self.resetDate = resetDate
    }

    var centerText: String {
        if let overrideText {
            return overrideText
        }
        guard let percent else {
            return "--"
        }
        return "\(percent)"
    }
}
