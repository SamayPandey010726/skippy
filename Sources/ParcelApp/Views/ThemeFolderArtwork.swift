import SwiftUI

struct ThemeFolderArtwork: View, Animatable {
  var opening: Double
  var papers: Double
  var tie: Double
  var count: Int
  var skin: ParcelSkin
  var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
    get { .init(opening, .init(papers, tie)) }
    set { opening = newValue.first; papers = newValue.second.first; tie = newValue.second.second }
  }
  private var dark: Bool { skin == .night }
  private var cord: Color { dark ? Color(red: 0.48, green: 0.48, blue: 0.53) : skin.palette.accent }
  var body: some View {
    GeometryReader { geometry in
      let scale = min(geometry.size.width, geometry.size.height) / 320
      let cordDraw = min(1, max(0, tie * 1.6))
      let vertical = min(1, max(0, (tie - 0.2) / 0.5))
      let bow = min(1, max(0, (tie - 0.55) / 0.45))
      ZStack {
        ThemeFolderBack()
          .fill(LinearGradient(colors: dark ? [Color(white: 0.15), Color(white: 0.055)] : [skin.satchelFlap, skin.satchelBody],
            startPoint: .topLeading, endPoint: .bottomTrailing))
          .overlay(ThemeFolderBack().stroke(.white.opacity(0.13), lineWidth: 1))
        ZStack {
          paper(photo: true).frame(width: 126, height: 176).rotationEffect(.degrees(-6)).position(x: 146, y: 125)
          paper(photo: false).frame(width: 126, height: 176).rotationEffect(.degrees(5)).position(x: 172, y: 133)
        }.offset(y: (1 - papers) * 60 - opening * 8).opacity(min(1, max(0, papers * 2.5)))
        RoundedRectangle(cornerRadius: 30)
          .fill(LinearGradient(colors: dark ? [Color(white: 0.30).opacity(0.66), Color(white: 0.035).opacity(0.93)]
            : [skin.satchelFlap.opacity(0.78), skin.satchelBody.opacity(0.94)], startPoint: .top, endPoint: .bottom))
          .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.18), lineWidth: 1.5))
          .overlay(alignment: .top) {
            Capsule().fill(.white.opacity(0.28)).frame(width: 218, height: 2).padding(.top, 7)
          }
          .overlay(alignment: .leading) {
            VStack(alignment: .leading, spacing: 10) {
              Capsule().fill(.white.opacity(0.11)).frame(width: 120, height: 7)
              Capsule().fill(.white.opacity(0.07)).frame(width: 84, height: 7)
            }.padding(.leading, 38)
          }
          .frame(width: 268, height: 142).rotationEffect(.degrees(-opening * 7), anchor: .bottom)
          .position(x: 160, y: 230 - opening * 30)
        ThemeRibbon(part: .horizontal).trim(from: 0, to: cordDraw).stroke(cord, style: StrokeStyle(lineWidth: 7, lineCap: .round))
        ThemeRibbon(part: .vertical).trim(from: 0, to: vertical).stroke(cord, style: StrokeStyle(lineWidth: 7, lineCap: .round))
        ThemeRibbon(part: .bow).trim(from: 0, to: bow).stroke(cord, style: StrokeStyle(lineWidth: 6, lineCap: .round))
        ThemeRibbon(part: .tails).trim(from: 0, to: bow).stroke(cord, style: StrokeStyle(lineWidth: 5, lineCap: .round))
        Circle().fill(cord).overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
          .frame(width: 13, height: 13).position(x: 160, y: 236).opacity(bow)
        if count > 0 {
          Text(count > 999 ? "999+" : "\(count)")
            .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Color(white: 0.08))
            .padding(.horizontal, 11).padding(.vertical, 5).background(Color(white: 0.97), in: Capsule())
            .position(x: 270, y: 284)
        }
      }.frame(width: 320, height: 320).scaleEffect(scale, anchor: .topLeading)
        .frame(width: 320 * scale, height: 320 * scale, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
  private func paper(photo: Bool) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      if photo {
        ZStack(alignment: .bottom) {
          RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.80, green: 0.84, blue: 0.80))
          Circle().fill(Color(red: 0.85, green: 0.72, blue: 0.49)).frame(width: 17, height: 17).offset(x: 24, y: -25)
          ThemePaperHill().fill(Color(red: 0.55, green: 0.63, blue: 0.57))
        }.frame(height: 54)
      }
      ForEach(0..<(photo ? 2 : 4), id: \.self) { index in
        Capsule().fill(Color(red: 0.79, green: 0.82, blue: 0.79))
          .frame(width: CGFloat([82, 94, 72, 88][index]), height: 7)
      }
      Spacer(minLength: 0)
    }.padding(16).background(Color(white: photo ? 0.945 : 0.98), in: RoundedRectangle(cornerRadius: 9))
  }
}

private struct ThemeFolderBack: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: 26, y: 288))
    path.addLine(to: CGPoint(x: 26, y: 103))
    path.addQuadCurve(to: CGPoint(x: 43, y: 87), control: CGPoint(x: 26, y: 87))
    path.addLine(to: CGPoint(x: 116, y: 87))
    path.addQuadCurve(to: CGPoint(x: 137, y: 98), control: CGPoint(x: 129, y: 87))
    path.addLine(to: CGPoint(x: 148, y: 112))
    path.addLine(to: CGPoint(x: 278, y: 112))
    path.addQuadCurve(to: CGPoint(x: 294, y: 128), control: CGPoint(x: 294, y: 112))
    path.addLine(to: CGPoint(x: 294, y: 288))
    path.addQuadCurve(to: CGPoint(x: 282, y: 301), control: CGPoint(x: 294, y: 301))
    path.addLine(to: CGPoint(x: 38, y: 301))
    path.addQuadCurve(to: CGPoint(x: 26, y: 288), control: CGPoint(x: 26, y: 301))
    path.closeSubpath()
    return path.applying(CGAffineTransform(scaleX: rect.width / 320, y: rect.height / 320))
  }
}

private struct ThemePaperHill: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: 0, y: rect.height))
    path.addQuadCurve(to: CGPoint(x: rect.width, y: rect.height), control: CGPoint(x: rect.width * 0.35, y: rect.height * 0.1))
    path.closeSubpath()
    return path
  }
}

private struct ThemeRibbon: Shape {
  enum Part { case horizontal, vertical, bow, tails }
  var part: Part
  func path(in rect: CGRect) -> Path {
    var path = Path()
    switch part {
    case .horizontal:
      path.move(to: CGPoint(x: 26, y: 231))
      path.addQuadCurve(to: CGPoint(x: 294, y: 231), control: CGPoint(x: 160, y: 247))
    case .vertical:
      path.move(to: CGPoint(x: 160, y: 159)); path.addLine(to: CGPoint(x: 160, y: 301))
    case .bow:
      path.move(to: CGPoint(x: 160, y: 236))
      path.addCurve(to: CGPoint(x: 127, y: 214), control1: CGPoint(x: 110, y: 240), control2: CGPoint(x: 115, y: 200))
      path.addQuadCurve(to: CGPoint(x: 160, y: 236), control: CGPoint(x: 148, y: 212))
      path.addCurve(to: CGPoint(x: 193, y: 214), control1: CGPoint(x: 175, y: 201), control2: CGPoint(x: 204, y: 207))
      path.addQuadCurve(to: CGPoint(x: 160, y: 236), control: CGPoint(x: 211, y: 242))
    case .tails:
      path.move(to: CGPoint(x: 157, y: 239))
      path.addCurve(to: CGPoint(x: 144, y: 289), control1: CGPoint(x: 147, y: 260), control2: CGPoint(x: 153, y: 275))
      path.move(to: CGPoint(x: 163, y: 239))
      path.addCurve(to: CGPoint(x: 176, y: 289), control1: CGPoint(x: 173, y: 260), control2: CGPoint(x: 167, y: 275))
    }
    return path.applying(CGAffineTransform(scaleX: rect.width / 320, y: rect.height / 320))
  }
}
