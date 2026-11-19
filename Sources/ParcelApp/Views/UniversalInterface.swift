import SwiftUI

struct UniversalInterface<Content: View>: View {
  @ObservedObject private var courier = DropPopupController.shared
  var content: Content
  init(@ViewBuilder content: () -> Content) { self.content = content() }
  var body: some View {
    GeometryReader { geometry in
      content.frame(width: geometry.size.width / courier.interfaceScale, height: geometry.size.height / courier.interfaceScale)
        .scaleEffect(courier.interfaceScale, anchor: .topLeading)
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
    }.onChange(of: courier.interfaceScale) { _, _ in AppController.shared.fitInterfaceWindows() }
  }
}
