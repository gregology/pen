# Shared build helpers, sourced by every tools/<name>/install.sh.
# Not copied into the runtime image — see the COPY in the agent Dockerfile.

say() { printf '\n[tool] %s\n' "$*"; }

apt_install() {
    apt-get update
    apt-get install -y --no-install-recommends "$@"
    rm -rf /var/lib/apt/lists/*
}

fetch() {
    local url="$1" sha="$2" out="$3"
    curl -fsSL -o "$out" "$url"
    echo "$sha  $out" | sha256sum -c -
}

unpack() {
    local archive="$1" dest="$2"
    rm -rf "$dest"
    mkdir -p "$dest"
    case "$archive" in
        *.zip)    unzip -q "$archive" -d "$dest" ;;
        *.tar.gz|*.tgz) tar -xzf "$archive" -C "$dest" ;;
        *.tar.xz) tar -xJf "$archive" -C "$dest" ;;
        *.tar.bz2) tar -xjf "$archive" -C "$dest" ;;
        *.deb)    dpkg-deb -x "$archive" "$dest" ;;
        *)        echo "unpack: unknown archive type: $archive" >&2; return 1 ;;
    esac
}

# Place each named file on PATH, wherever it sits in the unpacked tree.
# Every named file must exist exactly once — a silent miss would install a
# tool that cannot run.
install_bins() {
    local root="$1"; shift
    local name found
    for name in "$@"; do
        found="$(find "$root" -type f -name "$name" -print -quit)"
        if [ -z "$found" ]; then
            echo "install_bins: $name not found under $root" >&2
            return 1
        fi
        install -m 0755 "$found" "/usr/local/bin/$name"
    done
}

# Expose a virtualenv's console scripts on PATH. Symlinking the scripts is
# what keeps a tool usable without activating anything: each script's
# shebang is an absolute path into its own venv, so the tool always runs
# under the interpreter its packages were resolved for.
#
# Names after the venv are left unlinked. A Python distribution can ship a
# console script that collides with a different tool's binary — the httpx
# HTTP client against ProjectDiscovery's httpx is the known case, and the
# loser is whichever gets linked last. The intended owner is always declared
# here, never decided by install order.
expose_venv() {
    local venv="$1"; shift
    local skip="$*"
    "$venv/bin/python3" -m pip check
    local script name
    for script in "$venv"/bin/*; do
        name="$(basename "$script")"
        case "$name" in
            python*|pip*|activate*|Activate.ps1) continue ;;
        esac
        case " $skip " in
            *" $name "*) say "expose_venv: leaving $name to its intended owner"; continue ;;
        esac
        ln -sf "$script" /usr/local/bin/
    done
}
