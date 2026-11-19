import SwiftUI

enum NotchWidgetSize: String, Codable, CaseIterable, Identifiable {
  case oneByOne = "1×1"
  case oneByTwo = "1×2"
  case twoByOne = "2×1"
  case twoByTwo = "2×2"
  case fourByFour = "4×4"
  var id: String { rawValue }
  var label: String {
    switch self {
    case .oneByOne: "1×1 Small"
    case .oneByTwo: "1×2 Tall"
    case .twoByOne: "2×1 Wide"
    case .twoByTwo: "2×2 Large"
    case .fourByFour: "4×4 Full page"
    }
  }
  var columns: Int {
    switch self { case .oneByOne, .oneByTwo: 1; case .twoByOne, .twoByTwo: 2; case .fourByFour: 4 }
  }
  var rows: Int {
    switch self { case .oneByOne, .twoByOne: 1; case .oneByTwo, .twoByTwo: 2; case .fourByFour: 4 }
  }
}

enum NotchWidgetKind: String, Codable, CaseIterable, Identifiable {
  case parcel, clipboard, extract, color, timer, notes, qr, search, launcher, music, downloads, awake, recent, system, calendar, calculator, screenshot, draw
  var id: String { rawValue }
  var module: NotchModule {
    switch self {
    case .parcel: .parcel; case .clipboard: .clipboard; case .extract: .extract; case .color: .color
    case .timer: .timer; case .notes: .notes; case .qr: .qr; case .search: .search
    case .launcher: .launcher; case .music: .music; case .downloads: .downloads
    case .awake: .awake; case .recent: .recent; case .system: .system
    case .calendar: .calendar; case .calculator: .calculator; case .screenshot: .screenshot; case .draw: .draw
    }
  }
  var defaultSize: NotchWidgetSize {
    switch self {
    case .music: .fourByFour
    case .parcel, .notes, .recent: .twoByTwo
    case .clipboard, .search, .downloads, .system: .twoByOne
    case .launcher: .fourByFour
    default: .oneByOne
    }
  }
}

struct NotchWidget: Codable, Identifiable, Equatable {
  var kind: NotchWidgetKind
  var size: NotchWidgetSize
  var pinned: Bool
  var id: NotchWidgetKind { kind }
}

@MainActor final class NotchWidgetStore: ObservableObject {
  static let shared = NotchWidgetStore()
  @Published private(set) var widgets: [NotchWidget] { didSet { save() } }
  @Published var editing = false
  private let defaults: UserDefaults
  private let key = "parcels.widgets.v2"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: key),
      let saved = try? JSONDecoder().decode([NotchWidget].self, from: data) {
      let known = Set(saved.map(\.kind))
      widgets = saved + NotchWidgetKind.allCases.filter { !known.contains($0) }
        .map { NotchWidget(kind: $0, size: $0.defaultSize, pinned: [.music, .timer].contains($0)) }
    } else {
      let order: [NotchWidgetKind] = [.music, .parcel, .timer, .clipboard, .notes, .search,
        .downloads, .awake, .recent, .launcher, .extract, .color, .qr, .system, .calendar, .calculator, .screenshot, .draw]
      widgets = order.map { NotchWidget(kind: $0, size: $0.defaultSize, pinned: [.music, .timer].contains($0)) }
    }
  }

  var pinned: [NotchWidget] { widgets.filter(\.pinned) }

  /// Packs widgets into complete 4×4 pages so a scroll always lands on a
  /// composed dashboard instead of cutting a card in half.
  var pages: [[NotchWidget]] {
    var pages: [[NotchWidget]] = [[]]
    var occupied = Array(repeating: Array(repeating: false, count: 4), count: 4)
    func placement(for widget: NotchWidget) -> (Int, Int)? {
      for row in 0...(4 - widget.size.rows) {
        for column in 0...(4 - widget.size.columns) {
          let clear = (row..<(row + widget.size.rows)).allSatisfy { y in
            (column..<(column + widget.size.columns)).allSatisfy { !occupied[y][$0] }
          }
          if clear { return (row, column) }
        }
      }
      return nil
    }
    for widget in widgets {
      var position = placement(for: widget)
      if position == nil {
        pages.append([])
        occupied = Array(repeating: Array(repeating: false, count: 4), count: 4)
        position = placement(for: widget)
      }
      guard let (row, column) = position else { continue }
      for y in row..<(row + widget.size.rows) {
        for x in column..<(column + widget.size.columns) { occupied[y][x] = true }
      }
      pages[pages.count - 1].append(widget)
    }
    return pages
  }

  func resize(_ kind: NotchWidgetKind, to size: NotchWidgetSize) {
    guard let index = widgets.firstIndex(where: { $0.kind == kind }) else { return }
    widgets[index].size = size
  }

  func togglePinned(_ kind: NotchWidgetKind) {
    guard let index = widgets.firstIndex(where: { $0.kind == kind }) else { return }
    widgets[index].pinned.toggle()
  }

  func move(_ source: NotchWidgetKind, before target: NotchWidgetKind) {
    guard source != target, let from = widgets.firstIndex(where: { $0.kind == source }),
      let to = widgets.firstIndex(where: { $0.kind == target }) else { return }
    let widget = widgets.remove(at: from)
    widgets.insert(widget, at: from < to ? to - 1 : to)
  }

  func reset() {
    defaults.removeObject(forKey: key)
    let order: [NotchWidgetKind] = [.music, .parcel, .timer, .clipboard, .notes, .search,
      .downloads, .awake, .recent, .launcher, .extract, .color, .qr, .system, .calendar, .calculator, .screenshot, .draw]
    widgets = order.map { NotchWidget(kind: $0, size: $0.defaultSize, pinned: [.music, .timer].contains($0)) }
  }

  private func save() {
    if let data = try? JSONEncoder().encode(widgets) { defaults.set(data, forKey: key) }
  }
}

private struct NotchWidgetSpanKey: LayoutValueKey {
  static let defaultValue = CGSize(width: 1, height: 1)
}

extension View {
  func notchWidgetSpan(_ size: NotchWidgetSize) -> some View {
    layoutValue(key: NotchWidgetSpanKey.self,
      value: CGSize(width: size.columns, height: size.rows))
  }
}

/// Four-column packing layout for mixed-size notch widgets.
struct NotchWidgetGridLayout: Layout {
  struct Cache { var frames: [CGRect] = []; var height: CGFloat = 0 }
  var columns = 4
  var rowHeight: CGFloat = 48
  var spacing: CGFloat = 7

  func makeCache(subviews: Subviews) -> Cache { Cache() }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
    let width = max(280, proposal.width ?? 456)
    let columnWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
    var occupied: [[Bool]] = []
    var frames: [CGRect] = []
    func fits(row: Int, column: Int, width: Int, height: Int) -> Bool {
      guard column + width <= columns else { return false }
      for y in row..<(row + height) {
        if y < occupied.count {
          for x in column..<(column + width) where occupied[y][x] { return false }
        }
      }
      return true
    }
    for subview in subviews {
      let span = subview[NotchWidgetSpanKey.self]
      let spanWidth = min(columns, max(1, Int(span.width)))
      let spanHeight = max(1, Int(span.height))
      var row = 0
      var column = 0
      while true {
        if fits(row: row, column: column, width: spanWidth, height: spanHeight) { break }
        column += 1
        if column >= columns { column = 0; row += 1 }
      }
      while occupied.count < row + spanHeight { occupied.append(Array(repeating: false, count: columns)) }
      for y in row..<(row + spanHeight) { for x in column..<(column + spanWidth) { occupied[y][x] = true } }
      frames.append(CGRect(x: CGFloat(column) * (columnWidth + spacing),
        y: CGFloat(row) * (rowHeight + spacing),
        width: CGFloat(spanWidth) * columnWidth + CGFloat(spanWidth - 1) * spacing,
        height: CGFloat(spanHeight) * rowHeight + CGFloat(spanHeight - 1) * spacing))
    }
    cache.frames = frames
    cache.height = frames.map(\.maxY).max() ?? 0
    return CGSize(width: width, height: cache.height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
    if cache.frames.count != subviews.count { _ = sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache) }
    for (subview, frame) in zip(subviews, cache.frames) {
      subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        anchor: .topLeading, proposal: ProposedViewSize(frame.size))
    }
  }
}
