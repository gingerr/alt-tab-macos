import Cocoa
import Darwin
import LetsMove
import ShortcutRecorder

let cgsMainConnectionId = CGSMainConnectionID()

class App: NSApplication, NSApplicationDelegate {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
    static let licence = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as! String
    static let repository = "https://github.com/lwouis/alt-tab-macos"
    static var app: App!
    static let shortcutMonitor = LocalShortcutMonitor()
    var statusItem: NSStatusItem?
    var thumbnailsPanel: ThumbnailsPanel?
    var preferencesWindow: PreferencesWindow?
    var feedbackWindow: FeedbackWindow?
    var uiWorkShouldBeDone = true
    var isFirstSummon = true
    var appIsBeingUsed = false

    override init() {
        super.init()
        delegate = self
        App.app = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        #if !DEBUG
        PFMoveToApplicationsFolderIfNecessary()
        #endif
        SystemPermissions.ensureAccessibilityCheckboxIsChecked()
        SystemPermissions.ensureScreenRecordingCheckboxIsChecked()
        Preferences.migrateOldPreferences()
        Preferences.registerDefaults()
        statusItem = Menubar.make()
        loadMainMenuXib()
        thumbnailsPanel = ThumbnailsPanel()
        Spaces.initialDiscovery()
        Applications.initialDiscovery()
        Keyboard.listenToGlobalEvents()
        preferencesWindow = PreferencesWindow()
        UpdatesTab.observeUserDefaults()
        // TODO: undeterministic; events in the queue may still be processing; good enough for now
        DispatchQueue.main.async { Windows.sortByLevel() }
    }

    // keyboard shortcuts are broken without a menu. We generated the default menu from XCode and load it
    // see https://stackoverflow.com/a/3746058/2249756
    private func loadMainMenuXib() {
        var menuObjects: NSArray?
        Bundle.main.loadNibNamed("MainMenu", owner: self, topLevelObjects: &menuObjects)
        menu = menuObjects?.first(where: { $0 is NSMenu }) as? NSMenu
    }

    // we put application code here which should be executed on init() and Preferences change
    func resetPreferencesDependentComponents() {
        ThumbnailsView.recycledViews = ThumbnailsView.recycledViews.map { _ in ThumbnailView() }
        thumbnailsPanel!.thumbnailsView.layer!.cornerRadius = Preferences.windowCornerRadius
    }

    func hideUi() {
        debugPrint("hideUi")
        thumbnailsPanel!.orderOut(nil)
        appIsBeingUsed = false
        isFirstSummon = true
    }

    func focusTarget() {
        debugPrint("focusTarget")
        focusSelectedWindow(Windows.focusedWindow())
    }

    @objc
    func checkForUpdatesNow(_ sender: NSMenuItem) {
        UpdatesTab.checkForUpdatesNow(sender)
    }

    @objc
    func showPreferencesPanel() {
        Screen.repositionPanel(preferencesWindow!, Screen.preferred(), .appleCentered)
        preferencesWindow?.show()
    }

    @objc
    func showFeedbackPanel() {
        if feedbackWindow == nil {
            feedbackWindow = FeedbackWindow()
        }
        Screen.repositionPanel(feedbackWindow!, Screen.preferred(), .appleCentered)
        feedbackWindow?.show()
    }

    @objc
    func showUi() {
        uiWorkShouldBeDone = true
        appIsBeingUsed = true
        DispatchQueue.main.async { self.showUiOrCycleSelection(0) }
    }

    func cycleSelection(_ step: Int) {
        Windows.cycleFocusedWindowIndex(step)
    }

    func focusSelectedWindow(_ window: Window?) {
        hideUi()
        guard !CGWindow.isMissionControlActive() else { return }
        window?.focus()
    }

    func reopenUi() {
        thumbnailsPanel!.orderOut(nil)
        rebuildUi()
    }

    func refreshOpenUi(_ windowsToRefresh: [Window]? = nil) {
        guard appIsBeingUsed else { return }
        windowsToRefresh?.forEach { $0.refreshThumbnail() }
        guard uiWorkShouldBeDone else { return }
        // workaround: when Preferences > Mission Control > "Displays have separate Spaces" is unchecked,
        // switching between displays doesn't trigger .activeSpaceDidChangeNotification; we get the latest manually
        Spaces.refreshCurrentSpaceId()
        guard uiWorkShouldBeDone else { return }
        let currentScreen = Screen.preferred() // fix screen between steps since it could change (e.g. mouse moved to another screen)
        thumbnailsPanel!.thumbnailsView.updateItems(currentScreen)
        guard uiWorkShouldBeDone else { return }
        thumbnailsPanel!.setFrame(thumbnailsPanel!.thumbnailsView.frame, display: false)
        guard uiWorkShouldBeDone else { return }
        Screen.repositionPanel(thumbnailsPanel!, currentScreen, .appleCentered)
    }

    func showUiOrCycleSelection(_ step: Int) {
        debugPrint("showUiOrCycleSelection", step)
        if isFirstSummon {
            debugPrint("showUiOrCycleSelection: isFirstSummon")
            isFirstSummon = false
            if Windows.list.count == 0 || CGWindow.isMissionControlActive() { hideUi(); return }
            // TODO: find a way to update isSingleSpace by listening to space creation, instead of on every trigger
            Spaces.idsAndIndexes = Spaces.allIdsAndIndexes()
            // TODO: find a way to update space index when windows are moved to another space, instead of on every trigger
            Windows.updateSpaces()
            let screen = Screen.preferred()
            Windows.refreshWhichWindowsToShowTheUser(screen)
            if Windows.list.first(where: { $0.shouldShowTheUser }) == nil { hideUi(); return }
            Windows.updateFocusedWindowIndex(0)
            Windows.cycleFocusedWindowIndex(step)
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Preferences.windowDisplayDelay) {
                self.rebuildUi()
            }
        } else {
            cycleSelection(step)
        }
    }

    func rebuildUi() {
        guard uiWorkShouldBeDone else { return }
        Windows.refreshAllThumbnails()
        guard uiWorkShouldBeDone else { return }
        refreshOpenUi()
        guard uiWorkShouldBeDone else { return }
        thumbnailsPanel!.show()
//        guard uiWorkShouldBeDone else { return }
//        DispatchQueue.main.async {
//            Windows.refreshAllExistingThumbnails()
//        }
    }
}
