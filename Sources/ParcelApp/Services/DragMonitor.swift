import AppKit
import ParcelCore

@MainActor final class DragMonitor {
  static let shared = DragMonitor()
  private var dragStateHandlers: [(Bool) -> Void] = []
  var onDragState: (Bool) -> Void {
    get { { [weak self] dragging in self?.dragStateHandlers.forEach { $0(dragging) } } }
    set { dragStateHandlers.append(newValue) }
  }
  var onDragLocation: ((NSPoint) -> Void)?
  var onTopEdgeHover: ((NSPoint) -> Void)?
  var onShiftFileDrag: (([URL]?, NSPoint) -> Void)?
  var shouldDetectShake: () -> Bool = { false }
  var onMouseShake: (() -> Void)?
  private var shake = PointerShakeDetector()
  var isDragging: Bool { session.isDragging }
  private(set) var isSending = false
  private var convertsOwnDrag = false
  private let board = NSPasteboard(name: .drag)
  private var session = ExternalDragSession(pasteboardGeneration: 0)
  private var timer: Timer?
  private var monitors: [Any] = []
  private var shiftPresented = false

  func suppressNextOwnDrag(allowQuickConvert: Bool = false) {
    isSending = true
    convertsOwnDrag = allowQuickConvert
    let wasDragging = isDragging
    session.suppress()
    endShiftGesture()
    if wasDragging { onDragState(false) }
  }
  func finishOwnDrag() { isSending = false; convertsOwnDrag = false; endShiftGesture() }

  func start() {
    guard monitors.isEmpty else { return }
    session = ExternalDragSession(pasteboardGeneration: board.changeCount)
    if let monitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved], handler: { [weak self] event in
        MainActor.assumeIsolated {
          if event.type == .mouseMoved { self?.checkShake(event) } else { self?.tick() }
        }
      }) {
      monitors.append(monitor)
    }
    if let monitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved], handler: { [weak self] event in
        if event.type == .mouseMoved { self?.checkShake(event) } else { self?.tick() }
        return event
      }) { monitors.append(monitor) }
  }
  private func checkShake(_ event: NSEvent) {
    onTopEdgeHover?(NSEvent.mouseLocation)
    guard shouldDetectShake() else { shake = PointerShakeDetector(); return }
    if shake.update(point: NSEvent.mouseLocation, time: event.timestamp,
      buttonDown: NSEvent.pressedMouseButtons != 0 || isDragging || isSending) { onMouseShake?() }
  }

  private func tick() {
    let wasDragging = isDragging
    let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
    if buttonDown && timer == nil {
      let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.tick() }
      }
      timer.tolerance = 0.008
      RunLoop.main.add(timer, forMode: .common)
      self.timer = timer
    } else if !buttonDown {
      timer?.invalidate()
      timer = nil
    }
    session.update(
      buttonDown: buttonDown,
      pasteboardGeneration: board.changeCount,
      supported: buttonDown && !wasDragging && FileDropSurface.supports(board))
    if isDragging != wasDragging { onDragState(isDragging) }
    if isDragging { onDragLocation?(NSEvent.mouseLocation) }
    updateShiftGesture()
  }

  private func updateShiftGesture() {
    let point = NSEvent.mouseLocation
    let shift = NSEvent.modifierFlags.contains(.shift)
    let convertibleDrag = isDragging || (isSending && convertsOwnDrag && NSEvent.pressedMouseButtons & 1 != 0)
    if convertibleDrag, shift {
      let urls = Self.fileURLs(on: board)
      guard !urls.isEmpty else { return }
      if !shiftPresented {
        shiftPresented = true
        onShiftFileDrag?(urls, point)
      }
    } else { endShiftGesture(at: point) }
  }
  private func endShiftGesture(at point: NSPoint = NSEvent.mouseLocation) {
    guard shiftPresented else { return }
    shiftPresented = false
    onShiftFileDrag?(nil, point)
  }
  static func fileURLs(on board: NSPasteboard) -> [URL] {
    let urls = board.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    return urls.filter { url in
      var directory: ObjCBool = false
      return url.isFileURL && FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
        && !directory.boolValue
    }.map(\.standardizedFileURL)
  }
}
