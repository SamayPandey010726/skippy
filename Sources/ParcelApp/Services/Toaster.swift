import AppKit
import SwiftUI

/// A small floating "X copied to clipboard" popup, visible no matter which
/// app is frontmost. Route every clipboard copy through `copied(_:)`.
@MainActor final class Toaster {
  static let shared = Toaster()
  private var panel: NSPanel?
  private var hosting: NSHostingView<ToastView>?
  private var hideWork: DispatchWorkItem?

  func copied(_ label: String) {
    show("\(label) copied to clipboard")
  }

  /// A plain floating note (not a copy confirmation).
  func note(_ text: String) {
    show(text)
  }

  func tip(_ key: String, _ text: String) {
    let defaults = UserDefaults.standard
    guard defaults.object(forKey: "parcel.showTips") as? Bool ?? true,
      !defaults.bool(forKey: "parcel.tip.\(key)") else { return }
    defaults.set(true, forKey: "parcel.tip.\(key)")
    show("Tip · \(text)")
  }

  private func show(_ text: String) {
    hideWork?.cancel()
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let p: NSPanel
    if let existing = panel, let h = hosting {
      p = existing
      h.rootView = ToastView(text: text)
    } else {
      p = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 46),
        styleMask: [.nonactivatingPanel, .fullSizeContentView],
        backing: .buffered, defer: false)
      p.isOpaque = false
      p.backgroundColor = .clear
      p.hasShadow = true
      p.level = .floating
      p.ignoresMouseEvents = true
      p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      p.isReleasedWhenClosed = false
      let h = NSHostingView(rootView: ToastView(text: text))
      p.contentView = h
      hosting = h
      panel = p
    }
    if let screen = NSScreen.main {
      let f = screen.visibleFrame
      p.setFrameOrigin(NSPoint(x: f.midX - 160, y: f.minY + 56))
    }
    p.orderFrontRegardless()
    if reduceMotion {
      p.alphaValue = 1
    } else {
      p.alphaValue = 0
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.22
        p.animator().alphaValue = 1
      }
    }
    let work = DispatchWorkItem { [weak self] in self?.hide() }
    hideWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.9, execute: work)
  }

  private func hide() {
    guard let p = panel else { return }
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      p.orderOut(nil)
    } else {
      NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.3
        p.animator().alphaValue = 0
      }, completionHandler: { p.orderOut(nil) })
    }
  }
}

struct ToastView: View {
  var text: String
  var body: some View {
    HStack(spacing: 9) {
      Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(.white)
      Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
    }
    .padding(.horizontal, 16).padding(.vertical, 12)
    .background(Color.black.opacity(0.82), in: Capsule())
    .frame(width: 320, height: 46, alignment: .center)
  }
}
