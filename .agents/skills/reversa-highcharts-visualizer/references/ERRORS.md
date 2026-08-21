# Error handling — Highcharts Visualizer

## Insufficient or empty data

**Symptom:** The chart renders empty or with the message "No data to display".

**Action:** Configure the `noData` module or check the data before creating the chart:
```javascript
// Include: modules/no-data-to-display.js
lang: { noData: 'No data available to display' },
noData: { style: { fontWeight: 'bold', fontSize: '16px', color: '#666' } }
```

Warn the user:
> "The data you provided looks empty or was not processed correctly. Could you check it?"

## Incompatible data format

**Symptom:** A console error, or a chart with NaN/undefined values.

**Action:** Validate the data with `scripts/parse_data.py` before embedding it. The script automatically converts
numeric strings ("1.234,56" → 1234.56) and dates in several formats.

## CDN module does not load

**Symptom:** The error "Highcharts is not defined", or an unrecognized chart type.

**Action:** Check the script order. The `highcharts.js` core must come first, then the modules.
For Stock/Maps/Gantt, use the respective main script (highstock.js, highmaps.js, highcharts-gantt.js)
**instead of** highcharts.js, not alongside it.

Correct order:
```html
<script src="https://code.highcharts.com/highcharts.js"></script>
<script src="https://code.highcharts.com/highcharts-more.js"></script>
<script src="https://code.highcharts.com/modules/solid-gauge.js"></script>
<script src="https://code.highcharts.com/modules/exporting.js"></script>
<script src="https://code.highcharts.com/modules/accessibility.js"></script>
```

## Chart is not responsive

**Symptom:** The chart does not resize with the window, or gets cut off.

**Action:** Do not set a fixed `chart.width`. Use a container with responsive CSS.
Make sure `chart.reflow` is not disabled.

```javascript
chart: {
    // Do NOT set a fixed width/height
    // Let Highcharts adapt to the container
    reflow: true
}
```

## Slow performance with a lot of data

**Symptom:** The chart freezes or takes a long time to render with >10,000 points.

**Action:**
1. Include `modules/boost.js`
2. Set `boostThreshold: 5000` on the series
3. Disable animations: `plotOptions: { series: { animation: false } }`
4. Disable markers: `marker: { enabled: false }`
5. Consider aggregating the data (downsampling) via `scripts/analyze_data.py`

## Tooltips with wrong values

**Symptom:** The tooltip shows "undefined" or the wrong format.

**Action:** Check that the data is in the right format for the chart type.
Use a custom `tooltip.formatter` for full control over the format.

## Unreadable colors

**Symptom:** Series or labels with insufficient contrast.

**Action:** Use `Highcharts.getOptions().colors` to check the active palette.
For dark mode, make sure labels/grid/ticks use light colors.
The accessibility module warns about contrast problems.

## CSV with a different encoding (UTF-8 BOM, Latin1)

**Symptom:** Special characters (accents) appear as "�" or "Ã©".

**Action:** `scripts/parse_data.py` tries to detect the encoding automatically.
If that fails, force the encoding:
```bash
python scripts/parse_data.py data.csv --encoding latin1
```

## Excel file with multiple sheets

**Symptom:** The extracted data comes from the wrong sheet.

**Action:**
```bash
python scripts/parse_data.py data.xlsx --sheet "Sheet2"
```
