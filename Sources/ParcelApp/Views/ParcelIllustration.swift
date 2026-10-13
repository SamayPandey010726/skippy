import SwiftUI

private func polygon(_ points: [CGPoint]) -> Path {
  var path = Path()
  guard let first = points.first else { return path }
  path.move(to: first)
  for point in points.dropFirst() { path.addLine(to: point) }
  path.closeSubpath()
  return path
}
private struct FolderCover: Shape {
  var amount: CGFloat
  var animatableData: CGFloat {
    get { amount }
    set { amount = newValue }
  }
  func path(in rect: CGRect) -> Path {
    let open: [CGPoint] = [
      .init(x: 80, y: 190), .init(x: 354, y: 208), .init(x: 378, y: 307), .init(x: 105, y: 307),
    ]
    let closed: [CGPoint] = [
      .init(x: 105, y: 144), .init(x: 378, y: 144), .init(x: 378, y: 307), .init(x: 105, y: 307),
    ]
    return polygon(
      zip(open, closed).map { a, b in
        .init(x: a.x + (b.x - a.x) * amount, y: a.y + (b.y - a.y) * amount)
      })
  }
}
private struct FolderFinishState: Equatable {
  var packed: Bool
  var ready: Bool
  var reduced: Bool
}
private struct MetalPaperclip: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let w = rect.width
    let h = rect.height
    path.move(to: .init(x: w * 0.85, y: h * 0.23))
    path.addLine(to: .init(x: w * 0.85, y: h * 0.83))
    path.addQuadCurve(to: .init(x: w * 0.08, y: h * 0.83), control: .init(x: w * 0.48, y: h * 1.13))
    path.addLine(to: .init(x: w * 0.08, y: h * 0.10))
    path.addQuadCurve(
      to: .init(x: w * 0.67, y: h * 0.10), control: .init(x: w * 0.40, y: -h * 0.12))
    path.addLine(to: .init(x: w * 0.67, y: h * 0.77))
    path.addQuadCurve(to: .init(x: w * 0.35, y: h * 0.77), control: .init(x: w * 0.50, y: h * 0.94))
    path.addLine(to: .init(x: w * 0.35, y: h * 0.26))
    return path
  }
}
struct ParcelIllustration: View {
  var sealed: Bool
  var count: Int
  var bounce: Int
  var receiving: Bool = false
  var stamped: Bool = true
  var animate: Bool = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var clipped = false
  @State private var lift: CGFloat = 0
  private var finished: Bool { animate ? clipped : sealed && stamped }
  private var motion: Animation? { reduceMotion || !animate ? nil : .easeOut(duration: 0.46) }
  var body: some View {
    GeometryReader { geometry in
      let scale = min(geometry.size.width / 480, geometry.size.height / 355)
      ZStack {
        Ellipse().fill(Ink.text.opacity(0.14)).frame(width: 292, height: 18).blur(radius: 9)
          .position(x: 241, y: 328)
        Path { path in
          path.move(to: .init(x: 105, y: 307))
          path.addLine(to: .init(x: 105, y: 110))
          path.addQuadCurve(to: .init(x: 114, y: 102), control: .init(x: 105, y: 102))
          path.addLine(to: .init(x: 174, y: 102))
          path.addLine(to: .init(x: 193, y: 126))
          path.addLine(to: .init(x: 368, y: 126))
          path.addQuadCurve(to: .init(x: 378, y: 137), control: .init(x: 378, y: 126))
          path.addLine(to: .init(x: 378, y: 307))
          path.closeSubpath()
        }.fill(
          LinearGradient(
            colors: [
              Color(red: 0.85, green: 0.72, blue: 0.52), Color(red: 0.79, green: 0.63, blue: 0.43),
            ], startPoint: .top, endPoint: .bottom))
        RoundedRectangle(cornerRadius: 8).fill(Ink.green).frame(width: 29, height: 66)
          .position(x: 391, y: 227)
        Path { path in
          path.move(to: .init(x: 396, y: 204))
          path.addLine(to: .init(x: 396, y: 249))
        }
        .stroke(Ink.paleGreen.opacity(0.65), lineWidth: 1)
        ForEach(0..<min(max(count, 0), 3), id: \.self) { index in
          PaperPiece(index: index, count: count)
            .rotationEffect(.degrees(Double(index) * 9 - 7))
            .offset(x: CGFloat(index) * 24 - 24, y: sealed ? 80 : -2)
            .scaleEffect(sealed ? 0.88 : 1, anchor: .bottom)
            .opacity(sealed ? 0 : 1).position(x: 237, y: 150)
            .animation(reduceMotion || !animate ? nil : .easeOut(duration: 0.30), value: sealed)
        }
        FolderCover(amount: sealed ? 1 : 0)
          .fill(
            LinearGradient(
              colors: [
                Color(red: 0.89, green: 0.76, blue: 0.57),
                Color(red: 0.82, green: 0.67, blue: 0.46),
              ], startPoint: .topLeading, endPoint: .bottomTrailing)
          )
          .overlay(
            FolderCover(amount: sealed ? 1 : 0).stroke(
              Color(red: 0.65, green: 0.51, blue: 0.34), lineWidth: 0.8))
        Canvas { context, _ in
          for index in 0..<40 {
            let x = CGFloat(120 + (index * 37) % 246)
            let y = CGFloat(240 + (index * 19) % 55)
            var fibre = Path()
            fibre.move(to: .init(x: x, y: y))
            fibre.addLine(to: .init(x: x + 3, y: y + 1))
            context.stroke(fibre, with: .color(Color.white.opacity(0.11)), lineWidth: 0.7)
          }
        }
        Text(finished ? "ZIP · READY" : "YOUR FILES")
          .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1)
          .foregroundStyle(Ink.secondary).frame(width: 105, height: 29)
          .background(
            Color(red: 0.93, green: 0.90, blue: 0.82), in: RoundedRectangle(cornerRadius: 3)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 3).stroke(
              Color(red: 0.75, green: 0.68, blue: 0.55), lineWidth: 0.8)
          )
          .rotationEffect(.degrees(sealed ? 0 : 4)).position(x: 183, y: sealed ? 212 : 235)
        HStack(spacing: 21) {
          Ellipse().fill(Color(red: 0.29, green: 0.27, blue: 0.22)).frame(width: 4, height: 5)
          Ellipse().fill(Color(red: 0.29, green: 0.27, blue: 0.22)).frame(width: 4, height: 5)
        }.position(x: 315, y: sealed ? 245 : 255)
        Path { path in
          let y: CGFloat = sealed ? 253 : 263
          path.move(to: .init(x: 311, y: y))
          path.addQuadCurve(to: .init(x: 319, y: y), control: .init(x: 315, y: y + 4))
        }.stroke(
          Color(red: 0.38, green: 0.32, blue: 0.25),
          style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        if count > 0 {
          Text("\(count) pieces").font(.system(size: 10)).foregroundStyle(
            Color(red: 0.46, green: 0.38, blue: 0.28)
          )
          .position(x: 330, y: 290)
        }
        MetalPaperclip().stroke(
          Color(red: 0.43, green: 0.47, blue: 0.44),
          style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
        )
        .overlay(
          MetalPaperclip().stroke(
            Color(red: 0.87, green: 0.89, blue: 0.85),
            style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
        )
        .frame(width: 18, height: 62).position(x: 158, y: finished ? 172 : 160)
        .opacity(finished ? 1 : 0)
        .animation(
          reduceMotion || !animate ? nil : .spring(response: 0.22, dampingFraction: 0.75),
          value: finished)
      }.frame(width: 480, height: 355).offset(y: lift)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: 480 * scale, height: 355 * scale, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(motion, value: sealed)
        .task(id: FolderFinishState(packed: sealed, ready: stamped, reduced: reduceMotion)) {
          clipped = false
          guard sealed && stamped && animate else { return }
          if !reduceMotion {
            do { try await Task.sleep(nanoseconds: 460_000_000) } catch { return }
          }
          guard !Task.isCancelled else { return }
          clipped = true
        }
        .onChange(of: bounce) { _, _ in
          guard !reduceMotion && animate else { return }
          withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) { lift = 3 }
          Task { @MainActor in
            try? await Task.sleep(nanoseconds: 110_000_000)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) { lift = 0 }
          }
        }
    }.accessibilityLabel(
      sealed ? "Packed folder with \(count) items" : "Open folder with \(count) items")
  }
}

private struct PaperPiece: View {
  var index: Int
  var count: Int
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      if index % 2 == 0 {
        ZStack(alignment: .bottom) {
          RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.83, green: 0.89, blue: 0.76))
          Circle().fill(Color(red: 0.97, green: 0.86, blue: 0.57)).frame(width: 16, height: 16)
            .offset(x: 19, y: -20)
          Path { p in
            p.move(to: .init(x: 0, y: 54))
            p.addQuadCurve(to: .init(x: 74, y: 54), control: .init(x: 36, y: -3))
            p.closeSubpath()
          }.fill(Ink.moss.opacity(0.7))
        }.frame(height: 58)
      } else {
        Image(systemName: "doc.text").font(.system(size: 27, weight: .light)).foregroundStyle(
          Ink.moss
        ).frame(maxWidth: .infinity).padding(.vertical, 9)
      }
      RoundedRectangle(cornerRadius: 2).fill(Ink.line).frame(height: 3)
      RoundedRectangle(cornerRadius: 2).fill(Ink.line.opacity(0.6)).frame(width: 40, height: 3)
    }.padding(10).frame(width: 91, height: 123).background(
      Color(red: 1, green: 0.995, blue: 0.967), in: RoundedRectangle(cornerRadius: 6)
    )
    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Ink.line.opacity(0.6), lineWidth: 1)).shadow(
      color: Ink.text.opacity(0.09), radius: 6, x: 0, y: 3)
  }
}

struct GardenBackdrop: View {
  var body: some View {
    Canvas { context, size in
      for index in 0..<58 {
        let x = CGFloat((index * 71 + 19) % 997) / 997 * size.width
        let y = CGFloat((index * 113 + 43) % 991) / 991 * size.height
        context.fill(
          Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
          with: .color(Ink.secondary.opacity(0.06)))
      }
    }.allowsHitTesting(false).accessibilityHidden(true)
  }
}
