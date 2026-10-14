import SwiftUI

/// Skin picker: three looks, one shelf. Same geometry and behaviour —
/// only the palette and illustration change.
struct SkinPickerRow: View {
  @StateObject private var skinStore = SkinStore.shared
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Shelf skin").font(.system(size: 11)).foregroundStyle(Ink.secondary)
      HStack(spacing: 10) {
        ForEach(ParcelSkin.allCases) { skin in
          Button {
            skinStore.skin = skin
          } label: {
            VStack(spacing: 6) {
              RoundedRectangle(cornerRadius: 10)
                .fill(skin.palette.paper)
                .overlay(
                  RoundedRectangle(cornerRadius: 10)
                    .stroke(
                      skinStore.skin == skin ? skin.palette.accent : skin.palette.line,
                      lineWidth: skinStore.skin == skin ? 2 : 1))
                .frame(height: 44)
                .overlay(
                  Image(systemName: "bag.fill").font(.system(size: 16))
                    .foregroundStyle(skin.palette.accent))
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
