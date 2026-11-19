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
    reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.6)
  }
  /// Drag spring-back, drop bounce.
  static var playfulSettle: Animation? {
    reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.62)
  }
  /// Shelf summon / reveal (open with personality).
  static var uiReveal: Animation? {
    reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.82)
  }
  /// Grid/list switch, reorder.
  static var layoutRelayout: Animation? {
    reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.86)
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
    reduceMotion ? nil : .easeOut(duration: 0.09)
  }
  /// Press feedback.
  static var pressSquish: Animation? {
    reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.85)
  }
  static var pendulum: Animation? {
    reduceMotion ? nil : .interpolatingSpring(stiffness: 70, damping: 7)
  }
  static var bagOpen: Animation? {
    reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.88)
  }
  static var fanOpen: Animation? {
    reduceMotion ? nil : .interpolatingSpring(stiffness: 150, damping: 20)
  }
  static var dialDetent: Animation? {
    reduceMotion ? nil : .interpolatingSpring(mass: 0.85, stiffness: 120, damping: 13)
  }
  static var folderFlap: Animation? {
    reduceMotion ? nil : .easeInOut(duration: 0.16)
  }
  static var fileCatch: Animation? {
    reduceMotion ? nil : .timingCurve(0.45, 0, 0.15, 1, duration: 0.42)
  }
  static var catchSettle: Animation? {
    reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)
  }
  static var ribbonTie: Animation? {
    reduceMotion ? nil : .timingCurve(0.45, 0, 0.15, 1, duration: 0.72)
  }
}
