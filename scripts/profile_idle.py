#!/usr/bin/env python3
"""Measure an already-running PawSync process without synthesizing input."""
import argparse
import json
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pid", required=True, type=int)
    parser.add_argument("--seconds", type=int, default=60)
    args = parser.parse_args()
    if args.pid <= 0 or args.seconds < 10: raise SystemExit("Use a valid process ID and at least 10 seconds")
    def snapshot():
        try:
            values = subprocess.check_output(["ps", "-p", str(args.pid), "-o", "time=,rss="], text=True).split()
        except subprocess.CalledProcessError:
            raise SystemExit("PawSync process exited") from None
        if len(values) != 2: raise SystemExit("PawSync process exited")
        # ps %cpu includes a decaying history of launch work. CPU-time deltas
        # measure this sampling interval, which is what an idle budget needs.
        parts = values[0].split(":")
        cpu_seconds = sum(float(part) * 60 ** index for index, part in enumerate(reversed(parts)))
        return time.monotonic(), cpu_seconds, int(values[1]) / 1024

    first = snapshot()
    samples = [first]
    deadline = time.monotonic() + args.seconds
    while time.monotonic() < deadline:
        time.sleep(1)
        samples.append(snapshot())
    wall_time = samples[-1][0] - first[0]
    cpu = 100 * (samples[-1][1] - first[1]) / wall_time
    memory = max(value[2] for value in samples)
    result = {"pid": args.pid, "samples": len(samples), "interval_cpu_percent": round(cpu, 3), "peak_rss_mb": round(memory, 2), "cpu_target": 0.5, "ram_target_mb": 60, "passed": cpu < 0.5 and memory < 60}
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["passed"] else 1)


if __name__ == "__main__": main()
