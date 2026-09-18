# Shared build helpers, sourced by every tools/<name>/install.sh.
# Not copied into the runtime image — see the COPY in the agent Dockerfile.

say() { printf '\n[tool] %s\n' "$*"; }

# Verify a tool by capturing its output and grepping the capture, never by
# piping into the tool's output. Two failure modes make the pipeline form
# unusable as a build gate, and both cost a full rebuild to discover:
#
#   1. An early-closing reader (`head`, or `grep -m1` which exits on its first
#      match) closes the pipe while the tool is still writing. The tool dies on
#      SIGPIPE, and `set -o pipefail` reports the build as failed even though
#      the expected line was printed and matched.
#   2. Several tools exit non-zero from their own --version/--help paths, so the
#      pipeline status reflects the tool rather than the match.
#
# Capturing first leaves the tool free to finish, and the grep's own status is
# then the only thing that decides the build. Usage:
#
#   verify_output 'Masscan version' masscan --version
verify_output() {
    local pattern="$1"; shift
    local out=/tmp/verify-output.txt
    "$@" > "$out" 2>&1 || true
    if ! grep -q -- "$pattern" "$out"; then
        echo "verify_output: '$pattern' not found in the output of: $*" >&2
        tail -20 "$out" >&2
        rm -f "$out"
        return 1
    fi
    rm -f "$out"
}

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
