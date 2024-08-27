import Cocoa
import Defaults
import Settings

enum PlusMinusAction {
  static let plus = 0
  static let minus = 1
}

struct ExcludedApp {
  let path: String
  var basename: String {
    String(path.split(separator: "/").last!)
  }
  var icon: NSImage? {
    NSWorkspace.shared.icon(forFile: self.path)
  }
}

final class ExcludesViewController: NSViewController, SettingsPane {
  var paneIdentifier: Settings.PaneIdentifier = .excludes
  var paneTitle: String = "Excludes"

  override var nibName: NSNib.Name? { "Excludes" }

  @IBOutlet var tableView: NSTableView!
  @IBOutlet var plusMinusControl: NSSegmentedControl!

  var sortedApps: [ExcludedApp] = []

  override func viewDidLoad() {
    super.viewDidLoad()
    self.preferredContentSize = NSSize(width: 400, height: 428)

    Task {
      for await value in Defaults.updates(.excludedApplicationPaths) {
        self.sortedApps = Array(value).sorted().map { ExcludedApp(path: $0) }
        self.tableView.reloadData()
      }
    }

    tableView.registerForDraggedTypes([.fileURL])
  }

  @IBAction func plusMinusControlClicked(_ sender: Any) {
    switch plusMinusControl.selectedSegment {
    case PlusMinusAction.plus: showApplicationsPicker()
    case PlusMinusAction.minus: removeSelectedApps()
    default: assertionFailure("unknown plusMinusControl segment")
    }
  }

  private func removeSelectedApps() {
    var result = Defaults[.excludedApplicationPaths]
    for index in tableView.selectedRowIndexes {
      let app = sortedApps[index]
      result.remove(app.path)
    }
    Defaults[.excludedApplicationPaths] = result
  }

  private func showApplicationsPicker() {
    let openPanel = NSOpenPanel()
    openPanel.allowsMultipleSelection = true
    openPanel.canChooseDirectories = false
    openPanel.canChooseFiles = true
    openPanel.allowedFileTypes = ["app"]
    openPanel.directoryURL = URL(string: "/Applications")
    openPanel.resolvesAliases = true
    openPanel.begin { (result) in
      switch result {
      case .OK:
        self.addApplications(urls: openPanel.urls)
      default: break
      }
    }
  }

  private func addApplications(urls: [URL]) {
    let cleanPaths = urls.compactMap { cleanFilePath($0.absoluteString.removingPercentEncoding) }
    let joined = Defaults[.excludedApplicationPaths].union(cleanPaths)
    Defaults[.excludedApplicationPaths] = joined
  }

  private func cleanFilePath(_ maybeInput: String?) -> String? {
    guard let input = maybeInput else { return nil }

    let pattern = "^file://(.*)/?$"
    let matches = input.matchingStrings(regex: pattern)
    guard matches.count == 1, matches[0].count == 2 else { return nil }
    return matches[0][1]
  }
}

extension ExcludesViewController: NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    return sortedApps.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard
      let cell = tableView.makeView(withIdentifier: tableColumn!.identifier, owner: self)
        as? NSTableCellView
    else { return nil }
    let app = sortedApps[row]
    cell.textField?.stringValue = app.basename
    cell.imageView?.image = app.icon
    return cell
  }
}

extension ExcludesViewController: NSTableViewDelegate {
  func tableView(
    _ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
    dropOperation: NSTableView.DropOperation
  ) -> Bool {
    if let fileUrls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil)
      as? [URL]
    {
      addApplications(urls: fileUrls)
    }

    return true
  }

  func tableView(
    _ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
    proposedDropOperation dropOperation: NSTableView.DropOperation
  ) -> NSDragOperation {
    return .copy
  }
}
