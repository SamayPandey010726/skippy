import SwiftUI
import ParcelCore

struct MediaPreparationView: View {
  @EnvironmentObject private var store: ParcelStore
  @ObservedObject private var presets = TransformPresetStore.shared
  var close: () -> Void
  var body: some View {
    ScrollView {
    VStack(alignment: .leading, spacing: 14) {
      HStack { Text("Prepare copies").font(.headline); Spacer(); Button("Back", action: close) }
      Text("Originals stay untouched. Smaller dimensions and lower quality can reduce file size; results vary.")
        .font(.system(size: 11)).foregroundStyle(Ink.secondary)
      if !store.availableTransforms.isEmpty {
        Text("Transform locally").font(.subheadline)
        Text("PDF and image OCR stays on this Mac. Searchable Word copies keep page images and add editable recognized text.")
          .font(.system(size: 10)).foregroundStyle(Ink.secondary)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
          ForEach(store.availableTransforms) { transform in
            Button {
              RecentActionStore.shared.record(
                id: "transform.\(transform.rawValue)", title: transform.label, symbol: transform.icon)
              store.transformDocuments(transform)
              close()
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                Label(transform.label, systemImage: transform.icon).font(.system(size: 11, weight: .semibold))
                Text(transform.detail).font(.system(size: 9)).foregroundStyle(Ink.secondary).lineLimit(3)
              }.frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading).padding(9)
            }.buttonStyle(.plain)
              .background(Ink.canvas, in: RoundedRectangle(cornerRadius: 10))
              .overlay(RoundedRectangle(cornerRadius: 10).stroke(Ink.line.opacity(0.8)))
              .disabled(store.busy || !store.canExport)
          }
        }
        if !store.imageItems.isEmpty || !store.videoItems.isEmpty { Divider() }
      }
      if !store.imageItems.isEmpty {
        Text("\(store.imageItems.count) image\(store.imageItems.count == 1 ? "" : "s")").font(.subheadline)
        Button {
          store.extractTextFromImages(); close()
        } label: { Label("Copy image text with OCR", systemImage: "text.viewfinder") }
          .disabled(store.busy || store.extractingText)
        if !presets.imagePresets.isEmpty {
          presetStrip(title: "Image presets", presets: presets.imagePresets.map { ($0.id, $0.name) }) { id in
            if let preset = presets.imagePresets.first(where: { $0.id == id }) { store.recipe = preset.recipe }
          }
        }
        Picker("Image format", selection: $store.recipe.format) {
          ForEach(ImageFormat.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        Picker("Maximum edge", selection: $store.recipe.maximumDimension) {
          Text("Original").tag(0)
          Text("1200 px").tag(1200); Text("1600 px").tag(1600); Text("2400 px").tag(2400)
          Text("3200 px").tag(3200); Text("4000 px").tag(4000)
        }
        Slider(value: $store.recipe.quality, in: 0.1...1).disabled(store.recipe.format == .png)
        Text("Image quality: \(Int(store.recipe.quality * 100))% (PNG remains lossless)").font(.system(size: 10))
        Toggle("Remove image metadata", isOn: $store.recipe.removeMetadata)
        Toggle("White background for transparent JPEGs", isOn: $store.recipe.flattenTransparency)
        HStack {
          Button("Prepare image copies") {
            RecentActionStore.shared.record(id: "prepare.images", title: "Prepare images", symbol: "photo")
            store.prepareImages(); close()
          }.disabled(store.busy || !store.canExport)
          Button("Save as preset") { presets.addImage(name: "Custom image", recipe: store.recipe) }
            .disabled(store.busy)
        }
      }
      if !store.videoItems.isEmpty {
        Divider()
        Text("\(store.videoItems.count) video\(store.videoItems.count == 1 ? "" : "s")").font(.subheadline)
        if !presets.videoPresets.isEmpty {
          presetStrip(title: "Video presets", presets: presets.videoPresets.map { ($0.id, $0.name) }) { id in
            if let preset = presets.videoPresets.first(where: { $0.id == id }) { store.videoRecipe = preset.recipe }
          }
        }
        Picker("Maximum edge", selection: $store.videoRecipe.maximumDimension) {
          Text("480 px").tag(480); Text("720 px").tag(720); Text("1280 px").tag(1280)
          Text("1920 px").tag(1920); Text("3840 px").tag(3840)
        }
        Picker("Quality", selection: $store.videoRecipe.quality) {
          ForEach(VideoQuality.allCases) { Text($0.rawValue.capitalized).tag($0) }
        }
        Text("MP4/MOV copy, up to 30 fps. Lower-quality presets may also reduce resolution. No upscaling; codec support depends on macOS.")
          .font(.system(size: 10)).foregroundStyle(Ink.secondary)
        HStack {
          Button("Prepare video copies") {
            RecentActionStore.shared.record(id: "prepare.videos", title: "Prepare videos", symbol: "film")
            store.prepareVideos(); close()
          }.disabled(store.busy || !store.canExport)
          Button("Save as preset") { presets.addVideo(name: "Custom video", recipe: store.videoRecipe) }
            .disabled(store.busy)
        }
      }
    }.font(.system(size: 12)).padding(16)
    }
  }

  private func presetStrip(
    title: String, presets: [(UUID, String)], apply: @escaping (UUID) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Ink.secondary)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 7) {
          ForEach(presets, id: \.0) { preset in
            Button(preset.1) { apply(preset.0) }
              .buttonStyle(.bordered).controlSize(.small)
          }
        }
      }
    }
  }
}
