"""Read-only collection size and timestamp-coverage report."""
from __future__ import annotations

import argparse
import gzip
import json
from collections import defaultdict
from pathlib import Path


def line_count(path: Path) -> int:
    opener = gzip.open if path.suffix == ".gz" else open
    if path.suffix not in {".jsonl", ".gz"}:
        return 1
    with opener(path, "rt", encoding="utf-8") as handle:
        return sum(1 for _ in handle)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", type=Path, default=Path(__file__).resolve().parents[1] / "data")
    args = parser.parse_args()
    groups: dict[str, list[Path]] = defaultdict(list)
    for path in (args.data_dir / "raw").rglob("*"):
        if path.is_file():
            groups[path.relative_to(args.data_dir / "raw").parts[0]].append(path)
    print(f"{'source':24} {'files':>7} {'records':>10} {'MiB':>10}")
    for source, files in sorted(groups.items()):
        total = sum(path.stat().st_size for path in files)
        count = sum(line_count(path) for path in files)
        print(f"{source:24} {len(files):7} {count:10} {total / 1024 / 1024:10.2f}")


if __name__ == "__main__":
    main()
