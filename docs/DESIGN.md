---
name: Duct-Tape VPN
description: A personal VPN utility with neutral surfaces, blue controls and grouped settings.
colors:
  primary: "#0066cc"
  primary-dark: "#2997ff"
  canvas: "#f5f5f7"
  canvas-dark: "#000000"
  surface: "#ffffff"
  surface-dark: "#1c1c1e"
  ink: "#1d1d1f"
  ink-dark: "#ffffff"
  secondary: "#636366"
  secondary-dark: "#aeaeb2"
typography:
  display:
    fontFamily: ".SF Pro Text, Segoe UI, Arial"
    fontSize: "34px"
    fontWeight: 600
    letterSpacing: "-1px"
  headline:
    fontFamily: ".SF Pro Text, Segoe UI, Arial"
    fontSize: "28px"
    fontWeight: 600
    lineHeight: 1.15
    letterSpacing: "-0.7px"
  title:
    fontSize: "22px"
    fontWeight: 600
  body:
    fontFamily: ".SF Pro Text, Segoe UI, Arial"
    fontSize: "17px"
    lineHeight: 1.47
  button:
    fontSize: "17px"
    fontWeight: 400
  status:
    fontSize: "15px"
    lineHeight: 1.45
  caption:
    fontSize: "13px"
    lineHeight: 1.45
rounded:
  group: "18px"
  settings-control: "24px"
  glass: "28px"
spacing:
  small: "6px"
  inline: "12px"
  row: "16px"
  page: "24px"
  group: "28px"
  hero: "44px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.surface}"
    typography: "{typography.button}"
  button-primary-dark:
    backgroundColor: "{colors.primary-dark}"
    textColor: "{colors.surface}"
    typography: "{typography.button}"
  button-text:
    textColor: "{colors.primary}"
    typography: "{typography.button}"
  settings-group:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.group}"
  settings-group-dark:
    backgroundColor: "{colors.surface-dark}"
    rounded: "{rounded.group}"
  settings-row:
    padding: "15px 16px"
  group-field:
    typography: "{typography.body}"
    padding: "6px 16px"
  glass-navigation:
    rounded: "{rounded.glass}"
  power-indicator:
    width: "132px"
    height: "132px"
---

# Design System: Duct-Tape VPN

## Overview

**Creative North Star: "Apple utility"**

The interface puts connection status and a single primary action ahead of setup. Pale gray or black surrounds solid grouped surfaces. Blue identifies controls and the active tunnel illustration. The user requested an Apple reference and restrained translucent glass; the build applies glass to the settings control and connection-details navigation.

This document records `clients/app/lib/main.dart` and `presentation/{components,home,settings}.dart`. The former green dial design is superseded. The implementation combines Material controls with Cupertino icons, switches, routes and dialogs. It does not establish full native platform conformance.

**Key Characteristics:**

- One centered connection action with a separate live status sentence.
- A narrow, scrolling column on mobile and desktop.
- Solid grouped settings with fine inset separators.
- Translucent navigation controls and system font selection.

## Colors

One blue accent sits against neutral surfaces. The frontmatter records the explicit palette in `AppColors` and the application theme. Derived error, disabled and interaction colors remain owned by Flutter's generated color scheme and component defaults.

### Primary

Connection blue identifies filled actions, text actions, row icons, the requested-on switch and an active tunnel indicator. The dark appearance uses the brighter `primary-dark` token. Filled actions retain white text in both appearances.

**The Control Blue Rule.** Use the theme's blue for actions and the tunnel indicator; keep status explanations readable as text independently of color.

### Neutral

Canvas is the page background. Surface is the solid settings-group background and the base color for glass. Ink supplies strong foregrounds and faint glass borders. Secondary supplies supporting copy, inactive power icon and separators. Each role has an explicit dark counterpart.

The active power indicator uses blue at 9% opacity for its fill and 22% for its border. The inactive border uses secondary at 12%. Group separators use secondary at 20%.

## Typography

The application selects `.SF Pro Text` on iOS and macOS and `Segoe UI` on other targets, with `Segoe UI` and `Arial` fallbacks. The frontmatter family list describes this platform selection; it is not an instruction to request an Apple font on Windows. Cupertino controls can use their own framework typography.

### Hierarchy

- Display is the VPN title and the settings introduction, with semibold weight and tightened tracking.
- Headline is the centered connection sentence. Its compact line height allows wrapping at large text sizes.
- Title is the theme's secondary heading role. The primary screens mainly use display, headline and body.
- Body is the theme's reading style. Settings rows, fields and buttons use the same base size, with component-specific inherited line heights.
- Status is the connection explanation and small feedback text. The brand subtitle also uses its size.
- Caption is group context, row subtitles and footers. Row subtitles use a 1.4 line height; footers use the caption token's 1.45. Group labels inherit their line height.

**The Scaling Rule.** Preserve Flutter text scaling and vertical scrolling. The large-text capture shows the headline wrapping and lower groups continuing below the viewport.

Sizes are Flutter logical pixels at text scale 1. The portable frontmatter uses `px` to represent those values. Platform font scaling changes the rendered size.

## Layout

Both screens use safe-area layout and a centered column capped at 560 logical pixels. There is no breakpoint that converts the app into a dashboard or navigation rail. Home uses horizontal page insets from the page token, a top inset of 20 and a bottom inset from the same page token. Its header, central action block and lower groups distribute vertically when space permits. The central block has hero spacing above and below. On shorter screens or at large text sizes, the entire page scrolls.

Settings uses a vertically scrolling list with the same horizontal inset, a top inset from the row token and a bottom inset of 32. Group separation uses the group spacing token. Rows have expandable text columns so descriptions can wrap next to their icons and trailing controls.

Settings-row icons are 23 logical pixels with a 14-pixel gap before text. Trailing controls have a 12-pixel gap. Separators begin at the row inset and are 0.5 pixels thick within a 1-pixel divider slot.

## Elevation & Depth

The custom surfaces have no drop shadows. Solid surface fills distinguish groups from the canvas. `Glass` clips a backdrop blur with sigma 20 on both axes, a surface fill at 82% opacity and a 1-pixel ink border at 7% opacity. The app bar is transparent with zero elevation and no surface tint. Framework switches and dialogs retain their own rendering.

**The Navigation Glass Rule.** Reuse glass for the settings shortcut and connection-details navigation. Settings forms stay on solid surfaces so labels and entered values remain clear.

The power indicator animates its decoration over 240 milliseconds. `MediaQuery.disableAnimationsOf` reduces that custom duration to zero. Other route and control transitions use framework defaults.

## Shapes

Settings groups have the group radius. The settings shortcut uses the settings-control radius; the wider connection-details control uses the glass radius. Filled actions use `StadiumBorder`, which stays pill-shaped as text scales. The power indicator is a circle, distinct from the actionable button below it. Avoid substituting the obsolete large ON/OFF dial for this hierarchy.

## Components

### Buttons

Filled actions use blue, white text, a stadium shape and a minimum size of 120 by 48 logical pixels. The home button adds internal child padding of 18 horizontally and 3 vertically to the framework's button padding. It shows a 22-pixel progress indicator while busy and disables repeated requests.

Text actions are blue with a minimum target of 44 by 44. Settings wraps them with 6-pixel horizontal and 2-pixel vertical padding. Destructive actions use the generated scheme's error color. Hover, focus, pressed and disabled treatments come from Material defaults; no custom interaction-color palette is established.

### Cards / Containers

`SettingsGroup` clips its children to a solid rounded surface. Optional labels and footers sit outside the group, inset by the row spacing token, with a 9-pixel gap. Separators divide related rows. These are grouped controls and information, rather than independent dashboard cards.

### Inputs / Fields

`GroupField` places borderless Material text fields inside a settings group. It uses body-sized text, 12-pixel vertical content padding, and outer padding recorded in the frontmatter. Labels, multiline invitation input and numeric input keep their native field behavior. Suggestions and autocorrect are disabled for configuration values. Validation appears as readable feedback above groups; feedback is a live region.

### Navigation

Home opens settings through a `CupertinoPageRoute`. Settings has a transparent app bar, a semibold body-sized title and an explicit back button. The gear shortcut has a tooltip. Tappable settings rows show a chevron unless they supply a trailing control. These routes retain framework transitions and navigation behavior.

### Connection controls

The power illustration contains a Cupertino power icon at 49 logical pixels. It changes blue only after a fresh connection check passes. A Cupertino activity indicator replaces the icon while connecting. The filled button is the connection control. The redundant request switch has been removed.

**The Verified Connection Rule.** The headline and connection details use one state calculation with three labels: Not connected, Connecting and Connected. A running service alone cannot produce Connected. The Windows personal adapter checks the actual IPv4 routes, home-server ICMP, uncached DNS and TLS-validated IPv4 HTTPS in a background worker. It repeats checks after ten seconds, expires passing evidence after thirty seconds, and fails a check after fifteen seconds. The controller also bounds Connecting to twenty seconds. Service changes invalidate earlier checks. Connection evidence has its own timestamp and never becomes a protection attestation.

## Do's and Don'ts

### Do

- Do use the explicit light and dark role pairs together.
- Do retain the single primary action, grouped settings and scrolling text layout.
- Do use framework controls, icons and feedback semantics already present in the Flutter build.
- Do describe connection and protection from their actual state fields.

### Don't

- Don't restore the superseded green dial palette or its ON/OFF control.
- Don't replace the status explanation with a color-only success cue.
- Don't treat rendered test states as proof of a working VPN connection.

Evidence: `artifacts/ui/mobile.png`, `desktop.png`, `dark-connected.png`, `large-text.png` and `settings.png` are Flutter widget renders with simulated VPN states and Segoe UI/Cupertino fonts. They show layout and appearance, not iOS or Android hardware certification, gesture testing or VPN operation. No shipping raster assets are required by this interface. The sidecar's HTML/CSS previews translate Flutter shapes for documentation; Flutter source remains authoritative for framework behavior.

Operational evidence is separate from the captures. The standard Flutter suite passed 14 tests and static analysis reported no issues. The Windows integration test in `clients/app/integration_test/windows_connection_test.dart` passed with the actual `NativeVpn` plugin: it connected a paired device, observed the tunnel up, reached the server at `10.77.0.1`, selected the DuctTape internet route, completed IPv4 HTTPS, then disconnected and restored ordinary routing. The privileged installer separately passed handshake, route, DNS and IPv4 HTTPS checks. Server-side WireGuard confirmed a handshake and traffic; the existing Tailscale service remained active. The Windows test used LAN transport to the server.

Not canonized or repaired: the shared Apple-inspired control language does not establish Android Material adaptation or Apple hardware conformance. These checks do not certify a kill switch, mobile hardware behavior or connectivity through an external WAN. The interface continues to distinguish a working tunnel from verified protection.
