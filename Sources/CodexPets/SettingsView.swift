import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum RefreshPreset: String, CaseIterable, Identifiable {
    case realtime
    case balanced
    case economy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .realtime: "实时"
        case .balanced: "均衡"
        case .economy: "低功耗"
        }
    }

    var values: (active: TimeInterval, idle: TimeInterval, usage: TimeInterval, watcher: TimeInterval, gap: TimeInterval) {
        switch self {
        case .realtime: (2, 4, 120, 8, 1)
        case .balanced: (3, 6, 300, 12, 3)
        case .economy: (8, 20, 900, 30, 8)
        }
    }

    func matches(_ draft: SettingsDraft) -> Bool {
        let values = values
        return draft.activeRefreshInterval == values.active
            && draft.idleRefreshInterval == values.idle
            && draft.usageRefreshInterval == values.usage
            && draft.watcherRefreshInterval == values.watcher
            && draft.fileChangeRefreshMinimumGap == values.gap
    }

    static func matching(_ draft: SettingsDraft) -> RefreshPreset {
        allCases.first { $0.matches(draft) } ?? .balanced
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case codex
    case launch
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: "Codex"
        case .launch: "启动与外观"
        case .about: "关于"
        }
    }

    var iconName: String {
        switch self {
        case .codex: "circle.grid.2x2.fill"
        case .launch: "gearshape.fill"
        case .about: "info.circle.fill"
        }
    }
}

private struct SettingsDraft: Equatable {
    var activeRefreshInterval: TimeInterval = 3
    var idleRefreshInterval: TimeInterval = 6
    var usageRefreshInterval: TimeInterval = 300
    var watcherRefreshInterval: TimeInterval = 12
    var fileChangeRefreshMinimumGap: TimeInterval = 3
    var rateLimitSource: RateLimitSourcePreference = .appServerFirst
    var showPeriodUsage = true
    var taskHistoryRange: TaskHistoryRange = .threeDays
    var selectedPetSkinID: String?
    var launchAtLoginEnabled = false
    var showMenuBarIcon = true
    var menuBarLayout: MenuBarLayout = .default

    @MainActor
    init(settings: CodexPetsSettings) {
        activeRefreshInterval = settings.activeRefreshInterval
        idleRefreshInterval = settings.idleRefreshInterval
        usageRefreshInterval = settings.usageRefreshInterval
        watcherRefreshInterval = settings.watcherRefreshInterval
        fileChangeRefreshMinimumGap = settings.fileChangeRefreshMinimumGap
        rateLimitSource = settings.rateLimitSource
        showPeriodUsage = settings.showPeriodUsage
        taskHistoryRange = settings.taskHistoryRange
        selectedPetSkinID = settings.selectedPetSkinID
        launchAtLoginEnabled = settings.launchAtLoginEnabled
        showMenuBarIcon = settings.showMenuBarIcon
        menuBarLayout = settings.menuBarLayout
    }

    init() {}

    mutating func applyPreset(_ preset: RefreshPreset) {
        let values = preset.values
        activeRefreshInterval = values.active
        idleRefreshInterval = values.idle
        usageRefreshInterval = values.usage
        watcherRefreshInterval = values.watcher
        fileChangeRefreshMinimumGap = values.gap
    }
}

private struct MenuBarLayoutEditor: View {
    @Binding var layout: MenuBarLayout
    let icon: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            itemZone(title: "显示区", items: layout.visibleItems, isHidden: false)
            itemZone(title: "隐藏区", items: layout.hiddenItems, isHidden: true)
        }
    }

    private func itemZone(title: String, items: [MenuBarDisplayItem], isHidden: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHidden ? .secondary : .primary)

            HStack(spacing: 7) {
                ForEach(items) { item in
                    itemCard(item)
                        .draggable(item.rawValue)
                        .dropDestination(for: String.self) { values, _ in
                            move(values.first, toHidden: isHidden, before: item)
                        }
                }
                if items.isEmpty {
                    Text("拖到这里")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 8)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .dropDestination(for: String.self) { values, _ in
                move(values.first, toHidden: isHidden, before: nil)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func itemCard(_ item: MenuBarDisplayItem) -> some View {
        VStack(spacing: 2) {
            switch item {
            case .pet:
                Group {
                    if let icon {
                        Image(nsImage: icon).resizable().renderingMode(.template).scaledToFit()
                    } else {
                        Image(systemName: "pawprint.fill").resizable().scaledToFit()
                    }
                }
                .frame(width: 18, height: 18)
                Text("宠物").font(.system(size: 8, weight: .semibold))
            case .fiveHour:
                Text("54%").font(.system(size: 10, weight: .medium, design: .rounded))
                Text("5h").font(.system(size: 8, weight: .semibold, design: .rounded))
            case .weekly:
                Text("81%").font(.system(size: 10, weight: .medium, design: .rounded))
                Text("7d").font(.system(size: 8, weight: .semibold, design: .rounded))
            }
        }
        .monospacedDigit()
        .foregroundStyle(.primary)
        .frame(width: 48, height: 38)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .help("拖动以排序或切换显示状态")
    }

    private func move(_ rawValue: String?, toHidden: Bool, before target: MenuBarDisplayItem?) -> Bool {
        guard let rawValue, let item = MenuBarDisplayItem(rawValue: rawValue) else {
            return false
        }
        if target == item {
            return true
        }
        var visible = layout.visibleItems.filter { $0 != item }
        var hidden = layout.hiddenItems.filter { $0 != item }
        if toHidden {
            guard !visible.isEmpty else {
                return false
            }
            insert(item, before: target, into: &hidden)
        } else {
            insert(item, before: target, into: &visible)
        }
        layout = MenuBarLayout(visibleItems: visible, hiddenItems: hidden)
        return true
    }

    private func insert(_ item: MenuBarDisplayItem, before target: MenuBarDisplayItem?, into items: inout [MenuBarDisplayItem]) {
        if let target, let index = items.firstIndex(of: target) {
            items.insert(item, at: index)
        } else {
            items.append(item)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: CodexPetsSettings
    let onRefresh: () -> Void

    @State private var draft = SettingsDraft()
    @State private var selectedPreset: RefreshPreset = .balanced
    @State private var selectedTab: SettingsTab = .codex
    @State private var petArtworkSelectionError: String?
    @State private var petSkinDeleteCandidate: PetSkin?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                Text("codex-pet 设置")
                    .font(.system(size: 18, weight: .bold))
                Form { tabContent }
                    .formStyle(.grouped)
                footer
            }
            .padding(20)
            .frame(width: 710)
        }
        .frame(width: 900)
        .frame(minHeight: 660)
        .onAppear { reloadDraft() }
        .onChange(of: settings.showMenuBarIcon) { _, isVisible in
            draft.showMenuBarIcon = isVisible
        }
        .alert(
            "删除皮肤？",
            isPresented: Binding(
                get: { petSkinDeleteCandidate != nil },
                set: { if !$0 { petSkinDeleteCandidate = nil } }
            )
        ) {
            Button("删除", role: .destructive) { deletePendingPetSkin() }
            Button("取消", role: .cancel) { petSkinDeleteCandidate = nil }
        } message: {
            Text(petSkinDeleteCandidate.map { "确定删除「\($0.name)」吗？" } ?? "")
        }
    }

    private var currentDraft: SettingsDraft { SettingsDraft(settings: settings) }
    private var hasChanges: Bool { draft != currentDraft }

    private var menuBarPreviewIcon: NSImage? {
        let image: NSImage?
        if let bundledURL = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png") {
            image = NSImage(contentsOf: bundledURL)
        } else {
            image = NSImage(contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/MenuBarIcon.png"))
        }
        let copy = image?.copy() as? NSImage
        copy?.isTemplate = true
        return copy
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("设置")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            ForEach(SettingsTab.allCases) { tab in
                Button { selectedTab = tab } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.iconName).frame(width: 16)
                        Text(tab.title).font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(selectedTab == tab ? Color.primary.opacity(0.10) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 20)
        .frame(width: 190)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.secondary.opacity(0.055))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .codex: codexSettingsContent
        case .launch: launchAndAppearanceContent
        case .about: aboutContent
        }
    }

    @ViewBuilder
    private var codexSettingsContent: some View {
        Section("Codex 刷新") {
            HelpLabel(title: "刷新模式", help: "快速切换本机 Codex 状态、历史用量和文件监听的刷新频率。")
            presetControls
            intervalStepper("运行中", value: $draft.activeRefreshInterval, range: 2...30, help: "Codex 正在执行任务时的刷新间隔。")
            intervalStepper("空闲", value: $draft.idleRefreshInterval, range: 4...120, help: "Codex 没有运行中任务时的刷新间隔。")
            intervalStepper("历史用量", value: $draft.usageRefreshInterval, range: 120...1_800, help: "统计本机 token 用量的刷新间隔。")
            intervalStepper("文件监听", value: $draft.watcherRefreshInterval, range: 8...120, help: "扫描本机 Codex 会话文件变化的保底间隔。")
            intervalStepper("补刷节流", value: $draft.fileChangeRefreshMinimumGap, range: 1...30, help: "文件频繁变化时连续刷新的最小间隔。")
        }
        Section("Codex 数据") {
            Picker(selection: $draft.rateLimitSource) {
                ForEach(RateLimitSourcePreference.allCases) { source in
                    Text(source.label).tag(source)
                }
            } label: {
                HelpLabel(title: "额度来源", help: "决定本机 Codex 额度优先从实时接口读取，还是只使用本地记录。")
            }
            .pickerStyle(.segmented)
            Toggle(isOn: $draft.showPeriodUsage) {
                HelpLabel(title: "显示 24小时 / 7天 / 30天", help: "控制详情页是否显示本机 token 用量。")
            }
            Picker(selection: $draft.taskHistoryRange) {
                ForEach(TaskHistoryRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            } label: {
                HelpLabel(title: "任务范围", help: "决定详情页读取最近多长时间内的本机 Codex 对话。")
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var launchAndAppearanceContent: some View {
        Section("宠物换肤") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112, maximum: 112), spacing: 12)], alignment: .leading, spacing: 12) {
                Button(action: choosePetArtwork) {
                    VStack(spacing: 7) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 28)).foregroundStyle(.secondary)
                        Text("添加照片…").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }
                    .frame(width: 112, height: 90)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                petSkinCard(image: PetArtwork.defaultImage, name: "默认形象", isSelected: draft.selectedPetSkinID == nil) {
                    draft.selectedPetSkinID = nil
                }
                ForEach(settings.petSkins) { skin in
                    ZStack(alignment: .topTrailing) {
                        petSkinCard(image: settings.image(for: skin), name: skin.name, isSelected: draft.selectedPetSkinID == skin.id) {
                            draft.selectedPetSkinID = skin.id
                        }
                        Button { petSkinDeleteCandidate = skin } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.black.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .padding(5)
                    }
                }
            }
            Text("点击皮肤选择，保存后生效。支持常见图片格式，透明背景效果最佳。")
                .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
            if let message = petArtworkSelectionError ?? settings.petArtworkError {
                Text(message).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.red)
            }
        }
        Section("启动与外观") {
            Toggle(isOn: $draft.showMenuBarIcon) {
                HelpLabel(title: "显示菜单栏图标", help: "在菜单栏显示宠物、本机 5h 和 7d 额度。宠物隐藏时必须保持开启。")
            }
            .disabled(!settings.petVisible)
            VStack(alignment: .leading, spacing: 8) {
                HelpLabel(title: "菜单栏项目编辑", help: "拖动宠物、5h 和 7d 项目调整顺序或显示状态。")
                MenuBarLayoutEditor(layout: $draft.menuBarLayout, icon: menuBarPreviewIcon)
            }
            .disabled(!draft.showMenuBarIcon)
            Toggle(isOn: $draft.launchAtLoginEnabled) {
                HelpLabel(title: "开机自启", help: "登录 macOS 后自动启动 codex-pet。")
            }
            if let error = settings.launchAtLoginError {
                Text("开机自启设置失败：\(error)").font(.system(size: 11)).foregroundStyle(.red)
            }
        }
    }

    private var aboutContent: some View {
        Section("关于 codex-pet") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("codex-pet").font(.system(size: 18, weight: .bold))
                        Text("Mac 桌面上的本机 Codex 监测宠物").foregroundStyle(.secondary)
                    }
                }
                Divider()
                infoRow(title: "版本", value: AppInfo.displayVersion)
                infoRow(title: "本机监测", value: "Codex 运行状态、额度和 token 用量")
                Text("codex-pet 只读取当前 Mac 上的 Codex 本地数据，不连接远程账号或余额面板。")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("恢复默认刷新") {
                draft.applyPreset(.balanced)
                selectedPreset = .balanced
            }
            if hasChanges {
                Text("有未保存更改").font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
            }
            Spacer()
            Button("立即刷新", action: onRefresh).keyboardShortcut("r", modifiers: .command)
            Button("取消更改", action: reloadDraft).disabled(!hasChanges)
            Button("保存", action: saveDraft).keyboardShortcut(.defaultAction).disabled(!hasChanges)
        }
    }

    private var presetControls: some View {
        HStack(spacing: 8) {
            ForEach(RefreshPreset.allCases) { preset in
                Button {
                    selectedPreset = preset
                    draft.applyPreset(preset)
                } label: {
                    Text(preset.title)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedPreset == preset ? Color.primary.opacity(0.14) : Color.secondary.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func intervalStepper(_ title: String, value: Binding<TimeInterval>, range: ClosedRange<TimeInterval>, help: String) -> some View {
        HStack {
            HelpLabel(title: title, help: help)
            Spacer()
            Text("\(Int(value.wrappedValue)) 秒")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
            Stepper("", value: value, in: range, step: 1).labelsHidden()
        }
    }

    private func petSkinCard(image: NSImage?, name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                if let image {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit().frame(height: 68)
                } else {
                    Image(systemName: "person.crop.square").font(.system(size: 28)).foregroundStyle(.secondary).frame(height: 68)
                }
                Text(name).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
            }
            .padding(5)
            .frame(width: 112, height: 90)
            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.16), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func choosePetArtwork() {
        let panel = NSOpenPanel()
        panel.title = "选择宠物形象"
        panel.prompt = "选择"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            if let skinID = settings.importPetSkin(data: data, name: url.deletingPathExtension().lastPathComponent) {
                draft.selectedPetSkinID = skinID
                petArtworkSelectionError = nil
            }
        } catch {
            petArtworkSelectionError = "图片读取失败：\(error.localizedDescription)"
        }
    }

    private func deletePendingPetSkin() {
        guard let skin = petSkinDeleteCandidate else { return }
        if settings.deletePetSkin(id: skin.id), draft.selectedPetSkinID == skin.id {
            draft.selectedPetSkinID = nil
        }
        petSkinDeleteCandidate = nil
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
            Text(value).font(.system(size: 12, weight: .semibold)).textSelection(.enabled)
            Spacer()
        }
    }

    private func reloadDraft() {
        draft = currentDraft
        selectedPreset = .matching(draft)
    }

    private func saveDraft() {
        let next = draft
        settings.activeRefreshInterval = next.activeRefreshInterval
        settings.idleRefreshInterval = next.idleRefreshInterval
        settings.usageRefreshInterval = next.usageRefreshInterval
        settings.watcherRefreshInterval = next.watcherRefreshInterval
        settings.fileChangeRefreshMinimumGap = next.fileChangeRefreshMinimumGap
        settings.rateLimitSource = next.rateLimitSource
        settings.showPeriodUsage = next.showPeriodUsage
        settings.taskHistoryRange = next.taskHistoryRange
        settings.selectPetSkin(next.selectedPetSkinID)
        if next.launchAtLoginEnabled != settings.launchAtLoginEnabled {
            settings.setLaunchAtLoginEnabled(next.launchAtLoginEnabled)
        }
        settings.showMenuBarIcon = settings.petVisible ? next.showMenuBarIcon : true
        settings.menuBarLayout = next.menuBarLayout
        reloadDraft()
    }
}

private struct HelpLabel: View {
    let title: String
    let help: String
    @State private var showsHelp = false

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            Button { showsHelp.toggle() } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showsHelp, arrowEdge: .trailing) {
                Text(help)
                    .font(.system(size: 12, weight: .medium))
                    .padding(12)
                    .frame(width: 260, alignment: .leading)
            }
        }
    }
}
