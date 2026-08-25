import AXSwift
import Cocoa
import Defaults
import Settings
import Sparkle

extension Settings.PaneIdentifier {
  static let general = Self("general")
  static let excludes = Self("excludes")
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  let sparkle = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
  )

  let statusItem = StatusItem()
  let windowHandler = WindowHandler()

  lazy var settingsWindowController = SettingsWindowController(
    panes: [
      Settings.Pane(
        identifier: .general,
        title: "General",
        toolbarIcon: settingsIcon(named: "gearshape")
      ) {
        GeneralSettingsPane()
      },
      Settings.Pane(
        identifier: .excludes,
        title: "Excludes",
        toolbarIcon: settingsIcon(named: "nosign")
      ) {
        ExcludesSettingsPane()
      },
    ],
    style: .segmentedControl
  )

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    setupMainMenu()
    setSettingsActivation(active: false)

    Task {
      for await value in Defaults.updates(.showInMenubar) {
        if value {
          self.statusItem.enable()
        } else {
          self.statusItem.disable()
        }
      }
    }

    statusItem.handleCheckForUpdates = { self.sparkle.checkForUpdates(nil) }
    statusItem.handleSettings = { self.showSettingsWindow() }

    let modifiers = Modifiers { self.windowHandler.intention = $0 }

    Task {
      for await value in Defaults.updates(.accessibilityEnabled) {
        if value {
          modifiers.observe()
        } else {
          modifiers.remove()
        }
      }
    }

    DistributedNotificationCenter.default.addObserver(
      forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: nil
    ) { _ in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        Defaults[.accessibilityEnabled] = AXSwift.checkIsProcessTrusted()
      }
    }

    Defaults[.accessibilityEnabled] = AXSwift.checkIsProcessTrusted(prompt: true)

    if Defaults[.showSettingsOnLaunch] {
      showSettingsWindow()
    }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    showSettingsWindow()
    return false
  }

  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    if window == settingsWindowController.window {
      setSettingsActivation(active: false)
    }
  }

  private func showSettingsWindow() {
    guard !isRunningForPreviews else { return }
    setSettingsActivation(active: true)
    NSApp.activate(ignoringOtherApps: true)
    settingsWindowController.window?.delegate = self
    sanitizeSettingsWindowAutosave()
    settingsWindowController.show()
  }

  private func setSettingsActivation(active: Bool) {
    _ = NSApp.setActivationPolicy(active ? .regular : .accessory)
  }

  private var isRunningForPreviews: Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
  }

  private var registeredURLSchemes: Set<String> {
    guard let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else { return [] }
    return Set(urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] })
  }

  private func applyToURLTarget(_ operation: (AccessibilityElement) -> Void) {
    guard let application = ActiveWindow.getFrontmostApplication(
      excluding: ProcessInfo.processInfo.processIdentifier),
      let window = ActiveWindow.getMainWindow(of: application)
    else { return }

    operation(window)
    DispatchQueue.main.async {
      application.activate()
    }
  }

  private func sanitizeSettingsWindowAutosave() {
    let key = "NSWindow Frame com.sindresorhus.Settings.FrameAutosaveName"
    guard let stored = UserDefaults.standard.string(forKey: key) else { return }
    guard !stored.contains("{") else { return }
    UserDefaults.standard.removeObject(forKey: key)
  }

  private func settingsIcon(named systemName: String) -> NSImage {
    NSImage(systemSymbolName: systemName, accessibilityDescription: nil) ?? NSImage()
  }

  // MARK: - Main Menu

  private func setupMainMenu() {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)

    let appMenu = NSMenu()
    appMenuItem.submenu = appMenu

    let appName = ProcessInfo.processInfo.processName

    appMenu.addItem(
      withTitle: "About \(appName)",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
      keyEquivalent: "")

    appMenu.addItem(.separator())

    let settingsItem = NSMenuItem(
      title: "Settings…",
      action: #selector(openSettingsFromMenu),
      keyEquivalent: ",")
    settingsItem.target = self
    appMenu.addItem(settingsItem)

    appMenu.addItem(.separator())

    appMenu.addItem(
      withTitle: "Hide \(appName)",
      action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h")

    let hideOthers = NSMenuItem(
      title: "Hide Others",
      action: #selector(NSApplication.hideOtherApplications(_:)),
      keyEquivalent: "h")
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(hideOthers)

    appMenu.addItem(
      withTitle: "Show All",
      action: #selector(NSApplication.unhideAllApplications(_:)),
      keyEquivalent: "")

    appMenu.addItem(.separator())

    appMenu.addItem(
      withTitle: "Quit \(appName)",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")

    NSApp.mainMenu = mainMenu
  }

  @objc private func openSettingsFromMenu() {
    showSettingsWindow()
  }

  // MARK: - URLs

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      handleURL(url)
    }
  }

  private func handleURL(_ url: URL) {
    guard let scheme = url.scheme, registeredURLSchemes.contains(scheme) else { return }

    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let host = url.host
    else { return }

    let queryItems = components.queryItems ?? []

    switch host {
    case "template":
      let templateName = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      guard !templateName.isEmpty else { return }

      guard let templateType = TemplateType(rawValue: templateName) else { return }
      applyToURLTarget { ActiveWindow.applyTemplate(templateType, to: $0) }

    case "custom":
      let positionString: String
      let command = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

      if let positionParam = queryItems.first(where: { $0.name == "position" })?.value,
        !positionParam.isEmpty
      {
        positionString = positionParam
      } else if !command.isEmpty {
        positionString = command
      } else {
        positionString = "topLeft"
      }

      let position: WindowPosition
      if let validPosition = WindowPosition(rawValue: positionString) {
        position = validPosition
      } else {
        position = .topLeft
      }

      let screenRect = NSScreen.main?.visibleFrame ?? .zero

      var width: CGFloat? = nil
      if let absoluteWidth = queryItems.first(where: { $0.name == "absoluteWidth" })?.value.flatMap(
        { CGFloat(Double($0) ?? 0) }),
        absoluteWidth > 0
      {
        width = absoluteWidth
      } else if let relativeWidth = queryItems.first(where: { $0.name == "relativeWidth" })?.value
        .flatMap({ Double($0) }),
        relativeWidth > 0
      {
        width = CGFloat(relativeWidth) * screenRect.width
      }

      var height: CGFloat? = nil
      if let absoluteHeight = queryItems.first(where: { $0.name == "absoluteHeight" })?.value
        .flatMap({ CGFloat(Double($0) ?? 0) }),
        absoluteHeight > 0
      {
        height = absoluteHeight
      } else if let relativeHeight = queryItems.first(where: { $0.name == "relativeHeight" })?.value
        .flatMap({ Double($0) }),
        relativeHeight > 0
      {
        height = CGFloat(relativeHeight) * screenRect.height
      }

      var xOffset: CGFloat = 0
      if let absoluteXOffset = queryItems.first(where: { $0.name == "absoluteXOffset" })?.value
        .flatMap({ CGFloat(Double($0) ?? 0) })
      {
        xOffset = absoluteXOffset
      } else if let relativeXOffset = queryItems.first(where: { $0.name == "relativeXOffset" })?
        .value.flatMap({ Double($0) })
      {
        xOffset = CGFloat(relativeXOffset) * screenRect.width
      }

      var yOffset: CGFloat = 0
      if let absoluteYOffset = queryItems.first(where: { $0.name == "absoluteYOffset" })?.value
        .flatMap({ CGFloat(Double($0) ?? 0) })
      {
        yOffset = absoluteYOffset
      } else if let relativeYOffset = queryItems.first(where: { $0.name == "relativeYOffset" })?
        .value.flatMap({ Double($0) })
      {
        yOffset = CGFloat(relativeYOffset) * screenRect.height
      }

      applyToURLTarget {
        ActiveWindow.position(
          position,
          window: $0,
          width: width,
          height: height,
          xOffset: xOffset,
          yOffset: yOffset
        )
      }

    default:
      break
    }
  }
}
