# Tulink Mobile — Combined UX and Accessibility Audit

## Audit scope

Current authenticated experience, using native simulator captures from this audit run and code inspection for screens that could not be reached without mutating real account state. Core goal: start or join a shared journey quickly, understand its state, travel together, and review prior journeys.

Evidence:

1. `/private/tmp/tulink-app-audit/01-map-home.png`
2. `/private/tmp/tulink-app-audit/02-journeys.png`
3. `/private/tmp/tulink-app-audit/03-invites.png`
4. `/private/tmp/tulink-app-audit/google-maps-reference-comparison.png`

## Strengths

- The revised home now communicates Tulink's product idea immediately: place search over a live map.
- Map, Journeys, and Invites create a clear top-level information architecture using functions already present in the app.
- A prior destination can be reused with one prominent `Go` action.
- Active journeys remain more important than history and replace the latest-journey treatment when present.
- Existing location, push, invite, WebSocket, and journey providers remain the behavioral source of truth.

## UX risks

### P1 — The app currently presents two visual products

The revised map is bright, warm, and conversational. Journeys and Invites still use the legacy black, grey, uppercase, orange-accent system. Moving between tabs feels like switching apps and weakens confidence that the redesign is intentional.

Recommendation: migrate the shell-adjacent screens first—Journeys, Invites, Profile—using the semantic Tulink tokens and Manrope type scale. Preserve their behavior while replacing dark backgrounds, all-caps headings, and heavy cards.

### P1 — The destination flow still reveals legacy screens after the polished entry point

Home search and companion selection are coherent, but journey preview, participant management, history details, and live-navigation overlays retain dense legacy styling and configuration language. Friction has moved later rather than disappeared.

Recommendation: make the compact ready state the canonical pre-start surface. Show destination, selected people, and one primary action. Move invite code, lag threshold, scheduling, and destructive actions into secondary sheets or overflow menus.

### P1 — Journey history emphasizes implementation metadata

The visible cards prioritize `500m`, zero-participant counts, uppercase status badges, and relative time. Users are more likely to need destination, companions, date/duration, and whether they can repeat the trip.

Recommendation: use a destination-led row with human date, participant avatars/names, status as quiet supporting text, and `Go again` as the row action. Hide lag threshold outside diagnostics or journey settings.

### P2 — Invitations has a weak empty state

The empty screen is technically clear but visually sparse and disconnected from the new warm system. Refresh remains visually prominent even when there is nothing to refresh.

Recommendation: use a warm empty state with a short explanation of how invitations arrive and a secondary `Join with code` action. Retain pull-to-refresh and reduce the app-bar refresh affordance.

### P2 — Profile contains visible nonfunctional or low-value settings

Code inspection shows several settings actions routed to placeholders and an `Edit Profile` surface rendered as a styled container rather than a clear button. This creates dead-end affordances.

Recommendation: show only supported controls. Group account, notifications, navigation voice, privacy, help, and sign-out in a light settings list; remove or mark unavailable actions until implemented.

### P2 — Authentication does not yet introduce the redesigned product

Sign-in and sign-up still use the legacy dark theme and an older app icon asset. The first-run promise does not visually connect to the map-first experience.

Recommendation: use the current brand mark, warm background, Manrope, one clear sign-in form, and a small map/travel cue. Keep existing autofill, password manager, verification, and social-auth behavior.

### P2 — Terminology varies across the product

The code and screens mix `journey`, `trip`, `convoy`, `formation`, and `racer`. These words imply different product models.

Recommendation: use `journey` for the object, `travel together` for the benefit, `people` for participants, and reserve `convoy` for the live technical mode only when it helps the user.

## Accessibility risks

- Several legacy screens use low-contrast grey text over near-black backgrounds; exact contrast needs automated sampling.
- Many controls are icon-only. The revised map controls include tooltips/semantics, but the remaining screens need a semantic-label pass.
- All-caps headings with expanded letter spacing reduce scan speed and should not be the sole hierarchy mechanism.
- Error, status, and selected states frequently depend on orange/grey color differences. Add text and icon cues consistently.
- The full start flow needs screen-reader, Dynamic Type/text scaling, focus order, and touch-target testing; screenshots cannot establish compliance.
- Live-map state changes, journey countdowns, and participant updates need announcement behavior tested with VoiceOver/TalkBack.

## Recommended design sequence

### Phase 1 — Product shell

Keep the new compact map home and redesign Journeys, Invites, and Profile in the same light token system. Establish shared page headers, cards, empty states, status chips, navigation, and buttons.

### Phase 2 — Journey setup

Unify destination search, people selection, ready state, invite code, and start into one progressive flow. Remove the separate create-journey form from the normal path while retaining it only for advanced scheduling/editing.

### Phase 3 — Live journey

Restyle the live Mapbox screen around three priorities: next route action, group health, and end/leave controls. Collapse diagnostics and secondary metrics into a pull-up sheet.

### Phase 4 — History and details

Make journey history destination-led and repeatable. Redesign details as a light summary with route, companions, duration/distance, and one `Go again` action.

### Phase 5 — Entry and trust

Bring sign-in, sign-up, verification, permissions, errors, and offline states into the same brand system. Complete accessibility verification and copy normalization.

## Evidence limits

- The supplied temporary simulator screenshot was unavailable, so the app was recaptured directly.
- Map, Journeys, and the empty Invites state were captured from the running native app.
- Profile, auth, populated invitations, journey preview, and live journey were inspected in code but not used as screenshot-backed claims about exact rendering.
- No VoiceOver/TalkBack, text scaling, reduced motion, localization, or contrast-tool pass was performed in this audit.
