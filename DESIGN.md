---
name: MyVault
description: Offline password and secrets manager in the security-envelope world.
colors:
  paper: "#F4F5F7"
  panel: "#ECEEF2"
  sheet: "#FBFBFC"
  ink: "#1B2433"
  ink-2: "#47526A"
  ink-3: "#5F687A"
  rule: "#D5DAE3"
  rule-2: "#C2C9D6"
  envelope-blue: "#2F4A7A"
  tint-wash: "#E4E9F2"
  franking-red: "#B4432E"
  ok-green: "#2D6A4A"
  night-paper: "#12161E"
  night-sheet: "#1A202A"
  night-ink: "#E6EAF2"
  night-blue: "#7E98CC"
typography:
  wordmark:
    fontFamily: "Segoe UI Variable Display, Segoe UI, system-ui, sans-serif"
    fontSize: "26px"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: "-0.02em"
  title:
    fontFamily: "Segoe UI Variable Display, Segoe UI, system-ui, sans-serif"
    fontSize: "24px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "-0.015em"
  body:
    fontFamily: "Segoe UI Variable Text, Segoe UI, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.45
  label:
    fontFamily: "Segoe UI Variable Text, Segoe UI, system-ui, sans-serif"
    fontSize: "12.5px"
    fontWeight: 500
    lineHeight: 1.3
  secret:
    fontFamily: "Cascadia Mono, Cascadia Code, Consolas, monospace"
    fontSize: "13.5px"
    fontWeight: 400
    lineHeight: 1.6
rounded:
  sm: "4px"
  md: "6px"
  lg: "8px"
  window: "10px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "14px"
  lg: "22px"
  page: "44px"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    rounded: "{rounded.md}"
    height: "32px"
    padding: "0 13px"
  button-primary-hover:
    backgroundColor: "{colors.envelope-blue}"
  button-secondary:
    backgroundColor: "{colors.sheet}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    height: "32px"
  button-danger:
    backgroundColor: "{colors.sheet}"
    textColor: "{colors.franking-red}"
    rounded: "{rounded.md}"
  input:
    backgroundColor: "{colors.sheet}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    height: "36px"
    padding: "0 11px"
  chip:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.ink-2}"
    rounded: "13px"
    height: "26px"
  chip-selected:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
  list-item-selected:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    rounded: "{rounded.md}"
---

# Design System: MyVault

## Overview

**Creative North Star: "The Security Envelope"**

MyVault looks like the inside of a bank envelope: fine blue linework printed so
nobody can read the contents against the light. Everything secret sits under
that tint, and the tint lifts only from the one value you ask to see. The rest
of the interface is quiet paper and ink, so the tint always means *hidden*.

The world runs across the Windows window (HTML/CSS), the Android app (Flutter),
the browser extension's on-page cards and popup, and the printed backup PDF
(which carries the same tint band and adds registration crosshairs at the
corners).

**Key Characteristics:**
- Cool paper ground, one ink, envelope blue as the only accent.
- The tint (fine sine-wave linework, optionally crossed by a slower vertical wave) marks concealment and nothing else.
- One workhorse sans for everything, plus a monospace for secret values, keys and ciphertext only.
- State is carried by structure: a dashed outline means concealed, a solid outline means revealed, solid ink fill means selected or on.

## Colors

### Primary
- **Ink** (#1B2433): text, primary buttons, the selected list row, switches when on. Inverts to night ink in dark mode.

### Secondary
- **Envelope Blue** (#2F4A7A): the tint linework, focus rings, the caret and text selection, digits inside passwords, and the hover state of primary buttons. Night Blue (#7E98CC) takes the role in dark mode.

### Tertiary
- **Franking Red** (#B4432E): destructive actions and errors only.
- **OK Green** (#2D6A4A): the connected dot and the top strength level only.

### Neutral
- **Paper** (#F4F5F7) is the ground; **Panel** (#ECEEF2) is the rail and app bars; **Sheet** (#FBFBFC) is the reading surface and inputs.
- **Ink 2 / Ink 3** carry labels and secondary text (both ≥4.5:1 on paper).
- **Rule / Rule 2** are the 1px hairlines and control borders.

### Named Rules
**The Tint Means Hidden Rule.** The tint appears only on concealed values, the lock screen, empty states, and the PDF header band. It is never decoration on ordinary content.

**The One Accent Rule.** Envelope blue is the only hue besides the danger red and the OK green. Categories are told apart by icons, not colours.

## Typography

**UI face:** Segoe UI Variable on Windows (Display cut for the wordmark and titles, Text cut for everything else), Roboto on Android. Product UI wants a workhorse sans, so no display face is added.
**Secret face:** Cascadia Mono / Consolas (desktop), the platform monospace (Android).

### Hierarchy
- **Wordmark** (600, 26px): lock screen only.
- **Title** (600, 24px, -0.015em): the entry or tool name, the only headline on a sheet.
- **Body** (400, 14px, 1.45): values, prose (max 64ch).
- **Label** (500, 12.5px): field labels, hints, chips.
- **Secret** (mono 13.5px; 17px in the generator, 24px in the big generator): revealed secrets, keys, tokens. Digits go envelope blue and symbols go bold, so a password reads back character by character.

### Named Rules
**The Nothing Twice Rule.** Each value has one label. The title is the only headline. No eyebrow or kicker above a heading.

## Layout

Desktop: a 300px rail (wordmark and lock, search, kind filter, entry list, New entry, tools) beside a scrolling sheet whose content tops out at 760px wide with 44px gutters (26px under 960px). Field rows are a three-column grid (150px label, value, actions) separated by 1px rules. The lock screen is a full-bleed tint field with one 420px window at the optical centre.

Android: an app bar on panel, a search and filter band, then the list. The entry view uses stacked label-over-value rows with trailing actions. Bottom sheets hold the generator and the new-entry picker.

## Elevation & Depth

Almost flat. Hairlines do the separating. Only two things float: the lock-screen window (soft 8–24px shadow plus a 4px inner sheet ring, read as the envelope's glassine window) and toasts or extension cards (the same soft shadow). There are no hard offset shadows.

## Shapes

Gently squared: 4px on secret swatches, 6px on controls, 8px on panels and cards, 10px on the lock window. Chips and switches are pills.

## Components

### Buttons
Primary is an ink fill with paper text that turns envelope blue on hover. Secondary is sheet with a rule-2 border. Danger has red text and turns into a solid red confirm for the final "Delete for good". Icon buttons are 32px ghost squares.

### Chips
The kind filter (All, Logins, API keys, SSH keys, Notes) shows a count. Selected chips fill with ink.

### Inputs / Fields
36px, rule-2 border, envelope-blue focus border with a 3px soft ring. Secret inputs are masked (`-webkit-text-security` for multi-line keys) with a reveal toggle beside them.

### Navigation
The rail list on desktop, where the selected row is a solid ink fill; tools at the rail foot with a sheet-coloured current state. App bar actions on Android.

### Secret Swatch (signature)
A concealed value is a dashed-outline box filled with the tint, at a fixed width so it doesn't reveal the value's length. Reveal wipes the tint away left to right (220ms, ease-out); the outline turns solid. It reseals after 20s. Under reduced motion the swap is instant.

### Switch
Off is a dashed outline with a grey knob; on is a solid ink track with a paper knob. Used for every generator toggle.

## Do's and Don'ts

### Do:
- **Do** put every secret behind the swatch, and copy it through the private clipboard.
- **Do** use plain words in copy ("Encrypted, and stored only on this computer"), and keep cryptographic detail on Settings and in the docs.
- **Do** keep the tint fine and quiet: about a 3.5px line pitch at 30–42% opacity on the lock field.

### Don't:
- **Don't** use the tint as a background texture for ordinary panels.
- **Don't** use colour to tell entry kinds apart. Use the kind icons.
- **Don't** use Unicode glyphs as icons. Icons are drawn with one 1.5px stroke family.
- **Don't** add an eyebrow or kicker above a title.
