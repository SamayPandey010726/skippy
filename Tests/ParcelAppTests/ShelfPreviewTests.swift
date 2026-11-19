import AppKit
import ParcelCore
import SwiftUI
import XCTest
@testable import ParcelApp

final class ShelfPreviewTests: XCTestCase {
  @MainActor func testExportReviewPreviews() throws {
    guard let directory = ProcessInfo.processInfo.environment["PARCEL_PREVIEW_DIRECTORY"] else {
      throw XCTSkip("Set PARCEL_PREVIEW_DIRECTORY to export SwiftUI layout review images.")
    }
    _ = NSApplication.shared
    let folder = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let fixtures = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fixtures) }
    let note = fixtures.appendingPathComponent("Meeting notes.txt")
    try "Notes for the courier review.".write(to: note, atomically: true, encoding: .utf8)
    let store = ParcelStore(persist: false)
    store.boxes = ["Today's little things", "Design references", "Weekend plans", "Files for Maya"].map { name in
      var box = ParcelBox(name: name)
      box.items = [ParcelItem(sourcePath: note.path, displayName: note.lastPathComponent, byteCount: 28)]
      return box
    }
    store.selectedBox = store.boxes.first?.id
    store.boxes[0].isPinned = true
    for width in [720, 900, 1160, 1600] {
      try render(WorkbenchView().environmentObject(store), size: CGSize(width: width, height: 720),
                 to: folder.appendingPathComponent("hub-\(width).png"))
    }
    try render(WorkbenchView().environmentObject(store), size: CGSize(width: 720, height: 520),
               to: folder.appendingPathComponent("hub-minimum.png"))
    for tab in 0...3 {
      try render(PreferencesView(initialTab: tab).environmentObject(store), size: CGSize(width: 550, height: 540),
                 to: folder.appendingPathComponent("preferences-\(tab).png"))
    }
    try render(PrepareSheet().environmentObject(store), size: CGSize(width: 565, height: 630),
               to: folder.appendingPathComponent("prepare.png"))
    for step in OnboardingStep.allCases {
      try render(WelcomeView(initialStep: step).environmentObject(store), size: CGSize(width: 540, height: 610),
        to: folder.appendingPathComponent("welcome-\(step.rawValue).png"))
    }
    try render(RenameSheet(title: "Give your parcel a name", initial: "A little room", caption: "Find it again easily.", save: { _ in }),
               size: CGSize(width: 500, height: 260), to: folder.appendingPathComponent("rename.png"))
    let preferenceSuite = "ParcelPreview-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: preferenceSuite))
    defer { defaults.removePersistentDomain(forName: preferenceSuite) }
    let shelf = DropPopupController(store: store, defaults: defaults)
    try render(DropPopupView(shelf: shelf).environmentObject(store), size: CourierLayout.compactSize,
               to: folder.appendingPathComponent("courier-resident.png"))
    shelf.expand()
    try render(DropPopupView(shelf: shelf).environmentObject(store), size: shelf.contentSize,
               to: folder.appendingPathComponent("shelf-chooser.png"))
    let receipt = try XCTUnwrap(shelf.beginDrop(into: store.selectedBox))
    try render(DropPopupView(shelf: shelf).environmentObject(store), size: shelf.contentSize,
               to: folder.appendingPathComponent("shelf-contents.png"))
    receipt.receiving(true)
    try render(DropPopupView(shelf: shelf).environmentObject(store), size: shelf.contentSize,
               to: folder.appendingPathComponent("shelf-receiving.png"))
    receipt.receiving(false)
    store.phase = .packing
    store.progress = 0.42
    store.progressLabel = "Tucking your pieces together"
    try render(DropPopupView(shelf: shelf).environmentObject(store), size: shelf.contentSize,
               to: folder.appendingPathComponent("shelf-packing.png"))
    let archive = fixtures.appendingPathComponent("Review.zip")
    let input = PackageInput(url: note, desiredName: note.lastPathComponent)
    _ = try PackageBuilder.build(inputs: [input], title: "Review", destination: archive)
    store.archiveURL = archive
    store.phase = .ready
    try render(DropPopupView(shelf: shelf).environmentObject(store), size: shelf.contentSize,
               to: folder.appendingPathComponent("shelf-ready.png"))
    store.phase = .open
    receipt.failure("This file could not be received. Your other pieces are safe.")
    try render(DropPopupView(shelf: shelf).environmentObject(store), size: shelf.contentSize,
               to: folder.appendingPathComponent("shelf-error-small.png"))
    for skin in ParcelSkin.allCases {
      try render(DropPopupView(shelf: shelf, skin: skin).environmentObject(store), size: shelf.contentSize,
                 to: folder.appendingPathComponent("shelf-\(skin.rawValue)-glass.png"))
      try render(DropPopupView(shelf: shelf, skin: skin, solidSurface: true, strongBorder: true).environmentObject(store),
        size: shelf.contentSize, to: folder.appendingPathComponent("shelf-\(skin.rawValue)-accessible.png"))
      try render(CourierSatchel(count: 3, awake: true, skin: skin)
        .padding(20).background(skin.palette.paper), size: CGSize(width: 320, height: 280),
        to: folder.appendingPathComponent("courier-\(skin.rawValue).png"))
    }
    shelf.select(store.boxes[0].id)
    store.boxes[0].items = (0..<24).map { index in
      ParcelItem(sourcePath: note.path,
        displayName: "Quarterly reference with a deliberately long file name number \(index).txt", byteCount: 28)
    }
    store.phase = .ready
    try render(DropPopupView(shelf: shelf).environmentObject(store), size: shelf.contentSize,
               to: folder.appendingPathComponent("shelf-long-list-ready.png"))
    for style in CourierViewStyle.allCases {
      shelf.viewStyle = style
      try render(DropPopupView(shelf: shelf).environmentObject(store), size: shelf.contentSize,
        to: folder.appendingPathComponent("shelf-style-\(style.rawValue).png"))
    }
    shelf.viewStyle = .grid
    for iconSize: CGFloat in [64, 88, 128] {
      shelf.iconSize = iconSize
      shelf.dismiss()
      try render(DropPopupView(shelf: shelf).environmentObject(store), size: shelf.contentSize,
        to: folder.appendingPathComponent("courier-size-\(Int(iconSize)).png"))
    }
    shelf.iconSize = CourierLayout.defaultIconSize
    shelf.select(store.boxes[0].id)
    for progress in [0.0, 0.45, 1.0] {
      try render(CourierSatchel(count: 8, awake: true, packingProgress: progress).padding(20),
        size: CGSize(width: 240, height: 220),
        to: folder.appendingPathComponent("courier-zip-\(Int(progress * 100)).png"))
    }
    for tie in [0.0, 0.4, 0.75, 1.0] {
      try render(ThemeFolderArtwork(opening: 0, papers: 0.42, tie: tie, count: 3, skin: .night),
        size: CGSize(width: 320, height: 320), to: folder.appendingPathComponent("hem-ribbon-\(Int(tie * 100)).png"))
    }
    shelf.iconSize = 128
    shelf.closeControlScale = 1.5; shelf.expandControlScale = 0.8
    shelf.dismiss()
    try render(DropPopupView(shelf: shelf).environmentObject(store), size: shelf.contentSize,
      to: folder.appendingPathComponent("courier-independent-controls.png"))
    shelf.closeControlScale = 1; shelf.expandControlScale = 1
    shelf.iconSize = CourierLayout.defaultIconSize
    shelf.select(store.boxes[0].id)
    shelf.viewStyle = .dial
    for side in CourierSide.allCases {
      shelf.side = side
      try render(DropPopupView(shelf: shelf).environmentObject(store), size: shelf.contentSize,
        to: folder.appendingPathComponent("hem-fan-\(side.rawValue).png"))
    }
    shelf.parkInMenuBar()
    shelf.select(store.boxes[0].id)
    try render(DropPopupView(shelf: shelf).environmentObject(store), size: shelf.contentSize,
      to: folder.appendingPathComponent("menu-dial-straight.png"))
    shelf.returnFromMenuBar()
    shelf.select(store.boxes[0].id)
    for scale: CGFloat in [0.75, 1, 1.5] {
      shelf.interfaceScale = scale
      try render(DropPopupView(shelf: shelf).environmentObject(store), size: shelf.contentSize,
        to: folder.appendingPathComponent("courier-interface-\(Int(scale * 100)).png"))
    }
    shelf.interfaceScale = 1
    shelf.side = .left
    store.phase = .open
    let originalBox = store.boxes[0]
    store.boxes[0].items = [ParcelItem(sourcePath: fixtures.appendingPathComponent("Photo.jpg").path, displayName: "Photo.jpg"),
      ParcelItem(sourcePath: fixtures.appendingPathComponent("Video.mov").path, displayName: "Video.mov")]
    shelf.mediaEditor = true
    try render(DropPopupView(shelf: shelf).environmentObject(store), size: shelf.contentSize,
               to: folder.appendingPathComponent("shelf-media-editor.png"))
    shelf.mediaEditor = false
    store.boxes[0] = originalBox
    store.moveToBin(store.boxes[1].id)
    try render(BinView().environmentObject(store), size: CGSize(width: 590, height: 460),
               to: folder.appendingPathComponent("bin-populated.png"))
    store.emptyBin()
    try render(BinView().environmentObject(store), size: CGSize(width: 590, height: 460),
               to: folder.appendingPathComponent("bin-empty.png"))
    store.boxes = [ParcelBox(name: "A little room")]
    store.selectedBox = store.boxes[0].id
    try render(WorkbenchView().environmentObject(store), size: CGSize(width: 720, height: 520),
               to: folder.appendingPathComponent("hub-empty.png"))
  }

  @MainActor private func render<Content: View>(_ view: Content, size: CGSize, to url: URL) throws {
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
      .environment(\.courierStaticRendering, true)
      .transaction { $0.disablesAnimations = true })
    host.frame = NSRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, Int(size.width))
    XCTAssertGreaterThanOrEqual(bitmap.pixelsHigh, Int(size.height))
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
  }
}
