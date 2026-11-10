# Design decision

Three directions were considered:

| Direction | Character | Decision |
|---|---|---|
| Quiet dial | Fine circular outline, neutral type, generous space, muted green intent state | Selected: equally recognizable in a small desktop window and on a phone; ON/OFF remains legible without color |
| Mechanical toggle | Horizontal track with a sliding thumb | Familiar, but its small thumb reads as a setting rather than the single primary action |
| Typographic rail | Large ON/OFF words beside a thin vertical rule | Compact, but its activation target and selected state are less obvious on touch screens |

The selected design uses a warm near-white surface, dark evergreen text, a restrained green requested-ON surface, and a fine outline. It avoids textures, shields, charts, decorative controls and dashboard cards. System sans-serif type respects native fallback; the compact brand mark uses modest tracking. Spacing is based on 4/8-point increments; the switch is 184 logical pixels, secondary controls at least 48. Content caps at 520 logical pixels and scrolls under text scaling rather than clipping.

The switch shows desired state. The status below it independently describes permission, tunnel, protection and verification. A requested ON surface is not a security indicator. “Protected” requires all conditions in the state model, including an enforced protection mechanism and verification no older than 30 seconds. Current native adapters deliberately do not emit that verification field. Apple reports limited protection because includeAllNetworks still has OS exceptions; Android needs user-configured lockdown for crash blocking.

Light/dark color palettes, keyboard-focusable Material controls, semantic labels, live status, text scaling and reduced-motion behavior are implemented in Flutter source. Motion lasts 180 ms and is disabled by the OS reduced-motion setting. OFF uses ordinary networking only when actual tunnel/protection state supports that description.

The four PNGs in `docs/design/` were rendered with Chromium and visually inspected as concept previews. They check layout at 440×640, 390×844, dark appearance and 320-pixel large-text width. No horizontal overflow was found. They are not Flutter render tests, screen-reader certification or device screenshots. Flutter widget tests are present but unrun because the SDK download is denied by the current environment policy.
