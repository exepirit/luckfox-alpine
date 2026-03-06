#!/usr/bin/env python3
"""Build Alpine packages from a branch directory in dependency order."""

import argparse
import collections
import os
import re
import subprocess
import sys
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(
        description="Build Alpine Linux packages in dependency order."
    )
    parser.add_argument(
        "--branch",
        default="mesh",
        help="Branch subdirectory name under packages/ (default: mesh)",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        metavar="DIR",
        help="Destination directory for built .apk files (REPODEST)",
    )
    parser.add_argument(
        "--packages-dir",
        default="./packages",
        metavar="DIR",
        help="Root packages directory (default: ./packages)",
    )
    return parser.parse_args()


def parse_apkbuild(apkbuild_path: Path) -> dict:
    """
    Parse key fields from an APKBUILD file.

    Returns dict with keys:
      - 'pkgname': str or None
      - 'depends': list[str]
    """
    text = apkbuild_path.read_text(encoding="utf-8", errors="replace")

    def extract_field(field: str) -> str | None:
        """Extract the value of a shell variable assignment, handling multi-line quoted values."""
        # Match: field="..." or field='...' (single line)
        # or field="...\n...\n..." (multi-line with closing quote on its own line)
        pattern = re.compile(
            r'^' + re.escape(field) + r'''=(['"])(.*?)(\1)''',
            re.MULTILINE | re.DOTALL,
        )
        m = pattern.search(text)
        if m:
            return m.group(2)

        # Fallback: unquoted single-word value
        pattern_bare = re.compile(
            r'^' + re.escape(field) + r'=(\S+)',
            re.MULTILINE,
        )
        m2 = pattern_bare.search(text)
        if m2:
            return m2.group(1)

        return None

    pkgname_raw = extract_field("pkgname")
    depends_raw = extract_field("depends") or ""

    # Remove backslash-newline continuations, then split on whitespace
    depends_clean = depends_raw.replace("\\\n", " ")
    depends = depends_clean.split()

    return {
        "pkgname": pkgname_raw.strip() if pkgname_raw else None,
        "depends": depends,
    }


def build_dep_graph(
    packages: list[tuple[str, Path]],
) -> tuple[dict[str, set[str]], dict[str, Path]]:
    """
    Build an intra-branch dependency graph.

    Returns:
      - graph: {pkgname: set of local deps (only packages present in branch)}
      - dir_map: {pkgname: pkgdir path}
    """
    local_names: dict[str, Path] = {}

    for dir_name, pkgdir in packages:
        info = parse_apkbuild(pkgdir / "APKBUILD")
        pkgname = info["pkgname"]
        if pkgname is None:
            print(f"Warning: no pkgname in {pkgdir}/APKBUILD, skipping", file=sys.stderr)
            continue
        local_names[pkgname] = pkgdir

    graph: dict[str, set[str]] = {}
    for dir_name, pkgdir in packages:
        info = parse_apkbuild(pkgdir / "APKBUILD")
        pkgname = info["pkgname"]
        if pkgname is None:
            continue
        local_deps = {d for d in info["depends"] if d in local_names}
        graph[pkgname] = local_deps

    return graph, local_names


def topological_sort(graph: dict[str, set[str]]) -> list[str]:
    """
    Kahn's algorithm for topological sort.

    Returns ordered list of package names (dependencies before dependents).
    Exits with code 1 if a cycle is detected.
    """
    in_degree = {}
    for pkg in graph:
        in_degree[pkg] = len(graph[pkg])

    queue = collections.deque(pkg for pkg, deg in in_degree.items() if deg == 0)
    result = []

    dependents: dict[str, list[str]] = {pkg: [] for pkg in graph}
    for pkg, deps in graph.items():
        for dep in deps:
            dependents[dep].append(pkg)

    while queue:
        pkg = queue.popleft()
        result.append(pkg)
        for dependent in dependents.get(pkg, []):
            in_degree[dependent] -= 1
            if in_degree[dependent] == 0:
                queue.append(dependent)

    if len(result) != len(graph):
        cyclic = [pkg for pkg in graph if pkg not in result]
        print(f"Error: cyclic dependency detected among: {cyclic}", file=sys.stderr)
        sys.exit(1)

    return result


def discover_packages(packages_dir: Path, branch: str) -> list[tuple[str, Path]]:
    """Return list of (pkgname_dir, pkgdir) for all packages in branch."""
    branch_dir = packages_dir / branch
    if not branch_dir.is_dir():
        print(f"Error: branch directory not found: {branch_dir}", file=sys.stderr)
        sys.exit(1)

    packages = []
    for pkgdir in sorted(branch_dir.iterdir()):
        if not pkgdir.is_dir():
            continue
        apkbuild = pkgdir / "APKBUILD"
        if not apkbuild.is_file():
            print(f"Warning: no APKBUILD in {pkgdir}, skipping", file=sys.stderr)
            continue
        packages.append((pkgdir.name, pkgdir))

    return packages


def build_packages(
    ordered: list[str],
    pkg_dirs: dict[str, Path],
    output_dir: Path,
) -> None:
    """
    Build each package in topological order using abuild -r.

    Sets REPODEST env var to output_dir.
    Exits with code 1 on first build failure.
    """
    env = os.environ.copy()
    env["REPODEST"] = str(output_dir)

    output_dir.mkdir(parents=True, exist_ok=True)

    for pkgname in ordered:
        pkgdir = pkg_dirs[pkgname]
        print(f"\n==> Building: {pkgname} (in {pkgdir})")
        try:
            subprocess.run(
                ["abuild", "-r"],
                cwd=str(pkgdir),
                env=env,
                check=True,
            )
        except subprocess.CalledProcessError as exc:
            print(
                f"Error: build failed for '{pkgname}' (exit code {exc.returncode})",
                file=sys.stderr,
            )
            sys.exit(1)

    print(f"\nAll {len(ordered)} package(s) built successfully.")
    print(f"Output: {output_dir}")


def main():
    args = parse_args()
    packages_dir = Path(args.packages_dir).resolve()
    output_dir = Path(args.output_dir).resolve()

    packages = discover_packages(packages_dir, args.branch)
    if not packages:
        print("No packages found.", file=sys.stderr)
        sys.exit(1)

    graph, pkg_dirs = build_dep_graph(packages)
    ordered = topological_sort(graph)

    print(f"Build order for branch '{args.branch}':")
    for i, name in enumerate(ordered, 1):
        print(f"  {i}. {name}")

    build_packages(ordered, pkg_dirs, output_dir)


if __name__ == "__main__":
    main()