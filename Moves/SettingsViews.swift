import AppKit
import Defaults
import LaunchAtLogin
import Settings
import Sparkle
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsPane: View {
  @Default(.moveModifiers) private var moveModifiers
  @Default(.resizeModifiers) private var resizeModifiers
  @Default(.resizeFromClosestCorner) private var resizeFromClosestCorner
  @Default(.bringToFront) private var bringToFront
  @Default(.requireClick) private var requireClick
  @Default(.accessibilityEnabled) private var accessibilityEnabled
  @Default(.showSettingsOnLaunch) private var showSettingsOnLaunch
  @Default(.showInMenubar) private var showInMenubar

  @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
  @State private var automaticallyChecksForUpdates = false

  private let contentWidth: Double = 440

  var body: some View {
    Settings.Container(contentWidth: contentWidth) {
      Settings.Section(
        title: "Modifiers",
        bottomDivider: true,
        verticalAlignment: .top
      ) {
        Text("Hold these modifiers while moving your mouse to move or resize windows.")
          //          .settingDescription()
          .multilineTextAlignment(.leading)

        Spacer()

        VStack(alignment: .leading, spacing: 10) {
          ModifierRow(title: "Move", isDisabled: moveModifiers.isEmpty)
          ModifierSegments(modifiers: $moveModifiers)
            .frame(height: 24)
            .frame(maxWidth: 200, alignment: .leading)

          ModifierRow(title: "Resize", isDisabled: resizeModifiers.isEmpty)
          ModifierSegments(modifiers: $resizeModifiers)
            .frame(height: 24)
            .frame(maxWidth: 200, alignment: .leading)

          Spacer()

          Toggle("Require click before handling", isOn: $requireClick)

          Toggle("Bring window to front when handling", isOn: $bringToFront)
        }
      }

      Settings.Section(title: "Resizing mode", bottomDivider: true, verticalAlignment: .top) {
        LazyVGrid(
          columns: [
            GridItem(.fixed(ModeLayout.optionWidth), spacing: 24),
            GridItem(.fixed(ModeLayout.optionWidth)),
          ],
          alignment: .leading,
          spacing: 16
        ) {
          ModeOption(
            title: "Classic",
            isSelected: !resizeFromClosestCorner,
            isClosestMode: false
          ) {
            resizeFromClosestCorner = false
          }

          ModeOption(
            title: "Closest corner",
            isSelected: resizeFromClosestCorner,
            isClosestMode: true
          ) {
            resizeFromClosestCorner = true
          }
        }
        .padding(.horizontal, 8)
      }

      Settings.Section(title: "Accessibility", bottomDivider: true, verticalAlignment: .top) {
        HStack(spacing: 8) {
          Circle()
            .fill(accessibilityEnabled ? Color.green : Color.red)
            .frame(width: 8, height: 8)
          Text(accessibilityEnabled ? "Enabled" : "Not enabled")
        }

        Button("Open Accessibility Settings") {
          if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
          ) {
            NSWorkspace.shared.open(url)
          }
        }

        Text("Moves needs special permissions to work for other apps than itself.")
          .settingDescription()
      }

      Settings.Section(label: { Text("") }) {
        Toggle("Show this window on launch", isOn: $showSettingsOnLaunch)

        Toggle("Show Moves in the menubar", isOn: showInMenubarBinding)

        Toggle("Launch Moves at login", isOn: launchAtLoginBinding)

        Toggle("Check for updates", isOn: updatesBinding)
      }
    }
    .task {
      launchAtLoginEnabled = LaunchAtLogin.isEnabled
      if let updater = updater {
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
      }
    }
  }

  private var showInMenubarBinding: Binding<Bool> {
    Binding(
      get: { showInMenubar },
      set: { newValue in
        if !newValue && showInMenubar {
          showMenubarDisabledAlert()
        }
        showInMenubar = newValue
      }
    )
  }

  private var launchAtLoginBinding: Binding<Bool> {
    Binding(
      get: { launchAtLoginEnabled },
      set: { newValue in
        launchAtLoginEnabled = newValue
        LaunchAtLogin.isEnabled = newValue
      }
    )
  }

  private var updatesBinding: Binding<Bool> {
    Binding(
      get: { automaticallyChecksForUpdates },
      set: { newValue in
        automaticallyChecksForUpdates = newValue
        updater?.automaticallyChecksForUpdates = newValue
      }
    )
  }

  private var updater: SPUUpdater? {
    (NSApp.delegate as? AppDelegate)?.sparkle.updater
  }

  private func showMenubarDisabledAlert() {
    guard let window = (NSApp.delegate as? AppDelegate)?.settingsWindowController.window else {
      return
    }

    let alert = NSAlert()
    alert.messageText = "If you need to see this window again, launch the Moves app twice."
    alert.beginSheetModal(for: window, completionHandler: nil)
  }
}

struct ExcludesSettingsPane: View {
  @Default(.excludedApplicationPaths) private var excludedApplicationPaths
  @State private var selection = Set<String>()

  private let contentWidth: Double = 440

  var body: some View {
    Settings.Container(contentWidth: contentWidth) {
      Settings.Section(title: "Excluded apps", verticalAlignment: .top) {
        VStack(alignment: .leading, spacing: 8) {
          List(selection: $selection) {
            ForEach(sortedApps) { app in
              HStack(spacing: 8) {
                if let icon = app.icon {
                  Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                }
                Text(app.basename)
              }
            }
          }
          .frame(height: 220)

          HStack(spacing: 8) {
            Button {
              showApplicationsPicker()
            } label: {
              Image(systemName: "plus")
            }
            .buttonStyle(.borderless)

            Button {
              removeSelectedApps()
            } label: {
              Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .disabled(selection.isEmpty)
          }
        }
      }
    }
    .onChange(of: excludedApplicationPaths) { _ in
      selection = selection.filter { excludedApplicationPaths.contains($0) }
    }
  }

  private var sortedApps: [ExcludedAppItem] {
    excludedApplicationPaths
      .sorted()
      .map { ExcludedAppItem(path: $0) }
  }

  private func removeSelectedApps() {
    var result = excludedApplicationPaths
    selection.forEach { result.remove($0) }
    excludedApplicationPaths = result
  }

  private func showApplicationsPicker() {
    let openPanel = NSOpenPanel()
    openPanel.allowsMultipleSelection = true
    openPanel.canChooseDirectories = false
    openPanel.canChooseFiles = true
    openPanel.allowedContentTypes = [UTType.application]
    openPanel.directoryURL = URL(fileURLWithPath: "/Applications")
    openPanel.resolvesAliases = true
    openPanel.begin { result in
      switch result {
      case .OK:
        let cleanPaths = openPanel.urls.map { $0.path }
        excludedApplicationPaths = excludedApplicationPaths.union(cleanPaths)
      default:
        break
      }
    }
  }
}

private struct ModifierRow: View {
  let title: String
  let isDisabled: Bool

  var body: some View {
    HStack(spacing: 8) {
      Text(title)
        .fontWeight(.semibold)

      if isDisabled {
        Text("Disabled")
          .foregroundColor(.orange)
          .font(.system(size: 13, weight: .semibold))
      }
    }
  }
}

private struct ModeOption: View {
  let title: String
  let isSelected: Bool
  let isClosestMode: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        ResizeModePreview(isClosestMode: isClosestMode)
          .frame(width: ModeLayout.optionWidth, height: 90)

        HStack(spacing: 6) {
          Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
            .foregroundColor(isSelected ? .accentColor : .secondary)
          Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
        }
      }
      .frame(width: ModeLayout.optionWidth)
    }
    .contentShape(Rectangle())
    .buttonStyle(.plain)
  }
}

private enum ModeLayout {
  static let optionWidth: CGFloat = 130
}

private struct ResizeModePreview: NSViewRepresentable {
  let isClosestMode: Bool

  func makeNSView(context: Context) -> ResizeModePreviewView {
    let view = ResizeModePreviewView(frame: .zero)
    view.isClosestMode = isClosestMode
    return view
  }

  func updateNSView(_ nsView: ResizeModePreviewView, context: Context) {
    nsView.isClosestMode = isClosestMode
  }
}

private struct ModifierSegments: NSViewRepresentable {
  @Binding var modifiers: Set<Modifier>

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSSegmentedControl {
    let control = NSSegmentedControl(
      labels: labels, trackingMode: .selectAny, target: nil, action: nil)
    control.segmentStyle = .rounded
    control.target = context.coordinator
    control.action = #selector(Coordinator.selectionChanged(_:))
    applySelection(to: control)
    return control
  }

  func updateNSView(_ nsView: NSSegmentedControl, context: Context) {
    applySelection(to: nsView)
  }

  private func applySelection(to control: NSSegmentedControl) {
    modifiersByIndex.enumerated().forEach { index, modifier in
      control.setSelected(modifiers.contains(modifier), forSegment: index)
    }
  }

  private var labels: [String] {
    ["⌘", "⌥", "⌃", "⇧", "fn"]
  }

  private var modifiersByIndex: [Modifier] {
    [.command, .option, .control, .shift, .fn]
  }

  final class Coordinator: NSObject {
    private let parent: ModifierSegments

    init(_ parent: ModifierSegments) {
      self.parent = parent
    }

    @objc func selectionChanged(_ sender: NSSegmentedControl) {
      var newModifiers = Set<Modifier>()
      parent.modifiersByIndex.enumerated().forEach { index, modifier in
        if sender.isSelected(forSegment: index) {
          newModifiers.insert(modifier)
        }
      }
      parent.modifiers = newModifiers
    }
  }
}

private struct ExcludedAppItem: Identifiable {
  let path: String

  var id: String { path }

  var basename: String {
    URL(fileURLWithPath: path).lastPathComponent
  }

  var icon: NSImage? {
    NSWorkspace.shared.icon(forFile: path)
  }
}

#if DEBUG
  struct SettingsViews_Previews: PreviewProvider {
    static var previews: some View {
      Group {
        GeneralSettingsPane()
          .previewDisplayName("General")
        ExcludesSettingsPane()
          .previewDisplayName("Excludes")
      }
      .frame(width: 520)
      .preferredColorScheme(.dark)
    }
  }
#endif
