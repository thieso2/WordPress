#!/usr/bin/env python3
"""
Analyzes data and suggests the best Highcharts chart type.

It computes descriptive statistics and infers the nature of the data
in order to recommend suitable chart types.

Uso:
    python analyze_data.py <file> [--format json|text]
    python analyze_data.py dados.csv --suggest-chart

Output:
    Statistics + suggested chart types.
"""

import sys
import json
import argparse
import re
from pathlib import Path


def is_temporal(values: list) -> bool:
    """Detect whether a list of values looks temporal."""
    date_patterns = [
        r'\d{4}[-/]\d{1,2}[-/]\d{1,2}',  # 2024-01-15
        r'\d{1,2}[-/]\d{1,2}[-/]\d{4}',  # 15/01/2024
        r'(Jan|Fev|Mar|Abr|Mai|Jun|Jul|Ago|Set|Out|Nov|Dez)',
        r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)',
        r'Q[1-4]\s*\d{4}',  # Q1 2024
        r'\d{4}',  # Apenas anos
    ]
    if not values:
        return False
    matches = 0
    sample = values[:20]
    for v in sample:
        for pattern in date_patterns:
            if re.search(pattern, str(v), re.IGNORECASE):
                matches += 1
                break
    return matches / len(sample) > 0.6


def analyze_series(values: list) -> dict:
    """Analyze a series of numeric values."""
    nums = [v for v in values if isinstance(v, (int, float)) and v is not None]
    if not nums:
        return {"type": "non_numeric", "count": len(values)}

    nums.sort()
    n = len(nums)
    total = sum(nums)
    mean = total / n
    variance = sum((x - mean) ** 2 for x in nums) / n

    return {
        "type": "numeric",
        "count": n,
        "min": min(nums),
        "max": max(nums),
        "mean": round(mean, 2),
        "median": nums[n // 2],
        "std": round(variance ** 0.5, 2),
        "sum": round(total, 2),
        "has_negatives": any(x < 0 for x in nums),
        "all_integers": all(x == int(x) for x in nums),
        "all_positive": all(x >= 0 for x in nums),
        "range": max(nums) - min(nums),
        "unique_values": len(set(nums))
    }


def suggest_charts(categories: list, series_analysis: list, n_series: int) -> list:
    """Suggest chart types based on the analysis."""
    suggestions = []
    temporal = is_temporal(categories)
    n_categories = len(categories)
    all_positive = all(s.get("all_positive", True) for s in series_analysis)

    # Dados temporais → line/area
    if temporal:
        suggestions.append({
            "type": "line", "score": 95,
            "reason": "Temporal data — ideal for showing a trend over time"
        })
        suggestions.append({
            "type": "area", "score": 85,
            "reason": "Temporal data — the area emphasizes volume/magnitude"
        })
        if n_series > 1 and all_positive:
            suggestions.append({
                "type": "stacked_area", "score": 80,
                "reason": "Multiple time series — shows the composition over time"
            })

    # Few categorical points → column/bar
    if n_categories <= 20:
        suggestions.append({
            "type": "column", "score": 90 if not temporal else 70,
            "reason": f"{n_categories} categories — good for a direct comparison"
        })
        if n_categories > 8:
            suggestions.append({
                "type": "bar", "score": 85,
                "reason": "Many categories — horizontal bars make the labels easier to read"
            })

    # One series with few items → pie
    if n_series == 1 and n_categories <= 8 and all_positive:
        suggestions.append({
            "type": "pie", "score": 80,
            "reason": "One series with few categories — shows the proportion/composition"
        })

    # Two numeric series → scatter
    if n_series >= 2 and all(s.get("type") == "numeric" for s in series_analysis):
        suggestions.append({
            "type": "scatter", "score": 70,
            "reason": "Multiple numeric series — shows the correlation between variables"
        })

    # Muitos dados → considerar heatmap
    if n_categories > 20 and n_series > 5:
        suggestions.append({
            "type": "heatmap", "score": 75,
            "reason": "Many categories × series — a heatmap reveals matrix patterns"
        })

    # A single KPI → gauge
    if n_series == 1 and n_categories == 1:
        suggestions.append({
            "type": "solidgauge", "score": 85,
            "reason": "A single value — ideal for a KPI/progress indicator"
        })

    # Stacked for composition
    if n_series > 1 and n_categories <= 15 and all_positive:
        suggestions.append({
            "type": "stacked_column", "score": 75,
            "reason": "Multiple positive series — shows the composition per category"
        })

    # Ordenar por score
    suggestions.sort(key=lambda x: x["score"], reverse=True)
    return suggestions[:5]


def main():
    parser = argparse.ArgumentParser(description="Analyzes data and suggests charts")
    parser.add_argument("filepath", help="Path to the file")
    parser.add_argument("--format", choices=["json", "text"], default="json")
    parser.add_argument("--suggest-chart", action="store_true", default=True)
    parser.add_argument("--encoding", default=None)
    parser.add_argument("--sheet", default=None)
    args = parser.parse_args()

    # Import parse_data from the same directory
    script_dir = Path(__file__).parent
    sys.path.insert(0, str(script_dir))
    from parse_data import parse_csv, parse_json_data, parse_excel, detect_encoding

    path = Path(args.filepath)
    ext = path.suffix.lower()

    if ext in ('.csv', '.tsv', '.txt'):
        enc = args.encoding or detect_encoding(str(path))
        parsed = parse_csv(str(path), encoding=enc)
    elif ext == '.json':
        parsed = parse_json_data(str(path))
    elif ext in ('.xlsx', '.xls'):
        parsed = parse_excel(str(path), sheet=args.sheet)
    else:
        print(f"[ERROR] Unsupported format: {ext}", file=sys.stderr)
        sys.exit(1)

    if "error" in parsed:
        print(f"[ERRO] {parsed['error']}", file=sys.stderr)
        sys.exit(1)

    # Analyze each series
    series_analysis = []
    for s in parsed.get("series", []):
        analysis = analyze_series(s["data"])
        analysis["name"] = s["name"]
        series_analysis.append(analysis)

    # Suggest charts
    categories = parsed.get("categories", [])
    suggestions = suggest_charts(categories, series_analysis, len(series_analysis))

    result = {
        "data_summary": {
            "categories_count": len(categories),
            "series_count": len(series_analysis),
            "is_temporal": is_temporal(categories),
            "sample_categories": categories[:5]
        },
        "series_analysis": series_analysis,
        "chart_suggestions": suggestions
    }

    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"=== Data Summary ===")
        print(f"Categories: {len(categories)} ({'temporal' if is_temporal(categories) else 'categorical'})")
        print(f"Series: {len(series_analysis)}")
        for s in series_analysis:
            print(f"  • {s['name']}: min={s.get('min')}, max={s.get('max')}, "
                  f"mean={s.get('mean')}, {s.get('count')} points")
        print(f"\n=== Suggested charts ===")
        for i, sug in enumerate(suggestions, 1):
            print(f"  {i}. {sug['type']} (score: {sug['score']})")
            print(f"     {sug['reason']}")


if __name__ == "__main__":
    main()
