#!/usr/bin/env python3
"""Disposable U3 shell probe sampler.

The sampler follows the plan's definition of memory: phys_footprint summed over
all descendants, sampled once per second. It intentionally measures the trivial
probe window, not the production review fixture.
"""
from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import tempfile
import time
from pathlib import Path


def descendants(root: int) -> list[int]:
    rows = subprocess.check_output(["ps", "-axo", "pid=,ppid="], text=True)
    children: dict[int, list[int]] = {}
    for row in rows.splitlines():
        fields = row.split()
        if len(fields) != 2:
            continue
        pid, parent = map(int, fields)
        children.setdefault(parent, []).append(pid)
    found: list[int] = []
    pending = [root]
    while pending:
        pid = pending.pop()
        if pid in found:
            continue
        found.append(pid)
        pending.extend(children.get(pid, []))
    return found


def footprint(pid: int) -> int:
    try:
        output = subprocess.check_output(
            ["footprint", "-p", str(pid), "-f", "bytes"],
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except subprocess.CalledProcessError:
        return 0
    for line in output.splitlines():
        if "Footprint:" in line:
            fields = line.split()
            if len(fields) >= 5:
                return int(fields[4])
    return 0


def kill_tree(root: int) -> None:
    pids = descendants(root)
    for pid in reversed(pids):
        if pid == os.getpid():
            continue
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass


def run_once(app: Path, executable: Path, seconds: int, label: str) -> dict[str, object]:
    with tempfile.TemporaryDirectory(prefix=f"qaptr-u3-{label}-") as directory:
        root = Path(directory)
        paint = root / "paint"
        tcc = root / "tcc"
        environment = os.environ.copy()
        environment.update(
            {
                "QAPTR_U3_PAINT_FILE": str(paint),
                "QAPTR_U3_TCC_FILE": str(tcc),
                "QAPTR_U3_REQUEST_TCC": "0",
            }
        )
        started = time.time_ns()
        process = subprocess.Popen(
            [str(executable)],
            cwd=app,
            env=environment,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            deadline = time.monotonic() + 15
            while not paint.exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            painted = int(paint.read_text().splitlines()[0]) if paint.exists() else None
            samples: list[dict[str, object]] = []
            until = time.monotonic() + seconds
            while time.monotonic() < until:
                pids = descendants(process.pid)
                total = sum(footprint(pid) for pid in pids)
                samples.append({"at": time.time_ns(), "bytes": total, "pids": pids})
                time.sleep(1)
            return {
                "label": label,
                "duration_seconds": seconds,
                "pid": process.pid,
                "started_ns": started,
                "painted_ns": painted,
                "paint_ms": None if painted is None else (painted - started) / 1_000_000,
                "samples": samples,
                "median_mib": sorted(s["bytes"] for s in samples)[len(samples) // 2] / 1_048_576,
                "peak_mib": max(s["bytes"] for s in samples) / 1_048_576,
                "tcc": tcc.read_text().strip() if tcc.exists() else None,
            }
        finally:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("label", choices=["swiftui", "tauri"])
    parser.add_argument("app", type=Path)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--seconds", type=int, default=60)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    results = [run_once(args.app, args.executable, args.seconds, args.label) for _ in range(args.runs)]
    args.output.write_text(json.dumps(results, indent=2) + "\n")
    for result in results:
            paint_text = "n/a" if result["paint_ms"] is None else f"{result['paint_ms']:.1f} ms"
            print(
                f"{args.label} run: paint={paint_text} "
                f"median={result['median_mib']:.2f} MiB peak={result['peak_mib']:.2f} MiB"
            )


if __name__ == "__main__":
    main()
