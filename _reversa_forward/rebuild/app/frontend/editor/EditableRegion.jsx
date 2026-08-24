import { useRef, useEffect } from "react";

// An uncontrolled contenteditable region. React must NOT re-render its innerHTML on every
// keystroke (that resets the caret), so we set innerHTML imperatively when the block
// identity changes and read edits back on input/blur. This mirrors how the block editor
// keeps a live editable surface without React owning each character.
export default function EditableRegion({ html, tag = "p", pre = false, readOnly, onChange, onFocus, placeholder, ariaLabel }) {
  const ref = useRef(null);
  const last = useRef(html);

  useEffect(() => {
    if (ref.current && ref.current.innerHTML !== html) {
      ref.current.innerHTML = html;
      last.current = html;
    }
    // Intentionally keyed on `html` identity from the store, not on every render.
  }, [html]);

  const commit = () => {
    if (!ref.current) return;
    const next = ref.current.innerHTML;
    if (next !== last.current) {
      last.current = next;
      onChange(next);
    }
  };

  const Tag = tag;
  return (
    <Tag
      ref={ref}
      className={`be-editable${pre ? " be-pre" : ""}`}
      contentEditable={!readOnly}
      suppressContentEditableWarning
      spellCheck={false}
      data-placeholder={placeholder || ""}
      aria-label={ariaLabel || undefined}
      onInput={commit}
      onBlur={commit}
      onFocus={onFocus}
    />
  );
}
