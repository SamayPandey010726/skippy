import AppKit
import SwiftUI

struct CapturePreview: View {
  var images: [NSImage]
  var columns: Int
  @State private var thumbnail: CGImage?

  private struct Revision: Equatable {
    let images: [ObjectIdentifier]
    let columns: Int
  }

  var body: some View {
    GeometryReader { geometry in
      if let thumbnail {
        Image(decorative: thumbnail, scale: 1)
          .resizable().scaledToFit()
          .frame(width: geometry.size.width, height: geometry.size.height)
          .accessibilityLabel("Combined image preview")
      }
    }
    .background(Ink.cream, in: RoundedRectangle(cornerRadius: 9))
    .clipShape(RoundedRectangle(cornerRadius: 9))
    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Ink.line.opacity(0.7)))
    .onChange(of: Revision(images: images.map(ObjectIdentifier.init), columns: columns), initial: true) { _, _ in
      rebuild()
    }
  }

  private func rebuild() {
    let originals = images.compactMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    let largest = originals.map { max($0.height, $0.width) }.max() ?? 1
    let scale = min(1, 280 / CGFloat(largest))
    let samples = originals.compactMap { source -> CGImage? in
      let width = max(1, Int((CGFloat(source.width) * scale).rounded()))
      let height = max(1, Int((CGFloat(source.height) * scale).rounded()))
      guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
      context.interpolationQuality = .medium
      context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
      return context.makeImage()
    }
    thumbnail = CaptureComposition.combine(samples, columns: columns)
  }
}

struct CaptureComposer: View {
  @ObservedObject var tools: NotchToolStore

  var body: some View {
    VStack(alignment: .leading, spacing: 13) {
      Text("Compose image").font(.system(size: 22, weight: .semibold))
      HStack {
        Text("\(tools.captures.count) selections").foregroundStyle(.secondary)
        Spacer()
        Picker("Layout", selection: $tools.captureColumns) {
          Label("Stack", systemImage: "rectangle.split.1x2").tag(1)
          Label("Grid", systemImage: "square.grid.2x2").tag(2)
        }.labelsHidden().fixedSize()
      }
      CapturePreview(images: tools.captures, columns: tools.captureColumns)
      HStack {
        Button(action: tools.copyCombinedCaptures) { Label("Copy", systemImage: "doc.on.doc") }
          .frame(maxWidth: .infinity)
        Button(action: tools.saveCombinedCaptures) { Label("Save PNG", systemImage: "square.and.arrow.down") }
          .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
      }.disabled(tools.captures.isEmpty)
    }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
      .foregroundStyle(Ink.text).background(Ink.paper).tint(Ink.green).preferredColorScheme(.light)
  }
}
