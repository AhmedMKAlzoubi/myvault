---
version: 1
slug: "myvault-ui-index-html"
primary_target: "myvault/ui/index.html"
related_targets: ["android_app/lib/main.dart","browser-extension/content.js"]
---

# MyVault app shell (desktop window, Android app, extension, printed PDF)

Mode: Operate. Users open it many times a day to find, copy or fill a credential, and sometimes to add one. Family users must manage it without jargon.

## Direction contract

THESIS: Concealment you can see. Every secret sits under a fine security-envelope tint and lifts only where you ask. This refuses the category default of a navy dashboard with a shield icon and bullet-dot password fields.

OWN-WORLD: Laid-paper ground #F4F5F7 with a cooler panel layer, ink #1B2433, tint linework in envelope blue #2F4A7A at low density, glassine window panes (pale #E9EEF6 with a 1px #C9D2E3 rule), franking red #B4432E only for destructive actions and danger. Dark mode uses a night envelope: ground #12161E, ink #E6EAF2, tint #6F8CC4. One grotesque (Segoe UI Variable) on a 1px hairline grid; Cascadia Mono only for secret values, keys and ciphertext. Square-ish 6px corners.

STORY: The vault feels sealed and calm. You search, open an entry, lift the tint on one value, copy it, and it seals again. Sync, backup and the extension show plainly what leaves the device and how.

FIRST VIEWPORT: The lock screen is a full-bleed tint field with one glassine window (around 420px) at the optical centre, holding the wordmark, the master password field and an Unlock button. After unlock: a 300px index rail (search, kind filter, entries), a detail sheet on the right with the title as the only headline, concealed values drawn as tint swatches, and a tools strip (Generator, Sync, Backup, Browser, Settings).

FORM: Security envelope tint, candidate 3 of 7, seed key 372751f0. Raises: one grotesque on a hairline grid with crosshair corners on the PDF (plate section); state shown in structure, with a dotted outline for concealed and solid ink for revealed (exposure record); nothing labelled twice (catalog sleeve).

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

Signature interaction: reveal. The tint swatch over a secret wipes away left to right (clip-path, 220ms ease-out) and reseals after 20s or on blur. Reduced motion swaps it instantly.
