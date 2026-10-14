import AppKit

/// Notices when a file drag begins anywhere on screen, so the drop popup can
/// appear on its own.
///
/// Three mechanisms, each covering the others' blind spots:
/// 1. Permission-free poll (primary): left mouse button down + the cursor
///    moving means a drag is likely in flight — the drag pasteboard is then
///    checked for file URLs. Button up ends it. Needs no permissions.
/// 2. Global mouse monitors (when Accessibility is granted): event-driven and
///    instant.
/// 3. Drags that start inside Parcel itself (dragging the packed file out)
///    are suppressed so the popup doesn't chase its own tail.
///
/// All local-only.
@MainActor final class DragMonitor {
  static let shared = DragMonitor()
  /// Called with true when a file drag starts, false when it ends.
  /// Multiple listeners supported (drop popup + Dock picker).
  private var dragStateHandlers: [(Bool) -> Void] = []
  var onDragState: (Bool) -> Void {
    get { { [weak self] dragging in self?.dragStateHandlers.forEach { $0(dragging) } } }
    set { dragStateHandlers.append(newValue) }
  }
  /// Current drag state, for spring-load activation (Dock hover).
  var isDragging: Bool { dragging }
  private let board = NSPasteboard(name: NSPasteboard.Name("NSDragPboard"))
  private var timer: Timer?
  private var mouseMonitor: Any?
  private var upMonitor: Any?
  private var lastMouse = NSPoint.zero
  private var dragging = false
  private var suppressOwnDrag = false

  /// Call before Parcel starts its own drag-out session.
  func suppressNextOwnDrag() { suppressOwnDrag = true }

  func start() {
    mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) {
      [weak self] _ in
      Task { @MainActor [weak self] in self?.checkPasteboard() }
    }
    upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.suppressOwnDrag = false
        self?.setDragging(false)
      }
    }
    guard timer == nil else { return }
    lastMouse = NSEvent.mouseLocation
    let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.tick() }
    }
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  private func tick() {
    guard !suppressOwnDrag else { return }
    let leftDown = (NSEvent.pressedMouseButtons & 1) == 1
    let mouse = NSEvent.mouseLocation
    let moved = hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y) > 6
    lastMouse = mouse
    if leftDown && moved {
      checkPasteboard()
    } else if !leftDown {
      setDragging(false)
    }
    // Button held without moving: keep the current state.
  }

  private func checkPasteboard() {
    guard !suppressOwnDrag else { return }
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
