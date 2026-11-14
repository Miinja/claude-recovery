#!/usr/bin/env bash
# Construction de l'image live Claude Recovery (Debian live-build).
#
#   sudo build/build-iso.sh entreprise     # techniciens, Forgejo, journaux centralisés
#   sudo build/build-iso.sh particulier    # usage personnel, tout reste sur la clé
#
# À lancer en root sur une machine Debian (apt install live-build git). En pratique,
# c'est le workflow GitHub Actions qui construit les deux éditions à chaque tag vX.Y.Z
# et les publie en release (.github/workflows/release.yml).
#
# Résultat : build/out/claude-recovery-<édition>.iso (+ .sha256).
# L'image embarque le dépôt tel qu'il est COMMITÉ : commiter avant de construire.
set -euo pipefail

EDITION="${1:-${EDITION:-}}"
DIST="${DIST:-trixie}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
OUT="$HERE/out"

case "$EDITION" in
  entreprise|particulier) ;;
  *) echo "Usage : $0 <entreprise|particulier>" >&2; exit 1 ;;
esac
WORK="$HERE/work/$EDITION"

[ "$(id -u)" -eq 0 ] || { echo "À lancer en root (sudo)." >&2; exit 1; }
command -v lb  >/dev/null || { echo "live-build manquant : apt install live-build" >&2; exit 1; }
command -v git >/dev/null || { echo "git manquant : apt install git" >&2; exit 1; }
if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
  echo "ATTENTION : modifications non commitées, elles ne seront pas dans l'image." >&2
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
  --iso-application "Claude Recovery ($EDITION)" \
  --iso-volume "CLAUDE_RECOVERY" \
  --bootappend-live "boot=live components persistence persistence-encryption=none,luks username=ordi hostname=claude-recovery locales=fr_FR.UTF-8 keyboard-layouts=fr timezone=Europe/Paris"

# Paquets
grep -vE '^\s*(#|$)' "$HERE/packages.txt" > config/package-lists/recovery.list.chroot

# Dépôt embarqué : `ordi-update` fera ensuite un git pull à chaque session
mkdir -p config/includes.chroot/opt/ordi
rm -rf config/includes.chroot/opt/ordi/claude-recovery
git clone --quiet "$ROOT" config/includes.chroot/opt/ordi/claude-recovery
git -C config/includes.chroot/opt/ordi/claude-recovery remote remove origin

# Édition et version de l'image
mkdir -p config/includes.chroot/usr/share/ordi
echo "$EDITION" > config/includes.chroot/usr/share/ordi/edition
echo "$VERSION" > config/includes.chroot/usr/share/ordi/version

# Config Claude de l'édition dans le profil (repris de /etc/skel au premier démarrage)
mkdir -p config/includes.chroot/etc/skel/.claude
cp "$ROOT/config/$EDITION/CLAUDE.md" "$ROOT/config/$EDITION/settings.json" \
   config/includes.chroot/etc/skel/.claude/

# Autorité de certification interne (Caddy `tls internal`), si fournie dans build/ca/
if compgen -G "$HERE/ca/*.crt" >/dev/null; then
  mkdir -p config/includes.chroot/usr/local/share/ca-certificates
  cp "$HERE"/ca/*.crt config/includes.chroot/usr/local/share/ca-certificates/
fi

# Hook : installation de Claude Code, liens, service de mise à jour
mkdir -p config/hooks/normal
install -m 755 "$HERE/hooks/"*.hook.chroot config/hooks/normal/

lb build

iso="$OUT/claude-recovery-$EDITION.iso"
mv ./*.iso "$iso"
( cd "$OUT" && sha256sum "claude-recovery-$EDITION.iso" > "claude-recovery-$EDITION.iso.sha256" )
echo "Image prête : $iso ($VERSION)"
