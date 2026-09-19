#!/bin/bash
# tools/browser/install.sh — version pin, install, and verification for browser.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

PLAYWRIGHT_VERSION=1.63.0
BROWSER_VENV=/opt/venvs/browser

# Chromium's shared libraries. Installed by this script rather than taken
# from `playwright install-deps` so the package list is explicit and owned
# here: the 21 packages below are exactly what install-deps resolves for
# debian12-x64, and an upstream change to that list should be a visible edit
# in this repository, not a silent difference in a rebuilt image.
apt_install \
    libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 libcairo2 \
    libcups2 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0 libnspr4 libnss3 \
    libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 \
    libxfixes3 libxkbcommon0 libxrandr2 \
    fonts-liberation

# passwd supplies useradd/setpriv, which sandbox-experiment.sh uses to test
# whether Chromium's own sandbox can run under a dropped uid. Installed here
# because this tool owns that question; the slim base does not carry it.
apt_install passwd

python3 -m venv "$BROWSER_VENV"
"$BROWSER_VENV/bin/pip" install --no-cache-dir --upgrade pip
"$BROWSER_VENV/bin/pip" install --no-cache-dir "playwright==${PLAYWRIGHT_VERSION}"

# The browser binary is baked at build time, not downloaded on first use.
# A runtime download would be the only network dependency left in the
# toolchain, it would need the tunnel up to happen at all, and it would be
# lost on every container recreate because /root/.cache is not a volume.
#
# --only-shell installs chromium-headless-shell (114 MB) instead of the full
# browser (187 MB). Playwright uses the shell for headless launches when no
# channel is set, which is the only launch mode this image has.
#
# The path is under /opt, not $HOME: the tool's own documentation states it,
# and a browser whose location depends on the invoking user's home directory
# is a bug waiting for the first script that runs under a different uid.
PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
    "$BROWSER_VENV/bin/python3" -m playwright install --only-shell chromium

# The rod-based tools (katana, httpx, nuclei) each carry a "use my own
# browser" flag whose implementation is go-rod's launcher.LookPath(), and
# LookPath only searches PATH and a fixed list for a binary named `chromium`.
# Without this link each of them either downloads a second copy of Chromium
# at runtime or fails with "the chrome browser is not installed". A symlink is
# enough: the headless shell accepts a --remote-debugging-port launch and
# speaks CDP like any Chromium, verified by pointing a browser launch at it and
# reading /json/version back.
#
# /usr/local/bin comes before /usr/bin in LookPath's search, and this image
# installs no distro chromium, so there is exactly one candidate.
BROWSER_BIN="$(find /opt/ms-playwright -type f -name 'chrome-headless-shell' -print -quit)"
test -n "$BROWSER_BIN"
ln -sf "$BROWSER_BIN" /usr/local/bin/chromium

chmod +x /opt/browser/browser
ln -sf /opt/browser/browser /usr/local/bin/browser

# Verify by rendering, not by asking for a version. The failure this replaces
# is silent: a browser that cannot launch makes every dependent tool report an
# empty result that reads exactly like "the target has nothing".
verify_output 'BROWSER-OK' browser run --timeout 60 <<'EOF'
open data:text/html,<h1 id=t>placeholder</h1><script>document.getElementById("t").textContent="BROWSER-OK"</script>
text #t
close
EOF

# The link the rod tools resolve through. If this is missing, katana -hl -sc
# and httpx -ss -system-chrome fail with "the chrome browser is not installed"
# only when someone first asks for a screenshot.
verify_output 'Chrome' chromium --version
