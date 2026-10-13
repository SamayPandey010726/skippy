import SwiftUI

/// Saved pack recipes: name the current setup, re-apply it in one tap.
/// Inspired by CleanShot's editable project presets.
struct PackProfilePicker: View {
  @EnvironmentObject private var store: ParcelStore
  @State private var profiles: [PackProfile] = PackProfileStore.load()
  @State private var savingName = ""
  @State private var showSave = false
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Recipe").font(.system(size: 11)).foregroundStyle(Ink.secondary)
        Spacer()
        if !profiles.isEmpty {
          Menu {
            ForEach(profiles) { profile in
              Button(profile.name) { apply(profile) }
            }
            Divider()
            Button("Manage…") { showSave = true }
          } label: {
            HStack(spacing: 4) {
              Text("Saved recipes").font(.system(size: 11))
              Image(systemName: "chevron.down").font(.system(size: 9))
            }.foregroundStyle(Ink.moss)
          }.menuStyle(.borderlessButton)
        }
        Button {
          savingName = ""
          showSave = true
        } label: {
          Image(systemName: "bookmark.plus").font(.system(size: 12))
        }.buttonStyle(.plain).foregroundStyle(Ink.moss)
          .help("Save the current pack settings as a recipe")
      }
      if showSave {
        VStack(spacing: 8) {
          TextField("Recipe name", text: $savingName).textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
          HStack {
            if !profiles.isEmpty {
              Text("\(profiles.count) saved").font(.system(size: 10))
                .foregroundStyle(Ink.secondary)
            }
            Spacer()
            Button("Cancel") { showSave = false }.buttonStyle(.plain)
              .font(.system(size: 11)).foregroundStyle(Ink.secondary)
            Button("Save recipe") { save() }.buttonStyle(MossButtonStyle(secondary: true))
              .disabled(savingName.trimmingCharacters(in: .whitespaces).isEmpty)
          }
          if !profiles.isEmpty {
            ForEach(profiles) { profile in
              HStack {
                Button(profile.name) { apply(profile) }.buttonStyle(.plain)
                  .font(.system(size: 11))
                Spacer()
                Button {
                  profiles.removeAll { $0.id == profile.id }
                  PackProfileStore.save(profiles)
                } label: {
                  Image(systemName: "trash").font(.system(size: 10))
                }.buttonStyle(.plain).foregroundStyle(Ink.secondary)
              }
            }
          }
        }.padding(10).background(Ink.cream.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
      }
    }
  }
  private func apply(_ profile: PackProfile) {
    profile.apply(to: &store.packaging)
    store.savePackaging()
    store.notice = "“\(profile.name)” recipe applied."
    showSave = false
  }
  private func save() {
    let name = savingName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }
    profiles.removeAll { $0.name == name }
    profiles.append(PackProfile(name: name, from: store.packaging))
    PackProfileStore.save(profiles)
    savingName = ""
    showSave = false
    store.notice = "“\(name)” recipe saved."
  }
}
