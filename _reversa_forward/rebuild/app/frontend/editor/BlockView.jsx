import EditableRegion from "./EditableRegion.jsx";
import { blockType, textTag } from "./blockTypes.js";

// Renders one block by its kind and, when selected, its toolbar. Text blocks are live
// contenteditable; containers recurse; dynamic/void blocks show an honest labelled preview
// (never a fake front-end render — the real render is the server's Composition renderers).
export default function BlockView({ node, depth, selectedId, onSelect, onText, onAttrs, actions, readOnly, renderChildren }) {
  const type = blockType(node.name);
  const selected = node.clientId === selectedId;
  const select = (e) => { e.stopPropagation(); onSelect(node.clientId); };

  const shell = (inner) => (
    <div
      className={`be-block${selected ? " is-selected" : ""} kind-${type.kind}`}
      data-block={node.name || "freeform"}
      onMouseDown={select}
    >
      {selected && !readOnly && <BlockToolbar node={node} type={type} actions={actions} />}
      {inner}
    </div>
  );

  if (type.kind === "text") {
    return shell(
      <EditableRegion
        html={node.innerHTML}
        tag={textTag(node)}
        pre={!!type.pre}
        readOnly={readOnly}
        placeholder={node.name === "core/paragraph" ? "Type / to choose a block" : type.title}
        ariaLabel={`Block: ${type.title}`}
        onFocus={() => onSelect(node.clientId)}
        onChange={(html) => onText(node.clientId, html)}
      />
    );
  }

  if (type.kind === "container") {
    const Wrapper = type.wrapperTag || "div";
    return shell(
      <Wrapper className="be-container">
        <div className="be-container-label">{type.title}</div>
        {renderChildren(node)}
      </Wrapper>
    );
  }

  if (type.kind === "void") {
    return shell(<div className="be-void" aria-label={type.title}><span className="be-void-rule" /></div>);
  }

  // dynamic / freeform: labelled preview + the attrs that identify it.
  return shell(
    <div className="be-dynamic">
      <span className="be-dynamic-icon" aria-hidden="true">{type.icon}</span>
      <div className="be-dynamic-body">
        <div className="be-dynamic-title">{type.title}</div>
        <DynamicSummary node={node} type={type} />
      </div>
    </div>
  );
}

function DynamicSummary({ node, type }) {
  const keys = type.previewAttrs || [];
  const shown = keys.map((k) => node.attrs?.[k]).filter((v) => v != null && v !== "");
  if (node.name === "core/freeform" || node.name == null) {
    return <div className="be-dynamic-meta">Classic content — rendered as saved.</div>;
  }
  return (
    <div className="be-dynamic-meta">
      Server-rendered on the front end.
      {shown.length > 0 && <span className="be-dynamic-attrs"> · {shown.join(" · ")}</span>}
    </div>
  );
}

function BlockToolbar({ node, type, actions }) {
  return (
    <div className="be-toolbar" role="toolbar" aria-label={`${type.title} controls`}>
      <span className="be-toolbar-name">{type.icon} {type.title}</span>
      <button type="button" title="Move up" aria-label="Move up" onClick={() => actions.move(node.clientId, -1)}>▲</button>
      <button type="button" title="Move down" aria-label="Move down" onClick={() => actions.move(node.clientId, 1)}>▼</button>
      <button type="button" title="Duplicate" aria-label="Duplicate" onClick={() => actions.duplicate(node.clientId)}>⧉</button>
      <button type="button" title="Insert after" aria-label="Insert after" onClick={() => actions.openInserter(node.clientId)}>＋</button>
      <button type="button" className="be-danger" title="Remove block" aria-label="Remove block" onClick={() => actions.remove(node.clientId)}>✕</button>
    </div>
  );
}
