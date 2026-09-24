import Foundation
import Testing
@testable import CodexPets

@MainActor
@Test
func menuBarIconVisibilityDefaultsToEnabledAndPersists() throws {
    let suiteName = "codex-pets-menu-bar-icon-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = CodexPetsSettings(
        defaults: defaults,
        launchAtLoginManager: TestLaunchAtLoginManager()
    )

    #expect(settings.showMenuBarIcon)
    #expect(settings.menuBarLayout == .default)
    settings.showMenuBarIcon = false
    settings.menuBarLayout = MenuBarLayout(
        visibleItems: [.weekly, .pet],
        hiddenItems: [.fiveHour]
    )

    let reloaded = CodexPetsSettings(
        defaults: defaults,
        launchAtLoginManager: TestLaunchAtLoginManager()
    )
    #expect(!reloaded.showMenuBarIcon)
    #expect(reloaded.menuBarLayout.visibleItems == [.weekly, .pet])
    #expect(reloaded.menuBarLayout.hiddenItems == [.fiveHour])
}

@MainActor
@Test
func usagePeriodLayoutDefaultsToAllPeriodsAndPersists() throws {
    let suiteName = "codex-pets-usage-period-layout-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = CodexPetsSettings(
        defaults: defaults,
        launchAtLoginManager: TestLaunchAtLoginManager()
    )
    #expect(settings.usagePeriodLayout.visibleItems == [.today, .twentyFourHours, .sevenDays, .thirtyDays])
    #expect(settings.usagePeriodLayout.hiddenItems.isEmpty)

    settings.usagePeriodLayout = UsagePeriodLayout(
        visibleItems: [.today, .sevenDays],
        hiddenItems: [.twentyFourHours, .thirtyDays]
    )

    let reloaded = CodexPetsSettings(
        defaults: defaults,
        launchAtLoginManager: TestLaunchAtLoginManager()
    )
    #expect(reloaded.usagePeriodLayout.visibleItems == [.today, .sevenDays])
    #expect(reloaded.usagePeriodLayout.hiddenItems == [.twentyFourHours, .thirtyDays])
}

@MainActor
@Test
func appearanceThemeDefaultsToLightAndPersists() throws {
    let suiteName = "codex-pets-appearance-theme-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = CodexPetsSettings(
        defaults: defaults,
        launchAtLoginManager: TestLaunchAtLoginManager()
    )
    #expect(settings.appearanceTheme == .light)
    settings.appearanceTheme = .dark

    let reloaded = CodexPetsSettings(
        defaults: defaults,
        launchAtLoginManager: TestLaunchAtLoginManager()
    )
    #expect(reloaded.appearanceTheme == .dark)
}

@MainActor
@Test
func hidingPetEnablesMenuBarIconAndPersists() throws {
    let suiteName = "codex-pets-hidden-pet-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = CodexPetsSettings(
        defaults: defaults,
        launchAtLoginManager: TestLaunchAtLoginManager()
    )
    settings.showMenuBarIcon = false
    settings.setPetVisible(false)

    #expect(!settings.petVisible)
    #expect(settings.showMenuBarIcon)

    let reloaded = CodexPetsSettings(
        defaults: defaults,
        launchAtLoginManager: TestLaunchAtLoginManager()
    )
    #expect(!reloaded.petVisible)
    #expect(reloaded.showMenuBarIcon)
}

@MainActor
@Test
func refreshIntervalsAreNormalizedAndPersisted() throws {
    let suiteName = "codex-pets-refresh-intervals-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = CodexPetsSettings(
        defaults: defaults,
        launchAtLoginManager: TestLaunchAtLoginManager()
    )
    settings.activeRefreshInterval = 1.4
    settings.idleRefreshInterval = 121
    settings.usageRefreshInterval = 333.4
    settings.watcherRefreshInterval = 7
    settings.fileChangeRefreshMinimumGap = 30.7

    let reloaded = CodexPetsSettings(
        defaults: defaults,
        launchAtLoginManager: TestLaunchAtLoginManager()
    )
    #expect(reloaded.activeRefreshInterval == 2)
    #expect(reloaded.idleRefreshInterval == 120)
    #expect(reloaded.usageRefreshInterval == 333)
    #expect(reloaded.watcherRefreshInterval == 8)
    #expect(reloaded.fileChangeRefreshMinimumGap == 30)
}

private struct TestLaunchAtLoginManager: LaunchAtLoginManaging {
    var isEnabled = false
    func setEnabled(_ enabled: Bool) throws {}
}
