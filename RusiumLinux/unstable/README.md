# RusiumLinux Package Index

This directory contains the RusiumLinux package index, referencing packages from **Debian GNU/Linux**.

## Attribution & Copyright

RusiumLinux is a Linux distribution built on packages from Debian GNU/Linux.

**Debian** is a registered trademark of *Software in the Public Interest, Inc.*

### Debian Copyright

This project distributes packages sourced from Debian repositories. Debian packages are distributed under various licenses (GPL, BSD, MIT, Apache, etc.). Each package's specific license and copyright information can be found:

1. **Within each `.deb` package**: After installation, copyright files are at `/usr/share/doc/<package>/copyright`
2. **Online**: https://packages.debian.org/unstable/<packagename>
3. **Source**: https://tracker.debian.org/pkg/<srcpackagename>

### Our Usage

We do not modify the Debian binary packages — we repackage them for use in RusiumLinux. All original copyright notices, license texts, and attribution requirements are preserved.

For the index itself: the package list, descriptions, and metadata are derived from Debian's `Packages.gz` index, which is published under the same licenses as the packages it describes.

### License of RusiumLinux-specific files

The RusiumLinux package index generator (`gen_index.py`), package manager (`ru`), and related tooling are provided under the MIT License.

### Package Copyright

Each package in the index has full copyright information in its Debian source package. To view the copyright for an installed package:
```
ru copyright <package>
```

## Index Format

The index is split into section files for efficient lookup:

- `packages.json` — main index with `sections` listing and `pkg_section` mapping (package → section)
- `admin.json`, `devel.json`, `editors.json`, `interpreters.json`, `misc.json`, `net.json`, `shells.json`, `text.json`, `utils.json` — section-specific package lists

Each section file contains:
```json
{
  "generated": "ISO timestamp",
  "mirror": "Debian mirror URL",
  "suite": "unstable",
  "architecture": "amd64",
  "section": "editors",
  "packages": {
    "nano": {
      "version": "7.2-1",
      "filename": "pool/main/n/nano/nano_7.2-1_amd64.deb",
      "description": "small, friendly text editor",
      "url": "http://deb.debian.org/debian/pool/main/n/nano/nano_7.2-1_amd64.deb",
      ...
    }
  }
}
```

Generated for suite `unstable`, architecture `amd64`.

Last updated: see `packages.json` → `generated` field.
