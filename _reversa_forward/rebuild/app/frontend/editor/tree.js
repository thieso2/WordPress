// Block-tree model + immutable operations. The tree the server hands over
// ({name, attrs, innerHTML, innerContent, innerBlocks}) is decorated with a stable
// clientId per node (React key + selection handle). Serialization (see serialize.js) is
// byte-exact for untouched content without any dirty tracking, because the parser
// guarantees a leaf block's innerHTML is exactly the concatenation of its innerContent
// string chunks — so a leaf always round-trips through innerHTML, and only containers
// carry the null-slot interleaving that must be preserved.

let counter = 0;
const newId = () => `blk-${(counter++).toString(36)}-${Math.floor(performance.now() * 1000).toString(36)}`;

export function decorate(node) {
  return {
    clientId: newId(),
    name: node.name ?? null,
    attrs: node.attrs || {},
    innerHTML: node.innerHTML ?? "",
    innerContent: node.innerContent === undefined ? null : node.innerContent,
    innerBlocks: (node.innerBlocks || []).map(decorate)
  };
}

export const decorateList = (nodes) => (nodes || []).map(decorate);

// A freshly inserted block.
export function makeBlock(name, attrs = {}, innerHTML = "") {
  return { clientId: newId(), name, attrs, innerHTML, innerContent: innerHTML ? [innerHTML] : [], innerBlocks: [] };
}

export function mapTree(nodes, fn) {
  return nodes.map((n) => {
    const m = fn(n);
    return m.innerBlocks && m.innerBlocks.length ? { ...m, innerBlocks: mapTree(m.innerBlocks, fn) } : m;
  });
}

export function updateNode(nodes, clientId, patch) {
  return mapTree(nodes, (n) => (n.clientId === clientId ? { ...n, ...patch } : n));
}

export function removeNode(nodes, clientId) {
  const out = [];
  for (const n of nodes) {
    if (n.clientId === clientId) continue;
    out.push(n.innerBlocks.length ? { ...n, innerBlocks: removeNode(n.innerBlocks, clientId) } : n);
  }
  return out;
}

// Insert `block` immediately after `afterId` at whatever depth it lives; afterId === null
// appends at top level.
export function insertAfter(nodes, afterId, block) {
  if (afterId === null) return [...nodes, block];
  const out = [];
  for (const n of nodes) {
    const child = n.innerBlocks.length ? { ...n, innerBlocks: insertAfter(n.innerBlocks, afterId, block) } : n;
    out.push(child);
    if (n.clientId === afterId) out.push(block);
  }
  return out;
}

// Append `block` as the last child of the container `parentId`.
export function appendChild(nodes, parentId, block) {
  return mapTree(nodes, (n) =>
    n.clientId === parentId ? { ...n, innerBlocks: [...n.innerBlocks, block] } : n
  );
}

export function moveNode(nodes, clientId, delta) {
  const idx = nodes.findIndex((n) => n.clientId === clientId);
  if (idx !== -1) {
    const j = idx + delta;
    if (j < 0 || j >= nodes.length) return nodes;
    const copy = nodes.slice();
    const [item] = copy.splice(idx, 1);
    copy.splice(j, 0, item);
    return copy;
  }
  return nodes.map((n) =>
    n.innerBlocks.length ? { ...n, innerBlocks: moveNode(n.innerBlocks, clientId, delta) } : n
  );
}

export function duplicateNode(nodes, clientId) {
  const clone = (node) => ({ ...node, clientId: newId(), innerBlocks: node.innerBlocks.map(clone) });
  const out = [];
  for (const n of nodes) {
    out.push(n.innerBlocks.length ? { ...n, innerBlocks: duplicateNode(n.innerBlocks, clientId) } : n);
    if (n.clientId === clientId) out.push(clone(n));
  }
  return out;
}

export function findNode(nodes, clientId) {
  for (const n of nodes) {
    if (n.clientId === clientId) return n;
    const f = n.innerBlocks.length ? findNode(n.innerBlocks, clientId) : null;
    if (f) return f;
  }
  return null;
}
