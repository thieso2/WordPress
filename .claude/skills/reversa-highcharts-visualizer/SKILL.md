---
name: reversa-highcharts-visualizer
description: Creates interactive data visualizations with Highcharts.js, generating standalone HTML with animated, responsive and accessible charts from inline data, CSV or JSON.
disable-model-invocation: true
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  team: shared-skills
  role: charts-renderer
---

# Highcharts Visualizer

Creates professional data visualizations using Highcharts.js. It always generates **standalone HTML**
(a single, self-contained file) with interactive, animated, responsive and accessible charts.

## Workflow

### 1. Receiving the data

The data may come from:

- **Inline in the conversation** → the user pastes data, a table, or a list of values
- **An uploaded CSV/JSON** → analyze the content with `view_file` and inject the data directly into the generated HTML. Never create Python scripts.
- **An Excel spreadsheet** → extract the data from the tables and inject it into the HTML. Do not use Python.
- **Sample data** → when the user wants to explore a chart type without real data
- **A data URL** → use `web_fetch` to retrieve remote data

### 2. Analyzing the data

Before generating the chart, understand the nature of the data:

- **Dimensions**: how many series? How many categories? Temporal or categorical?
- **Scale**: the range of the values, outliers, the distribution
- **Relationships**: comparison, composition, distribution, trend, correlation
- **Volume**: few points (<100), medium (100-10K), large (>10K — use the boost module)

Analyze the data internally after reading it and inject the tags via strings. Do not create intermediate Python programs.

### 3. Choosing the chart type

Consult `references/CHART_CATALOG.md` for the complete catalog of 40+ chart types,
with guidance on when to use each one.

**A quick decision rule:**
| Goal | Recommended types |
| Objetivo | Tipos recomendados |
|----------|-------------------|
| A trend over time | line, area, spline, areaspline |
| A comparison between categories | column, bar, lollipop, bullet |
| Composition / proportion | pie, donut, stacked column, stacked area, treemap, sunburst |
| Distribution | histogram, box plot, scatter, bell curve |
| Correlation | scatter, bubble, heatmap |
| Flow / process | sankey, dependency wheel, network graph |
| Hierarchy | treemap, sunburst, organization chart |
| Geographic | map (the Highcharts Maps module) |
| Financial / timeline | stock chart (candlestick, OHLC, flags) |
| Progress / KPI | gauge, solid gauge, activity gauge |
| Project / planning | gantt chart |
| Funnel / conversion | funnel, pyramid |

If the user did not specify a type, suggest 2-3 options that best represent the data.

### 4. Generating the code

Consult `references/HIGHCHARTS_PATTERNS.md` for tested code patterns.

**Fundamental rules:**

1. **Standalone HTML**: a single `.html` file. When run by the Reversa Docs Team, Highcharts comes from `assets/vendor/` (downloaded by the Publisher via `vendor-pins.yaml`). When run standalone, a CDN is accepted as a fallback, but the local path is preferred.
2. **A pinned version**: `highcharts@11.4.8`. The core and the modules must be from the same version.
3. **Modules on demand**: only include extra scripts when they are needed (see the module table).
4. **Accessibility always**: always include `assets/vendor/highcharts-accessibility.js`.
5. **Exporting always**: always include `assets/vendor/highcharts-exporting.js`.
6. **Responsive**: the chart must adapt to the container/viewport.
7. **A consistent theme**: apply cohesive colors and professional typography.
8. **Animation**: enable entrance animations and smooth transitions.
9. **Rich tooltips**: formatted tooltips, with units and context.
10. **Large data**: for >10K points, include `modules/boost.js` (it needs to be added to `vendor-pins.yaml`).
11. **No `fetch()` for local files**: the data comes from `window.RV_DATA.metrics` (or `window.RV_DATA.timeline`), loaded by `assets/js/data.js`.

**The modules needed per chart type (preference: the local path in `assets/vendor/`):**

| Feature | Local (when run by the Docs team) | CDN fallback |
|---------|--------------------------------------|--------------|
| Core (mandatory) | `assets/vendor/highcharts.js` | `https://code.highcharts.com/11.4.8/highcharts.js` |
| Accessibility (mandatory) | `assets/vendor/highcharts-accessibility.js` | `.../11.4.8/modules/accessibility.js` |
| Exporting (mandatory) | `assets/vendor/highcharts-exporting.js` | `.../11.4.8/modules/exporting.js` |
| Treemap | `assets/vendor/highcharts-treemap.js` | `.../11.4.8/modules/treemap.js` |
| Sankey | `assets/vendor/highcharts-sankey.js` | `.../11.4.8/modules/sankey.js` |
| Timeline | `assets/vendor/highcharts-timeline.js` | `.../11.4.8/modules/timeline.js` |
| Others (Sunburst, Heatmap, Funnel, etc.) | add it to `vendor-pins.yaml` before using it | `.../11.4.8/modules/<module>.js` |
| Stock (candlestick, OHLC) | add it to `vendor-pins.yaml` before using it | `.../stock/11.4.8/highstock.js` |
| Maps | add it to `vendor-pins.yaml` before using it | `.../maps/11.4.8/highmaps.js` |
| Gantt | add it to `vendor-pins.yaml` before using it | `.../gantt/11.4.8/highcharts-gantt.js` |

> If a page needs a module that is **not yet** in `vendor-pins.yaml`, the correct path is:
> 1. Ask the Publisher to add the pin (a commit in that skill, or opening an issue), with a primary URL + fallbacks.
> 2. Only then use the module.
> Pointing directly at a CDN in the final pages breaks the "works via `file://` with no internet" invariant.

Every CDN (fallback) in the format: `https://code.highcharts.com/11.4.8/{path}`.

### 5. Saving and delivering

Save the generated HTML straight into the destination folder using `write_to_file`. Always produce a pure HTML file with all the data processed and injected into the `<script>` variables. Do not use Python snippets.

## Quality guidelines

- **Professional aesthetics**: cohesive colors (use the Highcharts palettes or a custom one), clean typography, appropriate spacing
- **Formatted data**: numbers with thousands separators, localized dates, units on the axes
- **Clear legends**: descriptive series names, in a position that does not obstruct the data
- **Rich interactivity**: hover highlights, contextual tooltips, zoom where applicable
- **Dark mode**: where appropriate, offer a dark version with `backgroundColor: '#1a1a2e'`
- **Multiple charts**: for dashboards, arrange them in a responsive CSS grid
- **Commented code**: comments in the installation's language explaining each section

## Error handling

Consult `references/ERRORS.md` for the error scenarios and their solutions.
