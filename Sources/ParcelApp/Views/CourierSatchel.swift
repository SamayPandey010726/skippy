import SwiftUI

struct CourierSatchel: View {
  var sealed = false
  var count = 0
  var awake = false
  var celebration = 0
  var skin: ParcelSkin? = nil
  var open = false
  var avatar = true
  var packingProgress: Double? = nil
  var intakeEvent = 0
  var intakeCount = 0
  @StateObject private var skins = SkinStore.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.courierStaticRendering) private var staticRendering
  @State private var tied = false
  @State private var catchSwell = false
  @State private var landed = true

  var body: some View {
    let motionOff = reduceMotion || staticRendering
    let tie = sealed ? (tied || motionOff ? 1.0 : 0.0) : min(0.5, max(0, packingProgress ?? 0) * 0.5)
    let papers = sealed ? 0.42 : (open ? 0.1 : (packingProgress != nil ? 0.75 : 1))
    ZStack {
      ThemeFolderArtwork(opening: open ? 1 : (awake && !sealed ? 0.3 : 0),
        papers: papers, tie: tie, count: count, skin: skin ?? skins.skin)
        .scaleEffect(motionOff ? 1 : (catchSwell ? 1.055 : (awake ? 1.02 : 1)), anchor: .bottom)
        .offset(y: motionOff ? 0 : (catchSwell ? -3 : 0))
        .animation(Motion.folderFlap, value: open)
        .animation(Motion.hoverLift, value: awake)
        .animation(Motion.ribbonTie, value: tied)
        .animation(Motion.hoverLift, value: packingProgress)
      if intakeEvent > 0 && !motionOff {
        ForEach(0..<min(3, max(0, intakeCount)), id: \.self) { index in
          Image(systemName: "doc.fill")
            .font(.system(size: 19)).foregroundStyle(Color(white: 0.96))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .rotationEffect(.degrees(landed ? 0 : Double(index * 8 - 8)))
            .scaleEffect(landed ? 0.1 : 0.85)
            .offset(x: landed ? 0 : CGFloat(index * 17 - 17), y: landed ? 2 : -35 - CGFloat(index * 6))
            .opacity(landed ? 0 : 1)
            .animation(Motion.fileCatch?.delay(Double(index) * 0.07), value: landed)
            .allowsHitTesting(false)
        }
      }
    }
    .task(id: sealed) {
      if !sealed { tied = false; return }
      if motionOff { tied = true; return }
      tied = false
      await Task.yield()
      guard !Task.isCancelled else { return }
      withAnimation(Motion.ribbonTie) { tied = true }
    }
    .task(id: intakeEvent) {
      guard intakeEvent > 0, intakeCount > 0, !motionOff else { return }
      var reset = Transaction(); reset.disablesAnimations = true
      withTransaction(reset) { landed = false; catchSwell = false }
      await Task.yield()
      guard !Task.isCancelled else { return }
      withAnimation(Motion.fileCatch) { landed = true; catchSwell = true }
      do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
      guard !Task.isCancelled else { return }
      withAnimation(Motion.catchSettle) { catchSwell = false }
    }
    .accessibilityLabel(packingProgress != nil ? "Packing parcel" : (sealed ? "Ribbon-tied parcel, ready to pick up" : "Parcel folder, \(count) file\(count == 1 ? "" : "s")"))
  }
}

struct CourierUnfold: ViewModifier {
  var order: Int
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.courierStaticRendering) private var staticRendering
  @State private var unfolded = false
  func body(content: Content) -> some View {
    content
      .opacity(unfolded || reduceMotion || staticRendering ? 1 : 0)
      .offset(y: unfolded || reduceMotion || staticRendering ? 0 : -6)
      .scaleEffect(unfolded || reduceMotion || staticRendering ? 1 : 0.96, anchor: .top)
      .onAppear {
        withAnimation(Motion.bagOpen?.delay(Double(order) * 0.02)) { unfolded = true }
      }
  }
}

private struct CourierStaticRenderingKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  var courierStaticRendering: Bool {
    get { self[CourierStaticRenderingKey.self] }
    set { self[CourierStaticRenderingKey.self] = newValue }
  }
}
