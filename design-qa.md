# Tablet landscape redesign — design QA

## Scope

- Branch: `codex/tablet-landscape-redesign`
- Target: 13-inch iPad landscape, with the same adaptive layout available to compatible Apple Silicon Mac windows.
- Phone portrait behaviour remains the compact fallback.
- Reviewed states: signed-out authentication, signed-in home/map, and profile.
- Code-reviewed states: email verification and active live convoy, which share the same responsive breakpoint and panel primitives.

## Visual sources

- Authentication: `/Users/wesleynyamu/.codex/generated_images/01a04ddf-e9da-74a1-91f6-ec262dc49be9/exec-21aa9170-acbc-45af-bd2b-385ffae0fd97.png`
- Home: `/Users/wesleynyamu/.codex/generated_images/01a04ddf-e9da-74a1-91f6-ec262dc49be9/exec-cbe895d3-1ca0-4fdf-86ec-43d7b0c47e2c.png`
- Profile: `/Users/wesleynyamu/.codex/generated_images/01a04ddf-e9da-74a1-91f6-ec262dc49be9/exec-ee87d5df-9fcd-4bad-a82d-9a64fec9a2f4.png`
- Live convoy: `/Users/wesleynyamu/.codex/generated_images/01a04ddf-e9da-74a1-91f6-ec262dc49be9/exec-c65d4fa6-9b45-4f30-803b-2b2d7d30cadf.png`

## Rendered evidence

- Authentication: `/private/tmp/tulink-ipad-auth-landscape-final-with-art.png`
- Home: `/private/tmp/tulink-ipad-home-landscape.png`
- Profile: `/private/tmp/tulink-ipad-profile-landscape.png`
- Side-by-side authentication comparison: `/private/tmp/tulink-auth-design-comparison-final.png`
- Side-by-side home comparison: `/private/tmp/tulink-home-design-comparison.png`
- Side-by-side profile comparison: `/private/tmp/tulink-profile-design-comparison.png`
- Destination overlay before/final comparison: `/private/tmp/tulink-destination-overlay-comparison.png`

The implementation was rendered on iPad Air/Pro 13-inch simulators in landscape. Simulator screenshots are 2048 × 2732 because `simctl` stores the rotated device buffer; they were rotated 90 degrees and fit to 1200 × 837 before being placed beside the source. The source and implementation were therefore compared at the same visible landscape density.

Full-view comparisons were sufficient to judge hierarchy, spacing, panel width, navigation placement, and typography. The rendered form controls remained readable at comparison scale, so no additional focused crop was necessary.

## Findings and fixes

### Authentication

- Initial finding — P2: the left panel lacked the map-led visual anchor from the approved reference.
- Fix: generated and added a real Tulink-coloured map illustration sized for the lower half of the panel.
- Post-fix result: split composition, form width, CTA hierarchy, and artwork placement match the reference direction. Existing Tulink logo and production auth controls were intentionally preserved.

### Home

- Result: map remains the primary canvas, search stays compact at the top-left, and navigation becomes a floating rail without blocking the map.
- Expected state difference: the reference contains a populated recent-journey card while the simulator account had no recent journey. The existing functional card is constrained to the same left-side tablet region when data is present.
- Follow-up finding — P2: destination search still inherited the phone bottom sheet's tall portrait proportions in landscape.
- Fix: tablet landscape now uses a compact, keyboard-aware left-side dialog with a close control. Empty search is 220 logical pixels tall; the panel expands up to 560 logical pixels when loading, showing an error, or displaying results. Phone layouts retain the bottom sheet.
- Post-fix result: the map, last-journey context, and tablet navigation remain visible while destination search is active, with no large empty portrait-shaped surface.

### Profile

- Result: overview and travel statistics occupy the left column; settings and account actions occupy the right column. Content no longer stretches across the full tablet width.
- P3: the production screen retains the existing plain app bar and copy instead of reproducing decorative mock-only treatments.

### Live convoy and verification

- Live convoy panels now anchor to the left edge in landscape with the map kept visible for driving context. The active-journey state was not available in the simulator account, so this state was verified through its responsive layout code and existing journey widget tests.
- Email verification uses the same split structure as authentication, with constrained content and a dedicated illustration panel.

## Regression and accessibility checks

- Wide layout only activates for tablet-class devices/windows at least 900 logical pixels wide in landscape.
- Phone landscape does not opt into the tablet layout.
- Narrow or portrait windows use the existing compact layout.
- Navigation retains semantic labels and badge semantics.
- Existing authentication, logout, convoy status, and journey progress tests pass.
- iOS simulator build succeeds for the 13-inch iPad target.
- Static analysis reports no errors.

final result: passed
