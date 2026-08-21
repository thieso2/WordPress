# Architecture Tour

An animated camera moving through the scene at a cinematic pace, with a synchronized **narrative overlay**. It works like a "trailer" for the system: someone hits play and the video unfolds on its own, pausing at key points with explanatory captions.

## Conceito

The Tour is not a standalone mode; it is an **animated layer** placed on top of any of the other modes (Code City, Dependency Graph 3D, Layer Stack, Call Graph). The skill receives a sequence of waypoints and narrations, and the camera travels between them.

## When to use it

- Presentations to non-technical stakeholders.
- Onboarding new devs ("hit play and see what the system looks like").
- A short executive demo (1 to 3 minutes).
- Accompanying the mini-site's `deck.html`.

## Data model: the choreography

```json
{
  "baseMode": "code-city",
  "duration": 90,
  "waypoints": [
    {
      "at": 0,
      "camera": { "position": [200, 250, 400], "target": [0, 0, 0] },
      "overlay": "This is the payments system seen from above."
    },
    {
      "at": 12,
      "camera": { "position": [50, 30, 80], "target": [40, 0, 20] },
      "overlay": "The tallest district, src/payments, holds 40% of the code."
    },
    {
      "at": 24,
      "camera": { "position": [80, 60, 60], "target": [60, 20, 30] },
      "highlight": ["src/payments/charge.ts", "src/payments/refund.ts"],
      "overlay": "Charge and refund are the central files."
    },
    {
      "at": 40,
      "camera": { "position": [-100, 80, 200], "target": [-50, 0, 0] },
      "switchMode": "dependency-graph",
      "overlay": "Now let's look at its dependencies."
    }
  ]
}
```

- `at`: the second on the timeline when the waypoint fires.
- `camera`: the camera's position and target on arrival.
- `highlight`: a list of node/module IDs to highlight (the rest are dimmed).
- `overlay`: the caption's text, in the installation's language.
- `switchMode` (optional): switches the base mode mid-tour, with a transition.

## Interpolation algorithm

Between two waypoints, the camera interpolates its position and target with easing.

```javascript
import { CatmullRomCurve3 } from "https://cdn.jsdelivr.net/npm/three@0.158.0/build/three.module.js";

const positions = waypoints.map((w) => new THREE.Vector3(...w.camera.position));
const targets = waypoints.map((w) => new THREE.Vector3(...w.camera.target));
const positionCurve = new CatmullRomCurve3(positions);
const targetCurve = new CatmullRomCurve3(targets);

let startTime = null;
function playTour() {
    startTime = performance.now();
    controls.enabled = false; // turn manual interaction off
    animateTour();
}

function animateTour() {
    const now = performance.now();
    const elapsed = (now - startTime) / 1000;

    if (elapsed >= tour.duration) {
        finishTour();
        return;
    }

    const t = elapsed / tour.duration; // 0..1
    const pos = positionCurve.getPoint(t);
    const tgt = targetCurve.getPoint(t);
    camera.position.copy(pos);
    camera.lookAt(tgt);

    updateOverlay(elapsed);
    updateHighlights(elapsed);

    renderer.render(scene, camera);
    requestAnimationFrame(animateTour);
}
```

## Overlay narrativo

A text box positioned in the footer or on the side, with smooth transitions between lines.

```html
<div id="tour-overlay">
    <p id="tour-text"></p>
    <div id="tour-progress"><div id="tour-progress-fill"></div></div>
    <div id="tour-controls">
        <button id="tour-pause">Pausar</button>
        <button id="tour-restart">Reiniciar</button>
        <button id="tour-skip">Pular</button>
    </div>
</div>
```

```javascript
function updateOverlay(elapsed) {
    const current = waypoints.findLast((w) => w.at <= elapsed);
    if (!current) return;
    const textEl = document.getElementById("tour-text");
    if (textEl.dataset.at !== String(current.at)) {
        textEl.dataset.at = current.at;
        textEl.style.opacity = 0;
        setTimeout(() => {
            textEl.textContent = current.overlay;
            textEl.style.opacity = 1;
        }, 300);
    }
    const progress = (elapsed / tour.duration) * 100;
    document.getElementById("tour-progress-fill").style.width = progress + "%";
}
```

## Destaque de elementos

During the highlights, the selected modules become emissive and the rest reduce their opacity.

```javascript
function updateHighlights(elapsed) {
    const current = waypoints.findLast((w) => w.at <= elapsed);
    const highlightIds = new Set(current?.highlight ?? []);

    modules.forEach((m, i) => {
        const isHighlighted = highlightIds.size === 0 || highlightIds.has(m.name);
        const targetOpacity = isHighlighted ? 1.0 : 0.15;
        // animating opacity via an InstancedMesh is more involved;
        // an alternative: switch to a desaturated color when the opacity is low
        const baseColor = colorForModule(m);
        const finalColor = isHighlighted ? baseColor : dim(baseColor, 0.3);
        instanced.setColorAt(i, new THREE.Color(finalColor));
    });
    instanced.instanceColor.needsUpdate = true;
}

function dim(hex, factor) {
    const c = new THREE.Color(hex);
    c.r *= factor; c.g *= factor; c.b *= factor;
    return c.getHex();
}
```

## Switching modes mid-tour

When a waypoint has `switchMode`, fade the current scene out, dispose of it, create the new scene, and fade in.

```javascript
function switchSceneMode(newMode) {
    fadeOverlay.style.opacity = 1;
    setTimeout(() => {
        clearScene();
        if (newMode === "dependency-graph") buildDependencyGraph();
        else if (newMode === "code-city") buildCodeCity();
        // etc
        fadeOverlay.style.opacity = 0;
    }, 600);
}
```

## Controles do tour

- **Pause**: stops `requestAnimationFrame`, freezing time.
- **Restart**: resets `startTime` to now.
- **Skip**: jumps to the next waypoint.
- **Manual takeover**: if the user drags the mouse over the scene, the tour stops and OrbitControls is enabled.

```javascript
renderer.domElement.addEventListener("pointerdown", () => {
    if (tourPlaying) {
        pauseTour();
        controls.enabled = true;
        showResumeButton();
    }
});
```

## Trilha sonora opcional

The tour may include subtle ambient music via an `<audio>` element embedded in base64 (short, ~30s looped) or via the Web Audio API generating procedural drones. Default: no audio.

## Generating the choreography

The skill either receives ready-made waypoints OR generates them automatically from heuristics:

- Iniciar de cima olhando o centro.
- Dive into the 3 tallest buildings (Code City).
- Fly through the dependency graph, highlighting the most central node.
- End by showing the layer stack of the violating layers (if there are any).

Each heuristic can be enabled or disabled via a parameter.

## Sidebar do tour

```html
<aside id="sidebar">
    <h3>Architecture Tour</h3>

    <label>Total duration
        <input type="range" min="30" max="300" value="90" data-param="duration"> s
    </label>

    <label>Modo base
        <select data-param="baseMode">
            <option value="code-city">Code City</option>
            <option value="dependency-graph">Dependency Graph</option>
            <option value="layer-stack">Layer Stack</option>
        </select>
    </label>

    <label>
        <input type="checkbox" data-param="autoPlay"> Tocar ao abrir
    </label>

    <label>
        <input type="checkbox" data-param="includeViolationsScene" checked> Include the violations scene
    </label>

    <button id="play-tour">Tocar Tour</button>
    <button id="pause-tour">Pausar</button>
    <button id="restart-tour">Reiniciar</button>
</aside>
```

## Performance

The Tour inherits the base mode's performance. Adding the tour costs little: only camera interpolation and opacity animations. Be careful with `switchMode` mid-tour: dispose + rebuild can cause a 200-500ms stutter.
