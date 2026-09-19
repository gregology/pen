#!/bin/bash
# Settles one question on evidence: can Chromium's own sandbox run as a
# non-root user inside the agent container?
#
# Why it matters. Chromium aborts at zygote init as root without --no-sandbox,
# and it also aborts as non-root when it cannot use namespaces or a SUID
# helper. tools/browser therefore ships --no-sandbox, which means an unsandboxed
# renderer parses every page the agent visits. If the sandbox can be turned on
# by dropping the browser to a non-root uid, that is a real layer back — but it
# costs either a container-wide seccomp change or a second uid, and neither is
# worth designing before the answer is known.
#
# Run it inside the agent container, not on the host:
#
#   docker exec agent bash /tools/browser/sandbox-experiment.sh
#
# Debian's default is to permit unprivileged user namespaces, so a NEGATIVE
# result here is a Docker seccomp/kernel restriction, not a platform choice.
# Exit 0 = the sandbox works as a dropped user; 1 = it does not, and
# --no-sandbox stays.

set -u

PY=/opt/venvs/browser/bin/python3
pass=0
fail=0

report() {
    if [ "$2" = "yes" ]; then
        printf '  %-42s YES  %s\n' "$1" "$3"
        pass=$((pass + 1))
    else
        printf '  %-42s no   %s\n' "$1" "$3"
        fail=$((fail + 1))
    fi
}

echo "== environment =="
printf '  uid=%s  kernel=%s\n' "$(id -u)" "$(uname -r)"
printf '  userns sysctls: unprivileged_userns_clone=%s apparmor_restrict_unprivileged_userns=%s\n' \
    "$(cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null || echo n/a)" \
    "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null || echo n/a)"

echo
echo "== browser and helper =="
if [ ! -x "$PY" ]; then
    echo "  /opt/venvs/browser/bin/python3 is missing — is this the agent image?" >&2
    exit 1
fi
BROWSER="$("$PY" -c 'from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    print(p.chromium.executable_path)' 2>/dev/null)"
if [ -z "$BROWSER" ] || [ ! -x "$BROWSER" ]; then
    echo "  no browser at $BROWSER — the image was built without 'playwright install --only-shell chromium'" >&2
    exit 1
fi
printf '  browser: %s\n' "$BROWSER"
printf '  useradd: %s\n' "$(command -v useradd || echo MISSING)"
printf '  setpriv: %s\n' "$(command -v setpriv || echo MISSING)"

echo
echo "== can an unprivileged uid be created and dropped to? =="
if ! id browser >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin browser 2>/dev/null
fi
if id browser >/dev/null 2>&1; then
    report "uid 'browser' exists" yes "uid=$(id -u browser)"
else
    report "uid 'browser' exists" no "useradd unavailable; install the passwd package or add the user with a direct /etc/passwd edit"
fi

echo
echo "== namespace capabilities as the dropped user =="
as_browser() {
    setpriv --reuid=browser --regid=browser --clear-groups -- "$@" 2>&1
}
if as_browser unshare --user --map-root-user true >/dev/null 2>&1; then
    report "unshare --user as browser" yes "unprivileged user namespaces work"
else
    report "unshare --user as browser" no "$(as_browser unshare --user --map-root-user true | head -1)"
fi
if as_browser unshare --net true >/dev/null 2>&1; then
    report "unshare --net as browser" yes "network namespaces work"
else
    report "unshare --net as browser" no "$(as_browser unshare --net true | head -1)"
fi

echo
echo "== does Chromium start with its sandbox, as the dropped user? =="
D=$(mktemp -d)
chmod 777 "$D"
if as_browser "$BROWSER" --headless --dump-dom --user-data-dir="$D/profile" \
    'data:text/html,<h1>sandbox-probe</h1>' 2>"$D/err" | grep -q sandbox-probe; then
    report "chromium starts unprivileged, sandboxed" yes "the --no-sandbox flag is not required"
    SANDBOX_OK=yes
else
    reason="$(grep -oE 'No usable sandbox|SUID sandbox helper|not configured correctly|Operation not permitted' "$D/err" | head -1)"
    report "chromium starts unprivileged, sandboxed" no "${reason:-$(head -1 "$D/err" 2>/dev/null)}"
    SANDBOX_OK=no
fi
rm -rf "$D"

echo
if [ "$SANDBOX_OK" = yes ]; then
    cat <<'RESULT'
RESULT: the Chromium sandbox can be kept.
  The browser can run as a non-root uid with its sandbox intact, so
  tools/browser should drop privileges before launch instead of passing
  --no-sandbox. Record the change in DESIGN.md before making it: the seccomp
  profile has to permit the namespace syscalls Chromium's namespace sandbox
  uses, and that profile applies to the whole container.
RESULT
    exit 0
fi

cat <<'RESULT'
RESULT: the Chromium sandbox is not available here.
  Either the container's seccomp profile blocks the namespace syscalls, or the
  kernel/AppArmor refuses unprivileged user namespaces. Both are fixed by
  changing container or host policy, and neither is worth it for a renderer
  sandbox that guards a process already running as root in this namespace.
  The conclusion to record in DESIGN.md: tools/browser runs --no-sandbox
  deliberately, and the barrier around a hostile page is the network topology,
  not the browser's own sandbox.
RESULT
exit 1
