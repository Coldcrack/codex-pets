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
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.12, blue: 0.28).opacity(0.985),
                        Color(red: 0.13, green: 0.20, blue: 0.43).opacity(0.985)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay {
                    RoundedRectangle(cornerRadius: 24).stroke(Color(red: 0.49, green: 0.61, blue: 0.92).opacity(0.28))
                }
                .shadow(color: Color.black.opacity(0.28), radius: 18, y: 8)

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
                .foregroundStyle(.white.opacity(0.82))
            Spacer()
            Text(snapshot.isRunning ? "\(snapshot.tasks.filter { $0.status == .running }.count) 个任务" : "空闲")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(snapshot.isRunning ? Color(red: 0.61, green: 0.95, blue: 0.68) : .white.opacity(0.48))
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
        VStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 7) {
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
        HStack(spacing: 12) {
            ForEach(snapshot.displayRateLimitWindows) { window in
                HStack(spacing: 3) {
                    Text(window.shortLabel).foregroundStyle(.white.opacity(0.46))
                    Text("刷新").foregroundStyle(.white.opacity(0.38))
                    Text(Formatters.quotaResetTime(window.resetsAt))
                        .foregroundStyle(quotaColor(for: window.shortLabel).opacity(0.82)).monospacedDigit()
                    if ResetCreditsPlacement.showsInLocalQuotaRow(label: window.shortLabel) {
                        ResetCreditsIndicator(resetCredits: snapshot.resetCredits, fontSize: 8.2, foregroundColor: .white.opacity(0.54))
                    }
                }
                .font(.system(size: 8.8, weight: .bold, design: .rounded))
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
        label == "5h" ? Color(red: 0.61, green: 0.95, blue: 0.68) : Color(red: 0.50, green: 0.78, blue: 1.00)
    }

    private var emptyState: some View {
        HStack {
            Text(snapshot.errorMessage ?? "暂无 Codex 活动")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.58))
            Spacer()
        }
        .padding(.horizontal, 10).frame(height: 36)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private var periodUsage: some View {
        HStack(spacing: 8) {
            PeriodUsageCell(label: "24小时", value: usageText(snapshot.usage24h))
            PeriodUsageCell(label: "7天", value: usageText(snapshot.usage7d))
            PeriodUsageCell(label: "30天", value: usageText(snapshot.usage30d))
        }
        .padding(.top, 1)
    }

    private func usageText(_ tokens: Int) -> String {
        PeriodUsageDisplay.text(tokens: tokens, hasLoaded: viewModel.hasLoadedUsageTotals)
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.68 : 0.58))
            .frame(width: 18, height: 18)
            .background(Color.white.opacity(configuration.isPressed ? 0.08 : 0.035), in: Circle())
    }
}

private struct RefreshIcon: View {
    let isRefreshing: Bool

    var body: some View {
        Group {
            if isRefreshing {
                TimelineView(.periodic(from: Date(), by: 0.25)) { context in
                    icon.rotationEffect(.degrees(rotationAngle(at: context.date)))
                        .foregroundStyle(Color(red: 0.61, green: 0.95, blue: 0.68))
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
                Text(task.title).font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.92)).lineLimit(1)
                Spacer(minLength: 4)
                Text(task.status.label).font(.system(size: 10, weight: .bold)).foregroundStyle(statusColor)
            }
            HStack(spacing: 6) {
                Text(task.displayDetail(now: now)).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.56)).lineLimit(1)
                Spacer(minLength: 8)
                if let badgeText = TaskBadgeFormatter.subagentBadgeText(for: task.activeSubagentCount) {
                    Text(badgeText)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.61, green: 0.95, blue: 0.68))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color(red: 0.61, green: 0.95, blue: 0.68).opacity(0.11), in: RoundedRectangle(cornerRadius: 4))
                }
                Text(Formatters.compactTokens(task.tokenCount))
                    .font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.66))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
    }

    private var statusColor: Color {
        switch task.status {
        case .running: Color(red: 0.61, green: 0.95, blue: 0.68)
        case .recent: Color(red: 0.50, green: 0.78, blue: 1.00)
        case .idle: .white.opacity(0.48)
        }
    }
}

private struct PeriodUsageCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.52))
            Text(value).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.92))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(Color.white.opacity(0.026), in: RoundedRectangle(cornerRadius: 8))
    }
}
