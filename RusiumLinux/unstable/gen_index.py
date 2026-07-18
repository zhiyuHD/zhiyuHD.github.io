#!/usr/bin/env python3
"""Generate RusiumLinux package index from Debian Packages.gz

Usage: python3 gen_index.py [--mirror MIRROR] [--suite SUITE] [--arch ARCH]
       python3 gen_index.py --list  # list available files first

Outputs: packages.json (for GitHub Pages)

Debian copyright attribution:
- This index references packages from Debian GNU/Linux.
- Debian is a registered trademark of Software in the Public Interest, Inc.
- Individual package copyrights are included in each .deb under /usr/share/doc/<pkg>/copyright
- See https://www.debian.org/ for more information.
"""

import sys, os, json, gzip, re, argparse
from urllib.request import urlopen
from datetime import datetime, timezone

DEFAULT_MIRROR = "http://deb.debian.org/debian"
DEFAULT_SUITE = "unstable"
DEFAULT_ARCH = "amd64"

def fetch_packages_gz(mirror, suite, arch, component="main"):
    """Fetch and return the raw content of Packages.gz"""
    url = f"{mirror}/dists/{suite}/{component}/binary-{arch}/Packages.gz"
    print(f"Fetching {url}...", file=sys.stderr)
    resp = urlopen(url)
    data = resp.read()
    return gzip.decompress(data).decode("utf-8", errors="replace")

def parse_packages(content):
    """Parse Debian Packages format into list of dicts"""
    packages = {}
    current = None
    
    for line in content.split("\n"):
        if line == "":
            if current and "Package" in current:
                pkg_name = current["Package"]
                packages[pkg_name] = current
            current = None
            continue
        
        if line.startswith(" "):
            # Multi-line field continuation
            if current:
                key = list(current.keys())[-1]
                current[key] += "\n" + line.strip()
            continue
        
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)", line)
        if m:
            key = m.group(1)
            val = m.group(2).strip()
            if current is None:
                current = {}
            current[key] = val
    
    # Last package
    if current and "Package" in current:
        packages[current["Package"]] = current
    
    return packages

def generate_index(parsed, mirror, suite, arch):
    """Convert parsed packages to our index format"""
    index = {
        "generated": datetime.now(timezone.utc).isoformat(),
        "mirror": mirror,
        "suite": suite,
        "architecture": arch,
        "attribution": (
            "This index references packages from Debian GNU/Linux. "
            "Debian is a registered trademark of Software in the Public Interest, Inc. "
            "See https://www.debian.org/"
        ),
        "packages": {}
    }
    
    for pkg_name, pkg_data in parsed.items():
        filename = pkg_data.get("Filename", "")
        if not filename:
            continue
        
        entry = {
            "version": pkg_data.get("Version", "unknown"),
            "filename": filename,
            "description": pkg_data.get("Description", "").split("\n")[0].strip(),
            "section": pkg_data.get("Section", ""),
            "maintainer": pkg_data.get("Maintainer", ""),
            "homepage": pkg_data.get("Homepage", ""),
            "depends": pkg_data.get("Depends", ""),
            "size": pkg_data.get("Size", "0"),
            "installed_size": pkg_data.get("Installed-Size", "0"),
        }
        
        # Full download URL
        if not filename.startswith("/"):
            entry["url"] = f"{mirror}/{filename}"
        else:
            entry["url"] = f"{mirror}{filename}"
        
        index["packages"][pkg_name] = entry
    
    return index

def list_suites(mirror):
    """List available suites at the mirror"""
    url = f"{mirror}/dists/"
    print(f"Fetching {url}...", file=sys.stderr)
    resp = urlopen(url)
    html = resp.read().decode()
    suites = re.findall(r'href="([^"]+)/"', html)
    # Filter out parent directory and common non-suite entries
    suites = [s for s in suites if s not in ("..",)]
    return sorted(suites)

def main():
    parser = argparse.ArgumentParser(description="Generate RusiumLinux package index")
    parser.add_argument("--mirror", default=DEFAULT_MIRROR, help="Debian mirror URL")
    parser.add_argument("--suite", default=DEFAULT_SUITE, help="Debian suite (stable, testing, unstable)")
    parser.add_argument("--arch", default=DEFAULT_ARCH, help="Architecture")
    parser.add_argument("--component", default="main", help="Component (main, contrib, non-free)")
    parser.add_argument("--output", default="packages.json", help="Output JSON file")
    parser.add_argument("--list", action="store_true", help="List available suites and exit")
    parser.add_argument("--split", action="store_true", help="Split index into first-namespace dirs")
    args = parser.parse_args()
    
    if args.list:
        suites = list_suites(args.mirror)
        print("Available suites:")
        for s in suites:
            print(f"  {s}")
        return 0
    
    print(f"Generating index for {args.suite}/{args.arch} from {args.mirror}", file=sys.stderr)
    
    content = fetch_packages_gz(args.mirror, args.suite, args.arch, args.component)
    parsed = parse_packages(content)
    index = generate_index(parsed, args.mirror, args.suite, args.arch)
    
    # Filter and split by section
    USEFUL_SECTIONS = {
        "admin", "editors", "interpreters", "misc",
        "net", "shells", "text", "utils", "devel",
    }
    by_section = {}
    for pkg_name, pkg_data in index["packages"].items():
        section = pkg_data.get("section", "misc")
        if not section or section not in USEFUL_SECTIONS:
            continue
        by_section.setdefault(section, {})[pkg_name] = pkg_data
    
    if args.split:
        # Write section-split files
        index_dir = os.path.dirname(args.output) or "."
        sections_index = {"generated": index["generated"], "sections": {}, "pkg_section": {}}
        for section, pkgs in sorted(by_section.items()):
            section_file = os.path.join(index_dir, f"{section}.json")
            section_index = {
                "generated": index["generated"],
                "mirror": index["mirror"],
                "suite": index["suite"],
                "architecture": index["architecture"],
                "attribution": index["attribution"],
                "section": section,
                "packages": pkgs,
            }
            with open(section_file, "w") as f:
                json.dump(section_index, f, indent=1, ensure_ascii=False)
            sections_index["sections"][section] = len(pkgs)
            for pkg_name in pkgs:
                sections_index["pkg_section"][pkg_name] = section
            print(f"  {section}: {len(pkgs)} packages -> {os.path.basename(section_file)}", file=sys.stderr)
        
        # Write main index
        sections_index["total"] = sum(len(v) for v in by_section.values())
        with open(args.output, "w") as f:
            json.dump(sections_index, f, indent=1)
        
        total = sum(len(v) for v in by_section.values())
        print(f"\nMain index: {args.output}", file=sys.stderr)
        print(f"Split into {len(by_section)} section files, {total} total packages", file=sys.stderr)
        
        # Also generate a flat text index for easy grep-ing
        text_index_file = os.path.join(index_dir, "packages.txt")
        with open(text_index_file, "w") as f:
            # Merge all sections into one sorted list
            all_pkgs = {}
            for pkgs in by_section.values():
                all_pkgs.update(pkgs)
            for pkg_name in sorted(all_pkgs):
                pkg_data = all_pkgs[pkg_name]
                section = pkg_data.get("section", "unknown")
                url = pkg_data.get("url", "")
                version = pkg_data.get("version", "unknown")
                desc = pkg_data.get("description", "").replace("|", "/")[:120]
                # Format: pkgname|section|version|url|description
                f.write(f"{pkg_name}|{section}|{version}|{url}|{desc}\n")
        text_size = os.path.getsize(text_index_file)
        print(f"  text index: {os.path.basename(text_index_file)} ({text_size/1024:.0f}K, {len(all_pkgs)} entries)", file=sys.stderr)
    else:
        # Single file (compact version with all useful sections)
        merged = {}
        for pkgs in by_section.values():
            merged.update(pkgs)
        index["packages"] = merged
        with open(args.output, "w") as f:
            json.dump(index, f, indent=1, ensure_ascii=False)
        print(f"Generated {args.output} with {len(merged)} packages", file=sys.stderr)
        print(f"Index size: {os.path.getsize(args.output)} bytes", file=sys.stderr)
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
