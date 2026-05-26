"""Plot libFuzzer coverage trend from a run log.

Usage:
    uv run harness/libexpat/plot_coverage.py build/logs/libexpat/fuzz-*.log

Output:
    build/plots/libexpat/coverage.png

Method:
    libFuzzer doesn't emit wall-clock timestamps. We reconstruct wall time
    from the per-line `exec/s` rate:
        for each consecutive pair of progress lines,
            dt_i = (execs_{i+1} - execs_i) / exec_s_{i+1}
    Then rescale the cumulative sum so it matches the total run time
    reported on the log's final `Done ... runs in N second(s)` line.
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys
from dataclasses import dataclass

import matplotlib.pyplot as plt


# Matches lines like:
#   #244953351\tREDUCE cov: 4480 ft: 16997 corp: 8222/1520Kb lim: 4096 exec/s: 5715 rss: 698Mb ...
PROGRESS_RE = re.compile(
    r"^#(?P<execs>\d+)\s+\S+\s+"
    r"cov:\s+(?P<cov>\d+)\s+"
    r"ft:\s+(?P<ft>\d+)\s+"
    r"corp:\s+\d+/\S+\s+"
    r"(?:lim:\s+\d+\s+)?"
    r"exec/s:\s+(?P<rate>\d+)"
)

DONE_RE = re.compile(r"^Done\s+(?P<execs>\d+)\s+runs\s+in\s+(?P<secs>\d+)\s+second")


@dataclass
class Sample:
    execs: int
    cov: int
    ft: int
    rate: int  # libFuzzer's reported exec/s at this point


def parse_log(path: str) -> tuple[list[Sample], int | None]:
    samples: list[Sample] = []
    total_secs: int | None = None
    with open(path, "r", errors="replace") as f:
        for line in f:
            m = PROGRESS_RE.match(line)
            if m:
                samples.append(
                    Sample(
                        execs=int(m["execs"]),
                        cov=int(m["cov"]),
                        ft=int(m["ft"]),
                        rate=max(int(m["rate"]), 1),
                    )
                )
                continue
            m = DONE_RE.match(line)
            if m:
                total_secs = int(m["secs"])
    return samples, total_secs


def reconstruct_time(samples: list[Sample], total_secs: int | None) -> list[float]:
    """Map exec count to wall time.

    libFuzzer doesn't print wall-clock timestamps. Our two known anchors are
    (execs=0, t=0) and (execs=final, t=total_secs). We use a linear mapping:

        t_i = execs_i * total_secs / final_execs

    Naive exec/s-integration looked tempting (it preserves the shape of
    fast/slow phases), but in practice libFuzzer reports `exec/s: 0` for
    the first ~minute of a run, which produces wildly wrong time deltas.
    Linear mapping is the most defensible reconstruction with the available
    signals, and the error stays small as long as exec/s doesn't vary by
    more than ~2x across the run.
    """
    if not samples or total_secs is None:
        return [0.0] * len(samples)
    final_execs = samples[-1].execs
    if final_execs <= 0:
        return [0.0] * len(samples)
    return [s.execs * total_secs / final_execs for s in samples]


def downsample(xs: list[float], ys: list[int], n: int = 500) -> tuple[list[float], list[int]]:
    """Pick ~n samples evenly along x (time)."""
    if len(xs) <= n:
        return xs, ys
    if xs[-1] <= 0:
        return xs, ys
    step = xs[-1] / n
    out_x: list[float] = []
    out_y: list[int] = []
    next_target = 0.0
    for x, y in zip(xs, ys):
        if x >= next_target:
            out_x.append(x)
            out_y.append(y)
            next_target += step
    # Always keep the final point.
    if out_x[-1] != xs[-1]:
        out_x.append(xs[-1])
        out_y.append(ys[-1])
    return out_x, out_y


def find_saturation_hour(times_s: list[float], covs: list[int], window_h: float = 1.0,
                         rel_threshold: float = 0.01) -> float | None:
    """Earliest time t such that cov grew by less than rel_threshold * cov_final
    over the next window_h hours."""
    if not times_s:
        return None
    final = covs[-1]
    threshold = rel_threshold * final
    window_s = window_h * 3600
    # Two-pointer scan.
    j = 0
    for i in range(len(times_s)):
        while j < len(times_s) - 1 and times_s[j] - times_s[i] < window_s:
            j += 1
        if covs[j] - covs[i] <= threshold:
            return times_s[i]
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("log", help="Path to libFuzzer run log (glob ok)")
    ap.add_argument("-o", "--out", default="build/plots/libexpat/coverage.png")
    ap.add_argument("--title", default="libexpat libFuzzer — 12h coverage trend")
    args = ap.parse_args()

    matched = sorted(glob.glob(args.log))
    if not matched:
        print(f"no log files matched: {args.log}", file=sys.stderr)
        return 2
    log_path = matched[-1]  # latest
    print(f"parsing: {log_path}")

    samples, total_secs = parse_log(log_path)
    if not samples:
        print("no progress lines parsed", file=sys.stderr)
        return 1
    print(f"  progress lines: {len(samples)}")
    print(f"  final execs:    {samples[-1].execs:,}")
    print(f"  final cov:      {samples[-1].cov}")
    print(f"  final ft:       {samples[-1].ft}")
    print(f"  total time:     {total_secs}s" if total_secs else "  total time: (unknown)")

    times_s = reconstruct_time(samples, total_secs)
    covs = [s.cov for s in samples]
    fts = [s.ft for s in samples]

    sat = find_saturation_hour(times_s, covs)
    if sat is not None:
        print(f"  cov saturation (<1% growth in next 1h): t = {sat/3600:.2f}h")

    # Downsample for plotting.
    xs_cov, ys_cov = downsample(times_s, covs)
    xs_ft, ys_ft = downsample(times_s, fts)
    hours_cov = [t / 3600 for t in xs_cov]
    hours_ft = [t / 3600 for t in xs_ft]

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    fig, ax_cov = plt.subplots(figsize=(10, 5.5))

    color_cov = "#1f77b4"
    color_ft = "#d62728"

    ax_cov.plot(hours_cov, ys_cov, color=color_cov, linewidth=1.8, label="cov (PCs)")
    ax_cov.set_xlabel("wall-clock time (hours)")
    ax_cov.set_ylabel("cov — PC counters hit", color=color_cov)
    ax_cov.tick_params(axis="y", labelcolor=color_cov)
    ax_cov.grid(True, alpha=0.3)
    ax_cov.set_xlim(0, max(hours_cov[-1], 12))

    ax_ft = ax_cov.twinx()
    ax_ft.plot(hours_ft, ys_ft, color=color_ft, linewidth=1.4, alpha=0.85, label="ft (features)")
    ax_ft.set_ylabel("ft — features", color=color_ft)
    ax_ft.tick_params(axis="y", labelcolor=color_ft)

    if sat is not None:
        sat_h = sat / 3600
        ax_cov.axvline(sat_h, color="grey", linestyle="--", linewidth=1, alpha=0.7)
        ax_cov.text(
            sat_h + 0.1,
            min(ys_cov) + (max(ys_cov) - min(ys_cov)) * 0.05,
            f"saturation ≈ {sat_h:.1f}h",
            fontsize=9,
            color="grey",
        )

    plt.title(args.title)
    fig.tight_layout()
    fig.savefig(args.out, dpi=150)
    print(f"wrote: {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
