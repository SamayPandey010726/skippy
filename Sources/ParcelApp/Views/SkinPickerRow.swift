import SwiftUI

/// Skin picker: three looks, one shelf. Same geometry and behaviour —
/// only the palette and illustration change.
struct SkinPickerRow: View {
  @StateObject private var skinStore = SkinStore.shared
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Theme").font(.system(size: 11, weight: .medium)).foregroundStyle(Ink.secondary)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
        ForEach(ParcelSkin.allCases) { skin in
          Button {
            skinStore.skin = skin
          } label: {
            VStack(spacing: 5) {
              RoundedRectangle(cornerRadius: 10)
                .fill(skin.palette.paper)
                .overlay(
                  RoundedRectangle(cornerRadius: 10)
                    .stroke(
                      skinStore.skin == skin ? skin.palette.accent : skin.palette.line,
                      lineWidth: skinStore.skin == skin ? 2 : 1))
                .frame(height: 58)
                .overlay(
                  CourierSatchel(count: 2, skin: skin).frame(width: 62, height: 54))
              Text(skin.name).font(.system(size: 10, weight: .medium))
                .foregroundStyle(Ink.text)
            }
          }.buttonStyle(.plain)
            .help(skin.blurb)
        }
      }
      Text(skinStore.skin.blurb).font(.system(size: 10)).foregroundStyle(Ink.secondary)
    }
  }
}
