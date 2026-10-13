import AppKit
import ParcelCore
import SwiftUI

struct PrepareSheet: View {
  @EnvironmentObject private var store: ParcelStore
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 23) {
      HStack {
        VStack(alignment: .leading, spacing: 7) {
          Text("A little finishing touch.").font(.custom(Ink.serif, size: 29)).foregroundStyle(
            Ink.green)
          Text(
            "Prepare \(store.imageItems.count) image \(store.imageItems.count == 1 ? "copy" : "copies"). Originals stay safe."
          ).font(.system(size: 12)).foregroundStyle(Ink.secondary)
        }
        Spacer()
        Image(systemName: "paperclip").font(.system(size: 25)).foregroundStyle(Ink.moss)
      }
      PaperCard {
        VStack(alignment: .leading, spacing: 19) {
          HStack {
            Text("Format").font(.system(size: 12, weight: .medium))
            Spacer()
            Picker("Format", selection: $store.recipe.format) {
              ForEach(ImageFormat.allCases, id: \.self) { Text($0.label).tag($0) }
            }.labelsHidden().frame(width: 175)
          }
          HStack {
            Text("Longest edge").font(.system(size: 12, weight: .medium))
            Spacer()
            Picker("Longest edge", selection: $store.recipe.maximumDimension) {
              Text("Original resolution").tag(0)
              Text("1200 pixels").tag(1200)
              Text("1600 pixels").tag(1600)
              Text("2400 pixels").tag(2400)
              Text("3200 pixels").tag(3200)
              Text("4000 pixels").tag(4000)
            }.labelsHidden().frame(width: 175)
          }
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Text("Quality").font(.system(size: 12, weight: .medium))
              Spacer()
              Text(
                store.recipe.format == .png ? "Lossless PNG" : "\(Int(store.recipe.quality*100))%"
              ).font(.system(size: 11, design: .monospaced)).foregroundStyle(Ink.secondary)
            }
            Slider(value: $store.recipe.quality, in: 0.1...1, step: 0.01).tint(Ink.moss).disabled(
              store.recipe.format == .png)
          }
          Divider().overlay(Ink.line)
          Toggle("Remove embedded metadata, including location", isOn: $store.recipe.removeMetadata)
            .font(.system(size: 11))
          Toggle(
            "Use a white background for transparent JPEGs", isOn: $store.recipe.flattenTransparency
          ).font(.system(size: 11))
        }.toggleStyle(.checkbox)
      }
      Text(
        "Smaller dimensions and lower JPEG/HEIC quality can reduce size. PNG stays lossless. Prepared copies use sRGB; compare the result before sending. Animated and multi-page images remain originals."
      ).font(.system(size: 11)).foregroundStyle(Ink.secondary).lineSpacing(4)
      HStack {
        Button("Cancel") { dismiss() }.buttonStyle(QuietButtonStyle())
        Spacer()
        Button {
          store.prepareImages()
        } label: {
          Label("Prepare copies", systemImage: "wand.and.stars")
        }.buttonStyle(MossButtonStyle()).disabled(store.imageItems.isEmpty || !store.canExport)
      }
    }.padding(30).frame(width: 505).background(Ink.paper).preferredColorScheme(.light)
  }
}
struct RenameSheet: View {
  var title: String
  var initial: String
  var caption: String
  var save: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var value = ""
  @FocusState private var focus: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(title).font(.custom(Ink.serif, size: 25)).foregroundStyle(Ink.green)
      Text(caption).font(.system(size: 12)).foregroundStyle(Ink.secondary)
      TextField("Name", text: $value).textFieldStyle(.roundedBorder).focused($focus).onSubmit {
        commit()
      }
      HStack {
        Button("Cancel") { dismiss() }.buttonStyle(QuietButtonStyle())
        Spacer()
        Button("Save name") { commit() }.buttonStyle(MossButtonStyle()).disabled(
          value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(30).frame(width: 440).background(Ink.paper).onAppear {
      value = initial
      focus = true
    }
  }
  private func commit() {
    save(value)
    dismiss()
  }
}
struct ImageComparisonView: View {
  var item: ParcelItem
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      Text("A closer look.").font(.custom(Ink.serif, size: 28)).foregroundStyle(Ink.green)
      HStack(alignment: .top, spacing: 20) {
        preview(url: item.sourceURL, title: "Original", bytes: item.byteCount)
        preview(url: item.effectiveURL, title: "Prepared copy", bytes: item.effectiveBytes)
      }
      HStack {
        Text(item.preparedDescription ?? "Prepared copy").font(.system(size: 12)).foregroundStyle(
          Ink.secondary)
        Spacer()
        Button("Open full size") {
          QuickLookController.shared.show([item.sourceURL, item.effectiveURL])
        }.buttonStyle(MossButtonStyle(secondary: true))
        Button("Done") { dismiss() }.buttonStyle(MossButtonStyle())
      }
    }.padding(30).frame(width: 700).background(Ink.paper).preferredColorScheme(.light)
  }
  private func preview(url: URL, title: String, bytes: Int64) -> some View {
    VStack(alignment: .leading, spacing: 11) {
      Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.green)
      FileThumbnail(url: url, size: 285, pixelLimit: 1600).frame(height: 250).background(
        Ink.cream, in: RoundedRectangle(cornerRadius: 12))
      Text(byteString(bytes)).font(.system(size: 11, design: .monospaced)).foregroundStyle(
        Ink.secondary)
    }
  }
}
