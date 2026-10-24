#!/usr/bin/env python3
"""Offline subprocess fixture; writes only into the caller's temporary directory."""
import argparse
import json
from pathlib import Path
import signal
import time

parser = argparse.ArgumentParser()
parser.add_argument("--input", default="")
parser.add_argument("--dir", default="")
parser.add_argument("--result-file", default="")
args, _ = parser.parse_known_args()
if args.input == "sleep":
    signal.signal(signal.SIGTERM, lambda *unused: (time.sleep(0.25), exit(15)))
    print("READY", flush=True)
    time.sleep(10)
elif args.input == "empty":
    pass
elif args.input == "fail":
    print("failed fixture", flush=True)
    exit(1)
else:
    directory = Path(args.dir) / "book-fixture"
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / "download.txt"
    target.write_text("downloaded fixture")
    report = Path(args.result_file)
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps({"version": 1, "saved": 1, "skipped": 0, "failed": 0,
                                 "files": [str(target)], "output_directories": [str(directory)]}))
    if args.input == "flood":
        for _ in range(2000):
            print("古籍下载日志" * 10)
    print("FINAL-LOG-LINE", flush=True)
