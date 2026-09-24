import Foundation

enum ResetSentinelEventKind: String, Codable, Sendable {
    case reset = "regular"
    case banked

    var label: String {
        switch self {
        case .reset: "额度重置"
        case .banked: "重置卡"
        }
    }
}

struct ResetSentinelEvent: Identifiable, Equatable, Sendable {
    let id: String
    let kind: ResetSentinelEventKind
    let title: String
    let summary: String
    let announcedAt: Date
    let sourceURL: URL
}

struct ResetSentinelStats: Equatable {
    let totalResets: Int
    let averageIntervalDays: Double
    let longestIntervalDays: Double
    let daysSinceLastReset: Double
}

enum ResetSentinelProbability: Equatable {
    case value(percent: Int, sampleSize: Int)
    case insufficient(sampleSize: Int)
    case beyondHistory

    var label: String {
        switch self {
        case .value(let percent, _):
            if percent < 30 { return "低" }
            if percent <= 60 { return "中" }
            return "高"
        case .insufficient: return "样本不足"
        case .beyondHistory: return "已超最长间隔"
        }
    }
}

enum ResetSentinelLogic {
    static let day: TimeInterval = 86_400

    static func stats(events: [ResetSentinelEvent], now: Date = Date()) -> ResetSentinelStats {
        let dates = events.map(\.announcedAt).sorted()
        guard let last = dates.last else {
            return ResetSentinelStats(
                totalResets: 0,
                averageIntervalDays: 0,
                longestIntervalDays: 0,
                daysSinceLastReset: 0
            )
        }
        let intervals = intervalsDays(events: events)
        let average = intervals.isEmpty ? 0 : intervals.reduce(0, +) / Double(intervals.count)
        return ResetSentinelStats(
            totalResets: dates.count,
            averageIntervalDays: average,
            longestIntervalDays: intervals.max() ?? 0,
            daysSinceLastReset: max(0, now.timeIntervalSince(last) / day)
        )
    }

    static func probability(events: [ResetSentinelEvent], now: Date = Date()) -> ResetSentinelProbability {
        let stats = stats(events: events, now: now)
        let intervals = intervalsDays(events: events).sorted()
        guard let longest = intervals.last else {
            return .insufficient(sampleSize: 0)
        }
        if stats.daysSinceLastReset >= longest {
            return .beyondHistory
        }
        let comparable = intervals.filter { $0 > stats.daysSinceLastReset }
        guard comparable.count >= 5 else {
            return .insufficient(sampleSize: comparable.count)
        }
        let nextDay = comparable.filter { $0 <= stats.daysSinceLastReset + 1 }
        let percent = Int((Double(nextDay.count) / Double(comparable.count) * 100).rounded())
        return .value(percent: percent, sampleSize: comparable.count)
    }

    static func nextScan(after date: Date, calendar: Calendar = .current) -> Date {
        let minute = calendar.component(.minute, from: date)
        let seconds = calendar.component(.second, from: date)
        let nanoseconds = calendar.component(.nanosecond, from: date)
        let elapsed = TimeInterval((minute % 30) * 60 + seconds) + TimeInterval(nanoseconds) / 1_000_000_000
        return date.addingTimeInterval(1_800 - elapsed)
    }

    static func secondsUntilNextScan(now: Date = Date()) -> TimeInterval {
        max(1, nextScan(after: now).timeIntervalSince(now))
    }

    private static func intervalsDays(events: [ResetSentinelEvent]) -> [Double] {
        let dates = events.map(\.announcedAt).sorted()
        return zip(dates, dates.dropFirst()).map { earlier, later in
            later.timeIntervalSince(earlier) / day
        }
    }
}

@MainActor
final class ResetSentinelStore: ObservableObject {
    @Published private(set) var events = ResetSentinelSeed.events
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastSuccessfulRefreshAt: Date?
    @Published private(set) var errorMessage: String?

    private let endpoint = URL(string: "https://codex-resets.com/api/resets")!

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 20
            request.setValue("codex-pet-reset-sentinel/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let remote = try JSONDecoder().decode(RemoteResponse.self, from: data).events
            let mapped = try localizedEvents(remote)
            guard !mapped.isEmpty else { throw ResetSentinelError.emptyFeed }
            events = mapped
            lastSuccessfulRefreshAt = Date()
            errorMessage = nil
        } catch {
            errorMessage = "实时雷达暂不可用，正在显示内置快照"
        }
    }

    func localizedEvents(_ remote: [RemoteEvent]) throws -> [ResetSentinelEvent] {
        var seen: Set<String> = []
        let now = Date().addingTimeInterval(300)
        let validated = try remote.map { item in
            guard seen.insert(item.tweetID).inserted,
                  !item.tweetID.isEmpty,
                  let date = ResetSentinelSeed.parseDate(item.announcedAt),
                  date <= now,
                  let url = URL(string: item.tweetURL),
                  url.scheme == "https",
                  url.host == "x.com",
                  url.path.hasPrefix("/thsottiaux/status/") else {
                throw ResetSentinelError.invalidFeed
            }
            return (item: item, date: date, url: url)
        }
        let localizedByTweetID = Dictionary(uniqueKeysWithValues: ResetSentinelSeed.events.map {
            ($0.sourceURL.lastPathComponent, $0)
        })
        return validated
            .sorted { $0.date < $1.date }
            .enumerated()
            .map { offset, entry in
                if let localized = localizedByTweetID[entry.item.tweetID] {
                    return localized
                }
                return ResetSentinelEvent(
                    id: entry.item.tweetID,
                    kind: entry.item.resetType,
                    title: "第 \(offset + 1) 次重置（\(entry.item.resetType == .banked ? "重置卡" : "常规")）",
                    summary: entry.item.text,
                    announcedAt: entry.date,
                    sourceURL: entry.url
                )
            }
    }
}

private struct RemoteResponse: Decodable {
    let events: [RemoteEvent]
}

struct RemoteEvent: Decodable {
    let tweetID: String
    let tweetURL: String
    let text: String
    let announcedAt: String
    let resetType: ResetSentinelEventKind

    enum CodingKeys: String, CodingKey {
        case tweetID = "tweet_id"
        case tweetURL = "tweet_url"
        case text
        case announcedAt = "announced_at"
        case resetType = "reset_type"
    }
}

private enum ResetSentinelError: Error {
    case invalidFeed
    case emptyFeed
}

enum ResetSentinelSeed {
    static let events: [ResetSentinelEvent] = rawData
        .split(separator: "\n")
        .compactMap { line in
            let fields = line.split(separator: "|", maxSplits: 4).map(String.init)
            guard (4...5).contains(fields.count),
                  let date = parseDate(fields[0]),
                  let kind = ResetSentinelEventKind(rawValue: fields[1]),
                  let url = URL(string: "https://x.com/thsottiaux/status/\(fields.count == 5 ? fields[4] : fields[3])") else { return nil }
            return ResetSentinelEvent(
                id: fields[3],
                kind: kind,
                title: fields[2],
                summary: fields[2],
                announcedAt: date,
                sourceURL: url
            )
        }

    static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private static let rawData = """
    2025-09-17T04:02:52.000Z|regular|全员额度重置补偿服务降速|1968163721034994139
    2025-11-05T20:19:29.000Z|regular|故障恢复后重置限额|1986166501435711936
    2025-11-22T23:13:56.000Z|regular|补偿延迟重置全员限额|1992370994028388670
    2025-12-02T22:49:02.000Z|regular|全量重置以快速缓解故障|1995988609896513743
    2025-12-17T02:18:14.000Z|regular|全员用量限额重置|2001114683047317723
    2025-12-19T22:01:37.000Z|regular|计量系统重写并全员重置|2002137269134819610
    2025-12-25T08:01:03.000Z|regular|圣诞礼物：重置并限时翻倍|2004100061933064395
    2026-03-03T01:50:07.000Z|regular|误拦截故障恢复后重置|2028649088594436225
    2026-03-04T21:30:47.000Z|regular|Plus/Pro 限额重置|2029308599835738218
    2026-03-08T02:42:13.000Z|regular|调查额度异常消耗并重置|2030474136024400173
    2026-03-10T03:51:43.000Z|regular|故障稳定后例行重置|2031216405266481489
    2026-03-11T05:38:13.000Z|regular|服务恢复，重置按钮已按下|2031605592352313567
    2026-03-27T01:52:28.000Z|regular|庆祝插件上线全员重置|2037346989244096581
    2026-04-01T07:48:39.000Z|regular|谨慎起见重置全套餐限额|2039248564967424483
    2026-04-07T23:13:48.000Z|regular|庆祝周活三百万重置限额|2041655710346572085
    2026-04-09T17:51:28.000Z|regular|百美元新套餐上线并重置|2042299371602264319
    2026-04-17T00:58:21.000Z|regular|周年庆：全套餐限额重置|2044943514832871564
    2026-04-20T23:15:21.000Z|regular|十分钟故障恢复后重置|2046367145588916687
    2026-04-28T05:28:43.000Z|regular|庆祝好一周，付费套餐重置|2048997818673537399
    2026-05-16T17:51:03.000Z|regular|付费套餐限额周末重置|2055707616605835333
    2026-05-23T20:14:35.000Z|regular|修复额度过耗并全员重置|2058280452851638313
    2026-05-31T15:25:06.000Z|regular|付费订阅恢复满额度|2061106703446450392
    2026-06-04T00:25:58.000Z|regular|多起小故障后付费重置|2062329981548802523
    2026-06-18T00:10:10.000Z|regular|双重重置：全额加重置卡|2067399435009622521
    2026-06-26T23:39:48.000Z|regular|补偿性全员额度重置|2070653282440405046
    2026-06-28T23:54:07.000Z|regular|硬性重置全员额度|2071381664853319742
    2026-06-29T23:39:41.000Z|regular|重置并向重置卡再加一张|2071740419030053227
    2026-07-09T21:24:11.000Z|regular|全量重置一小时内生效|2075330198887940337
    2026-07-10T17:59:43.000Z|regular|当日两波重置的第一波|2075641131002700120
    2026-07-11T05:54:25.000Z|regular|流量激增后再全员重置|2075820987833274448
    2026-07-12T21:28:59.000Z|regular|50 万用户获赠重置卡|2076418567143408112
    2026-07-13T18:29:31.000Z|regular|庆 700 万用户赠重置卡|2076735790567338203
    2026-07-14T19:34:54.000Z|regular|庆 800 万用户全员重置|2077114635308986427
    2026-07-16T04:14:09.000Z|regular|庆 900 万用户再重置|2077607697487188198
    2026-07-18T03:28:22.000Z|regular|付费用户周末再重置|2078320950488297917
    2026-07-21T16:47:15.000Z|regular|庆千万用户付费重置|2079609157934886975
    2026-07-25T19:17:12.000Z|regular|近乎全局故障后重置|2081096447718723984
    2026-07-28T03:09:23.000Z|regular|付费用户额度已重置|2081940052154933696
    2026-07-29T04:09:02.000Z|regular|全员重置并回应 Sol 消耗|2082317452755751098
    2026-08-01T03:32:37.000Z|regular|庆效率周：限额重置|2083395449814229287
    2026-08-08T20:29:22.000Z|regular|庆 Sol 泛用上线付费重置|2086188036493344823
    2026-08-11T00:27:44.000Z|regular|重置已完成|2086972802457063486
    2026-08-13T01:01:37.000Z|regular|庆 1500 万用户重置|2087706104814023111
    2026-08-21T11:43:19.000Z|banked|2000 万用户赠重置卡|2090766694897619318
    2026-08-24T00:46:51.000Z|regular|重置已到账并修复用量|2091688655828246890
    2026-08-25T14:30:00.000Z|regular|观测收录的重置公告|observed-20260825T143200Z|2092311059197808936
    2026-08-27T16:35:05.000Z|regular|全员焕新额度重置|2093014447833116908
    2026-08-29T20:43:34.000Z|regular|付费重置并修复八类消耗|2093801758665715784
    2026-08-31T02:29:25.000Z|regular|庆 2500 万用户付费重置|2094251180121854309
    2026-09-03T23:12:09.000Z|banked|Astra 每日补偿重置卡|2095651088502591861
    2026-09-05T00:39:25.000Z|banked|Astra 上线赠全量重置卡|2096035437299237298
    2026-09-08T01:56:57.501Z|regular|所有用户额度重置|observed-2097043464538264003|2097174560412246215
    2026-09-12T08:09:17.000Z|regular|全量重置已传播完成|2098685367058612394
    """
}
