import SwiftUI

struct ResetSentinelView: View {
    @ObservedObject var store: ResetSentinelStore
    @AppStorage("resetSentinelAutoScanEnabled") private var autoScanEnabled = true
    @Environment(\.openURL) private var openURL

    private let historyWeeks = 26
    private let historyCellSize: CGFloat = 17
    private let historyCellGap: CGFloat = 4

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                radarCard
                statsRow
                historyCard
                latestSignals
                disclaimer
            }
            .padding(.vertical, 4)
        }
        .task(id: autoScanEnabled) {
            guard autoScanEnabled else { return }
            await store.refresh()
            while !Task.isCancelled {
                let delay = ResetSentinelLogic.secondsUntilNextScan()
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { break }
                await store.refresh()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("CODEX RESET SENTINEL")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text("codex重置哨兵")
                    .font(.system(size: 24, weight: .bold))
                Text("追踪公开重置公告，从历史记录中发现下一次信号。")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                Toggle("自动扫描", isOn: $autoScanEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .semibold))
                Button {
                    Task { await store.refresh() }
                } label: {
                    if store.isRefreshing {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.mini)
                            Text("扫描中")
                        }
                    } else {
                        Label("手动扫描", systemImage: "arrow.clockwise")
                    }
                }
                .controlSize(.small)
                .disabled(store.isRefreshing)
            }
        }
    }

    private var radarCard: some View {
        let stats = ResetSentinelLogic.stats(events: store.events)
        let probability = ResetSentinelLogic.probability(events: store.events)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(
                    radarStatusTitle,
                    systemImage: radarStatusIcon
                )
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(radarStatusColor)
                Spacer()
                Text("已等待 \(stats.daysSinceLastReset, specifier: "%.1f") 天")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(autoScanEnabled ? "距离下一次信号扫描" : "自动扫描已暂停")
                        .font(.system(size: 15, weight: .bold))
                    if autoScanEnabled {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(countdownText(now: context.date))
                                .font(.system(size: 31, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                    } else {
                        Text("--:--:--")
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    Text(autoScanEnabled ? "整点 / 半点自动刷新公开信号" : "仍可使用右上角的手动扫描")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 82)

                VStack(alignment: .leading, spacing: 6) {
                    Text("未来 24 小时")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    probabilityValue(probability)
                    Text("历史条件概率 · 仅供趋势参考")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 190, alignment: .leading)
            }

            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .sentinelCard()
    }

    private var statsRow: some View {
        let stats = ResetSentinelLogic.stats(events: store.events)
        return HStack(spacing: 10) {
            statCell(title: "累计记录", value: "\(stats.totalResets)", unit: "次")
            statCell(title: "平均间隔", value: stats.averageIntervalDays.formatted(.number.precision(.fractionLength(1))), unit: "天")
            statCell(title: "最长间隔", value: stats.longestIntervalDays.formatted(.number.precision(.fractionLength(0))), unit: "天")
        }
    }

    private var historyCard: some View {
        let calendar = historyCalendar
        let start = historyStartDate(calendar: calendar)
        let eventsByDay = Dictionary(grouping: store.events) { event in
            calendar.startOfDay(for: event.announcedAt)
        }.compactMapValues { events in
            events.max { $0.announcedAt < $1.announcedAt }
        }
        let latest = store.events.max { $0.announcedAt < $1.announcedAt }

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("RESET MAP / 26 WEEKS")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                Text("Codex 重置历史")
                    .font(.system(size: 17, weight: .bold))
            }

            HStack(spacing: 16) {
                historyLegend(color: .blue, title: "额度重置")
                historyLegend(color: .blue.opacity(0.52), title: "重置卡")
                Text("悬停查看摘要，点击打开原帖")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: historyCellGap) {
                HStack(spacing: historyCellGap) {
                    Color.clear.frame(width: 16, height: 12)
                    ForEach(0..<historyWeeks, id: \.self) { week in
                        Text(monthLabel(week: week, start: start, calendar: calendar))
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(width: historyCellSize, height: 12, alignment: .leading)
                    }
                }

                ForEach(0..<7, id: \.self) { weekday in
                    HStack(spacing: historyCellGap) {
                        Text(["一", "二", "三", "四", "五", "六", "日"][weekday])
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(width: 16, alignment: .leading)
                        ForEach(0..<historyWeeks, id: \.self) { week in
                            let day = calendar.date(byAdding: .day, value: week * 7 + weekday, to: start)!
                            historyCell(event: eventsByDay[calendar.startOfDay(for: day)])
                        }
                    }
                }
            }

            if let latest {
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                    Text("最近一次")
                        .foregroundStyle(.secondary)
                    Text(dateOnlyText(latest.announcedAt))
                        .fontWeight(.bold)
                    Text("· \(latest.kind.label)")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 10.5, weight: .medium))
            }
        }
        .sentinelCard()
    }

    private var latestSignals: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近公开信号")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text(store.lastSuccessfulRefreshAt.map { "更新于 \(dateText($0))" } ?? "当前为内置快照")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            ForEach(Array(store.events.suffix(6).reversed())) { event in
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(event.kind == .banked ? Color.blue.opacity(0.52) : Color.blue)
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(event.kind.label)
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(event.kind == .banked ? Color.blue.opacity(0.7) : .secondary)
                            Text(dateText(event.announcedAt))
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                        Link(destination: event.sourceURL) {
                            Text(event.title)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                if event.id != store.events.suffix(6).first?.id { Divider() }
            }
        }
        .sentinelCard()
    }

    private var disclaimer: some View {
        Text("公开信号来自 @thsottiaux / codex-resets.com；概率基于历史间隔，不代表 OpenAI 的额度承诺。")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func probabilityValue(_ probability: ResetSentinelProbability) -> some View {
        switch probability {
        case .value(let percent, let sampleSize):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(percent)%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("\(probability.label) · \(sampleSize) 组样本")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        case .insufficient(let sampleSize):
            Text("样本不足（\(sampleSize) 组）")
                .font(.system(size: 18, weight: .bold))
        case .beyondHistory:
            Text("已超最长间隔")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.orange)
        }
    }

    private func statCell(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(unit).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sentinelCard()
    }

    private func countdownText(now: Date) -> String {
        let remaining = max(0, Int(ResetSentinelLogic.nextScan(after: now).timeIntervalSince(now)))
        return String(format: "%02d:%02d:%02d", remaining / 3_600, (remaining % 3_600) / 60, remaining % 60)
    }

    private var historyCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func historyStartDate(calendar: Calendar, now: Date = Date()) -> Date {
        let today = calendar.startOfDay(for: now)
        let daysSinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        let currentMonday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today)!
        return calendar.date(byAdding: .weekOfYear, value: -(historyWeeks - 1), to: currentMonday)!
    }

    private func monthLabel(week: Int, start: Date, calendar: Calendar) -> String {
        let date = calendar.date(byAdding: .weekOfYear, value: week, to: start)!
        guard week == 0 || calendar.component(.month, from: date) != calendar.component(
            .month,
            from: calendar.date(byAdding: .weekOfYear, value: week - 1, to: start)!
        ) else { return "" }
        return "\(calendar.component(.month, from: date))月"
    }

    @ViewBuilder
    private func historyCell(event: ResetSentinelEvent?) -> some View {
        if let event {
            Button { openURL(event.sourceURL) } label: {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(event.kind == .banked ? Color.blue.opacity(0.52) : Color.blue)
                    .frame(width: historyCellSize, height: historyCellSize)
            }
            .buttonStyle(.plain)
            .help("\(event.kind.label) · \(event.title) · \(dateOnlyText(event.announcedAt))")
        } else {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.primary.opacity(0.055))
                .frame(width: historyCellSize, height: historyCellSize)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                }
        }
    }

    private func historyLegend(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var radarStatusTitle: String {
        if !autoScanEnabled { return "自动扫描已关闭" }
        return store.lastSuccessfulRefreshAt == nil ? "内置快照" : "雷达在线"
    }

    private var radarStatusIcon: String {
        if !autoScanEnabled { return "pause.circle.fill" }
        return store.lastSuccessfulRefreshAt == nil ? "archivebox.fill" : "dot.radiowaves.left.and.right"
    }

    private var radarStatusColor: Color {
        if !autoScanEnabled { return .secondary }
        return store.lastSuccessfulRefreshAt == nil ? .orange : .green
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private func dateOnlyText(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day())
    }
}

private extension View {
    func sentinelCard() -> some View {
        padding(14)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            }
    }
}
