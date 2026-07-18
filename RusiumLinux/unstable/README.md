# RusiumLinux Package Index

This directory contains the **RusiumLinux package index** — a curated metadata index of packages from **Debian GNU/Linux**.

## Legal Status

### What We Host vs What We Don't

- **We host**: Package metadata only — names, versions, descriptions, and download URLs
- **We do NOT host**: Any binary `.deb` files, source code, or copyrighted package content
- **We do NOT modify**: No Debian packages are altered by us
- **How it works**: The package manager `ru` reads URLs from this index and downloads `.deb` files **directly from Debian mirrors** (deb.debian.org). The index is essentially a curated `sources.list` entry.

### Attribution & Copyright

**Debian** is a registered trademark of *Software in the Public Interest, Inc.*

Packages referenced in this index are copyrighted by their respective authors and licensed under various open-source licenses (GPL, BSD, MIT, Apache, etc.). Each package's specific license and copyright information:

1. **After installation**: `/usr/share/doc/<package>/copyright` (preserved by `ru`)
2. **Online**: https://packages.debian.org/unstable/<packagename>
3. **Source code**: https://tracker.debian.org/pkg/<srcpackagename>

### GPL Compliance

For packages licensed under the GNU General Public License (GPL), the corresponding **source code** is available from Debian's source repositories:

- Debian source mirror: `deb.debian.org/debian` (pool/ directory)
- Source package tracker: https://tracker.debian.org/pkg/<srcpackagename>
- `apt-get source <package>` or `dget` from Debian tools

The `ru` package manager does not distribute, convey, or sublicense any GPL-licensed software — it downloads packages directly from Debian's official distribution channel. Users of `ru` are bound by the original package licenses as if they had installed via `apt` or `dpkg`.

### Index Metadata

The package index (`packages.txt`, `packages.json`) contains only factual metadata derived from Debian's `Packages.gz`:
- Package name, version, section
- Download URL pointing to deb.debian.org
- One-line description (from Debian package metadata)

This metadata is widely republished by Debian's own infrastructure, apt, and third-party package indexing services.

### License of RusiumLinux-Specific Tooling

The `gen_index.py` script, `ru` package manager source, and related tooling are provided under the **MIT License** (see [LICENSE](/LICENSE) at repo root).

## Usage

The `ru` package manager reads this index to download and install packages:

```sh
ru update-index           # fetch index from GitHub Pages
ru search <pattern>       # search packages
ru info <package>         # show details
ru add <package>          # download .deb from Debian + install
ru copyright <package>    # view package copyright
```

All packages are downloaded directly from `deb.debian.org`.

## Index Format

The index is available in two formats:

### Text format (`packages.txt`) — used by `ru`

```
pkgname|section|version|url|description
```

Grep-friendly, one package per line. Used by the `ru` package manager for fast lookups via `grep`.

### JSON format (section files)

- `packages.json` — section listing and package→section mapping
- `admin.json`, `devel.json`, `editors.json`, `interpreters.json`, `misc.json`, `net.json`, `shells.json`, `text.json`, `utils.json`

Each section file contains:
```json
{
  "generated": "ISO timestamp",
  "mirror": "Debian mirror URL",
  "suite": "unstable",
  "architecture": "amd64",
  "section": "editors",
  "packages": { "nano": { "version": "...", "url": "http://deb.debian.org/..." } }
}
```

Generated for suite `unstable`, architecture `amd64`.
