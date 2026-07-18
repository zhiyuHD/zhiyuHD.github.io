// ru — RusiumLinux Package Manager
// Compile: /tmp/cy_comp < ru.cy > ru.c
//          python3 cy_patch_main.py ru.c && gcc -static -Os -s -o /sbin/ru ru.c -lm
//
// Supports:
//   ru add <pkgname>          install from Debian index (wget + dpkg-deb)
//   ru add <file.deb>         install local .deb file
//   ru add <file.tar.gz>      install local tarball
//   ru del <pkgname>          remove installed package
//   ru list                   list installed packages
//   ru info <pkgname>         show package info from index
//   ru search <pattern>       search index
//   ru copyright <pkgname>    show package copyright
//   ru update-index           refresh cached index

use <stdio.h>;
use <stdlib.h>;
use <string.h>;
use <unistd.h>;
use <sys/stat.h>;

// Index URL on GitHub Pages
let INDEX_BASE: *char = "https://zhiyuhd.github.io/RusiumLinux/unstable";

fn die(msg: *char) {
    printf("ru: fatal: %s\n", msg);
    exit(1);
}

fn run(cmd: *char) -> i32 {
    printf("  %s\n", cmd);
    return system(cmd);
}

fn run_quiet(cmd: *char) -> i32 {
    return system(cmd);
}

fn run_or_die(cmd: *char) {
    if run(cmd) != 0 { die(cmd); }
}

fn ensure_dir(path: *char) {
    c {
        struct stat _st;
        if (stat(path, &_st) != 0) {
            mkdir(path, 0755);
        }
    }
}

fn str_endswith(s: *char, suffix: *char) -> i32 {
    c {
        size_t slen = strlen(s);
        size_t suflen = strlen(suffix);
        if (slen < suflen) return 0;
        return strcmp(s + slen - suflen, suffix) == 0;
    }
    return 0;
}

fn basename_from_path(path: *char) -> *char {
    c {
        char *_buf = strdup(path);
        if (!_buf) return path;
        char *base = strrchr(_buf, '/');
        if (!base) { free(_buf); return (char*)path; }
        base++;
        char *dot = strstr(base, ".tar.gz");
        if (dot) { *dot = '\0'; return _buf; }
        dot = strstr(base, ".tgz");
        if (dot) { *dot = '\0'; return _buf; }
        dot = strstr(base, ".tar");
        if (dot) { *dot = '\0'; return _buf; }
        dot = strstr(base, ".deb");
        if (dot) { *dot = '\0'; return _buf; }
        return _buf;
    }
    return path;
}

// ========== Install from local file (tar.gz or .deb) ==========

fn install_tar(path: *char, name: *char) -> i32 {
    c {
        char _db[512], _cmd[1024];

        ensure_dir("/var/ru");
        ensure_dir("/var/ru/db");

        snprintf(_db, sizeof(_db), "/var/ru/db/%s", name);

        // Create package db directory
        mkdir(_db, 0755);

        // Extract package to /
        snprintf(_cmd, sizeof(_cmd), "tar xzf %s -C /", path);
        if (system(_cmd) != 0) {
            printf("ru: failed to extract package\n");
            snprintf(_cmd, sizeof(_cmd), "rm -rf %s", _db);
            system(_cmd);
            return 1;
        }

        // Record installed files
        snprintf(_cmd, sizeof(_cmd), "tar tzf %s > %s/files", path, _db);
        system(_cmd);

        printf("ru: installed '%s' from tarball\n", name);
    }
    return 0;
}

fn install_deb_file(path: *char) -> i32 {
    c {
        // Extract the real package name from the .deb control metadata
        char _realname[256], _cmd[1024], _db[512];

        ensure_dir("/var/ru");
        ensure_dir("/var/ru/db");

        // Get package name from deb control
        snprintf(_cmd, sizeof(_cmd), "dpkg-deb -f %s | grep '^Package' | cut -d' ' -f2", path);
        FILE *_f = popen(_cmd, "r");
        if (!_f) { printf("ru: cannot read deb info\n"); return 1; }
        if (!fgets(_realname, sizeof(_realname), _f)) {
            pclose(_f); printf("ru: invalid deb package\n"); return 1;
        }
        pclose(_f);
        // Strip trailing newline
        size_t _nl = strlen(_realname);
        while (_nl > 0 && (_realname[_nl-1] == '\n' || _realname[_nl-1] == '\r'))
            _realname[--_nl] = '\0';
        if (strlen(_realname) == 0) { printf("ru: empty package name\n"); return 1; }

        snprintf(_db, sizeof(_db), "/var/ru/db/%s", _realname);

        // Check if already installed
        struct stat _st;
        if (stat(_db, &_st) == 0) {
            printf("ru: package '%s' already installed\n", _realname);
            return 1;
        }

        // Create package db directory
        mkdir(_db, 0755);

        // Extract files to /
        snprintf(_cmd, sizeof(_cmd), "dpkg-deb -x %s /", path);
        if (system(_cmd) != 0) {
            printf("ru: failed to extract deb\n");
            snprintf(_cmd, sizeof(_cmd), "rm -rf %s", _db);
            system(_cmd);
            return 1;
        }

        // Record file list (extract just the path column from dpkg-deb -c)
        snprintf(_cmd, sizeof(_cmd), "dpkg-deb -c %s | awk '{print $NF}' > %s/files", path, _db);
        system(_cmd);

        // Extract control info (copyright, etc.)
        snprintf(_cmd, sizeof(_cmd), "dpkg-deb -e %s /tmp/debctrl", path);
        system(_cmd);

        // Save control info
        snprintf(_cmd, sizeof(_cmd), "cp -r /tmp/debctrl %s/control 2>/dev/null", _db);
        system(_cmd);

        // Try to save copyright from extracted files
        snprintf(_cmd, sizeof(_cmd), "ls /usr/share/doc/%s/copyright 2>/dev/null", _realname);
        if (system(_cmd) == 0) {
            snprintf(_cmd, sizeof(_cmd), "cp /usr/share/doc/%s/copyright %s/copyright", _realname, _db);
            system(_cmd);
        } else {
            snprintf(_cmd, sizeof(_cmd), "find /usr/share/doc/%s -name 'copyright' 2>/dev/null | head -1 | xargs -r cp -t %s/ 2>/dev/null", _realname, _db);
            system(_cmd);
        }

        // Cleanup temp
        system("rm -rf /tmp/debctrl");

        // Save Debian attribution
        snprintf(_cmd, sizeof(_cmd), "echo 'Package from Debian GNU/Linux (unstable).' > %s/attribution", _db);
        system(_cmd);
        snprintf(_cmd, sizeof(_cmd), "echo 'See https://www.debian.org/' >> %s/attribution", _db);
        system(_cmd);

        printf("ru: installed '%s' from .deb (Debian)\n", _realname);
    }
    return 0;
}

// ========== Index operations ==========

fn update_index() -> i32 {
    c {
        char _cmd[1024];
        ensure_dir("/var/ru/cache");

        printf("ru: fetching package index...\n");

        snprintf(_cmd, sizeof(_cmd), "wget -q -O /var/ru/cache/packages.txt '%s/packages.txt'", INDEX_BASE);
        if (system(_cmd) != 0) {
            printf("ru: failed to fetch index from GitHub Pages\n");
            printf("  Check network: is the interface up? (udhcpc -i eth0)\n");
            return 1;
        }

        // Count entries
        snprintf(_cmd, sizeof(_cmd), "wc -l < /var/ru/cache/packages.txt");
        FILE *_f = popen(_cmd, "r");
        if (_f) {
            char _count[64];
            if (fgets(_count, sizeof(_count), _f)) {
                printf("ru: index updated (%s packages)\n", _count);
            }
            pclose(_f);
        }
    }
    return 0;
}

fn lookup_in_index(name: *char, out_url: *char, out_section: *char,
                   out_version: *char, out_desc: *char) -> i32 {
    c {
        char _cmd[1024], _line[4096];
        FILE *_f;

        // First check if we have a cached index
        struct stat _st;
        const char *index_file = "/var/ru/cache/packages.txt";
        if (stat(index_file, &_st) != 0) {
            printf("ru: index not found, run 'ru update-index' first\n");
            return 1;
        }

        // Search for package
        snprintf(_cmd, sizeof(_cmd), "grep '^%s|' %s", name, index_file);
        _f = popen(_cmd, "r");
        if (!_f) return 1;

        if (!fgets(_line, sizeof(_line), _f)) {
            pclose(_f);
            printf("ru: package '%s' not found in index\n", name);
            printf("  Try: ru update-index (if cache is stale)\n");
            printf("  Try: ru search '%s' (fuzzy search)\n", name);
            return 1;
        }
        pclose(_f);

        // Parse: pkgname|section|version|url|description
        char *p = _line;
        char *tok;

        // Skip pkgname (first field)
        tok = strchr(p, '|');
        if (!tok) return 1;
        *tok = '\0';
        p = tok + 1;

        // section
        tok = strchr(p, '|');
        if (!tok) return 1;
        *tok = '\0';
        if (out_section) strcpy(out_section, p);
        p = tok + 1;

        // version
        tok = strchr(p, '|');
        if (!tok) return 1;
        *tok = '\0';
        if (out_version) strcpy(out_version, p);
        p = tok + 1;

        // url
        tok = strchr(p, '|');
        if (!tok) return 1;
        *tok = '\0';
        if (out_url) strcpy(out_url, p);
        p = tok + 1;

        // description (rest of line)
        if (out_desc) strcpy(out_desc, p);
        // Strip trailing newline
        size_t _len = strlen(out_desc);
        while (_len > 0 && (out_desc[_len-1] == '\n' || out_desc[_len-1] == '\r'))
            out_desc[--_len] = '\0';
    }
    return 0;
}

// ========== Subcommands ==========

// Install from Debian index by package name
fn ru_add(name: *char) -> i32 {
    c {
        char _url[2048], _deb[512], _cmd[1024], _section[64], _version[128], _desc[256];

        // Look up package in index
        if (lookup_in_index(name, _url, _section, _version, _desc) != 0) {
            return 1;
        }

        // Check if already installed
        snprintf(_deb, sizeof(_deb), "/var/ru/db/%s", name);
        struct stat _st;
        if (stat(_deb, &_st) == 0) {
            printf("ru: package '%s' already installed\n", name);
            return 1;
        }

        printf("ru: found %s %s (%s)\n", name, _version, _section);
        printf("  %s\n", _desc);
        printf("  Downloading...\n");

        // Download .deb
        snprintf(_cmd, sizeof(_cmd), "wget -q -O /tmp/ru_pkg.deb '%s'", _url);
        if (system(_cmd) != 0) {
            printf("ru: download failed\n");
            return 1;
        }

        // Check download size
        snprintf(_cmd, sizeof(_cmd), "ls -l /tmp/ru_pkg.deb | awk '{print $5}'");
        FILE *_f = popen(_cmd, "r");
        char _size[32];
        if (_f && fgets(_size, sizeof(_size), _f)) {
            printf("  Downloaded %s bytes\n", _size);
            pclose(_f);
        }

        // Install
        printf("  Installing...\n");
        return install_deb_file("/tmp/ru_pkg.deb");
    }
    return 0;
}

// Install from local file (auto-detect type)
fn ru_add_file(path: *char) -> i32 {
    c {
        char *_name = basename_from_path(path);
        if (!_name || strlen(_name) == 0) {
            printf("ru: invalid package name from '%s'\n", path);
            return 1;
        }

        // Check if already installed
        char _db[512];
        snprintf(_db, sizeof(_db), "/var/ru/db/%s", _name);
        struct stat _st;
        if (stat(_db, &_st) == 0) {
            printf("ru: package '%s' already installed\n", _name);
            free(_name);
            return 1;
        }

        int ret;
        if (str_endswith(path, ".deb")) {
            ret = install_deb_file(path);
        } else {
            ret = install_tar(path, _name);
        }
        free(_name);
        return ret;
    }
    return 0;
}

fn ru_del(name: *char) -> i32 {
    c {
        char _files[512], _cmd[1024];
        snprintf(_files, sizeof(_files), "/var/ru/db/%s/files", name);

        FILE *f = fopen(_files, "r");
        if (!f) {
            printf("ru: package '%s' not found\n", name);
            return 1;
        }

        int count = 0;
        char _line[1024];
        while (fgets(_line, sizeof(_line), f)) {
            size_t len = strlen(_line);
            while (len > 0 && (_line[len-1] == '\n' || _line[len-1] == '\r'))
                _line[--len] = '\0';
            if (len == 0) continue;
            if (_line[len-1] == '/') continue;
            char *rp = _line;
            if (_line[0] == '.' && _line[1] == '/') rp = _line + 2;
            if (strlen(rp) == 0) continue;

            snprintf(_cmd, sizeof(_cmd), "/bin/rm -f /%s", rp);
            system(_cmd);
            count++;
        }
        fclose(f);

        snprintf(_files, sizeof(_files), "/var/ru/db/%s", name);
        snprintf(_cmd, sizeof(_cmd), "rm -rf %s", _files);
        system(_cmd);

        printf("ru: removed '%s' (%d files)\n", name, count);
    }
    return 0;
}

fn ru_list() -> i32 {
    c {
        struct stat _st;
        if (stat("/var/ru/db", &_st) != 0) {
            printf("ru: no packages installed\n");
            return 0;
        }
        printf("Installed packages:\n");
        system("ls /var/ru/db/");
    }
    return 0;
}

fn ru_info(name: *char) -> i32 {
    c {
        char _url[2048], _section[64], _version[128], _desc[256];

        if (lookup_in_index(name, _url, _section, _version, _desc) != 0) {
            return 1;
        }

        printf("Package: %s\n", name);
        printf("Version: %s\n", _version);
        printf("Section: %s\n", _section);
        printf("Description: %s\n", _desc);
        printf("URL: %s\n", _url);
        printf("Source: Debian GNU/Linux (unstable)\n");

        // Check if installed
        char _db[512];
        snprintf(_db, sizeof(_db), "/var/ru/db/%s", name);
        struct stat _st;
        if (stat(_db, &_st) == 0) {
            printf("Status: installed\n");
        } else {
            printf("Status: not installed\n");
        }
    }
    return 0;
}

fn ru_search(pattern: *char) -> i32 {
    c {
        char _cmd[1024];

        struct stat _st;
        if (stat("/var/ru/cache/packages.txt", &_st) != 0) {
            printf("ru: index not found, run 'ru update-index' first\n");
            return 1;
        }

        // Search: use case-insensitive grep on name and description
        snprintf(_cmd, sizeof(_cmd),
            "grep -i '%s' /var/ru/cache/packages.txt | "
            "awk -F'|' '{printf \"%%-20s %%s\\n\", $1, $5}' | head -30",
            pattern);

        printf("Search results for '%s':\n", pattern);
        printf("%-20s %s\n", "PACKAGE", "DESCRIPTION");
        printf("-------------------- ------------------------------------------------\n");

        FILE *_f = popen(_cmd, "r");
        if (_f) {
            char _line[1024];
            int _count = 0;
            while (fgets(_line, sizeof(_line), _f)) {
                printf("%s", _line);
                _count++;
            }
            pclose(_f);

            if (_count == 0) {
                printf("  (no matches)\n");
            } else {
                // Check if there are more results
                snprintf(_cmd, sizeof(_cmd),
                    "grep -i '%s' /var/ru/cache/packages.txt | wc -l", pattern);
                FILE *_fc = popen(_cmd, "r");
                if (_fc) {
                    char _c[32];
                    if (fgets(_c, sizeof(_c), _fc)) {
                        int total = atoi(_c);
                        if (total > 30) {
                            printf("  ... and %d more (use a more specific pattern)\n", total - 30);
                        }
                    }
                    pclose(_fc);
                }
            }
        }
    }
    return 0;
}

fn ru_copyright(name: *char) -> i32 {
    c {
        char _path[512], _line[4096];
        FILE *_f;

        // Try copyright file first
        snprintf(_path, sizeof(_path), "/var/ru/db/%s/copyright", name);
        _f = fopen(_path, "r");
        if (_f) {
            printf("Copyright for '%s':\n", name);
            printf("------------------------------------------------------------\n");
            while (fgets(_line, sizeof(_line), _f)) {
                printf("%s", _line);
            }
            fclose(_f);
            printf("------------------------------------------------------------\n");
            printf("Source: Debian GNU/Linux (unstable)\n");
            printf("See https://www.debian.org/ for Debian licensing information.\n");
            return 0;
        }

        // Try attribution
        snprintf(_path, sizeof(_path), "/var/ru/db/%s/attribution", name);
        _f = fopen(_path, "r");
        if (_f) {
            while (fgets(_line, sizeof(_line), _f)) {
                printf("%s", _line);
            }
            fclose(_f);
            return 0;
        }

        // Fallback: check if installed at all
        snprintf(_path, sizeof(_path), "/var/ru/db/%s", name);
        struct stat _st;
        if (stat(_path, &_st) != 0) {
            printf("ru: package '%s' is not installed\n", name);
            return 1;
        }

        printf("ru: no copyright file found for '%s'\n", name);
        printf("  Package from Debian GNU/Linux (unstable)\n");
        printf("  See Debian copyright policy: https://www.debian.org/doc/debian-policy/ch-docs.html\n");
    }
    return 0;
}

fn main() -> i32 {
    c { int _ac; char **_av; }
    c { _ac = argc; _av = argv; }

    if _ac < 2 {
        printf("Usage: ru <command> [args]\n");
        printf("\n");
        printf("Package management:\n");
        printf("  add <name>           install package from Debian index\n");
        printf("  add <file.deb>       install local .deb file\n");
        printf("  add <file.tar.gz>    install local tarball\n");
        printf("  del <name>           remove installed package\n");
        printf("  list                 list installed packages\n");
        printf("\n");
        printf("Index:\n");
        printf("  update-index         refresh package index from GitHub Pages\n");
        printf("  search <pattern>     search packages by name/description\n");
        printf("  info <name>          show package details from index\n");
        printf("  copyright <name>     show package copyright\n");
        printf("\n");
        printf("All packages sourced from Debian GNU/Linux (unstable).\n");
        printf("See https://www.debian.org/ for licensing information.\n");
        return 1;
    }

    var cmd: *char = _av[1];

    if strcmp(cmd, "add") == 0 {
        if _ac < 3 {
            printf("ru: missing argument\n");
            return 1;
        }
        // Auto-detect: if it looks like a file path (.deb, .tar.gz, /, .), treat as local file
        var arg: *char = _av[2];
        if str_endswith(arg, ".deb") || str_endswith(arg, ".tar.gz") ||
           str_endswith(arg, ".tgz") || arg[0] == '/' || arg[0] == '.' {
            return ru_add_file(arg);
        } else {
            return ru_add(arg);
        }
    } else if strcmp(cmd, "del") == 0 {
        if _ac < 3 {
            printf("ru: missing package name argument\n");
            return 1;
        }
        return ru_del(_av[2]);
    } else if strcmp(cmd, "list") == 0 {
        return ru_list();
    } else if strcmp(cmd, "info") == 0 {
        if _ac < 3 {
            printf("ru: missing package name argument\n");
            return 1;
        }
        return ru_info(_av[2]);
    } else if strcmp(cmd, "search") == 0 {
        if _ac < 3 {
            printf("ru: missing search pattern argument\n");
            return 1;
        }
        return ru_search(_av[2]);
    } else if strcmp(cmd, "copyright") == 0 {
        if _ac < 3 {
            printf("ru: missing package name argument\n");
            return 1;
        }
        return ru_copyright(_av[2]);
    } else if strcmp(cmd, "update-index") == 0 {
        return update_index();
    } else {
        printf("ru: unknown command: %s\n", cmd);
        printf("Try: ru add, ru del, ru list, ru info, ru search, ru copyright, ru update-index\n");
        return 1;
    }
}
