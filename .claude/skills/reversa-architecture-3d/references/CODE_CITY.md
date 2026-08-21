# Code City

A well-established pattern for 3D software visualization: each file in the project is a **building**, grouped into **districts** that correspond to folders. It lets you grasp the code's size, complexity and distribution at a glance.

## Attribute mapping

| Code attribute | The building's visual attribute |
|---|---|
| Lines of code (LOC) | Height |
| Cyclomatic complexity | Base area (width x depth) |
| The file's folder | District (position on the plane) |
| File type (code, test, config) | Base color |
| Hot path (change frequency or dependents) | Highlight color (red/yellow) |

## When to use it

- An initial overview of an unfamiliar project.
- Spotting very large files (tall buildings) or complex ones (wide buildings).
- Detecting folder grouping (cohesive vs. scattered districts).
- An executive presentation: visually striking and intuitive.

**When to avoid it**: small projects (< 30 files), where the urban metaphor is overkill. Use Dependency Graph 3D or the 2D D3 module map.

## Layout algorithm

### 1. Group by folder

```javascript
const districts = {};
modules.forEach((m) => {
    if (!districts[m.folder]) districts[m.folder] = [];
    districts[m.folder].push(m);
});
```

### 2. Compute each district's size

The district's area is proportional to the number of files. Use simple packing (row by row) or a squarified treemap.

```javascript
function packDistrict(modules, padding = 1) {
    const count = modules.length;
    const cols = Math.ceil(Math.sqrt(count));
    const rows = Math.ceil(count / cols);
    return { cols, rows };
}
```

### 3. Position the districts on the plane

The districts form the city. For up to ~20 folders, pack them into a simple grid. For more, use a treemap.

```javascript
const districtSize = (count) => Math.sqrt(count) * cellSize * 2;
let offsetX = 0;
let offsetZ = 0;
const districtPositions = {};
Object.entries(districts).forEach(([folder, mods], i) => {
    const size = districtSize(mods.length);
    districtPositions[folder] = { x: offsetX, z: offsetZ, size };
    offsetX += size + districtGap;
    if ((i + 1) % gridCols === 0) {
        offsetX = 0;
        offsetZ += size + districtGap;
    }
});
```

### 4. Position the buildings inside a district

```javascript
modules.forEach((m) => {
    const district = districtPositions[m.folder];
    const local = packDistrict(districts[m.folder]);
    const indexInDistrict = districts[m.folder].indexOf(m);
    const col = indexInDistrict % local.cols;
    const row = Math.floor(indexInDistrict / local.cols);
    m.x = district.x + col * cellSize;
    m.z = district.z + row * cellSize;
});
```

### 5. Size each building

```javascript
const LOC_TO_HEIGHT = 0.4;      // 1000 LOC = 400 height units
const COMPLEXITY_TO_WIDTH = 0.8;
const MIN_W = 2;
const MIN_H = 1;

modules.forEach((m) => {
    m.height = Math.max(MIN_H, m.loc * LOC_TO_HEIGHT);
    const baseW = Math.max(MIN_W, Math.sqrt(m.complexity) * COMPLEXITY_TO_WIDTH);
    m.w = baseW;
    m.d = baseW;
});
```

### 6. Render with an InstancedMesh

See `THREE_PATTERNS.md` for the InstancedMesh pattern. Each building is an instance of the same BoxGeometry, with its own matrix and color.

```javascript
const boxGeo = new THREE.BoxGeometry(1, 1, 1);
boxGeo.translate(0, 0.5, 0); // base on the ground
const mat = new THREE.MeshStandardMaterial({ roughness: 0.6 });
const buildings = new THREE.InstancedMesh(boxGeo, mat, modules.length);
buildings.castShadow = true;
buildings.receiveShadow = true;

const dummy = new THREE.Object3D();
const color = new THREE.Color();

modules.forEach((m, i) => {
    dummy.position.set(m.x, 0, m.z);
    dummy.scale.set(m.w, m.height, m.d);
    dummy.updateMatrix();
    buildings.setMatrixAt(i, dummy.matrix);
    color.set(colorForModule(m));
    buildings.setColorAt(i, color);
});
buildings.instanceMatrix.needsUpdate = true;
buildings.instanceColor.needsUpdate = true;
scene.add(buildings);
```

### 7. The ground and the districts

Add a large plane as the ground and colored squares marking out each district.

```javascript
const ground = new THREE.Mesh(
    new THREE.PlaneGeometry(2000, 2000),
    new THREE.MeshStandardMaterial({ color: 0x14141a, roughness: 1 })
);
ground.rotation.x = -Math.PI / 2;
ground.receiveShadow = true;
scene.add(ground);

Object.entries(districtPositions).forEach(([folder, d]) => {
    const districtPlane = new THREE.Mesh(
        new THREE.PlaneGeometry(d.size, d.size),
        new THREE.MeshStandardMaterial({ color: districtColor(folder), transparent: true, opacity: 0.15 })
    );
    districtPlane.rotation.x = -Math.PI / 2;
    districtPlane.position.set(d.x + d.size / 2, 0.01, d.z + d.size / 2);
    scene.add(districtPlane);
});
```

## Colors per file type

```javascript
const TYPE_COLORS = {
    code:    0x4a9eff,  // blue
    test:    0x6cc46c,  // green
    config:  0xffc857,  // yellow
    doc:     0xb39ddb,  // lilac
    style:   0xff9aa2,  // pink
    asset:   0x999999   // gray
};

function colorForModule(m) {
    if (m.isHotPath) return 0xff5a4f;
    return TYPE_COLORS[m.type] || 0xcccccc;
}
```

## The controls sidebar (Code City)

```html
<aside id="sidebar">
    <h3>Code City</h3>

    <label>Height (LOC)
        <input type="range" min="0.1" max="2.0" step="0.1" value="0.4" data-param="locScale">
    </label>

    <label>Base (complexity)
        <input type="range" min="0.2" max="2.0" step="0.1" value="0.8" data-param="complexityScale">
    </label>

    <label>Hot path threshold
        <input type="range" min="0" max="100" step="5" value="50" data-param="hotPathThreshold">
    </label>

    <label>
        <input type="checkbox" data-param="showLabels" checked> Labels visible
    </label>

    <label>
        <input type="checkbox" data-param="showDistricts" checked> Show districts
    </label>

    <label>Filter by folder
        <select data-param="folderFilter">
            <option value="all">All</option>
            <!-- POPULATED_FROM_DATA -->
        </select>
    </label>

    <button id="reset">Reset</button>
    <button id="export-png">Export PNG</button>
</aside>
```

When a slider changes, recompute `m.height`, `m.w`, `m.d` and update the `InstancedMesh` with the new matrices.

## Interaction

- **Hovering a building**: a tooltip shows the file name, LOC, complexity and folder.
- **Clicking a building**: focuses the camera on it (animating `controls.target` to the building's position).
- **Dragging on a district**: rotates the camera with OrbitControls.
- **Scrolling**: zooms in/out.

## Performance

- Up to **5,000 buildings** is safe with an InstancedMesh.
- Above that, group the files by folder (one building = one folder, with the height aggregating LOC and the area from the file count).
- Disable shadows if the frame rate drops below 30fps (detect it with a `requestAnimationFrame` timer).

## Optional variants

- **A temporal Code City**: animate the growth over the project's history (each commit makes the buildings grow).
- **A Code City colored by author**: the colors indicate who the main maintainer of each file is.
- **A Code City with rain**: hot paths get a falling red particle effect, indicating "instability".

These variants are left for future versions of the skill.
