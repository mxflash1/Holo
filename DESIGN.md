# Holo interface direction

Holo should feel like a quiet macOS instrument: spatial, precise, and calm. It should not look like a generic analytics dashboard or a science-fiction control panel.

References were reviewed on July 16, 2026.

## Reference lessons

- Apple places Liquid Glass in the functional layer—navigation and controls—and recommends standard materials for content. Use system components first and custom glass sparingly. See [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) and [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/).
- Linear's 2026 refresh says interface elements should not compete for attention they have not earned, and that structure should be felt rather than seen. Holo therefore uses fewer icons, separators, borders, and elevated containers. See [A calmer interface for a product in motion](https://linear.app/now/behind-the-latest-design-refresh).
- Things succeeds through a stable sidebar, a single obvious working area, progressive disclosure, and purposeful motion. Holo keeps advanced sensing and rejection controls out of the primary path. See [Things](https://culturedcode.com/things/).
- Raycast's 2026 Mac redesign uses Liquid Glass in ways that support the function of a launcher while staying familiar and compact. Holo follows the same rule for its toolbar and primary controls. See [The New Raycast](https://www.raycast.com/blog/the-new-raycast).
- Apple's recognition of iA Writer and Mela reinforces task focus, contextual dimming, and attention to interaction details over decoration. See the [2025 Apple Design Awards](https://developer.apple.com/design/awards/2025/).
- The community-maintained [Slopless design directory](https://www.slopless.design/) is useful as a pattern audit, not a design authority: it identifies the repeated gradients, inflated cards, interchangeable dashboards, and filler copy that make generated interfaces converge on the same look.

## Anti-slop rules

1. No purple–cyan gradients, neon glow, decorative blobs, or forced dark mode.
2. No bento grid of interchangeable metric cards.
3. No boxes inside boxes. A container must communicate real grouping or interaction.
4. No uppercase eyebrow copy, excessive tracking, or oversized marketing headings inside the app.
5. One semantic accent color. Status colors are reserved for success, warning, recording, and error.
6. No decorative icon tiles. Symbols identify actions or objects only.
7. No invented metrics or ornamental charts. Every number must come from real capture or evaluation data.
8. Liquid Glass is for toolbar and important controls. Content uses standard system materials.
9. Prefer native `NavigationSplitView`, `List`, `Form`, `Table`, `LabeledContent`, `Gauge`, `ProgressView`, menus, sheets, and toolbars.
10. Motion explains a state change; nothing continuously pulses merely to look alive.

## Signal-processing lessons

- [Acustico](https://www.cs.dartmouth.edu/~hci/papers/Acustico.pdf) detects a surface tap as a short power pulse whose neighboring windows are substantially quieter. Holo applies the same temporal principle after capture, with deliberately looser thresholds because it has only the MacBook microphone rather than contact accelerometers.
- Essentia's [EffectiveDuration](https://essentia.upf.edu/reference/std_EffectiveDuration.html) descriptor explicitly distinguishes percussive from sustained sounds using time above 40% of the envelope maximum. Holo combines that cue with late-to-impact energy and early-energy concentration; no single cue rejects an event by itself.
- Research on [on-device mechano-acoustic touch classification](https://doi.org/10.3390/app11114834) supports combining temporal and spectral features with a learned classifier. Holo uses ten spatially varied captures per broad zone and a regularized linear boundary, while retaining nearest-example novelty and user-recorded negative checks.

## Screen hierarchy

Approved October 7, 2026. Native system appearance, typography and accessible controls remain the visual foundation.

- **Overview:** two broad left/right zones around the MacBook, visible assigned actions and a compact result strip.
- **My Desks:** saved desks and their surface/position notes, explicit selection, New Desk, Calibrate, Accuracy Test, Actions and Location controls. New Desk opens a blank naming form before capture.
- **Shared Sounds:** standalone capture, counts, save/cancel and explicit clearing for talking, typing, mouse clicks, laptop touch and background noise. Reused automatically across compatible desks.
- **Locations:** automatic switching, measured accuracy, per-desk saved locations and radius selection. No hidden primary controls in nested menus.
- **Actions:** one action per left/right zone, using native controls.
- **Settings:** a shortcut recorder with persistence, cancellation and conflict feedback; microphone/background behavior; Advanced access to the retained diagnostic, export, recording and experimental sensing tools.

The sidebar lists everyday sections first and saved desks directly beneath them. Settings and microphone state sit at the bottom. Calibration, accuracy evaluation and diagnostics appear as current tasks when opened. Preserve all user data and experimental tools unless deletion is explicitly approved.

The default window is 1040 × 700, with a 940 × 640 minimum. Use available space for desk selection and actual actions rather than decorative content. Follow the system light/dark appearance and reduced-motion preference.
