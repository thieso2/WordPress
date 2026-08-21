# Palettes by Visual Style

The table of palettes the seal uses, derived from the visual style the user chose in `/reversa-documentation`.

Each palette has 4 fields:

- `bg`: the canvas's background color.
- `foreground`: the list of main colors the pattern uses (3 to 5 colors).
- `accent`: the highlight color for the central elements (1 color).
- `fg`: the text color of the label outside the canvas.

---

## Palette: `sober`

A sober, technical, neutral style. Focused on legibility and timelessness.

```json
{
  "bg": "#f5f3ee",
  "foreground": ["#3d4a5c", "#7c8a99", "#a06b4a", "#4f6b5d", "#bdb4a4"],
  "accent": "#1e2937",
  "fg": "#1e2937"
}
```

The visual translation:
- Fundo: papel quebrado.
- Foreground: petrol blue, stone gray, terracotta, moss green, sand.
- Accent: azul-meia-noite profundo.

**A dark variant**: for a mini-seal on a dark header, mirror it (bg ↔ fg).

---

## Palette: `premium`

A cinematic, luxurious, dark style. Focused on contrast and shine.

```json
{
  "bg": "#0a0a14",
  "foreground": ["#d4af37", "#7a1c2a", "#b8b8b8", "#1e2b4f", "#3a3a4a"],
  "accent": "#f4d03f",
  "fg": "#eaeaea"
}
```

The visual translation:
- Fundo: preto noite-azulada.
- Foreground: gold, wine red, silver, midnight blue, smoke gray.
- Accent: light gold (brighter than the base gold).

**Typical use**: the hero of an executive presentation, the cover seal of premium documentation.

---

## Palette: `dense`

A dense, saturated style with high visual density. Focused on distinguishing between many categories.

```json
{
  "bg": "#f8f9fa",
  "foreground": ["#ff7a3e", "#00c6c6", "#e93f8f", "#a3d930", "#5b3fce"],
  "accent": "#1a1a2e",
  "fg": "#1a1a2e"
}
```

The visual translation:
- Fundo: branco gelo.
- Foreground: orange, cyan, magenta, lime, indigo.
- Accent: preto-azulado.

**Typical use**: documentation for a system with many components to tell apart; the seal covers multiple hues.

---

## Palette: `exploratory`

An exploratory, ethereal, luminous style. Focused on 3D and contemplation.

```json
{
  "bg": "#0d0d1a",
  "foreground": ["#ffb3ba", "#a0e7e5", "#c9b6e8", "#fff5b8", "#b8e0d2"],
  "accent": "#ffffff",
  "fg": "#eaeaea"
}
```

The visual translation:
- Fundo: preto-violeta profundo.
- Foreground: aurora pink, glacier cyan, mist lilac, soft yellow, watery green.
- Accent: branco luz.

**Typical use**: documentation with a strong 3D presence; the seal converses with `architecture.html`'s aesthetic.

---

## Palette `other` (the fallback)

When the user chooses "Other" in the style menu and gives a free-form description, the skill maps that description to the nearest palette, or applies a basic heuristic:

```javascript
function paletteFromFreeform(text) {
    if (/(luxury|premium|cinemat|dark)/.test(lower)) return palettes.premium;
    if (/(technical|sober|clean|minimal)/.test(lower)) return palettes.sober;
    if (/(dense|saturated|colorful|vibrant)/.test(lower)) return palettes.dense;
    if (/(explor|3D|luminous|ethereal)/.test(lower)) return palettes.exploratory;
    return palettes.sober; // a safe fallback
    return palettes.sober; // fallback seguro
}
```

---

## Color distribution within the palette

Even with 5 colors in `foreground`, the seal does not use them equally. The visual proportion rule:

| Position in the palette | Visual proportion in the seal |
|---|---|
| 1st color | 50% (dominant) |
| 2nd color | 25% (secondary) |
| 3rd color | 15% |
| 4th color | 7% |
| 5th color | 3% (a trace) |

Patterns like `flow-field` and `wave-interference` inherit that distribution automatically (color 1 appears on more particles).

Patterns like `crystal-lattice` use the colors in distinct layers, but the most visible (outer) layers use colors 1 and 2; the inner layers use 3, 4, 5.

---

## Automatic adaptation for the mini-seal

On mini-seals (<200px), the palette is simplified to just 3 colors:

```javascript
function simplifyForMini(palette) {
    return {
        ...palette,
        foreground: palette.foreground.slice(0, 3)
    };
}
```

It keeps legibility and visual impact even at a reduced size.

---

## Contrast check

Before rendering, verify that `accent` has enough contrast with `bg` for patterns that highlight the center (a minimum ratio of 4.5:1 per WCAG AA).

```javascript
function contrastRatio(hex1, hex2) {
    const lum = (hex) => {
        const { r, g, b } = hexToRgb(hex);
        const sRGB = [r, g, b].map((c) => {
            const v = c / 255;
            return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
        });
        return 0.2126 * sRGB[0] + 0.7152 * sRGB[1] + 0.0722 * sRGB[2];
    };
    const l1 = lum(hex1);
    const l2 = lum(hex2);
    const lighter = Math.max(l1, l2);
    const darker = Math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
}
```

If the contrast check fails, replace `accent` with an automatically derived lighter/darker version.
