import SwiftUI

struct WelcomeView: View {
  @EnvironmentObject private var store: ParcelStore
  var body: some View {
    VStack(spacing: 18) {
      BrandMark().padding(.top, 8)
      ZStack {
        GardenBackdrop()
        ParcelIllustration(sealed: false, count: 3, bounce: 0)
      }.frame(height: 245)
      Text("Drop a few files.").font(.custom(Ink.serif, size: 30)).foregroundStyle(
        Ink.green)
      Text(
        "Gather files from anywhere into one little box.\nPrepare your images, seal a ZIP, and send it on its way."
      ).font(.system(size: 13)).foregroundStyle(Ink.secondary).multilineTextAlignment(.center)
        .lineSpacing(5)
      HStack(spacing: 26) {
        tip("plus", "Gather")
        tip("wand.and.stars", "Prepare")
        tip("envelope", "Pack")
        tip("paperplane", "Send")
      }.padding(.vertical, 13)
      Button("Let's pack something") { store.finishWelcome() }.buttonStyle(MossButtonStyle())
      Text("Originals stay safe. Everything is prepared on your Mac.").font(.system(size: 10))
        .foregroundStyle(Ink.secondary).padding(.bottom, 8)
    }.padding(28).frame(width: 515).background(Ink.paper).preferredColorScheme(.light)
  }
  private func tip(_ icon: String, _ label: String) -> some View {
    VStack(spacing: 7) {
      Image(systemName: icon).font(.system(size: 16, weight: .light))
      Text(label).font(.system(size: 10))
    }.foregroundStyle(Ink.moss)
  }
}
