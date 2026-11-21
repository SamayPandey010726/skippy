import SwiftUI

struct WorkspaceQuickLaunch: View {
  @ObservedObject var shelf: DropPopupController
  @ObservedObject private var tools = NotchToolStore.shared
  @ObservedObject private var skin = SkinStore.shared
  @FocusState private var focus: String?
  @State private var hovered: String?
  @State private var message = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 5), spacing: 6) {
          ForEach(Array(tools.quickLaunchApps.enumerated()), id: \.element.id) { index, app in
            appTile(app, index: index)
          }
          tile(id: "add", name: "Add Mac application") {
            tools.addQuickLaunchApp()
            shelf.focusForKeyboard()
          } icon: {
            Image(systemName: "plus").font(.system(size: 15, weight: .medium))
              .foregroundStyle(skin.skin.palette.accent)
          }
        }.padding(2)
      }
      let name = tools.quickLaunchApps.first { $0.id == (hovered ?? focus) }?.installedName
      Text(message.isEmpty ? (name ?? ((hovered ?? focus) == "add" ? "Add Mac application" : " ")) : message)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary).lineLimit(1).frame(height: 15)
    }
    .onReceive(tools.$status.dropFirst()) { message = $0 }
    .onChange(of: hovered) { _, _ in message = "" }
  }

  private func appTile(_ app: PinnedNotchApp, index: Int) -> some View {
    tile(id: app.id, name: app.installedName) {
      if app.installedURL == nil {
        tools.addQuickLaunchApp(replacing: app)
        shelf.focusForKeyboard()
      } else {
        tools.launch(app) {
          if shelf.activeModule == .launcher && !shelf.choosingArrow { shelf.dismiss() }
        }
      }
    } icon: {
      Image(nsImage: tools.icon(for: app)).resizable().scaledToFit().frame(width: 30, height: 30)
    }
    .contextMenu {
      Button("Move left") { tools.moveQuickLaunchApp(app, by: -1) }.disabled(index == 0)
      Button("Move right") { tools.moveQuickLaunchApp(app, by: 1) }.disabled(index == tools.quickLaunchApps.count - 1)
      Button("Choose replacement…") { tools.addQuickLaunchApp(replacing: app); shelf.focusForKeyboard() }
      Button("Remove shortcut") { tools.removeQuickLaunchApp(app) }
    }
  }

  private func tile<Icon: View>(id: String, name: String, action: @escaping () -> Void,
                                @ViewBuilder icon: () -> Icon) -> some View {
    let highlighted = hovered == id || focus == id
    let adding = id == "add"
    return Button(action: action) {
      icon().frame(maxWidth: .infinity).frame(height: 41)
        .background(skin.skin.palette.accent.opacity(highlighted ? 0.24 : adding ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
          if highlighted || adding {
            RoundedRectangle(cornerRadius: 9).strokeBorder(skin.skin.palette.accent.opacity(0.55), lineWidth: 1)
          }
        }
        .contentShape(Rectangle())
    }.buttonStyle(WorkspaceKeyStyle()).focused($focus, equals: id)
      .onHover { inside in
        if inside { hovered = id }
        else if hovered == id { hovered = nil }
      }
      .help(name).accessibilityLabel(name)
  }
}
