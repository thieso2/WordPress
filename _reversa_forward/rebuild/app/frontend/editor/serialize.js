// Build the save payload: decorated tree -> the {name, attrs, innerHTML, innerContent,
// innerBlocks} shape the server's Composition::Serializer consumes. Byte-exact for
// untouched content:
//
//   * leaf block (no innerBlocks): the parser guarantees innerHTML === join(innerContent
//     string chunks), so we hand back innerHTML and let the server wrap it. Unedited or
//     edited, the bytes are whatever the block currently holds.
//
//   * container: the null slots in innerContent mark where children serialize. If the
//     child count still matches the original null count, we pass innerContent VERBATIM
//     (preserving the exact wrapper markup and inter-child whitespace) — so a container
//     whose children were only edited or reordered round-trips its wrapper unchanged.
//     If a child was added or removed, we rebuild innerContent as [lead, null…, trail]
//     from the original wrapper edges — the one place edited containers may differ from
//     the legacy by inter-child whitespace, which DEV-012's behavioural contract allows.
export function toPayload(nodes) {
  return nodes.map(serializeNode);
}

function serializeNode(node) {
  const base = { name: node.name, attrs: node.attrs || {} };

  if (!node.innerBlocks || node.innerBlocks.length === 0) {
    // Leaf (or void/dynamic): content is innerHTML. Empty innerHTML → server emits the
    // void form `<!-- wp:name /-->`.
    return { ...base, innerHTML: node.innerHTML || "", innerContent: node.innerHTML ? [node.innerHTML] : [], innerBlocks: [] };
  }

  const children = node.innerBlocks.map(serializeNode);
  const original = node.innerContent;
  const nullCount = Array.isArray(original) ? original.filter((c) => c === null).length : -1;

  let innerContent;
  if (Array.isArray(original) && nullCount === children.length) {
    innerContent = original; // verbatim: exact wrapper + whitespace preserved
  } else {
    const [lead, trail] = wrapperEdges(original);
    innerContent = [lead, ...children.flatMap(() => [null]), trail];
  }

  return { ...base, innerHTML: node.innerHTML || "", innerContent, innerBlocks: children };
}

// The wrapper markup around a container's child slots: everything before the first null,
// and everything after the last null (string chunks joined).
function wrapperEdges(innerContent) {
  if (!Array.isArray(innerContent)) return ["", ""];
  const first = innerContent.indexOf(null);
  const last = innerContent.lastIndexOf(null);
  if (first === -1) return [innerContent.join(""), ""];
  const lead = innerContent.slice(0, first).join("");
  const trail = innerContent.slice(last + 1).join("");
  return [lead, trail];
}
