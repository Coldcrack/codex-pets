import Foundation
import SwiftUI

struct ResetCreditsDisplay: Equatable {
    let availableCount: Int
    let expiryDates: [Date]

    init?(resetCredits: RateLimitResetCredits?) {
        guard let resetCredits else {
            return nil
        }
        let normalizedCount = max(0, resetCredits.availableCount)
        availableCount = normalizedCount
        expiryDates = Array(
            resetCredits.credits
                .map(\.expiresAt)
                .sorted()
                .prefix(normalizedCount)
        )
    }

    var countText: String {
        "剩余重置次数：\(availableCount)"
    }

    var showsInfoButton: Bool {
        availableCount > 0 && !expiryDates.isEmpty
    }

    func expiryRows(timeZone: TimeZone = .current) -> [ResetCreditExpiryRow] {
        expiryDates.enumerated().map { index, expiryDate in
            ResetCreditExpiryRow(
                ordinalText: "第 \(index + 1) 次",
                expiryText: RateLimitResetCreditsFormatter.expiryText(
                    expiryDate,
                    timeZone: timeZone
                )
            )
        }
    }
}

enum ResetCreditsPlacement {
    static func showsInLocalQuotaRow(label: String) -> Bool {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "7d"
    }
}

enum ResetCreditsLayout {
    static let infoHitTarget: CGFloat = 20
    static let inlineLayoutHeight: CGFloat = 20
}

struct ResetCreditExpiryRow: Equatable {
    let ordinalText: String
    let expiryText: String
}

struct ResetCreditsIndicator: View {
    let resetCredits: RateLimitResetCredits?
    var fontSize: CGFloat = 8.4
    var foregroundColor: Color = .white.opacity(0.58)

    @State private var isPopoverPresented = false

    private var display: ResetCreditsDisplay? {
        ResetCreditsDisplay(resetCredits: resetCredits)
    }

    var body: some View {
        if let display {
            HStack(spacing: 2) {
                Text(display.countText)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(foregroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .layoutPriority(1)

                if display.showsInfoButton {
                    Button {
                        isPopoverPresented.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 10, height: 10)
                            .frame(width: ResetCreditsLayout.infoHitTarget, height: ResetCreditsLayout.infoHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(foregroundColor)
                    .help("查看重置次数到期时间")
                    .accessibilityLabel("查看重置次数到期时间")
                    .accessibilityHint("显示每次可用重置次数的到期时间")
                    .accessibilityValue("共 \(display.expiryDates.count) 条到期时间")
                    .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
                        ResetCreditsExpiryPopover(display: display)
                    }
                }
            }
            .lineLimit(1)
            .frame(height: ResetCreditsLayout.inlineLayoutHeight)
        }
    }
}

private struct ResetCreditsExpiryPopover: View {
    let display: ResetCreditsDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("重置次数到期时间")
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(display.expiryRows().enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 12) {
                        Text(row.ordinalText)
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .leading)

                        Text(row.expiryText)
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    .font(.system(size: 12, weight: .medium))
                }
            }
        }
        .padding(14)
        .frame(minWidth: 226, alignment: .leading)
    }
}
