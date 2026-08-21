# Error Scenarios and Handling

A catalog of the common errors in the `architecture-3d` skill and how to handle them so the user's experience is preserved.

---

## ERR-01: Three.js unavailable (an unreachable CDN)

**Cause**: the user is offline on the first run, or the CDN is blocked by a corporate firewall.

**Detection**: the `<script type="module">` fails to import, or `THREE` stays `undefined` after loading.

**Tratamento**:

```javascript
try {
    const mod = await import("https://cdn.jsdelivr.net/npm/three@0.158.0/build/three.module.js");
    window.THREE = mod;
} catch (e) {
    document.getElementById("loader").innerHTML = `
        <div class="error-panel">
            <h2>The 3D library could not be loaded</h2>
            <p>This visualization needs internet access to download Three.js once.
               Connect to the internet and reload the page.</p>
            <p>Technical detail: ${e.message}</p>
        </div>`;
    return;
}
```

Text always follows the installation's language, with no em dashes.

---

## ERR-02: WebGL not supported

**Cause**: a browser without WebGL (extremely rare today, but possible on old VMs or in restricted corporate environments).

**Detection**: `new THREE.WebGLRenderer()` throws or returns `null`.

**Tratamento**:

```javascript
let renderer;
try {
    renderer = new THREE.WebGLRenderer({ antialias: true });
} catch (e) {
    showFallback("WebGL is not available in your browser. Use an up-to-date Chrome, Firefox or Edge.");
    return;
}
```

The fallback shows a static version of the scene (a pre-rendered screenshot if there is one, or symbolic ASCII art) with a clear message.

---

## ERR-03: JSON malformado

**Cause**: a `modules.json` or `deps.json` with invalid syntax, or missing expected fields.

**Detection**: `JSON.parse` fails, or schema validation reports missing fields.

**Tratamento**:

```javascript
function loadData() {
    const raw = document.getElementById("data").textContent;
    let data;
    try {
        data = JSON.parse(raw);
    } catch (e) {
        showError("Invalid input data: malformed JSON file. " + e.message);
        return null;
    }

    if (!Array.isArray(data.modules)) {
        showError("Invalid input data: 'modules' must be a list.");
        return null;
    }

    data.modules = data.modules.filter((m) => {
        if (!m.name) {
            console.warn("Module with no 'name' discarded:", m);
            return false;
        }
        return true;
    });

    return data;
}
```

Non-fatal errors (one bad module) discard the item with a warning. Fatal errors (an invalid root structure) show a clear message.

---

## ERR-04: An empty project, or no visualizable data

**Cause**: `modules.json` has 0 items, or `deps.json` has 0 edges, or both.

**Detection**: after `loadData()`, count the items.

**Tratamento**:

```javascript
if (data.modules.length === 0) {
    showEmptyState({
        title: "Nothing to visualize yet",
        message: "The project has no detected modules. Run `/reversa` to extract the structure first.",
        actions: [
            { label: "Back to the documentation", href: "index.html" }
        ]
    });
    return;
}
```

A friendly empty state, never a silently empty scene.

---

## ERR-05: A very large project (>5,000 modules with no grouping)

**Cause**: the user forces Code City mode with no grouping on a huge project.

**Detection**: `data.modules.length > 5000` and no grouping strategy enabled.

**Tratamento**: aplicar agrupamento automaticamente e avisar.

```javascript
if (data.modules.length > 5000) {
    showToast("Large project detected (" + data.modules.length + " files). Grouping by folder to keep performance.");
    data.modules = groupByFolder(data.modules);
    config.grouped = true;
}
```

The grouping and its impact appear in the page's permanent footer: "Visualization grouped by folder. Each block represents N files."

---

## ERR-06: Performance degradada (fps < 30)

**Causa**: hardware fraco, projeto no limite superior, sombras pesadas.

**Detection**: measure the `requestAnimationFrame` delta.

```javascript
let frameTimes = [];
function measureFps(time) {
    frameTimes.push(time);
    if (frameTimes.length > 60) frameTimes.shift();
    if (frameTimes.length === 60) {
        const fps = 1000 / ((frameTimes[59] - frameTimes[0]) / 59);
        if (fps < 30 && !config.degraded) {
            degradeQuality();
        }
    }
}
```

**Tratamento progressivo** (`degradeQuality`):

1. Desativar sombras.
2. Reduce pixelRatio to 1.
3. Reduce the particle count in tours.
4. Mostrar toast "Modo de performance ativado".

---

## ERR-07: InstancedMesh limit excedido

**Cause**: an attempt to create an InstancedMesh with more instances than the hardware supports (a limit of ~65k on older hardware via Uint16, but rare).

**Detection**: a console error from Three.js after `setMatrixAt` for high indices.

**Tratamento**:

```javascript
const MAX_INSTANCES = 32768;
if (modules.length > MAX_INSTANCES) {
    showWarning("Instance limit exceeded. Showing only the " + MAX_INSTANCES + " largest.");
    modules = modules.sort((a, b) => b.loc - a.loc).slice(0, MAX_INSTANCES);
}
```

---

## ERR-08: An infinite dependency cycle during layout

**Cause**: a graph with a closed cycle and an iterative layout with no stopping criterion.

**Detection**: count the simulation's iterations; if it passes `MAX_SIM_FRAMES` without converging, abort.

**Handling**: stop the simulation at the frame limit, show the warning "The layout did not converge; the positions may not reflect ideal stability", and draw it anyway.

---

## ERR-09: WebGL context lost

**Cause**: the tab was inactive for a long time, a graphics driver switch, or an overloaded GPU.

**Detection**: the `webglcontextlost` event on the canvas.

**Tratamento**:

```javascript
renderer.domElement.addEventListener("webglcontextlost", (e) => {
    e.preventDefault();
    showToast("Contexto 3D foi perdido. Tentando recuperar...");
});

renderer.domElement.addEventListener("webglcontextrestored", () => {
    rebuildScene();
    showToast("Contexto recuperado.");
});
```

Instead of reloading the page, rebuild the scene on the same canvas. It is important to call `rebuildScene()`, which recreates the textures and buffers.

---

## ERR-10: Sidebar localStorage corrompido

**Cause**: old localStorage data in an incompatible format after a skill update.

**Detection**: `JSON.parse` fails while restoring the state, or a value is outside a slider's expected range.

**Tratamento**: silencioso, descarta e usa default.

```javascript
function loadSliderState(slider) {
    try {
        const saved = localStorage.getItem(`arq3d.${slider.dataset.param}`);
        if (saved !== null) {
            const value = parseFloat(saved);
            if (value >= slider.min && value <= slider.max) {
                slider.value = value;
            }
        }
    } catch (e) {
        // ignore it and keep the default value
    }
}
```

---

## Utility function: showError + showWarning + showToast

```javascript
function showError(message) {
    const panel = document.createElement("div");
    panel.className = "reversa-error-panel";
    panel.innerHTML = `<h2>Erro</h2><p>${escapeHtml(message)}</p>`;
    document.body.appendChild(panel);
}

function showWarning(message) {
    const panel = document.createElement("div");
    panel.className = "reversa-warning-banner";
    panel.textContent = message;
    document.body.appendChild(panel);
    setTimeout(() => panel.remove(), 8000);
}

function showToast(message) {
    const t = document.createElement("div");
    t.className = "reversa-toast";
    t.textContent = message;
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 4000);
}

function escapeHtml(s) {
    return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}
```

The `reversa-error-panel`, `reversa-warning-banner` and `reversa-toast` styles live in the mini-site's shared CSS.

---

## General principle

No error should ever result in a **silent white screen**. Always show a clear message in the installation's language, with an actionable instruction or a clear statement of the limitation. Short messages, no framework jargon, no em dashes.
