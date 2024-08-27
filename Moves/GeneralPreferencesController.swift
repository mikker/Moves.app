import Cocoa
import Defaults
import LaunchAtLogin
import Settings
import Sparkle

enum Segment {
  static let command = 0
  static let option = 1
  static let control = 2
  static let shift = 3
  static let fn = 4
}

class GeneralPreferencesController: NSViewController, SettingsPane {
  var paneIdentifier: Settings.PaneIdentifier = .general
  var paneTitle: String = "General"

  override var nibName: NSNib.Name? { "General" }

  @IBOutlet var moveDisabledLabel: NSTextField!
  @IBOutlet var moveModifiersControl: NSSegmentedControl!

  @IBOutlet var resizeDisabledLabel: NSTextField!
  @IBOutlet var resizeModifiersControl: NSSegmentedControl!

  @IBOutlet var bringToFrontCheckbox: NSButton!

  @IBOutlet var accessibilityStatusButton: NSButton!
  @IBOutlet var accessibilityPrefsButton: NSButton!

  @IBOutlet var showPrefsOnLaunch: NSButton!
  @IBOutlet var showInMenubar: NSButton!
  @IBOutlet var launchAtLoginCheckbox: NSButton!
  @IBOutlet var checkForUpdatesCheckbox: NSButton!

  override func viewDidLoad() {
    super.viewDidLoad()

    self.preferredContentSize = NSSize(width: 400, height: 434)

    Task {
      for await value in Defaults.updates(.moveModifiers) {
        value.forEach { (mod) in
          switch mod {
          case .command: self.moveModifiersControl.setSelected(true, forSegment: Segment.command)
          case .option: self.moveModifiersControl.setSelected(true, forSegment: Segment.option)
          case .control: self.moveModifiersControl.setSelected(true, forSegment: Segment.control)
          case .shift: self.moveModifiersControl.setSelected(true, forSegment: Segment.shift)
          case .fn: self.moveModifiersControl.setSelected(true, forSegment: Segment.fn)
          }
        }

        self.moveDisabledLabel.isHidden = !value.isEmpty
      }
    }

    Task {
      for await value in Defaults.updates(.resizeModifiers) {
        value.forEach { (mod) in
          switch mod {
          case .command: self.resizeModifiersControl.setSelected(true, forSegment: Segment.command)
          case .option: self.resizeModifiersControl.setSelected(true, forSegment: Segment.option)
          case .control: self.resizeModifiersControl.setSelected(true, forSegment: Segment.control)
          case .shift: self.resizeModifiersControl.setSelected(true, forSegment: Segment.shift)
          case .fn: self.moveModifiersControl.setSelected(true, forSegment: Segment.fn)
          }
        }

        self.resizeDisabledLabel.isHidden = !value.isEmpty
      }
    }

    Task {
      for await value in Defaults.updates(.bringToFront) {
        self.bringToFrontCheckbox.state = value ? .on : .off
      }
    }

    Task {
      for await value in Defaults.updates(.accessibilityEnabled) {
        if value {
          self.accessibilityStatusButton.image = NSImage(named: NSImage.statusAvailableName)
          self.accessibilityStatusButton.title = "Enabled"
        } else {
          self.accessibilityStatusButton.image = NSImage(
            named: NSImage.statusUnavailableName)
          self.accessibilityStatusButton.title = "Not enabled"
        }
      }
    }

    Task {
      for await value in Defaults.updates(.showPrefsOnLaunch) {
        self.showPrefsOnLaunch.state = value ? .on : .off
      }
    }

    Task {
      for await value in Defaults.updates(.showInMenubar) {
        self.showInMenubar.state = value ? .on : .off
      }
    }

    launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
    if let updater = (NSApplication.shared.delegate as? AppDelegate)?.sparkle.updater {
      checkForUpdatesCheckbox.state = updater.automaticallyChecksForUpdates ? .on : .off
    }
  }

  @IBAction func moveModifiersChanged(_ sender: Any) {
    var mods: Set<Modifier> = Set()
    if moveModifiersControl.isSelected(forSegment: Segment.command) { mods.insert(.command) }
    if moveModifiersControl.isSelected(forSegment: Segment.option) { mods.insert(.option) }
    if moveModifiersControl.isSelected(forSegment: Segment.control) { mods.insert(.control) }
    if moveModifiersControl.isSelected(forSegment: Segment.shift) { mods.insert(.shift) }
    if moveModifiersControl.isSelected(forSegment: Segment.fn) { mods.insert(.fn) }
    Defaults[.moveModifiers] = mods
  }

  @IBAction func resizeModifiersChanged(_ sender: Any) {
    var mods: Set<Modifier> = Set()
    if resizeModifiersControl.isSelected(forSegment: Segment.command) { mods.insert(.command) }
    if resizeModifiersControl.isSelected(forSegment: Segment.option) { mods.insert(.option) }
    if resizeModifiersControl.isSelected(forSegment: Segment.control) { mods.insert(.control) }
    if resizeModifiersControl.isSelected(forSegment: Segment.shift) { mods.insert(.shift) }
    if resizeModifiersControl.isSelected(forSegment: Segment.fn) { mods.insert(.fn) }
    Defaults[.resizeModifiers] = mods
  }

  @IBAction func activateOnHandleClicked(_ sender: Any) {
    Defaults[.bringToFront] = bringToFrontCheckbox.state == .on
  }

  @IBAction func showPrefsOnLaunchClicked(_ sender: Any) {
    let state = self.showPrefsOnLaunch.state == .on
    Defaults[.showPrefsOnLaunch] = state
  }

  @IBAction func showInMenubarClicked(_ sender: Any) {
    let state = self.showInMenubar.state == .on

    if !state && Defaults[.showInMenubar] {
      if let window = (NSApp.delegate as? AppDelegate)?.preferencesWindowController.window {
        let alert = NSAlert()
        alert.messageText = "If you need to see this window again, launch the Moves app twice."
        alert.beginSheetModal(for: window, completionHandler: nil)
      }
    }

    Defaults[.showInMenubar] = state
  }

  @IBAction func launchAtLoginCheckboxClicked(_ sender: Any) {
    let state = self.launchAtLoginCheckbox.state == .on
    LaunchAtLogin.isEnabled = state
  }

  @IBAction func checkForUpdatesCheckboxClicked(_ sender: Any) {
    let state = self.launchAtLoginCheckbox.state == .on
    if let updater = (NSApplication.shared.delegate as? AppDelegate)?.sparkle.updater {
      updater.automaticallyChecksForUpdates = state
    }
  }

  @IBAction func accessibilityPrefsButtonClicked(_ sender: Any) {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      NSWorkspace.shared.open(url)
    }
  }
}
