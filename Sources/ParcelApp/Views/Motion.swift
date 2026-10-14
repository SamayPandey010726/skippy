import AppKit
import SwiftUI

/// Centralized motion recipes for Parcel. Springs are the default —
/// they carry velocity when retargeted, which is what makes the shelf
/// feel physical. Fixed-duration curves are reserved for dismissals.
///
/// Frequency budget (Apple HIG-aligned):
/// - 100×/day actions (scroll, hover, list tap): system defaults only
/// - 10×/day core (drop, summon): subtle signature ≤300ms + one haptic
/// - 1×/day: expressive scene ≤1s
/// - Rare moments: hero treatment
///
/// Reduce Motion: every recipe returns `nil` when the system setting
/// is on (macOS: NSWorkspace.accessibilityDisplayShouldReduceMotion),
/// so callers passing the recipe to `.animation` get an instant set.
/// Motion must never carry information alone.
enum Motion {
  private static var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }
  /// Icon bounce, button tap.
  static var snappyTap: Animation? {
    reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.45)
  }
  /// Drag spring-back, drop bounce.
  static var playfulSettle: Animation? {
    reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.5)
  }
  /// Shelf summon / reveal (open with personality).
  static var uiReveal: Animation? {
    reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.75)
  }
  /// Grid/list switch, reorder.
  static var layoutRelayout: Animation? {
    reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8)
  }
  /// Numeric settle, no wobble.
  static var counterRollUp: Animation? {
    reduceMotion ? nil : .spring(response: 1.2, dampingFraction: 0.85)
  }
  /// Dismissal: fast, flat, no overshoot. Bouncy exits feel reluctant.
  static var dismiss: Animation? {
    reduceMotion ? nil : .easeIn(duration: 0.13)
  }
  /// Hover lift: object rises toward the pointer.
  static var hoverLift: Animation? {
    reduceMotion ? nil : .easeOut(duration: 0.18)
  }
  /// Press squish: deliberately slow, builds toward an action.
  static var pressSquish: Animation? {
    reduceMotion ? nil : .easeInOut(duration: 0.45)
  }
}
