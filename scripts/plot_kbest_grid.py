#!/usr/bin/env python3
from __future__ import annotations

import html
import math
import re
from pathlib import Path


RESULTS_DIR = Path(__file__).resolve().parent.parent / "results"
OUTPUT_FILE = RESULTS_DIR / "kbest-grid.svg"


def parse_version(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def parse_result_file(path: Path) -> tuple[str, dict[str, float]]:
    lines = path.read_text().splitlines()
    version = ""
    metrics: dict[str, float] = {}

    for line in lines:
        if line.startswith("Test Name:"):
            parts = [part.strip() for part in line.split(",")]
            if len(parts) >= 2:
                version = parts[1]
            continue

        parts = [part.strip() for part in line.split(",")]
        if len(parts) < 2:
            continue

        label, value = parts[0], parts[1]
        if "kbest:" not in label:
            continue

        metric = label.replace("kbest:", "").replace("Child", "Child").strip()
        metric = " ".join(metric.split())
        metrics[metric] = float(value)

    if not version:
        match = re.match(r"output\.(.+)\.csv$", path.name)
        if not match:
            raise ValueError(f"could not infer version from {path}")
        version = match.group(1)

    if not metrics:
        raise ValueError(f"no kbest metrics found in {path}")

    return version, metrics


def color_for_percent(percent: float, limit: float) -> str:
    if math.isnan(percent):
        return "#d1d5db"

    clamped = max(-limit, min(limit, percent))
    magnitude = abs(clamped) / limit if limit else 0.0

    if clamped < 0:
        base = (236, 253, 245)
        strong = (22, 163, 74)
    elif clamped > 0:
        base = (254, 242, 242)
        strong = (220, 38, 38)
    else:
        return "#f8fafc"

    rgb = tuple(
        round(base[i] + (strong[i] - base[i]) * magnitude)
        for i in range(3)
    )
    return "#{:02x}{:02x}{:02x}".format(*rgb)


def text_color_for_percent(percent: float, limit: float) -> str:
    if math.isnan(percent):
        return "#111827"
    return "#ffffff" if abs(percent) >= limit * 0.55 else "#111827"


def percent_label(percent: float) -> str:
    if math.isnan(percent):
        return "n/a"
    return f"{percent:+.1f}%"


def main() -> None:
    result_files = sorted(RESULTS_DIR.glob("output.*.csv"))
    if not result_files:
        raise SystemExit(f"no result files found in {RESULTS_DIR}")

    parsed = [parse_result_file(path) for path in result_files]
    parsed.sort(key=lambda item: parse_version(item[0]))

    versions = [version for version, _ in parsed]
    baseline_version, baseline_metrics = parsed[0]

    metric_order = list(baseline_metrics.keys())
    metric_set = set(metric_order)

    for version, metrics in parsed[1:]:
        metric_set.update(metrics.keys())
        for metric in metrics:
            if metric not in metric_order:
                metric_order.append(metric)

    rows: list[list[float]] = []
    all_percents: list[float] = []
    for metric in metric_order:
        row: list[float] = []
        baseline = baseline_metrics.get(metric)
        for _, metrics in parsed:
            value = metrics.get(metric)
            if baseline is None or value is None or baseline == 0:
                percent = math.nan
            else:
                percent = ((value - baseline) / baseline) * 100.0
                all_percents.append(percent)
            row.append(percent)
        rows.append(row)

    limit = max((abs(v) for v in all_percents), default=1.0)
    limit = max(limit, 10.0)

    title = "Kbest syscall time delta by kernel"
    subtitle = (
        f"Baseline: {baseline_version} kbest. "
        "Green is faster (lower time), red is slower (higher time)."
    )

    left_margin = 220
    top_margin = 110
    cell_width = 76
    cell_height = 26
    header_height = 34
    width = left_margin + len(versions) * cell_width + 40
    height = top_margin + header_height + len(metric_order) * cell_height + 90

    svg: list[str] = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<style>',
        'text { font-family: "DejaVu Sans Mono", "Menlo", monospace; fill: #111827; }',
        '.title { font-size: 20px; font-weight: 700; }',
        '.subtitle { font-size: 12px; fill: #4b5563; }',
        '.label { font-size: 12px; }',
        '.celltext { font-size: 11px; text-anchor: middle; dominant-baseline: middle; }',
        '.metric { font-size: 12px; }',
        '.small { font-size: 11px; fill: #4b5563; }',
        '</style>',
        f'<rect x="0" y="0" width="{width}" height="{height}" fill="#ffffff" />',
        f'<text x="20" y="30" class="title">{html.escape(title)}</text>',
        f'<text x="20" y="52" class="subtitle">{html.escape(subtitle)}</text>',
    ]

    legend_x = 20
    legend_y = 70
    legend_width = 220
    legend_height = 16
    steps = 20
    step_w = legend_width / steps
    for i in range(steps):
        value = -limit + (2 * limit * i / (steps - 1))
        color = color_for_percent(value, limit)
        svg.append(
            f'<rect x="{legend_x + i * step_w:.2f}" y="{legend_y}" width="{step_w + 0.5:.2f}" '
            f'height="{legend_height}" fill="{color}" stroke="none" />'
        )
    svg.extend(
        [
            f'<rect x="{legend_x}" y="{legend_y}" width="{legend_width}" height="{legend_height}" fill="none" stroke="#9ca3af" stroke-width="1" />',
            f'<text x="{legend_x}" y="{legend_y + 30}" class="small">{percent_label(-limit)}</text>',
            f'<text x="{legend_x + legend_width / 2}" y="{legend_y + 30}" text-anchor="middle" class="small">0.0%</text>',
            f'<text x="{legend_x + legend_width}" y="{legend_y + 30}" text-anchor="end" class="small">{percent_label(limit)}</text>',
        ]
    )

    table_x = 20
    table_y = top_margin

    svg.append(
        f'<rect x="{table_x}" y="{table_y}" width="{left_margin - 20}" height="{header_height}" fill="#e5e7eb" stroke="#9ca3af" stroke-width="1" />'
    )
    svg.append(
        f'<text x="{table_x + 10}" y="{table_y + 22}" class="label">syscall</text>'
    )

    for col, version in enumerate(versions):
        x = table_x + left_margin + col * cell_width
        svg.append(
            f'<rect x="{x}" y="{table_y}" width="{cell_width}" height="{header_height}" fill="#e5e7eb" stroke="#9ca3af" stroke-width="1" />'
        )
        svg.append(
            f'<text x="{x + cell_width / 2}" y="{table_y + 22}" text-anchor="middle" class="label">{html.escape(version)}</text>'
        )

    for row_idx, metric in enumerate(metric_order):
        y = table_y + header_height + row_idx * cell_height

        svg.append(
            f'<rect x="{table_x}" y="{y}" width="{left_margin - 20}" height="{cell_height}" fill="#f9fafb" stroke="#d1d5db" stroke-width="1" />'
        )
        svg.append(
            f'<text x="{table_x + 8}" y="{y + 17}" class="metric">{html.escape(metric)}</text>'
        )

        for col_idx, percent in enumerate(rows[row_idx]):
            x = table_x + left_margin + col_idx * cell_width
            fill = color_for_percent(percent, limit)
            text_fill = text_color_for_percent(percent, limit)
            label = percent_label(percent)
            svg.append(
                f'<rect x="{x}" y="{y}" width="{cell_width}" height="{cell_height}" fill="{fill}" stroke="#d1d5db" stroke-width="1" />'
            )
            svg.append(
                f'<text x="{x + cell_width / 2}" y="{y + cell_height / 2 + 1}" class="celltext" fill="{text_fill}">{html.escape(label)}</text>'
            )

    footer_y = table_y + header_height + len(metric_order) * cell_height + 28
    svg.append(
        f'<text x="20" y="{footer_y}" class="small">Generated from results/output.*.csv using kbest only. Files like results/kbest-relative-to-5.0.0.txt are ignored.</text>'
    )
    svg.append("</svg>")

    OUTPUT_FILE.write_text("\n".join(svg))
    print(f"wrote {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
