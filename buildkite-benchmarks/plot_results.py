#!/usr/bin/env python3
"""
plot_results.py — Generate lollipop charts from benchmark CSV data.

Usage:
    python3 plot_results.py results/benchmarks.csv [--outdir results/]

Input CSV format (no header):
    compiler,project,old_avg,old_sd,new_avg,new_sd,diff_pct

Produces one lollipop chart per compiler showing the time difference %
for every project that has data for both old and new commits.
"""

import argparse
import csv
import math
import os
import sys

import matplotlib.pyplot as plt
import matplotlib.ticker as ticker


def load_csv(path):
    """Return list of dicts from the benchmark CSV."""
    rows = []
    with open(path, newline="") as f:
        reader = csv.reader(f)
        for r in reader:
            if len(r) < 7 or r[6] == "N/A":
                continue
            try:
                diff = float(r[6])
            except ValueError:
                continue
            rows.append({
                "compiler": r[0],
                "project": r[1],
                "old_avg": float(r[2]),
                "old_sd": float(r[3]),
                "new_avg": float(r[4]),
                "new_sd": float(r[5]),
                "diff_pct": diff,
            })
    return rows


def short_name(project):
    """'dlang-community/D-Scanner' → 'D-Scanner'"""
    return project.split("/")[-1]


def plot_lollipop(rows, compiler, outdir):
    """Draw a horizontal lollipop chart for one compiler."""
    # Sort by diff_pct so the chart reads from most-improved to most-regressed.
    rows = sorted(rows, key=lambda r: r["diff_pct"])

    projects = [short_name(r["project"]) for r in rows]
    diffs = [r["diff_pct"] for r in rows]

    # Propagate std devs into the percentage difference.
    # diff% = (new - old) / old * 100
    # σ(diff%) ≈ 100 * sqrt(σ_new² + σ_old²) / old
    diff_errs = []
    for r in rows:
        o, so, sn = r["old_avg"], r["old_sd"], r["new_sd"]
        if o != 0:
            err = 100 * math.sqrt(sn ** 2 + so ** 2) / o
        else:
            err = 0.0
        diff_errs.append(err)

    n = len(projects)
    fig_height = max(4, 0.38 * n)
    fig, ax = plt.subplots(figsize=(10, fig_height))

    # Colours: green for improvement (negative diff), red for regression.
    colors = ["#2ecc71" if d <= 0 else "#e74c3c" for d in diffs]

    y_pos = range(n)

    # Stems
    ax.hlines(y=y_pos, xmin=0, xmax=diffs, colors=colors, linewidth=1.5)
    # Dots with std-dev error bars
    for i in y_pos:
        ax.errorbar(diffs[i], i, xerr=diff_errs[i],
                     fmt='o', color=colors[i], markersize=5,
                     ecolor=colors[i], elinewidth=1, capsize=3,
                     alpha=0.8, zorder=3)

    # Zero line
    ax.axvline(0, color="grey", linewidth=0.8, linestyle="--")

    ax.set_yticks(list(y_pos))
    ax.set_yticklabels(projects, fontsize=8)
    ax.set_xlabel("Time difference (%)")
    ax.set_title(f"{compiler.upper()} — Test-time change (non-template → template)")
    ax.xaxis.set_major_formatter(ticker.FormatStrFormatter("%+.1f%%"))

    # Annotate each dot with its value (placed above the lollipop line).
    for i, d in enumerate(diffs):
        ha = "left" if d >= 0 else "right"
        offset = 0.5 if d >= 0 else -0.5
        ax.annotate(f"{d:+.1f}%", (d + offset, i - 0.3),
                     va="bottom", ha=ha, fontsize=9, color=colors[i])

    ax.invert_yaxis()
    ax.grid(axis="x", alpha=0.3)
    fig.tight_layout()

    outpath = os.path.join(outdir, f"{compiler}_lollipop.svg")
    fig.savefig(outpath)
    plt.close(fig)
    print(f"Saved {outpath}")


def main():
    parser = argparse.ArgumentParser(description="Plot benchmark lollipop charts")
    parser.add_argument("csv", help="Path to benchmarks.csv")
    parser.add_argument("--outdir", default=None,
                        help="Directory for PNG output (default: same as CSV)")
    args = parser.parse_args()

    if args.outdir is None:
        args.outdir = os.path.dirname(args.csv) or "."
    os.makedirs(args.outdir, exist_ok=True)

    rows = load_csv(args.csv)
    if not rows:
        print("No plottable data in", args.csv, file=sys.stderr)
        sys.exit(1)

    compilers = sorted(set(r["compiler"] for r in rows))
    for comp in compilers:
        subset = [r for r in rows if r["compiler"] == comp]
        if subset:
            plot_lollipop(subset, comp, args.outdir)


if __name__ == "__main__":
    main()
