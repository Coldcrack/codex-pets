import AppKit
import SwiftUI

private struct BubbleMetric: Identifiable {
    let id: String
    let label: String
    let value: String
    let color: Color
}

struct PetDashboardView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var overlayState: OverlayState
    @ObservedObject var settings: CodexPetsSettings
    let onToggleDetail: () -> Void
    let onSettings: () -> Void
    let onHidePet: () -> Void
    let onPetDragChanged: () -> Void
    let onPetDragEnded: () -> Void
    @State private var isHovering = false
    @State private var isPressed = false
    @State private var bubbleVisible = false

    private var snapshot: UsageSnapshot { viewModel.snapshot }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            statusBubble
                .frame(width: PetMetrics.width, height: 161)
                .offset(y: -65)
            petImage
                .frame(width: 140, height: 140)
                .shadow(color: Color(red: 0.10, green: 0.16, blue: 0.38).opacity(0.25), radius: 8, y: 5)
        }
        .frame(width: PetMetrics.width, height: PetMetrics.height, alignment: .bottomTrailing)
        .contentShape(Rectangle())
        .scaleEffect(isPressed ? 0.965 : 1, anchor: .bottomTrailing)
        .animation(.spring(response: 0.22, dampingFraction: 0.62), value: isPressed)
        .onTapGesture {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { onToggleDetail() }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in
                    isPressed = true
                    onPetDragChanged()
                }
                .onEnded { _ in
                    isPressed = false
                    onPetDragEnded()
                }
        )
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("设置", action: onSettings)
            Button("刷新") { viewModel.refreshAll() }
            Button("隐藏宠物", action: onHidePet)
            Divider()
            Button("退出 codex-pet") { NSApp.terminate(nil) }
        }
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.72).delay(0.24)) {
                bubbleVisible = true
            }
        }
    }

    private var statusBubble: some View {
        ZStack(alignment: .topLeading) {
            WhaleThoughtBubbleShape()
                .fill(Color(red: 0.96, green: 0.97, blue: 1.0).opacity(0.97))
                .overlay {
                    WhaleThoughtBubbleShape()
                        .stroke(Color(red: 0.13, green: 0.19, blue: 0.44).opacity(0.78),
                                style: StrokeStyle(lineWidth: 4, lineJoin: .round))
                }
                .shadow(color: Color(red: 0.10, green: 0.16, blue: 0.38).opacity(0.22), radius: 13, y: 6)
            ThoughtBubbleDots(isVisible: bubbleVisible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bubbleContent
                .frame(width: 136)
                .position(x: 104, y: 62)
                .opacity(bubbleVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.16).delay(0.36), value: bubbleVisible)
        }
        .scaleEffect(bubbleVisible ? 1 : 0.70, anchor: .bottomTrailing)
        .opacity(bubbleVisible ? 1 : 0)
        .opacity(isHovering || overlayState.isExpanded || snapshot.isRunning ? 1 : 0.93)
    }

    private var bubbleContent: some View {
        VStack(spacing: 2) {
            Text("Codex 额度")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.33, green: 0.42, blue: 0.66))
            HStack(spacing: 8) {
                ForEach(Array(metrics.prefix(2))) { metric in
                    VStack(spacing: 0) {
                        Text(metric.value)
                            .font(.system(size: metrics.count > 1 ? 18 : 25, weight: .black, design: .rounded))
                            .foregroundStyle(metric.color)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                        if metrics.count > 1 {
                            Text(metric.label)
                                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.48, green: 0.56, blue: 0.74))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                if metrics.isEmpty {
                    Text("--")
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.33, green: 0.42, blue: 0.66))
                }
            }
            Text(snapshot.isRunning ? "正在认真干活…" : "摸鱼待命中…")
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.61, green: 0.68, blue: 0.82))
                .lineLimit(1)
        }
    }

    private var metrics: [BubbleMetric] {
        snapshot.displayRateLimitWindows.map { window in
            BubbleMetric(
                id: window.id,
                label: window.shortLabel,
                value: Formatters.percent(window.remainingPercent),
                color: window.shortLabel == "5h"
                    ? Color(red: 0.22, green: 0.63, blue: 0.38)
                    : Color(red: 0.24, green: 0.48, blue: 0.82)
            )
        }
    }

    private var petImage: some View {
        Group {
            if let image = settings.selectedPetSkinImage ?? PetArtwork.defaultImage {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "whale.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(Color(red: 0.30, green: 0.42, blue: 0.70))
                    .padding(24)
            }
        }
        .scaledToFit()
    }
}

enum PetArtwork {
    static var defaultImage: NSImage? {
        if let bundledURL = Bundle.main.url(forResource: "CodexPet", withExtension: "png"),
           let image = NSImage(contentsOf: bundledURL) {
            return image
        }
        let developmentURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/CodexPet.png")
        return NSImage(contentsOf: developmentURL)
    }
}

private struct WhaleThoughtBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()
        path.move(to: CGPoint(x: width * 0.12, y: height * 0.16))
        path.addCurve(to: CGPoint(x: width * 0.44, y: height * 0.04),
                      control1: CGPoint(x: width * 0.20, y: height * 0.04),
                      control2: CGPoint(x: width * 0.34, y: height * 0.02))
        path.addCurve(to: CGPoint(x: width * 0.80, y: height * 0.14),
                      control1: CGPoint(x: width * 0.59, y: height * 0.01),
                      control2: CGPoint(x: width * 0.74, y: height * 0.05))
        path.addCurve(to: CGPoint(x: width * 0.91, y: height * 0.52),
                      control1: CGPoint(x: width * 0.94, y: height * 0.24),
                      control2: CGPoint(x: width * 0.96, y: height * 0.39))
        path.addCurve(to: CGPoint(x: width * 0.72, y: height * 0.76),
                      control1: CGPoint(x: width * 0.88, y: height * 0.66),
                      control2: CGPoint(x: width * 0.81, y: height * 0.73))
        path.addCurve(to: CGPoint(x: width * 0.29, y: height * 0.78),
                      control1: CGPoint(x: width * 0.57, y: height * 0.82),
                      control2: CGPoint(x: width * 0.42, y: height * 0.82))
        path.addCurve(to: CGPoint(x: width * 0.08, y: height * 0.58),
                      control1: CGPoint(x: width * 0.16, y: height * 0.76),
                      control2: CGPoint(x: width * 0.08, y: height * 0.69))
        path.addCurve(to: CGPoint(x: width * 0.12, y: height * 0.16),
                      control1: CGPoint(x: width * 0.01, y: height * 0.43),
                      control2: CGPoint(x: width * 0.02, y: height * 0.27))
        path.closeSubpath()
        return path
    }
}

private struct ThoughtBubbleDots: View {
    let isVisible: Bool

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color(red: 0.96, green: 0.97, blue: 1.0))
                .overlay(Ellipse().stroke(Color(red: 0.13, green: 0.19, blue: 0.44).opacity(0.78), lineWidth: 3))
                .frame(width: 22, height: 16).position(x: 127, y: 133)
                .scaleEffect(isVisible ? 1 : 0.7).opacity(isVisible ? 1 : 0)
            Ellipse()
                .fill(Color(red: 0.96, green: 0.97, blue: 1.0))
                .overlay(Ellipse().stroke(Color(red: 0.13, green: 0.19, blue: 0.44).opacity(0.78), lineWidth: 2.5))
                .frame(width: 11.2, height: 8.3).position(x: 102, y: 149)
                .scaleEffect(isVisible ? 1 : 0.7).opacity(isVisible ? 1 : 0)
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isVisible)
    }
}

struct DetailPanelView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var overlayState: OverlayState
    @ObservedObject var settings: CodexPetsSettings
    let onSettings: () -> Void
    let onRefresh: () -> Void

    private var snapshot: UsageSnapshot { viewModel.snapshot }

    private var layout: DetailPanelLayout {
        DetailPanelLayout(
            sideSectionWidth: DetailPanelMetrics.sideSectionWidth,
            contentWidth: DetailPanelMetrics.contentWidth,
            collapsedHeight: DetailPanelMetrics.collapsedHeight
        )
    }

    private var currentScreen: NSScreen? { NSScreen.main ?? NSScreen.screens.first }

    private var detailTopPadding: CGFloat {
        DetailPanelMetrics.detailContentTopPadding(
            safeAreaTop: ScreenSafeAreaGeometry.topSafeInset(for: currentScreen),
            collapsedHeight: layout.collapsedHeight
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(DetailPanelPalette.background)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(DetailPanelPalette.border, lineWidth: 1)
                }
                .shadow(color: DetailPanelPalette.shadow, radius: 20, y: 10)

            ZStack(alignment: .top) {
                VStack(spacing: 10) {
                    header
                    localContent
                }
                .padding(.horizontal, 14)
                .padding(.top, detailTopPadding)
                .padding(.bottom, DetailPanelMetrics.detailBottomPadding)
                .frame(maxHeight: .infinity, alignment: .top)
                quotaResetStrip
            }
            .opacity(overlayState.detailPresentationPhase.showsContent ? 1 : 0)
            .offset(y: overlayState.detailPresentationPhase.showsContent ? 0 : -6)
            .animation(contentAnimation, value: overlayState.detailPresentationPhase)
            .allowsHitTesting(overlayState.detailPresentationPhase.showsContent)
        }
        .frame(width: layout.width, height: detailHeight)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var contentAnimation: Animation? {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return nil }
        return overlayState.detailPresentationPhase == .hiding
            ? .easeIn(duration: DetailAnimationTiming.hideContentDuration)
            : .easeOut(duration: DetailAnimationTiming.contentDuration)
    }

    private var detailHeight: CGFloat {
        DetailPanelMetrics.detailHeight(
            taskRows: DetailPanelMetrics.visibleTaskRows,
            showsPeriodUsage: settings.showPeriodUsage,
            topPadding: detailTopPadding
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(snapshot.isRunning ? "正在运行" : "最近活动")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(DetailPanelPalette.primaryText)
            Spacer()
            Text(snapshot.isRunning ? "\(snapshot.tasks.filter { $0.status == .running }.count) 个任务" : "空闲")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(snapshot.isRunning ? DetailPanelPalette.green : DetailPanelPalette.tertiaryText)
            Button(action: onRefresh) { RefreshIcon(isRefreshing: viewModel.isRefreshing) }
                .buttonStyle(IconButtonStyle()).disabled(viewModel.isRefreshing).help("刷新本机 Codex")
            Button(action: onSettings) {
                Image(systemName: "gearshape.fill").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(IconButtonStyle()).help("设置")
        }
        .frame(height: DetailPanelMetrics.detailHeaderHeight)
    }

    private var localContent: some View {
        VStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(snapshot.tasks) { task in TaskRow(task: task, now: context.date) }
                        if snapshot.tasks.isEmpty { emptyState }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            if settings.showPeriodUsage { periodUsage }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder
    private var quotaResetStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DetailPanelPalette.secondaryText)
            ForEach(snapshot.displayRateLimitWindows) { window in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(window.shortLabel == "5h" ? "5 小时" : "每周")
                            .foregroundStyle(DetailPanelPalette.secondaryText)
                        Text("剩余 \(Formatters.percent(window.remainingPercent))")
                            .foregroundStyle(quotaColor(for: window.shortLabel))
                            .monospacedDigit()
                    }
                    HStack(spacing: 3) {
                        Text("刷新 \(Formatters.quotaResetTime(window.resetsAt))")
                            .foregroundStyle(DetailPanelPalette.tertiaryText)
                            .monospacedDigit()
                        if ResetCreditsPlacement.showsInLocalQuotaRow(label: window.shortLabel) {
                            ResetCreditsIndicator(
                                resetCredits: snapshot.resetCredits,
                                fontSize: 7.8,
                                foregroundColor: DetailPanelPalette.tertiaryText
                            )
                        }
                    }
                }
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, DetailPanelMetrics.quotaResetTopPadding(
            safeAreaTop: ScreenSafeAreaGeometry.topSafeInset(for: currentScreen),
            collapsedHeight: layout.collapsedHeight
        ))
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func quotaColor(for label: String) -> Color {
        label == "5h" ? DetailPanelPalette.green : DetailPanelPalette.blue
    }

    private var emptyState: some View {
        HStack {
            Text(snapshot.errorMessage ?? "暂无 Codex 活动")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(DetailPanelPalette.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 10).frame(height: 36)
        .background(DetailPanelPalette.rowBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    private var periodUsage: some View {
        VStack(spacing: 8) {
            Divider().overlay(DetailPanelPalette.border)
            HStack(spacing: 8) {
                PeriodUsageCell(label: "24小时", value: usageText(snapshot.usage24h))
                PeriodUsageCell(label: "7天", value: usageText(snapshot.usage7d))
                PeriodUsageCell(label: "30天", value: usageText(snapshot.usage30d))
            }
        }
    }

    private func usageText(_ tokens: Int) -> String {
        PeriodUsageDisplay.text(tokens: tokens, hasLoaded: viewModel.hasLoadedUsageTotals)
    }
}

private enum DetailPanelPalette {
    static let background = Color(red: 0.985, green: 0.988, blue: 0.995).opacity(0.985)
    static let rowBackground = Color(red: 0.94, green: 0.95, blue: 0.975).opacity(0.82)
    static let primaryText = Color(red: 0.12, green: 0.14, blue: 0.20)
    static let secondaryText = Color(red: 0.34, green: 0.37, blue: 0.44)
    static let tertiaryText = Color(red: 0.50, green: 0.53, blue: 0.60)
    static let border = Color.black.opacity(0.10)
    static let shadow = Color.black.opacity(0.18)
    static let green = Color(red: 0.10, green: 0.56, blue: 0.32)
    static let blue = Color(red: 0.16, green: 0.42, blue: 0.78)
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? DetailPanelPalette.primaryText : DetailPanelPalette.secondaryText)
            .frame(width: 20, height: 20)
            .background(configuration.isPressed ? Color.black.opacity(0.10) : Color.black.opacity(0.045), in: Circle())
    }
}

private struct RefreshIcon: View {
    let isRefreshing: Bool

    var body: some View {
        Group {
            if isRefreshing {
                TimelineView(.periodic(from: Date(), by: 0.25)) { context in
                    icon.rotationEffect(.degrees(rotationAngle(at: context.date)))
                        .foregroundStyle(DetailPanelPalette.green)
                }
            } else { icon }
        }
    }

    private var icon: some View { Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .bold)) }
    private func rotationAngle(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.85) / 0.85 * 360
    }
}

private struct TaskRow: View {
    let task: CodexTask
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(task.title).font(.system(size: 11, weight: .bold)).foregroundStyle(DetailPanelPalette.primaryText).lineLimit(1)
                Spacer(minLength: 4)
                Text(task.status.label).font(.system(size: 10, weight: .bold)).foregroundStyle(statusColor)
            }
            HStack(spacing: 6) {
                Text(task.displayDetail(now: now)).font(.system(size: 10, weight: .medium)).foregroundStyle(DetailPanelPalette.secondaryText).lineLimit(1)
                Spacer(minLength: 8)
                if let badgeText = TaskBadgeFormatter.subagentBadgeText(for: task.activeSubagentCount) {
                    Text(badgeText)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(DetailPanelPalette.green)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(DetailPanelPalette.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                }
                Text(Formatters.compactTokens(task.tokenCount))
                    .font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(DetailPanelPalette.secondaryText)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(DetailPanelPalette.rowBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(DetailPanelPalette.border.opacity(0.65)))
    }

    private var statusColor: Color {
        switch task.status {
        case .running: DetailPanelPalette.green
        case .recent: DetailPanelPalette.blue
        case .idle: DetailPanelPalette.tertiaryText
        }
    }
}

private struct PeriodUsageCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(DetailPanelPalette.tertiaryText)
            Text(value).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(DetailPanelPalette.primaryText)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
    }
}
