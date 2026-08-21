# Layer Stack 3D

A visualization of **architectural layers** stacked vertically, each layer a plane holding its modules, connected by vertical arrows showing the dependency flow between layers.

## Mapeamento

| Conceito arquitetural | Visual |
|---|---|
| Camada (UI, Domain, Infra, etc) | Plano horizontal em altura distinta |
| A module inside the layer | A box/disc positioned on the layer's plane |
| An inter-layer dependency | A directed vertical line connecting the modules |
| The flow's direction | An arrowhead at the end of the line |
| A layer violation (a lower layer importing from above) | A pulsing red line |

## When to use it

- Validating that the architecture follows Clean Architecture, Hexagonal, or Onion.
- Detecting **layer violations** (the UI importing straight from Infra, for example).
- Presenting the system to stakeholders who think in layers.
- Compare it side by side with the expected architectural diagram.

**When to avoid it**: systems with no clear layer separation (flat monoliths). Use Code City.

## Layer detection

The skill accepts the layer mapping from the user (via JSON), or tries to infer it from folder patterns.

**An explicit mapping**:

```json
{
  "layers": [
    { "name": "UI", "order": 0, "folders": ["src/components", "src/pages"] },
    { "name": "Application", "order": 1, "folders": ["src/services", "src/use-cases"] },
    { "name": "Domain", "order": 2, "folders": ["src/domain", "src/entities"] },
    { "name": "Infrastructure", "order": 3, "folders": ["src/db", "src/external"] }
  ]
}
```

**A heuristic inference** (when none is provided): a regex over the folder names.

```javascript
const LAYER_PATTERNS = [
    { name: "UI", regex: /(components|pages|views|screens|ui)/i, order: 0 },
    { name: "Application", regex: /(services|use-cases|application|handlers)/i, order: 1 },
    { name: "Domain", regex: /(domain|entities|models|business)/i, order: 2 },
    { name: "Infrastructure", regex: /(db|database|repositories|external|infra|adapters)/i, order: 3 }
];

function inferLayer(folder) {
    for (const p of LAYER_PATTERNS) {
        if (p.regex.test(folder)) return p;
    }
    return { name: "Outros", order: 999 };
}
```

## Algoritmo de layout

### 1. Empilhar camadas verticalmente

```javascript
const LAYER_GAP = 80;
const LAYER_SIZE = 400; // plano 400x400

const layerPlanes = layers.map((layer, i) => ({
    name: layer.name,
    y: i * LAYER_GAP,
    modules: modules.filter((m) => belongsToLayer(m, layer))
}));
```

### 2. Position the modules inside the layer

Simple packing into a 2D grid on the layer's plane.

```javascript
layerPlanes.forEach((layer) => {
    const cols = Math.ceil(Math.sqrt(layer.modules.length));
    const cellSize = LAYER_SIZE / cols;
    layer.modules.forEach((m, idx) => {
        const col = idx % cols;
        const row = Math.floor(idx / cols);
        m.x = (col - cols / 2) * cellSize;
        m.y = layer.y;
        m.z = (row - cols / 2) * cellSize;
    });
});
```

### 3. Renderizar planos de camada

```javascript
layerPlanes.forEach((layer, i) => {
    const planeGeo = new THREE.PlaneGeometry(LAYER_SIZE, LAYER_SIZE);
    const planeMat = new THREE.MeshStandardMaterial({
        color: LAYER_COLORS[i % LAYER_COLORS.length],
        transparent: true,
        opacity: 0.15,
        side: THREE.DoubleSide
    });
    const plane = new THREE.Mesh(planeGeo, planeMat);
    plane.rotation.x = Math.PI / 2;
    plane.position.y = layer.y;
    scene.add(plane);

    // Label da camada lateral
    const label = addLabel(layer.name, new THREE.Vector3(LAYER_SIZE / 2 + 20, layer.y, 0));
    scene.add(label);
});

const LAYER_COLORS = [0x4a9eff, 0x6cc46c, 0xffc857, 0xb39ddb, 0xff9aa2];
```

### 4. Render the modules as discs

```javascript
const moduleGeo = new THREE.CylinderGeometry(1, 1, 0.5, 16);
const moduleMat = new THREE.MeshStandardMaterial({ roughness: 0.5 });
const modulesMesh = new THREE.InstancedMesh(moduleGeo, moduleMat, modules.length);

modules.forEach((m, i) => {
    const dummy = new THREE.Object3D();
    const size = 1 + Math.sqrt(m.loc / 100);
    dummy.position.set(m.x, m.y, m.z);
    dummy.scale.set(size, 1, size);
    dummy.updateMatrix();
    modulesMesh.setMatrixAt(i, dummy.matrix);
});
modulesMesh.instanceMatrix.needsUpdate = true;
scene.add(modulesMesh);
```

### 5. Render the dependencies as vertical lines

```javascript
edges.forEach((e) => {
    const src = modules.find((m) => m.name === e.from);
    const dst = modules.find((m) => m.name === e.to);
    if (!src || !dst) return;

    const isViolation = isLayerViolation(src, dst);
    const color = isViolation ? 0xff5a4f : 0x6c8eb0;

    const points = [
        new THREE.Vector3(src.x, src.y, src.z),
        new THREE.Vector3(dst.x, dst.y, dst.z)
    ];
    const geo = new THREE.BufferGeometry().setFromPoints(points);
    const mat = new THREE.LineBasicMaterial({
        color,
        transparent: true,
        opacity: isViolation ? 1.0 : 0.4
    });
    const line = new THREE.Line(geo, mat);
    if (isViolation) line.userData.pulse = true; // anima opacidade
    scene.add(line);
});
```

### 6. Layer violation detection

The default rule (Clean Architecture): a layer may only depend on layers with a higher `order` (further "inwards").

```javascript
function isLayerViolation(src, dst) {
    return src.layerOrder > dst.layerOrder;
}
```

There may be configurable exceptions (e.g. ports/adapters in hexagonal).

## Animating the violations

The red lines pulse (their opacity oscillates) to draw attention.

```javascript
function pulseViolations(time) {
    scene.traverse((obj) => {
        if (obj.userData?.pulse) {
            obj.material.opacity = 0.5 + 0.5 * Math.sin(time * 0.003);
        }
    });
}
```

## Sidebar de controles

```html
<aside id="sidebar">
    <h3>Layer Stack</h3>

    <label>Spacing between layers
        <input type="range" min="40" max="200" value="80" data-param="layerGap">
    </label>

    <label>
        <input type="checkbox" data-param="showViolations" checked> Highlight violations
    </label>

    <label>
        <input type="checkbox" data-param="showLabels" checked> Module labels
    </label>

    <label>Mostrar apenas
        <select data-param="layerFilter">
            <option value="all">Todas as camadas</option>
            <!-- POPULATED -->
        </select>
    </label>

    <div id="violations-count"></div>

    <button id="reset">Reset</button>
    <button id="export-png">Exportar PNG</button>
</aside>
```

The `#violations-count` counter shows "X violations detected" in real time.

## Interaction

- **Hovering a module**: a tooltip with its name, layer and dependencies.
- **Clicking a violation**: focuses the camera on the two modules involved and shows the relationship's details in the panel.
- **The layer filter**: hides the unselected layers.

## Performance

Layers typically have dozens to a few hundred modules each. A total limit of ~2,000 modules. Above that, group by folder within each layer.
