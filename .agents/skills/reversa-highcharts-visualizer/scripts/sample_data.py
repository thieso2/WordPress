#!/usr/bin/env python3
"""
Generates ready-made sample data for different Highcharts chart types.

Useful when the user wants to explore a chart type without having real data.

Uso:
    python sample_data.py --type line
    python sample_data.py --type pie --items 6
    python sample_data.py --type stock --days 365
    python sample_data.py --type sankey
    python sample_data.py --list  (lists every type)

Output:
    JSON with ready-to-use Highcharts options.
"""

import sys
import json
import random
import argparse
from datetime import datetime, timedelta


def sample_line(months: int = 12, series_count: int = 2) -> dict:
    """Sample data for a line/spline/area chart."""
    months_list = ['Jan','Fev','Mar','Abr','Mai','Jun',
                   'Jul','Ago','Set','Out','Nov','Dez'][:months]
    series = []
    for i in range(series_count):
        base = random.randint(50, 200)
        data = [round(base + random.gauss(0, 20) + j * random.uniform(-2, 5), 1)
                for j in range(months)]
        series.append({"name": f"Series {chr(65+i)}", "data": data})
    return {"categories": months_list, "series": series, "suggested_type": "line"}


def sample_column(categories: int = 6, series_count: int = 2) -> dict:
    """Sample data for a column/bar chart."""
    cats = [f"Categoria {chr(65+i)}" for i in range(categories)]
    series = []
    for i in range(series_count):
        data = [random.randint(20, 150) for _ in range(categories)]
        series.append({"name": f"Grupo {i+1}", "data": data})
    return {"categories": cats, "series": series, "suggested_type": "column"}


def sample_pie(items: int = 6) -> dict:
    """Sample data for a pie/donut chart."""
    names = ['Technology', 'Healthcare', 'Finance', 'Education',
             'Retail', 'Manufacturing', 'Energy', 'Transport'][:items]
    values = [random.randint(5, 35) for _ in range(items)]
    total = sum(values)
    data = [{"name": n, "y": round(v / total * 100, 1)} for n, v in zip(names, values)]
    # Destacar o maior
    max_idx = max(range(len(data)), key=lambda i: data[i]["y"])
    data[max_idx]["sliced"] = True
    data[max_idx]["selected"] = True
    return {"series": [{"name": "Share", "colorByPoint": True, "data": data}],
            "suggested_type": "pie"}


def sample_scatter(points: int = 50) -> dict:
    """Sample data for a scatter chart."""
    data_a = [[round(random.gauss(5, 2), 1), round(random.gauss(5, 2), 1)]
              for _ in range(points)]
    data_b = [[round(random.gauss(8, 1.5), 1), round(random.gauss(3, 1.5), 1)]
              for _ in range(points)]
    return {"series": [
        {"name": "Grupo A", "data": data_a},
        {"name": "Grupo B", "data": data_b}
    ], "suggested_type": "scatter"}


def sample_heatmap(rows: int = 7, cols: int = 12) -> dict:
    """Sample data for a heatmap."""
    row_cats = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][:rows]
    col_cats = ['Jan','Fev','Mar','Abr','Mai','Jun',
                'Jul','Ago','Set','Out','Nov','Dez'][:cols]
    data = [[x, y, random.randint(0, 100)] for x in range(cols) for y in range(rows)]
    return {
        "xCategories": col_cats, "yCategories": row_cats,
        "series": [{"data": data}], "suggested_type": "heatmap"
    }


def sample_sankey() -> dict:
    """Sample data for a Sankey diagram."""
    data = [
        ['Marketing', 'Leads', 1000],
        ['Direct Sales', 'Leads', 500],
        ['Referral', 'Leads', 300],
        ['Leads', 'Qualified', 900],
        ['Leads', 'Disqualified', 900],
        ['Qualified', 'Proposal', 600],
        ['Qualified', 'Lost', 300],
        ['Proposal', 'Won', 400],
        ['Proposal', 'Lost', 200],
    ]
    return {
        "series": [{"keys": ["from", "to", "weight"], "data": data}],
        "suggested_type": "sankey"
    }


def sample_gauge(value: float = None) -> dict:
    """Sample data for a gauge/solid gauge."""
    val = value or round(random.uniform(30, 95), 1)
    return {
        "series": [{"name": "Performance", "data": [val]}],
        "suggested_type": "solidgauge",
        "min": 0, "max": 100
    }


def sample_treemap() -> dict:
    """Sample data for a treemap."""
    data = [
        {"name": "Brazil", "value": 211, "colorValue": 1},
        {"name": "Mexico", "value": 128, "colorValue": 2},
        {"name": "Colombia", "value": 50, "colorValue": 3},
        {"name": "Argentina", "value": 45, "colorValue": 4},
        {"name": "Peru", "value": 32, "colorValue": 5},
        {"name": "Venezuela", "value": 28, "colorValue": 6},
        {"name": "Chile", "value": 19, "colorValue": 7},
        {"name": "Ecuador", "value": 17, "colorValue": 8},
    ]
    return {"series": [{"data": data}], "suggested_type": "treemap"}


def sample_stock(days: int = 365) -> dict:
    """Sample data for a stock chart (OHLC)."""
    start = datetime(2024, 1, 1)
    price = 150.0
    data = []
    for i in range(days):
        date = start + timedelta(days=i)
        if date.weekday() >= 5:
            continue
        o = round(price + random.gauss(0, 2), 2)
        h = round(o + abs(random.gauss(0, 3)), 2)
        l = round(o - abs(random.gauss(0, 3)), 2)
        c = round(random.uniform(l, h), 2)
        price = c
        ts = int(date.timestamp() * 1000)
        data.append([ts, o, h, l, c])
    return {"series": [{"type": "candlestick", "name": "ACME", "data": data}],
            "suggested_type": "stock"}


def sample_funnel() -> dict:
    """Sample data for a funnel chart."""
    data = [
        ['Site Visitors', 15654],
        ['Downloads', 4064],
        ['Signups', 1987],
        ['Active Trial', 976],
        ['Purchase', 846]
    ]
    return {"series": [{"data": data}], "suggested_type": "funnel"}


GENERATORS = {
    "line": sample_line, "spline": sample_line, "area": sample_line,
    "column": sample_column, "bar": sample_column,
    "pie": sample_pie, "donut": sample_pie,
    "scatter": sample_scatter, "bubble": sample_scatter,
    "heatmap": sample_heatmap,
    "sankey": sample_sankey,
    "gauge": sample_gauge, "solidgauge": sample_gauge,
    "treemap": sample_treemap,
    "stock": sample_stock, "candlestick": sample_stock,
    "funnel": sample_funnel, "pyramid": sample_funnel,
}


def main():
    parser = argparse.ArgumentParser(description="Generates sample data for Highcharts")
    parser.add_argument("--type", "-t", choices=list(GENERATORS.keys()),
                        help="The chart type")
    parser.add_argument("--list", "-l", action="store_true", help="Lists the available types")
    parser.add_argument("--output", "-o", help="Save to a file")
    args = parser.parse_args()

    if args.list:
        print("Available types:")
        for t in sorted(set(GENERATORS.keys())):
            print(f"  • {t}")
        return

    if not args.type:
        parser.print_help()
        sys.exit(1)

    generator = GENERATORS[args.type]
    result = generator()

    output = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(output)
        print(f"[INFO] Salvo em: {args.output}", file=sys.stderr)
    else:
        print(output)


if __name__ == "__main__":
    main()
