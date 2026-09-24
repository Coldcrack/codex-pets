import AppKit
import Foundation
import ServiceManagement
import SwiftUI

protocol LaunchAtLoginManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

private struct SMAppServiceLaunchAtLoginManager: LaunchAtLoginManaging {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}

struct PetSkin: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let path: String
}

enum AppearanceTheme: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class CodexPetsSettings: ObservableObject {
    private enum Keys {
        static let activeRefreshInterval = "activeRefreshInterval"
        static let idleRefreshInterval = "idleRefreshInterval"
        static let usageRefreshInterval = "usageRefreshInterval"
        static let watcherRefreshInterval = "watcherRefreshInterval"
        static let fileChangeRefreshMinimumGap = "fileChangeRefreshMinimumGap"
        static let rateLimitSource = "rateLimitSource"
        static let showPeriodUsage = "showPeriodUsage"
        static let usagePeriodLayout = "usagePeriodLayout"
        static let appearanceTheme = "appearanceTheme"
        static let taskHistoryRange = "taskHistoryRange"
        static let customPetArtworkPath = "customPetArtworkPath"
        static let petSkins = "petSkins"
        static let selectedPetSkinID = "selectedPetSkinID"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let menuBarIconPlacement = "menuBarIconPlacement"
        static let menuBarLayout = "menuBarLayout"
        static let petVisible = "petVisible"
    }

    private let defaults: UserDefaults
    private let launchAtLoginManager: LaunchAtLoginManaging
    private var isInitializing = true

    @Published var activeRefreshInterval: TimeInterval {
        didSet { normalizeActiveRefreshInterval() }
    }

    @Published var idleRefreshInterval: TimeInterval {
        didSet { normalizeIdleRefreshInterval() }
    }

    @Published var usageRefreshInterval: TimeInterval {
        didSet { normalizeUsageRefreshInterval() }
    }

    @Published var watcherRefreshInterval: TimeInterval {
        didSet { normalizeWatcherRefreshInterval() }
    }

    @Published var fileChangeRefreshMinimumGap: TimeInterval {
        didSet { normalizeFileChangeRefreshMinimumGap() }
    }

    @Published var rateLimitSource: RateLimitSourcePreference {
        didSet { defaults.set(rateLimitSource.rawValue, forKey: Keys.rateLimitSource) }
    }

    @Published var showPeriodUsage: Bool {
        didSet { defaults.set(showPeriodUsage, forKey: Keys.showPeriodUsage) }
    }

    @Published var usagePeriodLayout: UsagePeriodLayout {
        didSet { defaults.set(try? JSONEncoder().encode(usagePeriodLayout), forKey: Keys.usagePeriodLayout) }
    }

    @Published var appearanceTheme: AppearanceTheme {
        didSet { defaults.set(appearanceTheme.rawValue, forKey: Keys.appearanceTheme) }
    }

    @Published var taskHistoryRange: TaskHistoryRange {
        didSet { defaults.set(taskHistoryRange.rawValue, forKey: Keys.taskHistoryRange) }
    }

    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var launchAtLoginError: String?

    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
    }

    @Published var menuBarLayout: MenuBarLayout {
        didSet { defaults.set(try? JSONEncoder().encode(menuBarLayout), forKey: Keys.menuBarLayout) }
    }

    @Published private(set) var petVisible: Bool {
        didSet { defaults.set(petVisible, forKey: Keys.petVisible) }
    }

    @Published private(set) var petSkins: [PetSkin]
    @Published private(set) var selectedPetSkinID: String?
    @Published private(set) var petArtworkError: String?
    private var petSkinImages: [String: NSImage]

    init(
        defaults: UserDefaults = .standard,
        launchAtLoginManager: LaunchAtLoginManaging = SMAppServiceLaunchAtLoginManager()
    ) {
        self.defaults = defaults
        self.launchAtLoginManager = launchAtLoginManager

        var loadedPetSkins = defaults.data(forKey: Keys.petSkins)
            .flatMap { try? JSONDecoder().decode([PetSkin].self, from: $0) }
            ?? []
        if loadedPetSkins.isEmpty,
           let legacyPath = defaults.string(forKey: Keys.customPetArtworkPath),
           DownsampledImage.canDecode(url: URL(fileURLWithPath: legacyPath)) {
            loadedPetSkins = [PetSkin(id: "legacy-custom", name: "自定义皮肤", path: legacyPath)]
        }
        loadedPetSkins = loadedPetSkins.filter { skin in
            DownsampledImage.canDecode(url: URL(fileURLWithPath: skin.path))
        }
        let storedSelectedPetSkinID = defaults.string(forKey: Keys.selectedPetSkinID)
            ?? (defaults.string(forKey: Keys.customPetArtworkPath) == nil ? nil : loadedPetSkins.first?.id)

        self.petSkins = loadedPetSkins
        self.petSkinImages = [:]
        self.selectedPetSkinID = loadedPetSkins.contains { $0.id == storedSelectedPetSkinID }
            ? storedSelectedPetSkinID
            : nil
        self.petArtworkError = nil
        self.activeRefreshInterval = Self.clamped(defaults.object(forKey: Keys.activeRefreshInterval) as? TimeInterval ?? 3, min: 2, max: 30)
        self.idleRefreshInterval = Self.clamped(defaults.object(forKey: Keys.idleRefreshInterval) as? TimeInterval ?? 6, min: 4, max: 120)
        self.usageRefreshInterval = Self.clamped(defaults.object(forKey: Keys.usageRefreshInterval) as? TimeInterval ?? 300, min: 120, max: 1_800)
        self.watcherRefreshInterval = Self.clamped(defaults.object(forKey: Keys.watcherRefreshInterval) as? TimeInterval ?? 12, min: 8, max: 120)
        self.fileChangeRefreshMinimumGap = Self.clamped(defaults.object(forKey: Keys.fileChangeRefreshMinimumGap) as? TimeInterval ?? 3, min: 1, max: 30)
        self.rateLimitSource = RateLimitSourcePreference(rawValue: defaults.string(forKey: Keys.rateLimitSource) ?? "") ?? .appServerFirst
        self.showPeriodUsage = defaults.object(forKey: Keys.showPeriodUsage) as? Bool ?? true
        self.usagePeriodLayout = defaults.data(forKey: Keys.usagePeriodLayout)
            .flatMap { try? JSONDecoder().decode(UsagePeriodLayout.self, from: $0) }
            ?? .default
        self.appearanceTheme = AppearanceTheme(rawValue: defaults.string(forKey: Keys.appearanceTheme) ?? "") ?? .light
        self.taskHistoryRange = TaskHistoryRange(rawValue: defaults.string(forKey: Keys.taskHistoryRange) ?? "") ?? .threeDays
        self.launchAtLoginEnabled = launchAtLoginManager.isEnabled
        self.showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
        if let data = defaults.data(forKey: Keys.menuBarLayout),
           let layout = try? JSONDecoder().decode(MenuBarLayout.self, from: data) {
            self.menuBarLayout = layout
        } else {
            switch defaults.string(forKey: Keys.menuBarIconPlacement) {
            case "betweenQuotas":
                self.menuBarLayout = MenuBarLayout(visibleItems: [.fiveHour, .pet, .weekly], hiddenItems: [])
            case "trailing":
                self.menuBarLayout = MenuBarLayout(visibleItems: [.fiveHour, .weekly, .pet], hiddenItems: [])
            default:
                self.menuBarLayout = .default
            }
        }
        self.petVisible = defaults.object(forKey: Keys.petVisible) as? Bool ?? true
        if !petVisible {
            showMenuBarIcon = true
        }
        self.isInitializing = false
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLoginEnabled = launchAtLoginManager.isEnabled
    }

    func setPetVisible(_ visible: Bool) {
        if !visible {
            showMenuBarIcon = true
        }
        petVisible = visible
    }

    var selectedPetSkinImage: NSImage? {
        guard let selectedPetSkinID,
              let skin = petSkins.first(where: { $0.id == selectedPetSkinID }) else {
            return nil
        }
        return image(for: skin)
    }

    func image(for skin: PetSkin) -> NSImage? {
        if let image = petSkinImages[skin.id] {
            return image
        }
        let image = DownsampledImage.load(
            url: URL(fileURLWithPath: skin.path),
            maxPixelSize: 320
        )
        petSkinImages[skin.id] = image
        return image
    }

    @discardableResult
    func importPetSkin(data: Data, name: String) -> String? {
        guard let image = DownsampledImage.load(data: data, maxPixelSize: 320) else {
            petArtworkError = "所选文件不是可用的图片。"
            return nil
        }
        do {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            let directory = root
                .appendingPathComponent("codex-pets", isDirectory: true)
                .appendingPathComponent("PetSkins", isDirectory: true)
            let id = UUID().uuidString
            let destination = directory.appendingPathComponent(id)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let skin = PetSkin(
                id: id,
                name: trimmedName.isEmpty ? "自定义皮肤" : trimmedName,
                path: destination.path
            )
            petSkinImages[id] = image
            petSkins.append(skin)
            persistPetSkins()
            petArtworkError = nil
            return id
        } catch {
            petArtworkError = "宠物图片保存失败：\(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func deletePetSkin(id: String) -> Bool {
        guard let skin = petSkins.first(where: { $0.id == id }) else {
            return true
        }
        do {
            try FileManager.default.removeItem(atPath: skin.path)
            petSkinImages.removeValue(forKey: id)
            petSkins.removeAll { $0.id == id }
            if selectedPetSkinID == id {
                selectPetSkin(nil)
            }
            persistPetSkins()
            petArtworkError = nil
            return true
        } catch {
            petArtworkError = "皮肤删除失败：\(error.localizedDescription)"
            return false
        }
    }

    func selectPetSkin(_ id: String?) {
        selectedPetSkinID = id.flatMap { candidate in
            petSkins.contains { $0.id == candidate } ? candidate : nil
        }
        if let selectedPetSkinID {
            defaults.set(selectedPetSkinID, forKey: Keys.selectedPetSkinID)
        } else {
            defaults.removeObject(forKey: Keys.selectedPetSkinID)
        }
    }

    func resetRefreshDefaults() {
        activeRefreshInterval = 3
        idleRefreshInterval = 6
        usageRefreshInterval = 300
        watcherRefreshInterval = 12
        fileChangeRefreshMinimumGap = 3
    }

    private func persistPetSkins() {
        if let data = try? JSONEncoder().encode(petSkins) {
            defaults.set(data, forKey: Keys.petSkins)
        }
        defaults.removeObject(forKey: Keys.customPetArtworkPath)
    }

    private func normalizeActiveRefreshInterval() {
        let normalized = Self.clamped(activeRefreshInterval.rounded(), min: 2, max: 30)
        guard activeRefreshInterval == normalized else {
            activeRefreshInterval = normalized
            return
        }
        persistRefreshInterval(normalized, key: Keys.activeRefreshInterval)
    }

    private func normalizeIdleRefreshInterval() {
        let normalized = Self.clamped(idleRefreshInterval.rounded(), min: 4, max: 120)
        guard idleRefreshInterval == normalized else {
            idleRefreshInterval = normalized
            return
        }
        persistRefreshInterval(normalized, key: Keys.idleRefreshInterval)
    }

    private func normalizeUsageRefreshInterval() {
        let normalized = Self.clamped(usageRefreshInterval.rounded(), min: 120, max: 1_800)
        guard usageRefreshInterval == normalized else {
            usageRefreshInterval = normalized
            return
        }
        persistRefreshInterval(normalized, key: Keys.usageRefreshInterval)
    }

    private func normalizeWatcherRefreshInterval() {
        let normalized = Self.clamped(watcherRefreshInterval.rounded(), min: 8, max: 120)
        guard watcherRefreshInterval == normalized else {
            watcherRefreshInterval = normalized
            return
        }
        persistRefreshInterval(normalized, key: Keys.watcherRefreshInterval)
    }

    private func normalizeFileChangeRefreshMinimumGap() {
        let normalized = Self.clamped(fileChangeRefreshMinimumGap.rounded(), min: 1, max: 30)
        guard fileChangeRefreshMinimumGap == normalized else {
            fileChangeRefreshMinimumGap = normalized
            return
        }
        persistRefreshInterval(normalized, key: Keys.fileChangeRefreshMinimumGap)
    }

    private func persistRefreshInterval(_ value: TimeInterval, key: String) {
        if !isInitializing {
            defaults.set(value, forKey: key)
        }
    }

    private static func clamped(_ value: TimeInterval, min: TimeInterval, max: TimeInterval) -> TimeInterval {
        Swift.min(max, Swift.max(min, value))
    }
}
