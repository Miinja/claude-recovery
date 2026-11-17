#!/usr/bin/env bash
# Builds the Ctrl-Z live image (Debian live-build).
#
#   sudo build/build-iso.sh business       # business: technicians, logs sent to a server
#   sudo build/build-iso.sh personal       # personal: everything stays on the key
#
# Run as root on a Debian machine (apt install live-build git). In practice the GitHub
# Actions workflow builds both editions on every vX.Y.Z tag and publishes them as a
# release (.github/workflows/release.yml).
#
# Result: build/out/ctrl-z-<edition>.iso (+ .sha256).
# The image embeds the repository as it is COMMITTED: commit before building.
set -euo pipefail

EDITION="${1:-${EDITION:-}}"
DIST="${DIST:-trixie}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
OUT="$HERE/out"

case "$EDITION" in
  business|personal) ;;
  *) echo "Usage: $0 <business|personal>" >&2; exit 1 ;;
esac
WORK="$HERE/work/$EDITION"

[ "$(id -u)" -eq 0 ] || { echo "Must be run as root (sudo)." >&2; exit 1; }
command -v lb  >/dev/null || { echo "live-build is missing: apt install live-build" >&2; exit 1; }
command -v git >/dev/null || { echo "git is missing: apt install git" >&2; exit 1; }
if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
  echo "WARNING: uncommitted changes will not be in the image." >&2
fi
VERSION="$(git -C "$ROOT" describe --tags --always)"

mkdir -p "$WORK" "$OUT"
cd "$WORK"
lb clean --purge >/dev/null 2>&1 || true

lb config \
  --distribution "$DIST" \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --archive-areas "main contrib non-free non-free-firmware" \
  --debian-installer none \
  --memtest memtest86+ \
  --iso-application "Ctrl-Z ($EDITION)" \
  --iso-volume "CTRL_Z" \
  --bootappend-live "boot=live components persistence persistence-encryption=none,luks username=recovery hostname=ctrl-z locales=fr_FR.UTF-8,en_US.UTF-8 keyboard-layouts=fr timezone=Europe/Paris quiet loglevel=3"

# Packages
grep -vE '^\s*(#|$)' "$HERE/packages.txt" > config/package-lists/recovery.list.chroot

# Embedded repository: `ctrlz-update` then does a git pull at every session
mkdir -p config/includes.chroot/opt/ctrl-z
rm -rf config/includes.chroot/opt/ctrl-z/repo
git clone --quiet "$ROOT" config/includes.chroot/opt/ctrl-z/repo
git -C config/includes.chroot/opt/ctrl-z/repo remote remove origin

# Edition and version of the image
mkdir -p config/includes.chroot/usr/share/ctrl-z
echo "$EDITION" > config/includes.chroot/usr/share/ctrl-z/edition
echo "$VERSION" > config/includes.chroot/usr/share/ctrl-z/version

# The edition's Claude configuration in the profile (copied from /etc/skel on first boot)
mkdir -p config/includes.chroot/etc/skel/.claude
# (English by default; `ctrlz` reinstalls the key's language at every session)
cp "$ROOT/config/$EDITION/CLAUDE.en.md" config/includes.chroot/etc/skel/.claude/CLAUDE.md
cp "$ROOT/config/$EDITION/settings.json" config/includes.chroot/etc/skel/.claude/

# Internal certificate authority (Caddy `tls internal`), when provided in build/ca/
if compgen -G "$HERE/ca/*.crt" >/dev/null; then
  mkdir -p config/includes.chroot/usr/local/share/ca-certificates
  cp "$HERE"/ca/*.crt config/includes.chroot/usr/local/share/ca-certificates/
fi

# Hook: installs Claude Code, the links and the update service
mkdir -p config/hooks/normal
install -m 755 "$HERE/hooks/"*.hook.chroot config/hooks/normal/

lb build

iso="$OUT/ctrl-z-$EDITION.iso"
mv ./*.iso "$iso"
( cd "$OUT" && sha256sum "ctrl-z-$EDITION.iso" > "ctrl-z-$EDITION.iso.sha256" )
echo "Image ready: $iso ($VERSION)"
