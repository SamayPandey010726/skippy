import AppKit

/// Notices when a file drag begins anywhere on screen, so the shelf can pop
/// out on its own — no need to hunt for the edge strip first.
///
/// There is no public "a drag started" notification on macOS, so this watches
/// the system drag pasteboard: it gains file URLs the moment a drag begins
/// and clears when the drag ends. Cheap (a change-count check 7x a second),
/// local-only, and silent when nothing is dragged.
@MainActor final class DragMonitor {
  static let shared = DragMonitor()
  /// Called with true when a file drag starts, false when it ends.
  var onDragState: (Bool) -> Void = { _ in }
  private let board = NSPasteboard(name: NSPasteboard.Name("NSDragPboard"))
  private var timer: Timer?
  private var lastChange = 0
  private var dragging = false

  func start() {
    guard timer == nil else { return }
    lastChange = board.changeCount
    let t = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.tick() }
    }
    // Drags run the run loop in event-tracking mode — .common keeps us alive.
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  private func tick() {
    let c = board.changeCount
    guard c != lastChange else { return }
    lastChange = c
    let urls = board.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    let now = !(urls?.isEmpty ?? true)
    if now != dragging {
      dragging = now
      onDragState(now)
    }
  }
}
