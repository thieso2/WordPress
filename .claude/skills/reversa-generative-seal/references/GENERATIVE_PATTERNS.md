# The Seal's Generative Patterns

A catalog of the 5 established patterns the `generative-seal` skill produces. Each pattern has a distinct look, a central algorithm and parameters derived from the seed.

The general seeding pattern: the sha256 hash (64 hex chars) is cut into 8-char slices, each slice becomes a `parseInt(slice, 16)` and feeds a distinct parameter. That way, different patterns from the same seed share a visual personality.

---

## 1. flow-field

Perlin flow fields: thousands of particles follow vectors derived from noise, leaving organic curved trails. A "turbulent natural" style.

**What it pairs with**: the `sober` (a soft version) and `exploratory` (a luminous version) styles.

**Algoritmo**:

```javascript
let particles = [];
const PARTICLE_COUNT = 500;
const NOISE_SCALE = 0.004;
const STEP = 1.5;

function setup() {
    const canvas = createCanvas(SIZE, SIZE);
    canvas.parent("seal-container");
    randomSeed(seedInt);
    noiseSeed(seedInt);
    background(palette.bg);
    noFill();
    strokeWeight(0.6);

    for (let i = 0; i < PARTICLE_COUNT; i++) {
        particles.push({
            x: random(width),
            y: random(height),
            color: random(palette.foreground),
            life: random(200, 600)
        });
    }
    noLoop();
    drawFlowField();
}

function drawFlowField() {
    particles.forEach((p) => {
        stroke(p.color + "55"); // semi-transparente
        let x = p.x, y = p.y;
        for (let step = 0; step < p.life; step++) {
            const angle = noise(x * NOISE_SCALE, y * NOISE_SCALE) * TWO_PI * 4;
            const nx = x + cos(angle) * STEP;
            const ny = y + sin(angle) * STEP;
            line(x, y, nx, ny);
            x = nx;
            y = ny;
            if (x < 0 || x > width || y < 0 || y > height) break;
        }
    });
}
```

**Parameters derived from the seed**:
- `PARTICLE_COUNT`: 300 a 1000 (slice 0 normalizado).
- `NOISE_SCALE`: 0.002 a 0.008 (slice 1).
- The field's center of gravity (if there is an attractor): an XY coordinate (slices 2 and 3).

**Performance**: up to 1500 particles on an 800x800 canvas without stalling.

---

## 2. particle-orbit

Particles orbiting a center with fading trails, creating a "rotating constellation" pattern.

**What it pairs with**: the `premium` (dark, gold) and `exploratory` (luminous pastels) styles.

**Algoritmo**:

```javascript
const ORBITS = 6;
const PARTICLES_PER_ORBIT = 24;

function setup() {
    const canvas = createCanvas(SIZE, SIZE);
    canvas.parent("seal-container");
    randomSeed(seedInt);
    noiseSeed(seedInt);
    background(palette.bg);
    drawOrbit();
    noLoop();
}

function drawOrbit() {
    const cx = width / 2;
    const cy = height / 2;
    for (let o = 0; o < ORBITS; o++) {
        const radius = (o + 1) * (width / (ORBITS * 2.5));
        const orbitColor = palette.foreground[o % palette.foreground.length];
        const phase = random(TWO_PI);
        const tilt = random(-PI / 6, PI / 6);

        for (let p = 0; p < PARTICLES_PER_ORBIT; p++) {
            const angle = (p / PARTICLES_PER_ORBIT) * TWO_PI + phase;
            const x = cx + cos(angle) * radius;
            const y = cy + sin(angle) * radius * cos(tilt);
            const size = map(noise(angle * 2, o), 0, 1, 1, 6);

            // Trilha
            stroke(orbitColor + "33");
            strokeWeight(0.4);
            noFill();
            arc(cx, cy, radius * 2, radius * 2 * cos(tilt), phase, angle);

            // The particle
            noStroke();
            fill(orbitColor);
            ellipse(x, y, size);
        }
    }

    // Centro
    fill(palette.accent);
    noStroke();
    ellipse(cx, cy, 14);
}
```

**Parameters derived from the seed**:
- The number of orbits: 3 to 8 (slice 0).
- The orbits' tilt: -π/4 to π/4 (slice 1).
- The particle density per orbit (slice 2).

**Performance**: trivial, dezenas de elementos.

---

## 3. crystal-lattice

A symmetric crystalline form derived from a base polygon, with clean geometric subdivisions. An "architectural logotype" style.

**Quando combina**: estilos `dense` (saturado) e `sober` (limpo).

**Algoritmo**:

```javascript
function setup() {
    const canvas = createCanvas(SIZE, SIZE);
    canvas.parent("seal-container");
    randomSeed(seedInt);
    background(palette.bg);
    drawCrystal();
    noLoop();
}

function drawCrystal() {
    const cx = width / 2;
    const cy = height / 2;
    const sides = floor(random(5, 9)); // 5 a 8 lados
    const radius = width * 0.35;
    const layers = floor(random(3, 6));

    push();
    translate(cx, cy);

    for (let layer = layers; layer > 0; layer--) {
        const r = radius * (layer / layers);
        const rotation = (layers - layer) * (PI / sides);
        const color = palette.foreground[layer % palette.foreground.length];
        fill(color);
        stroke(palette.bg);
        strokeWeight(2);

        beginShape();
        for (let i = 0; i < sides; i++) {
            const angle = (i / sides) * TWO_PI + rotation;
            const x = cos(angle) * r;
            const y = sin(angle) * r;
            vertex(x, y);
        }
        endShape(CLOSE);
    }

    // The central core
    fill(palette.accent);
    noStroke();
    const coreRadius = radius * 0.15;
    beginShape();
    for (let i = 0; i < sides; i++) {
        const angle = (i / sides) * TWO_PI;
        vertex(cos(angle) * coreRadius, sin(angle) * coreRadius);
    }
    endShape(CLOSE);

    pop();
}
```

**Parameters derived from the seed**:
- The number of sides: 5 to 8 (slice 0).
- The number of concentric layers: 3 to 6 (slice 1).
- The rotation offset between layers (slice 2).

**Exportable as SVG**: this pattern is purely geometric, ideal for conversion to real SVG for mini-seals.

**Performance**: trivial.

---

## 4. wave-interference

Moiré-style interference patterns: circular waves radiating from several centers and crossing, generating complex textures from simple rules.

**Quando combina**: estilos `premium` (preto + dourado, alta contraste) e `dense`.

**Algoritmo**:

```javascript
function setup() {
    const canvas = createCanvas(SIZE, SIZE);
    canvas.parent("seal-container");
    randomSeed(seedInt);
    pixelDensity(1);
    background(palette.bg);
    drawInterference();
    noLoop();
}

function drawInterference() {
    const centers = [];
    const numCenters = floor(random(2, 5));
    for (let i = 0; i < numCenters; i++) {
        centers.push({
            x: random(width * 0.2, width * 0.8),
            y: random(height * 0.2, height * 0.8),
            frequency: random(0.04, 0.10),
            phase: random(TWO_PI)
        });
    }

    loadPixels();
    for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
            let value = 0;
            centers.forEach((c) => {
                const dx = x - c.x;
                const dy = y - c.y;
                const dist = sqrt(dx * dx + dy * dy);
                value += sin(dist * c.frequency + c.phase);
            });
            value = (value / centers.length + 1) / 2;

            const colorIdx = floor(value * palette.foreground.length);
            const hex = palette.foreground[constrain(colorIdx, 0, palette.foreground.length - 1)];
            const rgb = hexToRgb(hex);
            const i = (y * width + x) * 4;
            pixels[i] = rgb.r;
            pixels[i + 1] = rgb.g;
            pixels[i + 2] = rgb.b;
            pixels[i + 3] = 255;
        }
    }
    updatePixels();
}

function hexToRgb(hex) {
    const h = hex.replace("#", "");
    return {
        r: parseInt(h.slice(0, 2), 16),
        g: parseInt(h.slice(2, 4), 16),
        b: parseInt(h.slice(4, 6), 16)
    };
}
```

**Parameters derived from the seed**:
- The number of centers: 2 to 4 (slice 0).
- The waves' frequency: 0.04 to 0.10 (slice 1).
- Each center's position (slices 2-N).

**Performance**: O(width * height * centers). At 800x800 with 3 centers, ~1.9M operations. Fine for `noLoop()`.

---

## 5. noise-strata

Horizontal noise strata, forming an "abstract landscape" with layers of Perlin noise.

**Quando combina**: estilos `sober` (terracota neutro) e `exploratory` (auroral).

**Algoritmo**:

```javascript
function setup() {
    const canvas = createCanvas(SIZE, SIZE);
    canvas.parent("seal-container");
    randomSeed(seedInt);
    noiseSeed(seedInt);
    background(palette.bg);
    drawStrata();
    noLoop();
}

function drawStrata() {
    const layers = floor(random(4, 8));
    const baseY = height * 0.3;
    const layerHeight = (height - baseY) / layers;

    for (let l = 0; l < layers; l++) {
        const y0 = baseY + l * layerHeight;
        const color = palette.foreground[l % palette.foreground.length];
        fill(color);
        noStroke();
        beginShape();
        vertex(0, height);
        for (let x = 0; x <= width; x += 4) {
            const n = noise(x * 0.005, l * 0.7);
            const y = y0 + n * layerHeight * 1.5;
            vertex(x, y);
        }
        vertex(width, height);
        endShape(CLOSE);
    }

    // Sol/lua decorativa
    fill(palette.accent);
    noStroke();
    const sunX = random(width * 0.2, width * 0.8);
    const sunY = baseY - random(20, 60);
    const sunR = random(30, 70);
    ellipse(sunX, sunY, sunR * 2);
}
```

**Parameters derived from the seed**:
- The number of layers: 4 to 8 (slice 0).
- The horizon's base height: 25% to 40% of the canvas (slice 1).
- The decorative sun/moon's position (slices 2 and 3).

**Performance**: trivial.

---

## Pattern selection from the seed

```javascript
const PATTERNS = ["flow-field", "particle-orbit", "crystal-lattice", "wave-interference", "noise-strata"];

function pickPattern(seedHex, styleHint) {
    const patternIndex = parseInt(seedHex.slice(0, 2), 16) % PATTERNS.length;
    let chosen = PATTERNS[patternIndex];

    // A gentle adjustment by style (choosing among the "compatible" patterns when there is a mismatch)
    if (styleHint && !isStyleCompatible(chosen, styleHint)) {
        chosen = pickCompatible(seedHex, styleHint);
    }
    return chosen;
}
```

The `pattern x style` compatibility is listed at the top of this reference. When there is a declared mismatch, the `pickCompatible` function re-picks among the patterns marked as appropriate for the style.

---

## Manual override

The skill accepts a `forcePattern` parameter to ignore the seed-based derivation and choose the pattern manually, useful when the user wants a specific seal in a style other than the default.
