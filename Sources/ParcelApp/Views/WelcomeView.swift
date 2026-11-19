import ParcelCore
import SwiftUI

enum OnboardingStep: Int, CaseIterable, Identifiable {
  case welcome
  case collect
  case organize
  case deliver
  case defaults
  case shortcut

  var id: Int { rawValue }
}

struct WelcomeView: View {
  @EnvironmentObject private var store: ParcelStore
  @StateObject private var skins = SkinStore.shared
  @ObservedObject private var shortcuts = GlobalShortcutManager.shared
  @State private var step: OnboardingStep

  init(initialStep: OnboardingStep = .welcome) { _step = State(initialValue: initialStep) }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        BrandMark()
        Spacer()
        Button("Skip tutorial", action: finish)
          .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Ink.secondary)
      }.padding(.bottom, 18)

      ZStack {
        stepContent.transition(.asymmetric(
          insertion: .move(edge: .trailing).combined(with: .opacity),
          removal: .move(edge: .leading).combined(with: .opacity)))
      }.id(step).frame(maxWidth: .infinity, maxHeight: .infinity)

      HStack(spacing: 7) {
        ForEach(OnboardingStep.allCases) { item in
          Capsule().fill(item == step ? Ink.green : Ink.line)
            .frame(width: item == step ? 22 : 7, height: 7)
            .animation(Motion.snappyTap, value: step).accessibilityHidden(true)
        }
      }.padding(.vertical, 16)

      HStack {
        Button("Back") { move(-1) }.buttonStyle(QuietButtonStyle()).disabled(step == .welcome)
          .opacity(step == .welcome ? 0 : 1)
        Spacer()
        Text("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
          .font(.system(size: 10)).foregroundStyle(Ink.secondary)
        Spacer()
        Button(step == .shortcut ? "Start using Parcels" : "Continue") {
          if step == .shortcut { finish() } else { move(1) }
        }.buttonStyle(MossButtonStyle())
      }
    }.padding(28).frame(width: 540, height: 610).background(Ink.paper).foregroundStyle(Ink.text)
      .preferredColorScheme(skins.skin == .night ? .dark : .light)
  }

  @ViewBuilder private var stepContent: some View {
    switch step {
    case .welcome:
      tutorialPage(
        title: "Meet Parcels.",
        body: "A customizable workspace that lives over your Mac's menu bar and keeps everyday tools within reach.") {
          ZStack { GardenBackdrop(); CourierSatchel(count: 3, awake: true) }
        }
    case .collect:
      tutorialPage(
        title: "Drop files. Keep moving.",
        body: "Drag files to the top of the screen. Your one parcel opens immediately and keeps them ready across Finder, Mail, browsers and chats.") {
          HStack(spacing: 18) {
            tutorialFile("photo", "Photo.jpg")
            Image(systemName: "arrow.right").font(.system(size: 20, weight: .light)).foregroundStyle(Ink.moss)
            CourierSatchel(count: 1, awake: true).frame(width: 128, height: 128)
          }
        }
    case .organize:
      tutorialPage(
        title: "Make the workspace yours.",
        body: "Resize every feature from 1×1 to a full 4×4 page, rearrange it, then scroll one complete page at a time.") {
          HStack(spacing: 18) {
            tutorialAction("arrow.up.left.and.arrow.down.right", "Resize")
            tutorialAction("circle.grid.3x3", "Arrange")
            tutorialAction("rectangle.portrait.on.rectangle.portrait", "Pages")
          }
        }
    case .deliver:
      tutorialPage(
        title: "Preview, prepare, deliver.",
        body: "Hover a file for native Quick Look. Search naturally, make smaller image or video copies, then drag individual files or pack a clean ZIP.") {
          HStack(spacing: 14) {
            tutorialAction("eye", "Preview")
            Image(systemName: "chevron.right").foregroundStyle(Ink.secondary)
            tutorialAction("slider.horizontal.3", "Prepare")
            Image(systemName: "chevron.right").foregroundStyle(Ink.secondary)
            tutorialAction("archivebox", "Pack")
          }
        }
    case .defaults:
      tutorialPage(
        title: "Choose your packing defaults.",
        body: "Dragging a parcel name uses these settings automatically. You can change them later in Settings.") {
          VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
              Text("Format").frame(width: 78, alignment: .leading)
              ForEach(PackFormat.availableCases.filter(\.isUsable), id: \.self) { format in
                choice(format.label, selected: store.packaging.format == format) {
                  store.packaging.format = format
                }
              }
            }
            HStack(spacing: 6) {
              Text("Compression").frame(width: 78, alignment: .leading)
              ForEach(PackStrength.allCases, id: \.self) { strength in
                choice(strength.label, selected: store.packaging.strength == strength) {
                  store.packaging.strength = strength
                }
              }
            }
            Text(store.packaging.strength.hint).font(.system(size: 10)).foregroundStyle(Ink.secondary)
            Toggle("Remove Mac-only ZIP clutter", isOn: $store.packaging.cleanMacMetadata)
            Toggle("Add the date to packed parcel names", isOn: $store.packaging.appendDate)
          }.font(.system(size: 11)).toggleStyle(.checkbox).padding(18)
            .background(Ink.canvas, in: RoundedRectangle(cornerRadius: 16))
        }
    case .shortcut:
      tutorialPage(
        title: "Open Parcels from anywhere.",
        body: "Use the global shortcut or shake your pointer whenever Parcels is collapsed. Click the shortcut now to choose another combination.") {
          VStack(spacing: 12) {
            ShortcutRecorder(shortcut: shortcuts.shortcut, onRecord: shortcuts.update)
              .frame(width: 150, height: 38)
            Text(shortcuts.message).font(.system(size: 10)).foregroundStyle(Ink.moss)
            Text("You can change this later in Settings → Shortcuts.")
              .font(.system(size: 10)).foregroundStyle(Ink.secondary)
          }.padding(20).background(Ink.canvas, in: RoundedRectangle(cornerRadius: 16))
        }
    }
  }

  private func tutorialPage<Visual: View>(
    title: String, body: String, @ViewBuilder visual: () -> Visual
  ) -> some View {
    VStack(spacing: 16) {
      visual().frame(maxWidth: .infinity, minHeight: 205, maxHeight: 225)
      Text(title).font(.custom(Ink.serif, size: 28)).foregroundStyle(Ink.green)
      Text(body).font(.system(size: 13)).foregroundStyle(Ink.secondary)
        .multilineTextAlignment(.center).lineSpacing(5).frame(maxWidth: 430)
    }
  }

  private func tutorialFile(_ icon: String, _ name: String) -> some View {
    VStack(spacing: 8) {
      Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(Ink.moss)
      Text(name).font(.system(size: 10, weight: .medium)).lineLimit(1)
    }.frame(width: 92, height: 92).background(Ink.canvas, in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.line))
  }

  private func tutorialAction(_ icon: String, _ label: String) -> some View {
    VStack(spacing: 10) {
      Image(systemName: icon).font(.system(size: 24, weight: .light)).foregroundStyle(Ink.moss)
      Text(label).font(.system(size: 10, weight: .medium))
    }.frame(width: 104, height: 94).background(Ink.canvas, in: RoundedRectangle(cornerRadius: 15))
      .overlay(RoundedRectangle(cornerRadius: 15).stroke(Ink.line))
  }

  private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).font(.system(size: 10, weight: selected ? .semibold : .medium))
        .foregroundStyle(selected ? Color.white : Ink.text)
        .frame(maxWidth: .infinity).padding(.vertical, 7)
        .background(selected ? Ink.green : Ink.paper, in: Capsule())
        .overlay(Capsule().stroke(selected ? Ink.green : Ink.line))
    }.buttonStyle(.plain)
  }

  private func move(_ offset: Int) {
    let index = min(max(step.rawValue + offset, 0), OnboardingStep.allCases.count - 1)
    guard let destination = OnboardingStep(rawValue: index) else { return }
    withAnimation(Motion.layoutRelayout) { step = destination }
  }

  private func finish() {
    store.savePackaging()
    store.finishWelcome()
    AppController.shared.closeTutorial()
  }
}
