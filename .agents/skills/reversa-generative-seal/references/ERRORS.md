# Error Scenarios and Handling

The common scenarios in the `generative-seal` skill and how to handle them.

---

## ERR-01: p5.js unavailable (an unreachable CDN)

**Cause**: the user is offline on the first run, or the CDN is blocked.

**Detection**: the global `p5` variable is undefined after the CDN's `<script>`.

**Tratamento**:

```javascript
window.addEventListener("load", () => {
    if (typeof p5 === "undefined") {
        document.getElementById("seal-container").innerHTML = `
            <div class="seal-fallback" style="width: ${SIZE}px; height: ${SIZE}px;
                 background: ${palette.bg}; display: flex; align-items: center;
                 justify-content: center; border-radius: 50%; color: ${palette.fg};">
                <span>Seal unavailable</span>
            </div>`;
        return;
    }
    // setup normal aqui
});
```

The fallback: a minimal inline SVG (a circle + the palette's background color), with no p5 dependency.

---

## ERR-02: Canvas not supported by the browser

**Cause**: a very old browser with no `<canvas>` support (extremely rare today).

**Detection**: `canvas.getContext("2d")` returns `null`.

**Handling**: fall back to an inline SVG with `crystal-lattice` (the pattern most compatible with real SVG).

---

## ERR-03: An invalid or missing seed

**Cause**: the agent called the skill with no seed, or passed an empty string.

**Detection**: validation at the input.

**Tratamento**: fallback seguro.

```javascript
function resolveSeed(rawSeed) {
    if (!rawSeed || typeof rawSeed !== "string" || rawSeed.length === 0) {
        const timestamp = Date.now().toString();
        console.warn("Seed missing, using the timestamp as a fallback. The seal will not be reproducible.");
        return timestamp;
    }
    return rawSeed;
}
```

When the timestamp is used, show a warning in the page's footer (only for a large hero): "Non-reproducible seal (no seed)".

---

## ERR-04: An extreme size

**Cause**: a request for a canvas that is too large (>4096) or too small (<16).

**Detection**: validation of the `size` parameter.

**Tratamento**:

```javascript
function clampSize(requested) {
    const MIN = 16;
    const MAX = 4096;
    if (requested < MIN) {
        console.warn(`Size ${requested} below the minimum (${MIN}). Adjusting.`);
        return MIN;
    }
    if (requested > MAX) {
        console.warn(`Size ${requested} above the maximum (${MAX}). Adjusting.`);
        return MAX;
    }
    return requested;
}
```

Above 1024, pixel-loop patterns like `wave-interference` get heavy. The skill should warn and require `noLoop()` with a cached canvas.

---

## ERR-05: A palette with invalid colors

**Cause**: the palette received has malformed hex or a missing field.

**Detection**: a validation regex on each color.

**Tratamento**:

```javascript
function validatePalette(palette) {
    const HEX_RX = /^#[0-9a-fA-F]{6}$/;
    const required = ["bg", "foreground", "accent", "fg"];
    for (const field of required) {
        if (!(field in palette)) {
            throw new Error(`Invalid palette: field '${field}' missing.`);
        }
    }
    if (!Array.isArray(palette.foreground) || palette.foreground.length === 0) {
        throw new Error("Invalid palette: 'foreground' must be a non-empty list.");
    }
    [palette.bg, palette.accent, palette.fg].forEach((c) => {
        if (!HEX_RX.test(c)) throw new Error(`Invalid color: ${c}`);
    });
    palette.foreground.forEach((c) => {
        if (!HEX_RX.test(c)) throw new Error(`Invalid color in foreground: ${c}`);
    });
}
```

If the palette is invalid, fall back to `palettes.sober` (the most conservative fallback palette) and log the failure.

---

## ERR-06: Insufficient contrast

**Cause**: a palette whose `accent` and `bg` are too close, making the central element invisible.

**Detection**: `contrastRatio(accent, bg) < 4.5` (see PALETTE_BY_STYLE.md).

**Tratamento**: derivar `accent` ajustado automaticamente.

```javascript
function ensureContrast(palette) {
    if (contrastRatio(palette.accent, palette.bg) < 4.5) {
        const bgIsLight = luminance(palette.bg) > 0.5;
        palette.accent = bgIsLight ? darken(palette.accent, 0.4) : lighten(palette.accent, 0.4);
    }
    return palette;
}
```

---

## ERR-07: The chosen pattern is incompatible with the style

**Cause**: the seed-based derivation produced a pattern visually incompatible with the chosen style (e.g. `crystal-lattice` in the `exploratory` style).

**Detection**: the compatibility table declared in `GENERATIVE_PATTERNS.md`.

**Handling**: re-roll among the compatible patterns.

```javascript
const STYLE_COMPATIBLE = {
    sober: ["flow-field", "crystal-lattice", "noise-strata"],
    premium: ["particle-orbit", "wave-interference"],
    dense: ["crystal-lattice", "wave-interference"],
    exploratory: ["flow-field", "particle-orbit", "noise-strata"]
};

function pickCompatible(seedHex, styleHint) {
    const allowed = STYLE_COMPATIBLE[styleHint];
    if (!allowed) return PATTERNS[0];
    const idx = parseInt(seedHex.slice(2, 4), 16) % allowed.length;
    return allowed[idx];
}
```

---

## ERR-08: Very poor performance on a mini-seal

**Cause**: a heavy pattern on a small canvas consuming disproportionate CPU.

**Detection**: measure the time between `setup` and the final `draw`.

**Handling**: if the canvas is mini (<200px) and the chosen pattern is `wave-interference` (a pixel loop), switch automatically to `crystal-lattice` (simple geometry) with a message in the console.

---

## ERR-09: Several instances of the same seal on the same page

**Cause**: the mini-seal appears on every page of the mini-site. Reloading p5.js and generating a canvas on each one is wasteful.

**Handling**: generate the seal once as SVG (for `crystal-lattice`) or as a PNG dataURI (for the other patterns) and embed it inline on every page. The skill accepts a `mode: "svg" | "dataURI" | "html"` parameter to return the appropriate format.

```javascript
function exportAs(mode) {
    if (mode === "svg") return canvasToSvg();
    if (mode === "dataURI") return canvas.elt.toDataURL("image/png");
    return wrapInStandaloneHtml(canvas);
}
```

---

## ERR-10: Corrupted seed in localStorage

Not directly applicable, because the skill does not persist state between runs. The seed always comes from the caller (the orchestrating agent), and reproducibility depends only on that.

If the caller lost the seed, the agent should recompute it from soul.md (sha256). This skill is not responsible for that.

---

## General principle

The seal is a **decorative** element. A seal failure must never break the whole page. In every scenario above, there is a fallback that always renders something: a colored circle, a minimal SVG, a simplified version. Never a white screen.

Messages follow the installation's language, with no em dashes.
