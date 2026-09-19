import Cocoa

class StatusItem {
  var statusItem: NSStatusItem?

  var handleSettings: (() -> Void)?
  var handleCheckForUpdates: (() -> Void)?

  func enable() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    guard let item = statusItem else {
      print("No status item")
      return
    }

    if let menubarButton = item.button {
      menubarButton.image = NSImage(named: NSImage.Name("Menubar Icon"))
    }

    let menu = NSMenu()

    let settingsItem = NSMenuItem(
      title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
    settingsItem.target = self
    menu.addItem(settingsItem)

    let updatesItem = NSMenuItem(
      title: "Check for updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    updatesItem.target = self
    menu.addItem(updatesItem)

    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    let aboutItem = NSMenuItem(
      title: "About Moves \(version)", action: #selector(openRepo), keyEquivalent: "")
    aboutItem.target = self
    menu.addItem(aboutItem)

    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      NSMenuItem(
        title: "Quit Moves", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

    item.menu = menu
  }

  func disable() {
    guard let item = statusItem else { return }
    NSStatusBar.system.removeStatusItem(item)
  }

  @objc func showSettings() {
    handleSettings?()
  }

  @objc func checkForUpdates() {
    handleCheckForUpdates?()
  }

  @objc func openRepo() {
    NSWorkspace.shared.open(URL(string: "https://github.com/mikker/Moves.app")!)
  }
}
