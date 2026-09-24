import AppKit
import Combine
import QuartzCore
import SwiftUI

@main
struct CodexPetsApp {
    static func main() {
        let arguments = CommandLine.arguments
        let shouldPrintHumanSnapshot = arguments.contains("--print-snapshot") || arguments.contains("--print-fast-snapshot")
        let shouldPrintJSONSnapshot = arguments.contains("--print-snapshot-json") || arguments.contains("--print-fast-snapshot-json")
        if shouldPrintHumanSnapshot || shouldPrintJSONSnapshot {
            let includePeriodUsage = !(arguments.contains("--print-fast-snapshot") || arguments.contains("--print-fast-snapshot-json"))
            let snapshot = CodexUsageStore().loadSnapshot(includePeriodUsage: includePeriodUsage)
            if shouldPrintJSONSnapshot {
                FileHandle.standardOutput.write(SnapshotOutputFormatter.jsonData(for: snapshot))
                FileHandle.standardOutput.write(Data("\n".utf8))
            } else {
                for line in SnapshotOutputFormatter.humanLines(for: snapshot) {
                    print(line)
                }
            }
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("codex-pet runs as a persistent desktop companion")
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayController: PetOverlayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        overlayController = PetOverlayController()
        overlayController?.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: "codex-pet")
        appMenu.addItem(withTitle: "退出 codex-pet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(editMenuItem("撤销", action: Selector(("undo:")), key: "z"))
        editMenu.addItem(editMenuItem("重做", action: Selector(("redo:")), key: "Z", modifiers: [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(editMenuItem("剪切", action: #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(editMenuItem("拷贝", action: #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(editMenuItem("粘贴", action: #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(.separator())
        editMenu.addItem(editMenuItem("全选", action: #selector(NSText.selectAll(_:)), key: "a"))
        editItem.submenu = editMenu

        return mainMenu
    }

    private static func editMenuItem(
        _ title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = nil
        return item
    }
}

private final class TopAnchoredClippingView: NSView {
    private let hostedView: NSView
    private var targetContentSize: NSSize

    init(hostedView: NSView, contentSize: NSSize) {
        self.hostedView = hostedView
        targetContentSize = contentSize
        super.init(frame: NSRect(origin: .zero, size: contentSize))

        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.clear.cgColor
        hostedView.autoresizingMask = []
        addSubview(hostedView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func updateContentSize(_ size: NSSize) {
        targetContentSize = size
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        hostedView.frame = NSRect(
            x: bounds.minX,
            y: bounds.maxY - targetContentSize.height,
            width: targetContentSize.width,
            height: targetContentSize.height
        )
    }
}

private struct MenuBarQuotaView: View {
    let icon: NSImage?
    let quota: MenuBarQuotaStatus
    let layout: MenuBarLayout

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(layout.visibleItems.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    itemDivider
                }
                itemView(item)
            }
        }
        .frame(height: 22)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func itemView(_ item: MenuBarDisplayItem) -> some View {
        switch item {
        case .pet:
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(.primary)
                    .frame(width: 18, height: 18)
            }
        case .fiveHour:
            quotaColumn(Formatters.percent(quota.fiveHourPercent), label: "5h")
        case .weekly:
            quotaColumn(Formatters.percent(quota.weeklyPercent), label: "7d")
        }
    }

    private var itemDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.38))
            .frame(width: 0.5, height: 18)
    }

    private func quotaColumn(_ value: String, label: String) -> some View {
        VStack(spacing: -1) {
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .rounded))
            Text(label)
                .font(.system(size: 7.5, weight: .semibold, design: .rounded))
        }
        .monospacedDigit()
        .lineLimit(1)
        .frame(width: 28)
    }
}

private final class PassThroughMenuBarHostingView: NSHostingView<MenuBarQuotaView> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private enum DetailPresentationAnchor {
    case pet
    case menuBar
}

@MainActor
final class PetOverlayController {
    private let settings = CodexPetsSettings()
    private lazy var viewModel = UsageViewModel(settings: settings)
    private let overlayState = OverlayState()
    private let window: NSPanel
    private let detailWindow: NSPanel
    private var detailContentContainer: TopAnchoredClippingView?
    private lazy var settingsController = SettingsWindowController(
        settings: settings,
        onRefresh: { [weak self] in
            self?.viewModel.refreshAll()
        }
    )
    private var cancellables: Set<AnyCancellable> = []
    private var eventMonitors: [Any] = []
    private var detailTransition = DetailTransitionState()
    private var pendingDetailWorkItems: [DispatchWorkItem] = []
    private var latestDetailExpandedFrame: NSRect?
    private var systemActivityResumeTimer: Timer?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var menuBarHostingView: PassThroughMenuBarHostingView?
    private var menuBarTemplateImage: NSImage?
    private var petVisibilityMenuItem: NSMenuItem?
    private var petOrigin: NSPoint?
    private var petDragStartOrigin: NSPoint?
    private var petDragStartPointer: NSPoint?
    private var detailPresentationAnchor: DetailPresentationAnchor = .pet

    private static let detailSettleDuration: TimeInterval = 0.12

    init() {
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: PetMetrics.width, height: PetMetrics.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        detailWindow = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: DetailPanelMetrics.width, height: DetailPanelMetrics.detailHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configureWindow()
        configureContent()
        observeState()
        observeScreenChanges()
        observeSystemActivity()
        installEventMonitors()
        synchronizeFramesForGeometryChange()
    }

    func show() {
        applyPetVisibility(settings.petVisible)
    }

    private func configureWindow() {
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

        detailWindow.backgroundColor = .clear
        detailWindow.isOpaque = false
        detailWindow.hasShadow = true
        detailWindow.level = .statusBar
        detailWindow.ignoresMouseEvents = false
        detailWindow.isMovableByWindowBackground = false
        detailWindow.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
    }

    private func configureContent() {
        let view = PetDashboardView(
            viewModel: viewModel,
            overlayState: overlayState,
            settings: settings,
            onToggleDetail: { [weak self] in
                guard let self else {
                    return
                }
                self.detailPresentationAnchor = .pet
                self.overlayState.isExpanded.toggle()
            },
            onSettings: { [weak self] in
                self?.showSettings()
            },
            onHidePet: { [weak self] in
                self?.settings.setPetVisible(false)
            },
            onPetDragChanged: { [weak self] in
                self?.dragPet(to: NSEvent.mouseLocation)
            },
            onPetDragEnded: { [weak self] in
                self?.finishDraggingPet()
            }
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: PetMetrics.width, height: PetMetrics.height)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = hostingView

        let detailView = DetailPanelView(
            viewModel: viewModel,
            overlayState: overlayState,
            settings: settings,
            onSettings: { [weak self] in
                self?.showSettings()
            },
            onRefresh: { [weak self] in
                self?.viewModel.refreshAll()
            }
        )
        let detailHostingView = NSHostingView(rootView: detailView)
        let detailContentSize = NSSize(width: DetailPanelMetrics.width, height: currentDetailHeight())
        detailHostingView.frame = NSRect(origin: .zero, size: detailContentSize)
        detailHostingView.wantsLayer = true
        detailHostingView.layer?.backgroundColor = NSColor.clear.cgColor
        let detailContentContainer = TopAnchoredClippingView(
            hostedView: detailHostingView,
            contentSize: detailContentSize
        )
        self.detailContentContainer = detailContentContainer
        detailWindow.contentView = detailContentContainer
    }

    private func observeState() {
        settings.$showMenuBarIcon
            .removeDuplicates()
            .sink { [weak self] isVisible in
                self?.setMenuBarIconVisible(isVisible)
            }
            .store(in: &cancellables)

        settings.$menuBarLayout
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                self.updateMenuBarQuota(self.viewModel.snapshot)
            }
            .store(in: &cancellables)

        viewModel.$snapshot
            .removeDuplicates()
            .sink { [weak self] snapshot in
                self?.updateMenuBarQuota(snapshot)
            }
            .store(in: &cancellables)

        settings.$petVisible
            .removeDuplicates()
            .sink { [weak self] isVisible in
                self?.applyPetVisibility(isVisible)
            }
            .store(in: &cancellables)

        overlayState.$isExpanded
            .removeDuplicates()
            .sink { [weak self] isExpanded in
                guard let self else {
                    return
                }
                self.setDetailVisible(isExpanded)
                if isExpanded, self.settings.showPeriodUsage {
                    self.viewModel.refreshUsageTotalsIfStale()
                } else if self.settings.showPeriodUsage {
                    self.viewModel.pausePeriodicUsageRefresh()
                } else {
                    self.viewModel.disableUsageTotals()
                }
            }
            .store(in: &cancellables)

        settings.$taskHistoryRange
            .combineLatest(settings.$showPeriodUsage)
            .sink { [weak self] _, showPeriodUsage in
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }
                    if self.overlayState.isExpanded {
                        if showPeriodUsage {
                            self.viewModel.refreshUsageTotalsIfStale()
                        } else {
                            self.viewModel.disableUsageTotals()
                        }
                    } else if showPeriodUsage {
                        self.viewModel.pausePeriodicUsageRefresh()
                    } else {
                        self.viewModel.disableUsageTotals()
                    }
                    self.updateFrames()
                }
            }
            .store(in: &cancellables)

        viewModel.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateFrames()
                }
            }
            .store(in: &cancellables)

    }

    private func observeScreenChanges() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                self.synchronizeFramesForGeometryChange()
            }
            .store(in: &cancellables)
    }

    private func observeSystemActivity() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ] {
            notificationCenter.publisher(for: name)
                .sink { [weak self] _ in
                    Task { @MainActor in
                        self?.scheduleSystemActivityResume()
                    }
                }
                .store(in: &cancellables)
        }
    }

    private func scheduleSystemActivityResume() {
        systemActivityResumeTimer?.invalidate()
        let timer = Timer.scheduledTimer(
            withTimeInterval: SystemActivityRefreshCadence.debounceDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.systemActivityResumeTimer = nil
                self?.viewModel.resumeAfterSystemActivity()
            }
        }
        timer.tolerance = 0.25
        systemActivityResumeTimer = timer
    }

    private func installEventMonitors() {
        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor in
                self?.closeIfClickIsOutside()
            }
        }) {
            eventMonitors.append(globalMonitor)
        }

        if let localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    self?.overlayState.isExpanded = false
                }
                return nil
            }
            if self?.shouldSuppressTextInputShortcut(event) == true {
                return nil
            }
            return event
        }) {
            eventMonitors.append(localKeyMonitor)
        }

        if let localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            Task { @MainActor in
                self?.closeIfClickIsOutside()
                self?.restorePanelOrdering()
            }
            return event
        }) {
            eventMonitors.append(localMouseMonitor)
        }
    }

    private func closeIfClickIsOutside() {
        guard overlayState.isExpanded else {
            return
        }

        let location = NSEvent.mouseLocation
        if window.frame.contains(location)
            || detailWindow.frame.contains(location)
            || menuBarButtonFrame()?.contains(location) == true {
            return
        }
        overlayState.isExpanded = false
    }

    private func setDetailVisible(_ visible: Bool) {
        cancelPendingDetailWorkItems()

        guard let screen = currentDetailScreen() else {
            return
        }

        let previousPhase = detailTransition.phase
        let generation = detailTransition.begin(expanded: visible)
        if visible {
            showDetail(on: screen, previousPhase: previousPhase, generation: generation)
        } else {
            hideDetail(on: screen, generation: generation)
        }
    }

    private func showDetail(
        on screen: NSScreen,
        previousPhase: DetailPresentationPhase,
        generation: UInt
    ) {
        let frames = detailFrames(for: screen)
        latestDetailExpandedFrame = frames.expanded
        if previousPhase == .hidden || !detailWindow.isVisible {
            updateDetailContentSize(for: frames.expanded)
        }
        overlayState.setDetailPresentationPhase(.revealing)

        if previousPhase == .hidden || !detailWindow.isVisible {
            detailWindow.setFrame(frames.collapsed, display: false)
        }
        orderDetailWindowFront()

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            detailWindow.setFrame(frames.expanded, display: true)
            guard detailTransition.completeShow(generation: generation) else {
                return
            }
            overlayState.setDetailPresentationPhase(.visible)
            updateFrames()
            return
        }

        scheduleDetailWork(after: DetailAnimationTiming.contentDelay, generation: generation) { [weak self] in
            self?.overlayState.setDetailPresentationPhase(.visible)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = DetailAnimationTiming.revealDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            detailWindow.animator().setFrame(frames.expanded, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.detailTransition.isCurrent(generation) else {
                    return
                }
                self.settleDetailAfterReveal(
                    generation: generation,
                    currentTarget: frames.expanded
                )
            }
        }
    }

    private func hideDetail(on screen: NSScreen, generation: UInt) {
        overlayState.setDetailPresentationPhase(.hiding)
        let frames = detailFrames(for: screen)
        latestDetailExpandedFrame = frames.expanded

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            detailWindow.setFrame(frames.collapsed, display: false)
            guard detailTransition.completeHide(generation: generation) else {
                return
            }
            finishHidingDetail()
            return
        }

        scheduleDetailWork(after: DetailAnimationTiming.hideShellDelay, generation: generation) { [weak self] in
            guard let self else {
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = DetailAnimationTiming.hideDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.detailWindow.animator().setFrame(frames.collapsed, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self, self.detailTransition.completeHide(generation: generation) else {
                        return
                    }
                    self.finishHidingDetail()
                }
            }
        }
    }

    private func settleDetailAfterReveal(generation: UInt, currentTarget: NSRect) {
        guard detailTransition.isCurrent(generation), detailTransition.phase == .revealing else {
            return
        }

        let latestTarget = latestDetailExpandedFrame ?? currentTarget
        guard latestTarget != currentTarget else {
            updateDetailContentSize(for: latestTarget)
            guard detailTransition.completeShow(generation: generation) else {
                return
            }
            overlayState.setDetailPresentationPhase(.visible)
            return
        }

        updateDetailContentSize(for: latestTarget)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.detailSettleDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            detailWindow.animator().setFrame(latestTarget, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.detailTransition.isCurrent(generation) else {
                    return
                }
                self.settleDetailAfterReveal(
                    generation: generation,
                    currentTarget: latestTarget
                )
            }
        }
    }

    private func finishHidingDetail() {
        overlayState.setDetailPresentationPhase(.hidden)
        window.removeChildWindow(detailWindow)
        detailWindow.orderOut(nil)
        updateFrames()
    }

    private func scheduleDetailWork(
        after delay: TimeInterval,
        generation: UInt,
        action: @escaping @MainActor () -> Void
    ) {
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.detailTransition.isCurrent(generation) else {
                    return
                }
                action()
            }
        }
        pendingDetailWorkItems.append(workItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelPendingDetailWorkItems() {
        pendingDetailWorkItems.forEach { $0.cancel() }
        pendingDetailWorkItems.removeAll()
    }

    private func restorePanelOrdering() {
        guard overlayState.isExpanded else {
            return
        }
        orderDetailWindowFront()
    }

    private func updateFrames() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let petFrame = currentPetFrame(for: screen)
        let detailScreen = currentDetailScreen() ?? screen
        let detailFrames = detailFrames(
            for: detailScreen,
            layout: currentDetailPanelLayout()
        )

        window.setFrame(petFrame, display: true, animate: false)
        window.contentView?.frame = NSRect(origin: .zero, size: petFrame.size)
        latestDetailExpandedFrame = detailFrames.expanded
        switch detailTransition.phase {
        case .hidden:
            updateDetailContentSize(for: detailFrames.expanded)
            detailWindow.setFrame(detailFrames.collapsed, display: false)
        case .visible:
            updateDetailContentSize(for: detailFrames.expanded)
            detailWindow.setFrame(detailFrames.expanded, display: true)
        case .revealing, .hiding:
            break
        }
    }

    private func synchronizeFramesForGeometryChange() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        cancelPendingDetailWorkItems()
        let detailScreen = currentDetailScreen() ?? screen
        let frames = detailFrames(
            for: detailScreen,
            layout: currentDetailPanelLayout()
        )
        let petFrame = currentPetFrame(for: screen)

        window.setFrame(petFrame, display: true, animate: false)
        window.contentView?.frame = NSRect(origin: .zero, size: petFrame.size)
        latestDetailExpandedFrame = frames.expanded
        updateDetailContentSize(for: frames.expanded)

        let generation = detailTransition.begin(expanded: overlayState.isExpanded)
        if overlayState.isExpanded {
            detailWindow.setFrame(frames.expanded, display: true)
            orderDetailWindowFront()
            guard detailTransition.completeShow(generation: generation) else {
                return
            }
            overlayState.setDetailPresentationPhase(.visible)
        } else {
            detailWindow.setFrame(frames.collapsed, display: false)
            guard detailTransition.completeHide(generation: generation) else {
                return
            }
            overlayState.setDetailPresentationPhase(.hidden)
            window.removeChildWindow(detailWindow)
            detailWindow.orderOut(nil)
        }
    }

    private func detailFrames(
        for screen: NSScreen,
        layout: DetailPanelLayout? = nil
    ) -> DetailWindowFrames {
        let layout = layout ?? currentDetailPanelLayout()
        let detailHeight = currentDetailHeight(for: screen, layout: layout)
        if detailPresentationAnchor == .menuBar, let anchorFrame = menuBarButtonFrame() {
            return DetailWindowFrameCalculator.calculateBelowMenuBar(
                screenFrame: screen.visibleFrame,
                anchorFrame: anchorFrame,
                detailWidth: layout.width,
                detailHeight: detailHeight,
                overlap: DetailPanelMetrics.detailOverlap,
                gap: 6
            )
        }
        return DetailWindowFrameCalculator.calculateAbovePet(
            screenFrame: screen.visibleFrame,
            petFrame: currentPetFrame(for: screen),
            detailWidth: layout.width,
            detailHeight: detailHeight,
            overlap: DetailPanelMetrics.detailOverlap,
            gap: PetMetrics.detailGap
        )
    }

    private func currentDetailScreen() -> NSScreen? {
        if detailPresentationAnchor == .menuBar {
            return statusItem?.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        }
        return window.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func orderDetailWindowFront() {
        if detailPresentationAnchor == .menuBar {
            window.removeChildWindow(detailWindow)
            detailWindow.orderFrontRegardless()
        } else {
            if window.childWindows?.contains(detailWindow) != true {
                window.addChildWindow(detailWindow, ordered: .below)
            }
            detailWindow.order(.below, relativeTo: window.windowNumber)
            window.orderFrontRegardless()
        }
    }

    private func currentPetFrame(for screen: NSScreen) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let defaultOrigin = NSPoint(
            x: visibleFrame.maxX - PetMetrics.width - PetMetrics.screenMargin,
            y: visibleFrame.minY + PetMetrics.screenMargin
        )
        let requestedOrigin = petOrigin ?? defaultOrigin
        let clampedOrigin = NSPoint(
            x: min(visibleFrame.maxX - PetMetrics.width, max(visibleFrame.minX, requestedOrigin.x)),
            y: min(visibleFrame.maxY - PetMetrics.height, max(visibleFrame.minY, requestedOrigin.y))
        )
        petOrigin = clampedOrigin
        return NSRect(origin: clampedOrigin, size: NSSize(width: PetMetrics.width, height: PetMetrics.height))
    }

    private func dragPet(to pointer: NSPoint) {
        guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return
        }
        if petDragStartOrigin == nil {
            petDragStartOrigin = window.frame.origin
            petDragStartPointer = pointer
        }
        guard let startOrigin = petDragStartOrigin, let startPointer = petDragStartPointer else {
            return
        }
        petOrigin = NSPoint(
            x: startOrigin.x + pointer.x - startPointer.x,
            y: startOrigin.y + pointer.y - startPointer.y
        )
        let frame = currentPetFrame(for: screen)
        window.setFrame(frame, display: true, animate: false)
    }

    private func finishDraggingPet() {
        petDragStartOrigin = nil
        petDragStartPointer = nil
        updateFrames()
    }

    private func updateDetailContentSize(for expandedFrame: NSRect) {
        detailContentContainer?.updateContentSize(expandedFrame.size)
    }

    private func currentDetailPanelLayout() -> DetailPanelLayout {
        DetailPanelLayout(
            sideSectionWidth: DetailPanelMetrics.sideSectionWidth,
            contentWidth: DetailPanelMetrics.contentWidth,
            collapsedHeight: DetailPanelMetrics.collapsedHeight
        )
    }

    private func showSettings() {
        overlayState.isExpanded = false
        settingsController.show()
    }

    private func setMenuBarIconVisible(_ isVisible: Bool) {
        guard isVisible else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
                statusMenu = nil
                menuBarHostingView = nil
                petVisibilityMenuItem = nil
            }
            return
        }

        guard statusItem == nil else {
            return
        }

        let statusItem = NSStatusBar.system.statusItem(
            withLength: menuBarWidth(for: settings.menuBarLayout)
        )
        if let button = statusItem.button {
            let image = menuBarIconImage()
                ?? NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "codex-pet")
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            menuBarTemplateImage = image
            button.image = nil
            button.title = ""
            button.target = self
            button.action = #selector(handleMenuBarClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            let hostingView = PassThroughMenuBarHostingView(
                rootView: MenuBarQuotaView(
                    icon: image,
                    quota: MenuBarQuotaStatus(snapshot: viewModel.snapshot),
                    layout: settings.menuBarLayout
                )
            )
            hostingView.frame = button.bounds
            hostingView.autoresizingMask = [.width, .height]
            button.addSubview(hostingView)
            menuBarHostingView = hostingView
        }

        let menu = NSMenu()
        let petVisibilityItem = NSMenuItem(
            title: settings.petVisible ? "隐藏宠物" : "显示宠物",
            action: #selector(togglePetVisibilityFromMenuBar(_:)),
            keyEquivalent: ""
        )
        petVisibilityItem.target = self
        menu.addItem(petVisibilityItem)
        let settingsItem = NSMenuItem(title: "打开设置…", action: #selector(openSettingsFromMenuBar(_:)), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 codex-pet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        statusMenu = menu
        self.statusItem = statusItem
        petVisibilityMenuItem = petVisibilityItem
        updateMenuBarQuota(viewModel.snapshot)
    }

    private func updateMenuBarQuota(_ snapshot: UsageSnapshot) {
        let quota = MenuBarQuotaStatus(snapshot: snapshot)
        menuBarHostingView?.rootView = MenuBarQuotaView(
            icon: menuBarTemplateImage,
            quota: quota,
            layout: settings.menuBarLayout
        )
        statusItem?.length = menuBarWidth(for: settings.menuBarLayout)
        statusItem?.button?.toolTip = "codex-pet · 5h \(Formatters.percent(quota.fiveHourPercent)) · 7d \(Formatters.percent(quota.weeklyPercent))"
    }

    private func menuBarWidth(for layout: MenuBarLayout) -> CGFloat {
        let contentWidth = layout.visibleItems.reduce(CGFloat.zero) { width, item in
            width + (item == .pet ? 18 : 28)
        }
        let gaps = CGFloat(max(0, layout.visibleItems.count - 1)) * 7
        return max(30, contentWidth + gaps + 12)
    }

    private func menuBarIconImage() -> NSImage? {
        if let bundledURL = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let bundledImage = DownsampledImage.load(url: bundledURL, maxPixelSize: 36) {
            return bundledImage
        }

        let developmentURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/MenuBarIcon.png")
        return DownsampledImage.load(url: developmentURL, maxPixelSize: 36)
    }

    private func menuBarButtonFrame() -> NSRect? {
        guard let button = statusItem?.button, let buttonWindow = button.window else {
            return nil
        }
        let frameInWindow = button.convert(button.bounds, to: nil)
        return buttonWindow.convertToScreen(frameInWindow)
    }

    @objc private func handleMenuBarClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            overlayState.isExpanded = false
            statusMenu?.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.minY),
                in: sender
            )
            return
        }

        if overlayState.isExpanded, detailPresentationAnchor == .menuBar {
            overlayState.isExpanded = false
            return
        }

        detailPresentationAnchor = .menuBar
        if overlayState.isExpanded {
            updateFrames()
            orderDetailWindowFront()
        } else {
            overlayState.isExpanded = true
        }
    }

    @objc private func openSettingsFromMenuBar(_ sender: Any?) {
        showSettings()
    }

    @objc private func togglePetVisibilityFromMenuBar(_ sender: Any?) {
        settings.setPetVisible(!settings.petVisible)
    }

    private func applyPetVisibility(_ isVisible: Bool) {
        if isVisible {
            window.orderFrontRegardless()
        } else {
            cancelPendingDetailWorkItems()
            overlayState.isExpanded = false
            detailWindow.orderOut(nil)
            window.orderOut(nil)
            if !settings.showMenuBarIcon {
                settings.showMenuBarIcon = true
            }
        }
        petVisibilityMenuItem?.title = isVisible ? "隐藏宠物" : "显示宠物"
    }

    private func shouldSuppressTextInputShortcut(_ event: NSEvent) -> Bool {
        guard NSApp.keyWindow?.firstResponder is NSTextView else {
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return SettingsShortcutFilter.shouldSuppressTextInputKey(
            characters: event.characters,
            hasCommand: flags.contains(.command),
            hasControl: flags.contains(.control),
            hasOption: flags.contains(.option),
            hasShift: flags.contains(.shift)
        )
    }

    private func currentDetailHeight(
        for screen: NSScreen? = NSScreen.main ?? NSScreen.screens.first,
        layout: DetailPanelLayout? = nil
    ) -> CGFloat {
        let layout = layout ?? currentDetailPanelLayout()
        let safeAreaTop = ScreenSafeAreaGeometry.topSafeInset(for: screen)
        let topPadding = DetailPanelMetrics.detailContentTopPadding(
            safeAreaTop: safeAreaTop,
            collapsedHeight: layout.collapsedHeight
        )
        return DetailPanelMetrics.detailHeight(
            taskRows: DetailPanelMetrics.visibleTaskRows,
            showsPeriodUsage: settings.showPeriodUsage,
            topPadding: topPadding
        )
    }
}

@MainActor
final class SettingsWindowController {
    private let settings: CodexPetsSettings
    private let onRefresh: () -> Void
    private var window: NSWindow?

    init(
        settings: CodexPetsSettings,
        onRefresh: @escaping () -> Void
    ) {
        self.settings = settings
        self.onRefresh = onRefresh
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let view = SettingsView(
            settings: settings,
            onRefresh: onRefresh
        )
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 660),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "codex-pet设置"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        return window
    }
}
