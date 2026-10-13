import AppKit

/// Notices when a file drag begins anywhere on screen, so the drop popup can
/// appear on its own.
///
/// Two mechanisms, belt and suspenders:
/// 1. A global left-mouse-dragged monitor (event-driven): the moment the
///    mouse moves with the button down, the drag pasteboard is checked for
///    file URLs. A global left-mouse-up ends the drag.
/// 2. A lightweight pasteboard poll as fallback.
///
/// All local-only. Drags that start inside Parcel itself (dragging the packed
/// file out) are suppressed so the popup doesn't chase its own tail.
@MainActor final class DragMonitor {
  static let shared = DragMonitor()
  /// Called with true when a file drag starts, false when it ends.
  var onDragState: (Bool) -> Void = { _ in }
  private let board = NSPasteboard(name: NSPasteboard.Name("NSDragPboard"))
  private var timer: Timer?
  private var mouseMonitor: Any?
  private var upMonitor: Any?
  private var lastChange = 0
  private var dragging = false
  private var suppressOwnDrag = false

  /// Call before Parcel starts its own drag-out session.
  func suppressNextOwnDrag() { suppressOwnDrag = true }

  func start() {
    mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) {
      [weak self] _ in
      Task { @MainActor [weak self] in self?.dragActivity() }
    }
    upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.suppressOwnDrag = false
        self?.setDragging(false)
      }
    }
    guard timer == nil else { return }
    lastChange = board.changeCount
    let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.tick() }
    }
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  private func dragActivity() {
    guard !suppressOwnDrag else { return }
    if board.changeCount != lastChange {
      lastChange = board.changeCount
      let urls = board.readObjects(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
      setDragging(!(urls?.isEmpty ?? true))
    }
  }

  private func tick() {
    guard !suppressOwnDrag else { return }
    let c = board.changeCount
    guard c != lastChange else { return }
    lastChange = c
    let urls = board.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    setDragging(!(urls?.isEmpty ?? true))
  }

  private func setDragging(_ now: Bool) {
    if now != dragging {
      dragging = now
      onDragState(now)
    }
  }
}
