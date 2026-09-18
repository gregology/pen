#!/bin/bash
# tools/metasploit/install.sh — install and verification for metasploit-framework.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

# The omnibus .deb carries its own Ruby, so "lucid" in the repo stanza is a
# legacy label, not a distro requirement. The pin keeps an unrelated
# metasploit* package from ever winning a version comparison.
apt_install curl gnupg
curl -fsSL https://apt.metasploit.com/metasploit-framework.gpg.key \
    | gpg --dearmor -o /usr/share/keyrings/metasploit-framework.gpg
echo "deb [signed-by=/usr/share/keyrings/metasploit-framework.gpg] https://apt.metasploit.com/ lucid main" \
    > /etc/apt/sources.list.d/metasploit-framework.list
printf 'Package: metasploit*\nPin: origin apt.metasploit.com\nPin-Priority: 1000\n' \
    > /etc/apt/preferences.d/pin-metasploit.pref

apt-get update
apt-get install -y --no-install-recommends --allow-downgrades metasploit-framework
rm -rf /var/lib/apt/lists/*

# msfconsole is the entry point; the image pins the package, not a version,
# because upstream publishes only a rolling apt repository.
msfconsole --version
