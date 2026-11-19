# Parcels notch: interaction direction and implementation status

This is a code review, not a runtime assessment. The scores below are provisional: no build or interactive testing has been performed for this revision.

## A. Feel audit

| Quality | Score | Evidence and uncertainty |
| --- | --- | --- |
| Response | 3/5 | Widget buttons have press-state feedback in `NotchWidgetButtonStyle`; actual input latency is unmeasured. |
| Directness | 2/5 | The grid supports dragging cards to reorder, but there is no measured one-to-one gesture tracking or velocity handoff. |
| Interruptibility | 2/5 | SwiftUI springs are retargetable, but the window, hover and dismissal paths need live interruption checks. |
| Spring behavior | 3/5 | `Motion` defines spring recipes and a reduced-motion alternative; the actual window transition has not been evaluated. |
| Spatial consistency | 2/5 | Pinned circles open their module, but the collapsed and expanded window geometry differ; visual continuity needs review. |
| Materials | 3/5 | The existing panel uses native glass and supports reduced transparency; overlap and contrast need visual review. |
| Reduced motion | 3/5 | Central animation recipes check macOS Reduce Motion; not every transition has been audited. |

## B. Interaction redesign

Hover the main pill to reveal the dashboard; hover a pinned circle to reveal its tool. Keep the pointer path between trigger and panel continuous and provide a grace period on exit. Scrolling settles on complete widget pages. A reverse gesture should retarget the current presentation state rather than waiting for a transition to finish. At the first and last page, resist overscroll rather than wrap unexpectedly. With Reduce Motion, reveal immediately or crossfade and omit scaling.

## C. Motion spec

Animate position, scale and opacity where possible. Start press feedback on pointer down. Target a critically damped spring around 0.3–0.4 seconds for panel movement; use small overshoot only when a release carries momentum. Preserve the drag's velocity when moving or snapping a widget. Avoid keyframes for pointer-driven motion; do not animate layout independently from the pointer. The current native code does not yet implement all these behaviors.

## D. Materials and hierarchy

Use the system material for the main surface, with a solid fallback for Reduce Transparency. Use discrete darker circles for pinned tools and a single surface for the active panel. No full-screen scrim for normal notch interactions; use a dimmed selection layer only for explicit screen capture or drawing. Keep shadows narrow on small circles and wider but subtle on the expanded panel.

## E. Implementation checklist

- [x] Existing mixed-size widget grid and paged layout.
- [x] Separate pinned widget circles and hover routing in code.
- [x] Screen-selection entry points for OCR and QR scanning in code.
- [ ] Verify the hover corridor, exit grace period and panel anchoring on macOS.
- [ ] Implement velocity-aware widget dragging, edge resistance and interruption across panel transitions.
- [x] Add code for multi-region screenshot composition, calendar, calculator and a manual Google Lens clipboard handoff.
- [x] Add code for a screen drawing overlay and user-defined commands with confirmation.
- [ ] Build font detection and automatic Google Lens upload; expand drawing with erasing and export.
- [x] Add horizontal overflow for pinned items in code.
- [ ] Verify pinned-item overflow and complete keyboard and accessibility navigation.
- [ ] Audit all requested tools, shortcuts, screen-recording permissions, privacy behavior and reduced-motion paths.
- [ ] Decide on a supported solution for third-party system notification mirroring. Apple’s documented notification center API returns the calling app’s notifications, not a general feed.
- [ ] [NEEDS INPUT] Identify a reliable font-recognition approach and acceptable confidence/quality bounds before presenting font matches as facts.

## F. Do / Don't

Do keep the shelf one widget away; keep widget controls legible; make pinned targets discoverable; ask for capture permission only when needed; respect Reduce Motion and Reduce Transparency.

Don't open an external app on hover; animate a selected screen region away from the pointer; hide permission failures; imply a font guess is certain; or claim that all Mac notifications can be mirrored via the app's own notification API.
