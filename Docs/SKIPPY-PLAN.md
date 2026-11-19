# Skippy implementation plan

1. Preserve the Swift macOS 14 app, shelf storage, clipboard, shortcuts, licences, indexed identifiers and saved widget layout. Rename the user-facing application and its development bundle.
2. Give the existing widget modules a single quiver mark. Hover reveals the pinned arrows in place. Click an arrow to open its own tool panel beside the chosen icon. Keep the launcher open while the pointer crosses into the panel. Click the mark or use the existing hotkey for all arrows.
3. Provide menu bar, physical notch, floating, display-edge and Dock placements. Persist placement and floating display position. Use a native Dock tile and Dock menu for the system-owned Dock surface.
4. Exercise the Mac app, unit suite, file pipelines and launch from a terminal on the repository's macOS runner. Boot iPhone and iPad simulator devices with Xcode's simctl and record native Mac interaction evidence. The Mac app uses AppKit and is the current application target.
5. Publish the development bundle, feature brief, test evidence and recordings to the project owner for review.

## Design research

DuoBar's creator describes a combined mark that unfolds in place on hover, a menu immediately beneath each clicked icon, and a delay before the icons fold away. The third product screenshot shows the primary mark stays at the outer edge during expansion. Skippy applies this interaction to its own tools. [Article](https://www.linkedin.com/pulse/hiding-menu-bar-icons-never-worked-me-so-i-merged-them-teekam-suthar-lhxof) · [Hover screenshot](https://www.teekamsuthar.com/duobar/screenshots/DuoBar-03-unfolds-on-hover.png)

The GitHub menu-bar and SwiftPM packaging skills informed the accessory activation policy, separation of placement state from views, terminal launch flow, bundle assembly and signature verification. The existing package and build scripts own the implementation. [Menu-bar skill](https://github.com/Dimillian/Skills/tree/main/macos-menubar-tuist-app) · [Packaging skill](https://github.com/Dimillian/Skills/tree/main/macos-spm-app-packaging)
