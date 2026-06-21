#!/usr/bin/env python3
"""Build a deployable source tarball for the Linux app host."""

from __future__ import annotations

import argparse
import tarfile
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE_ROOT = "backend-v1"
DEFAULT_DIRS = (
    "deploy",
    "doc",
    "frontend",
    "map_tiles",
    "reference",
    "scripts",
    "simulated_data",
)
DEFAULT_FILES = (
    ".env.example",
    "auth_users.example.json",
    "CLAUDE.md",
    "DECISIONS.md",
    "Makefile",
    "PROJECT_FEATURES.md",
    "README.md",
    "environment.yml",
    "pyproject.toml",
    "uv.lock",
)
EXCLUDED_DIRS = {
    ".git",
    ".venv",
    "__pycache__",
    "build",
    "dist",
    "logs",
    "frontend_backup_20260430_201419",
}
EXCLUDED_SUFFIXES = {".pyc", ".pyo", ".bak"}


def should_include(path: Path) -> bool:
    rel = path.relative_to(ROOT)
    if any(part in EXCLUDED_DIRS for part in rel.parts):
        return False
    if path.suffix in EXCLUDED_SUFFIXES:
        return False
    if path.name == ".DS_Store":
        return False
    return True


def normalize_tarinfo(tarinfo: tarfile.TarInfo) -> tarfile.TarInfo:
    tarinfo.uid = 0
    tarinfo.gid = 0
    tarinfo.uname = ""
    tarinfo.gname = ""
    if tarinfo.isfile():
        if tarinfo.name.endswith(".sh") or tarinfo.name.endswith("package_release.py"):
            tarinfo.mode = 0o755
        else:
            tarinfo.mode = 0o644
    elif tarinfo.isdir():
        tarinfo.mode = 0o755
    return tarinfo


def add_path(tar: tarfile.TarFile, path: Path) -> None:
    if not path.exists() or not should_include(path):
        return
    if path.is_file():
        tar.add(
            path,
            arcname=f"{PACKAGE_ROOT}/{path.relative_to(ROOT).as_posix()}",
            filter=normalize_tarinfo,
        )
        return
    for child in sorted(path.rglob("*")):
        if child.is_file() and should_include(child):
            arcname = f"{PACKAGE_ROOT}/{child.relative_to(ROOT).as_posix()}"
            tar.add(child, arcname=arcname, filter=normalize_tarinfo)


def build(tag: str) -> Path:
    out_dir = ROOT / "dist"
    out_dir.mkdir(exist_ok=True)
    out_file = out_dir / f"backend-v1-{tag}.tar.gz"

    with tarfile.open(out_file, "w:gz") as tar:
        for py_file in sorted(ROOT.glob("*.py")):
            add_path(tar, py_file)
        for file_name in DEFAULT_FILES:
            add_path(tar, ROOT / file_name)
        for dir_name in DEFAULT_DIRS:
            add_path(tar, ROOT / dir_name)

    return out_file


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "tag",
        nargs="?",
        default=datetime.now().strftime("%Y%m%d-%H%M"),
        help="Release tag used in dist/backend-v1-<tag>.tar.gz",
    )
    args = parser.parse_args()
    out_file = build(args.tag)
    size_mb = out_file.stat().st_size / 1024 / 1024
    print(f"created {out_file} ({size_mb:.1f} MiB)")


if __name__ == "__main__":
    main()
