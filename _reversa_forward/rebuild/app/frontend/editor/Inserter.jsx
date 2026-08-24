import { useState } from "react";
import { INSERTER_GROUPS, blockType } from "./blockTypes.js";

// The block inserter (the oracle's "+" palette). Grouped as the oracle groups them; a
// search box filters by title. Choosing a block calls onInsert(name).
export default function Inserter({ onInsert, onClose }) {
  const [q, setQ] = useState("");
  const query = q.trim().toLowerCase();

  return (
    <div className="be-inserter" role="dialog" aria-label="Add block">
      <div className="be-inserter-head">
        <input
          autoFocus
          type="search"
          className="be-inserter-search"
          placeholder="Search"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          aria-label="Search for a block"
        />
        <button type="button" className="be-inserter-close" aria-label="Close" onClick={onClose}>✕</button>
      </div>
      <div className="be-inserter-groups">
        {INSERTER_GROUPS.map((group) => {
          const items = group.names.filter((n) => !query || blockType(n).title.toLowerCase().includes(query));
          if (items.length === 0) return null;
          return (
            <div key={group.label} className="be-inserter-group">
              <div className="be-inserter-group-label">{group.label}</div>
              <div className="be-inserter-grid">
                {items.map((name) => {
                  const t = blockType(name);
                  return (
                    <button key={name} type="button" className="be-inserter-item" onClick={() => onInsert(name)}>
                      <span className="be-inserter-icon" aria-hidden="true">{t.icon}</span>
                      <span className="be-inserter-title">{t.title}</span>
                    </button>
                  );
                })}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
