import AXSwift
import Cocoa
import Defaults
import LetsMove
import Settings
import Sparkle

extension Settings.PaneIdentifier {
  static let general = Self("general")
  static let excludes = Self("excludes")
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
  @IBOutlet var sparkle: SPUStandardUpdaterController!

  let statusItem = StatusItem()

  lazy var preferencesWindowController = SettingsWindowController(
    panes: [
      GeneralPreferencesController(),
      ExcludesViewController(),
    ], style: .segmentedControl
  )

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    PFMoveToApplicationsFolderIfNecessary()

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
    statusItem.handlePreferences = { self.preferencesWindowController.show() }

    let windowHandler = WindowHandler()
    let modifiers = Modifiers { windowHandler.intention = $0 }

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

    if Defaults[.showPrefsOnLaunch] {
      preferencesWindowController.show()
    }
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    // Insert code here to tear down your application
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    preferencesWindowController.show()
  }
}
