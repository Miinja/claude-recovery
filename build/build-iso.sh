#!/usr/bin/env bash
# Construction de l'image live Claude Recovery (Debian live-build).
#
# À lancer en root sur une machine Debian (ou la VM Debian du serveur) :
#   sudo apt install live-build git
#   sudo build/build-iso.sh
#
# Résultat : build/out/claude-recovery-<date>.iso, à écrire sur une clé avec
# scripts/make-key.sh (qui crée aussi la partition de persistance).
#
# L'image embarque le dépôt tel qu'il est COMMITÉ (git clone) : commiter avant de construire.
set -euo pipefail

DIST="${DIST:-trixie}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
WORK="$HERE/work"
OUT="$HERE/out"

[ "$(id -u)" -eq 0 ] || { echo "À lancer en root (sudo)." >&2; exit 1; }
command -v lb  >/dev/null || { echo "live-build manquant : apt install live-build" >&2; exit 1; }
command -v git >/dev/null || { echo "git manquant : apt install git" >&2; exit 1; }
if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
  echo "ATTENTION : modifications non commitées, elles ne seront pas dans l'image." >&2
fi

mkdir -p "$WORK" "$OUT"
cd "$WORK"
lb clean --purge >/dev/null 2>&1 || true

lb config \
  --distribution "$DIST" \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --archive-areas "main contrib non-free non-free-firmware" \
  --debian-installer none \
  --iso-application "Claude Recovery" \
  --iso-volume "CLAUDE_RECOVERY" \
  --bootappend-live "boot=live components persistence persistence-encryption=none,luks username=ordi hostname=ordi-recovery locales=fr_FR.UTF-8 keyboard-layouts=fr timezone=Europe/Paris"

# Paquets
grep -vE '^\s*(#|$)' "$HERE/packages.txt" > config/package-lists/recovery.list.chroot

# Dépôt embarqué : `ordi-update` fera ensuite un git pull à chaque session
mkdir -p config/includes.chroot/opt/ordi
rm -rf config/includes.chroot/opt/ordi/claude-recovery
git clone --quiet "$ROOT" config/includes.chroot/opt/ordi/claude-recovery
git -C config/includes.chroot/opt/ordi/claude-recovery remote remove origin

# Config Claude dans le profil du technicien (repris de /etc/skel au premier démarrage)
mkdir -p config/includes.chroot/etc/skel/.claude
cp "$ROOT/config/CLAUDE.md" "$ROOT/config/settings.json" config/includes.chroot/etc/skel/.claude/

# Autorité de certification interne (Caddy `tls internal`), si fournie dans build/ca/
if compgen -G "$HERE/ca/*.crt" >/dev/null; then
  mkdir -p config/includes.chroot/usr/local/share/ca-certificates
  cp "$HERE"/ca/*.crt config/includes.chroot/usr/local/share/ca-certificates/
fi

# Hook : installation de Claude Code, liens, service de mise à jour
mkdir -p config/hooks/normal
install -m 755 "$HERE/hooks/"*.hook.chroot config/hooks/normal/

lb build

iso="$OUT/claude-recovery-$(date +%Y%m%d).iso"
mv ./*.iso "$iso"
sha256sum "$iso" > "$iso.sha256"
echo "Image prête : $iso"
