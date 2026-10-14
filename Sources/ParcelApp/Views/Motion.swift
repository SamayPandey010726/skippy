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
/// Reduce Motion: every animated view reads `accessibilityReduceMotion`
/// and uses instant-set / nil animation when true.
enum Motion {
  /// Icon bounce, button tap.
  static let snappyTap = Animation.spring(response: 0.25, dampingFraction: 0.45)
  /// Drag spring-back, drop bounce.
  static let playfulSettle = Animation.spring(response: 0.3, dampingFraction: 0.5)
  /// Shelf summon / reveal (open with personality).
  static let uiReveal = Animation.spring(response: 0.4, dampingFraction: 0.75)
  /// Grid/list switch, reorder.
  static let layoutRelayout = Animation.spring(response: 0.45, dampingFraction: 0.8)
  /// Numeric settle, no wobble.
  static let counterRollUp = Animation.spring(response: 1.2, dampingFraction: 0.85)
  /// Dismissal: fast, flat, no overshoot. Bouncy exits feel reluctant.
  static let dismiss = Animation.easeIn(duration: 0.13)
  /// Hover lift: object rises toward the pointer.
  static let hoverLift = Animation.easeOut(duration: 0.18)
  /// Press squish: deliberately slow, builds toward an action.
  static let pressSquish = Animation.easeInOut(duration: 0.45)
  /// Returns nil when Reduce Motion is on, so callers can pass `nil`
  /// to `.animation` and get an instant set instead.
  static func respectingReduceMotion(_ animation: Animation) -> Animation? {
    UIAccessibility.isReduceMotionEnabled ? nil : animation
  }
}
